ubi-based nginx with otel
=========================

This repository is for building a container image for nginx with otel instrumentation.

After building, follow https://github.com/open-telemetry/opentelemetry-cpp-contrib/blob/main/instrumentation/nginx/README.md#usage

The built module is present in /opt, so the line for loading the module should look like:

```nginx
load_module /opt/otel_ngx_module.so;
```
