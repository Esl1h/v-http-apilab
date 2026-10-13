# Endpoint contract

General conventions:

- Success responses are `application/json`, except where noted
  (`/metrics`, CSV downloads, static files and the text utilities).
- Every response carries the `X-Request-ID` header: the value received
  in the header of the same name (when valid: 1 to 128 printable ASCII
  characters) or a generated UUID v4. Errors also include it in the
  body.
- Optional `X-Test-Case` header: labels the request in the structured
  log and in the `/lab/calls` buffer.
- Every error response uses the format:

```json
{"error":{"code":"...","message":"...","request_id":"..."}}
```

- Cross-cutting codes: `400` invalid syntax, `401` missing or invalid
  credential, `403` known but refused credential, `404` non-existent
  route/resource, `405` method not allowed (with `Allow` header), `413`
  body above `MAX_BODY_BYTES`, `415` unexpected Content-Type, `422`
  valid body that is semantically invalid.
- Methods not covered by any route (for example `TRACE`, `PROPFIND`)
  get the same treatment: 405 with `Allow` when the path exists for
  another method, or 404; in both cases the request is logged and
  recorded in the `/lab/calls` buffer.

## Infra

### GET /health
Liveness. Always `200` with `{"status":"ok"}`.

### GET /ready
Readiness. `200` with `{"status":"ready"}`; `503` with
`{"status":"unavailable"}` when the `READY_FORCE_FAIL` env has any
non-empty value.

### GET /version
`200` with `{"app","version","v_version","build_date","deterministic_seed"}`.
`v_version` is baked at build time by `scripts/build.sh` and by the
Dockerfile (`unknown` when not provided). `build_date` comes from the
`@BUILD_DATE` comptime value (reproducible with `SOURCE_DATE_EPOCH`).

### GET /metrics
Prometheus text (Content-Type `text/plain; version=0.0.4;
charset=utf-8`): `v_http_apilab_up`, `v_http_apilab_uptime_seconds`,
`v_http_apilab_build_info` and `v_http_apilab_requests_total{route,status}`
per route (patterns such as `/api/v1/users/:id` or `unmatched`) and
status.

### GET /openapi.json
The complete OpenAPI 3.0.3 specification of this API, as
`application/json`. The document (`src/openapi/openapi.json`) is
embedded in the binary at compile time: there is no disk read.

### GET /docs
HTML page with Swagger UI pointing at `/openapi.json`. The UI assets
(CSS/JS) are loaded from a CDN, so rendering the page requires internet
access in the browser; the API itself is self-contained.

## Authentication (simulated)

### POST /api/v1/auth/login
JSON body `{"username","password"}`. Errors: `415` without JSON, `400`
invalid JSON, `422` missing field, `401` wrong credentials
(`invalid_credentials`). Success `200`: `{"token","token_type":"Bearer",
"expires_in":3600,"username","request_id"}`. The password is never
logged or returned. Default credentials: `LAB_USERNAME`/
`LAB_PASSWORD`.

### POST /api/v1/auth/logout
Requires `Authorization: Bearer <token>`. `200`
`{"logged_out":true,...}`; `401` without a token or with an unknown
token. Body is optional and ignored.

### GET /api/v1/auth/me
Requires a valid, unexpired `Authorization: Bearer <token>`. `200`
with the synthetic profile `{"username","display_name","role","email",
"request_id"}`; `401` otherwise.

## Users

### GET /api/v1/users
Query: `page` (default 1, minimum 1), `per_page` (default 20, 1..100;
an empty value uses the default),
`department` (optional exact filter). `200` with
`{"page","per_page","total","total_pages","items":[User]}`. Errors:
`400` non-numeric values, `422` out of range (including a page beyond
the last). `User`: `{"id","name","email","department","role"}`.

### GET /api/v1/users/{id}
`id` positive numeric. `200` with the user; `400` invalid id; `404`
not found.

### POST /api/v1/users
JSON body `{"name" (1..100),"email" (user@domain.tld syntax, up to
254),"department" (1..50),"role" (admin|operator|viewer)}`. `201` with
the created user (ids start at 26). Errors: `415`, `400`, `422` (all
field failures listed in `message`).

### PUT /api/v1/users/{id}
Full replacement; same validation as POST. `200` with the updated
user; `404` not found; `400/415/422` as in POST.

### PATCH /api/v1/users/{id}
JSON body with any subset of `name`, `email`, `department`, `role`.
Unknown fields and non-string values are `422`; an empty patch is
`422`; `404` not found; `415`/`400` as in the others.

### DELETE /api/v1/users/{id}
`204` with no body on success; `404` not found; `400` invalid id.

## Search

### GET /api/v1/search
Query: `q` (required, up to 256 characters) and `limit` (default 10,
1..50). `200` with `{"query","limit","results":[{"type","id","title"}]}`
over the synthetic corpus (users, reports and documents). Errors: `422`
without `q` or with invalid limits, `400` invalid size or number.

## Reports

### GET /api/v1/reports
`200` `{"count":6,"items":[{"report_id","title","category","rows",
"generated_at"}]}` from the fixed catalog `rep-001..rep-006`.

### POST /api/v1/reports/export
JSON body `{"report_id","format"}` with `format` in `csv|json`. `202`
with `{"job_id":"job-N","status":"queued","report_id","format",
"request_id"}`. Errors: `415`, `400`, `422` (missing fields/invalid
format), `404` unknown report. Nothing actually runs; the job is
listed in `/internal/debug`.

### GET /api/v1/reports/{id}/download
`200` with synthetic CSV (`text/csv`, `Content-Disposition:
attachment`), one `region,label,value` header line and `rows`
deterministic rows. `404` for an unknown id.

## Tickets

### POST /api/v1/tickets
JSON body `{"title" (1..120),"description" (0..2000),"severity"`
`(low|medium|high|critical),"tags" (up to 10, each up to 40)}`. `201`
with the ticket (ids start at 4; the seed has 3). Errors: `415`, `400`,
`422` with all violations listed.

### GET /api/v1/tickets/{id}
`200` with the ticket; `400` invalid id; `404` not found.

## Forms

### POST /api/v1/forms/feedback
Content-Type must be `application/x-www-form-urlencoded`. Fields:
`rating` (integer 1..5, required), `name` (up to 100), `comment` (up to
500), `email` (up to 254). `200` echoes the values with correct JSON
escaping `{"received":true,"name","rating","comment","email",
"request_id"}`. Errors: `415`, `400` (non-numeric rating), `422`
(missing/out-of-range rating, fields too long).

## Integrations

### POST /api/v1/webhooks/receive
Any Content-Type; body up to `MAX_BODY_BYTES`. `200` with the summary
`{"received_bytes","content_type","json_valid","top_level_keys",
"body_sha256","stored":false,"request_id"}`. Top-level keys (JSON
objects only) come sorted; the body content is never echoed.

### POST /api/v1/graphql
Documented stub; does not run GraphQL. JSON body
`{"query" (string 1..2048, required),"variables" (object, optional, up
to 64 keys)}`. Fixed `200`:

```json
{"data":{"lab":"ok"},"errors":[],"extensions":{"query_length":N,
  "variables_count":N,"variables_keys":[...],"request_id":"..."}}
```

Errors: `415`, `400` (invalid JSON), `422` (wrong shape).

## Files

### POST /api/v1/files/upload
Accepts `multipart/form-data` (part `file`, non-empty) or
`application/octet-stream` (with `?name=`). `201` with
`{"filename" (sanitized),"size","content_type","sha256","stored":false,
"request_id"}`. The name is reduced to its basename with only
`[A-Za-z0-9._-]` (others become `_`; empty becomes `upload.bin`; limit
128). Nothing is written to disk. Errors: `415` other Content-Type,
`422` missing part/missing name/empty body.

### GET /static/{name}
Serves only the embedded allowlist: `robots.txt`, `style.css`,
`logo.svg`, `data.csv` (with their Content-Types and
`X-Content-Type-Options: nosniff`). `404` outside the list. Segments
with backslash, slash or NUL get `400` `path_traversal_rejected`;
dot segments (`..`, `%2e%2e`) are normalized by the URL parser before
routing (they never reach the allowlist).

## Administration (simulated)

### GET /admin/status
`200` with non-sensitive counters: `{"mode":"lab","uptime_seconds",
"requests_total","users","tickets","sessions","export_jobs"}`.

### POST /admin/config
JSON object body. `200` with `{"valid":true,"applied":false,
"received":<echo>,"note":"lab mode: configuration is validated and
echoed, never applied","request_id"}`. Nothing is applied. Errors:
`415`, `400`, `422` (not an object).

### GET /internal/debug
`200` with non-sensitive data only: versions, `started_at`, uptime and
counters (including `calls_buffered`).

## Lab utilities

### GET /lab/echo
`200` with `{"method","path","query" (raw),"headers" (allowlist),
"body_bytes","body_sha256","request_id"}`. Reflected header allowlist:
`Host, User-Agent, Accept, Accept-Encoding, Accept-Language,
Content-Type, Content-Length, X-Request-ID, X-Test-Case,
X-Forwarded-For, X-Forwarded-Proto`. `Authorization` and `Cookie` are
never reflected; the body is never echoed (only size and hash). GET
only (`405` with `Allow: GET` for the others).

### /lab/method
Accepts GET, HEAD, POST, PUT, PATCH, DELETE and OPTIONS. `200` with
`{"method","received":true,"allowed":[...],"request_id"}` and the full
`Allow` header. HEAD answers without a body with the `Content-Length`
of the equivalent body.

### GET /lab/slow?ms=N
Sleeps `N` ms (0 to `MAX_SLOW_MS`) and answers `{"slept_ms","max_ms",
"request_id"}`. `400` for non-numeric values or above the ceiling.

### GET /lab/status/{code}
Answers with the requested status (200..599). 204, 205 and 304 come
without a body; the others with `{"requested_status":code,
"request_id"}`. `400` out of range or non-numeric.

### GET /lab/response-marker
`200` `text/plain` with the fixed body `LAB_RESPONSE_MARKER_7f3a\n` and
an `X-Lab-Marker` header with the same marker, for response-inspection
tests.

### GET /lab/large?bytes=N
`200` `text/plain` with exactly N bytes `A` (0 to `MAX_LARGE_BYTES`).
`400` out of range or non-numeric.

### GET /lab/headers
`200` JSON listing the headers fixed on the response:
`X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`,
`Referrer-Policy: no-referrer`, `Content-Security-Policy: default-src
'none'; frame-ancestors 'none'`, `Strict-Transport-Security:
max-age=31536000; includeSubDomains`,
`X-Permitted-Cross-Domain-Policies: none`,
`X-Lab-Static-Header: set-by-lab`.

### GET /lab/stream
`200` `text/plain` with `Transfer-Encoding: chunked`: five parts
`lab-stream-chunk-N-of-5` sent every 100 ms, written manually over the
connection (veb connection takeover; there is no native response
streaming API in this version).

### GET /lab/calls (protected)
Requires `X-Lab-Token: <LAB_ADMIN_TOKEN>` or
`Authorization: Bearer <token>`. `200` with
`{"count","capacity":200,"calls":[...]}` in chronological order; each
call: `{"request_id","x_test_case","method","path","route","status",
"timestamp"}`. Without a token: `401`; wrong token: `403`; without
`LAB_ADMIN_TOKEN` configured: `404` `lab_calls_disabled`. This is the
proof of what reached the backend.

### POST /lab/calls/reset (protected)
Same protection. `200` `{"reset":true,"dropped":N,"request_id"}`.
