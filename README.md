# docker 🐳

A handful of small, self-contained Docker images. One directory per image,
each with its own `Dockerfile` and nothing shared between them, so you can copy
a single folder out and use it without the rest.

### Status & Stats

![Last Commit](https://img.shields.io/github/last-commit/andreaskasper/docker.svg)
![Commit Activity](https://img.shields.io/github/commit-activity/m/andreaskasper/docker.svg)
[![Issues](https://img.shields.io/github/issues/andreaskasper/docker.svg)](https://github.com/andreaskasper/docker/issues)
![Repo Size](https://img.shields.io/github/repo-size/andreaskasper/docker.svg)
![Stars](https://img.shields.io/github/stars/andreaskasper/docker.svg?style=social)

---

## What is in here

| Directory | Image | What it is |
| --- | --- | --- |
| [`php/`](php/) | `andreaskasper/php:8.x-apache-github` | `php:*-apache` that clones a git repository on start and keeps it up to date. Built and published. |
| [`claude-code/`](claude-code/) | `andreaskasper/claude-code` | Anthropic's Claude Code CLI in a container. Built and published. |
| [`rsnapshot/`](rsnapshot/) | `andreaskasper/rsnapshot` | rsnapshot on Debian, driven by cron. Built and published. |
| [`openclaw/`](openclaw/) | `andreaskasper/openclaw` | OpenClaw, plus an Ollama variant under `ollama-kimik25/`. Built and published. |
| [`teamspeak/`](teamspeak/) | — | A TeamSpeak 3 server via Compose. No image of its own. |
| [`webproject/`](webproject/) | — | An all-in-one nginx + PHP-FPM + MariaDB box for local experiments. Example only, not published. |

## php — a container that deploys itself

The one worth reading about. It takes the official `php:*-apache` image and
adds a working copy of a git repository that clones itself on start, checks the
remote every few minutes, updates on a webhook, and reloads Apache when it
does. `.htaccess`, Apache modules, PHP settings and post-update hooks are all
environment variables.

```bash
docker run -d -p 8080:80 \
  -e GIT_REPO=https://github.com/you/your-site.git \
  -v site:/var/www \
  ghcr.io/andreaskasper/php:8.3-apache-github
```

Full documentation: [`php/README.md`](php/README.md).

## teamspeak

Brings up a TeamSpeak 3 server on port 9987. The admin token is printed once at
first start:

```bash
docker logs <container>
```

[![Play with Docker](https://github.com/play-with-docker/stacks/raw/cff22438cb4195ace27f9b15784bbb497047afa7/assets/images/button.png)](http://play-with-docker.com?stack=https://raw.githubusercontent.com/andreaskasper/docker/master/teamspeak/docker-compose.yml)

## How these get built

GitHub Actions builds and pushes on a change under the relevant directory, and
on `workflow_dispatch`. There is deliberately **no** `schedule:` trigger in any
workflow here: GitHub disables scheduled workflows after 60 days of repository
inactivity, and a disabled workflow refuses every dispatch with a `422` — which
is how four of these quietly stopped being rebuilt for four months. The weekly
rebuild, which exists so that base-image security patches actually reach the
published images, is triggered from outside instead.

| Workflow | Builds |
| --- | --- |
| `docker-publish-php.yml` | `andreaskasper/php` and `ghcr.io/andreaskasper/php`, PHP 8.2/8.3/8.4 |
| `docker-image.yml` | `andreaskasper/claude-code:latest` |
| `docker-public-claudecode-21104.yml` | `andreaskasper/claude-code:v2.1.104`, pinned |
| `docker-publish-openclaw.yml` | `andreaskasper/openclaw` |
| `docker-publish-rsnapshot.yml` | `andreaskasper/rsnapshot:latest` and `:debian` |

## Contributing

Issues and pull requests are welcome.

## License

MIT License, (c) Andreas Kasper. See [`LICENSE`](LICENSE).

## Support the project

[![donate via Patreon](https://img.shields.io/badge/Donate-Patreon-green.svg)](https://www.patreon.com/AndreasKasper)
[![donate via PayPal](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.me/AndreasKasper)
[![donate via Ko-fi](https://img.shields.io/badge/Donate-Ko--fi-green.svg)](https://ko-fi.com/andreaskasper)
[![Sponsors](https://img.shields.io/github/sponsors/andreaskasper)](https://github.com/sponsors/andreaskasper)

---

Made by [Andreas Kasper](https://github.com/andreaskasper)
