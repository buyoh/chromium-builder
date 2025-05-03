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

CMD=/bin/bash
if [[ -n "$ARG_CMD" ]]; then
    CMD="$ARG_CMD"
fi

DOCKER_ARG_MOUNTS=""

DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $PWD:/mnt/work"

docker run --init -it --rm \
  -w /mnt/work \
  $DOCKER_ARG_MOUNTS \
  env-chromium/$ARG_DIST_CODENAME:m120 \
  $CMD

