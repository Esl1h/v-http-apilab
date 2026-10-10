// logging emits one structured JSON log line per request to stdout.
//
// Never logged: Authorization, Cookie, Set-Cookie, passwords or tokens.
// Query-string values for sensitive keys are masked as "[REDACTED]".
// A mutex serializes writes because the veb fasthttp backend is
// multi-threaded.
module logging

import json2
import sync
import time

// sensitive_keys are query keys whose values are always masked in logs.
pub const sensitive_keys = [
	'password',
	'passwd',
	'secret',
	'token',
	'api_key',
	'apikey',
	'access_token',
	'authorization',
	'auth',
	'key',
	'cookie',
	'session',
]

pub struct LogEntry {
pub mut:
	timestamp       string @[json: 'timestamp']
	level           string @[json: 'level']
	msg             string @[json: 'msg']
	request_id      string @[json: 'request_id']
	method          string @[json: 'method']
	path            string @[json: 'path']
	query           string @[json: 'query']
	status          int    @[json: 'status']
	duration_ms     i64    @[json: 'duration_ms']
	route           string @[json: 'route']
	remote_addr     string @[json: 'remote_addr']
	user_agent      string @[json: 'user_agent']
	content_length  i64    @[json: 'content_length']
	content_type    string @[json: 'content_type']
	x_forwarded_for string @[json: 'x_forwarded_for']
	x_test_case     string @[json: 'x_test_case']
}

pub struct EventLine {
pub mut:
	timestamp string @[json: 'timestamp']
	level     string @[json: 'level']
	msg       string @[json: 'msg']
}

// Logger serializes structured log lines to stdout.
pub struct Logger {
mut:
	mu &sync.Mutex = unsafe { nil }
}

// new creates a ready-to-use Logger.
pub fn new() &Logger {
	mut l := &Logger{}
	l.mu = sync.new_mutex()
	return l
}

// write_request_line emits the single per-request JSON line to stdout.
pub fn (mut l Logger) write_request_line(entry LogEntry) {
	line := json2.encode(entry)
	l.mu.lock()
	println(line)
	flush_stdout()
	l.mu.unlock()
}

// write_event emits a non-request operational line (startup, shutdown).
pub fn (mut l Logger) write_event(level string, msg string) {
	entry := EventLine{
		timestamp: time.now().format_rfc3339()
		level:     level
		msg:       msg
	}
	line := json2.encode(entry)
	l.mu.lock()
	println(line)
	flush_stdout()
	l.mu.unlock()
}

// mask_query rewrites sensitive key values of a raw query string to
// "[REDACTED]". Non-sensitive pairs pass through untouched.
pub fn mask_query(raw string) string {
	if raw == '' {
		return ''
	}
	mut parts := []string{cap: 8}
	for pair in raw.split('&') {
		if pair == '' {
			continue
		}
		key := pair.all_before('=').to_lower()
		if pair.contains('=') && key in sensitive_keys {
			parts << '${pair.all_before('=')}=[REDACTED]'
		} else {
			parts << pair
		}
	}
	return parts.join('&')
}
