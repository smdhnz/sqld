#!/bin/bash
set -e

DB_NAME=$1

if [ -z "$DB_NAME" ]; then
	echo "Usage: ./setup-auth.sh <database_name>"
	exit 1
fi

# 1. Bootstrap directories
echo "1. Bootstrapping directories..."
mkdir -p data backups
echo "Directories 'data' and 'backups' are ready."

# 2. Initialize config.json if not exists
CONFIG_FILE="config.json"
if [ ! -f "$CONFIG_FILE" ]; then
	echo "2. Initializing config.json..."
	jq -n --arg db "$DB_NAME" '{"databases": {($db): {"expose": true}}}' >"$CONFIG_FILE"
	echo "Initialized $CONFIG_FILE with $DB_NAME (exposed: true)."
else
	echo "2. config.json already exists. Skipping initialization."
fi

# 3. Generate keys for the specific DB
DB_DIR="data/${DB_NAME}"
mkdir -p "$DB_DIR"

echo "3. Generating Ed25519 key pair for ${DB_NAME}..."
touch "${DB_DIR}/auth_private.pem"
chmod 600 "${DB_DIR}/auth_private.pem"
openssl genpkey -algorithm ed25519 -out "${DB_DIR}/auth_private.pem"
openssl pkey -in "${DB_DIR}/auth_private.pem" -pubout -out "${DB_DIR}/auth_public.pem"
echo "Keys generated successfully in ${DB_DIR}."

# 4. Generate JWT token
echo "4. Generating JWT token (EdDSA) for ${DB_NAME}..."
HEADER=$(echo -n '{"alg":"EdDSA","typ":"JWT"}' | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')
PAYLOAD=$(echo -n '{}' | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')

JWT_INPUT_TEMP=".jwt_input.$$"
echo -n "${HEADER}.${PAYLOAD}" >"$JWT_INPUT_TEMP"
SIGNATURE=$(openssl pkeyutl -sign -inkey "${DB_DIR}/auth_private.pem" -rawin -in "$JWT_INPUT_TEMP" | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')
rm "$JWT_INPUT_TEMP"

TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"

echo "--------------------------------------------------"
echo "SETUP COMPLETE FOR DATABASE: ${DB_NAME}"
echo ""
echo "DATABASE_AUTH_TOKEN:"
echo "${TOKEN}"
echo ""
echo "Connection URL: https://${SUBDOMAIN:-your-subdomain}.tcpexposer.com/${DB_NAME}/"
echo "--------------------------------------------------"
