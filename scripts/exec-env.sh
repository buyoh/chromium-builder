#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")

# CHROMIUM_TAG="120.0.6099.234"
ARG_DIST_CODENAME=focal

ARG_CMD=

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
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

# -----------------------------------------------------------------------------

IMAGE_TAG=v1

IMAGE_NAME=env-chromium-build/$ARG_DIST_CODENAME-$CHROMIUM_VERSION:$IMAGE_TAG

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

# TODO: Solve space. For instance, `ls "-l src"` should be failed by invalid option.

exec docker run --init -it --rm \
  -w /mnt/work \
  $DOCKER_ARG_ENV \
  $DOCKER_ARG_MOUNTS \
  $IMAGE_NAME \
  $PRE_CMD $CMD

