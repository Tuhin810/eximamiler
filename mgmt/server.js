// Tiny management API for the Exim node.
// Repo 1 (Proxy-Mailer backend) polls this over HTTPS/HTTP for health
// and queue depth. Bearer-token protected. No external deps.
const http = require('http');
const { execFile } = require('child_process');

const PORT = Number(process.env.MGMT_PORT || 8443);
const TOKEN = process.env.MGMT_TOKEN || '';

const authed = (req) =>
  TOKEN && req.headers.authorization === `Bearer ${TOKEN}`;

// Count messages sitting in the Exim spool (queue depth) via `exim -bpc`.
const queueDepth = () =>
  new Promise((resolve) => {
    execFile('exim', ['-bpc'], (err, stdout) => {
      if (err) return resolve(null);
      resolve(Number.parseInt(stdout.trim(), 10) || 0);
    });
  });

const send = (res, code, body) => {
  res.writeHead(code, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
};

const server = http.createServer(async (req, res) => {
  if (req.url === '/health') {
    return send(res, 200, { status: 'ok', mode: process.env.DELIVERY_MODE });
  }
  if (!authed(req)) return send(res, 401, { error: 'unauthorized' });

  if (req.url === '/queue') {
    return send(res, 200, { depth: await queueDepth() });
  }
  return send(res, 404, { error: 'not found' });
});

server.listen(PORT, () => console.log(`[mgmt] listening on :${PORT}`));
