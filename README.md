# docker-nginx-fips : Create an Nginx Docker image with FIPS compliant OpenSSL

## Overview

This repository contains a build script, `build.sh`, that prepares files and arguments in order to build a Docker image from the Dockerfile. It contains source code for Nginx, the Nginx HTTP Redis module, ZLib, PCRE, OpenSSL, and the OpenSSL FIPS object module (although the latter is required to be provided via an official OpenSSL Software Foundation CD-ROM) -- all of which is compiled according to the build script. If the instructions are followed properly, then running `build.sh` should result in a Docker image running an Nginx API gateway with FIPS-compliant OpenSSL.

## Usage

Run `build.sh` and follow the instructions, providing input when prompted.

#### Options

The build script also accepts the following command-line arguments:

    --default                   Use default settings; do not prompt user for input
    --openssl-fips-cdrom-path   Path for the volume (CD-ROM) with the source
    --openssl-fips-version      Version of the source to install
    --ssl-cert-path             Path for SSL certificate(s) and key(s)
    --nginx-conf-path           Path for Nginx conf directory to use in deployment
    --image-tag                 Tag for the Docker image to be built
    --run                       Attempt to run the Docker image when finished
    --nginx-conf-mount-path     If the above option exists, mount this path as the Nginx conf folder (optional)
    --no-clean                  Don't clean up temporary files after build
    --quiet                     Try to repress verbose Docker output
    --help                      Show this help
    
The `--default` option overrules all others but `--image-tag`, `--run`, `--nginx-conf-mount-path`, `--no-clean`, and `--quiet`. If no OpenSSL Software Foundation CD-ROM is provided, and the image is instead built using the source code provided in this repository, then `--openssl-fips-cdrom-path` and `--openssl-fips-version` will be ignored. (In this case, however, the image will not necessarily be FIPS-compliant.)

#### Example

In general, running the build script with the `--default` option is the equivalent of executing the following (assuming Mac OS X for `--openssl-fips-cdrom-path`):

```sh
./build.sh \
    --openssl-fips-cdrom-path /Volumes/OpenSSL  \
    --openssl-fips-version 2.0.10               \
    --ssl-cert-path ./cert                      \
    --nginx-conf-path ./conf                    \
    --image-tag ${USER}/nginx-fips
```

If an option is not provided, then the user will be prompted for the information by the script. It is possible eventually to accept all default values in this case by pressing the `Enter`/`Return` key at every prompt. In other words, running the script with no options and accepting all of the default options when prompted is the equivalent of running the script with the `--default` option.

For development purposes, it's generally fine to use the `--default` option. If no CD-ROM is detected, it will default to the FIPS object module source code provided in this repo (currently at least version `2.0.12`).

The default build can be executed with certain additional options, e.g.

```sh
./build.sh \
    --image-tag dingus              \
    --run                           \
    --nginx-conf-mount-path ./conf  \
    --no-clean                      \
    --quiet                         \
    --default
```

If the above command is executed, a default Docker image (tagged 'dingus') will be built with verbose Docker output suppressed; after it is built, it will be run with a mounted volume, './conf'. If it is interrupted or finishes, it will not attempt to clean up temporary files and folders. Note that the `--default` option is last in this case.

## Details

Specifically, running `build.sh` will accomplish the following:

1. Ask the user if they have an OpenSSL Software Foundation CD-ROM containing archives of various OpenSSL FIPS object module versions.
2. If they do not, use the source code provided in this repository. Warn the user that the image that will eventually be built will not be FIPS-compliant.
3. If they do, ask the user for the path of the volume.
4. Ask the user for the OpenSSL FIPS object module version that they would like to compile with OpenSSL and Nginx.
5. Prepare user-provided SSL certificate and keys, or generate self-signed ones for development and testing*
6. Copy OpenSSL FIPS object module source code, SSL-related files, and the indicated (or default) Nginx conf folder to a temporary location for usage with the `Dockerfile`.
7. Run `docker build`.

\* Generic self-signed ones are provided in this repo for your convenience

The `Dockerfile` then instructs that the image be built as follows:

1. Begin with the latest Ubuntu image.
2. Install necessary dependencies (`gcc`, `make`, etc.).
3. Copy the Nginx/OpenSSL/etc. source code from this repository (and configured from the build script) to the image.
4. Configure and install the OpenSSL FIPS object module.
5. Configure and install OpenSSL with FIPS.
6. Configure and install Nginx with FIPS-compliant OpenSSL.
7. Link binaries (for convenience) and expose requisite ports.

Interrupting the script at any point via ```Ctrl+C``` will trigger a graceful clean-up, removing all temporary files and, if present, dangling Docker images.

## Todo

* Nginx confs need to be written
