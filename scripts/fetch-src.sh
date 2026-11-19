#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f "$0")
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")
source "$BASE_DIR/lib/common.sh"

ARG_CHROMIUM_TAG=
ARG_CR=
ARG_WORK_DIR=
ARG_FULL_HISTORY=false

CHECKOUT_LATEST=false

WORK_DIR=

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --chromium <tag>   : Set chromium full tag (e.g. 120.0.6099.234)
    --chromium)
    ARG_CHROMIUM_TAG="$2"
    shift
    ;;
    ##  --cr <v>           : Set chromium tag (e.g. 120) instead of full tag
    ##                     : Special TAG "HEAD" is also available
    ##                     : HEAD will be used for checkout HEAD
    --cr)
    ARG_CR="$2"
    shift
    ;;
    ##  --dest <path>      : Mount the directory and pull the source code to the directory
    --dest)
    ARG_WORK_DIR="$2"
    shift
    ;;
    ##  --full-history     : Fetch the full history. Default is the latest commits only.
    --full-history)
    ARG_FULL_HISTORY=true
    ;;
    ##  --help, -h         : Show help
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

if [[ -z "$ARG_CHROMIUM_TAG" ]] && [[ -z "$ARG_CR" ]]; then
    echo "Error: --chromium or --cr is required"
    exit 1
fi

if [[ -n "$ARG_CR" ]] && [[ -n "$ARG_CHROMIUM_TAG" ]]; then
    echo "Error: --cr and --chromium are exclusive"
    exit 1
fi

if [[ -z "$ARG_WORK_DIR" ]]; then
    echo "Error: Destination directory is not set"
    exit 1
fi

# -----------------------------------------------------------------------------

if [[ -n "$ARG_CR" ]]; then
    if [[ "$ARG_CR" == "HEAD" ]]; then
        CHECKOUT_LATEST=true
    else
        ARG_CHROMIUM_TAG=$("$BASE_DIR/lib/suggest_cr_tag.sh" "$ARG_CR")
        if [[ -z "$ARG_CHROMIUM_TAG" ]]; then
            echo "Error: Chromium tag not found: '$ARG_CR'"
            exit 1
        fi
    fi
fi

if ! "$CHECKOUT_LATEST" && [[ ! "$ARG_CHROMIUM_TAG" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    echo "Error: Invalid chromium tag: '$ARG_CHROMIUM_TAG'"
    exit 1
fi

IMAGE_NAME=$(base_image_name)

require_image "$IMAGE_NAME" "Run cr-setup-base-docker-image to create it"

# -----------------------------------------------------------------------------
# Check WORK_DIR

WORK_DIR_ABSOLUTE=$(realpath -m "$ARG_WORK_DIR")
if [[ -e "$WORK_DIR_ABSOLUTE" ]] && [[ ! -d "$WORK_DIR_ABSOLUTE" ]]; then
    echo "Error: $ARG_WORK_DIR is not a directory"
    exit 1
fi
WORK_DIR=$WORK_DIR_ABSOLUTE

if [[ ! -d "$WORK_DIR" ]]; then
    mkdir -p "$WORK_DIR"
    if [[ ! -d "$WORK_DIR" ]]; then
        echo "Error: Failed to create directory $WORK_DIR"
        exit 1
    fi
fi

# -----------------------------------------------------------------------------

DOCKER_CMD=(/bin/bash "$CONTAINER_SCRIPTS_DIR/fetch-src.sh")

DOCKER_ARGS=(--pull=never --init --rm -w "$CONTAINER_WORK_DIR")
DOCKER_ARGS+=(-v "$WORK_DIR:$CONTAINER_WORK_DIR")
DOCKER_ARGS+=(-v "$THIS_SCRIPT_DIR/container:$CONTAINER_SCRIPTS_DIR:ro")

if [[ -t 0 ]]; then
    DOCKER_ARGS+=(-it)
fi

if "$CHECKOUT_LATEST"; then
    DOCKER_ARGS+=(-e CHECKOUT_LATEST=true)
else
    DOCKER_ARGS+=(-e "CHECKOUT_CHROMIUM_TAG=$ARG_CHROMIUM_TAG")
fi

if "$ARG_FULL_HISTORY"; then
    DOCKER_ARGS+=(-e FULL_HISTORY=true)
fi

docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "${DOCKER_CMD[@]}"
