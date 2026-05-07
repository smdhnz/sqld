#!/bin/sh
set -e

# Use PUID/PGID if provided, otherwise default to 1000
USER_ID=${PUID:-1000}
GROUP_ID=${PGID:-1000}

echo "Starting Router with Bun (UID: $USER_ID, GID: $GROUP_ID)"

# Ensure the user and group exist inside the container (for gosu)
getent group $GROUP_ID >/dev/null || groupadd -g $GROUP_ID bunuser
getent passwd $USER_ID >/dev/null || useradd -u $USER_ID -g $GROUP_ID -m bunuser

# Ensure the database directories have the correct permissions
# Note: We skip config.json which might be mounted as read-only
find /var/lib/sqld -maxdepth 1 -not -name "config.json" -not -path "/var/lib/sqld" -exec chown -R $USER_ID:$GROUP_ID {} +

# Drop privileges and execute the router using Bun
exec gosu $USER_ID:$GROUP_ID bun run index.js
