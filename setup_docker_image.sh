#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)

ARG_DIST_CODENAME=focal
ARG_CR=
ARG_CHROMIUM_TAG=
ARG_NAME=
ARG_NO_CACHE=
ARG_UBUNTU_APT_URL=http://archive.ubuntu.com/ubuntu/

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --chromium      : Set chromium full tag (e.g. 120.0.6099.234)
    --chromium)
    ARG_CHROMIUM_TAG=$2
    shift
    ;;
    ##  --cr            : Set chromium tag (e.g. 120) instead of full tag
    --cr)
    ARG_CR=$2
    shift
    ;;
    ##  --name          : Set image version name. (e.g. m120)
    ##                  : Image name will be env-chromium/$ARG_DIST_CODENAME:$ARG_NAME
    ##                  : Default is chromium tag.
    --name)
    ARG_NAME=$2
    shift
    ;;
    ##  --no-cache      : Do not use cache when building the image
    --no-cache)
    ARG_NO_CACHE=--no-cache
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

if [[ -z "$ARG_CHROMIUM_TAG" ]] && [[ -z "$ARG_CR" ]]; then
    echo "Error: --chromium or --cr is required"
    exit 1
fi

if [[ -n "$ARG_CR" ]] && [[ -n "$ARG_CHROMIUM_TAG" ]]; then
    echo "Error: --cr and --chromium are exclusive"
    exit 1
fi

cd $(dirname $0)

if [[ -n "$ARG_CR" ]]; then
    ARG_CHROMIUM_TAG=$(./lib/suggest_cr_tag.sh $ARG_CR)
    if [[ -z "$ARG_CHROMIUM_TAG" ]]; then
        echo "Error: Chromium tag not found: '$ARG_CR'"
        exit 1
    fi
fi

if [[ ! "$ARG_CHROMIUM_TAG" =~ ^[-0-9A-Za-z.-_]+$ ]]; then
    echo "Error: Invalid chromium tag: '$ARG_CHROMIUM_TAG'"
    exit 1
fi

if [[ -z "$ARG_NAME" ]]; then
    ARG_NAME=$ARG_CHROMIUM_TAG
fi

docker build -t env-chromium/$ARG_DIST_CODENAME:$ARG_NAME \
  --build-arg DIST_CODENAME=$ARG_DIST_CODENAME \
  --build-arg UBUNTU_APT_URL=$ARG_UBUNTU_APT_URL \
  --build-arg CHROMIUM_TAG=$ARG_CHROMIUM_TAG \
  ./docker/base $ARG_NO_CACHE

