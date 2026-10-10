#!/usr/bin/env bash
# tickets-forms.sh: synthetic tickets and the urlencoded feedback form.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start_server

http POST /api/v1/tickets -H 'Content-Type: application/json' \
	-d '{"title":"Synthetic smoke ticket","description":"created by tests","severity":"medium","tags":["lab","synthetic"]}'
expect_status smoke 201 'create a ticket'
expect_body_contains smoke '"severity":"medium"' 'the ticket echoes its severity'
expect_body_contains smoke '"tags":["lab","synthetic"]' 'the ticket echoes its tags'
CREATED_ID="$(grep -o '"id":[0-9]*' <<<"$BODY" | head -n 1 | cut -d: -f2)"

http GET "/api/v1/tickets/$CREATED_ID"
expect_status smoke 200 'show the created ticket'

http GET /api/v1/tickets/1
expect_status smoke 200 'show a seeded ticket'
expect_body_contains smoke '"severity":"low"' 'the seeded ticket is returned'

http POST /api/v1/forms/feedback -H 'Content-Type: application/x-www-form-urlencoded' \
	-d 'rating=5&name=tester&comment=great+synthetic+lab'
expect_status smoke 200 'submit the urlencoded feedback form'
expect_body_contains smoke '"received":true' 'feedback confirms receipt'
expect_body_contains smoke '"rating":5' 'feedback echoes the rating'
expect_body_contains smoke '"comment":"great synthetic lab"' 'feedback echoes the comment (url-decoded)'

http POST /api/v1/tickets -H 'Content-Type: application/json' \
	-d '{"title":"X","description":"","severity":"extreme","tags":[]}'
expect_status errors 422 'create a ticket with an invalid severity is 422'
expect_body_contains errors '\"severity\" must be one of low, medium, high, critical' '422 lists the valid severities'

http POST /api/v1/tickets -H 'Content-Type: application/json' \
	-d '{"description":"no title","severity":"low","tags":[]}'
expect_status errors 422 'create a ticket without a title is 422'

http POST /api/v1/tickets -H 'Content-Type: application/json' -d '{broken'
expect_status errors 400 'create a ticket with invalid JSON is 400'

http POST /api/v1/tickets -H 'Content-Type: text/csv' -d 'title,severity'
expect_status errors 415 'create a ticket with a non-JSON content type is 415'

http GET /api/v1/tickets/999
expect_status errors 404 'show an unknown ticket is 404'

http GET /api/v1/tickets/abc
expect_status errors 400 'show a ticket with a non-numeric id is 400'

http POST /api/v1/forms/feedback -H 'Content-Type: application/json' -d '{"rating":5}'
expect_status errors 415 'feedback with a JSON content type is 415'

http POST /api/v1/forms/feedback -H 'Content-Type: application/x-www-form-urlencoded' \
	-d 'name=tester'
expect_status errors 422 'feedback without rating is 422'

http POST /api/v1/forms/feedback -H 'Content-Type: application/x-www-form-urlencoded' \
	-d 'rating=9'
expect_status errors 422 'feedback with rating above 5 is 422'

http POST /api/v1/forms/feedback -H 'Content-Type: application/x-www-form-urlencoded' \
	-d 'rating=abc'
expect_status errors 400 'feedback with a non-numeric rating is 400'

long_title="$(head -c 121 /dev/zero | tr '\0' 'T')"
http POST /api/v1/tickets -H 'Content-Type: application/json' \
	-d "{\"title\":\"$long_title\",\"description\":\"\",\"severity\":\"low\",\"tags\":[]}"
expect_status limits 422 'a title longer than 120 chars is 422'

long_desc="$(head -c 2001 /dev/zero | tr '\0' 'D')"
http POST /api/v1/tickets -H 'Content-Type: application/json' \
	-d "{\"title\":\"ok\",\"description\":\"$long_desc\",\"severity\":\"low\",\"tags\":[]}"
expect_status limits 422 'a description longer than 2000 chars is 422'

http POST /api/v1/tickets -H 'Content-Type: application/json' \
	-d '{"title":"T","description":"","severity":"low","tags":["a","b","c","d","e","f","g","h","i","j","k"]}'
expect_status limits 422 'more than 10 tags is 422'

summary
