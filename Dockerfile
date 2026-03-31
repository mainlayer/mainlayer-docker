# Mainlayer CLI Docker Image
# Official image for running the Mainlayer CLI and integrating Mainlayer
# payment verification into containerized services.
#
# Usage:
#   docker pull mainlayer/mainlayer
#   docker run --rm -e MAINLAYER_API_KEY=your_key mainlayer/mainlayer verify --request-id <id>

FROM node:20-alpine

LABEL org.opencontainers.image.title="Mainlayer"
LABEL org.opencontainers.image.description="Official Mainlayer CLI image — Stripe for AI agents"
LABEL org.opencontainers.image.url="https://mainlayer.xyz"
LABEL org.opencontainers.image.documentation="https://docs.mainlayer.xyz"
LABEL org.opencontainers.image.source="https://github.com/mainlayer/mainlayer-docker"
LABEL org.opencontainers.image.vendor="Mainlayer"
LABEL org.opencontainers.image.licenses="MIT"

# Install system dependencies
RUN apk add --no-cache \
    curl \
    jq \
    bash \
    ca-certificates \
    tini

# Install the Mainlayer CLI globally
RUN npm install -g mainlayer-cli

# Copy helper scripts into PATH
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/mainlayer-entrypoint.sh \
             /usr/local/bin/healthcheck.sh \
             /usr/local/bin/setup.sh

# Create a non-root user for running the CLI
RUN addgroup -S mainlayer && adduser -S mainlayer -G mainlayer

# Runtime environment variables (all optional; set per-container)
ENV MAINLAYER_API_KEY=""
ENV MAINLAYER_BASE_URL="https://api.mainlayer.xyz"
ENV MAINLAYER_LOG_LEVEL="info"
ENV MAINLAYER_TIMEOUT="30"

# Health check — calls /health on the Mainlayer API
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

# Use tini as PID 1 to handle signals correctly
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/mainlayer-entrypoint.sh"]

# Default command shows help; override with any mainlayer-cli subcommand
CMD ["--help"]
