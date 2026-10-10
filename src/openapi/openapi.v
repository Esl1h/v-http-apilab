// openapi: serves the embedded OpenAPI 3 specification and the Swagger
// UI page.
//
// The spec lives in src/openapi/openapi.json and is embedded into the
// binary at compile time, so /openapi.json works with no files on disk.
// Keep it in sync with the routes registered in src/main.v.
module openapi

import router
import veb

// spec_json serves the OpenAPI document.
pub fn spec_json(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	spec := $embed_file('openapi.json')
	ctx.set_header(.content_type, 'application/json')
	return ctx.text(spec.to_string())
}

// swagger_ui serves a minimal Swagger UI page pointing at /openapi.json.
// The UI assets load from a CDN, so rendering this page needs internet
// access in the browser; the API itself is fully self-contained.
pub fn swagger_ui(mut app router.App, mut ctx router.Context, params []string) veb.Result {
	_ = params
	ctx.set_header(.content_type, 'text/html; charset=utf-8')
	return ctx.text(swagger_html)
}

const swagger_html = '<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <title>v-http-lab API</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@5.17.14/swagger-ui-bundle.js" charset="utf-8"></script>
<script>
  window.addEventListener(\'load\', function () {
    window.ui = SwaggerUIBundle({
      url: \'/openapi.json\',
      dom_id: \'#swagger-ui\',
      deepLinking: true
    });
  });
</script>
</body>
</html>'
