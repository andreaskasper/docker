# Base image with Node.js for OpenClaw
FROM node:slim

LABEL maintainer="Andreas Kasper <andreas.kasper@scoring.dance>"
LABEL description="OpenClaw with Ollama and Kimi K2.5 model pre-installed"

# Install dependencies for both OpenClaw and Ollama
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    sudo \
    tini \
    supervisor \
  && rm -rf /var/lib/apt/lists/*

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Install OpenClaw
ARG OPENCLAW_VERSION=latest
RUN npm install -g openclaw@${OPENCLAW_VERSION}

# Create user and configure sudo
RUN useradd -m -u 10001 -s /bin/bash openclaw \
  && echo "openclaw ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers

# Pre-pull the Kimi K2.5 model during build
RUN /bin/bash -c 'ollama serve & \
    pid=$! && \
    echo "Waiting for Ollama to start..." && \
    sleep 10 && \
    echo "Pulling kimi-k2.5:cloud model..." && \
    ollama pull kimi-k2.5:cloud && \
    echo "Model pulled successfully!" && \
    kill $pid && \
    wait $pid 2>/dev/null || true'

# Copy configuration files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose both OpenClaw and Ollama ports
EXPOSE 18789 11434

# Volumes for both services
VOLUME ["/home/openclaw/.openclaw", "/root/.ollama"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD []