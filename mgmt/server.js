// Management API for the Exim node.
// The Proxy-Mailer backend calls this (bearer-token protected) to check
// health/queue and to self-serve DKIM provisioning for new domains —
// so operators never have to SSH into the box.
//
// No external deps: DKIM keys are generated with Node's built-in crypto
// and written straight into the shared /etc/exim4/dkim volume that the
// Exim container reads per-message (no restart needed).
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const PORT = Number(process.env.MGMT_PORT || 8443);
const TOKEN = process.env.MGMT_TOKEN || '';
const SELECTOR = process.env.DKIM_SELECTOR || 'proxymail';
const PRIMARY_HOSTNAME = process.env.PRIMARY_HOSTNAME || 'mail.example.com';
const DKIM_DIR = '/etc/exim4/dkim';
// exim runtime user (Debian-exim = uid 100) must be able to read keys.
const EXIM_UID = 100;

const authed = (req) =>
  TOKEN && req.headers.authorization === `Bearer ${TOKEN}`;

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

// Base64 SPKI DER public key — the value that goes in the DKIM DNS TXT.
const publicKeyToDkimP = (publicKeyPem) =>
  crypto.createPublicKey(publicKeyPem)
    .export({ type: 'spki', format: 'der' })
    .toString('base64');

// Provision (or return existing) DKIM material for a domain, plus the
// full set of DNS records the operator needs to add.
const provisionDkim = (domain) => {
  if (!/^[a-z0-9.-]+\.[a-z]{2,}$/i.test(domain)) {
    throw Object.assign(new Error('invalid domain'), { statusCode: 400 });
  }
  const privPath = path.join(DKIM_DIR, `${domain}.private`);

  let p;
  if (fs.existsSync(privPath)) {
    // Derive the public value from the existing key (idempotent).
    const priv = fs.readFileSync(privPath, 'utf8');
    p = publicKeyToDkimP(crypto.createPublicKey(priv).export({ type: 'spki', format: 'pem' }));
  } else {
    const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs1', format: 'pem' } // Exim reads PKCS#1 PEM
    });
    fs.mkdirSync(DKIM_DIR, { recursive: true });
    fs.writeFileSync(privPath, privateKey, { mode: 0o640 });
    try { fs.chownSync(privPath, EXIM_UID, EXIM_UID); } catch (_) { /* best effort */ }
    p = publicKeyToDkimP(publicKey);
  }

  return {
    domain,
    selector: SELECTOR,
    records: {
      dkim: {
        type: 'TXT',
        host: `${SELECTOR}._domainkey.${domain}`,
        value: `v=DKIM1; k=rsa; p=${p}`
      },
      spf: {
        type: 'TXT',
        host: domain,
        value: 'v=spf1 a mx ip4:REPLACE_WITH_VPS_IP ~all'
      },
      dmarc: {
        type: 'TXT',
        host: `_dmarc.${domain}`,
        value: `v=DMARC1; p=none; rua=mailto:dmarc@${domain}; fo=1`
      },
      ptr: {
        note: `Set reverse DNS for this server's IP to ${PRIMARY_HOSTNAME} at your VPS provider.`
      }
    }
  };
};

const readJsonBody = (req) =>
  new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => { data += c; if (data.length > 1e4) req.destroy(); });
    req.on('end', () => { try { resolve(JSON.parse(data || '{}')); } catch { resolve({}); } });
  });

const server = http.createServer(async (req, res) => {
  if (req.url === '/health') {
    return send(res, 200, { status: 'ok', mode: process.env.DELIVERY_MODE });
  }
  if (!authed(req)) return send(res, 401, { error: 'unauthorized' });

  if (req.url === '/queue') {
    return send(res, 200, { depth: await queueDepth() });
  }

  // POST /dkim  { domain }  -> generates key + returns DNS records
  if (req.method === 'POST' && req.url === '/dkim') {
    try {
      const { domain } = await readJsonBody(req);
      if (!domain) return send(res, 400, { error: 'domain required' });
      return send(res, 200, provisionDkim(String(domain).toLowerCase().trim()));
    } catch (e) {
      return send(res, e.statusCode || 500, { error: e.message });
    }
  }

  return send(res, 404, { error: 'not found' });
});

server.listen(PORT, () => console.log(`[mgmt] listening on :${PORT}`));
