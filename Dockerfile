FROM nginx:alpine AS builder

# nginx:alpine contains NGINX_VERSION environment variable, like so:
ENV NGINX_VERSION 1.21.6

# Additional module version
ENV PROXY_CONNECT_VERSION 102101

# For latest build deps, see https://github.com/nginxinc/docker-nginx/blob/master/mainline/alpine/Dockerfile
RUN apk add --no-cache --virtual .build-deps \
  git \
  gcc \
  libc-dev \
  make \
  openssl-dev \
  pcre2-dev \
  zlib-dev \
  linux-headers \
  libxslt-dev \
  gd-dev \
  geoip-dev \
  libedit-dev \
  bash \
  alpine-sdk \
  findutils

# Download sources
RUN wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx.tar.gz && \
  git clone https://github.com/vozlt/nginx-module-vts.git && \
  git clone https://github.com/yaoweibin/nginx_upstream_check_module \
  git clone https://github.com/chobits/ngx_http_proxy_connect_module.git

# Reuse same cli arguments as the nginx:alpine image used to build (but remove the erroneous -fomit-frame-pointer)
RUN CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p') && \
    CONFARGS=${CONFARGS/-Os -fomit-frame-pointer -g/-Os} && \
    mkdir -p /usr/src && \
    tar -zxC /usr/src -f nginx.tar.gz && \
    cd /usr/src/nginx-$NGINX_VERSION && \
    patch -p1 < /ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_${PROXY_CONNECT_VERSION}.patch && \
    ./configure --with-compat $CONFARGS --add-dynamic-module=/ngx_http_proxy_connect_module && \
    make && make install

FROM nginx:alpine
# Copy new dynamic module ngx_http_proxy_connect_module
COPY --from=builder /usr/lib/nginx/modules/ngx_http_proxy_connect_module.so /usr/lib/nginx/modules/ngx_http_proxy_connect_module.so
# Copy new nginx binary, due to patching for ngx_http_proxy_connect_module
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8080
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]