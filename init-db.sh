#!/bin/bash
set -e

DB_NAME=$1

if [ -z "$DB_NAME" ]; then
	echo "使い方: ./init-db.sh <database_name>"
	exit 1
fi

# 1. ディレクトリの作成
mkdir -p data backups

# 2. .envがあれば読み込む
if [ -f .env ]; then
	export $(grep -v '^#' .env | xargs)
fi

# 3. 指定されたDB用のキーを生成
DB_DIR="data/${DB_NAME}"
mkdir -p "$DB_DIR"

touch "${DB_DIR}/auth_private.pem"
chmod 600 "${DB_DIR}/auth_private.pem"
openssl genpkey -algorithm ed25519 -out "${DB_DIR}/auth_private.pem"
openssl pkey -in "${DB_DIR}/auth_private.pem" -pubout -out "${DB_DIR}/auth_public.pem"

# 4. JWTトークンの生成
HEADER=$(echo -n '{"alg":"EdDSA","typ":"JWT"}' | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')
PAYLOAD=$(echo -n '{}' | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')

JWT_INPUT_TEMP=".jwt_input.$$"
echo -n "${HEADER}.${PAYLOAD}" >"$JWT_INPUT_TEMP"
SIGNATURE=$(openssl pkeyutl -sign -inkey "${DB_DIR}/auth_private.pem" -rawin -in "$JWT_INPUT_TEMP" | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')
rm "$JWT_INPUT_TEMP"

TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"
URL="https://${SUBDOMAIN:-your-subdomain}.tcpexposer.com/${DB_NAME}/"

# 5. config.json の初期化または更新
CONFIG_FILE="config.json"
if [ ! -f "$CONFIG_FILE" ]; then
	jq -n --arg db "$DB_NAME" --arg token "$TOKEN" --arg url "$URL" \
		'{"databases": {($db): {"expose": true, "token": $token, "url": $url}}}' >"$CONFIG_FILE"
else
	# 既存のオブジェクトに新しい情報を追加（exposeは維持、tokenとurlは更新）
	TMP_FILE="config.json.$$.tmp"
	jq --arg db "$DB_NAME" --arg token "$TOKEN" --arg url "$URL" \
		'.databases[($db)] |= (. // {"expose": true}) | .databases[($db)].token = $token | .databases[($db)].url = $url' \
		"$CONFIG_FILE" >"$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
fi

echo "db_name: \"${DB_NAME}\""
echo "token  : \"${TOKEN}\""
echo "url    : \"${URL}\""
