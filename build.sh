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
DEFAULT_CONTAINER_NAME="api-gateway"
DEFAULT_EXPOSE_PORTS="-p 8080:80 -p 4443:443"
DEFAULT_IMAGE_TAG="$USER/nginx-fips"
DEFAULT_OPENSSL_FIPS_DIR="openssl-fips-2.0.12"
DEFAULT_OPENSSL_FIPS_VERSION="2.0.10"
DEFAULT_NGINX_PATH="./nginx"
DEFAULT_NGINX_CONF_PATH="./conf"
DEFAULT_CERTIFICATE_PATH="$DEFAULT_NGINX_CONF_PATH/ssl_certificates"
DEFAULT_NGINX_VENDOR_PATH="$DEFAULT_NGINX_PATH/vendor"
CONTAINER_NAME=
FILENAME=
IMAGE_TAG=
NGINX_CONF_PATH=
NGINX_CONF_MOUNT_PATH=
NGINX_PATH=
NGINX_VENDOR_PATH=
NOCLEAN=0
NOEXPOSE=0
OPENSSL_FIPS_CDROM_PATH=
OPENSSL_FIPS_DIR=
OPENSSL_FIPS_EXTRACT_PATH=
OPENSSL_FIPS_VERSION=
QUIET=""
RUN=0
EXPOSE_PORTS=""

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
    --name                      If the --run option exists, the container will have this\n\
                                    name
    --port                      If the --run option exists, the container will expose   \n\
                                    this port (can include as many as needed, e.g.      \n\
                                    --port 8080:80 --port 4443:443)                     \n\
    --no-expose                 If the --run option exists, don't expose any ports      \n\
    --nginx-conf-mount-path     If the --run option exists, mount this path as the Nginx\n\
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
                printf "${NC}An attempt will be made to run a container after the image is built.\n"
                RUN=1
                ;;
            no-expose)
                NOEXPOSE=1
                ;;
            port)
                EXPOSE_PORTS="$EXPOSE_PORTS -p ${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                ;;
            quiet)
                QUIET="-q"
                ;;
            default)
                printf "${NC}Skipping manual build configuration and using default settings.${NC}\n"
                DEFAULT=1
                break
                ;;
            openssl-fips-cdrom-path)
                val="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                if [ -d "$val" ]
                then
                    OPENSSL_FIPS_CDROM_PATH="$val"
                    printf "\n${NC}Using OpenSSL FIPS CD-ROM path: $val${NC}\n" >&2;
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
                    printf "\n${NC}Using SSL certificate and key path: $val${NC}\n" >&2;
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
                    printf "\n${NC}Using Nginx conf folder path: $val${NC}\n" >&2;
                else
                    printf "\n${RED}Could not locate path: $val${NC}\n"
                fi
                ;;
            openssl-fips-version)
                OPENSSL_FIPS_VERSION="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                printf "${NC}Using OpenSSL FIPS version: $OPENSSL_FIPS_VERSION ${NC}\n" >&2;
                ;;
            image-tag)
                IMAGE_TAG="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                printf "${NC}Using Docker image tag: $IMAGE_TAG${NC}\n" >&2;
                ;;
            nginx-conf-mount-path)
                val="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                if [ -d "$val" ]
                then
                    NGINX_CONF_MOUNT_PATH="$val"
                    printf "${NC}Will mount Nginx conf folder path: $val${NC}\n" >&2;
                else
                    printf "\n${RED}Could not locate path: $val${NC}\n"
                fi
                ;;
            name)
                CONTAINER_NAME="${!OPTIND}"
                OPTIND=$(( $OPTIND + 1 ))
                printf "${NC}Using Docker container name: $CONTAINER_NAME${NC}\n" >&2;
                ;;
            *)
                if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]
                then
                    printf "\n${RED}Unknown option --${OPTARG}${NC}\n" >&2
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
        printf "\n${NC}Removing existing temporary folder...\n"
        rm -rf $DEFAULT_NGINX_VENDOR_PATH/tmp
        if [ $? -ne 0 ]
        then
            printf "${RED}Failed to remove existing temporary folder. ${NC}\n"
            exit 1
        else
            printf "${GREEN}Temporary folder successfully removed.${NC}\n"
        fi
    fi
    
    # Remove Nginx Makefile if it exists
    if [ -s "$DEFAULT_NGINX_PATH/Makefile" ] && ( [ $NOCLEAN -eq 0 ] || [ $# -eq 0 ] )
    then
        printf "\n${NC}Removing existing Nginx Makefile..."
        rm $DEFAULT_NGINX_PATH/Makefile
        if [ $? -ne 0 ]
        then
            printf "\n${RED}Failed to remove Nginx Makefile. ${NC}\n"
            exit 1
        else
            printf "\n${GREEN}Nginx Makefile successfully removed.${NC}"
        fi
    fi

    dangling=$(docker images --quiet --filter "dangling=true")
    if [ $dangling ] && ( [ $NOCLEAN -eq 0 ] || [ $# -eq 0 ] )
    then
        printf "\nRemoving dangling Docker images...\n"
        sleep 1 # Docker needs time to delete related containers
        docker rmi $(docker images --quiet --filter "dangling=true")
    fi

    # If passed an error code, exit
    if [ ${1+x} ]
    then
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
    
    printf "${NC}Creating new temporary folder...\n"
    mkdir $DEFAULT_NGINX_VENDOR_PATH/tmp
    if [ $? -ne 0 ]
    then
        printf "${RED}Failed to create new temporary folder.${NC}\n"
        exit 1
    else
        printf "${GREEN}Temporary folder successfully created.${NC}\n"
    fi
}

##############################################################################
# Prompt the user to provide a name for their Docker container
# Globals:
#   CONTAINER_NAME
#   DEFAULT_CONTAINER_NAME
# Arguments:
#   None
# Returns:
#   None
##############################################################################
get_container_name () {
    printf "\nPlease enter a name for your container. It ${BOLD}must${NC}${NC} be unique.\n"
    read -ep "${BOLD}(default: $DEFAULT_CONTAINER_NAME): ${NC}${NC}" container_name
    if [ -z $container_name ]
    then
        CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
    else
        CONTAINER_NAME="$container_name"
    fi
}

##############################################################################
# Run Docker using the built image
# Globals:
#   CONTAINER_NAME
#   IMAGE_TAG
# Arguments:
#   None
# Returns:
#   None
##############################################################################
run_docker () {
    docker run                  \
        -d                      \
        --name $CONTAINER_NAME  \
        $1                      \
        $EXPOSE_PORTS           \
        $IMAGE_TAG &            \
    wait
    clean_up
    exit 0
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
        read -ep "${BOLD}(default: $DEFAULT_IMAGE_TAG): ${NC}${NC}" IMAGE_TAG
        if [ -z $IMAGE_TAG ]
        then
            IMAGE_TAG="$DEFAULT_IMAGE_TAG"
        fi
    fi
    printf "\nTagging image as: ${BOLD}$IMAGE_TAG${NC}${NC}\n"
    printf "Building image using OpenSSL FIPS object module source code path:\n\t${BOLD}$1${NC}${NC}\n\n"
    if [ "$QUIET" == "-q" ]
    then
        printf "Since the ${YELLOW}--quiet${NC} option was set, there won't be much output. Please be patient...\n"
    fi
    docker build        \
        $QUIET          \
        -t $IMAGE_TAG   \
        --build-arg OPENSSL_FIPS_PATH=$1 .
    if [ $? -ne 0 ]
    then
        printf "\n${RED}${BOLD}There was a problem building the Docker image ${NC}${NC}\n"
        clean_up $?
    else
        printf "\n${GREEN}${BOLD}You did it, buddy!${NC}${NC}\n"
        if [ $RUN -eq 1 ]
        then
            if [ -z $CONTAINER_NAME ]
            then
                get_container_name
            fi
            if [ -z "$EXPOSE_PORTS" ]
            then
                if [ $NOEXPOSE -eq 0 ]
                then
                    EXPOSE_PORTS="$DEFAULT_EXPOSE_PORTS"
                else
                    EXPOSE_PORTS=""
                fi
            fi
            if [ -z $NGINX_CONF_MOUNT_PATH ]
            then
                mount_path=""
            else
                mount_path="-v $NGINX_CONF_MOUNT_PATH:/usr/local/nginx/conf"
            fi
            run_docker "$mount_path"
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
    read -ep "${BOLD}($OS default: $DEFAULT_OPENSSL_FIPS_CDROM_PATH): ${NC}${NC}" openssl_path
    if [ -z $openssl_path ]
    then
        OPENSSL_FIPS_CDROM_PATH="$DEFAULT_OPENSSL_FIPS_CDROM_PATH"
    else
        if [ -d $openssl_path ]
        then
            OPENSSL_FIPS_CDROM_PATH="$openssl_path"
        else
            printf "\n${RED}Path not found: $openssl_path.${NC} Let's try that again.\n"
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
    read -ep "${BOLD}(default: $DEFAULT_OPENSSL_FIPS_VERSION): ${NC}${NC}" OPENSSL_FIPS_VERSION
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
        printf "\n${RED}Failed to copy and extract source code.${NC}\n"
        clean_up $?
    else
        printf "\n${GREEN}Finished getting ${YELLOW}${BOLD}OpenSSL FIPS object module $OPENSSL_FIPS_VERSION${NC}${GREEN} source.${NC}\n"
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
        printf >&2 "${RED}You need to install OpenSSL to generate self-signed SSL certificates.${NC}\n"
        clean_up 1
    }
    openssl req -x509 -newkey rsa:2048 -keyout $DEFAULT_NGINX_VENDOR_PATH/tmp/key.pem -out $DEFAULT_NGINX_VENDOR_PATH/tmp/cert.pem -days XXX
    if [ $? -ne 0 ]
    then
        printf "\n${RED}Failed to generate SSL certificate and key.${NC}\n"
        clean_up $?
    else
        CERTIFICATE_PATH="$DEFAULT_CERTIFICATE_PATH"
        printf "\n${GREEN}Finished generating ${YELLOW}${BOLD}self-signed SSL certificate and key${NC}${GREEN}.${NC}\n"
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
            printf "\n${NC}Will you be providing your own ${BOLD}${YELLOW}SSL certificate and key${NC}${NC}? ${BOLD}(y/n)\n"
            read -ep "(default: y): ${NC}${NC}" yn
            case $yn in
                [Nn]* )
                    printf "\n${RED}${BOLD}WARNING:${NC}${RED} Self-signed certificates should not be used in production.${NC} But you knew that.\n"
                    read -resp $"Press any key to generate a self-signed SSL certificate and key..." -n1 key
                    generate_ssl_certificate
                    break
                    ;;
                * )
                    printf "\nPlease enter the path for your SSL certificate and key.\n"
                    read -ep "${BOLD}(default: $DEFAULT_CERTIFICATE_PATH): ${NC}${NC}" cert_path
                    if [ -z $cert_path ]
                    then
                        CERTIFICATE_PATH="$DEFAULT_CERTIFICATE_PATH"
                    else
                        if [ -d $cert_path ]
                        then
                            CERTIFICATE_PATH="$cert_path"
                        else
                            printf "\n${RED}Path not found: $cert_path.${NC} Let's try that again.\n"
                            get_ssl_certificate
                        fi
                    fi
                    break
                    ;;
            esac
        done
    fi
    
    mkdir $DEFAULT_NGINX_VENDOR_PATH/tmp/conf/cert \
        && cp $CERTIFICATE_PATH/*.pem $DEFAULT_NGINX_VENDOR_PATH/tmp/conf/cert/
    if [ $? -ne 0 ]
    then
        printf "\n${RED}Failed to copy SSL certificate(s) and key(s).${NC}\n"
        clean_up $?
    else
        printf "${GREEN}Finished copying ${YELLOW}${BOLD}SSL certificate(s) and key(s)${NC}${GREEN}.${NC}\n"
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
        read -p "${BOLD}(default: $DEFAULT_NGINX_CONF_PATH): ${NC}${NC}" conf_path
        if [ -z $conf_path ]
        then
            NGINX_CONF_PATH="$DEFAULT_NGINX_CONF_PATH"
        else
            if [ -d $conf_path ]
            then
                NGINX_CONF_PATH="$conf_path"
            else
                printf "\n${RED}Path not found: $conf_path.${NC} Let's try that again.\n"
                get_cdrom_volume_path
            fi
        fi
    fi
    mkdir $DEFAULT_NGINX_VENDOR_PATH/tmp/conf \
        && cp $NGINX_CONF_PATH/**/* $DEFAULT_NGINX_VENDOR_PATH/tmp/conf/
    if [ $? -ne 0 ]
    then
        printf "\n${RED}Failed to copy Nginx conf folder to temporary location.${NC}\n"
        clean_up $?
    else
        printf "${GREEN}Finished copying Nginx conf folder to temporary location.${NC}\n"
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
    get_nginx_conf
    get_ssl_certificate
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
    printf "\n${RED}${BOLD}WARNING:${NC}${RED} This image will not be FIPS-compliant.${NC} Oh, well.\n"
    read -resp $"Press any key to continue..." -n1 key
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
        printf "\n${YELLOW}${BOLD}Attempting graceful clean-up.${NC}${NC}\n"
        clean_up 1
    else
        printf "\n${RED}${BOLD}Would have attempted graceful clean-up, but ${YELLOW}--no-clean${RED} option was set.${NC}${NC}\n"
        printf "Temporary files and dangling Docker images have ${BOLD}not${NC}${NC} been deleted.\n"
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
    printf "\n\n${NC}This ${YELLOW}${BOLD}Dockerfile${NC}${NC} will build an image including ${YELLOW}${BOLD}Nginx${NC}${NC} compiled with \
${YELLOW}${BOLD}OpenSSL${NC}${NC}\nand the ${YELLOW}${BOLD}OpenSSL FIPS object module${NC}${NC} running on the latest Ubuntu. To be\nFIPS \
compliant, the OpenSSL FIPS object module source code must be copied\nfrom a ${YELLOW}${BOLD}CD provided by the OpenSSL Software Foundation${NC}${NC}."

    while true
    do
        printf "\n\n${NC}Do you have a CD provided by the OpenSSL Software Foundation? ${BOLD}(y/n)\n"
        read -ep "(default: y): ${NC}${NC}" yn
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
        printf "${NC}Using OpenSSL Software Foundation CD-ROM path: $OPENSSL_FIPS_CDROM_PATH\n"
    fi
    if [ -z $NGINX_CONF_PATH]
    then
        NGINX_CONF_PATH="$DEFAULT_NGINX_CONF_PATH"
        printf "${NC}Using Nginx conf folder path: $NGINX_CONF_PATH\n"
    fi
    if [ -z $CERTIFICATE_PATH ]
    then
        CERTIFICATE_PATH="$DEFAULT_CERTIFICATE_PATH"
        printf "${NC}Using SSL certificate path: $CERTIFICATE_PATH\n"
    fi
    if [ -z $FILENAME ]
    then
        FILENAME="openssl-fips-$DEFAULT_OPENSSL_FIPS_VERSION.tar.gz"
        printf "${NC}Using OpenSSL FIPS object module version: $DEFAULT_OPENSSL_FIPS_VERSION\n"
    fi
    if [ -z $IMAGE_TAG ]
    then
        IMAGE_TAG="$DEFAULT_IMAGE_TAG"
        printf "${NC}Using Docker image tag: $IMAGE_TAG\n"
    fi
    if [ -d "$OPENSSL_FIPS_CDROM_PATH" ]
    then
        get_nginx_paths
        get_source_code
    else
        handle_no_cd
    fi
fi
