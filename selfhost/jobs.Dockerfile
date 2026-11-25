# syntax=docker/dockerfile:1.20
# Self-host jobs image: runs DB migrations on start, then the stale-daemon
# sweeper every minute and database maintenance once a day.
# Build context: monorepo root.
FROM oven/bun:1.3
WORKDIR /usr/src/app
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY package.json bun.lock bunfig.toml ./
COPY --parents apps/*/package.json packages/*/package.json contracts/*/package.json vendor/*/package.json ./
RUN bun install --frozen-lockfile \
	--filter @humanlayer/db \
	--filter @humanlayer/stale-daemon-sweeper \
	--filter @humanlayer/database-maintenance-function
COPY --parents packages contracts vendor apps/stale-daemon-sweeper apps/database-maintenance-function ./
COPY selfhost/jobs.sh /jobs.sh
CMD ["sh", "/jobs.sh"]
