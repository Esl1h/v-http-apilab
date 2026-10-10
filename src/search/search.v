// search: substring search over the synthetic in-memory corpus.
module search

import router
import seed
import strconv
import veb

pub struct SearchHit {
pub:
	kind  string @[json: 'type']
	id    string @[json: 'id']
	title string @[json: 'title']
}

pub struct SearchBody {
pub:
	query   string      @[json: 'query']
	limit   int         @[json: 'limit']
	results []SearchHit @[json: 'results']
}

const max_query_len = 256

pub const default_limit = 10

pub const max_limit = 50

// search matches users, reports and synthetic documents by substring
// (case-insensitive) and returns up to `limit` hits.
pub fn search(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	query := ctx.query['q'] or {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'missing required query parameter "q"')
	}
	if query.len > max_query_len {
		return ctx.respond_error(.bad_request, 'invalid_query_value',
			'"q" must be at most ${max_query_len} characters, got ${query.len}')
	}
	limit_raw := ctx.query['limit'] or { '${default_limit}' }
	limit := strconv.atoi(limit_raw) or {
		return ctx.respond_error(.bad_request, 'invalid_query_value',
			'"limit" must be an integer, got "${limit_raw}"')
	}
	if limit < 1 || limit > max_limit {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'"limit" must be between 1 and ${max_limit}, got ${limit}')
	}
	mut st := app.store()
	needle := query.to_lower()
	mut results := []SearchHit{cap: limit}
	if needle != '' {
		for u in st.users_all() {
			if results.len >= limit {
				break
			}
			if u.name.to_lower().contains(needle) || u.email.to_lower().contains(needle)
				|| u.department.to_lower().contains(needle) {
				results << SearchHit{
					kind:  'user'
					id:    u.id.str()
					title: u.name
				}
			}
		}
		for r in seed.reports() {
			if results.len >= limit {
				break
			}
			if r.title.to_lower().contains(needle) || r.category.to_lower().contains(needle) {
				results << SearchHit{
					kind:  'report'
					id:    r.report_id
					title: r.title
				}
			}
		}
		for d in seed.search_docs {
			if results.len >= limit {
				break
			}
			if d.title.to_lower().contains(needle) {
				results << SearchHit{
					kind:  'document'
					id:    d.id
					title: d.title
				}
			}
		}
	}
	return ctx.respond_json(.ok, SearchBody{
		query:   query
		limit:   limit
		results: results
	})
}
