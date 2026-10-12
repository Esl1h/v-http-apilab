# v-http-lab

Deterministic HTTP backend with 100% synthetic data that simulates an
internal corporate API. It also serves as the upstream in a WAF testing
lab (NGINX + Coraza + OWASP CRS). Run the binary and the port opens
immediately: no database, no migrations, no config files (restarting
restores the initial state).

Interactive documentation (Swagger UI) at `/docs` and the embedded
OpenAPI 3.0.3 specification at `/openapi.json`.

> **Warning**: lab tool. This is not a production template, it is not
> secure as a real application and must not be exposed to uncontrolled
> networks. Authentication is simulated, data is synthetic and nothing
> is persisted.

## Compiler version and HTTP module

| Item | Pinned value |
| --- | --- |
| Language | V (vlang), commit `c6bb06f5c04d78f9f6d22a57c257d27e835ba40a` |
| Self-identification | `V 0.5.2 c6bb06f` (master, after tag 0.5.2) |
| HTTP module | `veb` (vlib; the only web framework in vlib at this version) |
| Network backend | `veb` uses the multi-threaded `fasthttp` backend of this version |
| External dependencies | none (vlib only: veb, net.http, json2, sync, crypto, rand, os, strconv, strings, time) |

Justifications:

1. `vweb` was **removed** from vlib in this version; `veb` is the
   maintained successor.
2. `net.http` targets the HTTP client; the server (`net.http` server)
   exposes no routing and is used internally by other tools. `veb`
   provides routing, context, multipart and connection takeover.
3. The pin is by commit (tag `0.5.2` is 2405 commits behind the
   compiler used here); the Dockerfile reproduces exactly this commit.

## Build and run (local)

Requirements: a V compiler at the commit above (see below), `curl`,
`bash`.

```sh
./scripts/build.sh      # compiles bin/v-http-lab (records the V version in the binary)
./scripts/run.sh        # starts the server (PORT=8080 by default)
```

Examples:

```sh
PORT=9090 scripts/run.sh
LAB_ADMIN_TOKEN=my-token scripts/run.sh   # enables /lab/calls
READY_FORCE_FAIL=1 scripts/run.sh         # /ready starts answering 503
```

Live documentation:

- `http://localhost:8080/docs`: Swagger UI (UI assets come from a CDN;
  the API itself is self-contained).
- `http://localhost:8080/openapi.json`: OpenAPI 3.0.3 specification
  (source file is `src/openapi/openapi.json`, embedded in the binary).

How to install the pinned V compiler (same method as the Dockerfile):

```sh
git init vlang && cd vlang
git remote add origin https://github.com/vlang/v.git
git fetch --depth 1 origin c6bb06f5c04d78f9f6d22a57c257d27e835ba40a
git checkout FETCH_HEAD
make
```

## Docker

```sh
docker build -t v-http-lab:latest .
docker run --rm -p 8080:8080 -e LAB_ADMIN_TOKEN=my-token v-http-lab:latest
# or
docker compose up -d
```

The image is multi-stage: the builder clones the V compiler at the
pinned commit and the runtime is `debian:bookworm-slim` (the binary is
dynamic, linked against glibc; `ldd` in the Dockerfile and in the build
proves the dependencies). The process runs as a non-root user (uid
10001) and there is a `HEALTHCHECK` pointing at `/health`.

## Releases and runtime image (binary, no compiling)

Every `v*` tag triggers `.github/workflows/release.yml`: it compiles
with the same pinned toolchain (the Dockerfile `builder` stage), smoke
tests the binary and attaches it to the GitHub release together with
`SHA256SUMS`.

```sh
gh release download v1.0.0 --repo Esl1h/v-http-lab   # v-http-lab-linux-amd64 + SHA256SUMS
sha256sum -c SHA256SUMS
./v-http-lab-linux-amd64
```

The binary is dynamic, linked against glibc (built on Debian bookworm,
glibc 2.36): use it on distributions with glibc >= 2.36 or on the
`debian:bookworm-slim` image.

For a Docker image that compiles nothing, use the runtime image, which
downloads the release binary pinned by tag and checksum (builds in
seconds):

```sh
docker build -f Dockerfile.runtime -t v-http-lab:latest .
docker run --rm -p 8080:8080 v-http-lab:latest
```

`Dockerfile` (compiles from source with the pinned toolchain) and
`Dockerfile.runtime` (uses the release binary with integrity
verification) produce the same server; choose full build
reproducibility or speed.

## Endpoints

Summary; the full contract is in `docs/endpoints.md`.

| Group | Endpoint | Method | Description |
| --- | --- | --- | --- |
| Infra | `/health` | GET | liveness |
| Infra | `/ready` | GET | readiness (forceable to 503) |
| Infra | `/version` | GET | app and V versions + build |
| Infra | `/metrics` | GET | Prometheus text |
| Docs | `/openapi.json` | GET | embedded OpenAPI 3.0.3 spec |
| Docs | `/docs` | GET | Swagger UI |
| Auth | `/api/v1/auth/login` | POST | fixed synthetic credentials |
| Auth | `/api/v1/auth/logout` | POST | revokes the token |
| Auth | `/api/v1/auth/me` | GET | synthetic profile (Bearer) |
| Users | `/api/v1/users` | GET/POST | paginated list / creation |
| Users | `/api/v1/users/{id}` | GET/PUT/PATCH/DELETE | CRUD |
| Search | `/api/v1/search?q=&limit=` | GET | search over the synthetic corpus |
| Reports | `/api/v1/reports` | GET | synthetic catalog |
| Reports | `/api/v1/reports/export` | POST | creates a synthetic job |
| Reports | `/api/v1/reports/{id}/download` | GET | synthetic CSV |
| Tickets | `/api/v1/tickets` | POST | creates a ticket |
| Tickets | `/api/v1/tickets/{id}` | GET | fetches a ticket |
| Forms | `/api/v1/forms/feedback` | POST | application/x-www-form-urlencoded |
| Integrations | `/api/v1/webhooks/receive` | POST | summary (size, keys, sha256) |
| Integrations | `/api/v1/graphql` | POST | documented stub (does not run GraphQL) |
| Files | `/api/v1/files/upload` | POST | multipart or octet-stream (never written to disk) |
| Files | `/static/{name}` | GET | embedded allowlist (traversal rejected) |
| Admin | `/admin/status` | GET | non-sensitive counters |
| Admin | `/admin/config` | POST | validated echo, nothing applied |
| Admin | `/internal/debug` | GET | non-sensitive data |
| Lab | `/lab/echo` | GET | reflects method/path/query/allowed headers |
| Lab | `/lab/method` | GET/HEAD/POST/PUT/PATCH/DELETE/OPTIONS | reports the received method |
| Lab | `/lab/slow?ms=` | GET | configurable delay |
| Lab | `/lab/status/{code}` | GET | answers the requested status (200..599) |
| Lab | `/lab/response-marker` | GET | fixed marker `LAB_RESPONSE_MARKER_7f3a` |
| Lab | `/lab/large?bytes=` | GET | N-byte body |
| Lab | `/lab/headers` | GET | custom and security headers |
| Lab | `/lab/stream` | GET | response in parts (manual chunked) |
| Lab | `/lab/calls` | GET | buffer of the last requests (token) |
| Lab | `/lab/calls/reset` | POST | clears the buffer (token) |

Every error response follows:

```json
{"error":{"code":"...","message":"...","request_id":"..."}}
```

`X-Request-ID` is returned in every response (using the received value
when valid, or a generated UUID). The `X-Test-Case` header, when sent,
is recorded in the structured log and in the `/lab/calls` buffer to
label test cases.

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `8080` | listening port (binds `0.0.0.0`) |
| `MAX_BODY_BYTES` | `1048576` | per-request body limit (413) |
| `READ_TIMEOUT_MS` | `30000` | read timeout (1 s granularity, see limitations) |
| `LAB_ADMIN_TOKEN` | empty | protects `/lab/calls*`; empty disables them (404) |
| `READY_FORCE_FAIL` | empty | any non-empty value forces `/ready` to 503 |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn` or `error` |
| `MAX_SLOW_MS` | `10000` | ceiling for `/lab/slow?ms=` |
| `MAX_LARGE_BYTES` | `1048576` | ceiling for `/lab/large?bytes=` |
| `LAB_USERNAME` | `admin` | synthetic login username |
| `LAB_PASSWORD` | `lab-password-123456` | synthetic login password (never logged) |

Invalid values in any variable abort the process with an explicit
error.

## Tests

```sh
make test          # runs smoke + errors + limits
./scripts/test-smoke.sh
./scripts/test-errors.sh
./scripts/test-limits.sh
tests/infra.sh     # any isolated group (all)
LAB_TEST_MODE=errors tests/users.sh
```

Each case prints `PASS/FAIL` with expected vs. actual; any FAIL exits
non-zero. Without `BASE_URL` set, each group starts a fresh server on
`18080` (clean state). With `BASE_URL`, it runs against an external
server.

## Logs

One JSON line per request on stdout: `timestamp`, `request_id`,
`method`, `path`, `query` (sensitive values masked as `[REDACTED]`),
`status`, `duration_ms`, `route`, `remote_addr`, `user_agent`,
`content_length`, `content_type`, `x_forwarded_for`, `x_test_case`.

Never logged or reflected: `Authorization`, `Cookie`, `Set-Cookie`,
passwords or tokens. Filtering non-JSON lines (the two veb startup
lines, see limitations): `grep '^{'`.

## Known limitations (operational honesty)

1. **Bodies up to 64 MiB are read by the backend before the app**:
   `MAX_BODY_BYTES` is enforced at the application layer (413 JSON)
   after the read; bodies above 64 MiB are refused by the veb/fasthttp
   backend itself with a generic 413 (no JSON, no log). Details in
   `docs/testing.md`.
2. **Headers above 16 KiB** are refused by the backend with 431
   (before any application logic).
3. **READ_TIMEOUT_MS has 1-second granularity** (a `RunParams`
   `timeout_in_seconds` limitation of veb; effective minimum 1 s).
4. **veb prints two non-JSON startup lines** on stdout
   (`[veb] Running multi-threaded app...` and `listening on ...`);
   there is no way to disable them in this version.
5. **Streaming is manual**: `/lab/stream` is written with hand-rolled
   chunked framing over the veb connection takeover; veb exposes no
   response streaming API in this version. It works (tested), but it is
   a custom implementation.
6. **Path traversal with dot segments** (`/static/..%2f..`) is
   normalized by the URL parser (RFC 3986) before routing; the request
   never reaches the allowlist. Traversal with backslashes and the
   like, which reaches the handler, gets an explicit 400
   (`path_traversal_rejected`).
7. **Port already in use**: veb asks on stdin whether to kill the
   process holding the port; without stdin (Docker) it reads `<EOF>`,
   kills nothing and the process exits with a bind error.
8. **Determinism**: seed data and responses are deterministic; session
   tokens and job ids (`job-N`) are generated in memory and disappear
   on restart.

## Repository structure

```
v-http-lab/
├── Dockerfile               multi-stage build with the compiler pinned by commit
├── Dockerfile.runtime       image that uses the release binary (with checksum)
├── docker-compose.yml       isolated backend for local tests
├── Makefile                 shortcuts (build, run, test, docker, fmt, clean)
├── .github/workflows/       release.yml: tag v* -> binary + SHA256SUMS on the release
├── v.mod                    module (base_url: src)
├── scripts/                 build.sh, run.sh, test-smoke.sh, test-errors.sh, test-limits.sh
├── tests/                   lib.sh + groups: infra, auth, users, search-reports,
│                            tickets-forms, webhooks, files, lab
├── docs/                    endpoints.md (contract) and testing.md (how to test)
└── src/                     one module per responsibility:
    ├── main.v               entry point: config, routes, server
    ├── config/              environment variables
    ├── seed/                deterministic synthetic data (users, reports, ...)
    ├── requestid/           X-Request-ID resolution
    ├── logging/             structured logging and masking
    ├── state/               in-memory state behind a mutex (users, tickets,
    │                        sessions, jobs, metrics, calls buffer)
    ├── router/              App/Context veb, dispatch, 405+Allow, error envelope
    ├── openapi/             embedded OpenAPI spec ($embed_file) + Swagger UI
    ├── infra/               health, ready, version
    ├── auth/                synthetic login/logout/me
    ├── users/               user CRUD
    ├── search/              synthetic search
    ├── reports/             reports, export and CSV
    ├── tickets/             tickets
    ├── forms/               urlencoded form
    ├── webhooks/            receive + graphql stub
    ├── admin/               status, config (echo), debug
    ├── files/               multipart/octet-stream upload + /static allowlist
    ├── lab/                 testing utilities
    └── metrics/             /metrics Prometheus
```

## Backend self-security

Inputs are never executed or interpreted (no SQL, shell or eval): they
are only validated and returned with correct JSON escaping. There is no
disk access beyond reading the binary itself (uploads are analyzed in
memory). No database: restarting the process restores the seed.

## Em português (resumo)

Backend HTTP determinístico, com dados 100% sintéticos, que simula uma
API corporativa interna e serve como upstream num laboratório de WAF
(NGINX + Coraza + OWASP CRS). Compilador V fixado por commit
(`c6bb06f5c04d78f9f6d22a57c257d27e835ba40a`, auto-identificado
`V 0.5.2 c6bb06f`), módulo HTTP `veb` e nenhuma dependência externa
(somente vlib).

Uso rápido:

```sh
./scripts/build.sh                        # compila bin/v-http-lab
LAB_ADMIN_TOKEN=meu-token scripts/run.sh  # sobe em 0.0.0.0:8080
curl http://127.0.0.1:8080/health
make test                                 # suíte smoke + errors + limits
```

Prova de chegada (o motivo de existir do `/lab/calls`): suba com
`LAB_ADMIN_TOKEN`, rotule cada requisição de teste com o header
`X-Test-Case` e consulte o buffer. Presença no buffer prova que a
requisição chegou ao backend; ausência prova que ela foi interrompida
antes (por proxy, WAF, firewall, timeout ou erro de rede). Detalhes em
`docs/testing.md`.

Avisos:

- Ferramenta de laboratório; não é segura como aplicação real e não
  deve ser exposta a redes não controladas.
- Existe um port em Rust do mesmo conceito:
  [rs-http-apilab](https://github.com/Esl1h/rs-http-apilab).
- A documentação completa do contrato (`docs/endpoints.md`,
  `docs/testing.md` e a especificação OpenAPI) está em inglês; este
  resumo em português é a visão geral.
