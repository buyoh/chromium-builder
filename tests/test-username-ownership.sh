#!/bin/bash
# Tests for the ownership contract of `cr-exec-env --username`.
# Docker and the user management commands are replaced by stubs in $PATH.
#
# Usage: bash tests/test-username-ownership.sh

set -u
THIS_SCRIPT=$(readlink -f "$0")
BASE_DIR=$(dirname "$(dirname "$THIS_SCRIPT")")

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_DIR=$TMP_DIR/stub
LOG=$TMP_DIR/log
WORK_DIR=$TMP_DIR/work
mkdir -p "$STUB_DIR" "$WORK_DIR/src/chrome"
printf 'MAJOR=1\nMINOR=2\nBUILD=3\nPATCH=4\n' > "$WORK_DIR/src/chrome/VERSION"

FAILED=0

stub() {
    # Record the call, then run the given body.
    printf '#!/bin/bash\n{ printf "%%s " "$(basename "$0")"; printf "%%q " "$@"; echo; } >> "%s"\n%s\n' \
        "$LOG" "${2:-}" > "$STUB_DIR/$1"
    chmod +x "$STUB_DIR/$1"
}

stub docker '
case "$1" in
    version) [[ "$STUB_DOCKER_MODE" != broken ]] ;;
    info)
        # The real command exits with 0 and prints [] if the daemon is unreachable.
        if [[ "$STUB_DOCKER_MODE" == broken ]]; then
            echo "[]"
        else
            echo "[name=seccomp,profile=builtin $STUB_DOCKER_MODE name=cgroupns]"
        fi ;;
    images) echo 0123456789ab ;;
esac'
stub id '
case "$1" in
    -u) echo "$STUB_UID" ;;
    -g) echo "$STUB_GID" ;;
esac'
stub groupadd 'exit "${STUB_GROUPADD_EXIT:-0}"'
stub useradd 'exit "${STUB_USERADD_EXIT:-0}"'
stub usermod
stub chown
stub sudo

run_exec_env() {
    : > "$LOG"
    (cd "$WORK_DIR" && PATH="$STUB_DIR:$PATH" DISPLAY=:0 \
        STUB_DOCKER_MODE=$1 STUB_UID=${STUB_UID:-1234} STUB_GID=${STUB_GID:-2345} \
        bash "$BASE_DIR/scripts/exec-env.sh" "${@:2}") > "$TMP_DIR/out" 2>&1
    STATUS=$?
}

run_prepare() {
    : > "$LOG"
    (env -u CRENV_USER -u CRENV_UID -u CRENV_GID PATH="$STUB_DIR:$PATH" "$@" \
        bash "$BASE_DIR/scripts/container/cmd-prepare.sh" printenv-args "arg with space") \
        > "$TMP_DIR/out" 2>&1
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
        sed -e 's/^/  out: /' "$TMP_DIR/out"
        FAILED=1
    fi
}

status_is() { [[ "$STATUS" == "$1" ]]; }
status_not() { [[ "$STATUS" != "$1" ]]; }
log_has() { grep -qF -- "$1" "$LOG"; }
log_lacks() { ! grep -qF -- "$1" "$LOG"; }
out_has() { grep -qF -- "$1" "$TMP_DIR/out"; }
out_lacks() { ! grep -qF -- "$1" "$TMP_DIR/out"; }

# -----------------------------------------------------------------------------
# exec-env.sh

run_exec_env name=rootless --username dev
check "rootless: --username is rejected" status_is 1
check "rootless: --username explains the reason" out_has "rootless"
check "rootless: --username does not start a container" log_lacks "docker run"

run_exec_env name=rootless --username root
check "rootless: --username root is accepted" status_is 0
check "rootless: --username root starts a container" log_has "docker run"
check "rootless: --username root does not set CRENV_USER" log_lacks "CRENV_USER"

run_exec_env name=rootless
check "rootless: default runs as root" status_is 0
check "rootless: default does not set CRENV_USER" log_lacks "CRENV_USER"
check "rootless: default has no warning" out_lacks "Warning"

run_exec_env no-rootless --username dev
check "rootful: --username is accepted" status_is 0
check "rootful: passes the user" log_has "-e CRENV_USER=dev"
check "rootful: passes the host UID" log_has "-e CRENV_UID=1234"
check "rootful: passes the host GID" log_has "-e CRENV_GID=2345"
check "rootful: --username has no warning" out_lacks "Warning"

run_exec_env no-rootless --username root
check "rootful: --username root is accepted" status_is 0
check "rootful: --username root does not set CRENV_USER" log_lacks "CRENV_USER"

chmod a-w "$WORK_DIR/src"
run_exec_env no-rootless --username dev
chmod u+w "$WORK_DIR/src"
check "rootful: read-only src warns" out_has "not writable"
check "rootful: read-only src still starts a container" log_has "docker run"

STUB_UID=0 run_exec_env no-rootless --username dev
check "rootful: --username is rejected for the host root" status_is 1
check "rootful: host root does not start a container" log_lacks "docker run"

STUB_UID=0 run_exec_env no-rootless
check "rootful: host root is allowed" status_is 0
check "rootful: host root has no warning" out_lacks "Warning"

run_exec_env no-rootless
check "rootful: default is allowed" status_is 0
check "rootful: default warns about root owned files" out_has "Warning"

run_exec_env broken
check "broken daemon: fails" status_is 1
check "broken daemon: reports the reason" out_has "Failed to query docker"
check "broken daemon: does not start a container" log_lacks "docker run"

# -----------------------------------------------------------------------------
# cmd-prepare.sh

stub printenv-args 'echo "PATH=$PATH"'

run_prepare
check "prepare: no user runs the command directly" status_is 0
check "prepare: no user keeps the arguments" log_has "printenv-args arg\ with\ space"
check "prepare: no user creates nobody" log_lacks "useradd"
check "prepare: PATH has depot_tools" out_has "PATH=/mnt/work/src/third_party/depot_tools:"

run_prepare CRENV_USER=dev CRENV_UID=1234 CRENV_GID=2345
check "prepare: user succeeds" status_is 0
check "prepare: creates the group with the host GID" log_has "groupadd -g 2345 --non-unique dev"
check "prepare: creates the user with the host UID" log_has "useradd -u 1234 -g 2345"
check "prepare: gives the user a login shell" log_has "--shell /bin/bash"
check "prepare: never changes ownership" log_lacks "chown"
check "prepare: does not touch the root user" log_lacks "usermod"
check "prepare: keeps PATH across sudo" log_has "PATH=/mnt/work/src/third_party/depot_tools:"
check "prepare: keeps DEPOT_TOOLS_UPDATE across sudo" log_has "DEPOT_TOOLS_UPDATE=0"
check "prepare: keeps the arguments across sudo" log_has "printenv-args arg\ with\ space"

run_prepare STUB_GROUPADD_EXIT=9 CRENV_USER=daemon CRENV_UID=1234 CRENV_GID=2345
check "prepare: stops when the user cannot be created" status_not 0
check "prepare: does not run the command after a failure" log_lacks "sudo"

run_prepare STUB_USERADD_EXIT=9 CRENV_USER=sync CRENV_UID=1234 CRENV_GID=2345
check "prepare: stops when useradd fails" status_not 0
check "prepare: does not run the command after a useradd failure" log_lacks "sudo"

run_prepare CRENV_USER=dev
check "prepare: rejects a user without UID and GID" status_not 0
check "prepare: does not create a user without UID and GID" log_lacks "useradd"

exit $FAILED
