# Modified by PastureStack contributors for independent maintenance and rebranding.

ARG UBUNTU_IMAGE=ubuntu:26.04@sha256:3131b4cc82a783df6c9df078f86e01819a13594b865c2cad47bd1bca2b7063bb
FROM ${UBUNTU_IMAGE} AS tool-builder

ARG GO_VERSION=1.26.5
ARG GO_SHA256_amd64=5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053
ARG YQ_VERSION=v4.53.3
ARG YQ_GIT_COMMIT=1b9b4ac5187171d2e5e3129be0cfa827c7f9d53d
ARG GOMPLATE_VERSION=v5.1.0
ARG GOMPLATE_GIT_COMMIT=0f4c15bc8521939478426bf6ffca4718837b9cb4
ARG DOCKER_VERSION=29.4.2
ARG DOCKER_GIT_COMMIT=055a478ea9010a19d0d4674c0d0e87ade37a4223
ARG DOCKER_SOURCE_DATE_EPOCH=1776697064
ARG UBUNTU_MIRROR=http://archive.ubuntu.com/ubuntu

ENV DEBIAN_FRONTEND=noninteractive \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GOCACHE=/tmp/go-build-cache \
    GOMODCACHE=/tmp/go-mod-cache \
    GOTELEMETRY=off \
    PATH=/usr/local/go/bin:${PATH}

RUN set -eux; \
    find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec sed -i \
        -e "s|http://security.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" \
        -e "s|http://archive.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" {} +; \
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::http::Pipeline-Depth "0";\n' > /etc/apt/apt.conf.d/80pasturestack-retries; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gcc \
        git \
        libc6-dev \
        make \
        tar; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 10 --max-time 300 \
        -o /tmp/go.tgz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"; \
    echo "${GO_SHA256_amd64}  /tmp/go.tgz" | sha256sum -c -; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm -f /tmp/go.tgz; \
    go version

RUN set -eux; \
    mkdir -p /src /out/licenses/yq; \
    git clone --branch "${YQ_VERSION}" --depth 1 https://github.com/mikefarah/yq /src/yq; \
    cd /src/yq; \
    test "$(git rev-parse HEAD)" = "${YQ_GIT_COMMIT}"; \
    go build -trimpath -buildvcs=false -ldflags "-s -w -X github.com/mikefarah/yq/v4/cmd.GitCommit=${YQ_GIT_COMMIT}" -o /out/yq .; \
    cp LICENSE /out/licenses/yq/LICENSE; \
    /out/yq --version; \
    rm -rf /src/yq /tmp/go-build-cache /tmp/go-mod-cache

RUN set -eux; \
    mkdir -p /out/licenses/gomplate; \
    git clone --branch "${GOMPLATE_VERSION}" --depth 1 https://github.com/hairyhenderson/gomplate /src/gomplate; \
    cd /src/gomplate; \
    test "$(git rev-parse HEAD)" = "${GOMPLATE_GIT_COMMIT}"; \
    go get \
        github.com/go-git/go-billy/v5@v5.9.0 \
        github.com/go-git/go-git/v5@v5.19.0 \
        golang.org/x/crypto@v0.52.0 \
        golang.org/x/net@v0.55.0 \
        google.golang.org/grpc@v1.82.1; \
    go mod tidy; \
    go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X github.com/hairyhenderson/gomplate/v5/version.Version=${GOMPLATE_VERSION} -X github.com/hairyhenderson/gomplate/v5/version.GitCommit=${GOMPLATE_GIT_COMMIT}" \
        -o /out/gomplate ./cmd/gomplate; \
    cp LICENSE /out/licenses/gomplate/LICENSE; \
    /out/gomplate --version; \
    rm -rf /src/gomplate /tmp/go-build-cache /tmp/go-mod-cache

RUN set -eux; \
    mkdir -p /out/licenses/docker-cli; \
    mkdir -p /go/src/github.com/docker; \
    git clone --branch "v${DOCKER_VERSION}" --depth 1 \
        https://github.com/docker/cli /go/src/github.com/docker/cli; \
    cd /go/src/github.com/docker/cli; \
    test "$(git rev-parse HEAD)" = "${DOCKER_GIT_COMMIT}"; \
    CGO_ENABLED=0 \
        GOPATH=/go \
        GO_STRIP=1 \
        GITCOMMIT="${DOCKER_GIT_COMMIT}" \
        SOURCE_DATE_EPOCH="${DOCKER_SOURCE_DATE_EPOCH}" \
        TARGET=/out \
        VERSION="${DOCKER_VERSION}" \
        ./scripts/build/binary; \
    test -x /out/docker; \
    cp LICENSE NOTICE /out/licenses/docker-cli/; \
    /out/docker --version; \
    rm -rf /go/src/github.com/docker/cli /tmp/go-build-cache /tmp/go-mod-cache

FROM ${UBUNTU_IMAGE}

ARG IMAGE_VERSION=dev
ARG UBUNTU_MIRROR=http://archive.ubuntu.com/ubuntu

ENV DEBIAN_FRONTEND=noninteractive \
    SYSTEM_IMAGE_PRELOADER_VERSION=${IMAGE_VERSION}

RUN set -eux; \
    find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec sed -i \
        -e "s|http://security.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" \
        -e "s|http://archive.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" {} +; \
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::http::Pipeline-Depth "0";\n' > /etc/apt/apt.conf.d/80pasturestack-retries; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        curl \
        gawk \
        grep \
        jq \
        procps \
        sed; \
    rm -f /usr/bin/pebble; \
    rm -rf /var/lib/apt/lists/*

COPY --from=tool-builder /out/yq /usr/local/bin/yq
COPY --from=tool-builder /out/gomplate /usr/local/bin/gomplate
COPY --from=tool-builder /out/docker /usr/local/bin/docker
COPY --from=tool-builder /out/licenses/ /licenses/third-party/
COPY ./system-image-preloader /usr/local/bin/system-image-preloader
COPY ./LICENSE ./SECURITY.md ./ORIGIN.md ./COMPATIBILITY.md /licenses/

RUN set -eux; \
    chmod +x \
        /usr/local/bin/docker \
        /usr/local/bin/gomplate \
        /usr/local/bin/system-image-preloader \
        /usr/local/bin/yq; \
    bash -n /usr/local/bin/system-image-preloader; \
    docker --version; \
    gomplate --version; \
    yq --version

ARG IMAGE_REVISION=unknown

LABEL org.opencontainers.image.title="system-image-preloader" \
      org.opencontainers.image.description="System image preloader maintained by PastureStack" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/PastureStack/system-image-preloader" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}"

ENTRYPOINT ["/usr/local/bin/system-image-preloader"]
