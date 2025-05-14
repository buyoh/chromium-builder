#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")

# CHROMIUM_TAG="120.0.6099.234"
ARG_DIST_CODENAME=focal
ARG_IMAGE_NAME=
ARG_GPU_ALL=false
ARG_XEPHYR=
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
    ##  --gpu-all       : Set `--gpus all` option
    --gpu-all)
    ARG_GPU_ALL=true
    ;;
    ##  --xephyr <width>x<height>
    ##                  : Use Xephyr and set display size (e.g. 1280x720)
    --xephyr)
    ARG_XEPHYR=$2
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

XEPHYR_DISPLAY_SIZE=
XEPHYR_DISPLAY=

if [[ -n "$ARG_XEPHYR" ]]; then
    # validate display size
    if [[ ! "$ARG_XEPHYR" =~ ^[0-9]+x[0-9]+$ ]]; then
        echo "Error: Invalid display size: '$ARG_XEPHYR'"
        exit 1
    fi
    XEPHYR_DISPLAY_SIZE=$ARG_XEPHYR
    XEPHYR_DISPLAY=:99
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

DOCKER_ARG=""
DOCKER_ARG_PRIVILEGED=""
DOCKER_ARG_MOUNTS=""
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $PWD:/mnt/work"
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $THIS_SCRIPT_DIR/container:/mnt/scripts:ro"

DOCKER_ARG_ENV=""

if [[ -n "$CRENV_USER" ]]; then
    DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e CRENV_USER=$CRENV_USER"
fi

if [[ -n "$XEPHYR_DISPLAY" ]]; then
    Xephyr -br -ac -noreset -screen "$XEPHYR_DISPLAY_SIZE" -resizeable $XEPHYR_DISPLAY &
    sleep 0.5
    # xhost +SI:localuser:root
    DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e DISPLAY=$XEPHYR_DISPLAY"
elif [[ -n "$DISPLAY" ]]; then
    DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e DISPLAY=$DISPLAY"
fi
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v /tmp/.X11-unix:/tmp/.X11-unix:ro"

# Add GPU device access for GLES support
if [[ -d /dev/dri ]]; then
    DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS --device /dev/dri:/dev/dri"
fi

# TODO: Solve space. For instance, `ls "-l src"` should be failed by invalid option.

if [[ "$ARG_GPU_ALL" == true ]]; then
    DOCKER_ARG="$DOCKER_ARG --gpus all"
    # DOCKER_ARG_PRIVILEGED="--privileged"
fi

exec docker run --init -it --rm $DOCKER_ARG \
  -w /mnt/work \
  $DOCKER_ARG_PRIVILEGED \
  $DOCKER_ARG_ENV \
  $DOCKER_ARG_MOUNTS \
  $IMAGE_NAME \
  $PRE_CMD $CMD

