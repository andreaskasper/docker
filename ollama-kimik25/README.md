# Ollama with Kimi K2.5

Docker container with Ollama and the Kimi K2.5 model pre-installed.

## Features

- **Pre-installed Model**: `kimi-k2.5:cloud` is already downloaded during image build
- **Instant Start**: Container is immediately ready to use
- **API Access**: Ollama API available on port 11434

## Build

```bash
docker build -t ollama-kimik25 .
```

## Run

```bash
# Basic run
docker run -d -p 11434:11434 --name ollama-kimik25 ollama-kimik25

# With volume for model persistence
docker run -d -p 11434:11434 -v ollama-data:/root/.ollama --name ollama-kimik25 ollama-kimik25

# With GPU support (NVIDIA)
docker run -d --gpus=all -p 11434:11434 --name ollama-kimik25 ollama-kimik25
```

## Usage

### Via Docker exec

```bash
# Interactive chat
docker exec -it ollama-kimik25 ollama run kimi-k2.5:cloud

# Single prompt
docker exec ollama-kimik25 ollama run kimi-k2.5:cloud "Explain quantum computing"
```

### Via API

```bash
# Generate completion
curl http://localhost:11434/api/generate -d '{
  "model": "kimi-k2.5:cloud",
  "prompt": "Why is the sky blue?"
}'

# Chat endpoint
curl http://localhost:11434/api/chat -d '{
  "model": "kimi-k2.5:cloud",
  "messages": [
    {"role": "user", "content": "Hello!"}
  ]
}'
```

### With OpenClaw

Configure OpenClaw to use this Ollama instance:

```bash
# In your OpenClaw configuration
export OLLAMA_BASE_URL=http://ollama-kimik25:11434
```

Or in docker-compose:

```yaml
services:
  ollama:
    image: ollama-kimik25
    ports:
      - "11434:11434"
    
  openclaw:
    image: openclaw
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    depends_on:
      - ollama
```

## Model Information

- **Model**: Kimi K2.5 Cloud
- **Provider**: Moonshot AI
- **Capabilities**: Text generation, chat, reasoning

## Health Check

```bash
curl http://localhost:11434/api/tags
```

Should return list of available models including `kimi-k2.5:cloud`.

## Logs

```bash
docker logs -f ollama-kimik25
```

## Stop/Remove

```bash
docker stop ollama-kimik25
docker rm ollama-kimik25
```