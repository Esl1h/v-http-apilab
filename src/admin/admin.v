// admin: simulated administration endpoints.
//
// Nothing here changes real state: /admin/config only validates and
// echoes the payload back (JSON-escaped), and /admin/status plus
// /internal/debug expose only non-sensitive operational counters.
module admin

import json2
import router
import seed
import veb

pub struct AdminStatus {
pub:
	mode           string @[json: 'mode']
	uptime_seconds i64    @[json: 'uptime_seconds']
	requests_total i64    @[json: 'requests_total']
	users          int    @[json: 'users']
	tickets        int    @[json: 'tickets']
	sessions       int    @[json: 'sessions']
	export_jobs    int    @[json: 'export_jobs']
}

// status reports non-sensitive operational counters.
pub fn status(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	mut st := app.store()
	return ctx.respond_json(.ok, AdminStatus{
		mode:           'lab'
		uptime_seconds: st.uptime_seconds()
		requests_total: st.requests_total()
		users:          st.users_count()
		tickets:        st.tickets_all().len
		sessions:       st.sessions_count()
		export_jobs:    st.jobs_count()
	})
}

pub struct AdminConfigResponse {
pub:
	valid      bool                 @[json: 'valid']
	applied    bool                 @[json: 'applied']
	received   map[string]json2.Any @[json: 'received']
	note       string               @[json: 'note']
	request_id string               @[json: 'request_id']
}

// config validates a JSON object and echoes it back; lab mode never
// applies configuration.
pub fn config(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	if !ctx.require_json() {
		return veb.no_result()
	}
	parsed := ctx.parse_body[json2.Any]() or {
		return ctx.respond_error(.bad_request, 'invalid_json', 'request body is not valid JSON: ${err}')
	}
	if parsed !is map[string]json2.Any {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'request body must be a JSON object of configuration keys')
	}
	obj := parsed as map[string]json2.Any
	return ctx.respond_json(.ok, AdminConfigResponse{
		valid:      true
		applied:    false
		received:   obj
		note:       'lab mode: configuration is validated and echoed, never applied'
		request_id: ctx.request_id
	})
}

pub struct DebugBody {
pub:
	app            string   @[json: 'app']
	version        string   @[json: 'version']
	v_version      string   @[json: 'v_version']
	build_date     string   @[json: 'build_date']
	started_at     string   @[json: 'started_at']
	uptime_seconds i64      @[json: 'uptime_seconds']
	counters       Counters @[json: 'counters']
}

pub struct Counters {
pub:
	requests_total i64 @[json: 'requests_total']
	users          int @[json: 'users']
	tickets        int @[json: 'tickets']
	sessions       int @[json: 'sessions']
	export_jobs    int @[json: 'export_jobs']
	calls_buffered int @[json: 'calls_buffered']
}

// debug exposes only non-sensitive runtime information.
pub fn debug(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	mut st := app.store()
	return ctx.respond_json(.ok, DebugBody{
		app:            seed.app_name
		version:        seed.app_version
		v_version:      seed.v_version
		build_date:     @BUILD_DATE
		started_at:     st.started_at()
		uptime_seconds: st.uptime_seconds()
		counters:       Counters{
			requests_total: st.requests_total()
			users:          st.users_count()
			tickets:        st.tickets_all().len
			sessions:       st.sessions_count()
			export_jobs:    st.jobs_count()
			calls_buffered: st.calls_all().len
		}
	})
}
