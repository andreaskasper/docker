<?php

declare(strict_types=1);

/**
 * Update trigger for the php-*-apache-github image.
 *
 * Mounted by the entrypoint at WEBHOOK_PATH, and only when WEBHOOK_SECRET is
 * set — without a secret the Alias is never written and this file is not
 * reachable at all.
 *
 * It does not run git. It writes one file into a spool directory; the update
 * loop, which runs as root, notices it and does the work. Nothing an attacker
 * could reach here executes anything.
 */

const SECRET_FILE  = '/run/php-github/webhook-secret';
const TRIGGER_FILE = '/run/php-github/spool/trigger';
const MAX_BODY     = 1048576; // 1 MiB. Payloads are never read, only signed.

/**
 * @param int    $status
 * @param string $state
 * @param string $detail
 */
function respond(int $status, string $state, string $detail = ''): never
{
    http_response_code($status);
    header('Content-Type: application/json');
    header('Cache-Control: no-store');
    echo json_encode(
        array_filter(['status' => $state, 'detail' => $detail]),
        JSON_UNESCAPED_SLASHES
    ), "\n";
    exit;
}

$secret = is_readable(SECRET_FILE) ? trim((string) file_get_contents(SECRET_FILE)) : '';

// No secret, no endpoint. A 404 rather than a 403, because the difference
// tells a scanner whether this image is in use.
if ($secret === '') {
    respond(404, 'not found');
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    header('Allow: POST');
    respond(405, 'method not allowed');
}

$body = (string) file_get_contents('php://input', false, null, 0, MAX_BODY);

$authorised = false;

// GitHub, Gitea and Forgejo sign the body. This is the path a real webhook takes.
$signature = $_SERVER['HTTP_X_HUB_SIGNATURE_256'] ?? '';
if ($signature !== '') {
    $expected   = 'sha256=' . hash_hmac('sha256', $body, $secret);
    $authorised = hash_equals($expected, $signature);
} else {
    // Everything else: a bearer token, for curl, n8n and CI.
    $presented = '';
    $header    = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (stripos($header, 'Bearer ') === 0) {
        $presented = substr($header, 7);
    } elseif (isset($_SERVER['HTTP_X_WEBHOOK_TOKEN'])) {
        $presented = (string) $_SERVER['HTTP_X_WEBHOOK_TOKEN'];
    }
    if ($presented !== '') {
        $authorised = hash_equals($secret, $presented);
    }
}

if (!$authorised) {
    error_log(sprintf(
        'php-github webhook: rejected %s from %s',
        $signature !== '' ? 'bad signature' : 'bad or missing token',
        $_SERVER['REMOTE_ADDR'] ?? '?'
    ));
    respond(403, 'forbidden');
}

// GitHub sends this once when the webhook is created. Answering it without
// kicking off a pull makes the "Recent Deliveries" page green immediately.
if (($_SERVER['HTTP_X_GITHUB_EVENT'] ?? '') === 'ping') {
    respond(200, 'pong');
}

if (@touch(TRIGGER_FILE) === false) {
    error_log('php-github webhook: cannot write ' . TRIGGER_FILE);
    respond(500, 'cannot queue update');
}

respond(202, 'queued');
