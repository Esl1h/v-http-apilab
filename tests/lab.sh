#!/usr/bin/env bash
# lab.sh: the testing utilities (/lab/*).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start_server

http GET /lab/echo -H 'X-Test-Case: echo-check' -H 'Authorization: Bearer must-not-reflect'
expect_status smoke 200 'echo answers the request'
expect_body_contains smoke '"method":"GET"' 'echo reports the method'
expect_body_contains smoke '"path":"/lab/echo"' 'echo reports the path'
expect_body_contains smoke '"X-Test-Case":"echo-check"' 'the headers reflect X-Test-Case'
expect_body_contains smoke '"Host":"127.0.0.1' 'the headers reflect Host'
expect_body_contains smoke '"body_bytes":0' 'echo reports the body size'
expect_body_not_contains smoke 'must-not-reflect' 'echo never reflects Authorization values'

http POST /lab/echo -H 'X-Test-Case: post-echo' -d 'sentinel-body-42'
expect_status errors 405 'POST /lab/echo is 405 (the route is GET-only)'
expect_header_contains errors 'Allow: GET' 'echo answers Allow: GET'

http GET /lab/method
expect_status smoke 200 'lab method answers GET'
expect_body_contains smoke '"method":"GET"' 'the method is reported'

http POST /lab/method
expect_status smoke 200 'lab method answers POST'
expect_body_contains smoke '"method":"POST"' 'the method is reported'

http PATCH /lab/method
expect_status smoke 200 'lab method answers PATCH'
expect_body_contains smoke '"method":"PATCH"' 'the method is reported'

http OPTIONS /lab/method
expect_status smoke 200 'lab method answers OPTIONS'
expect_header_contains smoke 'Allow: GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS' 'method answers the full Allow set'

http HEAD /lab/method
expect_status smoke 200 'lab method answers HEAD'
expect_header_contains smoke 'Allow: GET, HEAD, POST' 'HEAD answers with the Allow header'

http GET '/lab/slow?ms=200'
expect_status smoke 200 'slow answers after the delay'
expect_body_contains smoke '"slept_ms":200' 'slow reports the slept time'
timed GET '/lab/slow?ms=250'
expect_status smoke 200 'timed slow request succeeds'
expect_min_time smoke 0.24 'slow really sleeps the requested time'

http GET /lab/status/418
expect_status smoke 418 'status answers the requested code (418)'

http GET /lab/status/204
expect_status smoke 204 'status answers 204 without a body'
expect_body_size smoke 0 'the 204 answer has no body'

http GET /lab/status/503
expect_status smoke 503 'status answers the requested code (503)'

http GET /lab/response-marker
expect_status smoke 200 'response-marker answers 200'
expect_header_contains smoke 'X-Lab-Marker: LAB_RESPONSE_MARKER_7f3a' 'the marker is also exposed as a header'
expect_body_contains smoke 'LAB_RESPONSE_MARKER_7f3a' 'the marker is in the body'

http GET '/lab/large?bytes=1024'
expect_status smoke 200 'large answers a 1024-byte body'
expect_body_size smoke 1024 'the large body is exactly the requested size'

http GET /lab/headers
expect_status smoke 200 'headers answers the security set'
expect_header_contains smoke 'X-Frame-Options: DENY' 'headers sets X-Frame-Options'
expect_header_contains smoke 'X-Content-Type-Options: nosniff' 'headers sets nosniff'
expect_header_contains smoke "Content-Security-Policy: default-src 'none'" 'headers sets a CSP'
expect_header_contains smoke 'Strict-Transport-Security:' 'headers sets HSTS'

http GET /lab/stream
expect_status smoke 200 'stream answers with a chunked response'
expect_header_contains smoke 'Transfer-Encoding: chunked' 'stream uses chunked transfer encoding'
expect_body_contains smoke 'lab-stream-chunk-5-of-5' 'stream delivers all five chunks'

http GET '/health' -H 'X-Test-Case: calls-proof-tag'
expect_status smoke 200 'tag a request to prove it in /lab/calls'
http GET /lab/calls -H "X-Lab-Token: $LAB_ADMIN_TOKEN"
expect_status smoke 200 'calls answers with the lab token'
expect_body_contains smoke '"x_test_case":"calls-proof-tag"' 'the tagged request is provable in /lab/calls'

http GET '/lab/slow?ms=1' -H 'X-Test-Case: blocked-should-not-appear'
expect_status errors 200 'a request that reached the backend is recorded'
http GET /lab/calls -H "X-Lab-Token: $LAB_ADMIN_TOKEN"
expect_status errors 200 'calls lists the recorded request'
expect_body_contains errors '"x_test_case":"blocked-should-not-appear"' 'the /lab/calls buffer shows what really arrived'

http GET /lab/echo -H 'Authorization: Bearer no-echo-please' -H 'X-Test-Case: never-log-auth'
expect_status errors 200 'echo accepts an Authorization header'
expect_log_not_contains errors 'no-echo-please' 'Authorization values never reach the log'

http GET /lab/status/999
expect_status errors 400 'status above 599 is 400'

http GET /lab/status/199
expect_status errors 400 'status below 200 is 400'

http GET /lab/status/abc
expect_status errors 400 'a non-numeric status is 400'

http GET '/lab/slow?ms=99999'
expect_status errors 400 'slow above MAX_SLOW_MS is 400'

http GET '/lab/slow?ms=abc'
expect_status errors 400 'slow with a non-numeric ms is 400'

http GET '/lab/large?bytes=99999999999'
expect_status errors 400 'large above MAX_LARGE_BYTES is 400'

http GET '/lab/large?bytes=abc'
expect_status errors 400 'large with a non-numeric size is 400'

http GET /lab/calls
expect_status errors 401 'calls without a token is 401'

http GET /lab/calls -H 'X-Lab-Token: wrong-token'
expect_status errors 403 'calls with a wrong token is 403'

http POST /lab/calls/reset -H 'X-Lab-Token: wrong-token'
expect_status errors 403 'calls reset with a wrong token is 403'

http POST /lab/calls/reset -H "X-Lab-Token: $LAB_ADMIN_TOKEN"
expect_status smoke 200 'calls reset with the right token'
expect_body_contains smoke '"reset":true' 'calls reset confirms the operation'
http GET /lab/calls -H "X-Lab-Token: $LAB_ADMIN_TOKEN"
expect_body_contains smoke '"count":1' 'after reset only the reset and the calls themselves remain'

# Disabled mode: a second server without LAB_ADMIN_TOKEN must answer 404
# for both /lab/calls endpoints.
DISABLED_PORT=$((TEST_PORT + 1))
DISABLED_LOG="$(mktemp /tmp/v-http-lab-disabled.XXXXXX.log)"
env -u LAB_ADMIN_TOKEN PORT="$DISABLED_PORT" setsid "$VHTTP_BIN" >"$DISABLED_LOG" 2>&1 </dev/null &
DISABLED_PID=$!
for _ in $(seq 1 50); do
	curl -sf -m 1 "http://127.0.0.1:${DISABLED_PORT}/health" >/dev/null 2>&1 && break
	sleep 0.1
done
disabled_calls_status="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' \
	"http://127.0.0.1:${DISABLED_PORT}/lab/calls" || true)"
disabled_reset_status="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' \
	-X POST "http://127.0.0.1:${DISABLED_PORT}/lab/calls/reset" || true)"
kill "$DISABLED_PID" 2>/dev/null || true
wait "$DISABLED_PID" 2>/dev/null || true
rm -f "$DISABLED_LOG"
if ! should_run errors; then
	SKIP=$((SKIP + 2))
else
	if [[ "$disabled_calls_status" == "404" && "$disabled_reset_status" == "404" ]]; then
		PASS=$((PASS + 2))
		echo 'PASS [errors] /lab/calls endpoints are disabled (404) without LAB_ADMIN_TOKEN'
	else
		FAIL=$((FAIL + 2))
		echo "FAIL [errors] /lab/calls disabled mode (expected 404/404, got ${disabled_calls_status:-none}/${disabled_reset_status:-none})"
	fi
fi

summary
