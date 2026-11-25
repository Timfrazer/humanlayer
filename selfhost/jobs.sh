#!/bin/sh
# Migrate once, then loop the periodic jobs. Replaces HumanLayer's three Lambdas.
set -u
ROOT=/usr/src/app

echo "[jobs] running migrations"
(cd "$ROOT/packages/db" && bun --bun drizzle-kit migrate) || { echo "[jobs] migration failed"; exit 1; }
echo "[jobs] migrations done"

last_maintenance=0
while true; do
	(cd "$ROOT/apps/stale-daemon-sweeper" && bun --bun index.ts) || echo "[jobs] sweep failed"
	now=$(date +%s)
	if [ $((now - last_maintenance)) -ge 86400 ]; then
		(cd "$ROOT/apps/database-maintenance-function" && bun --bun index.ts) || echo "[jobs] maintenance failed"
		last_maintenance=$now
	fi
	sleep 60
done
