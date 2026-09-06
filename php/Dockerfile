# syntax=docker/dockerfile:1
#
# php:<version>-apache, plus a git working copy that keeps itself up to date.
#
#   docker build --build-arg PHP_VERSION=8.3 -t andreaskasper/php:8.3-apache-github .
#
# Everything below is pinned on purpose. An unpinned tool in a weekly rebuild
# is a build that changes underneath you without a commit to blame.

ARG PHP_VERSION=8.3
ARG COMPOSER_VERSION=2.8

FROM composer:${COMPOSER_VERSION} AS composer

FROM php:${PHP_VERSION}-apache

# Pinned release of mlocati/docker-php-extension-installer, verified by checksum.
ARG IPE_VERSION=2.11.12
ARG IPE_SHA256=7c133ae4b9490d912287188c62ea570729cfa74f0ea357e4be672ce696b4aa29
ARG PHP_EXTENSIONS="opcache pdo_mysql mysqli gd zip intl mbstring bcmath exif"

LABEL maintainer="Andreas.Kasper@goo1.de" \
      org.opencontainers.image.title="php-apache-github" \
      org.opencontainers.image.description="The official php:*-apache image, plus a git working copy that clones on start and keeps itself up to date." \
      org.opencontainers.image.source="https://github.com/andreaskasper/docker" \
      org.opencontainers.image.documentation="https://github.com/andreaskasper/docker/tree/master/php" \
      org.opencontainers.image.licenses="MIT"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        openssh-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/download/${IPE_VERSION}/install-php-extensions /usr/local/bin/install-php-extensions

# shellcheck disable=SC2086
RUN echo "${IPE_SHA256}  /usr/local/bin/install-php-extensions" | sha256sum -c - \
    && install-php-extensions ${PHP_EXTENSIONS} \
    && rm -f /usr/local/bin/install-php-extensions

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

ENV COMPOSER_HOME=/opt/composer \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1

# /var/www/html ships with the base image and would make `git clone /var/www`
# fail on a non-empty directory. The clone brings its own html/ — or
# DOCUMENT_ROOT points somewhere else.
#
# safe.directory: the working copy is chowned to www-data while git runs as
# root, which git otherwise refuses as "dubious ownership".
RUN a2enmod rewrite headers remoteip \
    && rm -rf /var/www/html \
    && mkdir -p /var/www /opt/webhook /opt/composer \
    && chown www-data:www-data /opt/composer \
    && git config --system --add safe.directory '*'

COPY lib/common.sh /usr/local/lib/php-github/common.sh
COPY bin/entrypoint.sh /usr/local/bin/php-github-entrypoint
COPY bin/git-sync.sh /usr/local/bin/git-sync
COPY bin/git-sync-loop.sh /usr/local/bin/git-sync-loop
COPY bin/healthcheck.sh /usr/local/bin/php-github-healthcheck
COPY webhook/index.php /opt/webhook/index.php

RUN chmod 0755 \
        /usr/local/bin/php-github-entrypoint \
        /usr/local/bin/git-sync \
        /usr/local/bin/git-sync-loop \
        /usr/local/bin/php-github-healthcheck \
    && chmod 0644 /usr/local/lib/php-github/common.sh /opt/webhook/index.php

ENV GIT_TARGET=/var/www \
    GIT_DEPTH=1 \
    GIT_POLL_INTERVAL=300 \
    GIT_CLEAN=true \
    GIT_SUBMODULES=false \
    GIT_CHOWN=true \
    GIT_CLONE_RETRIES=5 \
    APACHE_MODS="rewrite headers" \
    APACHE_ALLOW_OVERRIDE=All \
    PHP_INI_PRESET=production \
    COMPOSER_INSTALL=false \
    WEBHOOK_PATH=/_git/webhook \
    WEBHOOK_DEBOUNCE=5

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD /usr/local/bin/php-github-healthcheck

ENTRYPOINT ["/usr/local/bin/php-github-entrypoint"]
CMD ["apache2-foreground"]
