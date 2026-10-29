# nginx-otel

UBI-based nginx with OpenTelemetry instrumentation for SWATCH.

After building, follow the [opentelemetry-cpp-contrib nginx README](https://github.com/open-telemetry/opentelemetry-cpp-contrib/blob/main/instrumentation/nginx/README.md#usage).

The built module is installed at `/opt/otel_ngx_module.so`:

```nginx
load_module /opt/otel_ngx_module.so;
```

## Build

Upstream sources are **git submodules** under `vendor/`:

- `vendor/grpc` @ `v1.49.2` (recursive)
- `vendor/opentelemetry-cpp` @ `v1.8.1` (recursive)
- `vendor/opentelemetry-cpp-contrib` @ `webserver/v1.1.0`

```bash
git submodule update --init --recursive
./scripts/refresh-vendor.sh   # bump pins + regenerate rpms.lock.yaml
./scripts/build-local.sh      # submodule sync + podman/docker build
```

See `vendor/VERSIONS.md` for pinned refs.

## Testing locally

Run Jaeger:

```shell
podman run --rm --name jaeger \
  -e COLLECTOR_ZIPKIN_HOST_PORT=:9411 \
  -p 6831:6831/udp \
  -p 6832:6832/udp \
  -p 5778:5778 \
  -p 16686:16686 \
  -p 4317:4317 \
  -p 4318:4318 \
  -p 14250:14250 \
  -p 14268:14268 \
  -p 14269:14269 \
  -p 9411:9411 \
  jaegertracing/all-in-one:1.60
```

Build and run:

```shell
./scripts/build-local.sh
podman run \
    --network=host \
    -e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
    -v $(pwd)/example:/etc/nginx:z \
    --rm -ti \
    nginx-otel:local \
    /bin/bash -c "nginx -g 'daemon off;'"
```

```shell
curl http://localhost:8000/
```

Traces: [Jaeger UI](http://localhost:16686)
