FROM ollama/ollama:latest

LABEL maintainer="Andreas Kasper <andreas.kasper@scoring.dance>"
LABEL description="Ollama with Kimi K2.5 model pre-installed"

# Install curl for health checks
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
  && rm -rf /var/lib/apt/lists/*

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Pre-pull the Kimi K2.5 model during build
# This makes the image larger but the container starts immediately ready
RUN /bin/bash -c 'ollama serve & \
    pid=$! && \
    echo "Waiting for Ollama to start..." && \
    sleep 5 && \
    echo "Pulling kimi-k2.5:cloud model..." && \
    ollama pull kimi-k2.5:cloud && \
    echo "Model pulled successfully!" && \
    kill $pid && \
    wait $pid 2>/dev/null || true'

# Expose Ollama API port
EXPOSE 11434

# Use volume for model persistence (optional, already baked in)
VOLUME ["/root/.ollama"]

ENTRYPOINT ["/entrypoint.sh"]
CMD []