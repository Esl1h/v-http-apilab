// router owns the HTTP surface of the app.
//
// veb routes every request through seven method catch-alls
// ("/:path..."; get/post/put/patch/delete/options/head) into our own
// deterministic route table. Requests with any other method (TRACE,
// PROPFIND, ...) fall into the `not_found` override, which shares the
// same matching code, so every request that reaches the process gets a
// correct 405+Allow / 404 answer, a log line and a /lab/calls record.
//
// Only the seven route_* methods return veb.Result on App; every other
// method returns void or bool so it can never be picked up as a route
// by veb's compile-time route generation.
module router

import config
import logging
import net.http
import net.urllib
import requestid
import state
import strconv
import time
import veb

pub struct Context {
	veb.Context
pub mut:
	request_id string
mut:
	app_ref &App = unsafe { nil }
}

// Handler is the signature of every endpoint function.
pub type Handler = fn (mut app App, mut ctx Context, params []string) veb.Result

pub struct Route {
pub:
	method  http.Method
	pattern string
	words   []string
	handler Handler = unsafe { nil }
}

@[heap]
pub struct App {
	veb.Middleware[Context]
mut:
	routes []Route
	conf   config.Config
	st     &state.State    = unsafe { nil }
	log    &logging.Logger = unsafe { nil }
}

// setup wires the shared config, state and logger. Called once from main
// before the server starts.
pub fn (mut app App) setup(conf config.Config, st &state.State, log &logging.Logger) {
	app.conf = conf
	app.st = st
	app.log = log
}

// register adds an endpoint to the route table.
pub fn (mut app App) register(method http.Method, pattern string, handler Handler) {
	app.routes << Route{
		method:  method
		pattern: pattern
		words:   pattern.split('/').filter(it != '')
		handler: handler
	}
}

// cfg returns the startup configuration snapshot.
pub fn (app &App) cfg() config.Config {
	return app.conf
}

// store returns the shared mutable state.
pub fn (app &App) store() &state.State {
	return app.st
}

// request_middleware runs before routing for every request. It links the
// per-request context back to the shared app (so `not_found` can reach
// the route table and the state) and resolves the request id.
pub fn (app &App) request_middleware(mut ctx Context) bool {
	ctx.app_ref = app
	ctx.request_id = requestid.resolve(ctx.get_custom_header(requestid.header_name) or { '' })
	ctx.set_custom_header(requestid.header_name, ctx.request_id) or {}
	return true
}

// match_words matches url path words against a route pattern, capturing
// ":param" segments in order.
fn match_words(url_words []string, route_words []string) ?[]string {
	if url_words.len != route_words.len {
		return none
	}
	mut params := []string{cap: route_words.len}
	for i, rw in route_words {
		if rw.len > 1 && rw[0] == `:` {
			params << url_words[i]
		} else if rw != url_words[i] {
			return none
		}
	}
	return params
}

// normalized_words returns the decoded, normalized path words of a raw
// request URL (the same decoding veb applies when it routes the request,
// so unmatched requests are compared against the same path the dispatch
// layer saw).
fn normalized_words(raw_url string) []string {
	url := urllib.parse_request_uri(raw_url) or {
		return raw_url.all_before('?').split('/').filter(it != '')
	}
	return url.path.split('/').filter(it != '')
}

// allowed_methods_for returns the methods any registered route accepts
// for the given path words, used for the 405 Allow header.
fn (app &App) allowed_methods_for(url_words []string) []http.Method {
	mut methods := []http.Method{}
	for r in app.routes {
		if _ := match_words(url_words, r.words) {
			if r.method !in methods {
				methods << r.method
			}
		}
	}
	return methods
}

// dispatch enforces the global body limit and routes one request.
fn (mut app App) dispatch(mut ctx Context, path string) {
	if i64(ctx.req.data.len) > app.conf.max_body_bytes {
		// respond first so finalize records the final status code
		ctx.respond_error(.request_entity_too_large, 'payload_too_large',
			'request body of ${ctx.req.data.len} bytes exceeds MAX_BODY_BYTES=${app.conf.max_body_bytes}')
		app.finalize(mut ctx, 'body_too_large')
		return
	}
	url_words := path.split('/').filter(it != '')
	for r in app.routes {
		if r.method == ctx.req.method {
			if params := match_words(url_words, r.words) {
				res := r.handler(mut app, mut ctx, params)
				_ = res
				app.finalize(mut ctx, r.pattern)
				return
			}
		}
	}
	app.handle_unmatched(mut ctx)
}

// handle_unmatched answers 405 with an Allow header when the path exists
// under another method, and a JSON 404 otherwise. It normalizes the URL
// exactly like the dispatch layer, so Allow answers refer to the same
// path the route table saw.
pub fn (mut app App) handle_unmatched(mut ctx Context) {
	url_words := normalized_words(ctx.req.url)
	path := '/' + url_words.join('/')
	methods := app.allowed_methods_for(url_words)
	if methods.len > 0 {
		allow := methods.map(it.str()).join(', ')
		ctx.set_header(.allow, allow)
		ctx.respond_error(.method_not_allowed, 'method_not_allowed',
			'method ${ctx.req.method.str()} is not allowed for ${path}; allow: ${allow}')
		app.finalize(mut ctx, 'unmatched')
		return
	}
	ctx.respond_error(.not_found, 'not_found', 'no route for ${path}')
	app.finalize(mut ctx, 'unmatched')
}

// finalize records metrics, the /lab/calls ring entry and the single
// structured log line for the request.
fn (mut app App) finalize(mut ctx Context, route string) {
	status := ctx.res.status_code
	if app.st == unsafe { nil } {
		return
	}
	path := ctx.req.url.all_before('?')
	app.st.record_metric(route, status)
	app.st.record_call(ctx.request_id, ctx.get_custom_header('X-Test-Case') or { '' },
		ctx.req.method.str(), path, route, status)
	entry := logging.LogEntry{
		timestamp:       time.now().format_rfc3339()
		level:           'info'
		msg:             'request'
		request_id:      ctx.request_id
		method:          ctx.req.method.str()
		path:            path
		query:           logging.mask_query(raw_query(ctx.req.url))
		status:          status
		duration_ms:     ctx.time_to_render()
		route:           route
		remote_addr:     ctx.ip()
		user_agent:      ctx.user_agent()
		content_length:  content_length_of(ctx)
		content_type:    ctx.req.header.get(.content_type) or { '' }
		x_forwarded_for: ctx.req.header.get(.x_forwarded_for) or { '' }
		x_test_case:     ctx.get_custom_header('X-Test-Case') or { '' }
	}
	app.log.write_request_line(entry)
}

fn raw_query(url string) string {
	idx := url.index('?') or { return '' }
	if idx + 1 < url.len {
		return url[idx + 1..]
	}
	return ''
}

fn content_length_of(ctx &Context) i64 {
	header := ctx.req.header.get(.content_length) or { return 0 }
	return strconv.parse_int(header, 10, 64) or { 0 }
}

// route_*: the seven veb catch-alls, one per HTTP method of the surface.
@['/:path...'; get]
pub fn (mut app App) route_get(mut ctx Context, path string) veb.Result {
	app.dispatch(mut ctx, path)
	return veb.no_result()
}

@['/:path...'; post]
pub fn (mut app App) route_post(mut ctx Context, path string) veb.Result {
	app.dispatch(mut ctx, path)
	return veb.no_result()
}

@['/:path...'; put]
pub fn (mut app App) route_put(mut ctx Context, path string) veb.Result {
	app.dispatch(mut ctx, path)
	return veb.no_result()
}

@['/:path...'; patch]
pub fn (mut app App) route_patch(mut ctx Context, path string) veb.Result {
	app.dispatch(mut ctx, path)
	return veb.no_result()
}

@['/:path...'; delete]
pub fn (mut app App) route_delete(mut ctx Context, path string) veb.Result {
	app.dispatch(mut ctx, path)
	return veb.no_result()
}

@['/:path...'; options]
pub fn (mut app App) route_options(mut ctx Context, path string) veb.Result {
	app.dispatch(mut ctx, path)
	return veb.no_result()
}

@['/:path...'; head]
pub fn (mut app App) route_head(mut ctx Context, path string) veb.Result {
	app.dispatch(mut ctx, path)
	return veb.no_result()
}

// not_found is the veb fallback for every method without a catch-all
// (TRACE, PROPFIND, ...). It shares the 405/404 logic with dispatch so
// exotic methods also receive a correct answer and get recorded.
pub fn (mut ctx Context) not_found() veb.Result {
	mut app := ctx.app_ref
	if app == unsafe { nil } {
		ctx.res.set_status(.not_found)
		return ctx.text('404 Not Found')
	}
	app.handle_unmatched(mut ctx)
	return veb.no_result()
}
