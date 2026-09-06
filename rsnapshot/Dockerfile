FROM debian:stable-slim
LABEL maintainer="Andreas.Kasper@goo1.de"

# Was debian:10-slim. Buster is end of life and its mirrors are gone, so
# `apt-get install` failed with exit 100 — silently, because the workflow that
# would have reported it had been disabled since 2022.
RUN apt-get update \
    && apt-get install -y --no-install-recommends rsnapshot \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint

# 0755, not 0777. An entrypoint that runs as root and that anything in the
# container may rewrite is a privilege escalation waiting for an occasion.
RUN chmod 0755 /entrypoint

ENTRYPOINT ["/entrypoint"]
CMD ["rsnapshot", "daily"]
