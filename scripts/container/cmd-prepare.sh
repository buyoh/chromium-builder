export PATH=/mnt/work/src/third_party/depot_tools:$PATH

if [[ -n "$CRENV_USER" ]]; then
    useradd -u 1000 --user-group --create-home --non-unique $CRENV_USER
    chown $CRENV_USER:$CRENV_USER /mnt/work
    usermod -aG $CRENV_USER root

    # change current user to $CRENV_USER
    sudo -u $CRENV_USER "$@"
    # sudo -u $CRENV_USER -i bash -c 'cd '$PWD' && "$@"' -- "$@"
else
    exec "$@"
fi
