FROM alpine:latest

ARG PUID=1000
ARG PGID=1000

RUN apk add --no-cache sqlite tzdata

# Create a group and user with the specified IDs
RUN addgroup -g ${PGID} backup && \
    adduser -u ${PUID} -G backup -D backup

# SSHやその他のツールが書き込み可能なHOMEを必要とする場合があるため設定
RUN mkdir -p /home/backup && chown backup:backup /home/backup
ENV HOME=/home/backup

# バックアップスクリプトをイメージ内に作成
RUN printf '#!/bin/sh\n\
DB_FILE="/var/lib/sqld/dbs/default/data"\n\
BACKUP_DIR="/backups"\n\
\n\
while true; do\n\
  echo "Sleeping for ${BACKUP_INTERVAL_SECONDS:-86400} seconds..."\n\
  sleep "${BACKUP_INTERVAL_SECONDS:-86400}"\n\
  \n\
  TIMESTAMP=$(date +"%%Y%%m%%d_%%H%%M%%S")\n\
  BACKUP_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.db"\n\
  mkdir -p "${BACKUP_DIR}"\n\
  \n\
  echo "Starting backup at $(date)"\n\
  if [ -f "$DB_FILE" ]; then\n\
      sqlite3 "$DB_FILE" ".backup '"'$BACKUP_FILE'"'"\n\
      echo "Backup completed: $BACKUP_FILE"\n\
      find "${BACKUP_DIR}" -name "backup_*.db" -mtime +"${BACKUP_RETENTION_DAYS:-7}" -exec rm {} \\;\n\
      echo "Cleanup completed."\n\
  else\n\
      echo "Error: Database file not found at $DB_FILE"\n\
  fi\n\
done\n' > /usr/local/bin/backup.sh && \
    chmod +x /usr/local/bin/backup.sh

USER backup

ENTRYPOINT ["/usr/local/bin/backup.sh"]
