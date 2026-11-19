#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f "$0")
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")
source "$BASE_DIR/lib/common.sh"

ARG_NO_CACHE=false
ARG_UBUNTU_APT_URL=http://archive.ubuntu.com/ubuntu/

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --no-cache      : Do not use cache when building the image
    --no-cache)
    ARG_NO_CACHE=true
    ;;
    ##  --apt           : Set apt repository url
    --apt)
    ARG_UBUNTU_APT_URL=$2
    shift
    ;;
    ##  --apt-country   : Set apt repository url
    --apt-country)
    ARG_UBUNTU_APT_URL=http://$2.archive.ubuntu.com/ubuntu/
    shift
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

cd "$BASE_DIR"

DOCKER_ARGS=(-t "$(base_image_name)")
DOCKER_ARGS+=(--build-arg "DIST_CODENAME=$DIST_CODENAME")
DOCKER_ARGS+=(--build-arg "UBUNTU_APT_URL=$ARG_UBUNTU_APT_URL")

if "$ARG_NO_CACHE"; then
    DOCKER_ARGS+=(--no-cache)
fi

docker build "${DOCKER_ARGS[@]}" ./docker/base

