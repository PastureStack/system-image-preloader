# Security Policy

## Project status

PastureStack System Image Preloader is an independent compatibility maintenance project. Release `v0.3.0` has completed offline policy tests, container smoke tests, an isolated compatibility API-to-Docker cache lifecycle test, and a HIGH/CRITICAL container vulnerability gate.

## Reporting a vulnerability

Report vulnerabilities privately to the maintainers before opening a public issue. Include the affected revision, deployment assumptions, reproduction steps, impact, and any proposed mitigation. Do not include live credentials, access keys, private image names, internal URLs, or customer data.

## Runtime trust boundary

Real image preloading requires access to a Docker daemon. A mounted Docker socket is effectively host-privileged and must be treated as a high-trust interface. Run only reviewed images, restrict who can change configuration, and do not expose the socket through an untrusted network service.

The process also receives `CATTLE_ACCESS_KEY` and `CATTLE_SECRET_KEY`. Do not enable shell tracing, print the environment, or include these values in diagnostic bundles. `PLATFORM_DEBUG=true` intentionally avoids shell `xtrace`.

## Transport security

`PLATFORM_TLS_VERIFY=false` preserves compatibility with legacy self-signed endpoints but weakens server authentication. Prefer a trusted CA and set `PLATFORM_TLS_VERIFY=true`. Never send compatibility API credentials across an untrusted network.

## Retry safety

Image pulls and CPU-pressure waits are bounded. Keep retry limits small enough to preserve observability and orchestration recovery. Repeated failures should return a nonzero status rather than keeping a container alive indefinitely.

## Test safety

The repository's unit tests stub Docker calls and do not access a registry. The documented container smoke test runs with `--network none` and does not mount the Docker socket. The integration test uses mock credentials and compatibility endpoints, an exact public semantic image tag, and a real local Docker socket. Run it only on a disposable, explicitly authorized host. It refuses to remove a test image referenced by any container and never performs a broad image prune.

## Supported revisions

Only the latest reviewed PastureStack maintenance revision is eligible for security fixes. Historical upstream tags are retained for traceability and are not supported releases.
