#!/bin/sh
set -e

echo "バックアップサービスを起動しています..."

CONFIG_FILE="/etc/sqld/config.json"
BACKUP_DIR="/backups"

while true; do
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found at $CONFIG_FILE"
  else
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    
    # 全データベース名を取得
    DB_NAMES=$(jq -r ".databases | keys[]" "$CONFIG_FILE")
    
    for DB_NAME in $DB_NAMES; do
      DB_FILE="/var/lib/sqld/${DB_NAME}/dbs/default/data"
      TARGET_DIR="${BACKUP_DIR}/${DB_NAME}"
      mkdir -p "$TARGET_DIR"
      BACKUP_FILE="${TARGET_DIR}/backup_${TIMESTAMP}.db"
      
      echo "${DB_NAME} のバックアップを開始します (${TIMESTAMP})"
      if [ -f "$DB_FILE" ]; then
          # sqlite3 の VACUUM INTO コマンドを実行
          sqlite3 "$DB_FILE" "VACUUM INTO '$BACKUP_FILE'"
          echo "バックアップが完了しました: $BACKUP_FILE"
          
          # 古いバックアップの削除
          find "${TARGET_DIR}" -name "backup_*.db" -mtime +"${BACKUP_RETENTION_DAYS:-7}" -exec rm {} \;
      else
          echo "Warning: Database file not found at $DB_FILE (skipping)"
      fi
    done
    echo "バックアップサイクルが完了しました ($(date))"
  fi

  echo "${BACKUP_INTERVAL_SECONDS:-86400} 秒間待機します..."
  sleep "${BACKUP_INTERVAL_SECONDS:-86400}"
done
