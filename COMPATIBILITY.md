# Compatibility Contracts

This document identifies legacy contracts retained by PastureStack System Image Preloader. They are not product branding and must not be renamed until the corresponding platform components provide a coordinated replacement.

## Environment variables

| Contract | Status | Reason |
| --- | --- | --- |
| `CATTLE_URL` | Preserved | Base URL for the legacy-compatible environment API. |
| `CATTLE_ACCESS_KEY` | Preserved | API access-key input. |
| `CATTLE_SECRET_KEY` | Preserved | API secret-key input. |
| `PLATFORM_VERSION` | New contract | Version selector sent to the catalog API as `platformVersion`. |
| `PLATFORM_AGENT_IMAGE` | New contract | Optional additional agent image to preload. |
| `PLATFORM_DEBUG` | New contract | Enables safe debug status without tracing credentials. |
| `CHECK_CPU_USAGE` | Preserved | Enables CPU-pressure checks before stack image pulls. |
| `CPU_USAGE_MAX` | Preserved | Maximum CPU usage accepted by the pressure gate. |
| `CPU_USAGE_SLEEP` | Preserved | Delay between CPU-pressure checks. |
| `RANDOM_SLEEP` | Preserved | Enables the metadata-derived host delay. |

## Endpoint and data contracts

- Metadata defaults to `http://169.254.169.250/latest`.
- The environment name remains at `self/stack/environment_name`.
- Host enumeration remains at `hosts` with `Accept: application/json`.
- An API URL containing `/v1` is mapped to `/v2-beta` and `/v1-catalog`.
- System stacks are selected with `system=true` and the compatibility account identifier.
- Catalog lookups use the neutral `platformVersion` query parameter. The catalog-service migration must implement the same contract before integration.
- Stack external IDs retain the `catalog://...:<version>` parsing convention.
- The registry override remains sourced from `settings/registry.default`.
- Both `docker-compose.yml.tpl` and `docker-compose.yml` catalog payloads remain supported.

The current source does not read or write vendor-specific labels. No label alias
is introduced by this release.

## New PastureStack artifacts

| Artifact | Name |
| --- | --- |
| Repository | `PastureStack/system-image-preloader` |
| Executable | `/usr/local/bin/system-image-preloader` |
| Image | `ghcr.io/pasturestack/system-image-preloader:<version>` |
| OCI title | `system-image-preloader` |

The former entrypoint filename is not retained because the image entrypoint is controlled by this repository and is not a serialized platform contract.

## Bounded behavior changes

- Image pulls now stop after `IMAGE_PULL_MAX_ATTEMPTS` attempts, defaulting to `5`.
- Pull delays use `IMAGE_PULL_RETRY_DELAY_SECONDS`, defaulting to `10` seconds.
- CPU-pressure waiting now stops after `CPU_WAIT_MAX_ATTEMPTS`, defaulting to `60` checks.
- Invalid retry values fail before Docker is called.
- `PLATFORM_DEBUG=true` enables safe status logging without shell `xtrace`, because xtrace exposes API credentials in process arguments.
- `METADATA_URL` is injectable for controlled mock integration tests while preserving the original default endpoint.
- `PLATFORM_TLS_VERIFY=true` enables certificate verification. The default remains disabled only for compatibility with legacy self-signed deployments.

## Validation boundary

Unit tests override the Docker function in-process and use reserved `.invalid`
image names. Container smoke tests use `--network none`. The isolated
integration test exercises the metadata, environment API, catalog API, Compose
image extraction, and real Docker image-cache lifecycle with mock credentials
and a public PastureStack semantic tag. It does not use a live customer
environment or production credentials.

The default metadata base is `http://169.254.169.250/latest`. All metadata
paths are relative to that base; the host-enumeration request is therefore
`hosts`, not a second `latest/hosts` segment.
