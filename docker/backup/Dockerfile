FROM alpine:latest

# 必要なパッケージのインストール (su-exec削除)
RUN apk add --no-cache sqlite tzdata jq

# 非ルートユーザーの作成
RUN addgroup -g 1000 backupuser && \
    adduser -D -u 1000 -G backupuser backupuser

# ディレクトリの準備と権限設定
RUN mkdir -p /backups /var/lib/sqld /etc/sqld && \
    chown -R backupuser:backupuser /backups /var/lib/sqld /etc/sqld

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# デフォルトでは作成したユーザーで実行
USER backupuser

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
