# Origin and Attribution

This repository is derived from the upstream `rancher/pre-pull-images` project:

- Upstream source: <https://github.com/rancher/pre-pull-images>
- Preserved upstream release point: `v0.2.2`
- Preserved upstream boundary commit: `7ff29a61d6543934ebd25fcdba3701d88b0f4f93`
- Preserved source history: Git commits, authors, dates, and tags remain part of this repository
- Repository license: Apache License 2.0, as provided in [LICENSE](LICENSE)

PastureStack contributors maintain later compatibility, security, build, documentation, and naming changes. PastureStack does not claim authorship of the upstream work and does not replace upstream copyright or contributor attribution.

PastureStack is an independent community effort to preserve, audit, and modernize the Rancher 1.6 ecosystem. It is not affiliated with or endorsed by Rancher Labs or SUSE.

The names of the upstream project and its related products appear only where required for source attribution, license compliance, historical accuracy, or compatibility documentation. No trademark affiliation or endorsement is claimed.

## Bundled tools

The container build includes separately maintained tools:

- Docker CLI `29.4.2`, built from verified commit
  `055a478ea9010a19d0d4674c0d0e87ade37a4223`;
- `yq` `v4.53.3`, built from its verified upstream commit; and
- `gomplate` `v5.1.0`, built from its verified upstream commit.

The source-built Go tools use Go `1.26.5`. The `gomplate` build updates
dependencies with published security fixes while retaining the verified
`v5.1.0` application source.

Their actual upstream license and notice files are copied into `/licenses/third-party/` in the runtime image. They remain governed by their respective upstream terms.
