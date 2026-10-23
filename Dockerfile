# syntax=docker/dockerfile:1.7
# Modified by PastureStack contributors for independent maintenance and rebranding.

ARG UBUNTU_IMAGE=ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b
FROM ${UBUNTU_IMAGE} AS tool-builder

ARG GO_VERSION=1.27.3
ARG GO_SHA256_amd64=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
ARG YQ_VERSION=v4.53.3
ARG YQ_GIT_COMMIT=1b9b4ac5187171d2e5e3129be0cfa827c7f9d53d
ARG GOMPLATE_VERSION=v5.1.0
ARG GOMPLATE_GIT_COMMIT=0f4c15bc8521939478426bf6ffca4718837b9cb4
ARG DOCKER_VERSION=29.4.2
ARG DOCKER_GIT_COMMIT=055a478ea9010a19d0d4674c0d0e87ade37a4223
ARG DOCKER_SOURCE_DATE_EPOCH=1776697064
ARG UBUNTU_SNAPSHOT=20260825T000000Z

ADD --checksum=sha256:5b6326f1932cfd7be57130561dc78192f09ed9f58bfbe6606ed0c50510c3b6cd \
    https://archive.ubuntu.com/ubuntu/pool/main/c/ca-certificates/ca-certificates_20260816ubuntu0.26.04.1_all.deb \
    /tmp/ca-certificates.deb

ENV DEBIAN_FRONTEND=noninteractive \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GOCACHE=/tmp/go-build-cache \
    GOMODCACHE=/tmp/go-mod-cache \
    GOTELEMETRY=off \
    PATH=/usr/local/go/bin:${PATH}

ADD --checksum=sha256:5b6326f1932cfd7be57130561dc78192f09ed9f58bfbe6606ed0c50510c3b6cd https://archive.ubuntu.com/ubuntu/pool/main/c/ca-certificates/ca-certificates_20260816ubuntu0.26.04.1_all.deb /opt/pasturestack-ca-certificates.deb
RUN set -eux; \
    mkdir -p /tmp/ca-bootstrap /etc/ssl/certs; \
    dpkg-deb --extract /tmp/ca-certificates.deb /tmp/ca-bootstrap; \
    find /tmp/ca-bootstrap/usr/share/ca-certificates -type f -name '*.crt' | LC_ALL=C sort | while IFS= read -r certificate; do sed -e '$a\' "${certificate}"; done > /etc/ssl/certs/ca-certificates.crt; \
    rm -rf /tmp/ca-bootstrap /tmp/ca-certificates.deb; \
    rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; \
    printf 'Types: deb\nURIs: https://snapshot.ubuntu.com/ubuntu/%s\nSuites: resolute resolute-updates resolute-backports resolute-security\nComponents: main universe restricted multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\nSnapshot: no\n' "${UBUNTU_SNAPSHOT}" > /etc/apt/sources.list.d/pasturestack-snapshot.sources; \
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::http::Pipeline-Depth "0";\nAcquire::https::CaInfo "/etc/ssl/certs/ca-certificates.crt";\nAcquire::https::Verify-Peer "true";\nAcquire::https::Verify-Host "true";\nAcquire::AllowInsecureRepositories "false";\nAPT::Get::AllowUnauthenticated "false";\n' > /etc/apt/apt.conf.d/80pasturestack-snapshot; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gcc \
        git \
        libc6-dev \
        make \
        tar; \
    dpkg -i /opt/pasturestack-ca-certificates.deb && \
    update-ca-certificates --fresh && \
    test "$(dpkg-query -W -f='${Version}' ca-certificates)" = '20260816ubuntu0.26.04.1' && \
    test ! -e /usr/share/ca-certificates/mozilla/emSign_ECC_Root_CA_-_G3.crt && \
    rm -f /opt/pasturestack-ca-certificates.deb && \
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
        golang.org/x/crypto@v0.57.0 \
        golang.org/x/net@v0.60.0 \
        google.golang.org/grpc@v1.82.1; \
    go mod tidy; \
    test "$(go list -m -f '{{.Version}}' golang.org/x/net)" = v0.60.0; \
    go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X github.com/hairyhenderson/gomplate/v5/version.Version=${GOMPLATE_VERSION} -X github.com/hairyhenderson/gomplate/v5/version.GitCommit=${GOMPLATE_GIT_COMMIT}" \
        -o /out/gomplate ./cmd/gomplate; \
    cp LICENSE /out/licenses/gomplate/LICENSE; \
    /out/gomplate --version; \
    go version -m /out/gomplate | grep -F 'golang.org/x/net'; \
    rm -rf /src/gomplate /tmp/go-build-cache /tmp/go-mod-cache

RUN set -eux; \
    mkdir -p /out/licenses/docker-cli; \
    mkdir -p /go/src/github.com/docker; \
    git clone --branch "v${DOCKER_VERSION}" --depth 1 \
        https://github.com/docker/cli /go/src/github.com/docker/cli; \
    cd /go/src/github.com/docker/cli; \
    test "$(git rev-parse HEAD)" = "${DOCKER_GIT_COMMIT}"; \
    cp vendor.mod go.mod; \
    cp vendor.sum go.sum; \
    go get golang.org/x/net@v0.60.0; \
    go mod vendor; \
    test "$(go list -m -f '{{.Version}}' golang.org/x/net)" = v0.60.0; \
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
ARG UBUNTU_SNAPSHOT=20260825T000000Z

COPY --from=tool-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ENV DEBIAN_FRONTEND=noninteractive \
    SYSTEM_IMAGE_PRELOADER_VERSION=${IMAGE_VERSION}

ADD --checksum=sha256:5b6326f1932cfd7be57130561dc78192f09ed9f58bfbe6606ed0c50510c3b6cd https://archive.ubuntu.com/ubuntu/pool/main/c/ca-certificates/ca-certificates_20260816ubuntu0.26.04.1_all.deb /opt/pasturestack-ca-certificates.deb
RUN set -eux; \
    rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; \
    printf 'Types: deb\nURIs: https://snapshot.ubuntu.com/ubuntu/%s\nSuites: resolute resolute-updates resolute-backports resolute-security\nComponents: main universe restricted multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\nSnapshot: no\n' "${UBUNTU_SNAPSHOT}" > /etc/apt/sources.list.d/pasturestack-snapshot.sources; \
    printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\nAcquire::http::Pipeline-Depth "0";\nAcquire::https::CaInfo "/etc/ssl/certs/ca-certificates.crt";\nAcquire::https::Verify-Peer "true";\nAcquire::https::Verify-Host "true";\nAcquire::AllowInsecureRepositories "false";\nAPT::Get::AllowUnauthenticated "false";\n' > /etc/apt/apt.conf.d/80pasturestack-snapshot; \
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
    dpkg -i /opt/pasturestack-ca-certificates.deb && \
    update-ca-certificates --fresh && \
    test "$(dpkg-query -W -f='${Version}' ca-certificates)" = '20260816ubuntu0.26.04.1' && \
    test ! -e /usr/share/ca-certificates/mozilla/emSign_ECC_Root_CA_-_G3.crt && \
    rm -f /opt/pasturestack-ca-certificates.deb && \
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
