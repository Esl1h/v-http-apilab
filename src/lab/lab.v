// lab: integration testing utilities.
//
// These endpoints exist to make proxy behavior observable and
// provable: /lab/calls is the evidence buffer that shows which requests
// actually reached the backend.
module lab

import auth
import crypto.sha256
import crypto.subtle
import json2
import net.http
import router
import seed
import state
import strconv
import time
import veb

// echo_allowed_headers is the allowlist reflected by /lab/echo.
// Authorization and Cookie are deliberately absent.
pub const echo_allowed_headers = [
	'Host',
	'User-Agent',
	'Accept',
	'Accept-Encoding',
	'Accept-Language',
	'Content-Type',
	'Content-Length',
	'X-Request-ID',
	'X-Test-Case',
	'X-Forwarded-For',
	'X-Forwarded-Proto',
]

pub const method_allowed = ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']

pub struct EchoBody {
pub:
	method      string            @[json: 'method']
	path        string            @[json: 'path']
	query       string            @[json: 'query']
	headers     map[string]string @[json: 'headers']
	body_bytes  int               @[json: 'body_bytes']
	body_sha256 string            @[json: 'body_sha256']
	request_id  string            @[json: 'request_id']
}

// echo reflects the method, path, raw query, allowed headers and a body
// hash. It never reflects Authorization, Cookie or the body itself.
pub fn echo(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	url := ctx.req.url
	mut reflected := map[string]string{}
	for h in echo_allowed_headers {
		reflected[h] = ctx.get_custom_header(h) or { '' }
	}
	return ctx.respond_json(.ok, EchoBody{
		method:      ctx.req.method.str()
		path:        url.all_before('?')
		query:       if url.contains('?') { url.all_after('?') } else { '' }
		headers:     reflected
		body_bytes:  ctx.req.data.len
		body_sha256: sha256.sum256(ctx.req.data.bytes()).hex()
		request_id:  ctx.request_id
	})
}

pub struct MethodBody {
pub:
	method     string   @[json: 'method']
	received   bool     @[json: 'received']
	allowed    []string @[json: 'allowed']
	request_id string   @[json: 'request_id']
}

// method reports the HTTP method used to reach it. It is registered for
// GET, HEAD, POST, PUT, PATCH, DELETE and OPTIONS.
pub fn method(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	ctx.set_header(.allow, method_allowed.join(', '))
	if ctx.req.method == .head {
		// HEAD answers with headers only: set Content-Length to the size
		// the GET body would have and send no body.
		body := json2.encode(MethodBody{
			method:     'HEAD'
			received:   true
			allowed:    method_allowed.clone()
			request_id: ctx.request_id
		})
		ctx.set_header(.content_length, body.len.str())
		ctx.res.set_status(.ok)
		return ctx.text('')
	}
	return ctx.respond_json(.ok, MethodBody{
		method:     ctx.req.method.str()
		received:   true
		allowed:    method_allowed.clone()
		request_id: ctx.request_id
	})
}

pub struct SlowBody {
pub:
	slept_ms   int    @[json: 'slept_ms']
	max_ms     int    @[json: 'max_ms']
	request_id string @[json: 'request_id']
}

// slow sleeps the requested number of milliseconds (bounded by
// MAX_SLOW_MS) before answering.
pub fn slow(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	conf := app.cfg()
	ms := strconv.atoi(ctx.query['ms'] or { '0' }) or {
		return ctx.respond_error(.bad_request, 'invalid_query_value',
			'"ms" must be an integer, got "${ctx.query['ms'] or { '' }}"')
	}
	if ms < 0 || ms > conf.max_slow_ms {
		return ctx.respond_error(.bad_request, 'invalid_query_value',
			'"ms" must be between 0 and MAX_SLOW_MS=${conf.max_slow_ms}, got ${ms}')
	}
	time.sleep(ms * time.millisecond)
	return ctx.respond_json(.ok, SlowBody{
		slept_ms:   ms
		max_ms:     conf.max_slow_ms
		request_id: ctx.request_id
	})
}

pub struct StatusBody {
pub:
	requested_status int    @[json: 'requested_status']
	request_id       string @[json: 'request_id']
}

// status_code answers with the requested status code (200..599).
// 204, 205 and 304 are answered without a body.
pub fn status_code(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	code := strconv.atoi(params[0]) or {
		return ctx.respond_error(.bad_request, 'invalid_status_code',
			'status code must be an integer, got "${params[0]}"')
	}
	if code < 200 || code > 599 {
		return ctx.respond_error(.bad_request, 'invalid_status_code',
			'status code must be between 200 and 599, got ${code}')
	}
	set_raw_status(mut ctx, code)
	if code in [204, 205, 304] {
		// empty mimetype: no Content-Type header for a bodyless answer
		return ctx.send_response_to_client('', '')
	}
	return ctx.json(StatusBody{
		requested_status: code
		request_id:       ctx.request_id
	})
}

// set_raw_status sets any 2xx..5xx code on the response. set_status
// takes the http.Status enum, and codes it does not name (299, 499,
// 520...) map to .unassigned, which veb then sends as 200.
fn set_raw_status(mut ctx router.Context, code int) {
	status := http.status_from_int(code)
	if status == .unassigned {
		ctx.res.status_code = code
		ctx.res.status_msg = 'Unknown'
		return
	}
	ctx.res.set_status(status)
}

// response_marker serves the fixed marker body for response
// inspection tests.tests.
pub fn response_marker(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	ctx.set_custom_header('X-Lab-Marker', seed.response_marker) or {}
	return ctx.text('${seed.response_marker}\n')
}

// large answers a text/plain body of exactly `bytes` bytes
// (bounded by MAX_LARGE_BYTES).
pub fn large(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	conf := app.cfg()
	raw := ctx.query['bytes'] or { '0' }
	n := strconv.atoi(raw) or {
		return ctx.respond_error(.bad_request, 'invalid_query_value',
			'"bytes" must be an integer, got "${raw}"')
	}
	if n < 0 || i64(n) > conf.max_large_bytes {
		return ctx.respond_error(.bad_request, 'invalid_query_value',
			'"bytes" must be between 0 and MAX_LARGE_BYTES=${conf.max_large_bytes}, got ${n}')
	}
	return ctx.text('A'.repeat(n))
}

pub struct HeadersBody {
pub:
	headers_set []string @[json: 'headers_set']
	request_id  string   @[json: 'request_id']
}

// headers answers with a set of custom and security headers, to test
// proxy response inspection and header rewriting.
pub fn headers(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	ctx.set_header(.x_frame_options, 'DENY')
	ctx.set_header(.x_content_type_options, 'nosniff')
	ctx.set_header(.referrer_policy, 'no-referrer')
	ctx.set_header(.content_security_policy, "default-src 'none'; frame-ancestors 'none'")
	ctx.set_header(.strict_transport_security, 'max-age=31536000; includeSubDomains')
	ctx.set_custom_header('X-Permitted-Cross-Domain-Policies', 'none') or {}
	ctx.set_custom_header('X-Lab-Static-Header', 'set-by-lab') or {}
	return ctx.respond_json(.ok, HeadersBody{
		headers_set: [
			'X-Frame-Options',
			'X-Content-Type-Options',
			'Referrer-Policy',
			'Content-Security-Policy',
			'Strict-Transport-Security',
			'X-Permitted-Cross-Domain-Policies',
			'X-Lab-Static-Header',
		]
		request_id:  ctx.request_id
	})
}

// stream answers with a manual chunked-transfer response written over
// the raw connection (veb takeover mode). veb has no built-in response
// streaming API in this version, so the chunks are framed by hand; see
// README "Limitations" for details.
pub fn stream(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	ctx.res.set_status(.ok)
	ctx.takeover_conn()
	if ctx.conn == unsafe { nil } {
		return ctx.respond_error(.internal_server_error, 'stream_unavailable',
			'connection takeover is not available in this build')
	}
	conn := ctx.conn
	mut head := 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n'
	head += 'Transfer-Encoding: chunked\r\nX-Request-ID: ${ctx.request_id}\r\n'
	head += 'Connection: close\r\n\r\n'
	conn.write_string(head) or {}
	for i in 1 .. 6 {
		chunk := 'lab-stream-chunk-${i}-of-5\n'
		conn.write_string('${chunk.len:x}\r\n${chunk}\r\n') or {}
		time.sleep(100 * time.millisecond)
	}
	conn.write_string('0\r\n\r\n') or {}
	conn.close() or {}
	return veb.no_result()
}

pub struct CallsBody {
pub:
	count    int                @[json: 'count']
	capacity int                @[json: 'capacity']
	calls    []state.CallRecord @[json: 'calls']
}

// lab_authorized answers 404 (endpoints disabled), 401 (missing token)
// or 403 (wrong token) and returns false when the request must stop.
fn lab_authorized(mut app router.App, mut ctx router.Context) bool {
	conf := app.cfg()
	if conf.lab_admin_token == '' {
		ctx.respond_error(.not_found, 'lab_calls_disabled',
			'/lab/calls endpoints are disabled: LAB_ADMIN_TOKEN is not set')
		return false
	}
	token := ctx.get_custom_header('X-Lab-Token') or { auth.bearer_token(ctx) }
	if token == '' {
		ctx.respond_error(.unauthorized, 'unauthorized',
			'missing lab token: send header X-Lab-Token or Authorization: Bearer')
		return false
	}
	if subtle.constant_time_compare(token.bytes(), conf.lab_admin_token.bytes()) != 1 {
		ctx.respond_error(.forbidden, 'invalid_lab_token', 'invalid lab token')
		return false
	}
	return true
}

// calls lists the requests that reached the backend (chronological,
// oldest first), proving which requests passed the proxy.
pub fn calls(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	if !lab_authorized(mut app, mut ctx) {
		return veb.no_result()
	}
	mut st := app.store()
	return ctx.respond_json(.ok, CallsBody{
		count:    st.calls_all().len
		capacity: state.calls_capacity
		calls:    st.calls_all()
	})
}

pub struct CallsResetBody {
pub:
	reset      bool   @[json: 'reset']
	dropped    int    @[json: 'dropped']
	request_id string @[json: 'request_id']
}

// calls_reset clears the /lab/calls ring buffer.
pub fn calls_reset(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	if !lab_authorized(mut app, mut ctx) {
		return veb.no_result()
	}
	mut st := app.store()
	dropped := st.calls_reset()
	return ctx.respond_json(.ok, CallsResetBody{
		reset:      true
		dropped:    dropped
		request_id: ctx.request_id
	})
}
