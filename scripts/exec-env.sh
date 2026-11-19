#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f "$0")
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")
source "$BASE_DIR/lib/common.sh"

ARG_IMAGE_NAME=
ARG_IMAGE_PREFIX=
ARG_GPU_ALL=false
ARG_XEPHYR=
ARG_CMD=()
ARG_USERNAME=

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --image         : Set image name with tag (e.g. env-chromium/focal:v1)
    --image)
    ARG_IMAGE_NAME=$2
    shift
    ;;
    ##  --img <prefix>  : Use the latest builder image of the version prefix
    ##                  : (e.g. focal-132)
    --img)
    ARG_IMAGE_PREFIX=$2
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
    ##                  : in the container, with the UID and GID of the host user.
    ##                  : Only for rootful Docker. Rootless Docker rejects this
    ##                  : option because root in the container is the host user.
    --username)
    ARG_USERNAME=$2
    shift
    ;;
    ##  --help, -h      : Show help
    --help|-h)
    echo "Usage: $0 [OPTION...]"
    echo ""
    grep "^ *##" "$THIS_SCRIPT" | sed -e "s/^ *##//"
    exit 0
    ;;
    --)
    shift
    ARG_CMD=("$@")
    break
    ;;
    *)
    echo "Unknow option $arg"
    exit 2
    ;;
esac
shift
done

# -----------------------------------------------------------------------------

if [[ -n "$ARG_IMAGE_NAME" && -n "$ARG_IMAGE_PREFIX" ]]; then
    echo "Error: --image and --img cannot be used together"
    exit 1
fi

CHROMIUM_DIR=.
CRENV_USER=
CRENV_UID=
CRENV_GID=

CHROMIUM_VERSION=$(read_chromium_version "$CHROMIUM_DIR")

if [[ -n "$ARG_USERNAME" ]]; then
    # validate username
    if [[ ! "$ARG_USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Error: Invalid username: '$ARG_USERNAME'"
        exit 1
    fi
    if [[ "$ARG_USERNAME" != "root" ]]; then
        CRENV_USER=$ARG_USERNAME
    fi
fi

# `docker info` succeeds even if the daemon is unreachable.
if ! docker version --format '{{.Server.Version}}' > /dev/null; then
    echo "Error: Failed to query docker daemon"
    exit 1
fi

DOCKER_SECURITY_OPTIONS=$(docker info --format '{{.SecurityOptions}}')

if [[ "$DOCKER_SECURITY_OPTIONS" == *name=rootless* ]]; then
    if [[ -n "$CRENV_USER" ]]; then
        echo "Error: --username is not available on rootless Docker"
        echo "Error: root in the container is already the host user"
        exit 1
    fi
elif [[ "$(id -u)" == 0 ]]; then
    if [[ -n "$CRENV_USER" ]]; then
        echo "Error: --username maps to the host user, but the host user is root"
        exit 1
    fi
elif [[ -n "$CRENV_USER" ]]; then
    CRENV_UID=$(id -u)
    CRENV_GID=$(id -g)
    if [[ ! -w "$CHROMIUM_DIR/src" ]]; then
        echo "Warning: $CHROMIUM_DIR/src is not writable by the host user. See README.md."
    fi
else
    echo "Warning: Docker is not rootless. Files created in the container will be owned by root on the host."
    echo "Warning: Use --username to run as the host user. See README.md."
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

IMAGE_HINT="Run cr-setup-builder-docker-image to create it"

if [[ -n "$ARG_IMAGE_NAME" ]]; then
    IMAGE_NAME=$ARG_IMAGE_NAME
elif [[ -n "$ARG_IMAGE_PREFIX" ]]; then
    IMAGE_NAME=$(latest_builder_image "$ARG_IMAGE_PREFIX" "$IMAGE_HINT")
else
    IMAGE_NAME=$(builder_image_name "$CHROMIUM_VERSION")
fi

require_image "$IMAGE_NAME" "$IMAGE_HINT"

# -----------------------------------------------------------------------------

PRE_CMD=(/bin/bash "$CONTAINER_SCRIPTS_DIR/cmd-prepare.sh")

CMD=(/bin/bash)
if [[ ${#ARG_CMD[@]} -gt 0 ]]; then
    CMD=("${ARG_CMD[@]}")
fi

DOCKER_ARGS=(--pull=never --init -it --rm -w "$CONTAINER_WORK_DIR")
DOCKER_ARGS+=(-v "$PWD:$CONTAINER_WORK_DIR")
DOCKER_ARGS+=(-v "$THIS_SCRIPT_DIR/container:$CONTAINER_SCRIPTS_DIR:ro")

if [[ -n "$CRENV_USER" ]]; then
    DOCKER_ARGS+=(-e "CRENV_USER=$CRENV_USER")
    DOCKER_ARGS+=(-e "CRENV_UID=$CRENV_UID")
    DOCKER_ARGS+=(-e "CRENV_GID=$CRENV_GID")
fi

if [[ -n "$XEPHYR_DISPLAY" ]]; then
    Xephyr -br -ac -noreset -screen "$XEPHYR_DISPLAY_SIZE" -resizeable "$XEPHYR_DISPLAY" &
    sleep 0.5
    # xhost +SI:localuser:root
    DOCKER_ARGS+=(-e "DISPLAY=$XEPHYR_DISPLAY")
elif [[ -n "${DISPLAY:-}" ]]; then
    DOCKER_ARGS+=(-e "DISPLAY=$DISPLAY")
fi
DOCKER_ARGS+=(-v /tmp/.X11-unix:/tmp/.X11-unix:ro)

# Add GPU device access for GLES support
if [[ -d /dev/dri ]]; then
    DOCKER_ARGS+=(--device /dev/dri:/dev/dri)
fi

if [[ "$ARG_GPU_ALL" == true ]]; then
    DOCKER_ARGS+=(--gpus all)
fi

exec docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "${PRE_CMD[@]}" "${CMD[@]}"

