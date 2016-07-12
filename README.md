# Nginx Dockerfile with OpenSSL using the OpenSSL FIPS Object Module

This repository contains a Dockerfile that builds an Ubuntu container running a custom build of Nginx. The custom build includes OpenSSL, the OpenSSL FIPS Object Module, ZLib, PCRE, and the HTTP Redis module for Nginx all compiled from source.

### References

* [Building nginx from Sources](http://nginx.org/en/docs/configure.html) [sic]
* [OpenSSL and FIPS 140-2](https://www.openssl.org/docs/fipsvalidation.html)
* [OpenSSL Compilation and Installation](https://wiki.openssl.org/index.php/Compilation_and_Installation)
