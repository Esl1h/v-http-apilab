# syntax=docker/dockerfile:1

# v-http-lab image.
#
# The builder compiles with the V toolchain pinned to an exact commit of
# https://github.com/vlang/v. The binary is dynamically linked against
# glibc (libm, libc), so the runtime stage must ship a compatible glibc:
# both stages use Debian bookworm (glibc 2.36). The `ldd` call below
# documents the actual runtime dependencies; do not switch the runtime
# image to alpine/scratch without re-checking it.

ARG V_COMMIT=c6bb06f5c04d78f9f6d22a57c257d27e835ba40a

# ---- builder: fetch the pinned V toolchain and compile ----
FROM debian:bookworm AS builder
ARG V_COMMIT

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates curl gcc git make libc6-dev \
	&& rm -rf /var/lib/apt/lists/*

# Shallow-fetch the exact compiler commit (self-reported "V 0.5.2 c6bb06f").
RUN git init -q /opt/vlang \
	&& git -C /opt/vlang remote add origin https://github.com/vlang/v.git \
	&& git -C /opt/vlang fetch -q --depth 1 origin "${V_COMMIT}" \
	&& git -C /opt/vlang checkout -q FETCH_HEAD

WORKDIR /opt/vlang
RUN make -j"$(nproc)" \
	&& ./v version \
	&& ln -s /opt/vlang/v /usr/local/bin/v

WORKDIR /src
COPY v.mod ./
COPY src ./src

# Bake the toolchain version into /version (read at compile time) and
# verify the produced binary's dynamic dependencies before choosing the
# runtime image (expected: libm.so.6 and libc.so.6 on glibc).
RUN mkdir -p /out \
	&& V_VERSION="$(v version)" v -prod . -o /out/v-http-lab \
	&& echo '--- ldd of the final binary:' \
	&& ldd /out/v-http-lab

# ---- runtime: glibc userland, non-root user, curl for HEALTHCHECK ----
FROM debian:bookworm-slim AS runtime

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl \
	&& rm -rf /var/lib/apt/lists/* \
	&& useradd --uid 10001 --system --no-create-home vhttplab

COPY --from=builder /out/v-http-lab /app/v-http-lab

USER 10001:10001
ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
	CMD curl -fsS "http://127.0.0.1:${PORT:-8080}/health" || exit 1

ENTRYPOINT ["/app/v-http-lab"]
