ARG DIST_CODENAME=focal
FROM ubuntu:$DIST_CODENAME

ARG DIST_CODENAME=focal
ARG UBUNTU_APT_URL=http://archive.ubuntu.com/ubuntu/

ARG CHROMIUM_TAG="120.0.6099.234"

COPY ./configure-apt.sh /configure-apt.sh
COPY ./clean-after-apt.sh /clean-after-apt.sh

ENV DEBIAN_FRONTEND=noninteractive

RUN UBUNTU_APT_URL=$UBUNTU_APT_URL DIST_CODENAME=$DIST_CODENAME . /configure-apt.sh \
    && apt-get update -qqy \
    && apt-get -qqy upgrade \
    && apt-get install -qqy --no-install-recommends \
        git ca-certificates wget curl lsb-release sudo file \
        python xz-utils \
        nano \
    && bash /clean-after-apt.sh

# We never push commits
RUN git config --global user.email "user@example.com" \
    && git config --global user.name "user.name"

# -----------------------------------------------------------------------------
# Install depot_tools

# requires: python3, xz-utils 

RUN mkdir -p /opt/depot_tools \
    && git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /opt/depot_tools

ENV PATH="/opt/depot_tools:$PATH" \
    DEPOT_TOOLS_UPDATE=0

# -----------------------------------------------------------------------------
# glient sync

RUN mkdir -p /tmp/chromium
WORKDIR /tmp/chromium

RUN gclient config --spec="solutions = [ \
    { \"url\": \"https://chromium.googlesource.com/chromium/src@$CHROMIUM_TAG\", \
        \"managed\": False, \
        \"name\": \"src\", \
        \"deps_file\": \"DEPS\", \
        \"custom_deps\": {}, \
        }, \
    ]" \
    && echo '' >> .gclient \
    && echo 'target_os = ["linux", "android"]' >> .gclient \
    && gclient sync -j 16 --shallow --with_branch_heads --force

RUN bash src/build/install-build-deps.sh --no-prompt --backwards-compatible \
        --syms --android --lib32 --arm --chromeos-fonts

# Replace depot_tools with the one from the chromium source
RUN rm -rf /opt/depot_tools \
    && cp -ar /tmp/chromium/src/third_party/depot_tools /opt/depot_tools

# -----------------------------------------------------------------------------
# Clean up

RUN rmdir /tmp/chromium
