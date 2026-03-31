# Mainlayer CLI Docker Image (Node.js)
# Official image for payment verification and CLI access.
# Minimal (~12MB), production-ready with health checks and security hardening.
#
# Usage:
#   docker run --rm -e MAINLAYER_API_KEY=ml_live_... mainlayer/mainlayer verify --request-id <id>
#   docker compose up (see examples/)

FROM node:20-alpine as builder

# Install build dependencies
RUN apk add --no-cache \
    python3 \
    make \
    g++

# Install Mainlayer CLI with minimal footprint
RUN npm install --production --global mainlayer-cli

# ── Runtime Stage ────────────────────────────────────────────────────────────

FROM node:20-alpine

# OCI Labels for discoverability
LABEL org.opencontainers.image.title="Mainlayer CLI"
LABEL org.opencontainers.image.description="Payment infrastructure for AI agents"
LABEL org.opencontainers.image.url="https://mainlayer.fr"
LABEL org.opencontainers.image.documentation="https://docs.mainlayer.fr"
LABEL org.opencontainers.image.source="https://github.com/mainlayer/mainlayer-docker"
LABEL org.opencontainers.image.vendor="Mainlayer"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="1.0.0"

# Install minimal runtime dependencies
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    ca-certificates \
    tini

# Copy pre-built CLI from builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/mainlayer-cli/bin/mainlayer /usr/local/bin/mainlayer

# Copy helper scripts
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/mainlayer-entrypoint.sh \
             /usr/local/bin/healthcheck.sh

# Create non-root user (required for security scanning)
RUN addgroup -S mainlayer && adduser -S mainlayer -G mainlayer

# Set working directory
WORKDIR /app

# ── Environment Configuration ────────────────────────────────────────────────
# MAINLAYER_API_KEY is required; set via -e or secrets
ENV MAINLAYER_API_KEY="" \
    MAINLAYER_BASE_URL="https://api.mainlayer.fr" \
    MAINLAYER_LOG_LEVEL="info" \
    MAINLAYER_TIMEOUT="30" \
    MAINLAYER_SKIP_VERIFY="false" \
    NODE_ENV="production"

# ── Health Check ─────────────────────────────────────────────────────────────
# Ensures connectivity to Mainlayer API on container startup
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

# ── Signal Handling ──────────────────────────────────────────────────────────
# Use tini to properly handle SIGTERM, SIGINT
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/mainlayer-entrypoint.sh"]

# Default: show help; override with any CLI subcommand
CMD ["--help"]
