# Self-hosting HumanLayer on Railway

This folder holds what we added to run the HumanLayer backend on [Railway](https://railway.com) instead of AWS. The official reference (`.claude/skills/self-host-humanlayer/`) targets AWS with Pulumi; this is a smaller setup for a small team.

**Status: work in progress.** The table below says what has been run and what has not. Nothing here is supported by HumanLayer.

| Part | Status |
|---|---|
| Postgres 18, Redis, Electric, durable streams | Running on Railway |
| Migrations and cleanup jobs (`jobs` service) | Running |
| API (`api` service) | Boots and passes its health check with placeholder third-party values |
| Sync proxy (`sync` service) | Boots; not yet tested with a real login |
| WorkOS login, web apps, CLI and daemon builds, file uploads | Not done yet |

## Files here

- `jobs.Dockerfile`, `jobs.sh`: one container that runs database migrations on start, then the stale-daemon sweeper every minute and database maintenance once a day. It replaces the three AWS Lambdas (`riptide-migrator`, `stale-daemon-sweeper`, `database-maintenance-function`). Railway cron cannot run more often than every 5 minutes, so the sweeper runs in a loop.
- `api.Dockerfile`, `sync.Dockerfile`: copies of `apps/riptide-api/Dockerfile` and `apps/riptide-electric-proxy/Dockerfile` without the Sentry source-map stage. Railway rejects BuildKit `--mount=type=secret`.

All four build with the **monorepo root** as the build context. Point a Railway service at one by setting the `RAILWAY_DOCKERFILE_PATH` variable, for example `selfhost/api.Dockerfile`.

## Services

| Service | Source | Port | Volume | Public |
|---|---|---|---|---|
| `postgres` | image `postgres:18` | 5432 | `/var/lib/postgresql` | no |
| `Redis` | Railway Redis | 6379 | (managed) | no |
| `electric` | image `electricsql/electric:1.7.12` | 3000 | `/var/lib/electric` | no |
| `durable-streams` | `docker/durable-streams-server/Dockerfile` | 4437 | `/var/lib/durable-streams` | no |
| `jobs` | `selfhost/jobs.Dockerfile` | none | none | no |
| `api` | `selfhost/api.Dockerfile` | 8700 | none | yes |
| `sync` | `selfhost/sync.Dockerfile` | 8888 | none | yes |
| artifacts | Railway bucket | | | S3 endpoint |

Run exactly one `electric` and one `durable-streams` instance. A Railway service with a volume cannot have replicas, which enforces this.

## Setup notes

### Postgres

Postgres must be version 18 (the migrations use `uuidv7()`), and Electric needs logical replication. Start command:

```
docker-entrypoint.sh postgres -c wal_level=logical -c listen_addresses=* -c max_slot_wal_keep_size=10240 -c max_connections=200
```

Variables: `POSTGRES_DB=electric`, `POSTGRES_USER=postgres`, `POSTGRES_PASSWORD=<random>`, and for other services to reference:

```
DATABASE_URL=postgresql://postgres:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/electric?sslmode=disable
```

### Electric

```
DATABASE_URL=${{postgres.DATABASE_URL}}
ELECTRIC_SECRET=<random>
ELECTRIC_STORAGE_DIR=/var/lib/electric
ELECTRIC_DATABASE_USE_IPV6=true
ELECTRIC_LISTEN_ON_IPV6=true
ELECTRIC_LOG_COLORS=false
ELECTRIC_TCP_READ_TIMEOUT=120s
ELECTRIC_DB_POOL_SIZE=20
ELECTRIC_MAX_SHAPES=5000
ELECTRIC_SHAPE_SUSPEND_CONSUMER=true
PORT=3000
```

### Durable streams

Deploy `docker/durable-streams-server` as the service root. It builds a pinned commit of a third-party repo, so keep a mirror of that repo if you depend on this.

```
DS_SERVER__BIND_ADDRESS=[::]:4437
DS_STORAGE__MODE=file-fast
DS_STORAGE__DATA_DIR=/var/lib/durable-streams
DS_HTTP__ALLOW_WILDCARD_CORS=true
DS_LIMITS__MAX_STREAM_BYTES=104857600
DS_LIMITS__MAX_STREAM_NAME_SEGMENTS=256
RAILWAY_RUN_UID=0
PORT=4437
```

### Jobs

```
DATABASE_URL=${{postgres.DATABASE_URL}}
RAILWAY_DOCKERFILE_PATH=selfhost/jobs.Dockerfile
```

Redeploy `jobs` whenever you pull new migrations, before you redeploy `api`.

### API

Core settings:

```
RAILWAY_DOCKERFILE_PATH=selfhost/api.Dockerfile
NODE_ENV=production
STAGE=prod
PORT=8700
DATABASE_URL=${{postgres.DATABASE_URL}}
READ_REPLICA_DATABASE_URL=${{postgres.DATABASE_URL}}     # required; no replica, so same database
KV_URL=${{Redis.REDIS_URL}}
REDIS_CLIENT_MODE=standalone
DURABLE_STREAMS_ORIGIN=http://${{durable-streams.RAILWAY_PRIVATE_DOMAIN}}:4437
IS_BILLING_ENFORCEMENT_ENABLED=false
BLOCK_NEW_ORG_CREATION=false
ONBOARDING_CAMPAIGN_ENABLED=false
RIPTIDE_API_ORIGIN=https://<api host>
APP_ORIGIN=https://<app host>
CLOUD_ORIGIN=https://<admin host>
WORKOS_CLIENT_ID=<yours>
WORKOS_API_KEY=<yours>
WORKOS_REDIRECT_URI=https://<app host>/auth/callback
S3_ARTIFACTS_BUCKET=<bucket name>
S3_ARTIFACTS_REGION=auto
S3_ARTIFACTS_ENDPOINT=<bucket endpoint>
S3_ACCESS_KEY_ID=<bucket key>
S3_SECRET_ACCESS_KEY=<bucket secret>
RIPTIDE_DAEMON_TOKEN_PRIVATE_KEY=<base64 of PKCS#8 PEM>
RIPTIDE_DAEMON_TOKEN_PUBLIC_KEY=<base64 of SPKI PEM>
```

Generate the daemon token keys:

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out daemon-private.pem
openssl pkey -in daemon-private.pem -pubout -out daemon-public.pem
base64 < daemon-private.pem | tr -d '\n'   # RIPTIDE_DAEMON_TOKEN_PRIVATE_KEY
base64 < daemon-public.pem  | tr -d '\n'   # RIPTIDE_DAEMON_TOKEN_PUBLIC_KEY
```

The API refuses to start unless these are also set. Placeholder strings get it booting; the matching feature then does not work:

```
STRIPE_SECRET_KEY  STRIPE_WEBHOOK_SECRET
STRIPE_PRICE_STARTER  STRIPE_PRICE_PRO  STRIPE_PRICE_ENTERPRISE     # must start with price_
RESEND_API_KEY  RESEND_WEBHOOK_SECRET  RESEND_FROM_EMAIL  RESEND_PRODUCT_USERS_SEGMENT_ID
JIRA_CLIENT_ID  JIRA_CLIENT_SECRET  LINEAR_CLIENT_ID  LINEAR_CLIENT_SECRET
SLACK_CLIENT_ID  SLACK_APP_ID  SLACK_CLIENT_SECRET  SLACK_SIGNING_SECRET
GITHUB_APP_ID  GITHUB_APP_CLIENT_ID  GITHUB_APP_SLUG  GITHUB_APP_WEBHOOK_SECRET
GITHUB_APP_PRIVATE_KEY      # must be a real PKCS#8 RSA PEM, even if throwaway
EXA_API_KEY  CONTEXT7_API_KEY
```

Leave `OPENAI_API_KEY`, `SENTRY_DSN` and `POSTHOG_API_KEY` unset.

### Server-side models through OpenRouter

This branch adds `packages/ai/src/providers/primary-models.ts`. When `OPENROUTER_API_KEY` is set on `api`, titles, summaries and research go through OpenRouter. Without it, the code uses `ANTHROPIC_API_KEY` as before.

```
OPENROUTER_API_KEY=<yours>
OPENROUTER_MODEL_SONNET=anthropic/claude-sonnet-4.5          # optional overrides
OPENROUTER_MODEL_HAIKU=anthropic/claude-haiku-4.5
OPENROUTER_FALLBACK_MODEL_SONNET=openai/gpt-5
OPENROUTER_FALLBACK_MODEL_HAIKU=openai/gpt-5-mini
```

This path typechecks and the existing tests pass, but it has not been run against OpenRouter yet. Check the model slugs against OpenRouter's list.

This only affects server-side features. Agent sessions run on each developer's machine with their own Claude Code or Codex login.

### Sync proxy

```
RAILWAY_DOCKERFILE_PATH=selfhost/sync.Dockerfile
NODE_ENV=production
PORT=8888
DATABASE_URL=${{postgres.DATABASE_URL}}
ELECTRIC_SECRET=${{electric.ELECTRIC_SECRET}}
ELECTRIC_SHAPE_URL=http://${{electric.RAILWAY_PRIVATE_DOMAIN}}:3000/v1/shape
DURABLE_STREAMS_ORIGIN=http://${{durable-streams.RAILWAY_PRIVATE_DOMAIN}}:4437
WORKOS_CLIENT_ID=${{api.WORKOS_CLIENT_ID}}
WORKOS_API_KEY=${{api.WORKOS_API_KEY}}
WORKOS_REDIRECT_URI=${{api.WORKOS_REDIRECT_URI}}
RIPTIDE_DAEMON_TOKEN_PUBLIC_KEY=${{api.RIPTIDE_DAEMON_TOKEN_PUBLIC_KEY}}
```

## WorkOS

From reading the code; not yet verified end to end. Use a dedicated WorkOS environment.

- AuthKit, with roles `admin`, `manager` and `member`.
- A JWT template that adds an `internal_org_id` claim from organization metadata. The sync proxy rejects tokens without it.
- Redirect URIs: `https://<app host>/auth/callback`, `https://<app host>` and `https://<admin host>/auth/callback`. Allow both origins for CORS.
- Webhook to `https://<api host>/webhooks/workos` for `organization_membership.created`, `.updated` and `.deleted`. Put its signing secret in `WORKOS_WEBHOOK_SECRET`.
- Device authorization enabled, for `humanlayer login` in the CLI.

## Still to do

- Web apps (`apps/riptide-ui`, `apps/riptide-cloud`) as static sites with single-page-app fallback.
- CLI and daemon build with our own origins (see `.claude/skills/self-host-humanlayer/references/build-config.md`).
- Bucket CORS for browser uploads.
- A real GitHub App.
