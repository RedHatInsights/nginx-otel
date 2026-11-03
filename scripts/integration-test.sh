#!/usr/bin/env bash
# Local (and CI) integration test: nginx-otel proxies to a backend and exports OTLP traces to Jaeger.
# Requires: podman or docker; image IMAGE_TAG (default nginx-otel:local).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IMAGE_TAG="${IMAGE_TAG:-nginx-otel:local}"
JAEGER_IMAGE="${JAEGER_IMAGE:-docker.io/jaegertracing/all-in-one:1.60}"
BACKEND_IMAGE="${BACKEND_IMAGE:-docker.io/library/httpd:2.4-alpine}"
CURL_IMAGE="${CURL_IMAGE:-docker.io/curlimages/curl:8.5.0}"
TESTDATA_DIR="${ROOT}/testdata/integration"
TIMEOUT_SECS="${TIMEOUT_SECS:-90}"

if [ -z "${CONTAINER_ENGINE:-}" ]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE=podman
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_ENGINE=docker
  else
    echo "Need podman or docker on PATH" >&2
    exit 1
  fi
fi

# SELinux relabel for podman on Fedora/RHEL; plain :ro for docker (e.g. GitHub Actions).
VOLUME_OPTS=""
if [ "${CONTAINER_ENGINE}" = "podman" ] && [ "$(uname -s)" != "Darwin" ]; then
  VOLUME_OPTS=",Z"
fi

if ! "${CONTAINER_ENGINE}" image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
  echo "Image ${IMAGE_TAG} not found. Build first: ./scripts/build-local.sh" >&2
  exit 1
fi

NETWORK="nginx-otel-it-$$"
JAEGER="nginx-otel-it-jaeger-$$"
BACKEND="nginx-otel-it-backend-$$"
NGINX="nginx-otel-it-nginx-$$"

curl_net() {
  # Usage: curl_net <curl args...>
  "${CONTAINER_ENGINE}" run --rm --network "${NETWORK}" "${CURL_IMAGE}" "$@"
}

cleanup() {
  set +e
  "${CONTAINER_ENGINE}" rm -f "${NGINX}" "${BACKEND}" "${JAEGER}" >/dev/null 2>&1
  "${CONTAINER_ENGINE}" network rm "${NETWORK}" >/dev/null 2>&1
}
trap cleanup EXIT

echo "==> Creating network ${NETWORK}"
"${CONTAINER_ENGINE}" network create "${NETWORK}" >/dev/null

echo "==> Starting Jaeger (${JAEGER_IMAGE})"
"${CONTAINER_ENGINE}" run -d --rm --name "${JAEGER}" --network "${NETWORK}" \
  --network-alias jaeger \
  -e COLLECTOR_OTLP_ENABLED=true \
  "${JAEGER_IMAGE}" >/dev/null

echo "==> Starting backend (${BACKEND_IMAGE})"
"${CONTAINER_ENGINE}" run -d --rm --name "${BACKEND}" --network "${NETWORK}" \
  --network-alias backend \
  "${BACKEND_IMAGE}" >/dev/null

echo "==> Starting nginx-otel (${IMAGE_TAG})"
"${CONTAINER_ENGINE}" run -d --rm --name "${NGINX}" --network "${NETWORK}" \
  --network-alias nginx \
  -v "${TESTDATA_DIR}/nginx.conf:/etc/nginx/nginx.conf:ro${VOLUME_OPTS}" \
  -v "${TESTDATA_DIR}/otel.toml:/etc/nginx/otel.toml:ro${VOLUME_OPTS}" \
  "${IMAGE_TAG}" \
  nginx -c /etc/nginx/nginx.conf -g 'daemon off;' >/dev/null

echo "==> Waiting for /healthz"
deadline=$((SECONDS + TIMEOUT_SECS))
while true; do
  if out="$(curl_net -sf "http://nginx:8000/healthz" 2>/dev/null || true)"; then
    if [[ "${out}" == ok* ]]; then
      echo "healthz ok"
      break
    fi
  fi
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for healthz" >&2
    "${CONTAINER_ENGINE}" logs "${NGINX}" >&2 || true
    exit 1
  fi
  sleep 1
done

echo "==> Hitting proxied / (expect Trace-Id header)"
# Write headers to stdout; discard body
headers="$(curl_net -sD - -o /dev/null "http://nginx:8000/" || true)"
echo "${headers}" | head -20

if ! echo "${headers}" | grep -qiE '^[[:space:]]*Trace-Id:[[:space:]]*[0-9a-fA-F]{16,}'; then
  echo "FAIL: missing Trace-Id response header (module not creating spans?)" >&2
  "${CONTAINER_ENGINE}" logs "${NGINX}" >&2 || true
  exit 1
fi
trace_id="$(echo "${headers}" | awk -F': ' 'BEGIN{IGNORECASE=1} tolower($1)=="trace-id"{print $2}' | tr -d '\r' | head -1)"
# gawk may not be available; fallback:
if [ -z "${trace_id}" ]; then
  trace_id="$(echo "${headers}" | grep -i '^Trace-Id:' | head -1 | sed 's/[Tt]race-[Ii][Dd]:[[:space:]]*//' | tr -d '\r')"
fi
echo "Trace-Id=${trace_id}"
tid_lc="$(echo "${trace_id}" | tr 'A-F' 'a-f')"

echo "==> Waiting for trace in Jaeger (service=nginx-otel-integration-test)"
deadline=$((SECONDS + TIMEOUT_SECS))
found=0
while (( SECONDS < deadline )); do
  services="$(curl_net -sf "http://jaeger:16686/api/services" 2>/dev/null || true)"
  if echo "${services}" | grep -q 'nginx-otel-integration-test'; then
    traces="$(curl_net -sf "http://jaeger:16686/api/traces?service=nginx-otel-integration-test&limit=10" 2>/dev/null || true)"
    if echo "${traces}" | grep -qi "${tid_lc}" || echo "${traces}" | grep -q 'integration_proxy'; then
      found=1
      break
    fi
  fi
  sleep 2
done

if [ "${found}" -ne 1 ]; then
  echo "FAIL: no matching trace exported to Jaeger within ${TIMEOUT_SECS}s" >&2
  echo "services:" >&2
  curl_net -s "http://jaeger:16686/api/services" >&2 || true
  echo "nginx logs:" >&2
  "${CONTAINER_ENGINE}" logs "${NGINX}" >&2 || true
  echo "jaeger logs (tail):" >&2
  "${CONTAINER_ENGINE}" logs --tail 80 "${JAEGER}" >&2 || true
  exit 1
fi

echo "PASS: nginx-otel integration test (module load, proxy, OTLP export)"
