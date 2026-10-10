// tickets: synthetic support tickets (create + show).
module tickets

import router
import seed
import strconv
import veb

pub struct TicketRequest {
pub mut:
	title       string   @[json: 'title']
	description string   @[json: 'description']
	severity    string   @[json: 'severity']
	tags        []string @[json: 'tags']
}

const max_title_len = 120

const max_description_len = 2000

const max_tags = 10

const max_tag_len = 40

// create validates and stores a new synthetic ticket.
pub fn create(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	if !ctx.require_json() {
		return veb.no_result()
	}
	body := ctx.parse_body[TicketRequest]() or {
		return ctx.respond_error(.bad_request, 'invalid_json', 'request body is not valid JSON: ${err}')
	}
	mut errs := []string{}
	if body.title.len < 1 || body.title.len > max_title_len {
		errs << '"title" must be 1..${max_title_len} characters, got ${body.title.len}'
	}
	if body.description.len > max_description_len {
		errs << '"description" must be at most ${max_description_len} characters, got ${body.description.len}'
	}
	if body.severity !in seed.severities {
		errs << '"severity" must be one of ${seed.severities.join(', ')}, got "${body.severity}"'
	}
	if body.tags.len > max_tags {
		errs << '"tags" must have at most ${max_tags} entries, got ${body.tags.len}'
	}
	for tag in body.tags {
		if tag.len > max_tag_len {
			errs << 'tag "${tag}" must be at most ${max_tag_len} characters'
			break
		}
	}
	if errs.len > 0 {
		return ctx.respond_error(.unprocessable_entity, 'validation_error', errs.join('; '))
	}
	mut st := app.store()
	t := st.ticket_add(body.title, body.description, body.severity, body.tags)
	return ctx.respond_json(.created, t)
}

// show returns one synthetic ticket by numeric id.
pub fn show(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	id := strconv.atoi(params[0]) or {
		return ctx.respond_error(.bad_request, 'invalid_id', 'ticket id must be numeric, got "${params[0]}"')
	}
	if id < 1 {
		return ctx.respond_error(.bad_request, 'invalid_id', 'ticket id must be positive, got "${id}"')
	}
	mut st := app.store()
	t := st.ticket_by_id(id) or {
		return ctx.respond_error(.not_found, 'not_found', 'ticket ${id} not found')
	}
	return ctx.respond_json(.ok, t)
}
