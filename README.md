# Mainlayer Docker

Official Docker images for [Mainlayer](https://mainlayer.fr) — payment infrastructure for AI apps. Includes CLI and SDK runtimes for Node.js and Python.

## Images

| Image | Base | Use Case |
|-------|------|----------|
| `mainlayer/mainlayer` | node:20-alpine (12 MB) | CLI verification, lightweight tools |
| `mainlayer/mainlayer-python` | python:3.12-slim (51 MB) | Python apps, ML integrations |

## Quick Start

### 1. Pull & Run CLI

```bash
docker pull mainlayer/mainlayer

# Verify a payment
docker run --rm \
  -e MAINLAYER_API_KEY=ml_live_abc123 \
  mainlayer/mainlayer verify --request-id pay_xyz789

# Check health
docker run --rm \
  -e MAINLAYER_API_KEY=ml_live_abc123 \
  mainlayer/mainlayer health
```

### 2. Use as Sidecar (Production Pattern)

The **sidecar pattern** decouples payment verification from your app logic:

```yaml
# docker-compose.yml
version: '3.8'

services:
  # Your application
  app:
    build: .
    ports:
      - "8000:8000"
    environment:
      MAINLAYER_SIDECAR_URL: http://mainlayer-sidecar:3000
    depends_on:
      mainlayer-sidecar:
        condition: service_healthy

  # Mainlayer payment verification sidecar
  mainlayer-sidecar:
    image: mainlayer/mainlayer:latest
    command: ["serve", "--port", "3000"]
    environment:
      MAINLAYER_API_KEY: "${MAINLAYER_API_KEY}"
      MAINLAYER_LOG_LEVEL: debug
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
    ports:
      - "3000:3000"
    restart: unless-stopped
```

Run:
```bash
export MAINLAYER_API_KEY=ml_live_abc123
docker compose up
```

### 3. Python SDK

```bash
docker pull mainlayer/mainlayer-python

# Run a Python script
docker run --rm \
  -e MAINLAYER_API_KEY=ml_live_abc123 \
  -v $(pwd)/script.py:/app/script.py \
  mainlayer/mainlayer-python python /app/script.py
```

Sample Python script:
```python
import os
from mainlayer import Client

api_key = os.environ["MAINLAYER_API_KEY"]
client = Client(api_key=api_key)

# Check if user has entitlement
has_access = client.check_entitlement(
    user_id="user_123",
    resource_id="res_abc456"
)
print(f"Access granted: {has_access}")
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAINLAYER_API_KEY` | *(required)* | Your API key from [app.mainlayer.fr/settings](https://app.mainlayer.fr/settings) |
| `MAINLAYER_BASE_URL` | `https://api.mainlayer.fr` | API endpoint (use staging URL for testing) |
| `MAINLAYER_LOG_LEVEL` | `info` | Verbosity: `debug`, `info`, `warn`, `error` |
| `MAINLAYER_TIMEOUT` | `30` | HTTP request timeout in seconds |
| `MAINLAYER_SKIP_VERIFY` | `false` | Skip startup API check (testing only) |

## Examples

### FastAPI with Payment Verification

```bash
cd examples/fastapi-with-mainlayer
docker compose up
# Visit http://localhost:8000/docs for OpenAPI UI
```

See `/api/v1/data` endpoint for payment-gated resource.

### Node.js/Express with Payment Processing

```bash
cd examples/node-with-mainlayer
docker compose up
# POST http://localhost:8000/api/charge
```

Processes payments and grants entitlements.

## Sidecar Architecture

The sidecar pattern isolates payment logic:

```
┌─────────────────┐       ┌─────────────────────────┐
│                 │       │  Mainlayer Sidecar      │
│   Your App      │◄─────►│  • Verify payments      │
│   :8000         │       │  • Check entitlements   │
│                 │       │  • Log transactions     │
└─────────────────┘       └─────────────────────────┘
                                   │
                                   ▼
                         ┌──────────────────┐
                         │ Mainlayer API    │
                         │ api.mainlayer.fr │
                         └──────────────────┘
```

Benefits:
- **Decoupling**: Payment logic is independent
- **Resilience**: Sidecar can cache verification results
- **Security**: App never handles raw API keys
- **Observability**: Centralized logging and monitoring

## Building Locally

```bash
# CLI image (Node.js)
docker build -t mainlayer:local .

# Python image
docker build -f Dockerfile.python -t mainlayer-python:local .

# Test locally
docker run --rm \
  -e MAINLAYER_API_KEY=ml_live_test \
  -e MAINLAYER_SKIP_VERIFY=true \
  mainlayer:local --help
```

## Healthchecks

Both images include production-grade healthchecks:

```bash
# Manual healthcheck
docker exec <container_id> /usr/local/bin/healthcheck.sh

# In docker-compose
services:
  mainlayer-sidecar:
    healthcheck:
      test: ["CMD", "/usr/local/bin/healthcheck.sh"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
```

The healthcheck:
1. Checks local sidecar (if running in serve mode)
2. Falls back to upstream API health
3. Returns 0 on success, 1 on failure

## Security

### Best Practices

- **Never hardcode API keys** — use environment variables or Docker Secrets
- **Use read-only filesystems** — add `read_only: true` in docker-compose
- **Run as non-root** — images use unprivileged `mainlayer` user
- **Scan images** — run `docker scan mainlayer/mainlayer` before deployment

### Secrets Management (Docker Swarm)

```yaml
services:
  mainlayer-sidecar:
    image: mainlayer/mainlayer:latest
    environment:
      MAINLAYER_API_KEY_FILE: /run/secrets/ml_api_key
    secrets:
      - ml_api_key

secrets:
  ml_api_key:
    external: true  # Create with: docker secret create ml_api_key <(echo ml_live_...)
```

### Kubernetes Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mainlayer-secret
type: Opaque
stringData:
  api-key: ml_live_abc123
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mainlayer-sidecar
spec:
  containers:
  - name: mainlayer
    image: mainlayer/mainlayer:latest
    env:
    - name: MAINLAYER_API_KEY
      valueFrom:
        secretKeyRef:
          name: mainlayer-secret
          key: api-key
```

## Troubleshooting

**Container won't start**
```bash
docker logs <container_id>
# Check for: MAINLAYER_API_KEY not set, invalid key format, network connectivity
```

**Payment verification fails**
```bash
# Check sidecar logs
docker logs mainlayer-sidecar

# Test connectivity manually
docker exec mainlayer-sidecar curl -v \
  -H "Authorization: Bearer $MAINLAYER_API_KEY" \
  https://api.mainlayer.fr/health
```

**Slow requests**
- Increase `MAINLAYER_TIMEOUT` (default 30s)
- Check sidecar CPU/memory: `docker stats`
- Verify network latency to api.mainlayer.fr

## Testing

```bash
# Run tests for Python image
docker run --rm \
  mainlayer-python:local \
  python -m pytest tests/

# Test CLI
docker run --rm \
  -e MAINLAYER_SKIP_VERIFY=true \
  mainlayer:local \
  --version
```

## Performance

| Metric | Node.js Image | Python Image |
|--------|---------------|--------------|
| Startup Time | ~100ms | ~300ms |
| Memory (idle) | 25 MB | 45 MB |
| Healthcheck Latency | <50ms | <100ms |

## Resources

- **Docs**: [docs.mainlayer.fr](https://docs.mainlayer.fr)
- **Dashboard**: [app.mainlayer.fr](https://app.mainlayer.fr)
- **API Reference**: [docs.mainlayer.fr/api](https://docs.mainlayer.fr/api)
- **Docker Hub**: [hub.docker.com/r/mainlayer/mainlayer](https://hub.docker.com/r/mainlayer/mainlayer)
