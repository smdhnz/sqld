# --- Bun Binary Provider ---
FROM oven/bun:1.1 AS bun-provider

# --- Final Stage ---
FROM ghcr.io/tursodatabase/libsql-server:latest

# 非ルートユーザーの作成 (デフォルトUID 1000)
RUN groupadd -g 1000 sqlduser && \
    useradd -u 1000 -g sqlduser -m sqlduser

# Bunバイナリをコピー
COPY --from=bun-provider /usr/local/bin/bun /usr/local/bin/bun

WORKDIR /app
RUN chown sqlduser:sqlduser /app

USER sqlduser

# 依存関係の定義ファイルをコピーしてインストール
COPY --chown=sqlduser:sqlduser package.json ./
RUN bun install --production

# ソースコードをコピー
COPY --chown=sqlduser:sqlduser index.js .

# データの保存ディレクトリを準備 (実行時にマウントされるが、ベースとして作成)
# 注意: マウントされたボリュームの権限はホスト側に依存するため、ホスト側でのchownが必要
# ここではベースイメージ内のディレクトリ権限を設定
USER root
RUN mkdir -p /var/lib/sqld && chown sqlduser:sqlduser /var/lib/sqld
USER sqlduser

EXPOSE 8080 8081

# 直接アプリケーションを実行 (ベースイメージのENTRYPOINTを上書き)
ENTRYPOINT ["bun", "run", "index.js"]
