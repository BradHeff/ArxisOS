#!/bin/bash
set -euo pipefail

BUILD_DIR="/home/bheffernan/arxisos-build"
BLUEPRINT="arxisos-kde"
IMAGE_TYPE="workstation-live-installer"
VERSION="1.0"

echo "=== ArxisOS Build Script (osbuild-composer) ==="
echo "Building ArxisOS $VERSION"
echo "Started: $(date)"
echo ""

# Ensure osbuild-composer is running
if ! systemctl is-active --quiet osbuild-composer.socket; then
    echo "Starting osbuild-composer..."
    sudo systemctl start osbuild-composer.socket
fi

# Push latest blueprint
echo "Pushing blueprint..."
sudo composer-cli blueprints push "$BUILD_DIR/blueprints/arxisos-kde.toml"

# Start compose
echo "Starting compose..."
COMPOSE_OUTPUT=$(sudo composer-cli compose start "$BLUEPRINT" "$IMAGE_TYPE" 2>&1)
echo "$COMPOSE_OUTPUT"

# Extract compose ID
COMPOSE_ID=$(echo "$COMPOSE_OUTPUT" | grep -oP 'Compose \K[a-f0-9-]+')

if [ -z "$COMPOSE_ID" ]; then
    echo "ERROR: Failed to start compose"
    exit 1
fi

echo ""
echo "Compose ID: $COMPOSE_ID"
echo ""
echo "Monitor progress with:"
echo "  sudo composer-cli compose status"
echo "  sudo composer-cli compose log $COMPOSE_ID"
echo ""
echo "When complete, download with:"
echo "  sudo composer-cli compose image $COMPOSE_ID"
echo ""

# Optionally wait for completion
if [ "${1:-}" = "--wait" ]; then
    echo "Waiting for compose to complete..."
    while true; do
        STATUS=$(sudo composer-cli compose status | grep "$COMPOSE_ID" | awk '{print $2}')
        case "$STATUS" in
            FINISHED)
                echo ""
                echo "=== Build Complete ==="
                echo "Downloading ISO..."
                cd "$BUILD_DIR"
                sudo composer-cli compose image "$COMPOSE_ID"
                ISO_FILE=$(ls -1 *.iso 2>/dev/null | head -1)
                if [ -n "$ISO_FILE" ]; then
                    echo "ISO: $BUILD_DIR/$ISO_FILE"
                    echo "Size: $(du -h "$ISO_FILE" | cut -f1)"
                fi
                exit 0
                ;;
            FAILED)
                echo ""
                echo "=== Build FAILED ==="
                sudo composer-cli compose log "$COMPOSE_ID" | tail -50
                exit 1
                ;;
            *)
                echo -n "."
                sleep 30
                ;;
        esac
    done
fi

echo "Build queued. Use --wait flag to wait for completion."
exit 0
