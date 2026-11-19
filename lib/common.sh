# Definitions shared by the host scripts.

DIST_CODENAME=focal
IMAGE_TAG=v1
BUILDER_IMAGE_REPOSITORY=env-chromium-build

CONTAINER_WORK_DIR=/mnt/work
CONTAINER_SCRIPTS_DIR=/mnt/scripts

base_image_name() {
    echo "env-chromium/$DIST_CODENAME:$IMAGE_TAG"
}

# builder_image_name <chromium version>
builder_image_name() {
    echo "$BUILDER_IMAGE_REPOSITORY/$DIST_CODENAME-$1:$IMAGE_TAG"
}

# latest_builder_image <codename-version prefix> <hint>
# Print the builder image of the newest version. The prefix matches whole
# version components: focal-132 matches focal-132.0.1.2, but not focal-1320.0.1.2.
latest_builder_image() {
    local repository="$BUILDER_IMAGE_REPOSITORY/$1"

    local images
    images=$(docker image ls --format '{{.Repository}}' \
        --filter "reference=$BUILDER_IMAGE_REPOSITORY/*:$IMAGE_TAG") || return 1

    local image matches=()
    while read -r image; do
        if [[ "$image" == "$repository" || "$image" == "$repository".* ]]; then
            matches+=("$image")
        fi
    done <<< "$images"

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "Error: No builder image matches '$1'" >&2
        echo "Error: $2" >&2
        return 1
    fi
    echo "$(printf '%s\n' "${matches[@]}" | sort -V | tail -n 1):$IMAGE_TAG"
}

# read_chromium_version <chromium directory>
# Print the version. The file is not sourced, because it comes from the checkout.
read_chromium_version() {
    local version_file="$1/src/chrome/VERSION"
    if [[ ! -f "$version_file" ]]; then
        echo "Error: $1 is not a chromium source directory" >&2
        echo "Error: $version_file not found" >&2
        return 1
    fi

    local key parts=()
    for key in MAJOR MINOR BUILD PATCH; do
        parts+=("$(sed -n "s/^$key=//p" "$version_file")")
    done

    local version="${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid chromium version: '$version'" >&2
        return 1
    fi
    echo "$version"
}

# require_image <image name> <hint>
require_image() {
    if ! docker image inspect "$1" > /dev/null 2>&1; then
        echo "Error: Docker image $1 not found"
        echo "Error: $2"
        exit 1
    fi
}
