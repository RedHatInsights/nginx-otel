# Vendored build inputs (Hermetic Konflux)

Pinned as **git submodules** under `vendor/`. Konflux clones them with the
source artifact; Hermeto only prefetches RPMs (`rpms.lock.yaml`).

| Source | Ref | Path |
|--------|-----|------|
| grpc | v1.49.2 | `vendor/grpc` (recursive submodules) |
| opentelemetry-cpp | v1.8.1 | `vendor/opentelemetry-cpp` (recursive) |
| opentelemetry-cpp-contrib | webserver/v1.1.0 | `vendor/opentelemetry-cpp-contrib` |

After changing refs, stage submodule gitlinks:

```bash
git add vendor/grpc vendor/opentelemetry-cpp vendor/opentelemetry-cpp-contrib
```

Regenerate:

```bash
./scripts/refresh-vendor.sh
```
