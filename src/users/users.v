// users: CRUD over the synthetic user table.
module users

import json2
import router
import seed
import strconv
import veb

pub struct UserBody {
pub mut:
	name       string @[json: 'name']
	email      string @[json: 'email']
	department string @[json: 'department']
	role       string @[json: 'role']
}

pub struct UsersPage {
pub:
	page        i64         @[json: 'page']
	per_page    int         @[json: 'per_page']
	total       int         @[json: 'total']
	total_pages int         @[json: 'total_pages']
	items       []seed.User @[json: 'items']
}

const max_per_page = 100

// parse_id validates a numeric path id and answers 400 when malformed.
fn parse_id(mut ctx router.Context, raw string) ?int {
	id := strconv.atoi(raw) or {
		ctx.respond_error(.bad_request, 'invalid_id', 'user id must be numeric, got "${raw}"')
		return none
	}
	if id < 1 {
		ctx.respond_error(.bad_request, 'invalid_id', 'user id must be positive, got "${id}"')
		return none
	}
	return id
}

// validate checks one field of a user payload and returns its error
// message, or an empty string when the field is valid.
fn validate_field(field string, value string) string {
	match field {
		'name' {
			if value.len < 1 || value.len > 100 {
				return '"name" must be 1..100 characters, got ${value.len}'
			}
		}
		'email' {
			if value.len < 3 || value.len > 254 || !value.contains('@') || !value.contains('.')
				|| value.contains(' ') {
				return '"email" must be a syntactic email (user@domain.tld), got "${value}"'
			}
		}
		'department' {
			if value.len < 1 || value.len > 50 {
				return '"department" must be 1..50 characters, got ${value.len}'
			}
		}
		'role' {
			if value !in seed.roles {
				return '"role" must be one of ${seed.roles.join(', ')}, got "${value}"'
			}
		}
		else {}
	}
	return ''
}

// validate_body validates a complete user payload (POST/PUT).
fn validate_body(body UserBody) []string {
	mut errs := []string{cap: 4}
	for field in ['name', 'email', 'department', 'role'] {
		value := match field {
			'name' { body.name }
			'email' { body.email }
			'department' { body.department }
			else { body.role }
		}
		msg := validate_field(field, value)
		if msg != '' {
			errs << msg
		}
	}
	return errs
}

// respond_unprocessable sends a 422 with all field errors joined.
fn respond_unprocessable(mut ctx router.Context, errs []string) veb.Result {
	return ctx.respond_error(.unprocessable_entity, 'validation_error', errs.join('; '))
}

// parse_full_body answers 415/400 and parses a complete user payload.
fn parse_full_body(mut ctx router.Context) ?UserBody {
	if !ctx.require_json() {
		return none
	}
	body := ctx.parse_body[UserBody]() or {
		ctx.respond_error(.bad_request, 'invalid_json', 'request body is not valid JSON: ${err}')
		return none
	}
	return body
}

// index lists users with pagination and an optional department filter.
pub fn index(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	page := parse_positive_int(mut ctx, ctx.query['page'] or { '' }, 'page', 1) or {
		return veb.no_result()
	}
	per_page := parse_positive_int(mut ctx, ctx.query['per_page'] or { '' }, 'per_page',
		20) or { return veb.no_result() }
	if per_page > max_per_page {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"per_page" must be at most ${max_per_page}, got ${per_page}')
	}
	department := ctx.query['department'] or { '' }
	all := app.store().users_all()
	mut filtered := []seed.User{cap: all.len}
	for u in all {
		if department == '' || u.department == department {
			filtered << u
		}
	}
	total := filtered.len
	size := int(per_page)
	total_pages := if total == 0 { 0 } else { (total + size - 1) / size }
	if page > total_pages && total > 0 {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"page" ${page} is out of range (total_pages=${total_pages})')
	}
	mut items := []seed.User{}
	// an empty result set accepts any page; slicing is only safe (and
	// page small enough to multiply) when the page exists
	if page <= total_pages {
		start := int(page - 1) * size
		end := if start + size < total { start + size } else { total }
		items = filtered[start..end].clone()
	}
	return ctx.respond_json(.ok, UsersPage{
		page:        page
		per_page:    size
		total:       total
		total_pages: total_pages
		items:       items
	})
}

// parse_positive_int reads an optional numeric query value: empty or
// absent yields `default`, malformed answers 400, below 1 answers 422.
// It parses as i64 so a huge page is reported as out of range, not as
// malformed.
fn parse_positive_int(mut ctx router.Context, raw string, field string, default i64) ?i64 {
	if raw == '' {
		return default
	}
	value := strconv.parse_int(raw, 10, 64) or {
		ctx.respond_error(.bad_request, 'invalid_query_value', '"${field}" must be an integer, got "${raw}"')
		return none
	}
	if value < 1 {
		ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"${field}" must be at least 1, got ${value}')
		return none
	}
	return value
}

// show returns one user by numeric id.
pub fn show(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	id := parse_id(mut ctx, params[0]) or { return veb.no_result() }
	mut st := app.store()
	u := st.user_by_id(id) or {
		return ctx.respond_error(.not_found, 'not_found', 'user ${id} not found')
	}
	return ctx.respond_json(.ok, u)
}

// create validates and appends a new user.
pub fn create(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	body := parse_full_body(mut ctx) or { return veb.no_result() }
	errs := validate_body(body)
	if errs.len > 0 {
		return respond_unprocessable(mut ctx, errs)
	}
	mut st := app.store()
	u := st.user_add(body.name, body.email, body.department, body.role)
	return ctx.respond_json(.created, u)
}

// replace fully updates an existing user (PUT).
pub fn replace(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	id := parse_id(mut ctx, params[0]) or { return veb.no_result() }
	body := parse_full_body(mut ctx) or { return veb.no_result() }
	errs := validate_body(body)
	if errs.len > 0 {
		return respond_unprocessable(mut ctx, errs)
	}
	mut st := app.store()
	u := st.user_replace(id, body.name, body.email, body.department, body.role) or {
		return ctx.respond_error(.not_found, 'not_found', 'user ${id} not found')
	}
	return ctx.respond_json(.ok, u)
}

// update partially updates an existing user (PATCH). The body is any
// subset of the writable fields; unknown fields are rejected.
pub fn update(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	id := parse_id(mut ctx, params[0]) or { return veb.no_result() }
	if !ctx.require_json() {
		return veb.no_result()
	}
	parsed := ctx.parse_body[json2.Any]() or {
		return ctx.respond_error(.bad_request, 'invalid_json', 'request body is not valid JSON: ${err}')
	}
	// decoding straight into a map turns `null` into an empty map
	if parsed !is map[string]json2.Any {
		return ctx.respond_error(.bad_request, 'invalid_json', 'request body must be a JSON object')
	}
	raw := parsed as map[string]json2.Any
	mut patch := map[string]string{}
	mut errs := []string{}
	for key, value in raw {
		if key !in ['name', 'email', 'department', 'role'] {
			errs << 'unknown field "${key}" (allowed: name, email, department, role)'
			continue
		}
		if value is string {
			str_value := value as string
			msg := validate_field(key, str_value)
			if msg != '' {
				errs << msg
			} else {
				patch[key] = str_value
			}
		} else {
			errs << 'field "${key}" must be a JSON string'
		}
	}
	if errs.len > 0 {
		return respond_unprocessable(mut ctx, errs)
	}
	if patch.len == 0 {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'empty patch: provide at least one of name, email, department, role')
	}
	mut st := app.store()
	u := st.user_patch(id, patch) or {
		return ctx.respond_error(.not_found, 'not_found', 'user ${id} not found')
	}
	return ctx.respond_json(.ok, u)
}

// destroy removes a user (204 on success).
pub fn destroy(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	id := parse_id(mut ctx, params[0]) or { return veb.no_result() }
	mut st := app.store()
	if !st.user_delete(id) {
		return ctx.respond_error(.not_found, 'not_found', 'user ${id} not found')
	}
	return ctx.no_content()
}
