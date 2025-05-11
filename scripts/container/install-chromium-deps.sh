#!/bin/bash

set -e

# environment variables

# WORK_DIR: The directory where the source code will be checked out.
WORK_DIR=/mnt/work

# ----------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

apt-get update -qqy
apt-get -qqy upgrade

# ----------------------------------------------------

cd $WORK_DIR

# To avoid the error `Cannot change ownership to uid 376730, gid 89939: Invalid argument`,
# we use TAR_OPTIONS=--no-same-owner
# NOTE: Removed due to `Permission denied: '/mnt/work/src/out/default/../../third_party/node/linux/node-linux-x64/bin/node'`
gclient runhooks -j 16 --force

# install build dependencies into docker image

# Use debconf-set-selections to accept the EULA for mscorefonts
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections \
    && ln -sf /usr/share/zoneinfo/GMT0 /etc/localtime \
    && sed -i '/\s*"snapcraft",/ s/^/#/' src/build/install-build-deps.py \
    && bash src/build/install-build-deps.sh --backwards-compatible --no-prompt \
        --syms --android --lib32 --arm --chromeos-fonts

# Replace depot_tools with the one from the chromium source
rm -rf /opt/depot_tools \
    && cp -ar /tmp/chromium/src/third_party/depot_tools /opt/depot_tools

# ----------------------------------------------------
# Clean up

bash /clean-after-apt.sh
