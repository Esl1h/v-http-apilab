// forms: application/x-www-form-urlencoded form endpoint.
//
// veb already parses urlencoded bodies into ctx.form for POST/PUT/PATCH,
// so this handler only validates the declared content type and fields.
// The submitted values are echoed back JSON-escaped (never interpreted).
module forms

import router
import strconv
import veb

pub struct FeedbackResponse {
pub:
	received   bool   @[json: 'received']
	name       string @[json: 'name']
	rating     int    @[json: 'rating']
	comment    string @[json: 'comment']
	email      string @[json: 'email']
	request_id string @[json: 'request_id']
}

const max_name_len = 100

const max_comment_len = 500

const max_email_len = 254

// feedback validates and echoes a urlencoded feedback form.
pub fn feedback(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	ct := ctx.content_type()
	if ct != 'application/x-www-form-urlencoded' {
		got := if ct == '' { 'none' } else { ct }
		return ctx.respond_error(.unsupported_media_type, 'unsupported_media_type',
			'expected Content-Type application/x-www-form-urlencoded, got "${got}"')
	}
	rating_raw := ctx.form['rating'] or {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'missing required form field "rating"')
	}
	rating := strconv.atoi(rating_raw) or {
		return ctx.respond_error(.bad_request, 'invalid_form_value',
			'"rating" must be an integer between 1 and 5, got "${rating_raw}"')
	}
	if rating < 1 || rating > 5 {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"rating" must be between 1 and 5, got ${rating}')
	}
	name := ctx.form['name'] or { '' }
	if name.len > max_name_len {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"name" must be at most ${max_name_len} characters, got ${name.len}')
	}
	comment := ctx.form['comment'] or { '' }
	if comment.len > max_comment_len {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"comment" must be at most ${max_comment_len} characters, got ${comment.len}')
	}
	email := ctx.form['email'] or { '' }
	if email.len > max_email_len {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"email" must be at most ${max_email_len} characters, got ${email.len}')
	}
	return ctx.respond_json(.ok, FeedbackResponse{
		received:   true
		name:       name
		rating:     rating
		comment:    comment
		email:      email
		request_id: ctx.request_id
	})
}
