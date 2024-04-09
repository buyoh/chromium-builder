#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)

# CHROMIUM_TAG="120.0.6099.234"
ARG_DIST_CODENAME=focal


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
    *)
    echo "Unknow option "$arg
    exit 2
    ;;
esac
shift
done

# -----------------------------------------------------------------------------

CMD=/bin/bash

DOCKER_ARG_MOUNTS=""

DOCKER_ARG_MOUNTS="$DOCKER_ARG_MOUNTS -v $PWD:/mnt/work"

docker run --init -it --rm \
  -w /mnt/work \
  $DOCKER_ARG_MOUNTS \
  env-chromium/$ARG_DIST_CODENAME:m120 \
  $CMD

