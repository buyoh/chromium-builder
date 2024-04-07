
set -eu

ARG_USER=$1
ARG_UID=$2
ARG_GID=$3
WORK_DIR=$4

echo user=$ARG_USER
echo uid=$ARG_UID
echo gid=$ARG_GID

groupadd -g $ARG_GID $ARG_USER \
  && useradd -m -s /bin/bash -g $ARG_USER -u $ARG_UID $ARG_USER \
  && chown $ARG_USER:$ARG_USER /home/$ARG_USER

# depot_tools
export DEPOT_TOOLS_UPDATE=0
export PATH=$WORK_DIR/src/third_party/depot_tools:$PATH  

# 動くけどやりかたに違和感
export HOME=/home/$ARG_USER
cd $WORK_DIR
chroot --userspec=$ARG_UID:$ARG_GID --skip-chdir / \
  bash --login -i
