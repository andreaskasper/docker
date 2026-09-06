#!/usr/bin/env bash
#
# nginx runs in the foreground as PID 1 so that `docker stop` reaches it.
# MariaDB and php-fpm are started behind it.

set -Eeuo pipefail

# The FPM socket carries the PHP version in its name, and the version changes
# with the Debian release. The nginx config points at a stable path instead.
find_socket() {
    find /run/php /var/run/php -name 'php*-fpm.sock' ! -name 'php-fpm.sock' -print -quit 2> /dev/null || true
}

service mariadb start

# An `if` rather than `[[ ]] && cmd`: with set -e, a && list that fails on its
# last loop iteration is exactly the kind of thing that ends a script early.
for init in /etc/init.d/php*-fpm; do
    if [[ -x "${init}" ]]; then
        "${init}" start
    fi
done

mkdir -p /run/php

# The socket only exists once php-fpm has finished starting.
socket=""
for _ in {1..20}; do
    socket="$(find_socket)"
    [[ -n "${socket}" ]] && break
    sleep 0.5
done

if [[ -n "${socket}" ]]; then
    ln -sf "${socket}" /run/php/php-fpm.sock
else
    echo "warning: no php-fpm socket found, PHP will not be executed" >&2
fi

exec nginx -g "daemon off;"
