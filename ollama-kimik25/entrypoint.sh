#!/bin/bash
set -e

echo "Starting Ollama with Kimi K2.5 model..."
echo "Model is pre-installed and ready to use!"
echo ""
echo "API available at: http://localhost:11434"
echo "Try: ollama run kimi-k2.5:cloud"
echo ""

# Start Ollama server
exec ollama serve