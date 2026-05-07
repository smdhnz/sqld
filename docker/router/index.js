const fs = require('fs');
const { spawn } = require('child_process');
const http = require('http');
const httpProxy = require('http-proxy');

const CONFIG_PATH = '/var/lib/sqld/config.json';

if (!fs.existsSync(CONFIG_PATH)) {
    console.error(`Config file not found at ${CONFIG_PATH}`);
    process.exit(1);
}

const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
const proxy = httpProxy.createProxyServer({});

// Handle proxy errors to prevent crash
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

console.log('Starting sqld instances...');

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
        '--http-listen-addr', `127.0.0.1:${port}`
    ];

    if (fs.existsSync(keyPath)) {
        args.push('--auth-jwt-key-file', keyPath);
        console.log(`[${dbName}] Starting on port ${port} with JWT auth`);
    } else {
        console.log(`[${dbName}] Starting on port ${port} WITHOUT JWT auth (key not found at ${keyPath})`);
    }

    const sqld = spawn('/bin/sqld', args, { stdio: 'inherit' });
    children.push(sqld);
    
    sqld.on('exit', (code) => {
        console.error(`[${dbName}] sqld process exited with code ${code}`);
    });
}

// Forward signals to child processes for fast shutdown
const shutdown = (signal) => {
    console.log(`Received ${signal}, shutting down children...`);
    children.forEach(child => child.kill(signal));
    process.exit(0);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

const handleRequest = (req, res, isTunnel) => {
    // Add security headers
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');

    // Extract DB name from path: /dbName/rest...
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

    // Rewrite URL: strip the /dbName prefix
    req.url = '/' + parts.slice(1).join('/') + url.search;

    proxy.web(req, res, { target: `http://127.0.0.1:${db.port}` });
};

// Port 8080: Local access (all DBs)
http.createServer((req, res) => handleRequest(req, res, false)).listen(8080, () => {
    console.log('Router listening on port 8080 (Local Access)');
});

// Port 8081: Tunnel access (exposed DBs only)
http.createServer((req, res) => handleRequest(req, res, true)).listen(8081, () => {
    console.log('Router listening on port 8081 (Tunnel Access)');
});
