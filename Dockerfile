# Sogenio "builder" image — single source of truth for every dev/CI binary.
# Consumers: api/pkg/types, api/x/protos, dev shells, CI runners.
# Tagged as both ghcr.io/func-it/builder:latest and ghcr.io/func-it/protoc:latest
# (back-compat alias for one cycle).

FROM golang:1.25

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=$PATH:/go/bin:/usr/local/go/bin

# ---------------------------------------------------------------------------
# host-side dev tools (apt) — unzip/curl/ca-certs for downloads, then a
# kitchen sink of CLIs the dev flow + scripts/preflight.sh expect.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release unzip libc6 \
        jq figlet lsof netcat-openbsd ffmpeg chromium \
        gpg gpg-agent libcap2-bin \
    && ln -sf /usr/bin/chromium /usr/bin/google-chrome \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# protoc 21.0 — arch-aware (legacy image was amd64 only; this build supports
# both linux/amd64 and linux/arm64 via buildx).
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# protoc Go plugins + adjacent codegen tools (versions pinned to legacy image
# so existing pipelines remain bit-identical).
# ---------------------------------------------------------------------------
# Versions bumped from the legacy protoc image to match Go 1.25:
#   gqlgen v0.17.55 → v0.17.76 (matches api/go.mod; older pin pulls
#     golang.org/x/tools@v0.24.0 which fails to compile on Go 1.25
#     with "invalid array length -delta * delta" in tokeninternal.go).
#   grpc-gateway v2.7.3 → v2.25.1 (matches api/go.mod).
#   protoc-gen-go v1.28 → v1.34.2 (newer x/tools required for Go 1.25).
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.34.2 \
 && go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.5.1 \
 && go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@v2.25.1 \
 && go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@v2.25.1 \
 && go install github.com/favadi/protoc-go-inject-tag@latest \
 && go install github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@v2.4.1 \
 && go install github.com/99designs/gqlgen@v0.17.76

# ---------------------------------------------------------------------------
# dev-runtime Go tools — Air hot-reload + Delve debugger + Task runner.
# ---------------------------------------------------------------------------
RUN go install github.com/air-verse/air@latest \
 && go install github.com/go-delve/delve/cmd/dlv@latest \
 && go install github.com/go-task/task/v3/cmd/task@latest

# ---------------------------------------------------------------------------
# yq (mikefarah) — YAML CLI, arch-aware static binary.
# ---------------------------------------------------------------------------
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}"; \
    chmod +x /usr/local/bin/yq

# ---------------------------------------------------------------------------
# HashiCorp Vault CLI — same apt pattern as scripts/preflight.sh.
# ---------------------------------------------------------------------------
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/hashicorp.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends vault \
 && rm -rf /var/lib/apt/lists/* \
 && setcap -r /usr/bin/vault || true

# ---------------------------------------------------------------------------
# Node 20 (NodeSource) — for gqlgen integrations, npm, vite tooling.
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Google API Protos (HEAD of master, same as legacy image).
# ---------------------------------------------------------------------------
RUN curl -fsSL -o /tmp/googleapis.zip \
        https://github.com/googleapis/googleapis/archive/refs/heads/master.zip \
 && unzip /tmp/googleapis.zip -d /usr/local/include \
 && rm /tmp/googleapis.zip

# ---------------------------------------------------------------------------
# Sogenio canonical .proto sources (vendored from api/x/protos/protobuf/).
# Consumers reference `-I/protos` to pick these up.
# ---------------------------------------------------------------------------
COPY protos /protos

WORKDIR /workspace
