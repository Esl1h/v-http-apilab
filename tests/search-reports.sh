#!/usr/bin/env bash
# search-reports.sh: search, report listing, export jobs and CSV download.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start_server

http GET '/api/v1/search?q=security&limit=5'
expect_status smoke 200 'search for security'
expect_body_contains smoke '"query":"security"' 'the query is echoed'
expect_body_contains smoke '"type":"user"' 'search hits the synthetic users'

http GET '/api/v1/search?q=runbook&limit=2'
expect_status smoke 200 'search for a synthetic document'
expect_body_contains smoke '"type":"document"' 'search hits the synthetic documents'

http GET /api/v1/reports
expect_status smoke 200 'list reports'
expect_body_contains smoke '"count":6' 'the report catalog has 6 entries'

http POST /api/v1/reports/export -H 'Content-Type: application/json' \
	-d '{"report_id":"rep-001","format":"csv"}'
expect_status smoke 202 'export a report (202 accepted)'
expect_body_contains smoke '"status":"queued"' 'export answers a queued synthetic job'
expect_body_contains smoke '"job_id":"job-' 'export answers a deterministic job id'

http GET /api/v1/reports/rep-003/download
expect_status smoke 200 'download a report as CSV'
expect_header_contains smoke 'Content-Type: text/csv' 'download is text/csv'
expect_header_contains smoke 'Content-Disposition: attachment' 'download sets Content-Disposition'
expect_body_contains smoke 'Region 1,synthetic_rep-003_1,7' 'the CSV content is synthetic and deterministic'

http GET '/api/v1/search'
expect_status errors 422 'search without q is 422'

long_query="$(head -c 257 /dev/zero | tr '\0' 'q')"
http GET "/api/v1/search?q=$long_query"
expect_status errors 400 'a query longer than 256 chars is 400'

http GET '/api/v1/search?q=lab&limit=0'
expect_status errors 422 'limit below 1 is 422'

http GET '/api/v1/search?q=lab&limit=51'
expect_status limits 422 'limit above 50 is 422'

http GET '/api/v1/search?q=lab&limit=abc'
expect_status errors 400 'a non-numeric limit is 400'

http POST /api/v1/reports/export -H 'Content-Type: application/json' \
	-d '{"report_id":"rep-999","format":"csv"}'
expect_status errors 404 'export an unknown report is 404'

http POST /api/v1/reports/export -H 'Content-Type: application/json' \
	-d '{"report_id":"rep-001","format":"pdf"}'
expect_status errors 422 'export with an unsupported format is 422'

http POST /api/v1/reports/export -H 'Content-Type: application/json' -d '{"report_id":"rep-001"}'
expect_status errors 422 'export without format is 422'

http GET /api/v1/reports/rep-999/download
expect_status errors 404 'download an unknown report is 404'

http GET /api/v1/reports/rep-001/download -X DELETE
expect_status errors 405 'DELETE on a report download is 405'

summary
