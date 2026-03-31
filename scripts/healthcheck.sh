#!/usr/bin/env bash
# healthcheck.sh — Docker HEALTHCHECK for the Mainlayer container.
#
# Called by Docker's HEALTHCHECK instruction every 30 seconds.
# Exit 0 = healthy, exit 1 = unhealthy.
#
# The check hits the /health endpoint on the Mainlayer API with the
# configured API key and verifies a 200 response.

set -euo pipefail

MAINLAYER_BASE_URL="${MAINLAYER_BASE_URL:-https://api.mainlayer.xyz}"
MAINLAYER_TIMEOUT="${MAINLAYER_TIMEOUT:-10}"

# If the container is running in sidecar/serve mode, check the local port first.
LOCAL_PORT="${MAINLAYER_SERVE_PORT:-3000}"

# ── Check local sidecar health (if running in serve mode) ────────────────────
if curl --silent \
        --fail \
        --max-time 5 \
        "http://localhost:${LOCAL_PORT}/health" \
        > /dev/null 2>&1; then
    exit 0
fi

# ── Fall back to upstream API health check ───────────────────────────────────
if [[ -z "${MAINLAYER_API_KEY:-}" ]]; then
    # No API key — we can only do a basic TCP check
    curl --silent \
         --fail \
         --max-time "${MAINLAYER_TIMEOUT}" \
         --output /dev/null \
         "${MAINLAYER_BASE_URL}/health" \
         > /dev/null 2>&1
    exit $?
fi

HTTP_STATUS=$(
    curl --silent \
         --output /dev/null \
         --write-out "%{http_code}" \
         --max-time "${MAINLAYER_TIMEOUT}" \
         --header "Authorization: Bearer ${MAINLAYER_API_KEY}" \
         "${MAINLAYER_BASE_URL}/health" \
    || echo "000"
)

if [[ "${HTTP_STATUS}" == "200" ]]; then
    exit 0
else
    printf 'Mainlayer health check failed (HTTP %s)\n' "${HTTP_STATUS}" >&2
    exit 1
fi
