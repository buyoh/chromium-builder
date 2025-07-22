#!/bin/bash

set -e

# environment variables

# WORK_DIR: The directory where the source code will be checked out.
WORK_DIR=/mnt/work
# ARG_GCLIENT_SYNC: If set, run `gclient sync` instead of `gclient runhooks`.
ARG_GCLIENT_SYNC=${ARG_GCLIENT_SYNC:-false}

# ----------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

apt-get update -qqy
apt-get -qqy upgrade

# ----------------------------------------------------

cd $WORK_DIR

CHROMIUM_VERSION_MAJOR=

if [[ -f "$WORK_DIR/src/chrome/VERSION" ]]; then
    CHROMIUM_VERSION_MAJOR=$(source "$WORK_DIR/src/chrome/VERSION" && echo "$MAJOR")
    echo "version = $CHROMIUM_VERSION_MAJOR"
fi

COMMIT_HASH_DEPOT_TOOLS=

if [[ -f "$WORK_DIR/src/DEPS" ]]; then
    COMMIT_HASH_DEPOT_TOOLS=$(cat $WORK_DIR/src/DEPS | grep '/chromium/tools/depot_tools.git' | sed "s/.*@'//g" | tr -dc "a-f0-9")
fi

# ----------------------------------------------------

if [[ ! -x "$(command -v gclient)" ]]; then
    if [[ -n $COMMIT_HASH_DEPOT_TOOLS ]]; then
        # clone with specific commit hash
        git init /opt/depot_tools
        git -C /opt/depot_tools remote add origin https://chromium.googlesource.com/chromium/tools/depot_tools.git
        git -C /opt/depot_tools fetch --depth 1 origin $COMMIT_HASH_DEPOT_TOOLS &&
        git -C /opt/depot_tools checkout $COMMIT_HASH_DEPOT_TOOLS
    else
        git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /opt/depot_tools
    fi
    export PATH=/opt/depot_tools:$PATH
    export DEPOT_TOOLS_UPDATE=0
fi

# To avoid the error `Cannot change ownership to uid 376730, gid 89939: Invalid argument`,
# we use TAR_OPTIONS=--no-same-owner
# NOTE: Removed due to `Permission denied: '/mnt/work/src/out/default/../../third_party/node/linux/node-linux-x64/bin/node'`

SUBCMD_GCLIENT="runhooks -j 16 --force"
if [[ "$ARG_GCLIENT_SYNC" == true ]]; then
    SUBCMD_GCLIENT="sync -D -j 16 --force"
fi

if [[ "$CHROMIUM_VERSION_MAJOR" == 114 ]]; then
    # TODO: Only for m114?
    TAR_OPTIONS=--no-same-owner gclient $SUBCMD_GCLIENT -j 16 --force
else
    gclient $SUBCMD_GCLIENT -j 16 --force
fi

# install build dependencies into docker image

# Use debconf-set-selections to accept the EULA for mscorefonts
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections \
    && ln -sf /usr/share/zoneinfo/GMT0 /etc/localtime \
    && (sed -i '/snapcraft,/ s/^/#/' src/build/install-build-deps.py ;
        sed -i '/snapcraft,/ s/^/#/' src/build/install-build-deps.sh ;
        true) \
    && bash src/build/install-build-deps.sh --backwards-compatible --no-prompt \
        --syms --android --lib32 --arm --chromeos-fonts

# Replace depot_tools with the one from the chromium source
rm -rf /opt/depot_tools \
    && cp -ar $WORK_DIR/src/third_party/depot_tools /opt/depot_tools

# ----------------------------------------------------
# Clean up

bash /clean-after-apt.sh
