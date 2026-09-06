FROM debian:stable-slim
LABEL maintainer="Andreas.Kasper@goo1.de"

ARG APT_FLAGS_COMMON="-qq -y"

# mariadb-server, not mysql-server: Debian has not shipped a package by that
# name since stretch, so this image never built.
#
# php-json is gone too, and correctly so — JSON has been compiled into PHP
# since 8.0.
RUN apt-get ${APT_FLAGS_COMMON} update && \
    apt-get ${APT_FLAGS_COMMON} install --no-install-recommends \
            mariadb-server \
            nginx \
            php-fpm \
            php-gd \
            php-mysql \
            php-curl \
            php-mbstring \
            php-xml && \
    apt-get ${APT_FLAGS_COMMON} autoremove && \
    apt-get ${APT_FLAGS_COMMON} clean && \
    rm -rf /var/cache/nginx/* && \
    rm -rf /var/lib/apt/lists/*

# The stock nginx site serves .php as a download because nothing hands it to
# php-fpm. This one does.
COPY ["nginx-default.conf", "/etc/nginx/sites-available/default"]
COPY ["docker-entrypoint.sh", "/usr/local/bin/"]
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80
EXPOSE 3306

ENTRYPOINT ["docker-entrypoint.sh"]
