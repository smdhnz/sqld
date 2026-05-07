#!/bin/sh
set -e

USER_ID=${PUID:-1000}
GROUP_ID=${PGID:-1000}

# 権限の修正
mkdir -p /backups
chown -R $USER_ID:$GROUP_ID /backups

echo "Starting Backup service (UID: $USER_ID, GID: $GROUP_ID)"

# 実際のバックアップ処理を行うループ
# su-exec を使って一般ユーザーとして実行
exec su-exec $USER_ID:$GROUP_ID sh -c '
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
        
        echo "Starting backup for ${DB_NAME} at $(date)"
        if [ -f "$DB_FILE" ]; then
            # sqlite3 の VACUUM INTO コマンドを実行 (シングルクォートを使用)
            sqlite3 "$DB_FILE" "VACUUM INTO '\''$BACKUP_FILE'\''"
            echo "Backup completed: $BACKUP_FILE"
            
            # 古いバックアップの削除
            find "${TARGET_DIR}" -name "backup_*.db" -mtime +"${BACKUP_RETENTION_DAYS:-7}" -exec rm {} \;
        else
            echo "Warning: Database file not found at $DB_FILE (skipping)"
        fi
      done
      echo "Backup cycle completed at $(date)"
    fi

    echo "Sleeping for ${BACKUP_INTERVAL_SECONDS:-86400} seconds..."
    sleep "${BACKUP_INTERVAL_SECONDS:-86400}"
  done
'
