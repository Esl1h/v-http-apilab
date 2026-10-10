// files: multipart upload (analyzed in memory) and the /static allowlist.
//
// veb parses multipart/form-data bodies into ctx.files, so uploads are
// supported natively. Nothing is written to disk: only a sanitized name,
// the size and the SHA-256 are reported.
module files

import crypto.sha256
import router
import seed
import veb

pub struct UploadSummary {
pub:
	filename     string @[json: 'filename']
	size         int    @[json: 'size']
	content_type string @[json: 'content_type']
	sha256       string @[json: 'sha256']
	stored       bool   @[json: 'stored']
	request_id   string @[json: 'request_id']
}

const max_filename_len = 128

// sanitize_filename reduces a client filename to a safe token: only the
// base name, restricted to letters, digits, dot, dash and underscore.
// Returns 'upload.bin' when nothing safe remains.
pub fn sanitize_filename(raw string) string {
	base := raw.all_after_last('/').all_after_last('\\')
	mut cleaned := []u8{cap: base.len}
	for b in base.bytes() {
		if (b >= `a` && b <= `z`) || (b >= `A` && b <= `Z`) || (b >= `0` && b <= `9`)
			|| b == `.` || b == `-` || b == `_` {
			cleaned << b
		} else {
			cleaned << `_`
		}
	}
	name := cleaned.bytestr().trim_left('.')
	if name == '' || name.len > max_filename_len {
		return 'upload.bin'
	}
	return name
}

// upload accepts multipart/form-data (field "file") or
// application/octet-stream (name via ?name=) and answers the analysis.
pub fn upload(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	ct := ctx.content_type()
	if ct == 'multipart/form-data' {
		file := ctx.files['file'] or {
			return ctx.respond_error(.unprocessable_entity, 'validation_error',
				'missing multipart part "file"')
		}
		if file.len == 0 || file[0].data == '' {
			return ctx.respond_error(.unprocessable_entity, 'validation_error',
				'multipart part "file" must not be empty')
		}
		item := file[0]
		name := if item.filename != '' { item.filename } else { 'upload.bin' }
		return summary(mut ctx, name, item.content_type, item.data)
	}
	if ct == 'application/octet-stream' {
		name := ctx.query['name'] or {
			return ctx.respond_error(.unprocessable_entity, 'validation_error',
				'octet-stream uploads require a "?name=" query parameter')
		}
		if ctx.req.data == '' {
			return ctx.respond_error(.unprocessable_entity, 'validation_error',
				'request body must not be empty')
		}
		return summary(mut ctx, name, 'application/octet-stream', ctx.req.data)
	}
	got := if ct == '' { 'none' } else { ct }
	return ctx.respond_error(.unsupported_media_type, 'unsupported_media_type',
		'expected multipart/form-data or application/octet-stream, got "${got}"')
}

fn summary(mut ctx router.Context, raw_name string, content_type string, data string) veb.Result {
	return ctx.respond_json(.created, UploadSummary{
		filename:     sanitize_filename(raw_name)
		size:         data.len
		content_type: if content_type == '' { 'application/octet-stream' } else { content_type }
		sha256:       sha256.sum256(data.bytes()).hex()
		stored:       false
		request_id:   ctx.request_id
	})
}

// static_file serves only names present in the embedded allowlist.
// Path traversal is rejected explicitly (400) instead of relying on
// the 404 that an unknown name would produce.
pub fn static_file(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	name := params[0]
	for b in name.bytes() {
		if b == `\\` || b == `/` || b == 0 {
			return ctx.respond_error(.bad_request, 'path_traversal_rejected',
				'invalid static file name "${name}"')
		}
	}
	if name in ['.', '..'] || name.contains('..') {
		return ctx.respond_error(.bad_request, 'path_traversal_rejected',
			'invalid static file name "${name}"')
	}
	file := seed.static_file_by_name(name) or {
		return ctx.respond_error(.not_found, 'not_found',
			'static file "${name}" is not in the allowlist')
	}
	ctx.set_header(.content_type, file.content_type)
	ctx.set_header(.x_content_type_options, 'nosniff')
	return ctx.text(file.body)
}
