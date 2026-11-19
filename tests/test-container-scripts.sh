#!/bin/bash
# Tests for the scripts that run in the container. They run on the host with
# the fixed paths rewritten. git uses local repositories, and the other external
# commands are replaced by stubs in $PATH.
#
# Usage: bash tests/test-container-scripts.sh

set -u
THIS_SCRIPT=$(readlink -f "$0")
BASE_DIR=$(dirname "$(dirname "$THIS_SCRIPT")")

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR:?}"' EXIT

STUB_DIR=$TMP_DIR/stub
SCRIPT_DIR=$TMP_DIR/scripts
REMOTE_DIR=$TMP_DIR/remote
LOG=$TMP_DIR/log
OUT=$TMP_DIR/out
REAL_GIT=$(command -v git)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

mkdir -p "$STUB_DIR" "$SCRIPT_DIR" "$REMOTE_DIR"

FAILED=0

# -----------------------------------------------------------------------------
# Remote repositories

record() {
    # record <name> <body>
    printf '#!/bin/bash\nprintf "%%s\\n" "$(basename "$0") $*" >> "%s"\n%s\n' \
        "$LOG" "${2:-}" > "$STUB_DIR/$1"
    chmod +x "$STUB_DIR/$1"
}

# gclient comes from depot_tools, so it is on PATH only after the checkout.
record gclient '
if [[ "$1" == config ]]; then
    [[ ! -e .gclient ]] || exit 1
    printf "solutions = []\n" > .gclient
    exit 0
fi
exit "${STUB_GCLIENT_EXIT:-0}"'

"$REAL_GIT" init -q "$REMOTE_DIR/depot_tools"
mv "$STUB_DIR/gclient" "$REMOTE_DIR/depot_tools/gclient"
"$REAL_GIT" -C "$REMOTE_DIR/depot_tools" add gclient
"$REAL_GIT" -C "$REMOTE_DIR/depot_tools" commit -q -m pinned
PINNED_HASH=$("$REAL_GIT" -C "$REMOTE_DIR/depot_tools" rev-parse HEAD)
"$REAL_GIT" -C "$REMOTE_DIR/depot_tools" commit -q --allow-empty -m newer
"$REAL_GIT" -C "$REMOTE_DIR/depot_tools" config uploadpack.allowAnySHA1InWant true

"$REAL_GIT" init -q "$REMOTE_DIR/src"
cat > "$REMOTE_DIR/src/DEPS" <<DEPS
  'src/third_party/depot_tools':
    Var('chromium_git') + '/chromium/tools/depot_tools.git' + '@' + '$PINNED_HASH',
DEPS
"$REAL_GIT" -C "$REMOTE_DIR/src" add DEPS
"$REAL_GIT" -C "$REMOTE_DIR/src" commit -q -m old
"$REAL_GIT" -C "$REMOTE_DIR/src" tag 1.0.0.0
"$REAL_GIT" -C "$REMOTE_DIR/src" commit -q --allow-empty -m new
"$REAL_GIT" -C "$REMOTE_DIR/src" tag 2.0.0.0
"$REAL_GIT" -C "$REMOTE_DIR/src" commit -q --allow-empty -m newest
"$REAL_GIT" -C "$REMOTE_DIR/src" tag -a -m annotated 3.0.0.0

# -----------------------------------------------------------------------------
# Stubs

cat > "$STUB_DIR/git" <<STUB
#!/bin/bash
printf '%s\n' "git \$*" >> "$LOG"
args=()
for arg in "\$@"; do
    case "\$arg" in
        https://chromium.googlesource.com/chromium/src*) arg=file://$REMOTE_DIR/src ;;
        https://chromium.googlesource.com/chromium/tools/depot_tools*) arg=file://$REMOTE_DIR/depot_tools ;;
    esac
    args+=("\$arg")
done
exec "$REAL_GIT" "\${args[@]}"
STUB
chmod +x "$STUB_DIR/git"

record apt-get
record debconf-set-selections "input=\$(cat)
printf '%s\n' \"\$input\" >> \"$LOG\"
[[ -z \"\${STUB_DEBCONF_FAIL_ON:-}\" || \"\$input\" != *\"\$STUB_DEBCONF_FAIL_ON\"* ]] || exit 1
exit \"\${STUB_DEBCONF_EXIT:-0}\""
record dpkg-deb 'cp "$2/DEBIAN/control" "$TEST_ROOT/snapcraft-control"
stat -c "%a" "$2" > "$TEST_ROOT/snapcraft-mode"
exit "${STUB_DPKG_DEB_EXIT:-0}"'
record dpkg 'exit "${STUB_DPKG_EXIT:-0}"'
record ln
record clean-after-apt

for script in common.sh fetch-src.sh install-chromium-deps.sh; do
    [[ -e "$BASE_DIR/scripts/container/$script" ]] || continue
    sed -e "s#/mnt/work#\$TEST_ROOT/work#g" \
        -e "s#/tmp/depot_tools#\$TEST_ROOT/tmp-depot_tools#g" \
        -e "s#/opt/depot_tools#\$TEST_ROOT/opt-depot_tools#g" \
        -e "s#/clean-after-apt.sh#$STUB_DIR/clean-after-apt#g" \
        "$BASE_DIR/scripts/container/$script" > "$SCRIPT_DIR/$script"
done

new_root() {
    TEST_ROOT=$(mktemp -d -p "$TMP_DIR")
    export TEST_ROOT
    mkdir "$TEST_ROOT/work" "$TEST_ROOT/tmp"
}

run() {
    # run <script> [VAR=value...]
    : > "$LOG"
    local script=$1
    shift
    (env -u CHECKOUT_CHROMIUM_TAG -u CHECKOUT_LATEST -u FULL_HISTORY \
        PATH="$STUB_DIR:$PATH" TMPDIR="$TEST_ROOT/tmp" "$@" bash "$SCRIPT_DIR/$script") > "$OUT" 2>&1
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
status_not() { [[ "$STATUS" != "$1" ]]; }
log_has() { grep -qF -- "$1" "$LOG"; }
log_lacks() { ! grep -qF -- "$1" "$LOG"; }
log_line() { grep -qxF -- "$1" "$LOG"; }
log_before() {
    # log_before <earlier> <later>
    local earlier later
    earlier=$(grep -nF -- "$1" "$LOG" | head -n 1 | cut -d: -f1)
    later=$(grep -nF -- "$2" "$LOG" | head -n 1 | cut -d: -f1)
    [[ -n "$earlier" && -n "$later" && "$earlier" -lt "$later" ]]
}
out_has() { grep -qF -- "$1" "$OUT"; }
commit_count() { [[ "$("$REAL_GIT" -C "$TEST_ROOT/work/src" rev-list --count HEAD)" == "$1" ]]; }
pin_applied() { [[ "$("$REAL_GIT" -C "$TEST_ROOT/tmp-depot_tools" rev-parse HEAD)" == "$PINNED_HASH" ]]; }
one_target_os() { [[ "$(grep -c target_os "$TEST_ROOT/work/.gclient")" == 1 ]]; }
opt_absent() { [[ ! -e "$TEST_ROOT/opt-depot_tools" ]]; }
build_dir_unchanged() { diff -r "$TEST_ROOT/build-before" "$TEST_ROOT/work/src/build" > /dev/null; }
control_has() { grep -qxF -- "$1" "$TEST_ROOT/snapcraft-control"; }
control_has_no_depends() { [[ -f "$TEST_ROOT/snapcraft-control" ]] && ! grep -qiE '^(pre-)?depends:' "$TEST_ROOT/snapcraft-control"; }
installs_built_deb() {
    local built installed
    built=$(sed -n 's/^dpkg-deb --build [^ ]* //p' "$LOG")
    installed=$(sed -n 's/^dpkg -i //p' "$LOG")
    [[ -n "$built" && "$built" == "$installed" ]]
}
tmp_is_empty() { [[ -z "$(ls -A "$TEST_ROOT/tmp")" ]]; }
snapcraft_mode_is() { [[ "$(cat "$TEST_ROOT/snapcraft-mode")" == "$1" ]]; }

# -----------------------------------------------------------------------------
# fetch-src.sh: 12 history

new_root
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=1.0.0.0
check "12: tag clone succeeds" status_is 0
check "12: tag clone is shallow" log_has "--depth 2 --single-branch --branch 1.0.0.0"
check "12: gclient has no history" log_has "--no-history"
check "12: shallow clone of the first commit" commit_count 1
check "17: depot_tools is pinned" pin_applied

new_root
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=3.0.0.0
check "12: shallow clone keeps the parent" commit_count 2
rm -rf "${TEST_ROOT:?}/tmp-depot_tools"
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=3.0.0.0
check "11: rerun accepts an annotated tag" status_is 0
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=3.0.0.0 FULL_HISTORY=true
check "11: shallow src rejects --full-history" status_is 1
check "11: shallow src reports the reason" out_has "shallow"
check "11: shallow src does not run gclient" log_lacks "gclient"

new_root
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=2.0.0.0 FULL_HISTORY=true
check "12: full history succeeds" status_is 0
check "12: full history is a full clone" log_lacks "--depth"
check "12: gclient keeps history" log_lacks "--no-history"
check "12: full clone has all commits" commit_count 2
check "12: full clone has no shallow file" test ! -e "$TEST_ROOT/work/src/.git/shallow"

new_root
run fetch-src.sh CHECKOUT_LATEST=true
check "12: HEAD succeeds" status_is 0
check "12: HEAD is shallow" log_has "--depth 2 --single-branch"

new_root
run fetch-src.sh
check "fetch: no target is rejected" status_is 1

new_root
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=1.0.0.0 CHECKOUT_LATEST=true
check "fetch: two targets are rejected" status_is 1

# -----------------------------------------------------------------------------
# fetch-src.sh: 11 resume

new_root
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=1.0.0.0 STUB_GCLIENT_EXIT=1
check "11: failed gclient fails the fetch" status_not 0
rm -rf "${TEST_ROOT:?}/tmp-depot_tools"
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=1.0.0.0
check "11: rerun succeeds" status_is 0
check "11: rerun skips the clone of src" log_lacks "--branch 1.0.0.0"
check "11: rerun runs gclient sync" log_has "gclient sync"
check "11: .gclient has no duplicate" one_target_os

rm -rf "${TEST_ROOT:?}/tmp-depot_tools"
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=2.0.0.0
check "11: another tag is rejected" status_is 1
check "11: another tag is reported" out_has "2.0.0.0"
check "11: another tag does not run gclient" log_lacks "gclient"

new_root
mkdir -p "$TEST_ROOT/work/src/.git"
cp "$REMOTE_DIR/src/DEPS" "$TEST_ROOT/work/src/DEPS"
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=1.0.0.0
check "11: broken src/.git is rejected" status_is 1
check "11: broken src/.git does not run gclient" log_lacks "gclient"

# -----------------------------------------------------------------------------
# fetch-src.sh: 17 pin

new_root
"$REAL_GIT" clone -q "file://$REMOTE_DIR/src" "$TEST_ROOT/work/src"
"$REAL_GIT" -C "$TEST_ROOT/work/src" checkout -q 1.0.0.0
echo "no pin" > "$TEST_ROOT/work/src/DEPS"
run fetch-src.sh CHECKOUT_CHROMIUM_TAG=1.0.0.0
check "17: fetch rejects a missing pin" status_is 1
check "17: fetch does not clone depot_tools" log_lacks "depot_tools.git"

# -----------------------------------------------------------------------------
# install-chromium-deps.sh

BUILD_DEPS_ARGS="--backwards-compatible --no-prompt --syms --lib32 --arm --chromeos-fonts"

new_install_root() {
    new_root
    mkdir -p "$TEST_ROOT/work/src/build" "$TEST_ROOT/work/src/chrome" \
        "$TEST_ROOT/work/src/third_party/depot_tools"
    cp "$REMOTE_DIR/src/DEPS" "$TEST_ROOT/work/src/DEPS"
    printf 'MAJOR=120\nMINOR=0\nBUILD=1\nPATCH=2\n' > "$TEST_ROOT/work/src/chrome/VERSION"
    # Like 102 and 108, the script rejects --android by default. It runs with
    # the -e of the caller and fails at the end when STUB_DEPS_FAIL is set.
    printf 'printf "%%s\\n" "install-build-deps $*" >> "%s"\n[[ " $* " != *" --android "* ]]\n' "$LOG" \
        > "$TEST_ROOT/work/src/build/install-build-deps.sh"
    printf 'false_when_stubbed() { [[ -z "${STUB_DEPS_FAIL:-}" ]]; }\nfalse_when_stubbed\necho reached-the-end\n' \
        >> "$TEST_ROOT/work/src/build/install-build-deps.sh"
    printf 'packages = [\n      "snapcraft",\n]\n' > "$TEST_ROOT/work/src/build/install-build-deps.py"
}

accept_android_in_sh() {
    printf 'case "$1" in\n  --android) ;;\nesac\nprintf "%%s\\n" "install-build-deps $*" >> "%s"\n' "$LOG" \
        > "$TEST_ROOT/work/src/build/install-build-deps.sh"
}

accept_android_in_py() {
    printf 'printf "%%s\\n" "install-build-deps $*" >> "%s"\n' "$LOG" \
        > "$TEST_ROOT/work/src/build/install-build-deps.sh"
    printf '      "--android",\n' >> "$TEST_ROOT/work/src/build/install-build-deps.py"
}

add_android_script() {
    # add_android_script [exit status]
    printf 'printf "%%s\\n" "android-deps $*" >> "%s"\nexit %s\n' "$LOG" "${1:-0}" \
        > "$TEST_ROOT/work/src/build/install-build-deps-android.sh"
}

new_install_root
cp -r "$TEST_ROOT/work/src/build" "$TEST_ROOT/build-before"
run install-chromium-deps.sh
check "install: succeeds" status_is 0
check "install: runs install-build-deps" log_has "install-build-deps"
check "install: runs the clean up" log_has "clean-after-apt"
check "17: install fetches the pinned depot_tools" log_has "fetch --depth 1 origin $PINNED_HASH"
check "14: image has no copy of depot_tools" opt_absent
check "snapcraft: empty package is named snapcraft" control_has "Package: snapcraft"
check "snapcraft: empty package has a higher version" control_has "Version: 9999"
check "snapcraft: empty package has no dependencies" control_has_no_depends
check "snapcraft: package root is not private" snapcraft_mode_is 755
check "snapcraft: built before it is installed" log_before "dpkg-deb --build" "dpkg -i"
check "snapcraft: installs the built package" installs_built_deb
check "snapcraft: temporary files are removed" tmp_is_empty
check "snapcraft: installed before install-build-deps" log_before "dpkg -i" "install-build-deps"
check "snapcraft: source tree is not changed" build_dir_unchanged
check "snapcraft: debconf frontend is noninteractive" log_has "debconf debconf/frontend select Noninteractive"
check "snapcraft: debconf frontend is set before install-build-deps" log_before "debconf/frontend" "install-build-deps"

new_install_root
run install-chromium-deps.sh STUB_DEBCONF_EXIT=1
check "05: debconf failure stops the script" status_not 0
check "05: debconf failure skips install-build-deps" log_lacks "install-build-deps"
check "05: debconf failure skips the clean up" log_lacks "clean-after-apt"

new_install_root
run install-chromium-deps.sh STUB_DEBCONF_FAIL_ON=debconf/frontend
check "snapcraft: debconf frontend failure stops the script" status_not 0
check "snapcraft: debconf frontend failure skips install-build-deps" log_lacks "install-build-deps"

new_install_root
run install-chromium-deps.sh STUB_DPKG_DEB_EXIT=1
check "snapcraft: dpkg-deb failure stops the script" status_not 0
check "snapcraft: dpkg-deb failure skips install-build-deps" log_lacks "install-build-deps"

new_install_root
run install-chromium-deps.sh STUB_DPKG_EXIT=1
check "snapcraft: dpkg failure stops the script" status_not 0
check "snapcraft: dpkg failure skips install-build-deps" log_lacks "install-build-deps"

new_install_root
run install-chromium-deps.sh
check "android: unsupported version succeeds" status_is 0
check "android: unsupported version gets the other options" log_line "install-build-deps $BUILD_DEPS_ARGS"

new_install_root
rm "$TEST_ROOT/work/src/build/install-build-deps.py"
run install-chromium-deps.sh
check "android: missing .py succeeds" status_is 0
check "android: missing .py does not pass --android" log_line "install-build-deps $BUILD_DEPS_ARGS"
check "android: missing .py is not reported by grep" test -z "$(grep 'No such file' "$OUT")"

new_install_root
accept_android_in_sh
run install-chromium-deps.sh
check "android: .sh definition passes --android" log_line "install-build-deps $BUILD_DEPS_ARGS --android"

new_install_root
accept_android_in_py
run install-chromium-deps.sh
check "android: .py definition passes --android" log_line "install-build-deps $BUILD_DEPS_ARGS --android"

new_install_root
printf '# "--android", was removed\n' >> "$TEST_ROOT/work/src/build/install-build-deps.py"
printf '# --android) was removed\n' >> "$TEST_ROOT/work/src/build/install-build-deps.sh"
run install-chromium-deps.sh
check "android: a comment does not enable --android" status_is 0
check "android: a comment does not pass --android" log_line "install-build-deps $BUILD_DEPS_ARGS"

new_install_root
printf '      "--no-android",\n' >> "$TEST_ROOT/work/src/build/install-build-deps.py"
printf '  --no-android) ;;\n' >> "$TEST_ROOT/work/src/build/install-build-deps.sh"
run install-chromium-deps.sh
check "android: --no-android does not pass --android" log_line "install-build-deps $BUILD_DEPS_ARGS"

new_install_root
run install-chromium-deps.sh STUB_DEPS_FAIL=1
check "install: failure inside install-build-deps stops the script" status_not 0
check "install: failure inside install-build-deps skips the clean up" log_lacks "clean-after-apt"

new_install_root
run install-chromium-deps.sh
check "android: no separate script is run by default" log_lacks "android-deps"

new_install_root
add_android_script
run install-chromium-deps.sh
check "android: separate script is run after install-build-deps" log_before "install-build-deps --backwards-compatible" "android-deps"
check "android: separate script is run before the clean up" log_before "android-deps" "clean-after-apt"
check "android: separate script has no arguments" log_line "android-deps "

new_install_root
add_android_script 1
run install-chromium-deps.sh
check "android: separate script failure stops the script" status_not 0
check "android: separate script failure skips the clean up" log_lacks "clean-after-apt"

new_install_root
run install-chromium-deps.sh STUB_GCLIENT_EXIT=1
check "05: gclient failure stops the script" status_not 0

new_install_root
echo "no pin" > "$TEST_ROOT/work/src/DEPS"
run install-chromium-deps.sh
check "17: install rejects a missing pin" status_not 0
check "17: install does not fall back to HEAD" log_lacks "depot_tools.git"

new_install_root
sed -i "1i '/chromium/tools/depot_tools.git' has no hash in this comment" "$TEST_ROOT/work/src/DEPS"
run install-chromium-deps.sh
check "17: install skips a line without a hash" log_has "fetch --depth 1 origin $PINNED_HASH"

new_install_root
sed -i "s/'[0-9a-f]\{40\}'/'0000${PINNED_HASH}'/" "$TEST_ROOT/work/src/DEPS"
run install-chromium-deps.sh
check "17: install rejects a hash that is too long" status_not 0

new_install_root
rm "$TEST_ROOT/work/src/DEPS"
run install-chromium-deps.sh
check "17: install rejects a missing DEPS" status_not 0
check "17: install without DEPS does not fall back to HEAD" log_lacks "depot_tools.git"

new_install_root
cat >> "$TEST_ROOT/work/src/DEPS" <<DEPS
  'other': 'https://chromium.googlesource.com/chromium/tools/depot_tools.git@1111111111111111111111111111111111111111',
DEPS
run install-chromium-deps.sh
check "17: install uses only the first match" log_has "fetch --depth 1 origin $PINNED_HASH"

new_install_root
run install-chromium-deps.sh
check "07: runhooks has its arguments" log_has "gclient runhooks -j 16 --force"

new_install_root
run install-chromium-deps.sh ARG_GCLIENT_SYNC=true
check "07: sync has its arguments" log_has "gclient sync -D -j 16 --force"

# -----------------------------------------------------------------------------
# cmd-prepare.sh

: > "$LOG"
(env -u CRENV_USER bash "$BASE_DIR/scripts/container/cmd-prepare.sh" -a foo true) > "$OUT" 2>&1
STATUS=$?
check "07: a command is not an option of exec" status_is 127

exit $FAILED
