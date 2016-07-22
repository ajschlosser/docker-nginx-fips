# Start with the latest Ubuntu image
FROM ubuntu

# Install dependencies for compiling OpenSSL & Nginx
RUN apt-get update &&           \
    apt-get install             \
      --no-install-recommends   \
      --no-install-suggests -y  \
      file                      \
      gcc                       \
      g++                       \
      make                      \
      podlators-perl

# Set environment variables
ENV NGINX_SOURCE_PATH   /tmp/nginx
ENV NGINX_INSTALL_PATH  /usr/local/nginx
ENV VENDOR_PATH         $NGINX_SOURCE_PATH/vendor
ENV HTTP_REDIS_PATH     $VENDOR_PATH/ngx_http_redis-0.3.8
ENV ZLIB_PATH           $VENDOR_PATH/zlib-1.2.8
ENV PCRE_PATH           $VENDOR_PATH/pcre-8.39
ENV OPENSSL_PATH        $VENDOR_PATH/openssl-1.0.2h
ENV OPENSSL_FIPS        1

# Set build arguments
ARG OPENSSL_FIPS_PATH=openssl-fips-2.0.12

# Copy Nginx, OpenSSL, OpenSSL FIPS, HTTP Redis, ZLib, and PCRE source code
COPY nginx $NGINX_SOURCE_PATH

# Configure and install OpenSSL FIPS
WORKDIR $VENDOR_PATH/$OPENSSL_FIPS_PATH
RUN ./config
RUN make
RUN make install

# Configure OpenSSL (with FIPS)
WORKDIR $OPENSSL_PATH
RUN ./config fips
RUN make
RUN make install

# Configure and install Nginx (with OpenSSL & FIPS module)
WORKDIR $NGINX_SOURCE_PATH
RUN ./auto/configure              \
    --add-module=$HTTP_REDIS_PATH \
    --with-zlib=$ZLIB_PATH        \
    --with-pcre=$PCRE_PATH        \
    --with-openssl=$OPENSSL_PATH  \
    --with-http_ssl_module        \
    --with-ipv6
RUN make
RUN make install

# Copy SSL certificate/key and initial Nginx conf
COPY nginx/tmp/conf/*  $NGINX_INSTALL_PATH/conf/
COPY nginx/tmp/cert/*  $NGINX_INSTALL_PATH/conf/cert

# Link binaries
RUN ln -s /usr/local/nginx/sbin/nginx /usr/bin/nginx && \
    ln -s /usr/local/ssl/bin/openssl /usr/bin/openssl

# Forward request and error logs to Docker log collector
RUN ln -sf /dev/stdout $NGINX_INSTALL_PATH/logs/access.log && \
    ln -sf /dev/stderr $NGINX_INSTALL_PATH/logs/error.log

# Expose ports
EXPOSE 80
EXPOSE 443

# Run Nginx
CMD ["/usr/local/nginx/sbin/nginx", "-g", "daemon off;"]
