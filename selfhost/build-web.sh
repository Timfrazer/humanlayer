#!/bin/sh
# Build riptide-ui and riptide-cloud with your own origins and stage each one
# for `railway up`. Run from anywhere inside the repo.
#
# Required env:
#   APP_ORIGIN  CLOUD_ORIGIN  API_ORIGIN  SYNC_ORIGIN  WORKOS_CLIENT_ID
# Optional env:
#   DEEP_LINK_SCHEME (default: selfhost-humanlayer)   OUT_DIR (default: ../.deploy)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT/../.deploy"}
: "${APP_ORIGIN:?}" "${CLOUD_ORIGIN:?}" "${API_ORIGIN:?}" "${SYNC_ORIGIN:?}" "${WORKOS_CLIENT_ID:?}"

export NODE_ENV=production
export NODE_OPTIONS=--max-old-space-size=8192
export VITE_PUBLIC_RIPTIDE_API_ORIGIN="$API_ORIGIN"
export VITE_PUBLIC_SYNC_ORIGIN="$SYNC_ORIGIN"
export VITE_PUBLIC_APP_ORIGIN="$APP_ORIGIN"
export VITE_PUBLIC_CLOUD_ORIGIN="$CLOUD_ORIGIN"
export VITE_PUBLIC_WORKOS_CLIENT_ID="$WORKOS_CLIENT_ID"
export VITE_PUBLIC_BILLING_ENFORCEMENT_ENABLED=false
export VITE_PUBLIC_BUILD_TYPE=prod
export VITE_PUBLIC_REMOTE_DAEMON_BUILD_TYPE=prod
export VITE_PUBLIC_ENVIRONMENT=prod
export VITE_PUBLIC_DEEP_LINK_SCHEME="${DEEP_LINK_SCHEME:-selfhost-humanlayer}"
export VITE_PUBLIC_BUILD_VERSION="$(git -C "$ROOT" rev-parse --short HEAD)"

for pair in riptide-ui:app riptide-cloud:admin; do
	app=${pair%%:*}; name=${pair##*:}
	echo "[build-web] building $app"
	(cd "$ROOT/apps/$app" && bun run build)
	stage="$OUT_DIR/$name"
	rm -rf "$stage" && mkdir -p "$stage"
	cp -R "$ROOT/apps/$app/dist" "$stage/dist"
	cp "$ROOT/selfhost/web.Dockerfile" "$stage/Dockerfile"
	cp "$ROOT/selfhost/web.Caddyfile" "$stage/web.Caddyfile"
	echo "[build-web] staged $stage"
done
