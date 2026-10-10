# v-http-lab: deterministic synthetic HTTP API simulator.

.PHONY: build run test test-smoke test-errors test-limits docker-build docker-build-runtime docker-up docker-down fmt clean

build:
	scripts/build.sh

run:
	scripts/run.sh

test: test-smoke test-errors test-limits

test-smoke:
	scripts/test-smoke.sh

test-errors:
	scripts/test-errors.sh

test-limits:
	scripts/test-limits.sh

docker-build:
	docker build -t v-http-lab:latest .

docker-build-runtime:
	docker build -f Dockerfile.runtime -t v-http-lab:latest .

docker-up:
	docker compose up -d --build

docker-down:
	docker compose down

fmt:
	v fmt -w src

clean:
	rm -rf bin
