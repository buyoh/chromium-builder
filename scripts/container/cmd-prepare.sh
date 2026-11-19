set -euo pipefail

export PATH=/mnt/work/src/third_party/depot_tools:$PATH

if [[ -n "${CRENV_USER:-}" ]]; then
    groupadd -g "$CRENV_GID" --non-unique "$CRENV_USER"
    useradd -u "$CRENV_UID" -g "$CRENV_GID" --create-home --shell /bin/bash --non-unique "$CRENV_USER"

    # change current user to $CRENV_USER
    # sudo drops PATH and the other environment variables.
    exec sudo -u "$CRENV_USER" env "PATH=$PATH" DEPOT_TOOLS_UPDATE=0 "$@"
else
    exec -- "$@"
fi
