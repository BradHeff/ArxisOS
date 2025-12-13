#!/bin/bash
# Check osbuild-composer compose status

COMPOSE_ID="${1:-}"

if [ -z "$COMPOSE_ID" ]; then
    echo "=== All Composes ==="
    sudo composer-cli compose status
else
    echo "=== Compose $COMPOSE_ID ==="
    sudo composer-cli compose info "$COMPOSE_ID"
    echo ""
    echo "=== Logs ==="
    sudo composer-cli compose log "$COMPOSE_ID" 2>/dev/null | tail -30
fi
