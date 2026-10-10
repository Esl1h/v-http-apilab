// graphql: a fixed, documented stub endpoint.
//
// This is NOT a GraphQL engine: the request shape is validated and a
// deterministic response is returned, so the lab can exercise parser
// payloads that look like GraphQL without any query execution.
module webhooks

import json2
import router
import veb

const max_query_len = 2048

const max_variables = 64

pub struct GraphqlBody {
pub:
	data       map[string]string @[json: 'data']
	errors     []string          @[json: 'errors']
	extensions GraphqlExtensions @[json: 'extensions']
}

pub struct GraphqlExtensions {
pub:
	query_length    int      @[json: 'query_length']
	variables_count int      @[json: 'variables_count']
	variables_keys  []string @[json: 'variables_keys']
	request_id      string   @[json: 'request_id']
}

// graphql validates {"query": "...", "variables": {...}} and answers the
// fixed documented response.
pub fn graphql(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	if !ctx.require_json() {
		return veb.no_result()
	}
	parsed := ctx.parse_body[json2.Any]() or {
		return ctx.respond_error(.bad_request, 'invalid_json', 'request body is not valid JSON: ${err}')
	}
	if parsed !is map[string]json2.Any {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'request body must be a JSON object with "query" and optional "variables"')
	}
	obj := parsed as map[string]json2.Any
	query_value := obj['query'] or {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'missing required field "query"')
	}
	if query_value !is string {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'field "query" must be a string')
	}
	query := query_value as string
	if query == '' {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'field "query" must not be empty')
	}
	if query.len > max_query_len {
		return ctx.respond_error(.unprocessable_entity, 'validation_error',
			'field "query" must be at most ${max_query_len} characters, got ${query.len}')
	}
	mut variables_count := 0
	mut variables_keys := []string{}
	if variables_value := obj['variables'] {
		if variables_value !is map[string]json2.Any {
			return ctx.respond_error(.unprocessable_entity, 'validation_error',
				'field "variables" must be a JSON object')
		}
		variables := variables_value as map[string]json2.Any
		variables_keys = variables.keys()
		variables_keys.sort()
		variables_count = variables_keys.len
		if variables_count > max_variables {
			return ctx.respond_error(.unprocessable_entity, 'validation_error',
				'"variables" must have at most ${max_variables} keys, got ${variables_count}')
		}
	}
	return ctx.respond_json(.ok, GraphqlBody{
		data:       {
			'lab': 'ok'
		}
		errors:     []
		extensions: GraphqlExtensions{
			query_length:    query.len
			variables_count: variables_count
			variables_keys:  variables_keys
			request_id:      ctx.request_id
		}
	})
}
