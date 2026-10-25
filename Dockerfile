# syntax=docker/dockerfile:1.7
# Modified by PastureStack contributors for independent maintenance and rebranding.

ARG UBUNTU_IMAGE=ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b
FROM ghcr.io/pasturestack/ubuntu-security-backports:v0.1.1@sha256:45d6b507b63a18459ae5cf76afd4d9731f8ef43b9c40e4c3dbb01899e1752b19 AS ubuntu_security_backports
FROM ${UBUNTU_IMAGE} AS tool-builder

ARG GO_VERSION=1.27.3
ARG GO_SHA256_amd64=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
ARG YQ_VERSION=v4.53.3
ARG YQ_GIT_COMMIT=1b9b4ac5187171d2e5e3129be0cfa827c7f9d53d
ARG GOMPLATE_VERSION=v5.1.0
ARG GOMPLATE_GIT_COMMIT=0f4c15bc8521939478426bf6ffca4718837b9cb4
ARG DOCKER_VERSION=29.9.2
ARG DOCKER_GIT_COMMIT=a82e528901260c8df6073311379eac65f92db204
ARG DOCKER_ARCHIVE_SHA256=9ac225999fd5e863f7694c728ef23d480616b1e5639328fa309befd4243d69eb
ARG DOCKER_BINARY_SHA256=6c71cfe71faff949a602946a4df4799b563232e79d0b8b6fd343d0ef081c9621
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

COPY ubuntu-security-packages.lock /licenses/ubuntu-security-packages.lock
COPY scripts/install-ubuntu-security-updates /usr/local/libexec/pasturestack/install-ubuntu-security-updates
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
    sh /usr/local/libexec/pasturestack/install-ubuntu-security-updates /licenses/ubuntu-security-packages.lock /etc/ssl/certs/ca-certificates.crt && \
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
    go get golang.org/x/net@v0.60.0 golang.org/x/text@v0.42.0; \
    go mod tidy; \
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
        github.com/go-git/go-git/v5@v5.19.2 \
        golang.org/x/crypto@v0.57.0 \
        golang.org/x/net@v0.60.0 \
        go.opentelemetry.io/otel/sdk@v1.45.0 \
        google.golang.org/grpc@v1.83.2; \
    go mod tidy; \
    test "$(go list -m -f '{{.Version}}' golang.org/x/net)" = v0.60.0; \
    test "$(go list -m -f '{{.Version}}' go.opentelemetry.io/otel/sdk)" = v1.45.0; \
    mkdir -p /out/licenses/security; \
    go list -deps -f '{{.ImportPath}}' ./cmd/gomplate > /out/licenses/security/gomplate-dependencies.txt; \
    ! grep -Eq '^golang.org/x/crypto/openpgp(/|$)' /out/licenses/security/gomplate-dependencies.txt; \
    go build -trimpath -buildvcs=false \
        -ldflags "-s -w -X github.com/hairyhenderson/gomplate/v5/version.Version=${GOMPLATE_VERSION} -X github.com/hairyhenderson/gomplate/v5/version.GitCommit=${GOMPLATE_GIT_COMMIT}" \
        -o /out/gomplate ./cmd/gomplate; \
    cp LICENSE /out/licenses/gomplate/LICENSE; \
    /out/gomplate --version; \
    go version -m /out/gomplate | grep -F 'golang.org/x/net'; \
    go version -m /out/gomplate > /out/licenses/security/gomplate-buildinfo.txt; \
    rm -rf /src/gomplate /tmp/go-build-cache /tmp/go-mod-cache

RUN set -eux; \
    mkdir -p /out/licenses/docker-cli; \
    git clone --branch "v${DOCKER_VERSION}" --depth 1 https://github.com/docker/cli /src/docker-cli; \
    test "$(git -C /src/docker-cli rev-parse HEAD)" = "${DOCKER_GIT_COMMIT}"; \
    cp /src/docker-cli/LICENSE /src/docker-cli/NOTICE /out/licenses/docker-cli/; \
    curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 --max-time 300 \
        -o /tmp/docker.tgz "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"; \
    echo "${DOCKER_ARCHIVE_SHA256}  /tmp/docker.tgz" | sha256sum -c -; \
    tar -xOf /tmp/docker.tgz docker/docker > /out/docker; \
    echo "${DOCKER_BINARY_SHA256}  /out/docker" | sha256sum -c -; \
    chmod +x /out/docker; \
    /out/docker --version; \
    rm -rf /src/docker-cli /tmp/docker.tgz

FROM ${UBUNTU_IMAGE}

ARG IMAGE_VERSION=dev
ARG UBUNTU_SNAPSHOT=20260825T000000Z

COPY --from=tool-builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

ENV DEBIAN_FRONTEND=noninteractive \
    SYSTEM_IMAGE_PRELOADER_VERSION=${IMAGE_VERSION}

COPY ubuntu-security-packages.lock /licenses/ubuntu-security-packages.lock
COPY scripts/install-ubuntu-security-updates /usr/local/libexec/pasturestack/install-ubuntu-security-updates
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
    sh /usr/local/libexec/pasturestack/install-ubuntu-security-updates /licenses/ubuntu-security-packages.lock /etc/ssl/certs/ca-certificates.crt && \
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

# Install qualified backports only for packages already in this runtime.
# The immutable read-only build mount adds no installer or interpreter to it.
RUN --mount=from=ubuntu_security_backports,source=/out,target=/opt/pasturestack/ubuntu-security-backports,ro \
    set -eux; \
    evidence=/usr/share/pasturestack/security/ubuntu-backports; \
    mkdir -p "${evidence}"; \
    /opt/pasturestack/ubuntu-security-backports/install-existing-backports --install-in-docker-build > "${evidence}/install.json"; \
    /opt/pasturestack/ubuntu-security-backports/install-existing-backports --verify-installed > "${evidence}/verify.json"; \
    for document in manifest.json qualification.json openvex.json source-inputs.lock.json; do \
        cp "/opt/pasturestack/ubuntu-security-backports/${document}" "${evidence}/${document}"; \
    done; \
    printf '%s\n' 'ghcr.io/pasturestack/ubuntu-security-backports:v0.1.1@sha256:45d6b507b63a18459ae5cf76afd4d9731f8ef43b9c40e4c3dbb01899e1752b19' > "${evidence}/bundle-image.txt"; \
    (cd "${evidence}" && sha256sum manifest.json qualification.json openvex.json source-inputs.lock.json install.json verify.json bundle-image.txt > SHA256SUMS); \
    dpkg-query -W -f='${binary:Package}\t${Version}\n' | LC_ALL=C sort > /usr/share/pasturestack/ubuntu-security-packages.tsv; \
    rm -f /var/cache/ldconfig/aux-cache

ENTRYPOINT ["/usr/local/bin/system-image-preloader"]
