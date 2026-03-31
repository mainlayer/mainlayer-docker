# Mainlayer Docker

Official Docker images for [Mainlayer](https://mainlayer.fr) — payment infrastructure for apps and AI agents.

## Images

| Image | Base | Description |
|-------|------|-------------|
| `mainlayer/mainlayer` | `node:20-alpine` | Mainlayer CLI |
| `mainlayer/mainlayer-python` | `python:3.11-slim` | Python SDK environment |

## Quick Start

### CLI Image

```bash
docker pull mainlayer/mainlayer

# Verify a payment by request ID
docker run --rm \
  -e MAINLAYER_API_KEY=ml_live_your_key \
  mainlayer/mainlayer verify --request-id <id>

# Get help
docker run --rm mainlayer/mainlayer --help
```

### Python Image

```bash
docker pull mainlayer/mainlayer-python

# Run a Python script that uses the Mainlayer SDK
docker run --rm \
  -e MAINLAYER_API_KEY=ml_live_your_key \
  -v $(pwd)/my_script.py:/app/script.py \
  mainlayer/mainlayer-python python /app/script.py
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MAINLAYER_API_KEY` | *(required)* | Your Mainlayer API key |
| `MAINLAYER_BASE_URL` | `https://api.mainlayer.fr` | API base URL (override for staging) |
| `MAINLAYER_LOG_LEVEL` | `info` | Log verbosity: `debug`, `info`, `warn`, `error` |
| `MAINLAYER_TIMEOUT` | `30` | Request timeout in seconds |

## Docker Compose: Sidecar Pattern

The recommended production pattern is to run Mainlayer as a **sidecar container** alongside your application. Your app calls the sidecar for payment verification without embedding payment logic directly.

```yaml
# docker-compose.yml
services:
  app:
    build: .
    ports:
      - "8000:8000"
    environment:
      MAINLAYER_SIDECAR_URL: "http://mainlayer-sidecar:3000"
    depends_on:
      mainlayer-sidecar:
        condition: service_healthy

  mainlayer-sidecar:
    image: mainlayer/mainlayer:latest
    command: ["serve", "--port", "3000"]
    environment:
      MAINLAYER_API_KEY: "${MAINLAYER_API_KEY}"
    ports:
      - "3000:3000"
```

```bash
export MAINLAYER_API_KEY=ml_live_your_key
docker compose up
```

See [`docker-compose.yml`](docker-compose.yml) and [`docker-compose.example.yml`](docker-compose.example.yml)
for complete examples.

## Examples

- [`examples/fastapi-with-mainlayer/`](examples/fastapi-with-mainlayer/) — FastAPI app with Mainlayer payment verification
- [`examples/node-with-mainlayer/`](examples/node-with-mainlayer/) — Node.js Express app with Mainlayer

## Building Locally

```bash
# CLI image
docker build -t mainlayer/mainlayer:local .

# Python image
docker build -f Dockerfile.python -t mainlayer/mainlayer-python:local .
```

## Links

- [Mainlayer Documentation](https://docs.mainlayer.fr)
- [Mainlayer Dashboard](https://app.mainlayer.fr)
- [Docker Hub](https://hub.docker.com/r/mainlayer/mainlayer)
