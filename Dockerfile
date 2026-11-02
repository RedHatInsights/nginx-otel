FROM registry.access.redhat.com/ubi9/ubi:1793179250 AS build

ARG NGINX_VERSION=1.24.0
ENV GRPC_VERSION=v1.49.2
ENV OTEL_CPP_VERSION=v1.8.1
ENV OTEL_CPP_CONTRIB_VERSION=webserver/v1.1.0

COPY vendor/grpc /src/grpc
COPY vendor/opentelemetry-cpp /src/opentelemetry-cpp
COPY vendor/opentelemetry-cpp-contrib /src/opentelemetry-cpp-contrib
# Prefetched nginx sources for hermetic ExternalProject (no nginx.org at build time).
COPY vendor/nginx/nginx-1.24.0.tar.gz /src/nginx-1.24.0.tar.gz

# Hermetic (Konflux): source Hermeto env so dnf uses the prefetched local repos.
RUN set -eux; \
  if [ -f /cachi2/cachi2.env ]; then . /cachi2/cachi2.env; \
  elif [ -f /cachi2/output/cachi2.env ]; then . /cachi2/output/cachi2.env; fi; \
  dnf install -y \
    cmake \
    vim-filesystem \
    curl-devel \
    gcc-c++ \
    pcre-devel \
    zlib-devel

RUN set -eux; \
  cd /src/grpc \
  && mkdir -p cmake/build \
  && cd cmake/build \
  && cmake \
    -DgRPC_INSTALL=ON \
    -DgRPC_BUILD_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=/install \
    -DCMAKE_BUILD_TYPE=Release \
    -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF \
    -DCMAKE_CXX_STANDARD=17 \
    ../.. \
  && make -j2 \
  && make install

RUN set -eux; \
  cd /src/opentelemetry-cpp \
  && mkdir -p build \
  && cd build \
  && cmake -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/install \
    -DCMAKE_PREFIX_PATH=/install \
    -DWITH_OTLP=ON \
    -DWITH_OTLP_GRPC=ON \
    -DWITH_OTLP_HTTP=OFF \
    -DBUILD_TESTING=OFF \
    -DWITH_EXAMPLES=OFF \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    .. \
  && make -j2 \
  && make install

RUN set -eux; \
  # Point ExternalProject at the vendored tarball (hermetic builds have no network).
  sed -i \
    's|URL "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"|URL "/src/nginx-${NGINX_VERSION}.tar.gz"|' \
    /src/opentelemetry-cpp-contrib/instrumentation/nginx/nginx.cmake \
  && cd /src/opentelemetry-cpp-contrib/instrumentation/nginx \
  && mkdir -p build \
  && cd build \
  && cmake -DCMAKE_BUILD_TYPE=Release \
    -DNGINX_VERSION=${NGINX_VERSION} \
    -DCMAKE_PREFIX_PATH=/install \
    -DCMAKE_INSTALL_PREFIX=/usr/share/nginx/modules \
    .. \
  && make -j2 \
  && make install
FROM registry.access.redhat.com/ubi9/nginx-124:1793249990

ARG NGINX_VERSION=1.24.0

# Required labels for Enterprise Contract
LABEL name="nginx-otel"
LABEL maintainer="Red Hat, Inc."
LABEL version="ubi9"
LABEL release="${NGINX_VERSION}"
LABEL vendor="Red Hat, Inc."
LABEL url="https://github.com/RedHatInsights/nginx-otel"
LABEL com.redhat.component="nginx-otel"
LABEL distribution-scope="public"
LABEL io.k8s.description="NGINX with OpenTelemetry instrumentation based on UBI9."
LABEL description="NGINX with OpenTelemetry instrumentation based on UBI9."

#label for EULA
LABEL com.redhat.license_terms="https://www.redhat.com/en/about/red-hat-end-user-license-agreements#UBI"

COPY LICENSE /licenses/LICENSE

COPY --from=build /usr/share/nginx/modules/otel_ngx_module.so /opt/
