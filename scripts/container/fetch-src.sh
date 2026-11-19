#!/bin/bash

# environment variables
# CHECKOUT_CHROMIUM_TAG: The tag of the Chromium source code to checkout.
# CHECKOUT_LATEST: If set, checkout the HEAD version of Chromium.
# FULL_HISTORY: If set, fetch the full history.

set -euo pipefail

source "$(dirname "$0")/common.sh"

CHECKOUT_CHROMIUM_TAG=${CHECKOUT_CHROMIUM_TAG:-}
CHECKOUT_LATEST=${CHECKOUT_LATEST:-}
FULL_HISTORY=${FULL_HISTORY:-}

# WORK_DIR: The directory where the source code will be checked out.
WORK_DIR=/mnt/work

if [[ -z "$CHECKOUT_CHROMIUM_TAG" ]] && [[ -z "$CHECKOUT_LATEST" ]]; then
  echo "Please set CHECKOUT_CHROMIUM_TAG or CHECKOUT_LATEST"
  exit 1
fi

if [[ -n "$CHECKOUT_CHROMIUM_TAG" ]] && [[ -n "$CHECKOUT_LATEST" ]]; then
  echo "Please set only one of CHECKOUT_CHROMIUM_TAG or CHECKOUT_LATEST"
  exit 1
fi

# -----------------------------------------------------------------------------

cd "$WORK_DIR"

if [[ -d src/.git ]]; then
  # Resume from a previous run.
  if [[ -n "$FULL_HISTORY" ]] && [[ -f src/.git/shallow ]]; then
    echo "Error: src is a shallow clone. Remove src to fetch the full history"
    exit 1
  fi
  if [[ -n "$CHECKOUT_CHROMIUM_TAG" ]]; then
    if ! SRC_COMMIT=$(git -C src rev-parse --verify HEAD) \
        || ! TAG_COMMIT=$(git -C src rev-parse --verify "refs/tags/$CHECKOUT_CHROMIUM_TAG^{commit}") \
        || [[ "$SRC_COMMIT" != "$TAG_COMMIT" ]]; then
      echo "Error: src is not at the tag $CHECKOUT_CHROMIUM_TAG"
      exit 1
    fi
  fi
else
  GIT_CLONE_ARGS=()
  if [[ -z "$FULL_HISTORY" ]]; then
    # build/util/lastchange.py needs a commit with Change-Id. Some tags are on
    # a commit without it, so keep the parent commit as well.
    GIT_CLONE_ARGS+=(--depth 2 --single-branch)
  fi
  if [[ -n "$CHECKOUT_CHROMIUM_TAG" ]]; then
    GIT_CLONE_ARGS+=(--branch "$CHECKOUT_CHROMIUM_TAG")
  fi
  git clone https://chromium.googlesource.com/chromium/src.git "${GIT_CLONE_ARGS[@]}"
fi

# Read src/DEPS file and get depot_tools hash
if [[ ! -f "src/DEPS" ]]; then
  echo "Error: DEPS file not found"
  exit 1
fi
DEPS_HASH=$(depot_tools_revision src/DEPS)

# -----------------------------------------------------------------------------
# Clone depot_tools

git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /tmp/depot_tools 
git -C /tmp/depot_tools checkout "$DEPS_HASH"

export PATH=/tmp/depot_tools:$PATH
export DEPOT_TOOLS_UPDATE=0

# -----------------------------------------------------------------------------
# Sync the source code

cd "$WORK_DIR"

SOLUTION_URL=https://chromium.googlesource.com/chromium/src
if [[ -n "$CHECKOUT_CHROMIUM_TAG" ]]; then
  SOLUTION_URL=https://chromium.googlesource.com/chromium/src.git@$CHECKOUT_CHROMIUM_TAG
fi

rm -f .gclient
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

GCLIENT_SYNC_ARGS=(--nohooks -j 16)
if [[ -z "$FULL_HISTORY" ]]; then
  GCLIENT_SYNC_ARGS+=(--no-history)
fi
gclient sync "${GCLIENT_SYNC_ARGS[@]}"

# -----------------------------------------------------------------------------

echo "Checkout done"
