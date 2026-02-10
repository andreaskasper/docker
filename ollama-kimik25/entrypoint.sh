#!/bin/bash
set -e

echo "========================================"
echo "OpenClaw + Ollama with Kimi K2.5"
echo "========================================"
echo ""
echo "Starting services..."
echo "  - OpenClaw Gateway on port 18789"
echo "  - Ollama API on port 11434"
echo "  - Kimi K2.5 model pre-installed"
echo ""
echo "OpenClaw WebUI: http://localhost:18789"
echo "Ollama API: http://localhost:11434"
echo ""

# Fix permissions for openclaw user
if [ -d "/home/openclaw/.openclaw" ]; then
    sudo chown -R openclaw:openclaw /home/openclaw/.openclaw 2>/dev/null || true
fi

# Start supervisord to manage both services
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf