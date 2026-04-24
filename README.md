# 自宅 SQLite エッジサーバー (libSQL/sqld)

Vercel 等の外部サービスから、自宅サーバーの SQLite (libSQL) を利用するための構成一式です。
libSQL 互換のクライアントであれば利用可能ですが、ここでは例として Drizzle ORM での設定方法を記載します。
セキュリティ、バックアップ、トンネル（tcpexposer）を統合しています。

## 1. 事前準備

```bash
# 必要なディレクトリを作成
mkdir -p data backups
```

## 2. セキュリティ設定 (JWT 認証) ※必須

本構成ではセキュリティのため、**トークン認証が必須**となっています。以下のスクリプトを実行して、鍵ペアの作成と認証用トークンの発行を一度に行います。

```bash
# 実行権限を付与して実行
chmod +x setup-auth.sh
./setup-auth.sh
```

実行後、表示されたトークンを `.env` の `DATABASE_AUTH_TOKEN` に設定してください。
公開鍵は `data/auth_public.pem` として保存され、これがないとサーバーは起動しません。

## 3. 設定 (.env)

`.env.example` をコピーして、環境に合わせた設定を行います。

```bash
cp .env.example .env
```

`.env` 内の各項目を設定してください：

- `PUID`, `PGID`: ホストのユーザーIDとグループID（`id -u`, `id -g` で確認可能）。
- `SSH_SECRET_KEY_FILENAME`: `~/.ssh` 内の秘密鍵ファイル名（例: `id_ed25519`）。
- `SUBDOMAIN`: tcpexposer で使用するサブドメイン名。
- `TCPEXPOSER_USERNAME`: tcpexposer のユーザー名。

## 4. 起動

```bash
# イメージのビルド
docker compose build --no-cache

# 起動
docker compose up -d
```

## 5. クライアントからの接続例 (Drizzle ORM)

環境変数に以下を設定します（`${DB_SUBDOMAIN}` は `.env` ファイルで設定した実際の値に置き換えてください）：

- `DATABASE_URL`: `https://${DB_SUBDOMAIN}.tcpexposer.com`
- `DATABASE_AUTH_TOKEN`: (手順2で生成したトークン)

```typescript
// db.ts (Example)
import { drizzle } from "drizzle-orm/libsql";
import { createClient } from "@libsql/client";

const client = createClient({
  url: process.env.DATABASE_URL!,
  authToken: process.env.DATABASE_AUTH_TOKEN,
});
export const db = drizzle(client);
```

## 6. 運用・バックアップ

- **自動バックアップ**: 指定した間隔（デフォルト 24時間）ごとに `./backups` へ保存されます（`.env` の `BACKUP_INTERVAL_SECONDS` で設定）。
- **手動バックアップ**: `docker exec sqld-backup /usr/local/bin/backup.sh`
- **リストア**:
  1. `docker compose stop sqld`
  2. `cp backups/backup_XXX.db data/dbs/default/data`
  3. `docker compose start sqld`
- **GUI操作**: ローカル PC から `npx drizzle-kit studio` を実行したり、[libSQL Studio](https://libsqlstudio.com/) を利用したりするのが最適です。

## 技術仕様

- **汎用性**: libSQL 互換のあらゆるクライアント（Python, Rust, Go, Node.js 等）から接続可能。
- **Immutable & Minimal**: バックアップスクリプトはすべて Docker イメージ内に埋め込まれており、ホスト側を汚しません。
- **設定の集約**: ポート、サブドメイン、バックアップスケジュール、認証設定はすべて `.env` で管理します。
