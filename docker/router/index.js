const fs = require('fs');
const { spawn } = require('child_process');
const http = require('http');

const CONFIG_PATH = '/etc/sqld/config.json';

if (!fs.existsSync(CONFIG_PATH)) {
    console.error(`Config file not found at ${CONFIG_PATH}`);
    process.exit(1);
}

const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

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

const shutdown = async (signal) => {
    console.log(`${signal} を受信しました。子プロセスを終了しています...`);
    for (const { process: child, dbName } of children) {
        child.kill(signal);
    }
    process.exit(0);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

const handleRequest = (req, res, isTunnel) => {
    // パスから DB 名を抽出: /dbName/rest...
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
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

    // セキュリティヘッダー
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');

    // バックエンドへのパスを構築
    const backendPath = '/' + parts.slice(1).join('/') + url.search;

    // リクエストボディをバッファリング
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
        const payload = Buffer.concat(chunks);
        
        const options = {
            hostname: '127.0.0.1',
            port: db.port,
            path: backendPath,
            method: req.method,
            headers: { ...req.headers }
        };

        // チャンク転送を固定長に書き換える（Vercel対応の核心）
        if (payload.length > 0) {
            options.headers['content-length'] = payload.length;
            delete options.headers['transfer-encoding'];
        }
        
        // Host ヘッダーをバックエンドに合わせる
        options.headers['host'] = `127.0.0.1:${db.port}`;
        
        // Hop-by-hop ヘッダーを削除（安定性のため）
        delete options.headers['connection'];
        delete options.headers['keep-alive'];

        const proxyReq = http.request(options, (proxyRes) => {
            res.writeHead(proxyRes.statusCode, proxyRes.headers);
            proxyRes.pipe(res);
        });

        proxyReq.on('error', (err) => {
            console.error(`[${dbName}] Proxy error:`, err);
            if (!res.headersSent) res.writeHead(502);
            res.end('Bad Gateway');
        });

        if (payload.length > 0) {
            proxyReq.write(payload);
        }
        proxyReq.end();
    });
};

// ポート 8080: ローカルアクセス (全DB) + ヘルスチェック
http.createServer((req, res) => {
    if (req.url === '/health') {
        const alive = children.filter(c => c.process.exitCode === null);
        res.writeHead(alive.length > 0 ? 200 : 503);
        return res.end(alive.length > 0 ? 'OK' : 'No DBs running');
    }
    handleRequest(req, res, false);
}).listen(8080, () => {
    console.log('ルーターがポート 8080 で待機中 (ローカルアクセス)');
});

// ポート 8081: トンネルアクセス
http.createServer((req, res) => handleRequest(req, res, true)).listen(8081, () => {
    console.log('ルーターがポート 8081 で待機中 (トンネルアクセス)');
});

