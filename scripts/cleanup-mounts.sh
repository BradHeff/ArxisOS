#!/bin/bash
# Emergency cleanup script for ArxisOS build
# Run this if apply-branding.sh failed and left mounts behind

WORK_DIR="/var/tmp/arxisos-remaster"

echo "=== ArxisOS Emergency Mount Cleanup ==="
echo "Work directory: $WORK_DIR"
echo ""

# Show current mounts related to work directory
echo "Current mounts involving $WORK_DIR:"
mount | grep "$WORK_DIR" || echo "  (none found)"
echo ""

# Unmount bind mounts first (in reverse order)
echo "Unmounting bind mounts..."
for mount_point in run sys proc dev; do
    if mount | grep -q "$WORK_DIR/squashfs/rootfs/$mount_point"; then
        echo "  Unmounting $WORK_DIR/squashfs/rootfs/$mount_point"
        sudo umount -l "$WORK_DIR/squashfs/rootfs/$mount_point" 2>/dev/null
    fi
    if mount | grep -q "$WORK_DIR/squashfs/$mount_point"; then
        echo "  Unmounting $WORK_DIR/squashfs/$mount_point"
        sudo umount -l "$WORK_DIR/squashfs/$mount_point" 2>/dev/null
    fi
done

# Unmount rootfs
if mount | grep -q "$WORK_DIR/squashfs/rootfs"; then
    echo "  Unmounting $WORK_DIR/squashfs/rootfs"
    sudo umount -l "$WORK_DIR/squashfs/rootfs" 2>/dev/null
fi

# Unmount squashfs
if mount | grep -q "$WORK_DIR/squashfs"; then
    echo "  Unmounting $WORK_DIR/squashfs"
    sudo umount -l "$WORK_DIR/squashfs" 2>/dev/null
fi

# Unmount ISO
if mount | grep -q "$WORK_DIR/iso"; then
    echo "  Unmounting $WORK_DIR/iso"
    sudo umount -l "$WORK_DIR/iso" 2>/dev/null
fi

# Kill any processes using the work directory
echo ""
echo "Checking for processes using $WORK_DIR..."
if sudo fuser -v "$WORK_DIR" 2>/dev/null; then
    echo "Killing processes..."
    sudo fuser -km "$WORK_DIR" 2>/dev/null || true
fi

# Detach loop devices
echo ""
echo "Detaching loop devices..."
for loop in $(losetup -a 2>/dev/null | grep "$WORK_DIR" | cut -d: -f1); do
    echo "  Detaching $loop"
    sudo losetup -d "$loop" 2>/dev/null || true
done

# Final check
echo ""
echo "Remaining mounts:"
mount | grep "$WORK_DIR" || echo "  (none - cleanup successful)"

echo ""
echo "Remaining loop devices:"
losetup -a 2>/dev/null | grep "$WORK_DIR" || echo "  (none - cleanup successful)"

# Optional: remove work directory
if [ "${1:-}" = "--remove" ]; then
    echo ""
    echo "Removing work directory..."
    sudo rm -rf "$WORK_DIR"
    echo "Done."
else
    echo ""
    echo "Work directory NOT removed. To remove, run: $0 --remove"
fi
