// metrics.v: per-route/per-status request counters (module state).
module state

import strings

// record_metric counts one request for a route pattern and status code.
// `route` is the matched route pattern (e.g. "/api/v1/users/:id") or
// "unmatched" when no route matched.
pub fn (mut s State) record_metric(route string, status int) {
	s.mu.lock()
	s.req_total++
	mut statuses := (s.metrics[route] or { map[string]int{} }).clone()
	statuses[status.str()]++
	s.metrics[route] = statuses
	s.mu.unlock()
}

// metrics_counters_text renders the v_http_apilab_requests_total lines in
// Prometheus text format while holding the lock, so no nested-map
// copies can race with concurrent requests.
pub fn (s &State) metrics_counters_text() string {
	s.mu.lock()
	defer {
		s.mu.unlock()
	}
	mut sb := strings.new_builder(256)
	mut routes := s.metrics.keys()
	routes.sort()
	for route in routes {
		statuses := (s.metrics[route] or { map[string]int{} }).clone()
		mut codes := statuses.keys()
		codes.sort()
		for code in codes {
			n := statuses[code] or { 0 }
			sb.write_string('v_http_apilab_requests_total{route="${route}",status="${code}"} ${n}\n')
		}
	}
	return sb.str()
}

// requests_total returns the total number of requests that reached the
// dispatch layer (everything that produced a log line).
pub fn (s &State) requests_total() i64 {
	s.mu.lock()
	n := s.req_total
	s.mu.unlock()
	return n
}
