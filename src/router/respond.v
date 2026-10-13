// respond.v: response and request-parsing helpers (module router).
//
// Every error is JSON in the fixed shape:
// {"error":{"code":"...","message":"...","request_id":"..."}}
module router

import json2
import net.http
import veb

pub struct ErrorDetail {
pub:
	code       string @[json: 'code']
	message    string @[json: 'message']
	request_id string @[json: 'request_id']
}

pub struct ErrorEnvelope {
pub:
	err ErrorDetail @[json: 'error']
}

// respond_error sends a JSON error with the given HTTP status.
pub fn (mut ctx Context) respond_error(status http.Status, code string, message string) veb.Result {
	ctx.res.set_status(status)
	return ctx.json(ErrorEnvelope{
		err: ErrorDetail{
			code:       code
			message:    message
			request_id: ctx.request_id
		}
	})
}

// respond_json sends a JSON body with an explicit status code.
pub fn (mut ctx Context) respond_json[T](status http.Status, body T) veb.Result {
	ctx.res.set_status(status)
	return ctx.json(body)
}

// parse_body decodes the request body as JSON into T.
// Returns an error when the body is not valid JSON.
pub fn (ctx &Context) parse_body[T]() !T {
	return json2.decode[T](ctx.req.data) or { return error(json_error_text(err)) }
}

// json_error_text flattens a json2 error to one line: the default msg()
// is multi-line and carries terminal color escapes that would otherwise
// leak into API error messages.
fn json_error_text(err IError) string {
	if err is json2.JsonDecodeError {
		return '${err.message} at line ${err.line} column ${err.character}'
	}
	return err.msg()
}

// content_type returns the normalized request Content-Type
// (parameters such as charset stripped).
pub fn (ctx &Context) content_type() string {
	raw := ctx.req.header.get(.content_type) or { '' }
	return raw.all_before(';').trim_space().to_lower()
}

// content_type_is_json accepts application/json and any +json suffix.
pub fn (ctx &Context) content_type_is_json() bool {
	ct := ctx.content_type()
	if ct == 'application/json' {
		return true
	}
	return ct.ends_with('+json')
}

// require_json answers 415 and returns false when the request body is
// not declared as JSON. Used with `if !ctx.require_json() { return ... }`.
pub fn (mut ctx Context) require_json() bool {
	if ctx.content_type_is_json() {
		return true
	}
	provided := ctx.content_type()
	if provided == '' {
		ctx.respond_error(.unsupported_media_type, 'unsupported_media_type',
			'expected Content-Type application/json, got none')
	} else {
		ctx.respond_error(.unsupported_media_type, 'unsupported_media_type',
			'expected Content-Type application/json, got "${provided}"')
	}
	return false
}
