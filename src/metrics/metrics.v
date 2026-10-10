// metrics: simple, honest Prometheus text exposition.
//
// Counters are in-memory request counts by route pattern and status
// code, gathered from the state module. No histogram, no process
// exporter: only what this app actually measures.
module metrics

import router
import seed
import strings
import veb

// prometheus renders the /metrics body in the Prometheus text format
// (version 0.0.4).
pub fn prometheus(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	mut st := app.store()
	mut sb := strings.new_builder(256)
	sb.write_string('# HELP v_http_lab_up Service liveness (1 = up).\n')
	sb.write_string('# TYPE v_http_lab_up gauge\n')
	sb.write_string('v_http_lab_up 1\n')
	sb.write_string('# HELP v_http_lab_uptime_seconds Seconds since process start.\n')
	sb.write_string('# TYPE v_http_lab_uptime_seconds gauge\n')
	sb.write_string('v_http_lab_uptime_seconds ${st.uptime_seconds()}\n')
	sb.write_string('# HELP v_http_lab_build_info Build information (constant 1).\n')
	sb.write_string('# TYPE v_http_lab_build_info gauge\n')
	sb.write_string('v_http_lab_build_info{app="${seed.app_name}",version="${seed.app_version}"} 1\n')
	sb.write_string('# HELP v_http_lab_requests_total Requests handled by route and status.\n')
	sb.write_string('# TYPE v_http_lab_requests_total counter\n')
	sb.write_string(st.metrics_counters_text())
	body := sb.str()
	ctx.set_header(.content_type, 'text/plain; version=0.0.4; charset=utf-8')
	return ctx.text(body)
}
