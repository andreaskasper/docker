# OpenClaw requires Node >= 22
FROM node:slim

LABEL maintainer="Andreas Kasper <andreas.kasper@scoring.dance>"

# Basic deps (curl for install/debug; tini for clean signal handling; sudo for permission fixes)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl tini git sudo \
  && rm -rf /var/lib/apt/lists/*

ARG OPENCLAW_VERSION=latest
RUN npm install -g openclaw@${OPENCLAW_VERSION}

# Create user and configure sudo
RUN useradd -m -u 10001 -s /bin/bash openclaw \
  && echo "openclaw ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

USER openclaw
ENV HOME=/home/openclaw
VOLUME ["/home/openclaw/.openclaw"]
EXPOSE 18789

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["openclaw", "gateway", "--port", "18789", "--verbose"]