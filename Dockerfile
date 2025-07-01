FROM registry.access.redhat.com/ubi9/ubi:9.6-1751287003 as build
# NOTE: this must be the same as the output of `nginx -V` from the ubi9/nginx image
ENV NGINX_VERSION=1.24.0
# NOTE: this must be the same as the target grpc version from otel-cpp-contrib
# see @grpc_version at https://github.com/open-telemetry/opentelemetry-cpp-contrib/blob/main/instrumentation/nginx/test/instrumentation/lib/mix/tasks/dockerfiles.ex
ENV GRPC_VERSION=v1.49.2
# NOTE: this must be the same as the target cpp version from otel-cpp-contrib
# see @otel_cpp_version at https://github.com/open-telemetry/opentelemetry-cpp-contrib/blob/main/instrumentation/nginx/test/instrumentation/lib/mix/tasks/dockerfiles.ex
ENV OTEL_CPP_VERSION=v1.8.1
# NOTE: this is the tag of a opentelemetry-cpp-contrib release, see https://github.com/open-telemetry/opentelemetry-cpp-contrib/releases
ENV OTEL_CPP_CONTRIB_VERSION=webserver/v1.1.0
RUN dnf install -y \
    cmake \
    curl-devel \
    gcc-c++ \
    git \
    pcre-devel \
    zlib-devel
RUN git clone --shallow-submodules --depth 1 --recurse-submodules -b $GRPC_VERSION \
  https://github.com/grpc/grpc \
  && cd grpc \
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
    -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF \
    -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF \
    -DCMAKE_CXX_STANDARD=17 \
    ../.. \
  && make -j2 \
  && make install
RUN git clone --shallow-submodules --depth 1 --recurse-submodules -b $OTEL_CPP_VERSION \
  https://github.com/open-telemetry/opentelemetry-cpp.git \
  && cd opentelemetry-cpp \
  && mkdir build \
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
RUN git clone --shallow-submodules --depth 1 --recurse-submodules -b $OTEL_CPP_CONTRIB_VERSION \
  https://github.com/open-telemetry/opentelemetry-cpp-contrib.git \
  && cd opentelemetry-cpp-contrib/instrumentation/nginx \
  && mkdir build \
  && cd build \
  && cmake -DCMAKE_BUILD_TYPE=Release \
    -DNGINX_VERSION=$NGINX_VERSION \
    -DCMAKE_PREFIX_PATH=/install \
    -DCMAKE_INSTALL_PREFIX=/usr/share/nginx/modules \
    .. \
  && make -j2 \
  && make install
FROM registry.access.redhat.com/ubi9/nginx-124:9.6-1750911912
COPY --from=build /usr/share/nginx/modules/otel_ngx_module.so /opt/
