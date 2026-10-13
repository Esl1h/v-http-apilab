#!/usr/bin/env bash
# infra.sh: health, ready, version, metrics, request-id and log behavior.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start_server

http GET /health
expect_status smoke 200 'GET /health'
expect_body_contains smoke '"status":"ok"' '/health body is {"status":"ok"}'

http GET /ready
expect_status smoke 200 'GET /ready'
expect_body_contains smoke '"status":"ready"' '/ready body is {"status":"ready"}'

http GET /version
expect_status smoke 200 'GET /version'
expect_body_contains smoke '"app":"v-http-apilab"' '/version reports the app name'
expect_body_contains smoke '"version":"1.0.1"' '/version reports the app version'
expect_body_contains smoke '"v_version"' '/version reports the baked V version field'

http GET /
expect_status smoke 200 'GET / (index)'
expect_body_contains smoke '"endpoints"' 'index lists endpoint hints'

http GET /metrics
expect_status smoke 200 'GET /metrics'
expect_body_contains smoke 'v_http_apilab_up 1' 'metrics expose the up gauge'
expect_body_contains smoke 'v_http_apilab_requests_total' 'metrics expose request counters'
expect_header_contains smoke 'text/plain' 'metrics content type is text'

http GET /openapi.json
expect_status smoke 200 'GET /openapi.json'
expect_header_contains smoke 'application/json' 'the OpenAPI spec is served as JSON'
expect_body_contains smoke '"openapi": "3.0.3"' 'the spec declares OpenAPI 3.0.3'
expect_body_contains smoke '"/api/v1/users/{id}"' 'the spec documents the users path'
expect_body_contains smoke '"/lab/calls"' 'the spec documents the lab calls path'

http GET /docs
expect_status smoke 200 'GET /docs'
expect_header_contains smoke 'text/html' 'the Swagger UI page is HTML'
expect_body_contains smoke 'swagger-ui' 'the Swagger UI page loads the UI assets'
expect_body_contains smoke '/openapi.json' 'the Swagger UI points at the local spec'

http GET /health -H 'X-Request-ID: fixed-req-id-0001'
expect_status smoke 200 'GET /health with client X-Request-ID'
expect_header_contains smoke 'X-Request-ID: fixed-req-id-0001' 'client X-Request-ID is echoed in the response header'

http GET '/health?password=supersecret-value&normal=1'
expect_status errors 200 'GET /health with a sensitive query value is still served'
expect_log_contains errors 'password=[REDACTED]' 'sensitive query values are masked in the log'
expect_log_not_contains errors 'supersecret-value' 'the raw sensitive value never reaches the log'

http GET /health -H 'Authorization: Bearer should-never-be-logged'
expect_status errors 200 'GET /health with an Authorization header is served'
expect_log_not_contains errors 'should-never-be-logged' 'Authorization values are never logged'

http DELETE /health
expect_status errors 405 'DELETE /health is rejected'
expect_header_contains errors 'Allow: GET' '405 answers with Allow: GET'

http TRACE /health
expect_status errors 405 'TRACE /health is rejected (exotic method)'
expect_header_contains errors 'Allow: GET' 'TRACE 405 answers with Allow: GET'

http GET /no/such/route
expect_status errors 404 'GET unknown route is 404'
expect_body_contains errors '"error":{"code":"not_found"' '404 body uses the error envelope'

http PATCH /metrics
expect_status errors 405 'PATCH /metrics is rejected'
expect_header_contains errors 'Allow: GET' 'PATCH /metrics answers Allow: GET'

huge_value="$(head -c 20000 /dev/zero | tr '\0' 'A')"
http GET /health -H "X-Oversized-Header: $huge_value"
expect_status limits 431 'request headers above 16 KiB are refused by the backend (431)'

summary
