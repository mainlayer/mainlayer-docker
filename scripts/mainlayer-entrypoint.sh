#!/usr/bin/env bash
# mainlayer-entrypoint.sh — Container entrypoint for the Mainlayer CLI image.
#
# Responsibilities:
#   1. Validate that MAINLAYER_API_KEY is set.
#   2. Confirm connectivity to the Mainlayer API.
#   3. Exec the mainlayer-cli process (or any command passed as arguments).
#
# Environment variables:
#   MAINLAYER_API_KEY   — Required. Your Mainlayer API key.
#   MAINLAYER_BASE_URL  — Optional. Defaults to https://api.mainlayer.xyz
#   MAINLAYER_LOG_LEVEL — Optional. Defaults to "info".
#   MAINLAYER_TIMEOUT   — Optional. HTTP timeout in seconds. Defaults to 30.
#   MAINLAYER_SKIP_VERIFY — Set to "true" to skip startup API validation (testing only).

set -euo pipefail

MAINLAYER_BASE_URL="${MAINLAYER_BASE_URL:-https://api.mainlayer.xyz}"
MAINLAYER_LOG_LEVEL="${MAINLAYER_LOG_LEVEL:-info}"
MAINLAYER_TIMEOUT="${MAINLAYER_TIMEOUT:-30}"
MAINLAYER_SKIP_VERIFY="${MAINLAYER_SKIP_VERIFY:-false}"

# ── Logging helpers ──────────────────────────────────────────────────────────
log_info()  { printf '[mainlayer] INFO  %s\n' "$*" >&2; }
log_warn()  { printf '[mainlayer] WARN  %s\n' "$*" >&2; }
log_error() { printf '[mainlayer] ERROR %s\n' "$*" >&2; }

# ── 1. Validate API key ──────────────────────────────────────────────────────
if [[ -z "${MAINLAYER_API_KEY:-}" ]]; then
    log_error "MAINLAYER_API_KEY is not set."
    log_error "Set it via: docker run -e MAINLAYER_API_KEY=your_key ..."
    exit 1
fi

# Basic format check — keys begin with "ml_"
if [[ "${MAINLAYER_API_KEY}" != ml_* ]]; then
    log_warn "MAINLAYER_API_KEY does not start with 'ml_'. Double-check your key."
fi

log_info "API key detected (${#MAINLAYER_API_KEY} chars)."

# ── 2. Connectivity check ────────────────────────────────────────────────────
if [[ "${MAINLAYER_SKIP_VERIFY}" != "true" ]]; then
    log_info "Verifying connectivity to ${MAINLAYER_BASE_URL} ..."

    HTTP_STATUS=$(
        curl --silent \
             --output /dev/null \
             --write-out "%{http_code}" \
             --max-time "${MAINLAYER_TIMEOUT}" \
             --header "Authorization: Bearer ${MAINLAYER_API_KEY}" \
             --header "Content-Type: application/json" \
             "${MAINLAYER_BASE_URL}/health" \
        || true
    )

    case "${HTTP_STATUS}" in
        200)
            log_info "Mainlayer API is reachable and healthy."
            ;;
        401|403)
            log_error "Authentication failed (HTTP ${HTTP_STATUS}). Check your MAINLAYER_API_KEY."
            exit 1
            ;;
        000)
            log_error "Could not reach ${MAINLAYER_BASE_URL}. Check your network or MAINLAYER_BASE_URL."
            exit 1
            ;;
        *)
            log_warn "Unexpected HTTP status ${HTTP_STATUS} from Mainlayer API. Proceeding with caution."
            ;;
    esac
else
    log_warn "Startup API verification skipped (MAINLAYER_SKIP_VERIFY=true)."
fi

# ── 3. Exec the requested command ───────────────────────────────────────────
log_info "Starting: mainlayer $*"

# If the first argument looks like a mainlayer subcommand, prepend the binary.
# Otherwise exec whatever was passed directly (e.g. /bin/sh for debugging).
if [[ $# -eq 0 ]]; then
    exec mainlayer --help
elif [[ "$1" == "mainlayer" ]]; then
    exec "$@"
elif [[ "$1" == /* || "$1" == "./"* ]]; then
    # Absolute or relative path — exec directly
    exec "$@"
else
    exec mainlayer "$@"
fi
