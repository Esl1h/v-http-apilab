// calls.v: the in-memory ring of recent requests (module state).
//
// This is the evidence buffer of the lab: /lab/calls lists what the
// backend actually received, so a request blocked by the proxy can be
// proven absent here.
module state

import time

pub struct CallRecord {
pub mut:
	request_id string @[json: 'request_id']
	test_case  string @[json: 'x_test_case']
	method     string @[json: 'method']
	path       string @[json: 'path']
	route      string @[json: 'route']
	status     int    @[json: 'status']
	timestamp  string @[json: 'timestamp']
}

// record_call appends one request to the bounded ring (oldest entries
// are dropped once the capacity is reached).
pub fn (mut s State) record_call(request_id string, test_case string, method string, path string, route string, status int) {
	rec := CallRecord{
		request_id: request_id
		test_case:  test_case
		method:     method
		path:       path
		route:      route
		status:     status
		timestamp:  time.now().format_rfc3339()
	}
	s.mu.lock()
	s.calls << rec
	if s.calls.len > calls_capacity {
		s.calls = s.calls[1..]
	}
	s.mu.unlock()
}

// calls_all returns a chronological copy of the ring (oldest first).
pub fn (s &State) calls_all() []CallRecord {
	s.mu.lock()
	list := s.calls.clone()
	s.mu.unlock()
	return list
}

// calls_reset clears the ring; returns how many entries were dropped.
pub fn (mut s State) calls_reset() int {
	s.mu.lock()
	n := s.calls.len
	s.calls.clear()
	s.mu.unlock()
	return n
}
