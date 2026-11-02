# Vendored build inputs (Hermetic Konflux)

Pinned as **git submodules** under `vendor/` plus the nginx source tarball.
Konflux clones submodules with the source artifact; Hermeto only prefetches
RPMs (`rpms.lock.yaml`). The nginx tarball is required because
`opentelemetry-cpp-contrib` ExternalProject would otherwise download from
nginx.org (blocked in hermetic builds).

| Source | Ref | Path |
|--------|-----|------|
| grpc | v1.49.2 | `vendor/grpc` (recursive submodules) |
| opentelemetry-cpp | v1.8.1 | `vendor/opentelemetry-cpp` (recursive) |
| opentelemetry-cpp-contrib | webserver/v1.1.0 | `vendor/opentelemetry-cpp-contrib` |
| nginx | 1.24.0 | `vendor/nginx/nginx-1.24.0.tar.gz` |

After changing refs, stage submodule gitlinks:

```bash
git add vendor/grpc vendor/opentelemetry-cpp vendor/opentelemetry-cpp-contrib
```

Regenerate pins / RPM lockfile / nginx tarball:

```bash
./scripts/refresh-vendor.sh
```

Local image build (same Dockerfile as Konflux):

```bash
./scripts/build-local.sh
```
