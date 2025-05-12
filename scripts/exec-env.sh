#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")

# CHROMIUM_TAG="120.0.6099.234"
ARG_DIST_CODENAME=focal
ARG_IMAGE_NAME=
ARG_CMD=
ARG_USERNAME=

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --image         : Set image name (e.g. env-chromium/focal:v1)
    --image)
    ARG_IMAGE_NAME=$2
    shift
    ;;
    ##  --username      : Set username (e.g. developer)
    ##                  : Default is root
    ##                  : This option is used to run the command as a non-root user
    ##                  : in the container.
    --username)
    ARG_USERNAME=$2
    shift
    ;;
    ##  --help, -h      : Show help
    --help|-h)
    echo "Usage: $0 [OPTION...]"
    echo ""
    grep "^ *##" $THIS_SCRIPT | sed -e "s/^ *##//"
    exit 0
    ;;
    --)
    shift
    ARG_CMD="$@"
    break
    ;;
    *)
    echo "Unknow option "$arg
    exit 2
    ;;
esac
shift
done

# -----------------------------------------------------------------------------

CHROMIUM_DIR=.
CRENV_USER=

if [[ ! -f "$CHROMIUM_DIR/src/chrome/VERSION" ]]; then
    echo "Error: $CHROMIUM_DIR is not a chromium source directory"
    echo "Error: $CHROMIUM_DIR/src/chrome/VERSION not found"
    exit 1
fi

CHROMIUM_VERSION=$(source "$CHROMIUM_DIR/src/chrome/VERSION" && echo "$MAJOR.$MINOR.$BUILD.$PATCH")

if [[ -z "$CHROMIUM_VERSION" ]]; then
    echo "Error: $CHROMIUM_DIR/src/chrome/VERSION is empty"
    exit 1
fi

if [[ ! "$CHROMIUM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid chromium version: '$CHROMIUM_VERSION'"
    exit 1
fi

if [[ -n "$ARG_USERNAME" ]]; then
    # validate username
    if [[ ! "$ARG_USERNAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        echo "Error: Invalid username: '$ARG_USERNAME'"
        exit 1
    fi
    if [[ "$ARG_USERNAME" != "root" ]]; then
        CRENV_USER=$ARG_USERNAME
    fi
fi

# -----------------------------------------------------------------------------

IMAGE_TAG=v1

if [[ -n "$ARG_IMAGE_NAME" ]]; then
    IMAGE_NAME=$ARG_IMAGE_NAME:$IMAGE_TAG
else
    IMAGE_NAME=env-chromium-build/$ARG_DIST_CODENAME-$CHROMIUM_VERSION:$IMAGE_TAG
fi

if [[ -z $(docker images -q $IMAGE_NAME ) ]]; then
    echo "Error: Docker image $IMAGE_NAME not found"
    exit 1
fi

# -----------------------------------------------------------------------------

PRE_CMD="/bin/bash /mnt/scripts/cmd-prepare.sh"

CMD=/bin/bash
if [[ -n "$ARG_CMD" ]]; then
    CMD=$ARG_CMD
fi

DOCKER_ARG_MOUNTS=""
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $PWD:/mnt/work"
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $THIS_SCRIPT_DIR/container:/mnt/scripts:ro"

DOCKER_ARG_ENV=""

if [[ -n "$CRENV_USER" ]]; then
    DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e CRENV_USER=$CRENV_USER"
fi

if [[ -n "$DISPLAY" ]]; then
    DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e DISPLAY=$DISPLAY"
fi
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v /tmp/.X11-unix:/tmp/.X11-unix:ro"

# Add GPU device access for GLES support
if [[ -d /dev/dri ]]; then
    DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS --device /dev/dri:/dev/dri"
fi

# TODO: XAUTHORITY
# XAUTH=/tmp/.docker.xauth
# touch $XAUTH
# xauth nlist $DISPLAY | sed -e 's/^..../ffff/' | xauth -f $XAUTH nmerge -
# DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $XAUTH:$XAUTH:rw"
# DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e XAUTHORITY=$XAUTH"

# TODO: Solve space. For instance, `ls "-l src"` should be failed by invalid option.

exec docker run --init -it --rm \
  -w /mnt/work \
  $DOCKER_ARG_ENV \
  $DOCKER_ARG_MOUNTS \
  $IMAGE_NAME \
  $PRE_CMD $CMD

