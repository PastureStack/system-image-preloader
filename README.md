# PastureStack System Image Preloader

PastureStack System Image Preloader discovers the images required by legacy-compatible system workloads and asks the local Docker daemon to pull images that are not already present.

The runtime is a Bash executable rather than a Go module. Its public package identity is the repository, executable, container image, and OCI metadata name `system-image-preloader`.

PastureStack is an independent community effort to preserve, audit, and modernize the Rancher 1.6 ecosystem. It is not affiliated with or endorsed by Rancher Labs or SUSE.

**Upstream:** [`rancher/pre-pull-images`](https://github.com/rancher/pre-pull-images). This GitHub fork retains the upstream Git history, authorship, dates, and license notices unchanged; PastureStack maintenance is consolidated into one commit after the preserved upstream boundary.

This repository is a derivative maintenance project. It preserves the upstream Git history, authorship, and Apache License 2.0 terms. See [ORIGIN.md](ORIGIN.md) for source attribution and [COMPATIBILITY.md](COMPATIBILITY.md) for the legacy contracts that intentionally retain upstream identifiers.

## Reviewed release

The `v0.3.0` release provides:

- a self-contained public build based on a digest-pinned Ubuntu image;
- the `system-image-preloader` executable and image name;
- a checksum-verified Go toolchain download;
- source-pinned Docker CLI, `yq`, and `gomplate` builds;
- a finite, configurable image-pull retry policy;
- offline retry and URL-contract tests;
- offline `--help` and `--version` smoke paths; and
- an isolated end-to-end test that discovers a system stack through mock
  compatibility APIs and caches a real public image through the mounted Docker
  socket.

## How it works

At runtime the executable:

1. reads the environment name from the compatibility metadata endpoint;
2. discovers system stacks through the compatibility environment API;
3. resolves stack versions through the compatibility catalog API;
4. extracts image references from Compose YAML; and
5. pulls each missing image through the mounted Docker socket.

Image pulls stop after `IMAGE_PULL_MAX_ATTEMPTS`. A failed pull never retries forever.

## Local validation

The retry tests do not require Docker or network access:

```bash
make validate
make test
```

Build and perform offline container smoke tests:

```bash
make build
make smoke
```

The build needs internet access only for the pinned public Ubuntu base, Go
archive, and pinned Docker CLI, `yq`, and `gomplate` source trees.

Run the isolated API-to-Docker integration test on a disposable Docker host:

```bash
make integration
```

The integration test starts a local mock metadata, environment, and catalog
API, removes only its exact test image tag after confirming no container
references it, verifies a real registry pull through the Docker socket, and
restores the image-presence state. It never performs a broad image prune.

## Deployment

Use the immutable semantic tag:

```text
ghcr.io/pasturestack/system-image-preloader:v0.3.0
```

The deployment definition must mount `/var/run/docker.sock`, run one instance
per host, and mark the service as start-once. Optional private-registry
credentials can be mounted from the host Docker configuration selected by the
operator.

## Runtime configuration

The deployed compatibility environment supplies these required variables:

- `CATTLE_URL`
- `CATTLE_ACCESS_KEY`
- `CATTLE_SECRET_KEY`
- `PLATFORM_VERSION`

Important optional settings include:

- `METADATA_URL` — defaults to `http://169.254.169.250/latest`.
- `IMAGE_PULL_MAX_ATTEMPTS` — defaults to `5` and must be positive.
- `IMAGE_PULL_RETRY_DELAY_SECONDS` — defaults to `10`.
- `PLATFORM_TLS_VERIFY` — defaults to `false` for legacy compatibility; use `true` when the endpoint has a trusted certificate.
- `CHECK_CPU_USAGE`, `CPU_USAGE_MAX`, `CPU_USAGE_SLEEP`, and `CPU_WAIT_MAX_ATTEMPTS` — optional bounded CPU-pressure gate.
- `RANDOM_SLEEP` — preserves the optional metadata-based host delay.
- `PLATFORM_AGENT_IMAGE` — provides optional agent-image preloading.
- `PLATFORM_DEBUG` — enables safe debug status without tracing credentials.

The complete contract and behavior-change list is in [COMPATIBILITY.md](COMPATIBILITY.md).

## Security boundary

The container requires access to a Docker daemon to perform real pulls. Mounting `/var/run/docker.sock` grants powerful host-level capabilities and must only be done for a trusted image in a controlled environment. The offline tests and smoke commands do not mount the socket or contact compatibility services. The integration test does mount the socket and is intentionally limited to a disposable, explicitly authorized Docker host.

See [SECURITY.md](SECURITY.md) before integration testing.

## Licensing

The repository remains under its existing Apache License 2.0 file. The runtime image also includes the actual upstream license files for the bundled Docker CLI, `yq`, and `gomplate` under `/licenses/third-party/`. These files do not replace or alter the repository license.

## Localization

This project is a background service with no user interface or runtime localization subsystem. It therefore does not add locale files. User-facing dashboards that manage this service must provide Traditional Chinese through their own locale framework.
