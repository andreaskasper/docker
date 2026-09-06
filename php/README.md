# php-apache-github 🐘

The official `php:*-apache` image, plus a git working copy that clones itself
on start and keeps itself up to date. No build step, no deploy script, no
volume full of files nobody can trace back to a commit.

```
php:8.3-apache  →  andreaskasper/php:8.3-apache-github
```

### Status & Stats

![Last Commit](https://img.shields.io/github/last-commit/andreaskasper/docker.svg)
![Commit Activity](https://img.shields.io/github/commit-activity/m/andreaskasper/docker.svg)
[![Issues](https://img.shields.io/github/issues/andreaskasper/docker.svg)](https://github.com/andreaskasper/docker/issues)
[![Docker Pulls](https://img.shields.io/docker/pulls/andreaskasper/php.svg)](https://hub.docker.com/r/andreaskasper/php)
![Stars](https://img.shields.io/github/stars/andreaskasper/docker.svg?style=social)

---

## What it does

```
┌──────────┐   push    ┌────────────┐   webhook    ┌───────────────────┐
│ your git │ ───────► │   GitHub   │ ───────────► │  container          │
│   push   │           │            │ ◄─────────── │  ┌───────────────┐  │
└──────────┘           └────────────┘   ls-remote  │  │ update loop   │  │
                                        every 5m   │  └───────┬───────┘  │
                                                   │          │          │
                                                   │     /var/www        │
                                                   │          │          │
                                                   │      Apache + PHP   │
                                                   └───────────────────┘
```

On start the container clones `GIT_REPO` into `/var/www` and hands over to
Apache. A loop then watches the ref you pointed it at — every
`GIT_POLL_INTERVAL` seconds with a single `git ls-remote`, which transfers one
line and no objects, and immediately when a webhook arrives. When the remote
moved, it fetches, resets the working copy hard, runs your hooks and reloads
Apache gracefully.

The working copy is always exactly what the ref says it is. There is no drift
to investigate, because there is nowhere for drift to accumulate.

## Where to get it

The image is published to two registries from the same build, with the same
digest and the same tags.

| Registry                  | Image                       |
| ------------------------- | --------------------------- |
| GitHub Container Registry | `ghcr.io/andreaskasper/php` |
| Docker Hub                | `andreaskasper/php`         |

`linux/amd64`. arm64 is not built: the PHP extensions have to be compiled, and
under QEMU that turns a two-minute job into a twenty-minute one for every
version in the matrix. A pipeline that slow stops being watched.

| Tag                 | Points at                       |
| ------------------- | ------------------------------- |
| `8.4-apache-github` | PHP 8.4                         |
| `8.3-apache-github` | PHP 8.3                         |
| `8.2-apache-github` | PHP 8.2                         |
| `8-apache-github`   | the newest 8.x of the three     |

Rebuilt weekly so that base-image security patches actually reach you.

## Quick start

```bash
docker run -d --name site -p 8080:80 \
  -e GIT_REPO=https://github.com/andreaskasper/example-site.git \
  -v site:/var/www \
  ghcr.io/andreaskasper/php:8.3-apache-github
```

That is the whole configuration for a public repository. If the repository has
an `html/` directory it is served immediately, because that is where the base
image's DocumentRoot already points. If it has `public/` or `web/` instead,
that is detected and used. Anything else: set `DOCUMENT_ROOT` yourself.

A full example with Traefik, a private repository, a webhook and Composer is
in [`docker-compose.example.yml`](docker-compose.example.yml).

**Use a volume for `/var/www`.** Not for the data — the data is in git — but
so that a restart during a GitHub outage still finds a working copy to serve.
Without one, a five-minute outage plus an unlucky restart is a blank site.

## Configuration

### The repository

| Variable | Default | Purpose |
| --- | --- | --- |
| `GIT_REPO` | — | **Required.** HTTPS or SSH URL. |
| `GIT_REF` | the remote's default branch | Branch, tag or commit SHA. A bare SHA pins the deployment and disables polling. |
| `GIT_TARGET` | `/var/www` | Where the working copy goes. |
| `GIT_DEPTH` | `1` | Shallow. `0` fetches the full history. |
| `GIT_POLL_INTERVAL` | `300` | Seconds between remote checks. `0` disables polling and leaves only the webhook. |
| `GIT_SUBMODULES` | `false` | Initialise and update submodules. |
| `GIT_CLONE_RETRIES` | `5` | Attempts on the very first clone before giving up, with exponential backoff. |

### Credentials

| Variable | Default | Purpose |
| --- | --- | --- |
| `GIT_TOKEN` / `GIT_TOKEN_FILE` | — | Deploy token or PAT for HTTPS. |
| `GIT_USERNAME` | `x-access-token` | Username that goes with it. GitHub ignores it, GitLab and Gitea do not. |
| `GIT_SSH_KEY` / `GIT_SSH_KEY_FILE` | — | Private deploy key, for SSH URLs. |

Prefer the `_FILE` forms with Docker secrets. A value passed as `-e` shows up
in `docker inspect` and in your shell history; a file does not.

### The working tree

| Variable | Default | Purpose |
| --- | --- | --- |
| `GIT_CLEAN` | `true` | Remove untracked files after every update. |
| `GIT_CLEAN_EXCLUDE` | — | Space-separated patterns `git clean` must leave alone. |
| `GIT_CHOWN` | `true` | Hand the working copy to `www-data` after every update. |

`GIT_CLEAN` deletes untracked files, and that is the point: a file nobody can
attribute to a commit has no business in a deployment. It does **not** delete
ignored files. Put your uploads and caches in `.gitignore` — which they should
be in anyway — and they survive every update without any configuration:

```gitignore
html/uploads/
var/cache/
```

`GIT_CLEAN_EXCLUDE` is the escape hatch for the case where that is not
possible.

### Apache

| Variable | Default | Purpose |
| --- | --- | --- |
| `DOCUMENT_ROOT` | auto | Unset: `html/`, then `public/`, `web/`, `htdocs/`, `www/`, `public_html/`, then the repository root. |
| `APACHE_MODS` | `rewrite headers` | Space-separated, enabled with `a2enmod` at start. |
| `APACHE_ALLOW_OVERRIDE` | `All` | `.htaccess` does nothing without this. |
| `APACHE_SERVER_NAME` | `localhost` | Sets `ServerName`. |
| `TRUSTED_PROXIES` | — | Space-separated CIDRs. Turns on `mod_remoteip`. |

`rewrite` on its own is not enough for `.htaccess`: the base image ships
`AllowOverride None`, so the rules are read and silently ignored. That is why
`APACHE_ALLOW_OVERRIDE` exists and why it defaults to `All`.

Behind Traefik, nginx or Cloudflare, set `TRUSTED_PROXIES` (`172.16.0.0/12`
covers the usual Docker networks). Without it every log line and every
`$_SERVER['REMOTE_ADDR']` reads as the proxy's address, which quietly breaks
rate limiting, fail2ban and any ban list you build on top.

### PHP

| Variable | Default | Purpose |
| --- | --- | --- |
| `PHP_INI_PRESET` | `production` | `production`, `development` or `none`. |
| `PHP_MEMORY_LIMIT` | php default | |
| `PHP_UPLOAD_MAX_FILESIZE` | php default | |
| `PHP_POST_MAX_SIZE` | php default | Raise this together with the one above, or large uploads fail without an error anyone can find. |
| `PHP_MAX_EXECUTION_TIME` | php default | |
| `PHP_TIMEZONE` | php default | |
| `PHP_ERROR_REPORTING`, `PHP_DISPLAY_ERRORS` | preset default | |

Compiled in and enabled: `opcache`, `pdo_mysql`, `mysqli`, `gd`, `zip`,
`intl`, `mbstring`, `bcmath`, `exif`. The stock `php:*-apache` image has
almost none of these, which is the first wall every real project hits.

Extensions are fixed at build time on purpose. Installing them at start would
mean every container boot needs a compiler and a working network — and a
restart at three in the morning would be a coin flip.

### After an update

| Variable | Default | Purpose |
| --- | --- | --- |
| `COMPOSER_INSTALL` | `false` | Runs `composer install --no-dev --optimize-autoloader`. |
| `POST_UPDATE_CMD` | — | A shell one-liner. |

Anything longer belongs in the repository, at `.docker/post-update.sh`. If
that file exists it is executed after every update, from the repository root:

```bash
#!/usr/bin/env bash
set -e
php bin/console cache:clear
php bin/console doctrine:migrations:migrate --no-interaction
```

Hooks and Composer run as `www-data`, not as root. A repository you deploy can
change; the account it runs as should not be the one that can rewrite the
container.

### Webhook

| Variable | Default | Purpose |
| --- | --- | --- |
| `WEBHOOK_SECRET` / `WEBHOOK_SECRET_FILE` | — | Unset means the endpoint does not exist. |
| `WEBHOOK_PATH` | `/_git/webhook` | |
| `WEBHOOK_DEBOUNCE` | `5` | Seconds to wait so that a burst of pushes causes one update. |

Point a GitHub webhook at `https://your.site/_git/webhook`, content type
`application/json`, with the same secret. The signature is verified with
`hash_hmac` and compared in constant time. GitHub's initial `ping` is answered
without triggering anything, so the delivery goes green straight away.

For anything that cannot sign a payload — curl, n8n, a CI job:

```bash
curl -X POST -H "Authorization: Bearer $WEBHOOK_SECRET" \
  https://your.site/_git/webhook
```

The endpoint runs no git commands. It writes one file into a spool directory
that only the update loop reads, so the worst an attacker who guesses the
secret can do is make the container check for updates.

## Operating it

```bash
docker exec site git-sync            # update now
docker exec site git-sync --force    # re-apply the current ref
docker exec site cat /run/php-github/status
docker logs -f site
```

The status file is what the `HEALTHCHECK` reads:

```json
{"state":"ok","sha":"1a2b3c4d…","message":"synchronised","at":"2026-09-06T09:14:02Z"}
```

| State | Meaning | Healthy |
| --- | --- | :---: |
| `ok` | Working copy matches the remote | ● |
| `degraded` | The remote was unreachable; an older working copy is being served | ● |
| `error` | Nothing to serve | |

`degraded` is deliberately still healthy. GitHub being down is not a reason to
pull a working site out of a load balancer.

## What it will not do

- **It never fails over to an empty site.** If a working copy exists, it is
  served, whatever the remote is doing. Only a first clone with nothing to
  fall back on exits non-zero, and only after `GIT_CLONE_RETRIES` attempts.
- **It never clones over somebody's data.** A `GIT_TARGET` that is not empty
  and not a git working copy is refused, not overwritten.
- **It does not put the token where the application can read it.** Git
  credentials are passed through `GIT_ASKPASS` and a root-only file, never in
  the remote URL and never in the environment Apache inherits. Without that
  last part, a repository containing `phpinfo()` would print your deploy token
  to anyone who asked.
- **It does not serve dotfiles.** `.git`, `.env` and `.docker` are denied
  wherever `DOCUMENT_ROOT` happens to point. `/.well-known/` stays reachable
  for ACME.
- **It does not terminate TLS.** Put a reverse proxy in front of it.

The webhook secret is readable by `www-data`, because the script that verifies
it runs as `www-data`. The git credential is not. That split is intentional:
one of the two is worth stealing.

## Building and testing

```bash
docker build --build-arg PHP_VERSION=8.3 -t php-github:local php/
./php/test/sync-test.sh
```

`sync-test.sh` runs the real synchronisation logic against a throwaway local
repository — clone, update, reset, clean, exclude patterns, tags, unreachable
refs, occupied directories. No Docker, no network, no root, so it runs in CI
before the image is built. It does not cover Apache, the webhook over HTTP, or
running hooks as `www-data`; those need a container.

## Project layout

```
php/
├── Dockerfile
├── README.md
├── docker-compose.example.yml
├── bin/
│   ├── entrypoint.sh        # boot: credentials, first clone, Apache, PHP, handover
│   ├── git-sync.sh          # one synchronisation pass; also the `git-sync` command
│   ├── git-sync-loop.sh     # the clock and the webhook spool
│   └── healthcheck.sh
├── lib/
│   └── common.sh            # logging, defaults, config file, credential plumbing
├── webhook/
│   └── index.php            # signature check, then one touch(). No git.
└── test/
    └── sync-test.sh
```

## License

MIT License, (c) 2026 Andreas Kasper. See [`LICENSE`](../LICENSE).

## Support the project

[![donate via Patreon](https://img.shields.io/badge/Donate-Patreon-green.svg)](https://www.patreon.com/AndreasKasper)
[![donate via PayPal](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.me/AndreasKasper)
[![donate via Ko-fi](https://img.shields.io/badge/Donate-Ko--fi-green.svg)](https://ko-fi.com/andreaskasper)
[![Sponsors](https://img.shields.io/github/sponsors/andreaskasper)](https://github.com/sponsors/andreaskasper)

---

Made by [Andreas Kasper](https://github.com/andreaskasper)
