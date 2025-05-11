#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")

ARG_CHROMIUM_TAG=
ARG_CR=
ARG_WORK_DIR=
ARG_REFERENCE_DIR=

CHECKOUT_CHROMIUM_TAG=
CHECKOUT_LATEST=false
ARG_DIST_CODENAME=focal

WORK_DIR=
REFERENCE_DIR=

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
    ##  --reference <path> : Mount the directory and use git clone --reference
    ##                     : "src" directory must be set different from --dest
    ##                     : The dependencies will not be referenced
    --reference)
    ARG_REFERENCE_DIR="$2"
    echo "--reference is not tested yet" ; exit 1
    shift
    ;;
    ##  --dest <path>      : Mount the directory and pull the source code to the directory
    --dest)
    ARG_WORK_DIR="$2"
    shift
    ;;
    ##  --help, -h         : Show help
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

if [[ -z "$ARG_CHROMIUM_TAG" ]] && [[ -z "$ARG_CR" ]]; then
    echo "Error: --chromium or --cr or --latest is required"
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
        ARG_CHROMIUM_TAG=$(./lib/suggest_cr_tag.sh $ARG_CR)
        if [[ -z "$ARG_CHROMIUM_TAG" ]]; then
            echo "Error: Chromium tag not found: '$ARG_CR'"
            exit 1
        fi
    fi
fi

if ! "$CHECKOUT_LATEST" && [[ ! "$ARG_CHROMIUM_TAG" =~ ^[-0-9A-Za-z.-_]+$ ]]; then
    echo "Error: Invalid chromium tag: '$ARG_CHROMIUM_TAG'"
    exit 1
fi

# -----------------------------------------------------------------------------
# Check WORK_DIR

WORK_DIR_ABSOLUTE=$(realpath "$ARG_WORK_DIR")
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
# Check REFERENCE_DIR

if [[ -n "$ARG_REFERENCE_DIR" ]]; then
    REFERENCE_DIR_ABSOLUTE=$(realpath "$ARG_REFERENCE_DIR")
    if [[ ! -d "$REFERENCE_DIR_ABSOLUTE" ]]; then
        echo "Error: $ARG_REFERENCE_DIR is not a directory"
        exit 1
    fi
    REFERENCE_DIR="$REFERENCE_DIR_ABSOLUTE"
else
    REFERENCE_DIR=
fi

# -----------------------------------------------------------------------------

DOCKER_CMD="/bin/bash /mnt/scripts/fetch-src.sh"

DOCKER_ARG_MOUNTS=""
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $WORK_DIR:/mnt/work"
DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $THIS_SCRIPT_DIR/container:/mnt/scripts:ro"

DOCKER_ARG_ENV=""

if [[ -n "$REFERENCE_DIR" ]]; then
    DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $REFERENCE_DIR:/mnt/reference"
    DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e USE_REFERENCE=true"
fi

if "$CHECKOUT_LATEST"; then
    DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e CHECKOUT_LATEST=true"
else
    DOCKER_ARG_ENV="$DOCKER_ARG_ENV -e CHECKOUT_CHROMIUM_TAG=$ARG_CHROMIUM_TAG"
fi

docker run --init -it --rm \
    -w /mnt/work \
    $DOCKER_ARG_MOUNTS \
    $DOCKER_ARG_ENV \
    env-chromium/$ARG_DIST_CODENAME:v1 \
    $DOCKER_CMD

