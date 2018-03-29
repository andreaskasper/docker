FROM debian:stable-slim
LABEL maintainer="Andreas.Kasper@goo1.de"

ARG APT_FLAGS_COMMON="-qq -y"

RUN apt-get ${APT_FLAGS_COMMON} update && \
    apt-get ${APT_FLAGS_COMMON} install \
            mysql-server \
            nginx \
            php-fpm \
            php-gd \
            php-json \
            php-mysql \
            php-curl && \
    apt-get ${APT_FLAGS_COMMON} purge && \
    apt-get ${APT_FLAGS_COMMON} autoremove && \
    apt-get ${APT_FLAGS_COMMON} clean && \
    rm -rf /var/cache/nginx/* && \
    rm -rf /var/lib/apt/lists/*

EXPOSE 80
EXPOSE 22
EXPOSE 3306

COPY ["docker-entrypoint.sh", "/usr/bin/"]

ENTRYPOINT ["docker-entrypoint.sh"]
