# EstiMate — Helm chart

Kubernetes deployment of [EstiMate](https://github.com/DACdigital/Estimate),
an Elixir/Phoenix estimation platform. Chart is built on the
[`helm-framework`](https://github.com/k8s-stuff/helm-framework) library and
publishes at every git tag from
[`docker.yml`](../../../.github/workflows/docker.yml).

## Install

### Pull

```bash
helm pull oci://registry-1.docker.io/dacinfomotion/estimate-chart --version <TAG>
```

### Install (bundled Postgres, quick start)

```bash
helm install estimate \
  oci://registry-1.docker.io/dacinfomotion/estimate-chart \
  --version <TAG> \
  --namespace estimate --create-namespace \
  --set envVars[0].value=estimate.example.com \
  --set appSecret.secretKeyBase="$(mix phx.gen.secret 2>/dev/null || openssl rand -base64 48)" \
  --set appSecret.encryptionKey="$(openssl rand -base64 32)" \
  --set appSecret.databaseRolePassword="$(openssl rand -base64 24)" \
  --set postgres.auth.password="$(openssl rand -base64 24)"
```

The bundled Postgres is a single-replica `StatefulSet` with a `PersistentVolumeClaim`
and **no backups, replication, or WAL archiving**. Fine for staging and single-
tenant hobbyist deploys; for production, disable it and point at a managed
database:

### Install (external database)

```bash
helm install estimate \
  oci://registry-1.docker.io/dacinfomotion/estimate-chart \
  --version <TAG> \
  --namespace estimate --create-namespace \
  --set postgres.enabled=false \
  --set externalDatabase.url="postgres://postgres:...@db.example.com:5432/estimate" \
  --set appSecret.secretKeyBase=... \
  --set appSecret.encryptionKey=... \
  --set appSecret.databaseRolePassword=...
```

## RLS bootstrap

The application enforces Row-Level Security by connecting as the Postgres
superuser and switching to the non-privileged `estimate_app` role per
connection. That role is created automatically by migration
`20260211080345_enforce_rls_with_app_role.exs` on first boot — no manual SQL
required. The migration uses `DATABASE_ROLE_PASSWORD` from the app Secret as
the role's password.

## Values reference

The chart exposes the full [`helm-framework` value reference](https://github.com/k8s-stuff/helm-framework)
at the root, plus two chart-owned sections:

| Key | Type | Default | Notes |
|---|---|---|---|
| `appSecret.create` | bool | `true` | Render Secret named `estimate-app` |
| `appSecret.existingSecretName` | string | `""` | BYO — must supply all seven keys |
| `appSecret.secretKeyBase` | string | `""` | REQUIRED when `create=true` |
| `appSecret.encryptionKey` | string | `""` | REQUIRED when `create=true` (32-byte base64) |
| `appSecret.databaseRolePassword` | string | `""` | REQUIRED when `create=true` (role `estimate_app`) |
| `appSecret.google.clientId` | string | `""` | Optional (Google OAuth SSO) |
| `appSecret.google.clientSecret` | string | `""` | Optional (Google OAuth SSO) |
| `postgres.enabled` | bool | `true` | Bundle a single-replica StatefulSet |
| `postgres.image.tag` | string | `17-alpine` | Official upstream `postgres` image |
| `postgres.auth.password` | string | `""` | REQUIRED when `enabled=true` |
| `postgres.persistence.size` | string | `10Gi` | PVC size |
| `postgres.persistence.storageClass` | string | `""` | Empty → cluster default |
| `externalDatabase.url` | string | `""` | Used when `postgres.enabled=false` |

## Upgrade

```bash
helm upgrade estimate oci://registry-1.docker.io/dacinfomotion/estimate-chart \
  --version <NEW-TAG> --reuse-values
```

Migrations run automatically on pod boot via the image entrypoint
(`bin/migrate_and_server` with `SKIP_RLS_ROLE=true` — see the [top-level README][repo-readme]
for the RLS design).

[repo-readme]: https://github.com/DACdigital/Estimate/blob/main/README.md
