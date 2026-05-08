#!/bin/bash
set -e

DB_NAME=$1

if [ -z "$DB_NAME" ]; then
	echo "使い方: ./init-db.sh <database_name>"
	exit 1
fi

# 1. ディレクトリの作成
echo "1. ディレクトリを作成しています..."
mkdir -p data backups
echo "'data' と 'backups' ディレクトリの準備が完了しました。"

# 2. config.json の初期化または更新
CONFIG_FILE="config.json"
if [ ! -f "$CONFIG_FILE" ]; then
	echo "2. config.json を初期化しています..."
	jq -n --arg db "$DB_NAME" '{"databases": {($db): {"expose": true}}}' >"$CONFIG_FILE"
	echo "$CONFIG_FILE を $DB_NAME で初期化しました (expose: true)。"
else
	echo "2. config.json を ${DB_NAME} で更新しています..."
	# 既存のオブジェクトに新しいデータベースを追加
	TMP_FILE="config.json.$$.tmp"
	jq --arg db "$DB_NAME" '.databases[($db)] = {"expose": true}' "$CONFIG_FILE" >"$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
	echo "$CONFIG_FILE に $DB_NAME を追加しました。"
fi

# 3. 指定されたDB用のキーを生成
DB_DIR="data/${DB_NAME}"
mkdir -p "$DB_DIR"

echo "3. ${DB_NAME} 用の Ed25519 キーペアを生成しています..."
touch "${DB_DIR}/auth_private.pem"
chmod 600 "${DB_DIR}/auth_private.pem"
openssl genpkey -algorithm ed25519 -out "${DB_DIR}/auth_private.pem"
openssl pkey -in "${DB_DIR}/auth_private.pem" -pubout -out "${DB_DIR}/auth_public.pem"
echo "${DB_DIR} にキーが正常に生成されました。"

# 4. JWTトークンの生成
echo "4. ${DB_NAME} 用の JWTトークン (EdDSA) を生成しています..."
HEADER=$(echo -n '{"alg":"EdDSA","typ":"JWT"}' | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')
PAYLOAD=$(echo -n '{}' | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')

JWT_INPUT_TEMP=".jwt_input.$$"
echo -n "${HEADER}.${PAYLOAD}" >"$JWT_INPUT_TEMP"
SIGNATURE=$(openssl pkeyutl -sign -inkey "${DB_DIR}/auth_private.pem" -rawin -in "$JWT_INPUT_TEMP" | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')
rm "$JWT_INPUT_TEMP"

TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"

echo "--------------------------------------------------"
echo "データベースのセットアップが完了しました: ${DB_NAME}"
echo ""
echo "データベース認証トークン (DATABASE_AUTH_TOKEN):"
echo "${TOKEN}"
echo ""
echo "接続URL: https://${SUBDOMAIN:-your-subdomain}.tcpexposer.com/${DB_NAME}/"
echo "--------------------------------------------------"
