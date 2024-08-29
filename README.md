ubi-based nginx with otel
=========================

This repository is for building a container image for nginx with otel instrumentation.

After building, follow [opentelemetry-cpp-contrib nginx README](https://github.com/open-telemetry/opentelemetry-cpp-contrib/blob/main/instrumentation/nginx/README.md#usage)

The built module is present in /opt, so the line for loading the module should
look like:

```nginx
load_module /opt/otel_ngx_module.so;
```

Testing locally
---------------

First, run the jaeger all-in-one-image, which will collect traces:

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

Build the image:

```shell
podman build . -t nginx-otel
```

Run the built nginx container:

```shell
podman run \
    --network=host \
    -e OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317 \
    -v $(pwd)/example:/etc/nginx:z \
    --rm -ti \
    nginx-otel \
    /bin/bash -c "nginx -g 'daemon off;'"
```

Hit the nginx deployment:

```shell
curl http://localhost:8000/
```

Finally view the trace in the [local jaeger UI](http://localhost:16686)
