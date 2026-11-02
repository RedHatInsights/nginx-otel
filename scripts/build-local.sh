#!/usr/bin/env bash
# Local image build using the same Dockerfile as Konflux (needs network for dnf).
# Ensures git submodules under vendor/ are present, then builds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IMAGE_TAG="${IMAGE_TAG:-nginx-otel:local}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"

if [ -z "${CONTAINER_ENGINE}" ]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE=podman
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_ENGINE=docker
  else
    echo "Need podman or docker on PATH" >&2
    exit 1
  fi
fi

echo "==> Ensuring vendor/ git submodules"
git submodule update --init --recursive

for path in vendor/grpc vendor/opentelemetry-cpp vendor/opentelemetry-cpp-contrib; do
  if [ ! -f "${path}/.git" ] && [ ! -d "${path}/.git" ] && [ ! -e "${path}/CMakeLists.txt" ] && [ ! -e "${path}/Makefile" ] && [ ! -d "${path}/instrumentation" ]; then
    echo "Missing checkout at ${path}. Run: git submodule update --init --recursive" >&2
    exit 1
  fi
done

echo "==> Building ${IMAGE_TAG} with ${CONTAINER_ENGINE} (Dockerfile)"
exec "${CONTAINER_ENGINE}" build -f Dockerfile -t "${IMAGE_TAG}" .
