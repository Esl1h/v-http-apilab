# Testing with v-http-lab

How to exercise the simulated API and use the built-in testing
utilities. The project is agnostic: it serves as a deterministic
upstream for any integration lab, proxy or testing tool.

## Starting and calling the API

```sh
./scripts/build.sh
./scripts/run.sh                 # listens on 0.0.0.0:8080
curl http://127.0.0.1:8080/health
```

Interactive documentation: `http://127.0.0.1:8080/docs` (Swagger UI; the
interface assets come from a CDN). Raw specification:
`http://127.0.0.1:8080/openapi.json` (OpenAPI 3.0.3, also embedded in
the binary).

## Proof of receipt: X-Test-Case + /lab/calls

Every request that reaches the process is recorded in an in-memory
buffer (the last 200 requests). This makes it verifiable whether a
request reached the backend or was cut off before it (for example by a
proxy, load balancer, firewall, timeout or network error).

1. Start with a lab token:

```sh
LAB_ADMIN_TOKEN=lab-secret ./scripts/run.sh
```

2. Label each request of the test case with a unique header:

```sh
curl -H 'X-Test-Case: case-42-select-query' \
     'http://127.0.0.1:8080/api/v1/search?q=security'
```

3. Inspect the buffer:

```sh
curl -H 'X-Lab-Token: lab-secret' http://127.0.0.1:8080/lab/calls | \
  jq '.calls[] | select(.x_test_case == "case-42-select-query")'
```

Interpretation:

- Entry present: the request reached the backend (with the real
  `status` and `route`, plus the `request_id`).
- Entry absent: the request did not arrive. The absence proves the
  backend never saw it; to find out who cut it off, cross-check with
  the logs of the intermediary under test (anything counts: proxy,
  load balancer, firewall, timeout or network error).

Between rounds:

```sh
curl -X POST -H 'X-Lab-Token: lab-secret' http://127.0.0.1:8080/lab/calls/reset
```

Without `LAB_ADMIN_TOKEN` configured, the `/lab/calls*` endpoints answer
404 (disabled).

## Size limits across layers

The body of a request crosses up to three distinct limits, and it is
important to know which one answered:

1. Intermediary (if any): proxies and load balancers usually limit the
   body; the backend never sees the request.
2. veb/fasthttp backend: refuses while framing bodies above 64 MiB and
   headers above 16 KiB (generic 413/431, without JSON and without a
   request log; the connection is closed).
3. Application (`MAX_BODY_BYTES`, default 1 MiB): 413 with the JSON
   error envelope, with a log entry and a record in `/lab/calls`.

## Matrix: endpoint x test type

| Endpoint | What it exercises |
| --- | --- |
| `/lab/method` (7 methods; TRACE and others fall into 405+Allow) | allowed HTTP methods and denial of exotic methods |
| `/admin/status`, `/admin/config`, `/internal/debug`, `/static/*` | access control by path |
| `/api/v1/users` (POST/PUT/PATCH), `/api/v1/tickets`, `/api/v1/graphql`, `/admin/config` | JSON payload validation and escaping |
| `/api/v1/forms/feedback` | `application/x-www-form-urlencoded` payload |
| `/api/v1/files/upload` | multipart: size, missing part, traversal-looking filename, Content-Type |
| `/static/{name}`, `/static/..%5C...` | path traversal and normalization |
| `/api/v1/search?q=...`, `/lab/echo?...` | the same payload in distinct positions (query string) |
| `/api/v1/auth/login` | credentials in JSON, Bearer tokens, password leakage in response/log |
| `/lab/response-marker`, `/lab/headers` | response inspection and rewriting (marker and fixed headers) |
| `/lab/large?bytes=N` and POST with a large body | size limits per layer |
| `/lab/slow?ms=N` | timeouts (the request may expire on the client and still appear in `/lab/calls`) |
| `/lab/status/{code}` | upstream error-code handling |
| `/lab/stream` | response in parts (chunked) |
| any endpoint under load | counters in `/metrics` and `/internal/debug` to reconcile volume |
| `/api/v1/webhooks/receive` | arbitrary payloads without echo; proof of receipt via SHA-256 |

## Recommended flow of one round

1. `POST /lab/calls/reset`.
2. Fire the cases, each with a unique `X-Test-Case`.
3. `GET /lab/calls` and cross-check with the intermediary logs.
4. `GET /metrics` for the aggregated view (counters by route/status).
5. Repeat with another configuration: the synthetic data is
   deterministic, so the difference between rounds comes only from
   whatever is under test.
