# exim-mailer-vps

Self-hosted **Exim** sending node for Proxy-Mailer. Runs on a dedicated
VPS, separate from the main app. The Proxy-Mailer backend (Repo 1) talks
to it over **SMTP-AUTH on port 587** and nothing else.

Config-switchable between two delivery modes:

| Mode | What Exim does | Use when |
|------|----------------|----------|
| `submission` | Forwards every message to an upstream **smarthost** (Brevo/SES/etc.), DKIM-signing on the way out | You want your own signing + queue but still lean on a relay's IP reputation |
| `direct-mx`  | Looks up the recipient **MX** and delivers directly, DKIM-signed from your own IP | You control the sending IP and DNS (SPF/DKIM/PTR) and want full independence |

Switch by changing `DELIVERY_MODE` in `.env` and restarting — no app redeploy.

## Layout
```
exim-vps/
├── conf/exim4.conf.template   # rendered at boot via envsubst
├── scripts/entrypoint.sh      # render config, gen TLS+DKIM, run exim
├── scripts/gen-dkim.sh        # DKIM keypair + printable DNS record
├── mgmt/                      # optional health/queue API (:8443)
├── docs/DNS.md                # SPF / DKIM / DMARC / PTR records
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

## Quick start
```sh
cp .env.example .env      # then edit PRIMARY_HOSTNAME, APP_SMTP_*, DKIM_DOMAINS
docker compose up -d --build
docker compose logs -f exim
```
On first boot it self-signs a TLS cert (dev), generates a DKIM key per
domain, and provisions the app submission account. Add the printed DKIM
record + the records in [docs/DNS.md](docs/DNS.md) to your DNS.

For production TLS, mount real certs into `./data/tls/{fullchain,privkey}.pem`.

## How Repo 1 connects
The Proxy-Mailer backend stores an `EximConfig` with:
`host = mail.yourdomain.com`, `port = 587`, `authUser = APP_SMTP_USER`,
`authPass = APP_SMTP_PASS`. It submits mail via nodemailer (optionally
through a SOCKS proxy). Repo 1 never needs to know the delivery mode.

## Management API (optional)
```
GET /health          -> { status, mode }              (public)
GET /queue           -> { depth }   Bearer MGMT_TOKEN  (queue depth)
```

## Split into its own git repo
This lives under the main repo for now. To break it out:
```sh
cd exim-vps && git init && git add . && git commit -m "init exim node"
git remote add origin <your-new-remote> && git push -u origin main
```
