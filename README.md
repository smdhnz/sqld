# sqld Multi-Database Edge Server (Production Ready)

本プロジェクトは、[libSQL (sqld)](https://github.com/tursodatabase/libsql) を使用した、本格的な運用向けのマルチデータベース・エッジサーバー構成です。フロントに **Bun** を採用した高性能な非同期ルーターを配し、単一のポートで複数の SQLite データベースを動的にルーティング・管理します。

## 🌟 主な特徴

- **マルチデータベース対応**: `config.json` で定義するだけで、複数の独立したデータベースを即座に追加・運用可能。
- **高性能 Bun プロキシ**: Node.js 22 互換の最新ランタイム **Bun** を採用。非ブロッキング I/O により、低メモリかつ高スループットなルーティングを実現。
- **セキュアな設計**: 全コンテナで `su-exec` / `gosu` を使用し non-root 実行。JWT秘密鍵のパーミッション制限（600）、SSH鍵の最小限のマウント、セキュリティヘッダーの付与、およびリソース制限（CPU/メモリ）を標準装備。
- **高速な終了**: 終了シグナル（SIGTERM）を子プロセスへ即座に転送するルーター設計により、`docker compose down` 時の待機時間を解消。
- **堅牢なバックアップ**: 起動時に全 DB の即時バックアップを実行し、その後設定された間隔で世代管理バックアップを自動継続。
- **自動ブートストラップ**: `init-db.sh` により、フォルダ作成、設定初期化（追記対応）、Ed25519 鍵ペア生成が 1 コマンドで完結。

## 🏗 ディレクトリ構造

```text
.
├── config.json         # データベース定義（Git管理対象外。コンテナ内では /etc/sqld/config.json にマウント）
├── compose.yml         # サービス定義（リソース制限・セキュリティ設定済み）
├── init-db.sh          # 初期セットアップ・認証キー生成・設定更新スクリプト
├── data/               # データベース実体（Git管理対象外・DBごとにフォルダ分割）
├── backups/            # バックアップファイル（Git管理対象外）
└── docker/             # サービスごとのDockerfile
    ├── router/         # Bunルーター（dbsサービス）
    ├── backup/         # バックアップサービス
    └── tunnel/         # トンネルサービス（tcpexposer）
```

## 🚀 クイックスタート

### 1. 事前準備

`.env.example` をコピーして `.env` を作成します（トンネルを使用しない場合はデフォルトのままでも動作します）。

```bash
cp .env.example .env
```

### 2. 初期セットアップ (自動ブートストラップ)

以下のコマンドを実行して、データベース（例: `db1`）を作成します。

```bash
chmod +x init-db.sh
./init-db.sh db1
```

この操作により、以下の処理が自動的に行われます：
1.  `data` および `backups` フォルダの作成。
2.  **`config.json` の自動生成または追記**（すでに存在する場合は新しいDB設定をマージ）。
3.  指定したデータベース専用の認証キー（Ed25519）の生成（chmod 600）と JWT の発行。

### 3. 設定の確認・カスタマイズ

生成された `config.json` を開き、データベースの定義を確認します。

```json
{
  "databases": {
    "db1": {
      "expose": true
    }
  }
}
```
- `expose`: `true` に設定すると、トンネル経由で外部からアクセス可能になります。

### 4. 起動

```bash
docker compose up -d --build
```

## ⚙️ 運用・管理

### データベースの管理

- **追加**: `./init-db.sh <新DB名>` を実行し、`docker compose restart dbs` で反映。`config.json` は自動的に更新されます。
- **公開制御**: `config.json` の `expose: true/false` でトンネル経由の外部露出を個別に制御。
- **リセット**: 特定の DB を初期化する場合、`docker compose stop dbs` してから `data/<DB名>/dbs` フォルダを削除し、再起動します。

### リストア（復元）の手順

1.  安全のため、対象のコンテナを停止します： `docker compose stop dbs`
2.  バックアップファイルをデータディレクトリに上書きコピーします：
    ```bash
    cp backups/db1/backup_YYYYMMDD_HHMMSS.db data/db1/dbs/default/data
    ```
3.  パーミッションが正しい（PUID/PGIDと一致している）ことを確認します。
4.  コンテナを再起動します： `docker compose start dbs`

### 接続URLと認証 (SDK/Drizzle 等)

Drizzle ORM や libSQL SDK から接続する場合は、以下の **Base URL** を使用します。

- **Local Access**: `http://localhost:8080/{db_name}/`
- **Tunnel Access**: `https://{your-subdomain}.tcpexposer.com/{db_name}/`
- **Auth Token**: `./init-db.sh` で発行されたトークンを使用。

### 動作確認 (curl)

直接 API を叩く場合は、エンドポイントまで指定します。

```bash
curl -s -X POST http://localhost:8080/db1/v1/execute \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"stmt": {"sql": "SELECT 1;"}}' | jq .
```

## 📝 技術スタック

- **Core**: libSQL (sqld)
- **Runtime**: Bun 1.1+ (Router/Manager)
- **Security**: Ed25519 JWT Auth, Docker native `user` mapping, Resource Limits
- **Size**: Optimized multi-stage build & .dockerignore
ulti-stage build (~370MB)
