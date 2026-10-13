#!/usr/bin/env bash
# users.sh: user CRUD, pagination and validation.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start_server

http GET '/api/v1/users?page=1&per_page=5'
expect_status smoke 200 'list users first page'
expect_body_contains smoke '"total":25' 'the seed contains 25 synthetic users'
expect_body_contains smoke '"page":1' 'pagination echoes the page'
expect_body_contains smoke '"per_page":5' 'pagination echoes per_page'

http GET '/api/v1/users?department=security'
expect_status smoke 200 'list users filtered by department'
expect_body_contains smoke '"department":"security"' 'filtered list only has the department'

http GET /api/v1/users/1
expect_status smoke 200 'show user 1'
expect_body_contains smoke '"email":"user1@lab.example"' 'user 1 is the seeded synthetic record'

http POST /api/v1/users -H 'Content-Type: application/json' \
	-d '{"name":"Lab Tester","email":"labtester@lab.example","department":"security","role":"viewer"}'
expect_status smoke 201 'create a user'
expect_body_contains smoke '"name":"Lab Tester"' 'the created user echoes its fields'
CREATED_ID="$(grep -o '"id":[0-9]*' <<<"$BODY" | head -n 1 | cut -d: -f2)"

http PUT "/api/v1/users/$CREATED_ID" -H 'Content-Type: application/json' \
	-d '{"name":"Lab Tester II","email":"labtester2@lab.example","department":"security","role":"operator"}'
expect_status smoke 200 'replace the created user (PUT)'
expect_body_contains smoke '"name":"Lab Tester II"' 'PUT updates every field'

http PATCH "/api/v1/users/$CREATED_ID" -H 'Content-Type: application/json' \
	-d '{"role":"admin"}'
expect_status smoke 200 'patch only the role (PATCH)'
expect_body_contains smoke '"role":"admin"' 'PATCH applies the provided field'
expect_body_contains smoke '"name":"Lab Tester II"' 'PATCH keeps the other fields'

http DELETE "/api/v1/users/$CREATED_ID"
expect_status smoke 204 'delete the created user (204, no body)'

http DELETE "/api/v1/users/$CREATED_ID"
expect_status errors 404 'deleting a deleted user is 404'

http GET /api/v1/users/99999
expect_status errors 404 'show an unknown user is 404'

http GET /api/v1/users/abc
expect_status errors 400 'a non-numeric user id is 400'
expect_body_contains errors '"code":"invalid_id"' 'non-numeric id uses the invalid_id code'

http POST /api/v1/users -H 'Content-Type: application/json' \
	-d '{"name":"","email":"not-an-email","department":"x","role":"root"}'
expect_status errors 422 'create with invalid fields is 422'
expect_body_contains errors '\"name\" must be 1..100 characters' '422 reports the name error'
expect_body_contains errors '\"email\" must be a syntactic email' '422 reports the email error'
expect_body_contains errors '\"role\" must be one of admin, operator, viewer' '422 reports the role error'

http POST /api/v1/users -H 'Content-Type: application/json' -d '{broken'
expect_status errors 400 'create with invalid JSON is 400'

http POST /api/v1/users -H 'Content-Type: text/plain' -d '{"name":"x"}'
expect_status errors 415 'create with a non-JSON content type is 415'

http PUT /api/v1/users/99999 -H 'Content-Type: application/json' \
	-d '{"name":"X","email":"x@lab.example","department":"ops","role":"viewer"}'
expect_status errors 404 'replace an unknown user is 404'

http PATCH /api/v1/users/1 -H 'Content-Type: application/json' -d '{"nickname":"x"}'
expect_status errors 422 'patch with an unknown field is 422'

http PATCH /api/v1/users/1 -H 'Content-Type: application/json' -d '{"role":5}'
expect_status errors 422 'patch with a non-string field value is 422'

http DELETE /api/v1/users
expect_status errors 405 'DELETE on the users collection is 405'
expect_header_contains errors 'Allow: GET, POST' 'the collection answers Allow: GET, POST'

http GET '/api/v1/users?page=1&per_page=101'
expect_status limits 422 'per_page above 100 is 422'

http GET '/api/v1/users?page=0&per_page=5'
expect_status limits 422 'page below 1 is 422'

http GET '/api/v1/users?per_page=abc'
expect_status limits 400 'a non-numeric per_page is 400'

http GET '/api/v1/users?page=99999&per_page=5'
expect_status limits 422 'a page beyond the last one is 422'

http GET '/api/v1/users?page=&per_page='
expect_status errors 200 'empty page/per_page fall back to the defaults'
expect_body_contains errors '"per_page":20' 'an empty per_page uses the default 20'

http GET '/api/v1/users?department=none&page=5'
expect_status errors 200 'any page of an empty result set is 200'
expect_body_contains errors '"items":[]' 'an empty result set has no items'

http GET '/api/v1/users?page=99999999999'
expect_status limits 422 'a page beyond 32 bits is out of range, not malformed'

http GET /health
expect_status errors 200 'the server survives the pagination edge cases'

summary
