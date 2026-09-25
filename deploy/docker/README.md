<div align="center">

# EstiMate · Docker Compose

**Self-hosted, single-command deploy of the EstiMate estimation workspace.**

App + PostgreSQL 17, one `docker compose up`, migrations run themselves.

![Docker](https://img.shields.io/badge/Docker-Compose_v2-2496ED?logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-4169E1?logo=postgresql&logoColor=white)
![Image](https://img.shields.io/badge/image-ghcr.io%2Fdacdigital%2Festimate-black?logo=github)

[Quickstart](#quickstart) · [Configuration](#configuration) · [Upgrade](#upgrade) · [Backup](#backup--restore) · [Reverse proxy](#reverse-proxy) · [Troubleshooting](#troubleshooting)

</div>

---

## Quickstart

```bash
git clone https://github.com/DACdigital/Estimate.git
cd Estimate/deploy/docker

cp .env.example .env
echo "SECRET_KEY_BASE=$(make -s secret)" >> .env
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)" >> .env
# then edit .env and set PHX_HOST (default: localhost)

docker compose up -d
```

Open **http://localhost:4000**, register the first account — that user becomes the owner of a fresh organization and can invite everyone else.

The application container automatically runs any pending database migrations on start, so `docker compose up -d` is also how you upgrade.

## Prerequisites

- **Docker Engine 24+** with the Compose v2 plugin (`docker compose`, not the deprecated `docker-compose`)
- **~2 GB RAM** free (Postgres + BEAM VM)
- Ports **4000/tcp** free on the host (or set `APP_PORT` to another)
- `openssl` and `make` on the host — used only for one-shot secret generation

## Configuration

Copy `.env.example` to `.env` and set at least the three required values. Full reference:

| Variable            | Required | Default    | Purpose |
| ------------------- | :------: | ---------- | ------- |
| `SECRET_KEY_BASE`   | ✅        | —          | Signs cookies + LiveView tokens (≥ 64 chars). Generate with `make secret`. |
| `POSTGRES_PASSWORD` | ✅        | —          | Superuser password for the bundled Postgres. Also used by the app. |
| `PHX_HOST`          | ✅        | `localhost`| Hostname users reach the app on. Must match the URL in the browser. |
| `APP_PORT`          |          | `4000`     | Host port to publish the app on. |
| `ESTIMATE_TAG`      |          | `latest`   | Image tag from `ghcr.io/dacdigital/estimate`. Pin to a version in production. |
| `POOL_SIZE`         |          | `10`       | Ecto connection pool size. |
| `ENCRYPTION_KEY`    |          | —          | AES-256 key encrypting per-org SMTP/OAuth secrets at rest. Without it, those features stay disabled. Generate with `openssl rand -base64 32`. |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | | — | Enables "Sign in with Google". Redirect URI: `https://<PHX_HOST>/auth/google/callback`. |

The full list of runtime variables lives in [`config/runtime.exs`](../../config/runtime.exs).

## First user & first organization

There is **no default admin account** — the first person to register becomes the owner of the first organization. Rate limits and 2FA are enforced from day one; you can enable **org-required 2FA** in organization settings once you're in.

If you want to close registration after your team has signed up, set the org to invite-only and delete any open join links.

## Upgrade

```bash
make upgrade   # docker compose pull && docker compose up -d
```

The container's entrypoint runs `bin/migrate` (with `SKIP_RLS_ROLE=true`, since the role already exists) before starting the server. Nothing to do by hand.

Pinning a version is recommended for anything that isn't a test instance:

```env
ESTIMATE_TAG=v0.2.0
```

## Backup & restore

```bash
make backup                              # writes backup-<timestamp>.sql.gz
make restore FILE=backup-2026-....sql.gz
```

The database lives in a named Docker volume (`estimate_pgdata`) — `docker compose down` keeps it, `docker compose down -v` (or `make destroy`) wipes it. Take a backup before major upgrades.

## Reverse proxy

The compose stack exposes plain HTTP on `APP_PORT` (default 4000). For anything internet-facing, put a proxy in front that terminates TLS and forwards to `localhost:4000`. LiveView needs **WebSocket upgrade** and **long connections** — do not buffer.

### Caddy (auto-HTTPS, recommended for a single host)

`/etc/caddy/Caddyfile`:

```caddyfile
estimate.example.com {
    reverse_proxy 127.0.0.1:4000
}
```

Caddy handles Let's Encrypt automatically — nothing else needed.

### nginx

```nginx
server {
    listen 443 ssl http2;
    server_name estimate.example.com;

    ssl_certificate     /etc/letsencrypt/live/estimate.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/estimate.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
    }
}
```

### Traefik (labels on the app service)

Append to the `app` service in `docker-compose.override.yml`:

```yaml
services:
  app:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.estimate.rule=Host(`estimate.example.com`)"
      - "traefik.http.routers.estimate.entrypoints=websecure"
      - "traefik.http.routers.estimate.tls.certresolver=letsencrypt"
      - "traefik.http.services.estimate.loadbalancer.server.port=4000"
```

When you sit the app behind a proxy, make sure `PHX_HOST` matches the **public** hostname the browser sees.

## Rotating the at-rest encryption key

`ENCRYPTION_KEY` is a versioned key ring — see the [Rotating the at-rest encryption key](../../README.md#rotating-the-at-rest-encryption-key) section in the main README for the full sequence. In short: add the new key, deploy, run `Estimate.Encryption.Rotation.run/0` from `make shell`, then retire the old key once nothing on v1 remains.

## Troubleshooting

**`SECRET_KEY_BASE` too short.** Must be at least 64 characters. Regenerate with `make secret` and paste the whole string.

**`bind: address already in use` on 4000.** Something else is on port 4000. Set `APP_PORT=8080` (or any free port) in `.env` and `docker compose up -d` again.

**App restarts in a loop right after the first `up`.** Migrations connected before the Postgres role finished being created. Nuke the volume and retry: `make destroy && make up`. This is only safe on a fresh install — never on a database with real data.

**`role "estimate_app" does not exist`.** The bootstrap SQL in `init-db/` only runs on a *fresh* Postgres data volume. If you're bringing your own database, run [`init-db/01-create-role.sql`](init-db/01-create-role.sql) against it once, by hand, before starting the app.

**Can't reach the app from another machine.** `PHX_HOST` must match the hostname in the browser, and (if you're behind a proxy) TLS must terminate there — the app itself only speaks HTTP. Also check firewall on the host.

**Where are the logs?** `make logs`, or `docker compose logs -f app` for just the app.

## Support & contributing

- **Docs & source:** [`../../README.md`](../../README.md) — the main project README covers architecture, RLS, pricing math, and dev setup.
- **Issues:** please open one on the [GitHub repository](https://github.com/DACdigital/Estimate/issues) with the output of `docker compose ps` and the last ~50 lines of `make logs`.
- **Contributions to the compose setup itself** — small PRs against this folder are very welcome (extra proxy examples, other init-db strategies, etc.).

## License

See [`LICENSE`](../../LICENSE) at the repository root.
