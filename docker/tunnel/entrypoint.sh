#!/bin/sh
set -e

echo "Starting Tunnel service..."

# SSHコマンドを実行
# compose.yml の command 引数が "$@" として渡される
exec ssh "$@"
