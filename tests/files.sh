#!/usr/bin/env bash
# files.sh: multipart/octet-stream upload analysis and the /static allowlist.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start_server

UPLOAD_FILE="$(mktemp /tmp/v-http-apilab-upload.XXXXXX)"
printf 'SYNTHETIC-UPLOAD-CONTENT' >"$UPLOAD_FILE"

http POST /api/v1/files/upload -F "file=@${UPLOAD_FILE};type=application/octet-stream"
expect_status smoke 201 'multipart upload is analyzed'
expect_body_contains smoke '"size":24' 'the upload size is reported'
expect_body_contains smoke '"stored":false' 'uploads are never written to disk'
expect_body_contains smoke '"sha256":"' 'the upload hash is reported'

http POST /api/v1/files/upload -F "file=@${UPLOAD_FILE};filename=../../etc/secret.conf"
expect_status smoke 201 'a traversal-looking filename is sanitized'
expect_body_contains smoke '"filename":"secret.conf"' 'only the safe base name survives'

http POST "/api/v1/files/upload?name=report.pdf" \
	-H 'Content-Type: application/octet-stream' --data-binary "@${UPLOAD_FILE}"
expect_status smoke 201 'octet-stream upload with ?name= is analyzed'
expect_body_contains smoke '"filename":"report.pdf"' 'the octet-stream name is echoed (sanitized)'

http GET /static/robots.txt
expect_status smoke 200 'GET an allowlisted static file'
expect_header_contains smoke 'Content-Type: text/plain' 'robots.txt is text/plain'
expect_body_contains smoke 'User-agent: *' 'robots.txt serves its fixed synthetic content'

http GET /static/style.css
expect_status smoke 200 'GET another allowlisted file'
expect_header_contains smoke 'Content-Type: text/css' 'style.css is text/css'

http GET /static/data.csv
expect_status smoke 200 'GET the synthetic CSV static file'
expect_body_contains smoke 'id,label,value' 'data.csv serves its fixed synthetic content'

http POST /api/v1/files/upload -F 'not-a-file=just-a-field'
expect_status errors 422 'multipart without a "file" part is 422'

http POST /api/v1/files/upload -H 'Content-Type: application/octet-stream' \
	--data-binary "@${UPLOAD_FILE}"
expect_status errors 422 'octet-stream upload without ?name= is 422'

http POST /api/v1/files/upload -H 'Content-Type: text/plain' --data-binary 'x'
expect_status errors 415 'upload with an unsupported content type is 415'

http GET /static/unknown.txt
expect_status errors 404 'a name outside the allowlist is 404'
expect_body_contains errors 'not in the allowlist' 'the 404 explains the allowlist'

http GET '/static/..%5C..%5Cwindows%5Cwin.ini'
expect_status errors 400 'a backslash traversal segment is rejected with 400'
expect_body_contains errors '"code":"path_traversal_rejected"' 'traversal uses the path_traversal_rejected code'

http GET '/static/..'
expect_status errors 200 'dot-segment traversal is normalized by the URL parser (RFC 3986)'
expect_body_contains errors '"name":"v-http-apilab"' 'the normalized path answers the index, never a file'

http POST /static/robots.txt
expect_status errors 405 'POST on a static file is 405'
expect_header_contains errors 'Allow: GET' 'static files answer Allow: GET'

rm -f "$UPLOAD_FILE"

summary
