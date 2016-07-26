##############################################################################
# IMAGES
##############################################################################

# Start with the latest Ubuntu image
FROM ubuntu

##############################################################################
# VARIABLES
##############################################################################

# Set environment variables
ENV TMP_PATH            /tmp
ENV NGINX_SOURCE_PATH   $TMP_PATH/nginx-1.11.2
ENV NGINX_INSTALL_PATH  /usr/local/nginx
ENV SSL_INSTALL_PATH    /usr/local/ssl
ENV HTTP_REDIS_PATH     $TMP_PATH/ngx_http_redis-0.3.8
ENV ZLIB_PATH           $TMP_PATH/zlib-1.2.8
ENV PCRE_PATH           $TMP_PATH/pcre-8.39
ENV OPENSSL_PATH        $TMP_PATH/openssl-1.0.2h
ENV OPENSSL_FIPS        1
ENV PID_PATH            /var/run/nginx.pid
ENV LOG_PATH            /var/log/nginx
ENV ERROR_LOG_PATH      $LOG_PATH/error.log
ENV ACCESS_LOG_PATH     $LOG_PATH/access.log

# Set build arguments
ARG OPENSSL_FIPS_PATH=openssl-fips-2.0.12
ARG SRC_TMP_PATH=tmp
ARG SRC_PATH=src
ARG LIB_PATH=lib

##############################################################################
# COPY SOURCE CODE
##############################################################################

# Copy Nginx, OpenSSL, OpenSSL FIPS, HTTP Redis, ZLib, and PCRE source code
COPY $SRC_PATH      $TMP_PATH/

# Copy any temporary pre-build files, including source code
COPY $SRC_TMP_PATH  $TMP_PATH/

# Copy initial Nginx conf(s) and SSL certificate(s)/key(s)
COPY $LIB_PATH      $TMP_PATH/

##############################################################################
# INSTALL DEPENDENCIES
##############################################################################

# Install dependencies for compiling OpenSSL & Nginx
RUN apt-get update &&           \
    apt-get install             \
      --no-install-recommends   \
      --no-install-suggests -y  \
      file                      \
      g++                       \
      make

##############################################################################
# CONFIGURE AND INSTALL OPENSSL
##############################################################################

# Configure and install OpenSSL FIPS
WORKDIR $TMP_PATH/$OPENSSL_FIPS_PATH
RUN ./config
RUN make
RUN make install

# Configure OpenSSL (with FIPS)
WORKDIR $OPENSSL_PATH
RUN ./config fips
RUN make
RUN make install

##############################################################################
# CONFIGURE AND INSTALL NGINX
##############################################################################

# Configure and install Nginx (with OpenSSL & FIPS module)
WORKDIR $NGINX_SOURCE_PATH
RUN ./configure                         \
    --add-module=$HTTP_REDIS_PATH       \
    --with-zlib=$ZLIB_PATH              \
    --with-pcre=$PCRE_PATH              \
    --with-openssl=$OPENSSL_PATH        \
    --with-http_ssl_module              \
    --pid-path=$PID_PATH                \
    --error-log-path=$ERROR_LOG_PATH    \
    --http-log-path=$ACCESS_LOG_PATH    \
    --with-ipv6
RUN make
RUN make install

##############################################################################
# COPY NGINX- AND SSL-RELATED FILES
##############################################################################

# Copy initial Nginx conf
COPY $LIB_PATH/conf $NGINX_INSTALL_PATH/conf

# Copy SSL certificate(s)/key(s)
COPY $LIB_PATH/certs $SSL_INSTALL_PATH/certs

##############################################################################
# LINKS
##############################################################################

# Link binaries
RUN ln -s /usr/local/nginx/sbin/nginx /usr/bin/nginx && \
    ln -s /usr/local/ssl/bin/openssl /usr/bin/openssl

# Forward request and error logs to Docker log collector
RUN ln -sf /dev/stdout $ACCESS_LOG_PATH& \
    ln -sf /dev/stderr $ERROR_LOG_PATH

##############################################################################
# EXPOSE PORTS AND RUN NGINX
##############################################################################

# Expose ports
EXPOSE 80
EXPOSE 443

# Run Nginx
CMD ["/usr/local/nginx/sbin/nginx", "-g", "daemon off;"]
