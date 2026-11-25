# Static server for a prebuilt web app (riptide-ui or riptide-cloud).
# Build context: a folder holding this file, web.Caddyfile and the app's dist/.
# selfhost/build-web.sh creates that folder.
FROM caddy:2-alpine
COPY web.Caddyfile /etc/caddy/Caddyfile
COPY dist /srv
