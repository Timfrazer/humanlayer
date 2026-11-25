# syntax=docker/dockerfile:1.20
# Self-host copy of apps/riptide-electric-proxy/Dockerfile without the Sentry source-map upload stage:
# Railway does not support BuildKit secret mounts. Build context: monorepo root.

FROM oven/bun:1.3 AS base
WORKDIR /usr/src/app
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

FROM base AS manifests
COPY package.json bun.lock bunfig.toml ./
COPY --parents apps/*/package.json packages/*/package.json contracts/*/package.json vendor/*/package.json ./

# Stage 1: Install deps and build
# Filtered install: a full workspace install would run node-pty's gyp build
# (dep of riptide-electron), which needs Python that oven/bun doesn't ship.
FROM manifests AS builder
RUN bun install --frozen-lockfile --filter @humanlayer/riptide-electric-proxy
COPY --parents apps/riptide-electric-proxy packages contracts vendor ./
RUN cd apps/riptide-electric-proxy && bun run build

# Stage 3: Install production deps only
FROM manifests AS prod-deps
RUN bun install --frozen-lockfile --production --filter @humanlayer/riptide-electric-proxy

# Stage 4: Final runtime image
FROM node:24-slim AS runner
WORKDIR /usr/src/app/apps/riptide-electric-proxy
RUN groupadd --system --gid 1001 nodejs && useradd --system --uid 1001 hono

COPY --from=prod-deps --chown=hono:nodejs /usr/src/app /usr/src/app
COPY --from=builder --chown=hono:nodejs /usr/src/app/apps/riptide-electric-proxy/dist ./dist
COPY --from=builder --chown=hono:nodejs /usr/src/app/apps/riptide-electric-proxy/dist/instrument.mjs ./instrument.mjs

USER hono
ENV NODE_ENV=production PORT=8888
EXPOSE 8888
CMD ["node", "--import", "./instrument.mjs", "./dist/index.mjs"]
