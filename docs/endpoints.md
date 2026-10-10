# Contrato dos endpoints

Convenções gerais:

- Respostas de sucesso são `application/json`, exceto onde indicado
  (`/metrics`, downloads CSV, arquivos estáticos e os utilitários de texto).
- Toda resposta carrega o header `X-Request-ID`: o valor recebido no header
  de mesmo nome (se válido: 1 a 128 caracteres ASCII imprimíveis) ou um UUID
  v4 gerado. Erros também o incluem no corpo.
- Header opcional `X-Test-Case`: rotula a requisição no log estruturado e no
  buffer `/lab/calls`.
- Toda resposta de erro usa o formato:

```json
{"error":{"code":"...","message":"...","request_id":"..."}}
```

- Códigos transversais: `400` sintaxe inválida, `401` credencial ausente ou
  inválida, `403` credencial conhecida e recusada, `404` rota/recurso
  inexistente, `405` método não permitido (com header `Allow`), `413` corpo
  acima de `MAX_BODY_BYTES`, `415` Content-Type inesperado, `422` corpo
  válido porém semanticamente inválido.
- Métodos não cobertos por rota nenhuma (por exemplo `TRACE`, `PROPFIND`)
  recebem o mesmo tratamento: 405 com `Allow` quando o path existe para
  outro método, ou 404; em ambos os casos a requisição é logada e gravada no
  buffer `/lab/calls`.

## Infra

### GET /health
Liveness. Sempre `200` com `{"status":"ok"}`.

### GET /ready
Readiness. `200` com `{"status":"ready"}`; `503` com `{"status":"unavailable"}`
quando a env `READY_FORCE_FAIL` tem qualquer valor não vazio.

### GET /version
`200` com `{"app","version","v_version","build_date","deterministic_seed"}`.
`v_version` é gravado em tempo de build pelo `scripts/build.sh` e pelo
Dockerfile (`unknown` quando não fornecido). `build_date` vem do comptime
`@BUILD_DATE` (reproduzível com `SOURCE_DATE_EPOCH`).

### GET /metrics
Texto Prometheus (Content-Type `text/plain; version=0.0.4; charset=utf-8`):
`v_http_lab_up`, `v_http_lab_uptime_seconds`, `v_http_lab_build_info` e
`v_http_lab_requests_total{route,status}` por rota (padrão como
`/api/v1/users/:id` ou `unmatched`) e status.

### GET /openapi.json
A especificação OpenAPI 3.0.3 completa desta API, em `application/json`.
O documento (`src/openapi/openapi.json`) é embutido no binário em tempo de
compilação: não há leitura de disco.

### GET /docs
Página HTML com o Swagger UI apontando para `/openapi.json`. Os recursos da
interface (CSS/JS) são carregados de CDN, portanto renderizar a página exige
acesso à internet no navegador; a API em si é autocontida.

## Autenticação (simulada)

### POST /api/v1/auth/login
Body JSON `{"username","password"}`. Erros: `415` sem JSON, `400` JSON
inválido, `422` campo ausente, `401` credenciais erradas (`invalid_credentials`).
Sucesso `200`: `{"token","token_type":"Bearer","expires_in":3600,"username",`
`"request_id"}`. A senha nunca é logada nem devolvida. Credenciais padrão:
`LAB_USERNAME`/`LAB_PASSWORD`.

### POST /api/v1/auth/logout
Exige `Authorization: Bearer <token>`. `200` `{"logged_out":true,...}`;
`401` sem token ou token desconhecido. Body opcional e ignorado.

### GET /api/v1/auth/me
Exige `Authorization: Bearer <token>` válido e não expirado. `200` com o
perfil sintético `{"username","display_name","role","email","request_id"}`;
`401` caso contrário.

## Usuários

### GET /api/v1/users
Query: `page` (default 1, mínimo 1), `per_page` (default 20, 1..100),
`department` (filtro exato opcional). `200` com
`{"page","per_page","total","total_pages","items":[User]}`. Erros: `400`
valores não numéricos, `422` fora dos limites (inclusive página além da
última). `User`: `{"id","name","email","department","role"}`.

### GET /api/v1/users/{id}
`id` numérico positivo. `200` com o usuário; `400` id inválido; `404`
inexistente.

### POST /api/v1/users
Body JSON `{"name" (1..100),"email" (sintaxe user@dominio.tld, até 254),`
`"department" (1..50),"role" (admin|operator|viewer)}`. `201` com o usuário
criado (ids a partir de 26). Erros: `415`, `400`, `422` (todas as falhas de
campo listadas em `message`).

### PUT /api/v1/users/{id}
Substituição completa; mesma validação do POST. `200` com o usuário
atualizado; `404` inexistente; `400/415/422` como no POST.

### PATCH /api/v1/users/{id}
Body JSON com qualquer subconjunto de `name`, `email`, `department`, `role`.
Campos desconhecidos e valores não string são `422`; patch vazio é `422`;
`404` inexistente; `415`/`400` como nos demais.

### DELETE /api/v1/users/{id}
`204` sem corpo em sucesso; `404` inexistente; `400` id inválido.

## Busca

### GET /api/v1/search
Query: `q` (obrigatória, até 256 caracteres) e `limit` (default 10, 1..50).
`200` com `{"query","limit","results":[{"type","id","title"}]}` sobre o corpus
sintético (usuários, relatórios e documentos). Erros: `422` sem `q` ou limites
inválidos, `400` tamanho ou número inválidos.

## Relatórios

### GET /api/v1/reports
`200` `{"count":6,"items":[{"report_id","title","category","rows",`
`"generated_at"}]}` do catálogo fixo `rep-001..rep-006`.

### POST /api/v1/reports/export
Body JSON `{"report_id","format"}` com `format` em `csv|json`. `202` com
`{"job_id":"job-N","status":"queued","report_id","format","request_id"}`.
Erros: `415`, `400`, `422` (campos ausentes/formato inválido), `404`
relatório desconhecido. Nada é realmente executado; o job fica listado em
`/internal/debug`.

### GET /api/v1/reports/{id}/download
`200` com CSV sintético (`text/csv`, `Content-Disposition: attachment`), uma
linha `region,label,value` e `rows` linhas determinísticas. `404` para id
desconhecido.

## Tickets

### POST /api/v1/tickets
Body JSON `{"title" (1..120),"description" (0..2000),"severity"`
`(low|medium|high|critical),"tags" (até 10, cada até 40)}`. `201` com o
ticket (ids a partir de 4; seed tem 3). Erros: `415`, `400`, `422` com todas
as violações listadas.

### GET /api/v1/tickets/{id}
`200` com o ticket; `400` id inválido; `404` inexistente.

## Forms

### POST /api/v1/forms/feedback
Content-Type obrigatório `application/x-www-form-urlencoded`. Campos:
`rating` (inteiro 1..5, obrigatório), `name` (até 100), `comment` (até 500),
`email` (até 254). `200` ecoa os valores com escape JSON correto
`{"received":true,"name","rating","comment","email","request_id"}`. Erros:
`415`, `400` (rating não numérico), `422` (rating ausente/fora da faixa,
campos longos demais).

## Integrações

### POST /api/v1/webhooks/receive
Qualquer Content-Type; body até `MAX_BODY_BYTES`. `200` com o resumo
`{"received_bytes","content_type","json_valid","top_level_keys",`
`"body_sha256","stored":false,"request_id"}`. Chaves de nível superior
(apenas objetos JSON) vêm ordenadas; o conteúdo do body nunca é ecoado.

### POST /api/v1/graphql
Stub documentado; não executa GraphQL. Body JSON
`{"query" (string 1..2048, obrigatória),"variables" (objeto, opcional, até 64`
`chaves)}`. `200` fixo:

```json
{"data":{"lab":"ok"},"errors":[],"extensions":{"query_length":N,
 "variables_count":N,"variables_keys":[...],"request_id":"..."}}
```

Erros: `415`, `400` (JSON inválido), `422` (forma errada).

## Arquivos

### POST /api/v1/files/upload
Aceita `multipart/form-data` (part `file`, não vazia) ou
`application/octet-stream` (com query `?name=`). `201` com
`{"filename" (sanitizado),"size","content_type","sha256","stored":false,`
`"request_id"}`. O nome é reduzido ao basename com apenas `[A-Za-z0-9._-]`
(outros viram `_`; vazio vira `upload.bin`; limite 128). Nada é gravado em
disco. Erros: `415` outro Content-Type, `422` sem part/sem nome/body vazio.

### GET /static/{name}
Serve somente a allowlist embutida: `robots.txt`, `style.css`, `logo.svg`,
`data.csv` (com seus Content-Types e `X-Content-Type-Options: nosniff`).
`404` fora da lista. Segmentos com barra invertida, barra ou NUL recebem
`400` `path_traversal_rejected`; dot-segments (`..`, `%2e%2e`) são
normalizados pelo parser de URL antes do roteamento (nunca alcançam a
allowlist).

## Administração (simulada)

### GET /admin/status
`200` com contadores não sensíveis: `{"mode":"lab","uptime_seconds",`
`"requests_total","users","tickets","sessions","export_jobs"}`.

### POST /admin/config
Body JSON objeto. `200` com `{"valid":true,"applied":false,"received":<eco>,`
`"note":"lab mode: configuration is validated and echoed, never applied",`
`"request_id"}`. Nada é aplicado. Erros: `415`, `400`, `422` (não objeto).

### GET /internal/debug
`200` apenas com dados não sensíveis: versões, `started_at`, uptime e
contadores (incluindo `calls_buffered`).

## Utilitários de laboratório

### GET /lab/echo
`200` com `{"method","path","query" (crua),"headers" (allowlist),`
`"body_bytes","body_sha256","request_id"}`. Allowlist de headers refletidos:
`Host, User-Agent, Accept, Accept-Encoding, Accept-Language, Content-Type,
Content-Length, X-Request-ID, X-Test-Case, X-Forwarded-For, X-Forwarded-Proto`.
`Authorization` e `Cookie` nunca são refletidos; o body nunca é ecoado (apenas
tamanho e hash). Só aceita GET (`405` com `Allow: GET` para os demais).

### /lab/method
Aceita GET, HEAD, POST, PUT, PATCH, DELETE e OPTIONS. `200` com
`{"method","received":true,"allowed":[...],"request_id"}` e header `Allow`
completo. HEAD responde sem corpo com `Content-Length` do corpo equivalente.

### GET /lab/slow?ms=N
Dorme `N` ms (0 a `MAX_SLOW_MS`) e responde `{"slept_ms","max_ms",`
`"request_id"}`. `400` para valores não numéricos ou acima do teto.

### GET /lab/status/{code}
Responde com o status pedido (200..599). 204, 205 e 304 vêm sem corpo; os
demais com `{"requested_status":code,"request_id"}`. `400` fora da faixa ou
não numérico.

### GET /lab/response-marker
`200` `text/plain` com o corpo fixo `LAB_RESPONSE_MARKER_7f3a\n` e header
`X-Lab-Marker` com o mesmo marcador, para testes de inspeção de resposta.

### GET /lab/large?bytes=N
`200` `text/plain` com exatamente N bytes `A` (0 a `MAX_LARGE_BYTES`). `400`
fora da faixa ou não numérico.

### GET /lab/headers
`200` JSON listando os headers fixados na resposta: `X-Frame-Options: DENY`,
`X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
`Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`,
`Strict-Transport-Security: max-age=31536000; includeSubDomains`,
`X-Permitted-Cross-Domain-Policies: none`, `X-Lab-Static-Header: set-by-lab`.

### GET /lab/stream
`200` `text/plain` com `Transfer-Encoding: chunked`: cinco partes
`lab-stream-chunk-N-of-5` enviadas a cada 100 ms, escritas manualmente sobre
a conexão (takeover do veb; sem API de streaming nativa nesta versão).

### GET /lab/calls (protegido)
Exige `X-Lab-Token: <LAB_ADMIN_TOKEN>` ou `Authorization: Bearer <token>`.
`200` com `{"count","capacity":200,"calls":[...]}` em ordem cronológica;
cada call: `{"request_id","x_test_case","method","path","route","status",`
`"timestamp"}`. Sem token: `401`; token errado: `403`; sem `LAB_ADMIN_TOKEN`
configurada: `404` `lab_calls_disabled`. É a prova do que chegou ao backend.

### POST /lab/calls/reset (protegido)
Mesma proteção. `200` `{"reset":true,"dropped":N,"request_id"}`.
