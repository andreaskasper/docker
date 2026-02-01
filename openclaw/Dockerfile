# OpenClaw requires Node >= 22
FROM node:slim

LABEL maintainer="Andreas Kasper <andreas.kasper@scoring.dance>"

# Basic deps (curl for install/debug; tini for clean signal handling)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl tini git \
  && rm -rf /var/lib/apt/lists/*

ARG OPENCLAW_VERSION=latest
RUN npm install -g openclaw@${OPENCLAW_VERSION}

RUN useradd -m -u 10001 -s /bin/bash openclaw
USER openclaw
ENV HOME=/home/openclaw
VOLUME ["/home/openclaw/.openclaw"]
EXPOSE 18789

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["openclaw", "gateway", "--port", "18789", "--verbose"]
