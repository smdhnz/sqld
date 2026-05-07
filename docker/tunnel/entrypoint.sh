#!/bin/sh
set -e

USER_ID=${PUID:-1000}
GROUP_ID=${PGID:-1000}

# Ensure the user and group exist inside Alpine (SSH requires this)
if ! getent group $GROUP_ID >/dev/null; then
    addgroup -g $GROUP_ID tunnelgroup
fi
if ! getent passwd $USER_ID >/dev/null; then
    adduser -D -u $USER_ID -G $(getent group $GROUP_ID | cut -d: -f1) tunneluser
fi

# Get the actual username for the UID
USER_NAME=$(getent passwd $USER_ID | cut -d: -f1)
USER_HOME=$(getent passwd $USER_ID | cut -d: -f6)

echo "Starting Tunnel service for user $USER_NAME (UID: $USER_ID, GID: $GROUP_ID)"

# SSH needs a writable home for known_hosts etc.
mkdir -p $USER_HOME/.ssh
chown -R $USER_ID:$GROUP_ID $USER_HOME

# Execute SSH as the specified user using su-exec
exec su-exec $USER_ID:$GROUP_ID ssh "$@"
