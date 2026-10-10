# Testando com o v-http-lab

Como exercitar a API simulada e usar os utilitários de teste embutidos. O
projeto é agnóstico: serve como upstream determinístico para qualquer
laboratório de integração, proxy ou ferramenta de teste.

## Subindo e batendo na API

```sh
./scripts/build.sh
./scripts/run.sh                 # sobe em 0.0.0.0:8080
curl http://127.0.0.1:8080/health
```

Documentação interativa: `http://127.0.0.1:8080/docs` (Swagger UI; os
recursos da interface vêm de CDN). Especificação bruta:
`http://127.0.0.1:8080/openapi.json` (OpenAPI 3.0.3, também embutida no
binário).

## Prova de chegada: X-Test-Case + /lab/calls

Todo request que chega ao processo é registrado num buffer em memória (as
últimas 200 requisições). Isso permite provar, de forma verificável, se uma
requisição chegou ao backend ou foi interrompida antes (por exemplo por um
proxy, balanceador, firewall, timeout ou erro de rede).

1. Suba com um token de laboratório:

```sh
LAB_ADMIN_TOKEN=lab-secret ./scripts/run.sh
```

2. Rotule cada requisição do caso de teste com um header único:

```sh
curl -H 'X-Test-Case: case-42-select-query' \
     'http://127.0.0.1:8080/api/v1/search?q=security'
```

3. Consulte o buffer:

```sh
curl -H 'X-Lab-Token: lab-secret' http://127.0.0.1:8080/lab/calls | \
  jq '.calls[] | select(.x_test_case == "case-42-select-query")'
```

Interpretação:

- Entrada presente: a requisição chegou ao backend (com `status` e `route`
  reais, além do `request_id`).
- Entrada ausente: a requisição não chegou. A ausência prova que o backend
  não a recebeu; para descobrir quem interrompeu, cruze com os logs do
  intermediário que estiver testando (aqui vale qualquer coisa: proxy,
  balanceador, firewall, timeout ou erro de rede).

Entre rodadas:

```sh
curl -X POST -H 'X-Lab-Token: lab-secret' http://127.0.0.1:8080/lab/calls/reset
```

Sem `LAB_ADMIN_TOKEN` configurada, os endpoints `/lab/calls*` respondem 404
(desabilitados).

## Limites de tamanho em camadas

O corpo de uma requisição atravessa até três limites distintos, e é
importante saber qual deles respondeu:

1. Intermediário (se houver): proxies e balanceadores normalmente limitam o
   corpo; o backend nunca vê a requisição.
2. Backend veb/fasthttp: recusa em enquadramento corpos acima de 64 MiB e
   headers acima de 16 KiB (413/431 genéricos, sem JSON e sem log da
   requisição; a conexão é fechada).
3. Aplicação (`MAX_BODY_BYTES`, padrão 1 MiB): 413 com o envelope JSON de
   erro, com log e registro em `/lab/calls`.

## Matriz: endpoint x tipo de teste

| Endpoint | O que exercita |
| --- | --- |
| `/lab/method` (7 métodos; TRACE e outros caem em 405+Allow) | métodos HTTP permitidos e negação de métodos exóticos |
| `/admin/status`, `/admin/config`, `/internal/debug`, `/static/*` | controle de acesso por path |
| `/api/v1/users` (POST/PUT/PATCH), `/api/v1/tickets`, `/api/v1/graphql`, `/admin/config` | validação e escape de payloads JSON |
| `/api/v1/forms/feedback` | payload `application/x-www-form-urlencoded` |
| `/api/v1/files/upload` | multipart: tamanho, part ausente, filename com traversal, Content-Type |
| `/static/{name}`, `/static/..%5C...` | path traversal e normalização |
| `/api/v1/search?q=...`, `/lab/echo?...` | o mesmo payload em posições distintas (query string) |
| `/api/v1/auth/login` | credenciais em JSON, tokens Bearer, vazamento de senha em resposta/log |
| `/lab/response-marker`, `/lab/headers` | inspeção e reescrita de resposta (marcador e headers fixos) |
| `/lab/large?bytes=N` e POST com corpo grande | limites de tamanho por camada |
| `/lab/slow?ms=N` | timeouts (a requisição pode expirar no cliente e ainda constar em `/lab/calls`) |
| `/lab/status/{code}` | tratamento de códigos de erro do upstream |
| `/lab/stream` | resposta em partes (chunked) |
| qualquer endpoint em rajada | contadores em `/metrics` e `/internal/debug` para conciliar o volume |
| `/api/v1/webhooks/receive` | payloads arbitrários sem eco; prova de recepção por SHA-256 |

## Fluxo recomendado de uma rodada

1. `POST /lab/calls/reset`.
2. Dispare os casos, cada um com um `X-Test-Case` único.
3. `GET /lab/calls` e cruze com os logs dos intermediários.
4. `GET /metrics` para a visão agregada (contadores por rota/status).
5. Repita com outra configuração: os dados sintéticos são determinísticos,
   então a diferença entre rodadas vem apenas do que estiver sob teste.
