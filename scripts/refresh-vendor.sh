#!/usr/bin/env bash
# Refresh git submodule pins and rpms.lock.yaml for hermetic Konflux builds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GRPC_VERSION="${GRPC_VERSION:-v1.49.2}"
OTEL_CPP_VERSION="${OTEL_CPP_VERSION:-v1.8.1}"
OTEL_CPP_CONTRIB_VERSION="${OTEL_CPP_CONTRIB_VERSION:-webserver/v1.1.0}"

checkout_submodule() {
  local path=$1
  local tag=$2
  local recursive=${3:-no}
  pushd "$path" >/dev/null
  git fetch --depth 1 origin "refs/tags/${tag}:refs/tags/${tag}" 2>/dev/null \
    || git fetch --depth 1 origin tag "$tag"
  git checkout "$tag"
  if [ "$recursive" = "yes" ]; then
    git submodule update --init --recursive --depth 1
  fi
  popd >/dev/null
}

echo "==> Updating vendor/grpc to ${GRPC_VERSION}"
checkout_submodule vendor/grpc "$GRPC_VERSION" yes

echo "==> Updating vendor/opentelemetry-cpp to ${OTEL_CPP_VERSION}"
checkout_submodule vendor/opentelemetry-cpp "$OTEL_CPP_VERSION" yes

echo "==> Updating vendor/opentelemetry-cpp-contrib to ${OTEL_CPP_CONTRIB_VERSION}"
checkout_submodule vendor/opentelemetry-cpp-contrib "$OTEL_CPP_CONTRIB_VERSION" no

cat > vendor/VERSIONS.md <<EOF
# Vendored build inputs (Hermetic Konflux)

Pinned as **git submodules** under \`vendor/\`. Konflux clones them with the
source artifact; Hermeto only prefetches RPMs (\`rpms.lock.yaml\`).

| Source | Ref | Path |
|--------|-----|------|
| grpc | ${GRPC_VERSION} | \`vendor/grpc\` (recursive submodules) |
| opentelemetry-cpp | ${OTEL_CPP_VERSION} | \`vendor/opentelemetry-cpp\` (recursive) |
| opentelemetry-cpp-contrib | ${OTEL_CPP_CONTRIB_VERSION} | \`vendor/opentelemetry-cpp-contrib\` |

After changing refs, stage submodule gitlinks:

\`\`\`bash
git add vendor/grpc vendor/opentelemetry-cpp vendor/opentelemetry-cpp-contrib
\`\`\`

Regenerate:

\`\`\`bash
./scripts/refresh-vendor.sh
\`\`\`
EOF

# Resolve against the *build* stage base (ubi9/ubi), not the final nginx image.
# `-f Dockerfile` picks the last FROM (ubi9/nginx-124), which already contains
# packages like vim-filesystem that ubi9/ubi lacks — hermetic dnf then fails
# with "nothing provides vim-filesystem needed by cmake-data".
BUILD_BASE_IMAGE="${BUILD_BASE_IMAGE:-registry.access.redhat.com/ubi9/ubi:1793179250}"

NGINX_VERSION="${NGINX_VERSION:-1.24.0}"
NGINX_TARBALL="vendor/nginx/nginx-${NGINX_VERSION}.tar.gz"
NGINX_SHA256_FILE="${NGINX_TARBALL}.sha256"
NGINX_URL="http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"

echo "==> Fetching ${NGINX_TARBALL}"
mkdir -p vendor/nginx
curl -fSL --retry 5 -o "${NGINX_TARBALL}.tmp" "${NGINX_URL}"
if [ -f "${NGINX_SHA256_FILE}" ]; then
  echo "$(cat "${NGINX_SHA256_FILE}")  ${NGINX_TARBALL}.tmp" | sha256sum -c -
else
  sha256sum "${NGINX_TARBALL}.tmp" | awk '{print $1}' > "${NGINX_SHA256_FILE}"
  echo "Wrote ${NGINX_SHA256_FILE}"
fi
mv "${NGINX_TARBALL}.tmp" "${NGINX_TARBALL}"

echo "==> Regenerating rpms.lock.yaml (image=${BUILD_BASE_IMAGE})"
if command -v rpm-lockfile-prototype >/dev/null 2>&1; then
  rpm-lockfile-prototype \
    --image "${BUILD_BASE_IMAGE}" \
    --arch x86_64 --arch aarch64 \
    --outfile rpms.lock.yaml \
    rpms.in.yaml
elif command -v podman >/dev/null 2>&1; then
  podman run --rm -v "${ROOT}:/work:Z" -w /work \
    -e BUILD_BASE_IMAGE="${BUILD_BASE_IMAGE}" \
    docker.io/library/fedora:41 \
    bash -c 'dnf -y -q install python3 python3-pip python3-dnf skopeo rpm createrepo_c &&
      python3 -m pip install -q https://github.com/konflux-ci/rpm-lockfile-prototype/archive/refs/tags/v0.30.1.tar.gz &&
      rpm-lockfile-prototype --image "${BUILD_BASE_IMAGE}" --arch x86_64 --arch aarch64 --outfile=rpms.lock.yaml rpms.in.yaml'
else
  echo "Install rpm-lockfile-prototype or podman to refresh rpms.lock.yaml" >&2
  exit 1
fi

echo "Done. Commit .gitmodules, vendor gitlinks, and rpms.lock.yaml."
