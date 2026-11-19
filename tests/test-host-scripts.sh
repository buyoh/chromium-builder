#!/bin/bash
# Tests for the host scripts. Docker is replaced by a stub in $PATH.
#
# Usage: bash tests/test-host-scripts.sh

set -u
THIS_SCRIPT=$(readlink -f "$0")
BASE_DIR=$(dirname "$(dirname "$THIS_SCRIPT")")

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR:?}"' EXIT

STUB_DIR=$TMP_DIR/stub
LOG=$TMP_DIR/log
OUT=$TMP_DIR/out
WORK_DIR=$TMP_DIR/work
mkdir -p "$STUB_DIR" "$WORK_DIR/src/chrome"
printf 'MAJOR=120\nMINOR=0\nBUILD=6099\nPATCH=234\n' > "$WORK_DIR/src/chrome/VERSION"

FAILED=0

cat > "$STUB_DIR/docker" <<STUB
#!/bin/bash
for arg in "\$@"; do
    printf '%s: %s\n' "\$1" "\$arg"
done >> "$LOG"
case "\$1" in
    info) echo "[name=\${STUB_DOCKER_MODE:-rootless}]" ;;
    image)
    if [[ "\$2" == ls ]]; then
        echo "\${STUB_IMAGES:-}"
        exit "\${STUB_IMAGE_LS_EXIT:-0}"
    else
        [[ -z "\${STUB_NO_IMAGE:-}" ]]
    fi
    ;;
    run) exit "\${STUB_RUN_EXIT:-0}" ;;
esac
STUB
chmod +x "$STUB_DIR/docker"

run() {
    # run <command> <argument...>
    : > "$LOG"
    (cd "$WORK_DIR" && PATH="$STUB_DIR:$PATH" DISPLAY=:0 \
        /bin/bash "$BASE_DIR/bin/$1" "${@:2}") < /dev/null > "$OUT" 2>&1
    STATUS=$?
}

check() {
    # check <description> <command...>
    local description=$1
    shift
    if "$@"; then
        echo "ok: $description"
    else
        echo "FAILED: $description"
        sed -e 's/^/  log: /' "$LOG"
        sed -e 's/^/  out: /' "$OUT"
        FAILED=1
    fi
}

status_is() { [[ "$STATUS" == "$1" ]]; }
log_has() { grep -qxF -- "$1" "$LOG"; }
log_lacks() { ! grep -qxF -- "$1" "$LOG"; }
out_has() { grep -qF -- "$1" "$OUT"; }
out_lacks() { ! grep -qF -- "$1" "$OUT"; }
no_docker_run() { ! grep -q '^run: ' "$LOG"; }

# -----------------------------------------------------------------------------
# 01: Dockerfile

no_missing_copy() { ! grep -q 'COPY fetch-src.sh' "$BASE_DIR/docker/base/Dockerfile"; }
check "01: Dockerfile does not copy a missing file" no_missing_copy

# -----------------------------------------------------------------------------
# 02: cwd independent

mkdir -p "$WORK_DIR/lib"
printf '#!/bin/bash\necho 666.0.0.0\n' > "$WORK_DIR/lib/suggest_cr_tag.sh"
chmod +x "$WORK_DIR/lib/suggest_cr_tag.sh"
run cr-fetch-src --cr 120 --dest "$WORK_DIR/dest"
rm -r "${WORK_DIR:?}/lib"
check "02: --cr works outside the repository" status_is 0
check "02: --cr resolves with the repository's lib" log_has "run: CHECKOUT_CHROMIUM_TAG=120.0.6099.234"

# -----------------------------------------------------------------------------
# 04: DISPLAY

: > "$LOG"
(cd "$WORK_DIR" && env -u DISPLAY PATH="$STUB_DIR:$PATH" bash "$BASE_DIR/bin/cr-exec-env") \
    < /dev/null > "$OUT" 2>&1
STATUS=$?
check "04: unset DISPLAY succeeds" status_is 0
check "04: unset DISPLAY starts a container" log_has "run: run"

# -----------------------------------------------------------------------------
# 12: history

run cr-fetch-src --cr HEAD --dest "$WORK_DIR/dest"
check "12: no history by default" log_lacks "run: FULL_HISTORY=true"
run cr-fetch-src --cr HEAD --dest "$WORK_DIR/dest" --full-history
check "12: --full-history is passed" log_has "run: FULL_HISTORY=true"

# -----------------------------------------------------------------------------
# 13: --image

run cr-exec-env --image registry:5000/name:v2
check "13: --image is checked as is" log_has "image: registry:5000/name:v2"
check "13: --image is used as is" log_has "run: registry:5000/name:v2"

# -----------------------------------------------------------------------------
# --img

STUB_IMAGES=$'env-chromium-build/focal-132.0.6834.9
env-chromium-build/focal-132.0.6834.161
env-chromium-build/focal-132.0.999.1
env-chromium-build/focal-133.0.1.1
env-chromium-build/focal-1320.0.1.1
env-chromium-build/jammy-132.0.9999.1'
export STUB_IMAGES

run cr-exec-env --img focal-132
check "img: selects the latest version" log_has "run: env-chromium-build/focal-132.0.6834.161:v1"
check "img: lists only the current tag" log_has "image: reference=env-chromium-build/*:v1"

run cr-exec-env --img focal-132.0.999
check "img: prefix may have several components" log_has "run: env-chromium-build/focal-132.0.999.1:v1"

run cr-exec-env --img focal-132.0.6834.9
check "img: full version is accepted" log_has "run: env-chromium-build/focal-132.0.6834.9:v1"

run cr-exec-env --img jammy-132
check "img: codename is part of the prefix" log_has "run: env-chromium-build/jammy-132.0.9999.1:v1"

for prefix in focal-13 focal focal-134 'focal-*'; do
    run cr-exec-env --img "$prefix"
    check "img: '$prefix' does not match" status_is 1
    check "img: '$prefix' does not start a container" no_docker_run
    check "img: '$prefix' tells how to create the image" out_has "cr-setup-builder-docker-image"
done

STUB_IMAGES= run cr-exec-env --img focal-132
check "img: no image is an error" status_is 1
check "img: no image does not start a container" no_docker_run

STUB_IMAGE_LS_EXIT=1 run cr-exec-env --img focal-132
check "img: docker failure is an error" status_is 1
check "img: docker failure does not start a container" no_docker_run
check "img: docker failure is not reported as no match" out_lacks "No builder image matches"

run cr-exec-env --image name:v2 --img focal-132
check "img: --image and --img conflict" status_is 1
check "img: conflict is reported first" log_lacks "version: version"
check "img: conflict does not start a container" no_docker_run

unset STUB_IMAGES

# -----------------------------------------------------------------------------
# 14: committed image config

run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
check "14: commit resets CMD" log_has 'commit: CMD ["/bin/bash"]'
check "14: commit clears ARG_GCLIENT_SYNC" log_has "commit: ENV ARG_GCLIENT_SYNC="

# -----------------------------------------------------------------------------
# 15: contract

check "15: builder image name" log_has "commit: env-chromium-build/focal-120.0.6099.234:v1"
check "15: builder base image name" log_has "run: env-chromium/focal:v1"
run cr-exec-env
check "15: exec image name" log_has "run: env-chromium-build/focal-120.0.6099.234:v1"
run cr-setup-base-docker-image
check "15: base image name" log_has "build: env-chromium/focal:v1"

# -----------------------------------------------------------------------------
# 16: messages

run cr-fetch-src --dest "$WORK_DIR/dest"
check "16: a missing target is an error" status_is 1
check "16: error does not mention --latest" out_lacks "--latest"

# -----------------------------------------------------------------------------
# 20: input validation

for tag in -x 1.2.3 1.2.3/4 main; do
    run cr-fetch-src --chromium "$tag" --dest "$WORK_DIR/dest"
    check "20: tag '$tag' is rejected" status_is 1
    check "20: tag '$tag' does not start a container" no_docker_run
done
run cr-fetch-src --chromium 120.0.6099.234 --dest "$WORK_DIR/dest"
check "20: full tag is accepted" status_is 0

for version in 1 12 13; do
    run cr-fetch-src --cr "$version" --dest "$WORK_DIR/dest"
    check "20: --cr $version is not a prefix match" status_is 1
    check "20: --cr $version does not start a container" no_docker_run
done

for username in -x Dev 1dev; do
    STUB_DOCKER_MODE=no-rootless run cr-exec-env --username "$username"
    check "20: username '$username' is rejected" status_is 1
    check "20: username '$username' does not start a container" no_docker_run
done

MARKER=$TMP_DIR/marker
marker_absent() { [[ ! -e "$MARKER" ]]; }
cp "$WORK_DIR/src/chrome/VERSION" "$TMP_DIR/VERSION"
printf 'touch %s\n' "$MARKER" >> "$WORK_DIR/src/chrome/VERSION"
run cr-exec-env
check "20: chrome/VERSION is not executed" marker_absent
check "20: chrome/VERSION is still read" log_has "run: env-chromium-build/focal-120.0.6099.234:v1"
printf 'MAJOR=$(touch %s)\nMINOR=0\nBUILD=1\nPATCH=2\n' "$MARKER" > "$WORK_DIR/src/chrome/VERSION"
run cr-exec-env
check "20: broken chrome/VERSION is rejected" status_is 1
check "20: broken chrome/VERSION is not executed" marker_absent
cp "$TMP_DIR/VERSION" "$WORK_DIR/src/chrome/VERSION"

run cr-fetch-src --cr HEAD --dest "$WORK_DIR/missing/parent/dest"
check "20: --dest creates the parents" status_is 0
check "20: --dest is mounted" log_has "run: $WORK_DIR/missing/parent/dest:/mnt/work"

# -----------------------------------------------------------------------------
# 21: implicit pull

run cr-fetch-src --cr HEAD --dest "$WORK_DIR/dest"
check "21: fetch never pulls" log_has "run: --pull=never"
run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
check "21: builder never pulls" log_has "run: --pull=never"
run cr-exec-env
check "21: exec never pulls" log_has "run: --pull=never"

STUB_NO_IMAGE=1 run cr-fetch-src --cr HEAD --dest "$WORK_DIR/dest"
check "21: fetch stops without the image" status_is 1
check "21: fetch does not start a container" no_docker_run
check "21: fetch tells how to create the image" out_has "cr-setup-base-docker-image"
STUB_NO_IMAGE=1 run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
check "21: builder stops without the image" status_is 1
check "21: builder does not start a container" no_docker_run
check "21: builder tells how to create the image" out_has "cr-setup-base-docker-image"
STUB_NO_IMAGE=1 run cr-exec-env
check "21: exec stops without the image" status_is 1
check "21: exec does not start a container" no_docker_run
dest_absent() { [[ ! -e "$WORK_DIR/new-dest" ]]; }
STUB_NO_IMAGE=1 run cr-fetch-src --cr HEAD --dest "$WORK_DIR/new-dest"
check "21: fetch does not create --dest without the image" dest_absent

STUB_RUN_EXIT=1 run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
check "14: builder fails if the container fails" status_is 1
no_commit() { ! grep -q '^commit: ' "$LOG"; }
check "14: builder does not commit if the container fails" no_commit

# -----------------------------------------------------------------------------
# 23: dead code

run cr-fetch-src --help
check "23: --reference is removed" out_lacks "--reference"
entrypoint_absent() { [[ ! -e "$BASE_DIR/docker/base/entrypoint.sh" ]]; }
check "23: entrypoint.sh is removed" entrypoint_absent

# -----------------------------------------------------------------------------
# 24: TTY

run cr-fetch-src --cr HEAD --dest "$WORK_DIR/dest"
check "24: fetch has no -it without a TTY" log_lacks "run: -it"
run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
check "24: builder has no -it without a TTY" log_lacks "run: -it"

: > "$LOG"
(cd "$WORK_DIR" && PATH="$STUB_DIR:$PATH" script -qec \
    "bash '$BASE_DIR/bin/cr-fetch-src' --cr HEAD --dest '$WORK_DIR/dest'" /dev/null) > "$OUT" 2>&1
check "24: fetch has -it with a TTY" log_has "run: -it"
: > "$LOG"
(cd "$WORK_DIR" && PATH="$STUB_DIR:$PATH" script -qec \
    "bash '$BASE_DIR/bin/cr-setup-builder-docker-image' --cr-dir '$WORK_DIR'" /dev/null) > "$OUT" 2>&1
check "24: builder has -it with a TTY" log_has "run: -it"

# -----------------------------------------------------------------------------
# 06: working container

container_name() { sed -n 's/^run: \(env-chromium-tmp-[0-9][0-9]*\)$/\1/p' "$LOG" | head -n 1; }
rm_count() { [[ "$(grep -c '^rm: rm$' "$LOG")" == 1 ]]; }
name_is_unique() { [[ -n "$NAME" ]] && [[ -n "$OTHER_NAME" ]] && [[ "$NAME" != "$OTHER_NAME" ]]; }

run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
OTHER_NAME=$(container_name)
run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
NAME=$(container_name)
check "06: container name is unique" name_is_unique
check "06: commit uses the same container" log_has "commit: $NAME"
check "06: trap removes the same container" log_has "rm: $NAME"
check "06: the container is removed once" rm_count

STUB_RUN_EXIT=1 run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
NAME=$(container_name)
check "06: failed run removes only its own container" log_has "rm: $NAME"
check "06: fixed name is not removed" log_lacks "rm: env-chromium-tmp"

# -----------------------------------------------------------------------------
# 07: command arguments

run cr-exec-env -- bash -c 'cd src && autoninja -C "out/my release" chrome'
check "07: command succeeds" status_is 0
check "07: command is not flattened" log_has 'run: cd src && autoninja -C "out/my release" chrome'
check "07: command keeps its option" log_has "run: -c"

run cr-exec-env -- ls '*' ''
check "07: glob is not expanded on the host" log_has "run: *"
check "07: empty argument is kept" log_has "run: "

run cr-exec-env
check "07: default command is bash" log_has "run: /bin/bash"

run cr-exec-env --gpu-all
check "07: --gpu-all has its option" log_has "run: --gpus"
check "07: --gpu-all has its value" log_has "run: all"

printf '#!/bin/bash\necho $$ > "%s"\nexec sleep 60\n' "$TMP_DIR/xephyr.pid" > "$STUB_DIR/Xephyr"
chmod +x "$STUB_DIR/Xephyr"
run cr-exec-env --xephyr 100x100
kill "$(cat "$TMP_DIR/xephyr.pid")"
check "07: --xephyr sets DISPLAY" log_has "run: DISPLAY=:99"

run cr-setup-base-docker-image
check "07: base build uses the cache by default" log_lacks "build: --no-cache"
run cr-setup-base-docker-image --no-cache
check "07: base build passes --no-cache" log_has "build: --no-cache"
check "07: base build passes the context" log_has "build: ./docker/base"

run cr-setup-builder-docker-image --cr-dir "$WORK_DIR" --gclient-sync
check "07: builder passes the environment" log_has "run: ARG_GCLIENT_SYNC=true"
check "07: builder runs the install script" log_has "run: /mnt/scripts/install-chromium-deps.sh"

run cr-fetch-src --chromium 120.0.6099.234 --dest "$WORK_DIR/dest"
check "07: fetch passes the environment" log_has "run: CHECKOUT_CHROMIUM_TAG=120.0.6099.234"
check "07: fetch runs the fetch script" log_has "run: /mnt/scripts/fetch-src.sh"

# run_args_end_with <argument...>
# Check that the last arguments of `docker run` are exactly the given ones.
run_args_end_with() {
    [[ "$(sed -n 's/^run: //p' "$LOG" | tail -n $#)" == "$(printf '%s\n' "$@")" ]]
}
build_args_end_with() {
    [[ "$(sed -n 's/^build: //p' "$LOG" | tail -n $#)" == "$(printf '%s\n' "$@")" ]]
}

EXEC_IMAGE=env-chromium-build/focal-120.0.6099.234:v1

run cr-exec-env -- bash -c 'cd src && pwd'
check "07: exec separates the image and the command" run_args_end_with \
    "$EXEC_IMAGE" /bin/bash /mnt/scripts/cmd-prepare.sh bash -c 'cd src && pwd'
check "07: exec keeps --init" log_has "run: --init"
check "07: exec keeps --rm" log_has "run: --rm"
check "07: exec keeps -it" log_has "run: -it"
check "07: exec keeps the workdir" log_has "run: -w"
check "07: exec keeps the workdir value" log_has "run: /mnt/work"
check "07: exec keeps the X11 mount" log_has "run: /tmp/.X11-unix:/tmp/.X11-unix:ro"

run cr-exec-env
check "07: exec default command is after the image" run_args_end_with \
    "$EXEC_IMAGE" /bin/bash /mnt/scripts/cmd-prepare.sh /bin/bash

run cr-fetch-src --cr HEAD --dest "$WORK_DIR/dest"
check "07: fetch separates the image and the command" run_args_end_with \
    env-chromium/focal:v1 /bin/bash /mnt/scripts/fetch-src.sh
check "07: fetch keeps --init" log_has "run: --init"
check "07: fetch keeps --rm" log_has "run: --rm"
check "07: fetch keeps the workdir" log_has "run: -w"

run cr-setup-builder-docker-image --cr-dir "$WORK_DIR"
check "07: builder separates the image and the command" run_args_end_with \
    env-chromium/focal:v1 /bin/bash /mnt/scripts/install-chromium-deps.sh

run cr-setup-base-docker-image --no-cache
check "07: base build has the context last" build_args_end_with ./docker/base

exit $FAILED
