# Sogenio "builder" image — protobuf codegen toolchain, and nothing else.
#
# The ONLY consumers are the two protoc Taskfiles, which each do exactly:
#   docker run --rm ... ghcr.io/func-it/builder:latest protoc ...
#   docker run --rm ... ghcr.io/func-it/builder:latest protoc-go-inject-tag ...
# (api/x/protos/Taskfile.yml + api/pkg/types/Taskfile.yml). Grep the repo:
# nothing FROM-s this image, no compose service uses it, no script execs it.
#
# So it carries protoc + the Go protoc plugins + the googleapis includes +
# the canonical /protos sources — full stop. The host owns Air / Delve / Task
# / Node / Vault / gqlgen (all run from $HOME/go/bin or natively), and the
# prod runtime (api/infra/prod/Dockerfile) ships its own ffmpeg + chromium.
# Bundling any of those here was ~7 GB of dead weight; this slim build is
# protoc-only.
#
# Tagged ghcr.io/func-it/builder:latest (+ protoc:latest back-compat alias).

# --- stage: build the protoc Go plugins as static binaries -------------------
FROM golang:1.25 AS plugins

# Static binaries → they run on the slim final base with no Go toolchain.
ENV CGO_ENABLED=0

# Versions pinned to api/go.mod (Go 1.25 compatible):
#   protoc-gen-go v1.34.2, protoc-gen-go-grpc v1.5.1, grpc-gateway v2.25.1.
# Older pins pull x/tools@v0.24.0 which fails to compile on Go 1.25.
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.34.2 \
 && go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.5.1 \
 && go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@v2.25.1 \
 && go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@v2.25.1 \
 && go install github.com/favadi/protoc-go-inject-tag@latest

# --- stage: download protoc + the googleapis includes ------------------------
FROM debian:bookworm-slim AS download

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

# protoc 21.0 — arch-aware (linux/amd64 + linux/arm64 via buildx). Extracts
# bin/protoc + include/google/protobuf/*.proto (the well-known types protoc
# auto-resolves relative to its own binary) into /usr/local.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) protoc_arch="linux-x86_64" ;; \
        arm64) protoc_arch="linux-aarch_64" ;; \
        *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/protoc.zip \
        "https://github.com/protocolbuffers/protobuf/releases/download/v21.0/protoc-21.0-${protoc_arch}.zip"; \
    unzip /tmp/protoc.zip -d /usr/local; \
    rm /tmp/protoc.zip

# Google API protos (HEAD of master) — consumed via -I/usr/local/include/googleapis-master.
RUN curl -fsSL -o /tmp/googleapis.zip \
        https://github.com/googleapis/googleapis/archive/refs/heads/master.zip \
 && unzip /tmp/googleapis.zip -d /usr/local/include \
 && rm /tmp/googleapis.zip

# --- final stage: slim runtime ----------------------------------------------
FROM debian:bookworm-slim

# protoc (the C++ release binary) dynamically links libstdc++/libgcc.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH=$PATH:/usr/local/bin

# protoc binary + its bundled well-known-type includes (google/protobuf/*)
# + the googleapis include tree.
COPY --from=download /usr/local/bin/protoc /usr/local/bin/protoc
COPY --from=download /usr/local/include/google /usr/local/include/google
COPY --from=download /usr/local/include/googleapis-master /usr/local/include/googleapis-master

# protoc Go plugins — must be on PATH so protoc can exec them as protoc-gen-*.
COPY --from=plugins /go/bin/ /usr/local/bin/

# Canonical .proto sources (vendored from api/x/protos/protobuf/), consumed via -I/protos.
COPY protos /protos

WORKDIR /workspace
