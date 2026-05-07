# --- Bun Binary Provider ---
FROM oven/bun:1.1 AS bun-provider

# --- Final Stage ---
FROM ghcr.io/tursodatabase/libsql-server:latest

USER root

# 実行に必要な最小限のパッケージ (gosu) のみインストール
RUN apt-get update && \
    apt-get install -y gosu && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Bunバイナリをコピー
COPY --from=bun-provider /usr/local/bin/bun /usr/local/bin/bun

WORKDIR /app

# 依存関係のインストール (Bunは高速かつ軽量)
# http-proxy を使用しつつ、Bunのランタイムで実行
RUN bun add http-proxy

# ソースコードとエントリポイントをコピー
COPY index.js .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

EXPOSE 8080 8081

# エントリポイント経由で実行
ENTRYPOINT ["./entrypoint.sh"]
