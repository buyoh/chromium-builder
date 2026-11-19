#!/bin/bash
# Tests that paths with a space reach docker as a single argument.
# Docker is replaced by a stub in $PATH.
#
# Usage: bash tests/test-path-with-space.sh

set -u
THIS_SCRIPT=$(readlink -f "$0")
BASE_DIR=$(dirname "$(dirname "$THIS_SCRIPT")")

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_DIR=$TMP_DIR/stub
LOG=$TMP_DIR/log
REPO_DIR="$TMP_DIR/repo dir"
WORK_DIR="$TMP_DIR/work dir"
mkdir -p "$STUB_DIR" "$REPO_DIR" "$WORK_DIR/src/chrome"
cp -r "$BASE_DIR/bin" "$BASE_DIR/lib" "$BASE_DIR/scripts" "$BASE_DIR/docker" "$REPO_DIR"
printf 'MAJOR=1\nMINOR=2\nBUILD=3\nPATCH=4\n' > "$WORK_DIR/src/chrome/VERSION"

FAILED=0

cat > "$STUB_DIR/docker" <<STUB
#!/bin/bash
subcommand=\$1
for arg in "\$@"; do
    printf '%s: %s\n' "\$subcommand" "\$arg"
done >> "$LOG"
case "\$1" in
    info) echo "[name=rootless]" ;;
    images) echo 0123456789ab ;;
esac
STUB
chmod +x "$STUB_DIR/docker"

run() {
    # run <description> <expected docker argument...> -- <bin command...>
    local description=$1
    shift
    local expected=()
    while [[ "$1" != "--" ]]; do
        expected+=("$1")
        shift
    done
    shift

    : > "$LOG"
    local output
    output=$(cd "$WORK_DIR" && PATH="$STUB_DIR:$PATH" DISPLAY=:0 /bin/bash "$@" 2>&1)
    local status=$?

    local ok=true
    [[ "$status" == 0 ]] || ok=false
    local arg
    for arg in "${expected[@]}"; do
        grep -qxF -- "$arg" "$LOG" || ok=false
    done

    if "$ok"; then
        echo "ok: $description"
    else
        echo "FAILED: $description (status=$status)"
        printf '%s\n' "$output" | sed -e 's/^/  out: /'
        sed -e 's/^/  log: /' "$LOG"
        FAILED=1
    fi
}

SCRIPTS_MOUNT="$REPO_DIR/scripts/container:/mnt/scripts:ro"

run "cr-exec-env" "run: $WORK_DIR:/mnt/work" "run: $SCRIPTS_MOUNT" \
    -- "$REPO_DIR/bin/cr-exec-env"
run "cr-exec-env --image" "images: name with space:v1" "run: name with space:v1" \
    -- "$REPO_DIR/bin/cr-exec-env" --image "name with space"
run "cr-fetch-src" "run: $WORK_DIR/dest:/mnt/work" "run: $SCRIPTS_MOUNT" \
    -- "$REPO_DIR/bin/cr-fetch-src" --cr HEAD --dest "$WORK_DIR/dest"
run "cr-setup-builder-docker-image" "run: $WORK_DIR:/mnt/work" "run: $SCRIPTS_MOUNT" "run: ARG_GCLIENT_SYNC=false" \
    -- "$REPO_DIR/bin/cr-setup-builder-docker-image" --cr-dir "$WORK_DIR"
run "cr-setup-base-docker-image" "build: UBUNTU_APT_URL=http://archive.ubuntu.com/ubuntu/" \
    -- "$REPO_DIR/bin/cr-setup-base-docker-image"

for entry in cr-exec-env:--gpu-all cr-fetch-src:--dest \
    cr-setup-base-docker-image:--no-cache cr-setup-builder-docker-image:--cr-dir; do
    command=${entry%%:*}
    option=${entry#*:}
    if /bin/bash "$REPO_DIR/bin/$command" --help 2>&1 | grep -qF -- "$option"; then
        echo "ok: $command --help"
    else
        echo "FAILED: $command --help does not show $option"
        FAILED=1
    fi
done

TAG=$(bash "$REPO_DIR/lib/suggest_cr_tag.sh" 120)
if [[ "$TAG" == 120.* ]]; then
    echo "ok: suggest_cr_tag.sh"
else
    echo "FAILED: suggest_cr_tag.sh (tag='$TAG')"
    FAILED=1
fi

exit $FAILED
