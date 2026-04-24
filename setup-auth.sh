#!/bin/bash
set -e

# データディレクトリの作成
mkdir -p data

echo "1. Generating Ed25519 key pair..."
if [ -f "data/auth_private.pem" ]; then
    read -p "data/auth_private.pem already exists. Overwrite? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping key generation."
    else
        openssl genpkey -algorithm ed25519 -out data/auth_private.pem
        openssl pkey -in data/auth_private.pem -pubout -out data/auth_public.pem
        echo "Keys generated successfully."
    fi
else
    openssl genpkey -algorithm ed25519 -out data/auth_private.pem
    openssl pkey -in data/auth_private.pem -pubout -out data/auth_public.pem
    echo "Keys generated successfully."
fi

echo "2. Generating JWT token (EdDSA)..."
# ヘッダーとペイロードを定義 (Base64URL エンコード)
# Ed25519 の場合、アルゴリズムは "EdDSA"
HEADER=$(echo -n '{"alg":"EdDSA","typ":"JWT"}' | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')
PAYLOAD=$(echo -n '{}' | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')

# Ed25519 で署名
echo -n "${HEADER}.${PAYLOAD}" > .jwt_input
SIGNATURE=$(openssl pkeyutl -sign -inkey data/auth_private.pem -rawin -in .jwt_input | openssl base64 -e | tr -d '\n=' | tr '+/' '-_')
rm .jwt_input

TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"

echo "--------------------------------------------------"
echo "Your DATABASE_AUTH_TOKEN:"
echo ""
echo "${TOKEN}"
echo ""
echo "--------------------------------------------------"
echo "Please copy this token to your .env file."
