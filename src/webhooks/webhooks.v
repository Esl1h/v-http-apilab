// webhooks: receives arbitrary webhook payloads and answers a summary.
//
// The body is never echoed and never interpreted: only its size, content
// type, top-level keys and SHA-256 are returned.
module webhooks

import crypto.sha256
import json2
import router
import veb

pub struct WebhookSummary {
pub:
	received_bytes int      @[json: 'received_bytes']
	content_type   string   @[json: 'content_type']
	json_valid     bool     @[json: 'json_valid']
	top_level_keys []string @[json: 'top_level_keys']
	body_sha256    string   @[json: 'body_sha256']
	stored         bool     @[json: 'stored']
	request_id     string   @[json: 'request_id']
}

// receive accepts any content type up to MAX_BODY_BYTES and answers a
// summary with a proof of receipt (hash) but no body content.
pub fn receive(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	body := ctx.req.data
	mut json_valid := false
	mut keys := []string{}
	if body != '' {
		if parsed := json2.decode[json2.Any](body) {
			json_valid = true
			if parsed is map[string]json2.Any {
				obj := parsed as map[string]json2.Any
				keys = obj.keys()
				keys.sort()
			}
		}
	}
	return ctx.respond_json(.ok, WebhookSummary{
		received_bytes: body.len
		content_type:   ctx.content_type()
		json_valid:     json_valid
		top_level_keys: keys
		body_sha256:    sha256.sum256(body.bytes()).hex()
		stored:         false
		request_id:     ctx.request_id
	})
}
