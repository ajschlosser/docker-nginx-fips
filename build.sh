#!/usr/bin/env bash -u
#
# Prepare OpenSSL FIPS object module source code and build Nginx Docker image.

# Ensure that Docker is installed
command -v docker >/dev/null 2>&1 || {
    echo >&2 "\nYou need to install Docker first."
    exit 1
}

trap ctrl_c INT


# Pretty terminal colors
BOLD=$( tput bold )
RED=$( tput setaf 1 )
GREEN=$( tput setaf 2 )
WHITE=$( tput setaf 7 )
YELLOW=$(tput setaf 3)
NC=$( tput sgr0 )

# Default global configuration variables
CERTIFICATE_PATH=
DEFAULT=0
DEFAULT_CERTIFICATE_PATH="./cert"
DEFAULT_IMAGE_TAG="$USER/nginx-fips"
DEFAULT_OPENSSL_FIPS_DIR="openssl-fips-2.0.12"
DEFAULT_OPENSSL_FIPS_VERSION="2.0.10"
DEFAULT_NGINX_PATH="./nginx"
DEFAULT_NGINX_CONF_PATH="./conf"
DEFAULT_NGINX_VENDOR_PATH="$DEFAULT_NGINX_PATH/vendor"
FILENAME=
IMAGE_TAG=
NGINX_CONF_PATH=
NGINX_CONF_MOUNT_PATH=
NGINX_PATH=
NGINX_VENDOR_PATH=
NOCLEAN=0
OPENSSL_FIPS_CDROM_PATH=
OPENSSL_FIPS_DIR=
OPENSSL_FIPS_EXTRACT_PATH=
OPENSSL_FIPS_VERSION=
QUIET=""
RUN=0

##############################################################################
# Prints a description of valid command-line arguments
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
##############################################################################
print_help () {
    printf "\n\
    --default                   Use default settings; do not prompt user for input      \n\
    --openssl-fips-cdrom-path   Path for the volume (CD-ROM) with the source            \n\
    --openssl-fips-version      Version of the source to install                        \n\
    --ssl-cert-path             Path for SSL certificate(s) and key(s)                  \n\
    --nginx-conf-path           Path for Nginx conf directory to use in deployment      \n\
    --image-tag                 Tag for the Docker image to be built                    \n\
    --run                       Attempt to run the Docker image when finished           \n\
    --nginx-conf-mount-path     If the above option exists, mount this path as the Nginx\n\
                                    conf folder
    --no-clean                  Don't clean up temporary files after build              \n\
    --quiet                     Try to repress verbose Docker output                    \n\
    --help                      Show this help\n\n"
    exit 1
}

# Parse command line arguments
while getopts "h:-:" opt; do
    case "$opt" in
    -)
        case "${OPTARG}" in
            help)
                print_help
                break
                ;;
            no-clean)
                NOCLEAN=1
                ;;
            run)
                RUN=1
                ;;
            quiet)
                QUIET="-q"
                ;;
            default)
                printf "\n${WHITE}Skipping manual configuration and using default settings.${NC}\n"
                DEFAULT=1
                break
                ;;
            openssl-fips-cdrom-path)
                val="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                if [ -d "$val" ]
                then
                    OPENSSL_FIPS_CDROM_PATH="$val"
                    printf "\n${WHITE}Using OpenSSL FIPS CD-ROM path: $val${NC}\n" >&2;
                else
                    printf "\n${RED}Could not locate path: $val${NC}\n"
                fi
                ;;
            ssl-cert-path)
                val="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                if [ -d "$val" ]
                then
                    CERTIFICATE_PATH="$val"
                    printf "\n${WHITE}Using SSL certificate and key path: $val${NC}\n" >&2;
                else
                    printf "\n${RED}Could not locate path: $val${NC}\n"
                fi
                ;;
            nginx-conf-path)
                val="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                if [ -d "$val" ]
                then
                    NGINX_CONF_PATH="$val"
                    printf "\n${WHITE}Using Nginx conf folder path: $val${NC}\n" >&2;
                else
                    printf "\n${RED}Could not locate path: $val${NC}\n"
                fi
                ;;
            openssl-fips-version)
                OPENSSL_FIPS_VERSION="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                printf "${WHITE}Using OpenSSL FIPS version: $OPENSSL_FIPS_VERSION ${NC}\n" >&2;
                ;;
            image-tag)
                IMAGE_TAG="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                printf "${WHITE}Using Docker image tag: $IMAGE_TAG${NC}\n" >&2;
                ;;
            nginx-conf-mount-path)
                val="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                if [ -d "$val" ]
                then
                    NGINX_CONF_MOUNT_PATH="$val"
                    printf "\n${WHITE}Will mount Nginx conf folder path: $val${NC}\n" >&2;
                else
                    printf "\n${RED}Could not locate path: $val${NC}\n"
                fi
                ;;
            *)
                if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]
                then
                    printf "\n${RED}Unknown option --${OPTARG}${WHITE}\n" >&2
                fi
                ;;
        esac;;
    esac
done

##############################################################################
# Get user OS type and set default paths acccordingly
# Globals:
#   DEFAULT_OPENSSL_FIPS_CDROM_PATH
#   OS
# Arguments:
#   None
# Returns:
#   None
##############################################################################
get_os () {
    if [ "$(uname)" == "Darwin" ]
    then
        OS="Mac OS X"
        DEFAULT_OPENSSL_FIPS_CDROM_PATH="/Volumes/OpenSSL"
    elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]
    then
        OS="Linux"
        DEFAULT_OPENSSL_FIPS_CDROM_PATH="/media/cdrom"
    elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]
    then
        printf "\n${RED}Windows is not supported.${NC}"
    fi
}

##############################################################################
# Remove temporary folders 
# Globals:
#   DEFAULT_NGINX_PATH
#   DEFAULT_NGINX_VENDOR_PATH
#   NOCLEAN
# Arguments:
#   None
# Returns:
#   None
##############################################################################
clean_up () {

    # Remove temporary folder if it exists
    if [ -d "$DEFAULT_NGINX_VENDOR_PATH/tmp" ] && ( [ $NOCLEAN -eq 0 ] || [ $# -eq 0 ] )
    then
        printf "\n${WHITE}Removing existing temporary folder..."
        rm -rf $DEFAULT_NGINX_VENDOR_PATH/tmp
        if [ $? -ne 0 ]
        then
            printf "\n${RED}Failed to remove existing temporary folder. ${WHITE}\n"
            exit 1
        else
            printf "\n${GREEN}Temporary folder successfully removed.${WHITE}"
        fi
    fi
    
    # Remove Nginx Makefile if it exists
    if [ -s "$DEFAULT_NGINX_PATH/Makefile" ] && ( [ $NOCLEAN -eq 0 ] || [ $# -eq 0 ] )
    then
        printf "\n${WHITE}Removing existing Nginx Makefile..."
        rm $DEFAULT_NGINX_PATH/Makefile
        if [ $? -ne 0 ]
        then
            printf "\n${RED}Failed to remove Nginx Makefile. ${WHITE}\n"
            exit 1
        else
            printf "\n${GREEN}Nginx Makefile successfully removed.${WHITE}"
        fi
    fi

    # If passed an error code, exit
    if [ ${1+x} ]
    then
        dangling=$(docker images --quiet --filter "dangling=true")
        if [ $dangling ] && ( [ $NOCLEAN -eq 0 ] || [ $# -eq 0 ] )
        then
            printf "\nRemoving dangling Docker images...\n"
            sleep 1 # Docker needs time to delete related containers
            docker rmi $(docker images --quiet --filter "dangling=true")
        fi
        exit $1
    fi
}

##############################################################################
# Create a new temporary folder for the source code
# Globals:
#   NOCLEAN
#   DEFAULT_NGINX_VENDOR_PATH
# Arguments:
#   None
# Returns:
#   None
##############################################################################
set_up () {
    
    printf "\n${WHITE}Creating new temporary folder..."
    mkdir $DEFAULT_NGINX_VENDOR_PATH/tmp
    if [ $? -ne 0 ]
    then
        printf "\n${RED}Failed to create new temporary folder.${WHITE}\n"
        exit 1
    else
        printf "\n${GREEN}Temporary folder successfully created.${WHITE}"
    fi
}

##############################################################################
# Build the Nginx Docker image with the OpenSSL/FIPS source code
# Globals:
#   IMAGE_TAG
#   USER
# Arguments:
#   {String} Location of the extracted OpenSSL FIPS object module source code
# Returns:
#   None
##############################################################################
build_docker_image () {
    if [ -z $IMAGE_TAG ]
    then
        printf "\nPlease provide a tag for your Docker image.\n"
        read -p "${BOLD}(default: $DEFAULT_IMAGE_TAG): ${NC}${WHITE}" IMAGE_TAG
        if [ -z $IMAGE_TAG ]
        then
            IMAGE_TAG="$DEFAULT_IMAGE_TAG"
        fi
    fi
    printf "\nTagging image as: ${BOLD}$IMAGE_TAG${NC}${WHITE}\n"
    printf "Building image using OpenSSL FIPS object module source code path:\n\t${BOLD}$1${NC}${WHITE}\n\n"
    if [ $QUIET == "-q" ]
    then
        printf "Since the ${YELLOW}--quiet${WHITE} option was set, there won't be much output. Please be patient...\n"
    fi
    docker build        \
        $QUIET          \
        -t $IMAGE_TAG   \
        --build-arg OPENSSL_FIPS_PATH=$1 .
    if [ $? -ne 0 ]
    then
        printf "\n${RED}${BOLD}There was a problem building the Docker image ${NC}${WHITE}\n"
        clean_up $?
    else
        printf "\n${GREEN}${BOLD}You did it, buddy!${NC}${WHITE}\n"
        if [ $RUN -eq 1 ]
        then
            clean_up
            exit 0
        fi
        clean_up
        exit 0
    fi
}

##############################################################################
# Prompt the user for the OpenSSL Software Foundation CD path
# Globals:
#   DEFAULT_OPENSSL_FIPS_CDROM_PATH
#   OPENSSL_FIPS_CDROM_PATH
# Arguments:
#   None
# Returns:
#   None
##############################################################################
get_cdrom_volume_path () {
    printf "\nPlease enter the path for your OpenSSL FIPS object module CD.\n"
    read -p "${BOLD}($OS default: $DEFAULT_OPENSSL_FIPS_CDROM_PATH): ${NC}${WHITE}" openssl_path
    if [ -z $openssl_path ]
    then
        OPENSSL_FIPS_CDROM_PATH="$DEFAULT_OPENSSL_FIPS_CDROM_PATH"
    else
        if [ -d $openssl_path ]
        then
            OPENSSL_FIPS_CDROM_PATH="$openssl_path"
        else
            printf "\n${RED}Path not found: $openssl_path.${WHITE} Let's try that again.\n"
            get_cdrom_volume_path
        fi
    fi
}

##############################################################################
# Prompt the user for the OpenSSL FIPS object module version number
# Globals:
#   FILENAME
#   OPENSSL_FIPS_VERSION
# Arguments:
#   None
# Returns:
#   None
##############################################################################
get_version () {
    printf "\nPlease enter the version of the OpenSSL FIPS object module you would like\nto compile with your build.\n"
    read -p "${BOLD}(default: $DEFAULT_OPENSSL_FIPS_VERSION): ${NC}${WHITE}" OPENSSL_FIPS_VERSION
    if [ -Z $OPENSSL_FIPS_VERSION ]
    then
        OPENSSL_FIPS_VERSION="$DEFAULT_OPENSSL_FIPS_VERSION"
    fi
    FILENAME="openssl-fips-$OPENSSL_FIPS_VERSION.tar.gz"
}

##############################################################################
# Extracts the FIPS module source code, then calls build_docker_image
# Globals:
#   DEFAULT_NGINX_VENDOR_PATH
#   FILENAME
#   OPENSSL_FIPS_CDROM_PATH
#   OPENSSL_FIPS_EXTRACT_PATH
#   OPENSSL_FIPS_VERSION
# Arguments:
#   None
# Returns:
#   None
##############################################################################
get_source_code () {
    
    printf "\nExtracting OpenSSL FIPS object module $OPENSSL_FIPS_VERSION source code from $OPENSSL_FIPS_CDROM_PATH/$FILENAME...\n"

    tar -xvf $OPENSSL_FIPS_CDROM_PATH/$FILENAME -C $DEFAULT_NGINX_VENDOR_PATH/tmp
    if [ $? -ne 0 ]
    then
        printf "\n${RED}Failed to copy and extract source code.${WHITE}\n"
        clean_up $?
    else
        printf "\n${GREEN}Finished getting ${YELLOW}${BOLD}OpenSSL FIPS object module $OPENSSL_FIPS_VERSION${NC}${GREEN} source.${WHITE}\n"
    fi
    
    OPENSSL_FIPS_EXTRACT_PATH=tmp/${FILENAME%.tar.gz}
    
    build_docker_image $OPENSSL_FIPS_EXTRACT_PATH
}

##############################################################################
# Generates self-signed SSL certificates and keys
# Globals:
#   CERTIFICATE_PATH
#   DEFAULT_CERTIFICATE_PATH
#   DEFAULT_NGINX_VENDOR_PATH
# Arguments:
#   None
# Returns:
#   None
##############################################################################
generate_ssl_certificate () {
    # Ensure that OpenSSL is installed
    command -v openssl >/dev/null 2>&1 || {
        printf >&2 "${RED}You need to install OpenSSL to generate self-signed SSL certificates.${WHITE}\n"
        clean_up 1
    }
    openssl req -x509 -newkey rsa:2048 -keyout $DEFAULT_NGINX_VENDOR_PATH/tmp/key.pem -out $DEFAULT_NGINX_VENDOR_PATH/tmp/cert.pem -days XXX
    if [ $? -ne 0 ]
    then
        printf "\n${RED}Failed to generate SSL certificate and key.${WHITE}\n"
        clean_up $?
    else
        CERTIFICATE_PATH="$DEFAULT_CERTIFICATE_PATH"
        printf "\n${GREEN}Finished generating ${YELLOW}${BOLD}self-signed SSL certificate and key${NC}${GREEN}.${WHITE}\n"
    fi
}

##############################################################################
# Copies SSL certificates and keys to the temporary folder for building
# Globals:
#   CERTIFICATE_PATH
#   DEFAULT_CERTIFICATE_PATH
#   DEFAULT_NGINX_VENDOR_PATH
# Arguments:
#   None
# Returns:
#   None
##############################################################################
get_ssl_certificate () {
    
    if [ -z $CERTIFICATE_PATH ]
    then
        while true
        do
            printf "\n${WHITE}Will you be providing your own ${BOLD}${YELLOW}SSL certificate and key${NC}${WHITE}? ${BOLD}(y/n)\n"
            read -p "(default: y): ${NC}${WHITE}" yn
            case $yn in
                [Nn]* )
                    printf "\n${RED}${BOLD}WARNING:${NC}${RED} Self-signed certificates should not be used in production.${WHITE} But you knew that.\n"
                    read -rsp $"Press any key to generate a self-signed SSL certificate and key..." -n1 key
                    generate_ssl_certificate
                    break
                    ;;
                * )
                    printf "\nPlease enter the path for your SSL certificate and key.\n"
                    read -p "${BOLD}(default: $DEFAULT_CERTIFICATE_PATH): ${NC}${WHITE}" cert_path
                    if [ -z $cert_path ]
                    then
                        CERTIFICATE_PATH="$DEFAULT_CERTIFICATE_PATH"
                    else
                        if [ -d $cert_path ]
                        then
                            CERTIFICATE_PATH="$cert_path"
                        else
                            printf "\n${RED}Path not found: $cert_path.${WHITE} Let's try that again.\n"
                            get_ssl_certificate
                        fi
                    fi
                    break
                    ;;
            esac
        done
    fi
    
    mkdir $DEFAULT_NGINX_VENDOR_PATH/tmp/cert \
        && cp $CERTIFICATE_PATH/*.pem $DEFAULT_NGINX_VENDOR_PATH/tmp/cert/
    if [ $? -ne 0 ]
    then
        printf "\n${RED}Failed to copy SSL certificate(s) and key(s).${WHITE}\n"
        clean_up $?
    else
        printf "\n${GREEN}Finished copying ${YELLOW}${BOLD}SSL certificate(s) and key(s)${NC}${GREEN}.${WHITE}\n"
    fi
    
}

##############################################################################
# Copies files from a particular path to a temporary location
# Globals:
#   DEFAULT_NGINX_CONF_PATH
#   DEFAULT_NGINX_VENDOR_PATH
#   NGINX_CONF_PATH
# Arguments:
#   None
# Returns:
#   None
##############################################################################
get_nginx_conf () {
    
    if [ -z $NGINX_CONF_PATH ]
    then
        printf "\nPlease enter the path for the Nginx conf folder you would like to use.\n"
        read -p "${BOLD}(default: $DEFAULT_NGINX_CONF_PATH): ${NC}${WHITE}" conf_path
        if [ -z $conf_path ]
        then
            NGINX_CONF_PATH="$DEFAULT_NGINX_CONF_PATH"
        else
            if [ -d $conf_path ]
            then
                NGINX_CONF_PATH="$conf_path"
            else
                printf "\n${RED}Path not found: $conf_path.${WHITE} Let's try that again.\n"
                get_cdrom_volume_path
            fi
        fi
    fi
    
    mkdir $DEFAULT_NGINX_VENDOR_PATH/tmp/conf \
        && cp $NGINX_CONF_PATH/* $DEFAULT_NGINX_VENDOR_PATH/tmp/conf/
    if [ $? -ne 0 ]
    then
        printf "\n${RED}Failed to copy Nginx conf folder to temporary location.${WHITE}\n"
        clean_up $?
    else
        printf "\n${GREEN}Finished copying Nginx conf folder to temporary location.${WHITE}\n"
    fi
}

##############################################################################
# Get Nginx-related paths and copy files if necessary
# Globals:
#   CERTIFICATE_PATH
#   NGINX_CONF_PATH
# Arguments:
#   None
# Returns:
#   None
##############################################################################
get_nginx_paths () {
    get_ssl_certificate
    get_nginx_conf
}

##############################################################################
# If default flag is used, handle for the case that there is no CD-ROM in the
# default path
# Globals:
#   DEFAULT_OPENSSL_FIPS_DIR
# Arguments:
#   None
# Returns:
#   None
##############################################################################
handle_no_cd () {
    printf "\n${RED}${BOLD}WARNING:${NC}${RED} This image will not be FIPS-compliant.${WHITE} Oh, well.\n"
    read -rsp $"Press any key to continue..." -n1 key
    get_nginx_paths
    build_docker_image $DEFAULT_OPENSSL_FIPS_DIR
}

##############################################################################
# Attempts a graceful clean-up if Ctrl+C interrupt is detected
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
##############################################################################
function ctrl_c() {
    if [ $NOCLEAN -eq 0 ]
    then
        printf "\n${YELLOW}${BOLD}Attempting graceful clean-up.${NC}${WHITE}\n"
        clean_up 1
    else
        printf "\n${RED}${BOLD}Would have attempted graceful clean-up, but ${YELLOW}--no-clean${RED} option was set.${NC}${WHITE}\n"
        printf "Temporary files and dangling Docker images have ${BOLD}not${NC}${WHITE} been deleted.\n"
        exit 1
    fi
}

# Get the user OS
get_os

# Remove any existing scaffolding
clean_up

# Create temporary folder(s)
set_up

if [ $DEFAULT -eq 0 ] && [ -z $OPENSSL_FIPS_CDROM_PATH ]
then
    printf "\n\n${WHITE}This ${YELLOW}${BOLD}Dockerfile${NC}${WHITE} will build an image including ${YELLOW}${BOLD}Nginx${NC}${WHITE} compiled with \
${YELLOW}${BOLD}OpenSSL${NC}${WHITE}\nand the ${YELLOW}${BOLD}OpenSSL FIPS object module${NC}${WHITE} running on the latest Ubuntu. To be\nFIPS \
compliant, the OpenSSL FIPS object module source code must be copied\nfrom a ${YELLOW}${BOLD}CD provided by the OpenSSL Software Foundation${NC}${WHITE}."

    while true
    do
        printf "\n\n${WHITE}Do you have a CD provided by the OpenSSL Software Foundation? ${BOLD}(y/n)\n"
        read -p "(default: y): ${NC}${WHITE}" yn
        case $yn in
            [Nn]* )
                handle_no_cd
                break
                ;;
            * )
                if [ -z "$OPENSSL_FIPS_CDROM_PATH" -a "${OPENSSL_FIPS_CDROM_PATH+x}" = "x" ]
                then
                    get_cdrom_volume_path
                fi
                if [ -z "$OPENSSL_FIPS_VERSION" -a "${OPENSSL_FIPS_VERSION+x}" = "x" ]
                then
                    get_version
                fi
                get_nginx_paths
                get_source_code
                break
                ;;
        esac
    done
else
    if [ -z $OPENSSL_FIPS_CDROM_PATH ]
    then
        OPENSSL_FIPS_CDROM_PATH="$DEFAULT_OPENSSL_FIPS_CDROM_PATH"
        printf "\n${WHITE}Using OpenSSL Software Foundation CD-ROM path: $OPENSSL_FIPS_CDROM_PATH\n"
    fi
    if [ -z $NGINX_CONF_PATH]
    then
        NGINX_CONF_PATH="$DEFAULT_NGINX_CONF_PATH"
        printf "${WHITE}Using Nginx conf folder path: $NGINX_CONF_PATH\n"
    fi
    if [ -z $CERTIFICATE_PATH ]
    then
        CERTIFICATE_PATH="$DEFAULT_CERTIFICATE_PATH"
        printf "${WHITE}Using SSL certificate path: $CERTIFICATE_PATH\n"
    fi
    if [ -z $FILENAME ]
    then
        FILENAME="openssl-fips-$DEFAULT_OPENSSL_FIPS_VERSION.tar.gz"
        printf "${WHITE}Using OpenSSL FIPS object module version: $DEFAULT_OPENSSL_FIPS_VERSION\n"
    fi
    if [ -z $IMAGE_TAG ]
    then
        IMAGE_TAG="$DEFAULT_IMAGE_TAG"
        printf "${WHITE}Using Docker image tag: $IMAGE_TAG\n"
    fi
    if [ -d "$OPENSSL_FIPS_CDROM_PATH" ]
    then
        get_nginx_paths
        get_source_code
    else
        handle_no_cd
    fi
fi
