FROM nginx:1.21.6-alpine AS builder

# nginx:alpine contains NGINX_VERSION environment variable, like so:
ENV NGINX_VERSION 1.21.6

ENV UPSTREAM_CHECK_MODULE_PATCH_VERSION=1.20.1

# lua
# https://www.lua.org/versions.html
# https://pkgs.alpinelinux.org/package/edge/main/x86/lua5.4
ENV VER_LUA=5.4

# ngx_devel_kit
# https://github.com/vision5/ngx_devel_kit
ENV VER_NGX_DEVEL_KIT=0.3.2

# luajit2
# https://github.com/openresty/luajit2
ENV VER_LUAJIT=2.1-20230410
ENV LUAJIT_LIB=/usr/local/lib
ENV LUAJIT_INC=/usr/local/include/luajit-2.1
ENV LD_LIBRARY_PATH=/usr/local/lib/:$LD_LIBRARY_PATH

# lua-nginx-module
# https://github.com/openresty/lua-nginx-module
ENV VER_LUA_NGINX_MODULE=0.10.24

# lua-resty-core
# https://github.com/openresty/lua-resty-core
ENV VER_LUA_RESTY_CORE=0.1.26
ENV LUA_LIB_DIR=/usr/local/share/lua/5.4

# lua-resty-lrucache
# https://github.com/openresty/lua-resty-lrucache
ENV VER_LUA_RESTY_LRUCACHE=0.13



# For latest build deps, see https://github.com/nginxinc/docker-nginx/blob/master/mainline/alpine/Dockerfile
RUN apk add --no-cache --virtual .build-deps \
  curl \
  gzip \
  libmaxminddb-dev \
  patch \
  tar \
  unzip \
  wget \
  git \
  gcc \
  libc-dev \
  make \
  openssl-dev \
  pcre-dev \
  zlib-dev \
  linux-headers \
  libxml2-dev \
  libxslt-dev \
  gd-dev \
  geoip-dev \
  libedit-dev \
  bash \
  alpine-sdk \
  findutils \
  lua${VER_LUA} \
  lua${VER_LUA}-dev

RUN wget "https://github.com/openresty/luajit2/archive/refs/tags/v${VER_LUAJIT}.tar.gz" -O "luajit2-${VER_LUAJIT}.tar.gz" && \
  wget "https://github.com/vision5/ngx_devel_kit/archive/refs/tags/v${VER_NGX_DEVEL_KIT}.tar.gz" -O "ngx_devel_kit-${VER_NGX_DEVEL_KIT}.tar.gz" && \
  wget "https://github.com/openresty/lua-nginx-module/archive/refs/tags/v${VER_LUA_NGINX_MODULE}.tar.gz" -O "lua-nginx-module-${VER_LUA_NGINX_MODULE}.tar.gz" && \
  wget "https://github.com/openresty/lua-resty-core/archive/refs/tags/v${VER_LUA_RESTY_CORE}.tar.gz" -O "lua-resty-core-${VER_LUA_RESTY_CORE}.tar.gz" && \
  wget "https://github.com/openresty/lua-resty-lrucache/archive/refs/tags/v${VER_LUA_RESTY_LRUCACHE}.tar.gz" -O "lua-resty-lrucache-${VER_LUA_RESTY_LRUCACHE}.tar.gz" && \
  mkdir /luajit2 && tar -zxC luajit2 -f "luajit2-${VER_LUAJIT}.tar.gz" --strip-components 1 && \
  mkdir /ngx_devel_kit && tar -zxC ngx_devel_kit -f "ngx_devel_kit-${VER_NGX_DEVEL_KIT}.tar.gz" --strip-components 1 && \
  mkdir /lua-nginx-module && tar -zxC lua-nginx-module -f "lua-nginx-module-${VER_LUA_NGINX_MODULE}.tar.gz" --strip-components 1 && \
  mkdir /lua-resty-core && tar -zxC lua-resty-core -f "lua-resty-core-${VER_LUA_RESTY_CORE}.tar.gz" --strip-components 1 && \
  mkdir /lua-resty-lrucache && tar -zxC lua-resty-lrucache -f "lua-resty-lrucache-${VER_LUA_RESTY_LRUCACHE}.tar.gz" --strip-components 1 && \
  cd /luajit2 && make -j8 && make install && cd /

# Download sources
RUN wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx.tar.gz && \
  git clone https://github.com/vozlt/nginx-module-vts.git && \
  git clone https://github.com/yaoweibin/nginx_upstream_check_module

# Reuse same cli arguments as the nginx:alpine image used to build (but remove the erroneous -fomit-frame-pointer)
RUN CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p') && \
    CONFARGS=${CONFARGS/-Os -fomit-frame-pointer -g/-Os} && \
    mkdir -p /usr/src && \
    tar -zxC /usr/src -f nginx.tar.gz && \
    cd "/usr/src/nginx-${NGINX_VERSION}" && \
    patch -p1 < "/nginx_upstream_check_module/check_${UPSTREAM_CHECK_MODULE_PATCH_VERSION}+.patch" && \
    ./configure --with-compat $CONFARGS --with-ld-opt="-Wl,-rpath,${LUAJIT_LIB}" \
      --add-module=/nginx_upstream_check_module \
      --add-dynamic-module=/nginx-module-vts \
      --add-dynamic-module=/ngx_devel_kit \
      --add-dynamic-module=/lua-nginx-module && \
    make -j8 && make install

RUN cd /lua-resty-core && make install PREFIX=/etc/nginx
RUN cd /lua-resty-lrucache && make install PREFIX=/etc/nginx

# ENTRYPOINT /bin/sh

FROM nginx:1.21.6-alpine 
# Copy new dynamic module ngx_http_proxy_connect_module

RUN apk add --no-cache \
  pcre \
  pcre2

COPY --from=builder /usr/lib/nginx/modules/*.so /usr/lib/nginx/modules/
# Copy new nginx binary, due to patching for ngx_http_proxy_connect_module
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx

RUN rm /etc/nginx/conf.d/default.conf
# COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8080
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]