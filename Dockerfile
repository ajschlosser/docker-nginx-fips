# Start with the latest ubuntu image
FROM ubuntu

# Install OpenSSL & Nginx dependencies
RUN \
  apt-get update && \
  apt-get install --no-install-recommends --no-install-suggests -y \
      file \
      gcc \
      g++ \
      make \
      podlators-perl

# Set environment variables
ENV NGINX_PATH          /tmp/nginx
ENV VENDOR_PATH         $NGINX_PATH/vendor
ENV OPENSSL_FIPS_PATH   $VENDOR_PATH/openssl-fips-2.0.12
ENV HTTP_REDIS_PATH     $VENDOR_PATH/ngx_http_redis-0.3.8
ENV ZLIB_PATH           $VENDOR_PATH/zlib-1.2.8
ENV PCRE_PATH           $VENDOR_PATH/pcre-8.39
ENV OPENSSL_PATH        $VENDOR_PATH/openssl-1.0.2h

# Copy Nginx, OpenSSL, OpenSSL FIPS, HTTP Redis, ZLib, and PCRE
COPY nginx /tmp/nginx

# Configure and install OpenSSL FIPS
WORKDIR $OPENSSL_FIPS_PATH
RUN ./config
WORKDIR $OPENSSL_FIPS_PATH
RUN make
WORKDIR $OPENSSL_FIPS_PATH
RUN make install

# Configure OpenSSL (with FIPS)
WORKDIR $OPENSSL_PATH
RUN ./config fips

# Configure and install Nginx
WORKDIR $NGINX_PATH
RUN ./auto/configure \
    --add-module=$HTTP_REDIS_PATH \
    --with-zlib=$ZLIB_PATH \
    --with-pcre=$PCRE_PATH \
    --with-openssl=$OPENSSL_PATH \
    --with-http_ssl_module
WORKDIR $NGINX_PATH
RUN make
WORKDIR $NGINX_PATH
RUN make install

# Expose ports
EXPOSE 80
EXPOSE 443

# Run Nginx
CMD ["/usr/local/nginx/sbin/nginx", "-g", "daemon off;"]
