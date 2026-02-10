# OpenClaw + Ollama with Kimi K2.5

Docker container with OpenClaw and Ollama running together, with the Kimi K2.5 model pre-installed.

## Features

- ✅ **OpenClaw Gateway** - Ready to use on port 18789
- ✅ **Ollama with Kimi K2.5** - Model pre-installed and ready
- ✅ **Integrated Setup** - OpenClaw automatically configured to use local Ollama
- ✅ **Both Services** - Run simultaneously via supervisord
- ✅ **Instant Start** - All models downloaded during build

## Exposed Ports

- `18789` - OpenClaw Gateway WebUI
- `11434` - Ollama API

## Build

```bash
cd ollama-kimik25
docker build -t ollama-kimik25 .
```

## Run

### Basic Run

```bash
docker run -d \
  -p 18789:18789 \
  -p 11434:11434 \
  --name ollama-kimik25 \
  ollama-kimik25
```

### With Volumes

```bash
docker run -d \
  -p 18789:18789 \
  -p 11434:11434 \
  -v openclaw-data:/home/openclaw/.openclaw \
  -v ollama-data:/root/.ollama \
  --name ollama-kimik25 \
  ollama-kimik25
```

### With Docker Compose

```bash
docker-compose up -d
```

## Usage

### OpenClaw WebUI

Open your browser:
```
http://localhost:18789
```

OpenClaw is already configured to use the local Ollama instance with Kimi K2.5.

### Ollama API

```bash
# Via Docker exec
docker exec -it ollama-kimik25 ollama run kimi-k2.5:cloud

# Via API
curl http://localhost:11434/api/generate -d '{
  "model": "kimi-k2.5:cloud",
  "prompt": "Hello!"
}'
```

### Check Services

```bash
# Check all running processes
docker exec ollama-kimik25 supervisorctl status

# View logs
docker logs -f ollama-kimik25

# Check OpenClaw
curl http://localhost:18789/health

# Check Ollama
curl http://localhost:11434/api/tags
```

## Architecture

This container runs two services simultaneously:

1. **Ollama Server** (port 11434)
   - Manages and serves the Kimi K2.5 model
   - API accessible for direct queries

2. **OpenClaw Gateway** (port 18789)
   - Provides web interface and workflow management
   - Pre-configured with `OLLAMA_BASE_URL=http://localhost:11434`
   - Can use Kimi K2.5 for AI tasks

Both services are managed by `supervisord` and start automatically.

## Environment Variables

OpenClaw is pre-configured with:
```bash
OLLAMA_BASE_URL=http://localhost:11434
```

You can override this by passing environment variables:

```bash
docker run -d \
  -p 18789:18789 \
  -p 11434:11434 \
  -e OLLAMA_BASE_URL=http://custom-ollama:11434 \
  ollama-kimik25
```

## GPU Support

For NVIDIA GPU support:

```bash
docker run -d \
  --gpus=all \
  -p 18789:18789 \
  -p 11434:11434 \
  --name ollama-kimik25 \
  ollama-kimik25
```

## Troubleshooting

### Check if both services are running

```bash
docker exec ollama-kimik25 supervisorctl status
```

Expected output:
```
ollama                           RUNNING   pid 123, uptime 0:01:00
openclaw                         RUNNING   pid 124, uptime 0:01:00
```

### Restart a service

```bash
# Restart Ollama
docker exec ollama-kimik25 supervisorctl restart ollama

# Restart OpenClaw
docker exec ollama-kimik25 supervisorctl restart openclaw
```

### View individual logs

```bash
# All logs
docker logs ollama-kimik25

# Follow logs
docker logs -f ollama-kimik25
```

## Model Information

- **Model**: Kimi K2.5 Cloud (`kimi-k2.5:cloud`)
- **Provider**: Moonshot AI
- **Size**: Downloaded during image build
- **Capabilities**: Text generation, chat, reasoning

## Stop/Remove

```bash
docker stop ollama-kimik25
docker rm ollama-kimik25
```