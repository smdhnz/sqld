const fs = require('fs');
const { spawn } = require('child_process');
const http = require('http');
const httpProxy = require('http-proxy');

const CONFIG_PATH = '/etc/sqld/config.json';

if (!fs.existsSync(CONFIG_PATH)) {
    console.error(`Config file not found at ${CONFIG_PATH}`);
    process.exit(1);
}

const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
const proxy = httpProxy.createProxyServer({});

// プロキシエラーを処理してクラッシュを防止
proxy.on('error', (err, req, res) => {
    console.error('Proxy error:', err);
    if (!res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
    }
    res.end('Bad Gateway');
});

let nextPort = 9000;
const dbs = {};
const children = [];

console.log('sqld インスタンスを起動しています...');

for (const [dbName, dbConfig] of Object.entries(config.databases)) {
    const port = nextPort++;
    const dbPath = `/var/lib/sqld/${dbName}`;
    const keyPath = `${dbPath}/auth_public.pem`;
    
    dbs[dbName] = { ...dbConfig, port };
    
    if (!fs.existsSync(dbPath)) {
        fs.mkdirSync(dbPath, { recursive: true });
    }

    const args = [
        '--db-path', dbPath,
        '--http-listen-addr', `127.0.0.1:${port}`,
        '--no-welcome'
    ];

    if (fs.existsSync(keyPath)) {
        args.push('--auth-jwt-key-file', keyPath);
        console.log(`[${dbName}] ポート ${port} で JWT 認証を有効にして起動中`);
    } else {
        console.log(`[${dbName}] ポート ${port} で JWT 認証なしで起動中 (キーが見つかりません: ${keyPath})`);
    }

    const sqld = spawn('/bin/sqld', args);
    children.push({ process: sqld, dbName });
    
    // ログにプレフィックスを付与
    const prefixLog = (data, isError = false) => {
        const stream = isError ? process.stderr : process.stdout;
        const lines = data.toString().split('\n');
        lines.forEach((line, i) => {
            if (i === lines.length - 1 && line === '') return;
            stream.write(`[${dbName}] ${line}\n`);
        });
    };

    sqld.stdout.on('data', (data) => prefixLog(data));
    sqld.stderr.on('data', (data) => prefixLog(data, true));

    sqld.on('exit', (code) => {
        console.log(`[${dbName}] sqld プロセスが終了しました (終了コード: ${code})`);
    });
}

// 子プロセスにシグナルを転送し、終了を待機
const shutdown = async (signal) => {
    console.log(`${signal} を受信しました。子プロセスを終了しています...`);
    
    const exitPromises = children.map(({ process: child, dbName }) => {
        return new Promise((resolve) => {
            child.on('exit', () => {
                console.log(`[${dbName}] クリーンアップ完了`);
                resolve();
            });
            child.kill(signal);
        });
    });

    // 安全のためタイムアウトを設定
    const timeout = new Promise((resolve) => setTimeout(() => {
        console.warn('シャットダウンがタイムアウトしました。強制終了します。');
        resolve();
    }, 10000));

    await Promise.race([Promise.all(exitPromises), timeout]);
    console.log('シャットダウン完了');
    process.exit(0);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (err) => {
    console.error('Uncaught Exception thrown:', err);
    shutdown('SIGINT');
});

const handleRequest = (req, res, isTunnel) => {
    // セキュリティヘッダーを追加
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');

    // パスから DB 名を抽出: /dbName/rest...
    const url = new URL(req.url, `http://${req.headers.host}`);
    const parts = url.pathname.split('/').filter(Boolean);
    
    if (parts.length === 0) {
        res.writeHead(404);
        return res.end('Specify database name in path (e.g., /db1/)');
    }

    const dbName = parts[0];
    const db = dbs[dbName];

    if (!db) {
        res.writeHead(404);
        return res.end(`Database "${dbName}" not found in config.json`);
    }

    if (isTunnel && !db.expose) {
        res.writeHead(403);
        return res.end(`Database "${dbName}" is not exposed via tunnel`);
    }

    // URLを書き換え: /dbName プレフィックスを削除
    req.url = '/' + parts.slice(1).join('/') + url.search;

    proxy.web(req, res, { target: `http://127.0.0.1:${db.port}` });
};

// ポート 8080: ローカルアクセス (全DB) + ヘルスチェック
http.createServer((req, res) => {
    if (req.url === '/health') {
        const alive = children.filter(c => c.process.exitCode === null);
        if (alive.length > 0) {
            res.writeHead(200);
            return res.end('OK');
        } else {
            res.writeHead(503);
            return res.end('No DBs running');
        }
    }
    handleRequest(req, res, false);
}).listen(8080, () => {
    console.log('ルーターがポート 8080 で待機中 (ローカルアクセス + /health)');
});

// ポート 8081: トンネルアクセス (公開対象のDBのみ)
http.createServer((req, res) => handleRequest(req, res, true)).listen(8081, () => {
    console.log('ルーターがポート 8081 で待機中 (トンネルアクセス)');
});
