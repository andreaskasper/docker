#!/bin/bash
set -e

# Fix permissions for the .openclaw directory if needed
if [ -d "$HOME/.openclaw" ]; then
    if [ ! -w "$HOME/.openclaw" ]; then
        echo "Fixing permissions for $HOME/.openclaw..."
        sudo chown -R openclaw:openclaw "$HOME/.openclaw"
    fi
fi

# Execute the command passed to the container
exec "$@"