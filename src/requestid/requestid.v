// requestid resolves the per-request correlation id.
//
// The client may pass X-Request-ID; when present and well-formed it is
// echoed back, otherwise a fresh UUID v4 is generated. The id is never
// interpreted: it is only validated, stored and escaped by json2.
module requestid

import rand

pub const header_name = 'X-Request-ID'

pub const max_len = 128

// resolve returns `incoming` when it is a safe printable header value,
// otherwise a freshly generated UUID v4.
pub fn resolve(incoming string) string {
	if is_valid(incoming) {
		return incoming
	}
	return rand.uuid_v4()
}

// is_valid accepts 1..max_len printable ASCII characters without spaces
// or control bytes. Longer or malformed ids are replaced, not echoed.
pub fn is_valid(id string) bool {
	if id.len < 1 || id.len > max_len {
		return false
	}
	for b in id {
		if b < `!` || b > `~` {
			return false
		}
	}
	return true
}
