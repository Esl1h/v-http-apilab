# v-http-lab

Backend HTTP determinístico, com dados 100% sintéticos, que simula uma API
corporativa interna. Rodando o binário, a porta abre e a API começa a
responder imediatamente: sem banco, sem migrações, sem arquivos de
configuração (reiniciar restaura o estado inicial).

Documentação interativa (Swagger UI) em `/docs` e especificação OpenAPI
3.0.3 embutida no binário em `/openapi.json`.

> **Aviso**: ferramenta de laboratório. Não é um template de produção, não é
> segura como aplicação real e não deve ser exposta a redes não controladas.
> A autenticação é simulada, os dados são sintéticos e nada é persistido.

## Versão do compilador e módulo HTTP

| Item | Valor fixado |
| --- | --- |
| Linguagem | V (vlang), commit `c6bb06f5c04d78f9f6d22a57c257d27e835ba40a` |
| Auto-identificação | `V 0.5.2 c6bb06f` (master, posterior à tag 0.5.2) |
| Módulo HTTP | `veb` (vlib; único framework web da vlib nesta versão) |
| Backend de rede | `veb` usa o backend `fasthttp` multi-thread desta versão |
| Dependências externas | nenhuma (somente vlib: veb, net.http, json2, sync, crypto, rand, os, strconv, strings, time) |

Justificativas:

1. `vweb` foi **removido** da vlib nesta versão; `veb` é o sucessor mantido.
2. `net.http` é voltado ao cliente HTTP; o servidor (`net.http` server) não
   expõe roteamento e é usado internamente por outras ferramentas. `veb` dá
   roteamento, contexto, multipart e takeover de conexão.
3. O pin é por commit (a tag `0.5.2` está 2405 commits atrás do compilador
   usado aqui); o Dockerfile reproduz exatamente este commit.

## Build e execução (local)

Requisitos: um compilador V no commit citado (veja abaixo), `curl`, `bash`.

```sh
./scripts/build.sh      # compila bin/v-http-lab (grava a versão do V no binário)
./scripts/run.sh        # sobe o servidor (PORT=8080 por padrão)
```

Exemplos:

```sh
PORT=9090 scripts/run.sh
LAB_ADMIN_TOKEN=meu-token scripts/run.sh   # habilita /lab/calls
READY_FORCE_FAIL=1 scripts/run.sh          # /ready passa a responder 503
```

Documentação ao vivo:

- `http://localhost:8080/docs`: Swagger UI (recursos da interface via CDN;
  a API em si é autocontida).
- `http://localhost:8080/openapi.json`: especificação OpenAPI 3.0.3
  (o arquivo fonte é `src/openapi/openapi.json`, embutido no binário).

Como instalar o compilador V fixado (mesmo método do Dockerfile):

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
docker run --rm -p 8080:8080 -e LAB_ADMIN_TOKEN=meu-token v-http-lab:latest
# ou
docker compose up -d
```

A imagem é multi-stage: o builder clona o compilador V no commit fixado, e o
runtime é `debian:bookworm-slim` (o binário é dinâmico, linkado à glibc;
`ldd` no Dockerfile e no build comprovam as dependências). O processo roda
como usuário não-root (uid 10001) e há um `HEALTHCHECK` apontando para
`/health`.

## Releases e imagem de runtime (binário, sem compilar)

Cada tag `v*` dispara o workflow `.github/workflows/release.yml`: ele
compila com o mesmo toolchain fixado (estágio `builder` do Dockerfile),
testa o binário e o anexa ao release do GitHub junto com `SHA256SUMS`.

```sh
gh release download v1.0.0 --repo Esl1h/v-http-lab   # v-http-lab-linux-amd64 + SHA256SUMS
sha256sum -c SHA256SUMS
./v-http-lab-linux-amd64
```

O binário é dinâmico, linkado à glibc (compilado em Debian bookworm,
glibc 2.36): use em distribuições com glibc >= 2.36 ou na imagem
`debian:bookworm-slim`.

Para um Docker que não compila nada, use a imagem de runtime, que baixa o
binário do release fixado por tag e checksum (build em segundos):

```sh
docker build -f Dockerfile.runtime -t v-http-lab:latest .
docker run --rm -p 8080:8080 v-http-lab:latest
```

`Dockerfile` (compila do código com o toolchain fixado) e
`Dockerfile.runtime` (usa o binário do release com verificação de
integrity) produzem o mesmo servidor; escolha conforme preferir
reprodutibilidade total do build ou velocidade.

## Endpoints

Resumo; contrato completo em `docs/endpoints.md`.

| Grupo | Endpoint | Método | Descrição |
| --- | --- | --- | --- |
| Infra | `/health` | GET | liveness |
| Infra | `/ready` | GET | readiness (forçável para 503) |
| Infra | `/version` | GET | versões do app e do V + build |
| Infra | `/metrics` | GET | texto Prometheus |
| Docs | `/openapi.json` | GET | especificação OpenAPI 3.0.3 embutida |
| Docs | `/docs` | GET | Swagger UI |
| Auth | `/api/v1/auth/login` | POST | credenciais sintéticas fixas |
| Auth | `/api/v1/auth/logout` | POST | revoga o token |
| Auth | `/api/v1/auth/me` | GET | perfil sintético (Bearer) |
| Users | `/api/v1/users` | GET/POST | lista paginada / criação |
| Users | `/api/v1/users/{id}` | GET/PUT/PATCH/DELETE | CRUD |
| Busca | `/api/v1/search?q=&limit=` | GET | busca no corpus sintético |
| Relatórios | `/api/v1/reports` | GET | catálogo sintético |
| Relatórios | `/api/v1/reports/export` | POST | cria job sintético |
| Relatórios | `/api/v1/reports/{id}/download` | GET | CSV sintético |
| Tickets | `/api/v1/tickets` | POST | cria ticket |
| Tickets | `/api/v1/tickets/{id}` | GET | consulta ticket |
| Forms | `/api/v1/forms/feedback` | POST | application/x-www-form-urlencoded |
| Integrações | `/api/v1/webhooks/receive` | POST | resumo (tamanho, chaves, sha256) |
| Integrações | `/api/v1/graphql` | POST | stub documentado (não executa GraphQL) |
| Arquivos | `/api/v1/files/upload` | POST | multipart ou octet-stream (não grava em disco) |
| Arquivos | `/static/{name}` | GET | allowlist embutida (traversal rejeitado) |
| Admin | `/admin/status` | GET | contadores não sensíveis |
| Admin | `/admin/config` | POST | eco validado, nada é aplicado |
| Admin | `/internal/debug` | GET | dados não sensíveis |
| Lab | `/lab/echo` | GET | reflete método/path/query/headers permitidos |
| Lab | `/lab/method` | GET/HEAD/POST/PUT/PATCH/DELETE/OPTIONS | informa o método recebido |
| Lab | `/lab/slow?ms=` | GET | atraso configurável |
| Lab | `/lab/status/{code}` | GET | responde o status pedido (200..599) |
| Lab | `/lab/response-marker` | GET | marcador fixo `LAB_RESPONSE_MARKER_7f3a` |
| Lab | `/lab/large?bytes=` | GET | corpo de N bytes |
| Lab | `/lab/headers` | GET | headers customizados e de segurança |
| Lab | `/lab/stream` | GET | resposta em partes (chunked manual) |
| Lab | `/lab/calls` | GET | buffer das últimas requisições (token) |
| Lab | `/lab/calls/reset` | POST | limpa o buffer (token) |

Toda resposta de erro segue:

```json
{"error":{"code":"...","message":"...","request_id":"..."}}
```

`X-Request-ID` é devolvido em toda resposta (usando o valor recebido quando
válido, ou um UUID gerado). O header `X-Test-Case`, quando enviado, é gravado
no log estruturado e no buffer `/lab/calls` para rotular casos de teste.

## Variáveis de ambiente

| Variável | Padrão | Descrição |
| --- | --- | --- |
| `PORT` | `8080` | porta de escuta (bind em `0.0.0.0`) |
| `MAX_BODY_BYTES` | `1048576` | limite de body por requisição (413) |
| `READ_TIMEOUT_MS` | `30000` | timeout de leitura (granularidade de 1s, ver limitações) |
| `LAB_ADMIN_TOKEN` | vazio | protege `/lab/calls*`; vazio desabilita (404) |
| `READY_FORCE_FAIL` | vazio | qualquer valor não vazio força `/ready` a 503 |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn` ou `error` |
| `MAX_SLOW_MS` | `10000` | teto do `/lab/slow?ms=` |
| `MAX_LARGE_BYTES` | `1048576` | teto do `/lab/large?bytes=` |
| `LAB_USERNAME` | `admin` | usuário sintético do login |
| `LAB_PASSWORD` | `lab-password-123456` | senha sintética do login (nunca logada) |

Valores inválidos em qualquer variável abortam o processo com erro explícito.

## Testes

```sh
make test          # executa smoke + errors + limits
./scripts/test-smoke.sh
./scripts/test-errors.sh
./scripts/test-limits.sh
tests/infra.sh     # qualquer grupo isolado (all)
LAB_TEST_MODE=errors tests/users.sh
```

Cada caso imprime `PASS/FAIL` com esperado vs. obtido; qualquer FAIL encerra
com código de saída não zero. Sem `BASE_URL` definida, cada grupo sobe um
servidor novo em `18080` (estado limpo). Com `BASE_URL`, roda contra um
servidor externo.

## Logs

Uma linha JSON por requisição em stdout: `timestamp`, `request_id`, `method`,
`path`, `query` (valores sensíveis mascarados como `[REDACTED]`), `status`,
`duration_ms`, `route`, `remote_addr`, `user_agent`, `content_length`,
`content_type`, `x_forwarded_for`, `x_test_case`.

Nunca são logados ou refletidos: `Authorization`, `Cookie`, `Set-Cookie`,
senhas ou tokens. Filtragem de linhas não JSON (as duas linhas de startup do
veb, ver limitações): `grep '^{'`.

## Limitações conhecidas (honestidade operacional)

1. **Corpo até 64 MiB é lido pelo backend antes do app**: `MAX_BODY_BYTES` é
   aplicado na camada da aplicação (413 JSON) depois da leitura; corpos acima
   de 64 MiB são recusados pelo próprio backend veb/fasthttp com um 413
   genérico (sem JSON, sem log). Detalhes em `docs/testing.md`.
2. **Headers acima de 16 KiB** são recusados pelo backend com 431 (antes de
   qualquer lógica da aplicação).
3. **READ_TIMEOUT_MS tem granularidade de 1 segundo** (limite do
   `RunParams.timeout_in_seconds` do veb; mínimo efetivo 1s).
4. **O veb imprime duas linhas de startup não JSON** em stdout
   (`[veb] Running multi-threaded app...` e `listening on ...`); não há como
   desabilitá-las nesta versão.
5. **Streaming é manual**: `/lab/stream` é escrito com enquadramento chunked
   próprio sobre o takeover da conexão; o veb não expõe API de streaming de
   resposta nesta versão. Funciona (testado), mas é implementação própria.
6. **Path traversal com dot-segments** (`/static/..%2f..`) é normalizado pelo
   parser de URL (RFC 3986) antes do roteamento; a requisição nunca alcança a
   allowlist. Traversal com barras invertidas e afins, que chegam ao handler,
   recebem 400 explícito (`path_traversal_rejected`).
7. **Porta em uso**: o veb pergunta no stdin se deve matar o processo que
   ocupa a porta; sem stdin (Docker) ele responde `<EOF>`, não mata nada e o
   processo sai com erro de bind.
8. **Determinismo**: dados e respostas do seed são determinísticos; tokens de
   sessão e ids de job (`job-N`) são gerados em memória e somem no restart.

## Estrutura do repositório

```
v-http-lab/
├── Dockerfile               build multi-stage com o compilador fixado por commit
├── Dockerfile.runtime       imagem que usa o binário do release (com checksum)
├── docker-compose.yml       backend isolado para teste local
├── Makefile                 atalhos (build, run, test, docker, fmt, clean)
├── .github/workflows/       release.yml: tag v* -> binário + SHA256SUMS no release
├── v.mod                    módulo (base_url: src)
├── scripts/                 build.sh, run.sh, test-smoke.sh, test-errors.sh, test-limits.sh
├── tests/                   lib.sh + grupos: infra, auth, users, search-reports,
│                            tickets-forms, webhooks, files, lab
├── docs/                    endpoints.md (contrato) e testing.md (como testar)
└── src/                     um módulo por responsabilidade:
    ├── main.v               entrada: config, rotas, server
    ├── config/              variáveis de ambiente
    ├── seed/                dados sintéticos determinísticos (usuários, relatórios...)
    ├── requestid/           resolução do X-Request-ID
    ├── logging/             log estruturado e mascaramento
    ├── state/               estado em memória com mutex (users, tickets, sessões,
    │                        jobs, métricas, buffer de calls)
    ├── router/              App/Context veb, dispatch, 405+Allow, envelope de erro
    ├── openapi/             spec OpenAPI embutida ($embed_file) + Swagger UI
    ├── infra/               health, ready, version
    ├── auth/                login/logout/me sintéticos
    ├── users/               CRUD de usuários
    ├── search/              busca sintética
    ├── reports/             relatórios, export e CSV
    ├── tickets/             tickets
    ├── forms/               form urlencoded
    ├── webhooks/            receive + stub graphql
    ├── admin/               status, config (eco), debug
    ├── files/               upload multipart/octet-stream + allowlist /static
    ├── lab/                 utilitários de teste
    └── metrics/             /metrics Prometheus
```

## Segurança do próprio backend

Entradas nunca são executadas nem interpretadas (não há SQL, shell ou
eval): são apenas validadas e devolvidas com escape JSON correto. Não há
acesso a disco além da leitura do binário (uploads são analisados em
memória). Sem banco de dados: reiniciar o processo restaura o seed.
