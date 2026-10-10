#!/usr/bin/env bash
# auth.sh: synthetic login/logout/me flow.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start_server

http POST /api/v1/auth/login -H 'Content-Type: application/json' \
	-d '{"username":"admin","password":"lab-password-123456"}'
expect_status smoke 200 'login with the seeded credentials'
expect_body_contains smoke '"token_type":"Bearer"' 'login answers a Bearer token'
expect_body_contains smoke '"username":"admin"' 'login answers the username'
expect_body_not_contains smoke 'lab-password-123456' 'login response never echoes the password'
TOKEN="$(grep -o '"token":"[^"]*"' <<<"$BODY" | head -n 1 | cut -d'"' -f4)"

http GET /api/v1/auth/me -H "Authorization: Bearer $TOKEN"
expect_status smoke 200 'GET /auth/me with a valid token'
expect_body_contains smoke '"username":"admin"' 'me answers the synthetic profile'

http POST /api/v1/auth/logout -H "Authorization: Bearer $TOKEN"
expect_status smoke 200 'logout with a valid token'
expect_body_contains smoke '"logged_out":true' 'logout confirms revocation'

http GET /api/v1/auth/me -H "Authorization: Bearer $TOKEN"
expect_status errors 401 'me with a revoked token is 401'

http POST /api/v1/auth/login -H 'Content-Type: application/json' \
	-d '{"username":"admin","password":"wrong-password"}'
expect_status errors 401 'login with a wrong password is 401'
expect_body_contains errors '"code":"invalid_credentials"' 'wrong credentials use the invalid_credentials code'

http POST /api/v1/auth/login -H 'Content-Type: application/json' -d '{"username":"admin"}'
expect_status errors 422 'login without password is 422'

http POST /api/v1/auth/login -H 'Content-Type: application/json' -d '{broken'
expect_status errors 400 'login with invalid JSON is 400'

http POST /api/v1/auth/login -H 'Content-Type: text/plain' -d '{"username":"a","password":"b"}'
expect_status errors 415 'login with a non-JSON content type is 415'

http GET /api/v1/auth/me
expect_status errors 401 'me without a token is 401'

http GET /api/v1/auth/me -H 'Authorization: Bearer vhl-not-a-real-token'
expect_status errors 401 'me with an unknown token is 401'

http POST /api/v1/auth/logout
expect_status errors 401 'logout without a token is 401'

summary
