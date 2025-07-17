#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")

ARG_DIST_CODENAME=focal
ARG_CHROMIUM_DIR=
ARG_GCLIENT_SYNC=false

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --cr-dir <path> : Set chromium source directory
    --cr-dir)
    ARG_CHROMIUM_DIR="$2"
    shift
    ;;
    ##  --gclient-sync  : Run gclient sync. Default is to run gclient runhooks.
    --gclient-sync)
    ARG_GCLIENT_SYNC=true
    ;;
    ##  --help, -h      : Show help
    --help|-h)
    echo "Usage: $0 [OPTION...]"
    echo ""
    grep "^ *##" $THIS_SCRIPT | sed -e "s/^ *##//"
    exit 0
    ;;
    *)
    echo "Unknow option "$arg
    exit 2
    ;;
esac
shift
done

# -----------------------------------------------------------------------------
# Check arguments

if [[ -z "$ARG_CHROMIUM_DIR" ]]; then
    echo "Error: --cr-dir is required"
    exit 1
fi

CHROMIUM_DIR=$(readlink -f "$ARG_CHROMIUM_DIR")

if [[ ! -d "$CHROMIUM_DIR" ]]; then
    echo "Error: $CHROMIUM_DIR is not a directory"
    exit 1
fi

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

cd $BASE_DIR

# if [[ -n "$ARG_CR" ]]; then
#     ARG_CHROMIUM_TAG=$(./lib/suggest_cr_tag.sh $ARG_CR)
#     if [[ -z "$ARG_CHROMIUM_TAG" ]]; then
#         echo "Error: Chromium tag not found: '$ARG_CR'"
#         exit 1
#     fi
# fi

# if [[ ! "$ARG_CHROMIUM_TAG" =~ ^[-0-9A-Za-z.-_]+$ ]]; then
#     echo "Error: Invalid chromium tag: '$ARG_CHROMIUM_TAG'"
#     exit 1
# fi

# if [[ -z "$ARG_NAME" ]]; then
#     ARG_NAME=$ARG_CHROMIUM_TAG
# fi

IMAGE_TAG=v1

DOCKER_CMD="/bin/bash /mnt/scripts/install-chromium-deps.sh"
# DOCKER_CMD="ls /mnt/scripts"

WORKING_CONTAINER_NAME=env-chromium-tmp
BASE_IMAGE_NAME=env-chromium/$ARG_DIST_CODENAME:$IMAGE_TAG
NEW_IMAGE_NAME=env-chromium-build/$ARG_DIST_CODENAME-$CHROMIUM_VERSION:$IMAGE_TAG

DOCKER_ARG_MOUNTS=""
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $CHROMIUM_DIR:/mnt/work"
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $THIS_SCRIPT_DIR/container:/mnt/scripts:ro"

DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -e ARG_GCLIENT_SYNC=$ARG_GCLIENT_SYNC"

trap 'docker rm -f $WORKING_CONTAINER_NAME > /dev/null' EXIT

docker run -it --name $WORKING_CONTAINER_NAME \
    $DOCKER_ARG_MOUNTS \
    $BASE_IMAGE_NAME $DOCKER_CMD

docker commit env-chromium-tmp $NEW_IMAGE_NAME
docker rm $WORKING_CONTAINER_NAME > /dev/null
