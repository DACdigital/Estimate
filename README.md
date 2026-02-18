# Estimate

Multi-tenant SaaS for project estimation — real-time collaboration, role-based pricing, AI-enhanced descriptions.

## Features

**Estimation engine**
- Epics/tasks hierarchy with per-role hour estimates
- Multi-currency support, MoSCoW priority levels
- Cost breakdowns by role, epic, and total
- JSON import/export, reusable templates

**Real-time collaboration**
- Phoenix LiveView + PubSub — no page reloads, instant updates across users

**Multi-tenancy**
- Organization-scoped PostgreSQL RLS enforced via `app_role`
- Roles: owner, admin, member

**CRM**
- Customer database with full-text search (pg_trgm + tsvector)

**Portfolio**
- Projects with collaborator management

**AI**
- OpenRouter integration for description enhancement
- Searchable model picker

**Auth**
- Email/password (Argon2) + Google OAuth (Assent)
- Invite links, join requests

**Email**
- Swoosh + gen_smtp, per-organization SMTP configuration
- Encrypted credentials storage

**Search**
- Cross-entity full-text search with trigram similarity

## Tech stack

| Layer | Technology |
|-------|-----------|
| Framework | Phoenix 1.8, LiveView 1.1 |
| Database | Ecto 3.13, PostgreSQL 17 |
| CSS | Tailwind v4 |
| JS bundler | esbuild |
| HTTP server | Bandit |
| Auth | Argon2, Assent (OAuth), JOSE |
| Email | Swoosh, gen_smtp |
| HTTP client | Req |

## Prerequisites

- Erlang/OTP 27+
- Elixir 1.15+
- PostgreSQL 17 (or Docker)
- No Node.js required

## Local development

```bash
# 1. Clone
git clone <repo-url> && cd estimate

# 2. Start Postgres (port 5499)
docker compose up -d

# 3. (Optional) Create .env with Google OAuth credentials
cat > .env << 'EOF'
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret
EOF

# 4. Install deps, create DB, run migrations, build assets
mix setup

# 5. Start server
mix phx.server
```

Open [localhost:4000](http://localhost:4000). Dev mailbox at [localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox).

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | prod | — | Postgres connection string (`ecto://USER:PASS@HOST/DATABASE`) |
| `SECRET_KEY_BASE` | prod | — | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | prod | `example.com` | Public hostname |
| `PORT` | no | `4000` | HTTP port |
| `PHX_SERVER` | prod | — | Set to `true` to start the HTTP server |
| `POOL_SIZE` | no | `20` | Ecto connection pool size |
| `ECTO_IPV6` | no | — | Set to `true` for IPv6 socket |
| `DNS_CLUSTER_QUERY` | no | — | DNS query for Erlang clustering |
| `GOOGLE_CLIENT_ID` | no | — | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | no | — | Google OAuth client secret |

## Tests

```bash
mix test
```

## Docker deployment

### Dockerfile

Multi-stage build: builder → runner.

```dockerfile
# --- Builder ---
FROM hexpm/elixir:1.15.7-erlang-27.0-debian-bookworm-20240701 AS builder

ENV MIX_ENV=prod

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN mix assets.deploy
RUN mix compile
RUN mix release

# --- Runner ---
FROM debian:bookworm-slim AS runner

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales && \
    apt-get clean && rm -f /var/lib/apt/lists/*_* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/estimate ./

CMD ["bin/estimate", "start"]
```

> **Note:** `libstdc++6` and `locales` are needed for the Argon2 NIF.

### docker-compose.prod.yml

```yaml
services:
  app:
    build: .
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: ecto://postgres:postgres@postgres/estimate_prod
      SECRET_KEY_BASE: <generate-with-mix-phx.gen.secret>
      PHX_HOST: your-domain.com
      PHX_SERVER: "true"
      PORT: "4000"
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:17
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: estimate_prod
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```

### Running migrations

```bash
docker compose -f docker-compose.prod.yml exec app bin/estimate eval "Estimate.Release.migrate"
```

## Kubernetes

### Build & push

```bash
docker build -t your-registry/estimate:latest .
docker push your-registry/estimate:latest
```

### Sample manifests

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: estimate
spec:
  replicas: 2
  selector:
    matchLabels:
      app: estimate
  template:
    metadata:
      labels:
        app: estimate
    spec:
      initContainers:
        - name: migrate
          image: your-registry/estimate:latest
          command: ["bin/estimate", "eval", "Estimate.Release.migrate"]
          envFrom:
            - secretRef:
                name: estimate-env
      containers:
        - name: estimate
          image: your-registry/estimate:latest
          ports:
            - containerPort: 4000
          envFrom:
            - secretRef:
                name: estimate-env
          readinessProbe:
            tcpSocket:
              port: 4000
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            tcpSocket:
              port: 4000
            initialDelaySeconds: 15
            periodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: estimate
spec:
  selector:
    app: estimate
  ports:
    - port: 80
      targetPort: 4000
---
apiVersion: v1
kind: Secret
metadata:
  name: estimate-env
type: Opaque
stringData:
  DATABASE_URL: ecto://user:pass@postgres-host/estimate_prod
  SECRET_KEY_BASE: <generate-with-mix-phx.gen.secret>
  PHX_HOST: your-domain.com
  PHX_SERVER: "true"
  PORT: "4000"
  POOL_SIZE: "10"
  DNS_CLUSTER_QUERY: estimate.default.svc.cluster.local
```

### Notes

- **Clustering**: set `DNS_CLUSTER_QUERY` to your headless Service DNS for Erlang node discovery across pods
- **Pool size**: divide total desired connections by replica count (`POOL_SIZE = total / replicas`)
- **Sessions**: no sticky sessions needed — LiveView uses WebSocket which stays on one node
- **Migrations**: init container runs before app pods start; alternatively use a Kubernetes Job

## Database notes

- **Extensions**: `citext`, `pg_trgm` (created automatically by migrations)
- **RLS**: row-level security enforced via `app_role` set on each connection (`after_connect` callback)
- Migrations create RLS policies automatically
