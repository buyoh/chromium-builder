ARG DIST_CODENAME=focal
FROM ubuntu:$DIST_CODENAME

ARG DIST_CODENAME=focal
ARG UBUNTU_APT_URL=http://archive.ubuntu.com/ubuntu/

COPY ./configure-apt.sh /configure-apt.sh
COPY ./clean-after-apt.sh /clean-after-apt.sh

ENV DEBIAN_FRONTEND=noninteractive

RUN UBUNTU_APT_URL=$UBUNTU_APT_URL DIST_CODENAME=$DIST_CODENAME . /configure-apt.sh \
    && apt-get update -qqy \
    && apt-get -qqy upgrade \
    && apt-get install -qqy --no-install-recommends \
        git ca-certificates wget curl lsb-release sudo file \
        python xz-utils \
        nano
# TODO: don't clean apt cache here. install-build-deps.sh will use apt-get.

# We never push commits
RUN git config --global user.email "user@example.com" \
    && git config --global user.name "user.name"

COPY fetch-src.sh /fetch-src.sh

ENV DEPOT_TOOLS_UPDATE=0

# -----------------------------------------------------------------------------
# Clean up

WORKDIR /
RUN rm -rf /tmp/chromium \
    && bash /clean-after-apt.sh

ENV EDITOR=nano
