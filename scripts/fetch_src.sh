#!/bin/bash

set -eu
THIS_SCRIPT=$(realpath $0)
THIS_SCRIPT_DIR=$(dirname "$THIS_SCRIPT")
BASE_DIR=$(dirname "$THIS_SCRIPT_DIR")

DEPOT_TOOLS_DIR="$BASE_DIR/var/depot_tools"

ARG_DEPOT_TOOLS_DIR=

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --depot-tools-dir     : Path to depot_tools
    ##                        : 
    --depot-tools-dir)
    ARG_DEPOT_TOOLS_DIR="$2"
    ARG_DEPOT_TOOLS_DIR=$(realpath "$ARG_DEPOT_TOOLS_DIR")
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

# -----------------------------------------------------------------------------

if [[ -n "$ARG_DEPOT_TOOLS_DIR" ]]; then
    DEPOT_TOOLS_DIR="$ARG_DEPOT_TOOLS_DIR"
fi

if [[ ! -d "$DEPOT_TOOLS_DIR" ]]; then
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
fi

if [[ ! -e "$DEPOT_TOOLS_DIR/gclient" ]]; then
    echo "Error: depot_tools not found"
    exit 1
fi

export PATH=$DEPOT_TOOLS_DIR:$PATH

# -----------------------------------------------------------------------------

set -x

CHROMIUM_TAG="120.0.6099.234"

# .gclient の作成
gclient config --spec="solutions = [
  { \"url\": \"https://chromium.googlesource.com/chromium/src@$CHROMIUM_TAG\",
    \"managed\": False,
    \"name\": \"src\",
    \"deps_file\": \"DEPS\",
    \"custom_deps\": {},
  },
]"
echo '' >> .gclient
echo 'target_os = ["linux", "android"]' >> .gclient

gclient sync
