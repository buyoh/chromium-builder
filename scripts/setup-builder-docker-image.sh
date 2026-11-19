#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f "$0")
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")
source "$BASE_DIR/lib/common.sh"

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
    grep "^ *##" "$THIS_SCRIPT" | sed -e "s/^ *##//"
    exit 0
    ;;
    *)
    echo "Unknow option $arg"
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

CHROMIUM_VERSION=$(read_chromium_version "$CHROMIUM_DIR")

# -----------------------------------------------------------------------------

cd "$BASE_DIR"

DOCKER_CMD=(/bin/bash "$CONTAINER_SCRIPTS_DIR/install-chromium-deps.sh")

WORKING_CONTAINER_NAME=env-chromium-tmp-$$
BASE_IMAGE_NAME=$(base_image_name)
NEW_IMAGE_NAME=$(builder_image_name "$CHROMIUM_VERSION")

require_image "$BASE_IMAGE_NAME" "Run cr-setup-base-docker-image to create it"

DOCKER_ARGS=(--pull=never --name "$WORKING_CONTAINER_NAME")
DOCKER_ARGS+=(-v "$CHROMIUM_DIR:$CONTAINER_WORK_DIR")
DOCKER_ARGS+=(-v "$THIS_SCRIPT_DIR/container:$CONTAINER_SCRIPTS_DIR:ro")
DOCKER_ARGS+=(-e "ARG_GCLIENT_SYNC=$ARG_GCLIENT_SYNC")

if [[ -t 0 ]]; then
    DOCKER_ARGS+=(-it)
fi

trap 'docker rm -f "$WORKING_CONTAINER_NAME" > /dev/null' EXIT

docker run "${DOCKER_ARGS[@]}" "$BASE_IMAGE_NAME" "${DOCKER_CMD[@]}"

docker commit \
    --change 'CMD ["/bin/bash"]' \
    --change 'ENV ARG_GCLIENT_SYNC=' \
    "$WORKING_CONTAINER_NAME" "$NEW_IMAGE_NAME"
