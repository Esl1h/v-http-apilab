#!/usr/bin/env bash
# webhooks.sh: webhook receive (summary only) and the graphql stub.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start_server

http POST /api/v1/webhooks/receive -H 'Content-Type: application/json' \
	-d '{"event":"push","repo":"synthetic-repo","secret":"should-not-be-echoed"}'
expect_status smoke 200 'receive a JSON webhook'
expect_body_contains smoke '"received_bytes":' 'the summary reports the body size'
expect_body_contains smoke '"top_level_keys":["event","repo","secret"]' 'the summary lists the top-level keys'
expect_body_contains smoke '"body_sha256":"' 'the summary reports a body hash'
expect_body_contains smoke '"stored":false' 'webhook bodies are never stored'
expect_body_not_contains smoke 'should-not-be-echoed' 'the webhook body content is never echoed'

http POST /api/v1/webhooks/receive -H 'Content-Type: text/plain' -d 'not-json-payload'
expect_status smoke 200 'receive a non-JSON webhook'
expect_body_contains smoke '"json_valid":false' 'non-JSON bodies are reported as not valid JSON'
expect_body_contains smoke '"top_level_keys":[]' 'non-JSON bodies have no top-level keys'

http POST /api/v1/graphql -H 'Content-Type: application/json' \
	-d '{"query":"{ lab { ok } }","variables":{"who":"tests"}}'
expect_status smoke 200 'graphql stub answers the fixed response'
expect_body_contains smoke '"data":{"lab":"ok"}' 'graphql answers the fixed data block'
expect_body_contains smoke '"query_length":14' 'graphql reports the query length'
expect_body_contains smoke '"variables_keys":["who"]' 'graphql reports the variable keys'

http POST /api/v1/graphql -H 'Content-Type: application/json' -d '{"variables":{"x":1}}'
expect_status errors 422 'graphql without query is 422'

http POST /api/v1/graphql -H 'Content-Type: application/json' -d '{"query":123}'
expect_status errors 422 'graphql with a non-string query is 422'

http POST /api/v1/graphql -H 'Content-Type: application/json' -d '[1,2,3]'
expect_status errors 422 'graphql with a non-object body is 422'

http POST /api/v1/graphql -H 'Content-Type: application/json' -d '{broken'
expect_status errors 400 'graphql with invalid JSON is 400'

http POST /api/v1/graphql -H 'Content-Type: text/plain' -d '{"query":"{ a }"}'
expect_status errors 415 'graphql with a non-JSON content type is 415'

http POST /api/v1/graphql -H 'Content-Type: application/json' \
	-d '{"query":"{ a }","variables":"not-an-object"}'
expect_status errors 422 'graphql with non-object variables is 422'

long_query="$(head -c 2049 /dev/zero | tr '\0' 'q')"
http POST /api/v1/graphql -H 'Content-Type: application/json' \
	-d "{\"query\":\"$long_query\"}"
expect_status limits 422 'a graphql query longer than 2048 chars is 422'

http GET /api/v1/webhooks/receive
expect_status errors 405 'GET on the webhook endpoint is 405'
expect_header_contains errors 'Allow: POST' 'the webhook endpoint answers Allow: POST'

summary
