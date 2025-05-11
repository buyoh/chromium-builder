#!/bin/bash

# environment variables
# CHECKOUT_CHROMIUM_TAG: The tag of the Chromium source code to checkout.
# CHECKOUT_LATEST: If set, checkout the HEAD version of Chromium.
# USE_REFERENCE: If set, use git clone --reference

# WORK_DIR: The directory where the source code will be checked out.
WORK_DIR=/mnt/work
REFERENCE_DIR=/mnt/reference

set -e

if [[ -z $CHECKOUT_CHROMIUM_TAG ]] && [[ -z $CHECKOUT_LATEST ]]; then
  echo "Please set CHECKOUT_CHROMIUM_TAG or CHECKOUT_LATEST"
  exit 1
fi

if [[ -n $CHECKOUT_CHROMIUM_TAG ]] && [[ -n $CHECKOUT_LATEST ]]; then
  echo "Please set only one of CHECKOUT_CHROMIUM_TAG or CHECKOUT_LATEST"
  exit 1
fi

# -----------------------------------------------------------------------------

cd $WORK_DIR

GIT_CLONE_TAGET="https://chromium.googlesource.com/chromium/src.git"
if [[ -n $USE_REFERENCE ]]; then
  GIT_CLONE_TAGET="--reference $REFERENCE_DIR"
fi

GIT_CLONE_ARGS="--depth 1 --single-branch"
if [[ -n $CHECKOUT_LATEST ]]; then
  GIT_CLONE_ARGS=""
else
  GIT_CLONE_ARGS="--branch $CHECKOUT_CHROMIUM_TAG"
fi

git clone $GIT_CLONE_TAGET $GIT_CLONE_ARGS

# Read src/DEPS file and get depot_tools hash
if [[ ! -f "src/DEPS" ]]; then
  echo "Error: DEPS file not found"
  exit 1
fi
DEPS_HASH=$(grep "depot_tools.git" "src/DEPS" | grep -oE "[0-9a-f]{40}" | head -n 1)

# -----------------------------------------------------------------------------
# Clone depot_tools

git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /tmp/depot_tools 
git -C /tmp/depot_tools checkout $DEPS_HASH

export PATH=/tmp/depot_tools:$PATH
export DEPOT_TOOLS_UPDATE=0

# -----------------------------------------------------------------------------
# Sync the source code

cd $WORK_DIR

SOLUTION_URL=https://chromium.googlesource.com/chromium/src
if [[ -n $CHECKOUT_CHROMIUM_TAG ]]; then
  SOLUTION_URL=https://chromium.googlesource.com/chromium/src.git@$CHECKOUT_CHROMIUM_TAG
fi

gclient config --spec="solutions = [
  { \"url\": \"$SOLUTION_URL\",
    \"managed\": False,
    \"name\": \"src\",
    \"deps_file\": \"DEPS\",
    \"custom_deps\": {},
  },
]"
echo '' >> .gclient
echo 'target_os = ["linux", "android"]' >> .gclient

gclient sync --nohooks -j 16
# --with_tags?

# -----------------------------------------------------------------------------

echo "Checkout done"
