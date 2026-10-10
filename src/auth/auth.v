// auth: synthetic login/logout/me flow.
//
// This is NOT real authentication: credentials are fixed lab values and
// the token is an in-memory opaque string. The flow exists so tests
// lab can exercise Authorization headers, login bodies and 401/403
// paths. The password is never logged or echoed.
module auth

import crypto.subtle
import router
import veb

pub struct LoginRequest {
pub mut:
	username string @[json: 'username']
	password string @[json: 'password']
}

pub struct LoginResponse {
pub:
	token      string @[json: 'token']
	token_type string @[json: 'token_type']
	expires_in i64    @[json: 'expires_in']
	username   string @[json: 'username']
	request_id string @[json: 'request_id']
}

// bearer_token extracts the token from "Authorization: Bearer <token>".
pub fn bearer_token(ctx &router.Context) string {
	header := ctx.req.header.get(.authorization) or { return '' }
	if header.len < 8 {
		return ''
	}
	scheme := header[..7].to_lower()
	if scheme != 'bearer ' {
		return ''
	}
	return header[7..]
}

// login validates the fixed synthetic credentials and issues a token.
pub fn login(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	if !ctx.require_json() {
		return veb.no_result()
	}
	body := ctx.parse_body[LoginRequest]() or {
		return ctx.respond_error(.bad_request, 'invalid_json', 'request body is not valid JSON: ${err}')
	}
	if body.username == '' || body.password == '' {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'both "username" and "password" are required')
	}
	conf := app.cfg()
	user_ok := subtle.constant_time_compare(body.username.bytes(), conf.auth_username.bytes()) == 1
	pass_ok := subtle.constant_time_compare(body.password.bytes(), conf.auth_password.bytes()) == 1
	if !user_ok || !pass_ok {
		return ctx.respond_error(.unauthorized, 'invalid_credentials', 'invalid username or password')
	}
	mut st := app.store()
	token := st.session_create(body.username, conf.token_ttl_seconds)
	return ctx.respond_json(.ok, LoginResponse{
		token:      token
		token_type: 'Bearer'
		expires_in: conf.token_ttl_seconds
		username:   body.username
		request_id: ctx.request_id
	})
}

pub struct LogoutResponse {
pub:
	logged_out bool   @[json: 'logged_out']
	request_id string @[json: 'request_id']
}

// logout revokes the presented Bearer token.
pub fn logout(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	token := bearer_token(ctx)
	if token == '' {
		return ctx.respond_error(.unauthorized, 'unauthorized', 'missing Bearer token')
	}
	mut st := app.store()
	if _ := st.session_lookup(token) {
		st.session_delete(token)
		return ctx.respond_json(.ok, LogoutResponse{
			logged_out: true
			request_id: ctx.request_id
		})
	}
	return ctx.respond_error(.unauthorized, 'unauthorized', 'invalid or expired Bearer token')
}

pub struct MeBody {
pub:
	username     string @[json: 'username']
	display_name string @[json: 'display_name']
	role         string @[json: 'role']
	email        string @[json: 'email']
	request_id   string @[json: 'request_id']
}

// me echoes the synthetic profile bound to the Bearer token.
pub fn me(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	token := bearer_token(ctx)
	if token == '' {
		return ctx.respond_error(.unauthorized, 'unauthorized', 'missing Bearer token')
	}
	mut st := app.store()
	username := st.session_lookup(token) or {
		return ctx.respond_error(.unauthorized, 'unauthorized', 'invalid or expired Bearer token')
	}
	return ctx.respond_json(.ok, MeBody{
		username:     username
		display_name: 'Lab Administrator (synthetic)'
		role:         'admin'
		email:        'admin@lab.example'
		request_id:   ctx.request_id
	})
}
