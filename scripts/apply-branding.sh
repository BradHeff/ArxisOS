#!/bin/bash
set -euo pipefail

# Apply ArxisOS branding to a Fedora live ISO

# Cleanup function for error handling - handles ALL exit scenarios
cleanup_mounts() {
    local exit_code=$?
    local work_dir="/var/tmp/arxisos-remaster"

    # Only show error message if exit code is non-zero
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "ERROR: Script failed (exit code: $exit_code). Cleaning up mounts..."
    fi

    # Unmount bind mounts first (in reverse order of mounting)
    # These are critical - leaving these mounted causes /dev/null errors!
    for mount_point in run sys proc dev; do
        # Try both possible rootfs locations
        sudo umount -l "$work_dir/squashfs/rootfs/$mount_point" 2>/dev/null || true
        sudo umount -l "$work_dir/squashfs/$mount_point" 2>/dev/null || true
    done

    # Small delay to ensure mounts are released
    sleep 1

    # Unmount rootfs.img if mounted
    sudo umount -l "$work_dir/squashfs/rootfs" 2>/dev/null || true

    # Unmount squashfs
    sudo umount -l "$work_dir/squashfs" 2>/dev/null || true

    # Unmount ISO
    sudo umount -l "$work_dir/iso" 2>/dev/null || true

    # Detach any loop devices associated with work_dir
    for loop in $(losetup -a 2>/dev/null | grep "$work_dir" | cut -d: -f1); do
        sudo losetup -d "$loop" 2>/dev/null || true
    done

    if [ $exit_code -ne 0 ]; then
        echo "Cleanup complete."
        exit $exit_code
    fi
}
# Trap ALL exit scenarios: errors, normal exit, interrupt, terminate
trap cleanup_mounts EXIT
trap 'exit 1' INT TERM
# This script modifies the ISO to include custom Plymouth, GRUB, wallpaper, etc.

BUILD_DIR="/home/bheffernan/arxisos-build"
BRANDING_DIR="$BUILD_DIR/branding"
WORK_DIR="/var/tmp/arxisos-remaster"

# ISO volume label - must match GRUB CDLABEL exactly
ISO_LABEL="ArxisOS-1-0-x86_64"

ISO_INPUT="${1:-}"
# Ensure output path is absolute
if [ -n "${2:-}" ]; then
    case "$2" in
        /*) ISO_OUTPUT="$2" ;;  # Already absolute
        *)  ISO_OUTPUT="$BUILD_DIR/$2" ;;  # Make absolute
    esac
else
    ISO_OUTPUT="$BUILD_DIR/ArxisOS-1.0-x86_64.iso"
fi

if [ -z "$ISO_INPUT" ]; then
    echo "Usage: $0 <input-iso> [output-iso]"
    echo "Example: $0 fedora-live.iso ArxisOS-1.0.iso"
    exit 1
fi

if [ ! -f "$ISO_INPUT" ]; then
    echo "ERROR: Input ISO not found: $ISO_INPUT"
    exit 1
fi

echo "=== ArxisOS Branding Application ==="
echo "Input:  $ISO_INPUT"
echo "Output: $ISO_OUTPUT"
echo ""

# Clean up previous work - unmount any existing mounts first (prevents /dev/null errors)
echo "Cleaning up previous work..."
# First unmount bind mounts (critical - these cause /dev/null errors if left mounted)
for mount_point in run sys proc dev; do
    sudo umount -l "$WORK_DIR/squashfs/rootfs/$mount_point" 2>/dev/null || true
    sudo umount -l "$WORK_DIR/squashfs/$mount_point" 2>/dev/null || true
done
# Then unmount filesystems
sudo umount -l "$WORK_DIR/squashfs/rootfs" 2>/dev/null || true
sudo umount -l "$WORK_DIR/squashfs" 2>/dev/null || true
sudo umount -l "$WORK_DIR/iso" 2>/dev/null || true
# Detach any loop devices from previous runs
for loop in $(losetup -a 2>/dev/null | grep "$WORK_DIR" | cut -d: -f1); do
    sudo losetup -d "$loop" 2>/dev/null || true
done
sleep 1
sudo rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"/{iso,squashfs}

# Mount the ISO
echo "Mounting ISO..."
sudo mount -o loop "$ISO_INPUT" "$WORK_DIR/iso"

# Copy ISO contents (except squashfs)
echo "Copying ISO contents..."
mkdir -p "$WORK_DIR/new_iso"
sudo rsync -a --exclude='LiveOS/squashfs.img' "$WORK_DIR/iso/" "$WORK_DIR/new_iso/"

# Fix .discinfo file
if [ -f "$WORK_DIR/new_iso/.discinfo" ]; then
    echo "Updating .discinfo..."
    sudo tee "$WORK_DIR/new_iso/.discinfo" > /dev/null << DISCINFO_EOF
$(date +%s.%N)
ArxisOS 1.0
x86_64
DISCINFO_EOF
fi

# Fix GRUB configuration files
echo "Fixing GRUB boot menu entries..."
echo "Using ISO label: $ISO_LABEL"

# Copy GRUB theme to ISO boot directories
echo "Copying GRUB theme to ISO..."
if [ -d "$BRANDING_DIR/grub/arxisos" ]; then
    # Copy to EFI boot theme directory
    sudo mkdir -p "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/grub/arxisos/"* "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos/"

    # Copy to boot/grub2 for BIOS boot
    sudo mkdir -p "$WORK_DIR/new_iso/boot/grub2/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/grub/arxisos/"* "$WORK_DIR/new_iso/boot/grub2/themes/arxisos/"
    echo "  - GRUB theme copied to ISO"

    # Convert PNG files to GRUB-compatible format (24-bit RGB, no alpha channel)
    # GRUB has issues with 32-bit RGBA PNGs - causes garbled display
    echo "  - Converting PNG files to GRUB-compatible format..."
    if command -v convert &> /dev/null; then
        for THEME_DIR in "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos" "$WORK_DIR/new_iso/boot/grub2/themes/arxisos"; do
            find "$THEME_DIR" -name "*.png" -type f | while read -r png_file; do
                # Convert to 24-bit RGB (remove alpha channel, flatten to black background for transparency)
                sudo convert "$png_file" -background black -alpha remove -alpha off -depth 8 "$png_file.tmp" 2>/dev/null && \
                    sudo mv "$png_file.tmp" "$png_file" || \
                    sudo rm -f "$png_file.tmp"
            done
        done
        echo "    PNG files converted to 24-bit RGB"
    else
        echo "    Warning: ImageMagick not found, PNG files may cause display issues"
    fi

    # Generate GRUB font files for ISO boot
    echo "  - Generating GRUB fonts for ISO theme..."
    GRUB_MKFONT=""
    if command -v grub2-mkfont &> /dev/null; then
        GRUB_MKFONT="grub2-mkfont"
    elif command -v grub-mkfont &> /dev/null; then
        GRUB_MKFONT="grub-mkfont"
    fi

    if [ -n "$GRUB_MKFONT" ]; then
        DEJAVU_REGULAR=$(find /usr/share/fonts -name "DejaVuSans.ttf" 2>/dev/null | head -1)
        DEJAVU_BOLD=$(find /usr/share/fonts -name "DejaVuSans-Bold.ttf" 2>/dev/null | head -1)
        DEJAVU_MONO=$(find /usr/share/fonts -name "DejaVuSansMono.ttf" 2>/dev/null | head -1)

        # Generate fonts for both EFI and BIOS theme directories
        for THEME_DIR in "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos" "$WORK_DIR/new_iso/boot/grub2/themes/arxisos"; do
            if [ -n "$DEJAVU_REGULAR" ]; then
                sudo $GRUB_MKFONT -s 11 -o "$THEME_DIR/dejavu_sans_11.pf2" "$DEJAVU_REGULAR" 2>/dev/null || true
                sudo $GRUB_MKFONT -s 16 -o "$THEME_DIR/dejavu_sans_16.pf2" "$DEJAVU_REGULAR" 2>/dev/null || true
            fi
            if [ -n "$DEJAVU_BOLD" ]; then
                sudo $GRUB_MKFONT -s 16 -o "$THEME_DIR/dejavu_sans_bold_16.pf2" "$DEJAVU_BOLD" 2>/dev/null || true
                sudo $GRUB_MKFONT -s 24 -o "$THEME_DIR/dejavu_sans_bold_24.pf2" "$DEJAVU_BOLD" 2>/dev/null || true
            fi
            if [ -n "$DEJAVU_MONO" ]; then
                sudo $GRUB_MKFONT -s 14 -o "$THEME_DIR/dejavu_mono_14.pf2" "$DEJAVU_MONO" 2>/dev/null || true
            fi
        done
        echo "    Font files generated for ISO"
    fi

    # Copy unicode.pf2 as fallback
    for THEME_DIR in "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos" "$WORK_DIR/new_iso/boot/grub2/themes/arxisos"; do
        if [ -f /usr/share/grub/unicode.pf2 ]; then
            sudo cp /usr/share/grub/unicode.pf2 "$THEME_DIR/" 2>/dev/null || true
        elif [ -f /boot/grub2/fonts/unicode.pf2 ]; then
            sudo cp /boot/grub2/fonts/unicode.pf2 "$THEME_DIR/" 2>/dev/null || true
        fi
    done
fi

# Fix EFI GRUB config
if [ -f "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg" ]; then
    # Replace the CDLABEL in kernel boot parameters
    sudo sed -i \
        -e "s/CDLABEL=Fedora-[0-9]*-[A-Za-z]*-x86_64/CDLABEL=${ISO_LABEL}/g" \
        -e "s/-l 'Fedora-[0-9]*-[A-Za-z]*-x86_64'/-l '${ISO_LABEL}'/g" \
        -e "s/Install Fedora [0-9]*/Start ArxisOS/g" \
        -e "s/Test this media & install Fedora [0-9]*/Test Media \& Start ArxisOS/g" \
        -e "s/Install Fedora [0-9]* in basic graphics mode/Start ArxisOS (Basic Graphics)/g" \
        -e "s/Rescue a Fedora system/Rescue ArxisOS System/g" \
        -e "s/--class fedora/--class arxisos/g" \
        "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"

    # Add selinux=0 to kernel boot parameters to disable SELinux completely
    sudo sed -i \
        -e '/^\s*linux/s/$/ selinux=0/' \
        -e '/^\s*linuxefi/s/$/ selinux=0/' \
        "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"

    # Add GRUB theme configuration at the beginning of the file
    if ! grep -q "set theme=" "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"; then
        # Create temp file with theme config prepended
        # Use ($root) to reference the boot device (ISO filesystem)
        {
            echo '# ArxisOS GRUB Theme Configuration'
            echo 'insmod all_video'
            echo 'insmod gfxterm'
            echo 'insmod gfxmenu'
            echo 'insmod png'
            echo 'set gfxmode=auto'
            echo 'set gfxpayload=keep'
            echo 'terminal_output gfxterm'
            echo ''
            echo '# Load fonts for theme'
            echo 'if [ -f ($root)/EFI/BOOT/themes/arxisos/dejavu_sans_16.pf2 ]; then'
            echo '    loadfont ($root)/EFI/BOOT/themes/arxisos/dejavu_sans_11.pf2'
            echo '    loadfont ($root)/EFI/BOOT/themes/arxisos/dejavu_sans_16.pf2'
            echo '    loadfont ($root)/EFI/BOOT/themes/arxisos/dejavu_sans_bold_16.pf2'
            echo '    loadfont ($root)/EFI/BOOT/themes/arxisos/dejavu_sans_bold_24.pf2'
            echo '    loadfont ($root)/EFI/BOOT/themes/arxisos/dejavu_mono_14.pf2'
            echo 'elif [ -f ($root)/EFI/BOOT/themes/arxisos/unicode.pf2 ]; then'
            echo '    loadfont ($root)/EFI/BOOT/themes/arxisos/unicode.pf2'
            echo 'fi'
            echo ''
            echo 'set theme=($root)/EFI/BOOT/themes/arxisos/theme.txt'
            echo 'export theme'
            echo ''
            cat "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"
        } | sudo tee "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg.new" > /dev/null
        sudo mv "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg.new" "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"
    fi
    echo "  - Updated EFI GRUB config with theme"
fi

# Fix BIOS GRUB config
if [ -f "$WORK_DIR/new_iso/boot/grub2/grub.cfg" ]; then
    sudo sed -i \
        -e "s/CDLABEL=Fedora-[0-9]*-[A-Za-z]*-x86_64/CDLABEL=${ISO_LABEL}/g" \
        -e "s/-l 'Fedora-[0-9]*-[A-Za-z]*-x86_64'/-l '${ISO_LABEL}'/g" \
        -e "s/Install Fedora [0-9]*/Start ArxisOS/g" \
        -e "s/Test this media & install Fedora [0-9]*/Test Media \& Start ArxisOS/g" \
        -e "s/Install Fedora [0-9]* in basic graphics mode/Start ArxisOS (Basic Graphics)/g" \
        -e "s/Rescue a Fedora system/Rescue ArxisOS System/g" \
        -e "s/--class fedora/--class arxisos/g" \
        "$WORK_DIR/new_iso/boot/grub2/grub.cfg"

    # Add selinux=0 to kernel boot parameters to disable SELinux completely
    sudo sed -i \
        -e '/^\s*linux/s/$/ selinux=0/' \
        -e '/^\s*linuxefi/s/$/ selinux=0/' \
        "$WORK_DIR/new_iso/boot/grub2/grub.cfg"

    # Add GRUB theme configuration for BIOS boot
    if ! grep -q "set theme=" "$WORK_DIR/new_iso/boot/grub2/grub.cfg"; then
        {
            echo '# ArxisOS GRUB Theme Configuration'
            echo 'insmod all_video'
            echo 'insmod gfxterm'
            echo 'insmod gfxmenu'
            echo 'insmod png'
            echo 'set gfxmode=auto'
            echo 'set gfxpayload=keep'
            echo 'terminal_output gfxterm'
            echo ''
            echo '# Load fonts for theme'
            echo 'if [ -f ($root)/boot/grub2/themes/arxisos/dejavu_sans_16.pf2 ]; then'
            echo '    loadfont ($root)/boot/grub2/themes/arxisos/dejavu_sans_11.pf2'
            echo '    loadfont ($root)/boot/grub2/themes/arxisos/dejavu_sans_16.pf2'
            echo '    loadfont ($root)/boot/grub2/themes/arxisos/dejavu_sans_bold_16.pf2'
            echo '    loadfont ($root)/boot/grub2/themes/arxisos/dejavu_sans_bold_24.pf2'
            echo '    loadfont ($root)/boot/grub2/themes/arxisos/dejavu_mono_14.pf2'
            echo 'elif [ -f ($root)/boot/grub2/themes/arxisos/unicode.pf2 ]; then'
            echo '    loadfont ($root)/boot/grub2/themes/arxisos/unicode.pf2'
            echo 'elif [ -f ($root)/boot/grub2/fonts/unicode.pf2 ]; then'
            echo '    loadfont ($root)/boot/grub2/fonts/unicode.pf2'
            echo 'fi'
            echo ''
            echo 'set theme=($root)/boot/grub2/themes/arxisos/theme.txt'
            echo 'export theme'
            echo ''
            cat "$WORK_DIR/new_iso/boot/grub2/grub.cfg"
        } | sudo tee "$WORK_DIR/new_iso/boot/grub2/grub.cfg.new" > /dev/null
        sudo mv "$WORK_DIR/new_iso/boot/grub2/grub.cfg.new" "$WORK_DIR/new_iso/boot/grub2/grub.cfg"
    fi
    echo "  - Updated BIOS GRUB config with theme"
fi

# Modify initrd to include ArxisOS Plymouth theme
echo "Modifying initrd with ArxisOS boot splash..."
INITRD_WORK="$WORK_DIR/initrd_work"
mkdir -p "$INITRD_WORK"

if [ -f "$WORK_DIR/new_iso/images/pxeboot/initrd.img" ]; then
    cd "$INITRD_WORK"

    # Extract initrd (it's xz compressed cpio)
    echo "  - Extracting initrd..."
    sudo xz -dc "$WORK_DIR/new_iso/images/pxeboot/initrd.img" | sudo cpio -idm 2>/dev/null || true

    # Find and replace Plymouth theme in initrd
    if [ -d "$INITRD_WORK/usr/share/plymouth/themes" ]; then
        echo "  - Adding ArxisOS Plymouth theme to initrd"

        # Create ArxisOS theme directory
        sudo mkdir -p "$INITRD_WORK/usr/share/plymouth/themes/arxisos"

        # Copy the theme files
        sudo cp "$BRANDING_DIR/plymouth/arxisos/arxisos.plymouth" "$INITRD_WORK/usr/share/plymouth/themes/arxisos/"
        sudo cp "$BRANDING_DIR/plymouth/arxisos/logo.png" "$INITRD_WORK/usr/share/plymouth/themes/arxisos/"

        # Also replace Fedora branding in existing themes (bgrt, spinner, etc.)
        echo "  - Replacing Fedora watermarks in initrd Plymouth themes"

        # Create small watermark for Plymouth (48x48 - appears at bottom of screen)
        PLYMOUTH_LOGO="/tmp/arxisos-plymouth-logo.png"
        WATERMARK_CREATED=false

        if [ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]; then
            echo "    Creating resized Plymouth watermark (48px)..."
            if command -v magick &> /dev/null; then
                magick "$BRANDING_DIR/logos/arxisos-logo.png" -resize 48x48 -background transparent -gravity center -extent 48x48 "$PLYMOUTH_LOGO" 2>/dev/null && WATERMARK_CREATED=true
            elif command -v convert &> /dev/null; then
                convert "$BRANDING_DIR/logos/arxisos-logo.png" -resize 48x48 -background transparent -gravity center -extent 48x48 "$PLYMOUTH_LOGO" 2>/dev/null && WATERMARK_CREATED=true
            fi
        fi

        # Only replace if we successfully created a resized watermark
        if [ "$WATERMARK_CREATED" = "true" ] && [ -f "$PLYMOUTH_LOGO" ]; then
            # Only replace watermark files specifically (NOT logo files which may be larger)
            sudo find "$INITRD_WORK/usr/share/plymouth/themes" -name "*watermark*" -type f | while read -r pngfile; do
                echo "    Replacing: $pngfile"
                sudo cp "$PLYMOUTH_LOGO" "$pngfile" 2>/dev/null || true
            done

            # Explicitly replace spinner watermark (this is the "fedora" logo at bottom)
            if [ -d "$INITRD_WORK/usr/share/plymouth/themes/spinner" ]; then
                sudo cp "$PLYMOUTH_LOGO" "$INITRD_WORK/usr/share/plymouth/themes/spinner/watermark.png" 2>/dev/null || true
            fi

            # Replace bgrt watermark
            if [ -d "$INITRD_WORK/usr/share/plymouth/themes/bgrt" ]; then
                sudo cp "$PLYMOUTH_LOGO" "$INITRD_WORK/usr/share/plymouth/themes/bgrt/watermark.png" 2>/dev/null || true
            fi
        else
            echo "    WARNING: Could not resize logo, skipping watermark replacement"
        fi

        # Clean up temp logo
        rm -f "$PLYMOUTH_LOGO"

        # Update Plymouth default theme configuration
        sudo mkdir -p "$INITRD_WORK/etc/plymouth"
        sudo tee "$INITRD_WORK/etc/plymouth/plymouthd.conf" > /dev/null << 'PLYMOUTH_EOF'
[Daemon]
Theme=spinner
ShowDelay=0
DeviceTimeout=8
PLYMOUTH_EOF

        # Create default.plymouth symlink
        sudo ln -sf /usr/share/plymouth/themes/spinner/spinner.plymouth "$INITRD_WORK/usr/share/plymouth/default.plymouth" 2>/dev/null || true

        echo "  - Plymouth themes in initrd:"
        ls -la "$INITRD_WORK/usr/share/plymouth/themes/" 2>/dev/null || true
    fi

    # Repack initrd
    echo "  - Repacking initrd..."
    cd "$INITRD_WORK"
    sudo find . | sudo cpio -o -H newc 2>/dev/null | xz -9 --check=crc32 | sudo tee "$WORK_DIR/new_iso/images/pxeboot/initrd.img" > /dev/null

    cd "$WORK_DIR"
fi

# Extract squashfs
echo "Extracting squashfs..."
sudo unsquashfs -d "$WORK_DIR/squashfs" "$WORK_DIR/iso/LiveOS/squashfs.img"

# Check if squashfs contains rootfs.img (traditional Fedora) or is the rootfs directly (osbuild)
ROOTFS_IMG=$(find "$WORK_DIR/squashfs" -maxdepth 2 -name "rootfs.img" 2>/dev/null | head -1)
if [ -n "$ROOTFS_IMG" ]; then
    echo "Traditional Fedora live format detected (rootfs.img)"
    # Define ROOTFS_DIR BEFORE using it
    ROOTFS_DIR="$WORK_DIR/squashfs/rootfs"
    mkdir -p "$ROOTFS_DIR"
    sudo mount -o loop "$ROOTFS_IMG" "$ROOTFS_DIR"
    MOUNTED_ROOTFS=true
else
    echo "OSBuild format detected (squashfs is rootfs)"
    ROOTFS_DIR="$WORK_DIR/squashfs"
    MOUNTED_ROOTFS=false
fi

echo "Applying branding..."

# ============================================
# INSTALL KDE PLASMA DESKTOP
# ============================================
echo "Installing KDE Plasma desktop packages..."

# Bind mount necessary filesystems for chroot
sudo mount --bind /dev "$ROOTFS_DIR/dev"
sudo mount --bind /proc "$ROOTFS_DIR/proc"
sudo mount --bind /sys "$ROOTFS_DIR/sys"
sudo mount --bind /run "$ROOTFS_DIR/run"

# Copy resolv.conf for network access (handle symlinks)
if [ -L "$ROOTFS_DIR/etc/resolv.conf" ]; then
    sudo rm -f "$ROOTFS_DIR/etc/resolv.conf"
fi
sudo cp -L /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null || \
    echo "nameserver 8.8.8.8" | sudo tee "$ROOTFS_DIR/etc/resolv.conf" > /dev/null

# Install KDE Plasma and SDDM
# Use --releasever=43 to ensure Fedora repos work even if os-release was modified
echo "  - Installing plasma-desktop, sddm, konsole, dolphin..."
echo "    (This may take 10-20 minutes, showing progress...)"
sudo chroot "$ROOTFS_DIR" dnf install -y --releasever=43 --allowerasing \
    plasma-desktop plasma-workspace plasma-workspace-x11 sddm sddm-kcm \
    konsole dolphin kate ark gwenview okular spectacle \
    plasma-nm plasma-pa bluedevil powerdevil kscreen \
    kwin kwin-x11 breeze-gtk breeze-icon-theme \
    xorg-x11-server-Xorg xorg-x11-drv-libinput xorg-x11-xinit \
    plasma-systemmonitor plasma-discover \
    NetworkManager-wifi NetworkManager-bluetooth \
    dbus-x11 xdg-desktop-portal-kde \
    || echo "Warning: Some packages may have failed"

# Install bootloader packages - CRITICAL for Anaconda to install GRUB on target disk
echo "  - Installing bootloader packages (grub2-efi, shim, efibootmgr)..."
sudo chroot "$ROOTFS_DIR" dnf install -y --releasever=43 \
    grub2-efi-x64 grub2-efi-x64-modules shim-x64 \
    grub2-tools grub2-tools-extra efibootmgr grub2-common \
    kernel kernel-modules kernel-modules-extra \
    || echo "Warning: Some bootloader packages may have failed"

# Remove GNOME packages to save space and avoid conflicts
echo "  - Removing GNOME packages..."
sudo chroot "$ROOTFS_DIR" dnf remove -y --releasever=43 --noautoremove \
    gnome-shell gnome-session gnome-tour gnome-initial-setup \
    gdm gnome-control-center gnome-settings-daemon \
    2>&1 | tail -20 || echo "Warning: Some GNOME packages may not be installed"

# Set graphical target as default
echo "  - Setting graphical.target as default..."
sudo chroot "$ROOTFS_DIR" systemctl set-default graphical.target

# Enable SDDM and disable GDM
echo "  - Enabling SDDM, disabling GDM..."
sudo chroot "$ROOTFS_DIR" systemctl disable gdm.service 2>/dev/null || true
sudo chroot "$ROOTFS_DIR" systemctl enable sddm.service 2>/dev/null || true

# Create display-manager symlink
sudo rm -f "$ROOTFS_DIR/etc/systemd/system/display-manager.service"
sudo ln -sf /usr/lib/systemd/system/sddm.service "$ROOTFS_DIR/etc/systemd/system/display-manager.service"

# ============================================
# CREATE LIVE USER FOR LIVE SESSION
# ============================================
echo "  - Creating liveuser for live session..."

# Create liveuser account if it doesn't exist
if ! sudo chroot "$ROOTFS_DIR" id liveuser &>/dev/null; then
    sudo chroot "$ROOTFS_DIR" useradd -m -G wheel -s /bin/bash liveuser 2>/dev/null || true
    # Set empty password for live user (allows passwordless login)
    sudo chroot "$ROOTFS_DIR" passwd -d liveuser 2>/dev/null || true
fi

# Create home directory structure for liveuser
sudo mkdir -p "$ROOTFS_DIR/home/liveuser/.config"
sudo mkdir -p "$ROOTFS_DIR/home/liveuser/Desktop"

# Copy skel to liveuser's home
if [ -d "$ROOTFS_DIR/etc/skel" ]; then
    sudo cp -r "$ROOTFS_DIR/etc/skel/." "$ROOTFS_DIR/home/liveuser/" 2>/dev/null || true
fi

# Set ownership
sudo chroot "$ROOTFS_DIR" chown -R liveuser:liveuser /home/liveuser 2>/dev/null || true

# Configure sudoers for passwordless sudo (live environment)
echo "liveuser ALL=(ALL) NOPASSWD: ALL" | sudo tee "$ROOTFS_DIR/etc/sudoers.d/liveuser" > /dev/null
sudo chmod 440 "$ROOTFS_DIR/etc/sudoers.d/liveuser"

# Create systemd service to ensure liveuser exists on boot and has proper configs
sudo tee "$ROOTFS_DIR/etc/systemd/system/liveuser-setup.service" > /dev/null << 'LIVEUSER_SERVICE'
[Unit]
Description=Setup Live User with Plasma configuration
Before=display-manager.service sddm.service
After=systemd-user-sessions.service local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
    id liveuser || useradd -m -G wheel liveuser; \
    passwd -d liveuser; \
    mkdir -p /home/liveuser/Desktop; \
    if [ -d /etc/skel/.config ]; then \
        cp -rn /etc/skel/. /home/liveuser/ 2>/dev/null || true; \
    fi; \
    chown -R liveuser:liveuser /home/liveuser'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
LIVEUSER_SERVICE

sudo chroot "$ROOTFS_DIR" systemctl enable liveuser-setup.service 2>/dev/null || true
# ============================================

# Unmount bind mounts (in reverse order, use lazy unmount for safety)
echo "  - Unmounting chroot bind mounts..."
sync  # Ensure all writes are flushed
sudo umount -l "$ROOTFS_DIR/run" 2>/dev/null || true
sudo umount -l "$ROOTFS_DIR/sys" 2>/dev/null || true
sudo umount -l "$ROOTFS_DIR/proc" 2>/dev/null || true
sudo umount -l "$ROOTFS_DIR/dev" 2>/dev/null || true
sleep 1  # Give kernel time to release mounts

# Verify mounts are released
if mount | grep -q "$ROOTFS_DIR/dev"; then
    echo "WARNING: /dev still mounted, forcing unmount..."
    sudo fuser -km "$ROOTFS_DIR/dev" 2>/dev/null || true
    sudo umount -f "$ROOTFS_DIR/dev" 2>/dev/null || true
fi

echo "  - KDE Plasma installation complete"
# ============================================

# Copy Plymouth theme
if [ -d "$BRANDING_DIR/plymouth/arxisos" ]; then
    echo "  - Plymouth theme"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/plymouth/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/plymouth/arxisos/"* "$ROOTFS_DIR/usr/share/plymouth/themes/arxisos/"

    # Configure Plymouth to use ArxisOS theme
    sudo mkdir -p "$ROOTFS_DIR/etc/plymouth"
    sudo tee "$ROOTFS_DIR/etc/plymouth/plymouthd.conf" > /dev/null << 'PLYMOUTHCONF'
[Daemon]
Theme=spinner
ShowDelay=0
DeviceTimeout=8
PLYMOUTHCONF

    # Create small watermark for Plymouth (48x48 - appears at bottom of screen)
    PLYMOUTH_LOGO_ROOTFS="/tmp/arxisos-plymouth-logo-rootfs.png"
    WATERMARK_CREATED=false

    if [ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]; then
        echo "    Creating resized Plymouth watermark (48px)..."
        if command -v magick &> /dev/null; then
            magick "$BRANDING_DIR/logos/arxisos-logo.png" -resize 48x48 -background transparent -gravity center -extent 48x48 "$PLYMOUTH_LOGO_ROOTFS" 2>/dev/null && WATERMARK_CREATED=true
        elif command -v convert &> /dev/null; then
            convert "$BRANDING_DIR/logos/arxisos-logo.png" -resize 48x48 -background transparent -gravity center -extent 48x48 "$PLYMOUTH_LOGO_ROOTFS" 2>/dev/null && WATERMARK_CREATED=true
        fi
    fi

    # Only replace if we successfully created a resized watermark
    if [ "$WATERMARK_CREATED" = "true" ] && [ -f "$PLYMOUTH_LOGO_ROOTFS" ]; then
        # Replace Fedora watermark with ArxisOS logo in spinner theme
        if [ -d "$ROOTFS_DIR/usr/share/plymouth/themes/spinner" ]; then
            sudo cp "$PLYMOUTH_LOGO_ROOTFS" "$ROOTFS_DIR/usr/share/plymouth/themes/spinner/watermark.png"
            echo "    - Replaced spinner watermark"
        fi

        # Also replace in bgrt theme (BIOS/UEFI logo fallback)
        if [ -d "$ROOTFS_DIR/usr/share/plymouth/themes/bgrt" ]; then
            sudo cp "$PLYMOUTH_LOGO_ROOTFS" "$ROOTFS_DIR/usr/share/plymouth/themes/bgrt/watermark.png"
            echo "    - Replaced bgrt watermark"
        fi
    else
        echo "    WARNING: Could not resize logo, skipping watermark replacement"
    fi

    rm -f "$PLYMOUTH_LOGO_ROOTFS"
fi

# Copy GRUB theme
if [ -d "$BRANDING_DIR/grub/arxisos" ]; then
    echo "  - GRUB theme"
    sudo mkdir -p "$ROOTFS_DIR/boot/grub2/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/grub/arxisos/"* "$ROOTFS_DIR/boot/grub2/themes/arxisos/"

    # Generate GRUB font files (.pf2) from system fonts
    echo "  - Generating GRUB fonts for theme..."
    GRUB_MKFONT=""
    if command -v grub2-mkfont &> /dev/null; then
        GRUB_MKFONT="grub2-mkfont"
    elif command -v grub-mkfont &> /dev/null; then
        GRUB_MKFONT="grub-mkfont"
    fi

    if [ -n "$GRUB_MKFONT" ]; then
        # Find DejaVu Sans font
        DEJAVU_REGULAR=$(find /usr/share/fonts -name "DejaVuSans.ttf" 2>/dev/null | head -1)
        DEJAVU_BOLD=$(find /usr/share/fonts -name "DejaVuSans-Bold.ttf" 2>/dev/null | head -1)
        DEJAVU_MONO=$(find /usr/share/fonts -name "DejaVuSansMono.ttf" 2>/dev/null | head -1)

        # Generate fonts at various sizes needed by theme
        if [ -n "$DEJAVU_REGULAR" ]; then
            sudo $GRUB_MKFONT -s 11 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_sans_11.pf2" "$DEJAVU_REGULAR" 2>/dev/null || true
            sudo $GRUB_MKFONT -s 16 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_sans_16.pf2" "$DEJAVU_REGULAR" 2>/dev/null || true
        fi
        if [ -n "$DEJAVU_BOLD" ]; then
            sudo $GRUB_MKFONT -s 16 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_sans_bold_16.pf2" "$DEJAVU_BOLD" 2>/dev/null || true
            sudo $GRUB_MKFONT -s 24 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_sans_bold_24.pf2" "$DEJAVU_BOLD" 2>/dev/null || true
        fi
        if [ -n "$DEJAVU_MONO" ]; then
            sudo $GRUB_MKFONT -s 14 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_mono_14.pf2" "$DEJAVU_MONO" 2>/dev/null || true
        fi
        echo "    Font files generated"
    else
        echo "    Warning: grub2-mkfont not found, using fallback fonts"
    fi

    # Copy unicode.pf2 as fallback
    if [ -f /usr/share/grub/unicode.pf2 ]; then
        sudo cp /usr/share/grub/unicode.pf2 "$ROOTFS_DIR/boot/grub2/themes/arxisos/" 2>/dev/null || true
    elif [ -f /boot/grub2/fonts/unicode.pf2 ]; then
        sudo cp /boot/grub2/fonts/unicode.pf2 "$ROOTFS_DIR/boot/grub2/themes/arxisos/" 2>/dev/null || true
    fi

    # Enable GRUB theme in configuration
    echo "  - Enabling GRUB theme and ArxisOS branding"
    sudo mkdir -p "$ROOTFS_DIR/etc/default"
    if [ -f "$ROOTFS_DIR/etc/default/grub" ]; then
        # Remove any existing lines we're going to set
        sudo sed -i '/^GRUB_THEME=/d' "$ROOTFS_DIR/etc/default/grub"
        sudo sed -i '/^GRUB_DISTRIBUTOR=/d' "$ROOTFS_DIR/etc/default/grub"
        sudo sed -i '/^GRUB_DISABLE_OS_PROBER=/d' "$ROOTFS_DIR/etc/default/grub"
    fi
    # Add GRUB configuration for ArxisOS
    sudo tee -a "$ROOTFS_DIR/etc/default/grub" > /dev/null << 'GRUB_DEFAULT_EOF'

# ArxisOS GRUB Configuration
GRUB_THEME="/boot/grub2/themes/arxisos/theme.txt"
GRUB_DISTRIBUTOR="ArxisOS"
# Disable os-prober to prevent duplicate entries from live media
GRUB_DISABLE_OS_PROBER=true
GRUB_DEFAULT_EOF

    # Also create a kernel post-install hook to regenerate grub.cfg
    echo "  - Creating kernel post-install hook for GRUB"
    sudo mkdir -p "$ROOTFS_DIR/etc/kernel/postinst.d"
    sudo tee "$ROOTFS_DIR/etc/kernel/postinst.d/99-update-grub-arxisos" > /dev/null << 'KERNEL_HOOK_EOF'
#!/bin/bash
# Regenerate GRUB config after kernel installation
# This ensures ArxisOS branding is preserved
if [ -x /usr/sbin/grub2-mkconfig ]; then
    /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true
fi
if [ -d /boot/efi/EFI/fedora ] && [ -x /usr/sbin/grub2-mkconfig ]; then
    /usr/sbin/grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true
fi
KERNEL_HOOK_EOF
    sudo chmod +x "$ROOTFS_DIR/etc/kernel/postinst.d/99-update-grub-arxisos"
fi

# Copy SDDM theme - prefer new Plasma 6 compatible ArxisOS-SDDM theme
SDDM_THEME_SOURCE=""
if [ -d "$BUILD_DIR/PLASMA-CONFIGS/ArxisOS-SDDM" ]; then
    SDDM_THEME_SOURCE="$BUILD_DIR/PLASMA-CONFIGS/ArxisOS-SDDM"
    echo "  - SDDM theme (Plasma 6 version from PLASMA-CONFIGS)"
elif [ -d "$BRANDING_DIR/sddm/arxisos" ]; then
    SDDM_THEME_SOURCE="$BRANDING_DIR/sddm/arxisos"
    echo "  - SDDM theme (fallback from branding)"
fi

if [ -n "$SDDM_THEME_SOURCE" ]; then
    sudo mkdir -p "$ROOTFS_DIR/usr/share/sddm/themes/arxisos"
    sudo cp -r "$SDDM_THEME_SOURCE/"* "$ROOTFS_DIR/usr/share/sddm/themes/arxisos/"

    # Set ArxisOS logo as default user avatar/face icon
    if [ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]; then
        echo "  - Setting ArxisOS logo as default user avatar"
        sudo mkdir -p "$ROOTFS_DIR/usr/share/sddm/themes/arxisos/faces"
        sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/sddm/themes/arxisos/faces/.face.icon"
        # Also set as default face for all users
        sudo mkdir -p "$ROOTFS_DIR/usr/share/sddm/faces"
        sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/sddm/faces/.face.icon"
    fi
fi

# Copy wallpapers
if [ -d "$BRANDING_DIR/wallpapers" ]; then
    echo "  - Wallpapers"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/wallpapers/arxisos"
    sudo cp -r "$BRANDING_DIR/wallpapers/"* "$ROOTFS_DIR/usr/share/wallpapers/arxisos/"
fi

# Copy logos
if [ -d "$BRANDING_DIR/logos" ]; then
    echo "  - Logos"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/arxisos/logos"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/pixmaps"
    sudo cp -r "$BRANDING_DIR/logos/"* "$ROOTFS_DIR/usr/share/arxisos/logos/"
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/" 2>/dev/null || true
fi

# Copy hicolor icons (ArxisOS branding)
if [ -d "$BRANDING_DIR/icons/hicolor" ]; then
    echo "  - Hicolor icons"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/icons/hicolor"
    for dir in "$BRANDING_DIR/icons/hicolor"/*/; do
        [ -d "$dir" ] && sudo cp -r "$dir" "$ROOTFS_DIR/usr/share/icons/hicolor/"
    done
fi

# Copy Vivid-Glassy-Dark icon theme
if [ -d "$BRANDING_DIR/icons/Vivid-Glassy-Dark-Icons" ]; then
    echo "  - Vivid-Glassy-Dark icon theme"
    sudo cp -r "$BRANDING_DIR/icons/Vivid-Glassy-Dark-Icons" "$ROOTFS_DIR/usr/share/icons/"
fi

# Copy cursor theme
if [ -d "$BRANDING_DIR/cursors/oreo_white_cursors" ]; then
    echo "  - Oreo White cursor theme"
    sudo cp -r "$BRANDING_DIR/cursors/oreo_white_cursors" "$ROOTFS_DIR/usr/share/icons/"
fi

# Copy GTK theme
if [ -d "$BRANDING_DIR/gtk-themes/PurPurNight-GTK" ]; then
    echo "  - PurPurNight GTK theme"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/themes"
    sudo cp -r "$BRANDING_DIR/gtk-themes/PurPurNight-GTK" "$ROOTFS_DIR/usr/share/themes/"
fi

# Copy Plasma look-and-feel themes
if [ -d "$BRANDING_DIR/plasma-themes/PurPurNight-Global-6" ]; then
    echo "  - PurPurNight Plasma global theme"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/plasma/look-and-feel"
    sudo cp -r "$BRANDING_DIR/plasma-themes/PurPurNight-Global-6" "$ROOTFS_DIR/usr/share/plasma/look-and-feel/"
fi

if [ -d "$BRANDING_DIR/plasma-themes/PurPurNight-Splash-6" ]; then
    echo "  - PurPurNight splash screen"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/plasma/look-and-feel"
    sudo cp -r "$BRANDING_DIR/plasma-themes/PurPurNight-Splash-6" "$ROOTFS_DIR/usr/share/plasma/look-and-feel/"
fi

# Copy PurPurNight color scheme system-wide
echo "  - Installing PurPurNight color scheme"
sudo mkdir -p "$ROOTFS_DIR/usr/share/color-schemes"
sudo tee "$ROOTFS_DIR/usr/share/color-schemes/PurPurNightColorscheme.colors" > /dev/null << 'COLORSCHEME_EOF'
[ColorEffects:Disabled]
Color=56,56,56
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=112,111,110
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=22,22,47
BackgroundNormal=25,25,54
DecorationFocus=91,78,157
DecorationHover=96,85,170
ForegroundActive=85,85,255
ForegroundInactive=139,145,157
ForegroundLink=142,142,213
ForegroundNegative=200,55,113
ForegroundNeutral=104,91,182
ForegroundNormal=211,218,227
ForegroundPositive=0,170,127
ForegroundVisited=136,136,204

[Colors:Complementary]
BackgroundAlternate=22,22,47
BackgroundNormal=22,22,47
DecorationFocus=91,78,157
DecorationHover=96,85,170
ForegroundActive=85,85,255
ForegroundInactive=176,182,189
ForegroundLink=120,120,180
ForegroundNegative=200,55,113
ForegroundNeutral=109,85,170
ForegroundNormal=211,218,227
ForegroundPositive=0,170,127
ForegroundVisited=136,136,204

[Colors:Header]
BackgroundAlternate=22,22,47

[Colors:Selection]
BackgroundAlternate=29,153,243
BackgroundNormal=91,78,157
DecorationFocus=91,78,157
DecorationHover=96,85,170
ForegroundActive=85,85,255
ForegroundInactive=158,163,170
ForegroundLink=142,142,213
ForegroundNegative=200,55,113
ForegroundNeutral=104,91,182
ForegroundNormal=255,255,255
ForegroundPositive=0,170,127
ForegroundVisited=136,136,204

[Colors:Tooltip]
BackgroundAlternate=22,22,47
BackgroundNormal=22,22,47
DecorationFocus=91,78,157
DecorationHover=96,85,170
ForegroundActive=85,85,255
ForegroundInactive=139,145,157
ForegroundLink=142,142,213
ForegroundNegative=200,55,113
ForegroundNeutral=104,91,182
ForegroundNormal=211,218,227
ForegroundPositive=0,170,127
ForegroundVisited=136,136,204

[Colors:View]
BackgroundAlternate=22,22,47
BackgroundNormal=19,19,40
DecorationFocus=91,78,157
DecorationHover=96,85,170
ForegroundActive=85,85,255
ForegroundInactive=139,145,157
ForegroundLink=142,142,213
ForegroundNegative=200,55,113
ForegroundNeutral=104,91,182
ForegroundNormal=211,218,227
ForegroundPositive=0,170,127
ForegroundVisited=136,136,204

[Colors:Window]
BackgroundAlternate=22,22,47
BackgroundNormal=22,22,47
DecorationFocus=91,78,157
DecorationHover=96,85,170
ForegroundActive=85,85,255
ForegroundInactive=139,145,157
ForegroundLink=142,142,213
ForegroundNegative=200,55,113
ForegroundNeutral=104,91,182
ForegroundNormal=211,218,227
ForegroundPositive=0,170,127
ForegroundVisited=136,136,204

[General]
ColorScheme=PurPurNightColorscheme
Name=PurPurNight-Colorscheme
shadeSortColumn=true

[KDE]
contrast=4

[WM]
activeBackground=22,22,47
activeBlend=22,22,47
activeForeground=211,218,227
inactiveBackground=22,22,47
inactiveBlend=22,22,47
inactiveForeground=141,147,159
COLORSCHEME_EOF

# Copy PurPurNight-Plasma desktop theme if available in PLASMA-CONFIGS
PLASMA_THEME_SRC="$BUILD_DIR/PLASMA-CONFIGS/Archive-local-share/plasma/desktoptheme/PurPurNight-Plasma"
if [ -d "$PLASMA_THEME_SRC" ]; then
    echo "  - PurPurNight Plasma desktop theme"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/plasma/desktoptheme"
    sudo cp -r "$PLASMA_THEME_SRC" "$ROOTFS_DIR/usr/share/plasma/desktoptheme/"
fi

# Copy Aurorae window decoration theme
if [ -d "$BRANDING_DIR/aurorae/PurPurNight-Blur-Aurorae-6" ]; then
    echo "  - PurPurNight Aurorae window decoration"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/aurorae/themes"
    sudo cp -r "$BRANDING_DIR/aurorae/PurPurNight-Blur-Aurorae-6" "$ROOTFS_DIR/usr/share/aurorae/themes/"
fi

# Copy skel (default user configuration)
# The Skel directory is in BUILD_DIR/Skel (note: capital S)
# IMPORTANT: Only copy GTK configs - Plasma configs cause plasmashell to fail
SKEL_DIR="$BUILD_DIR/Skel"
if [ -d "$SKEL_DIR" ]; then
    echo "  - User skeleton configuration (GTK only, Plasma uses defaults)"
    sudo mkdir -p "$ROOTFS_DIR/etc/skel/.config"

    # Only copy GTK and non-Plasma configs
    [ -d "$SKEL_DIR/.config/gtk-3.0" ] && sudo cp -r "$SKEL_DIR/.config/gtk-3.0" "$ROOTFS_DIR/etc/skel/.config/"
    [ -d "$SKEL_DIR/.config/gtk-4.0" ] && sudo cp -r "$SKEL_DIR/.config/gtk-4.0" "$ROOTFS_DIR/etc/skel/.config/"
    [ -d "$SKEL_DIR/.config/environment.d" ] && sudo cp -r "$SKEL_DIR/.config/environment.d" "$ROOTFS_DIR/etc/skel/.config/"
    [ -f "$SKEL_DIR/.bashrc" ] && sudo cp "$SKEL_DIR/.bashrc" "$ROOTFS_DIR/etc/skel/"
    [ -d "$SKEL_DIR/.local" ] && sudo cp -r "$SKEL_DIR/.local" "$ROOTFS_DIR/etc/skel/"
    sudo chmod +x "$ROOTFS_DIR/etc/skel/.local/bin/"* 2>/dev/null || true

    echo "  - Skipping Plasma configs (using Breeze defaults for stability)"

    # Setup liveuser with defaults
    if [ -d "$ROOTFS_DIR/home/liveuser" ]; then
        echo "  - Setting up liveuser with defaults"
        sudo mkdir -p "$ROOTFS_DIR/home/liveuser/.config"
        [ -d "$SKEL_DIR/.config/gtk-3.0" ] && sudo cp -r "$SKEL_DIR/.config/gtk-3.0" "$ROOTFS_DIR/home/liveuser/.config/"
        [ -d "$SKEL_DIR/.config/gtk-4.0" ] && sudo cp -r "$SKEL_DIR/.config/gtk-4.0" "$ROOTFS_DIR/home/liveuser/.config/"
        [ -d "$SKEL_DIR/.config/environment.d" ] && sudo cp -r "$SKEL_DIR/.config/environment.d" "$ROOTFS_DIR/home/liveuser/.config/"
        [ -f "$SKEL_DIR/.bashrc" ] && sudo cp "$SKEL_DIR/.bashrc" "$ROOTFS_DIR/home/liveuser/"
        [ -d "$SKEL_DIR/.local" ] && sudo cp -r "$SKEL_DIR/.local" "$ROOTFS_DIR/home/liveuser/"

        # Ensure no leftover Plasma configs that could break plasmashell
        sudo rm -rf "$ROOTFS_DIR/home/liveuser/.config/plasma*" 2>/dev/null || true
        sudo rm -rf "$ROOTFS_DIR/home/liveuser/.config/k*" 2>/dev/null || true

        sudo chroot "$ROOTFS_DIR" chown -R liveuser:liveuser /home/liveuser 2>/dev/null || true
    fi
fi

# Update icon cache
echo "  - Updating icon caches"
sudo chroot "$ROOTFS_DIR" gtk-update-icon-cache -f /usr/share/icons/Vivid-Glassy-Dark-Icons 2>/dev/null || true
sudo chroot "$ROOTFS_DIR" gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

# Configure SDDM to use the theme and Plasma session
# IMPORTANT: Autologin is set up ONLY for live session via separate service
echo "  - SDDM configuration"
sudo mkdir -p "$ROOTFS_DIR/etc/sddm.conf.d"

# Base SDDM config (theme, session) - NO autologin here
# Use X11 session for better VM/live environment compatibility
sudo tee "$ROOTFS_DIR/etc/sddm.conf.d/arxisos.conf" > /dev/null << 'SDDM_EOF'
[Theme]
Current=arxisos
CursorTheme=oreo_white_cursors

[General]
DefaultSession=plasmax11.desktop

[X11]
ServerArguments=-nolisten tcp

[Wayland]
SessionDir=/usr/share/wayland-sessions
SDDM_EOF

# Create systemd service to enable autologin ONLY in live session
# Live sessions have /run/initramfs/live present
# Use X11 session (plasmax11) for better compatibility in live/VM environments
echo "  - Creating live-session autologin service"
sudo tee "$ROOTFS_DIR/etc/systemd/system/sddm-live-autologin.service" > /dev/null << 'LIVE_AUTOLOGIN_EOF'
[Unit]
Description=Enable SDDM autologin for live session only
Before=sddm.service display-manager.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
    if [ -d /run/initramfs/live ] || grep -q "root=live:" /proc/cmdline 2>/dev/null; then \
        mkdir -p /etc/sddm.conf.d; \
        echo "[Autologin]" > /etc/sddm.conf.d/live-autologin.conf; \
        echo "User=liveuser" >> /etc/sddm.conf.d/live-autologin.conf; \
        echo "Session=plasmax11" >> /etc/sddm.conf.d/live-autologin.conf; \
        echo "Relogin=false" >> /etc/sddm.conf.d/live-autologin.conf; \
    fi'
ExecStop=/bin/rm -f /etc/sddm.conf.d/live-autologin.conf
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
LIVE_AUTOLOGIN_EOF

sudo chroot "$ROOTFS_DIR" systemctl enable sddm-live-autologin.service 2>/dev/null || true

# Set Plasma as default session and SDDM as display manager
echo "  - Setting Plasma as default session"
sudo mkdir -p "$ROOTFS_DIR/etc/X11/xinit"
echo "PREFERRED=plasma" | sudo tee "$ROOTFS_DIR/etc/sysconfig/desktop" > /dev/null 2>&1 || true

# Configure AccountsService for live user to use Plasma X11
echo "  - Configuring live user for Plasma X11 session"
sudo mkdir -p "$ROOTFS_DIR/var/lib/AccountsService/users"
# Configure for common live user names
for liveuser in liveuser live arxis; do
    sudo tee "$ROOTFS_DIR/var/lib/AccountsService/users/$liveuser" > /dev/null << ACCOUNTSEOF
[User]
Session=plasmax11
XSession=plasmax11
Icon=/usr/share/pixmaps/arxisos-logo.png
SystemAccount=false
ACCOUNTSEOF
done

# Configure GDM custom.conf to use Plasma if GDM is used
# NOTE: GDM autologin is handled by the live-session service
echo "  - Configuring GDM for Plasma session"
sudo mkdir -p "$ROOTFS_DIR/etc/gdm"
sudo tee "$ROOTFS_DIR/etc/gdm/custom.conf" > /dev/null << 'GDMCONF'
[daemon]
AutomaticLoginEnable=False
DefaultSession=plasma.desktop

[security]

[xdmcp]

[chooser]

[debug]
GDMCONF

# Enable SDDM and disable GDM
echo "  - Configuring display manager"
sudo chroot "$ROOTFS_DIR" systemctl disable gdm.service 2>/dev/null || true
sudo chroot "$ROOTFS_DIR" systemctl enable sddm.service 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/etc/systemd/system/display-manager.service" 2>/dev/null || true
sudo ln -sf /usr/lib/systemd/system/sddm.service "$ROOTFS_DIR/etc/systemd/system/display-manager.service" 2>/dev/null || true

# Set default session for X11
sudo mkdir -p "$ROOTFS_DIR/etc/X11/xinit"
sudo tee "$ROOTFS_DIR/etc/X11/xinit/Xsession" > /dev/null << 'XSESSION'
#!/bin/bash
exec startplasma-x11
XSESSION
sudo chmod +x "$ROOTFS_DIR/etc/X11/xinit/Xsession" 2>/dev/null || true

# Create default session symlinks and ensure Plasma is default
echo "  - Setting Plasma as default session"
sudo mkdir -p "$ROOTFS_DIR/usr/share/xsessions"
sudo mkdir -p "$ROOTFS_DIR/usr/share/wayland-sessions"

# For X11 sessions - use plasmax11 for stability
if [ -f "$ROOTFS_DIR/usr/share/xsessions/plasmax11.desktop" ]; then
    sudo ln -sf plasmax11.desktop "$ROOTFS_DIR/usr/share/xsessions/default.desktop" 2>/dev/null || true
elif [ -f "$ROOTFS_DIR/usr/share/xsessions/plasma.desktop" ]; then
    sudo ln -sf plasma.desktop "$ROOTFS_DIR/usr/share/xsessions/default.desktop" 2>/dev/null || true
fi

# Set default session in accountsservice for all users
sudo mkdir -p "$ROOTFS_DIR/var/lib/AccountsService/users"
# Default template for new users to use Plasma X11
sudo tee "$ROOTFS_DIR/var/lib/AccountsService/users/liveuser" > /dev/null << 'ACCT_EOF'
[User]
Session=plasmax11
XSession=plasmax11
Icon=/usr/share/sddm/faces/.face.icon
ACCT_EOF

# Hide GNOME sessions from SDDM to prevent accidental selection
# (Comment out rather than delete in case user wants them later)
for gnome_session in gnome gnome-xorg gnome-classic gnome-classic-xorg; do
    if [ -f "$ROOTFS_DIR/usr/share/xsessions/${gnome_session}.desktop" ]; then
        sudo sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$ROOTFS_DIR/usr/share/xsessions/${gnome_session}.desktop" 2>/dev/null || \
        echo "NoDisplay=true" | sudo tee -a "$ROOTFS_DIR/usr/share/xsessions/${gnome_session}.desktop" > /dev/null
    fi
    if [ -f "$ROOTFS_DIR/usr/share/wayland-sessions/${gnome_session}.desktop" ]; then
        sudo sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$ROOTFS_DIR/usr/share/wayland-sessions/${gnome_session}.desktop" 2>/dev/null || \
        echo "NoDisplay=true" | sudo tee -a "$ROOTFS_DIR/usr/share/wayland-sessions/${gnome_session}.desktop" > /dev/null
    fi
done

# Disable GNOME initial setup / Welcome to Fedora
echo "  - Disabling GNOME initial setup"
sudo rm -f "$ROOTFS_DIR/etc/xdg/autostart/gnome-initial-setup-first-login.desktop" 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/etc/xdg/autostart/gnome-welcome-tour.desktop" 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/usr/share/applications/org.gnome.Tour.desktop" 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/usr/share/applications/gnome-initial-setup.desktop" 2>/dev/null || true
# Also remove from autostart completely
sudo rm -rf "$ROOTFS_DIR/etc/xdg/autostart/org.gnome."* 2>/dev/null || true

# Install start.svg as the application menu icon (start-here, distributor-logo)
echo "  - Replacing Fedora icons with ArxisOS icons"
if [ -f "$BRANDING_DIR/start.svg" ]; then
    echo "    - Installing start.svg as application menu icon..."

    # Copy SVG to scalable icons
    sudo mkdir -p "$ROOTFS_DIR/usr/share/icons/hicolor/scalable/apps"
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/icons/hicolor/scalable/apps/start-here.svg"
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg"
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/icons/hicolor/scalable/apps/arxisos-start.svg"

    # Generate PNG versions from start.svg for different sizes
    if command -v convert &> /dev/null || command -v magick &> /dev/null; then
        CONVERT_CMD="convert"
        command -v magick &> /dev/null && CONVERT_CMD="magick"

        for size in 16 22 24 32 48 64 96 128 256 512; do
            ICON_DIR="$ROOTFS_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
            sudo mkdir -p "$ICON_DIR"
            echo "      - Generating ${size}x${size} icons from start.svg..."
            sudo $CONVERT_CMD -background none "$BRANDING_DIR/start.svg" -resize ${size}x${size} "$ICON_DIR/start-here.png" 2>/dev/null || true
            sudo cp "$ICON_DIR/start-here.png" "$ICON_DIR/distributor-logo.png" 2>/dev/null || true
            sudo cp "$ICON_DIR/start-here.png" "$ICON_DIR/arxisos-start.png" 2>/dev/null || true
        done
    fi

    # Copy to pixmaps
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/pixmaps/start-here.svg" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/pixmaps/distributor-logo.svg" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/pixmaps/arxisos-start.svg" 2>/dev/null || true
fi

# Install arxisos-logo.png for other branding (fedora replacements)
if [ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]; then
    echo "    - Installing arxisos-logo.png for system branding..."

    # Replace fedora-logo icons in various sizes
    for size in 16 22 24 32 48 64 96 128 256 512; do
        ICON_DIR="$ROOTFS_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
        if [ -d "$ICON_DIR" ]; then
            if command -v convert &> /dev/null || command -v magick &> /dev/null; then
                CONVERT_CMD="convert"
                command -v magick &> /dev/null && CONVERT_CMD="magick"
                sudo $CONVERT_CMD "$BRANDING_DIR/logos/arxisos-logo.png" -resize ${size}x${size} "$ICON_DIR/fedora-logo-icon.png" 2>/dev/null || true
                sudo cp "$ICON_DIR/fedora-logo-icon.png" "$ICON_DIR/fedora-logo-small.png" 2>/dev/null || true
                sudo cp "$ICON_DIR/fedora-logo-icon.png" "$ICON_DIR/arxisos-logo.png" 2>/dev/null || true
            fi
        fi
    done

    # Also replace in pixmaps
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-logo.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-logo-small.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-gdm-logo.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/system-logo-white.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/arxisos-logo.png" 2>/dev/null || true
fi

# Create ArxisOS installer desktop shortcut
echo "  - Creating ArxisOS installer shortcut"
sudo mkdir -p "$ROOTFS_DIR/usr/share/applications"
sudo tee "$ROOTFS_DIR/usr/share/applications/arxisos-installer.desktop" > /dev/null << 'INSTALLER_EOF'
[Desktop Entry]
Name=Install ArxisOS
Comment=Install ArxisOS to your hard drive
Exec=/usr/bin/liveinst
Icon=arxisos-start
Terminal=false
Type=Application
Categories=System;
StartupNotify=true
X-GNOME-Autostart-enabled=true
INSTALLER_EOF

# Create desktop shortcut for live user
sudo mkdir -p "$ROOTFS_DIR/etc/skel/Desktop"
sudo cp "$ROOTFS_DIR/usr/share/applications/arxisos-installer.desktop" "$ROOTFS_DIR/etc/skel/Desktop/"
sudo chmod +x "$ROOTFS_DIR/etc/skel/Desktop/arxisos-installer.desktop"

# Also add to autostart for live session (shows on desktop)
sudo mkdir -p "$ROOTFS_DIR/etc/xdg/autostart"
sudo tee "$ROOTFS_DIR/etc/xdg/autostart/arxisos-installer-autostart.desktop" > /dev/null << 'AUTOSTART_EOF'
[Desktop Entry]
Name=Install ArxisOS
Comment=Install ArxisOS to your hard drive
Exec=/usr/bin/cp /usr/share/applications/arxisos-installer.desktop ~/Desktop/ 2>/dev/null; chmod +x ~/Desktop/arxisos-installer.desktop 2>/dev/null
Icon=arxisos-start
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
OnlyShowIn=KDE;
AUTOSTART_EOF

# Copy fastfetch logo
if [ -f "$BRANDING_DIR/fastfetch/fastfetch-logo.txt" ]; then
    echo "  - Fastfetch logo"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/arxisos/logos"
    sudo cp "$BRANDING_DIR/fastfetch/fastfetch-logo.txt" "$ROOTFS_DIR/usr/share/arxisos/logos/"
fi

# Apply OS branding
echo "  - OS release info"
sudo tee "$ROOTFS_DIR/etc/os-release" > /dev/null << 'EOF'
NAME="ArxisOS"
VERSION="1.0 (Plasma)"
ID=arxisos
ID_LIKE=fedora
VERSION_ID=1.0
VERSION_CODENAME=Plasma
PRETTY_NAME="ArxisOS 1.0 (Plasma)"
ANSI_COLOR="0;38;2;129;212;250"
LOGO=arxisos-logo
CPE_NAME="cpe:/o:arxisos:arxisos:1"
HOME_URL="https://arxisos.com"
DOCUMENTATION_URL="https://docs.arxisos.com"
SUPPORT_URL="https://support.arxisos.com"
BUG_REPORT_URL="https://github.com/arxisos/arxisos/issues"
PRIVACY_POLICY_URL="https://arxisos.com/privacy"
DEVELOPER="Brad Heffernan"
EOF

echo "ArxisOS release 1.0 (Plasma)" | sudo tee "$ROOTFS_DIR/etc/system-release" > /dev/null
echo "ArxisOS release 1.0 (Plasma)" | sudo tee "$ROOTFS_DIR/etc/arxisos-release" > /dev/null

# Create lsb-release
sudo tee "$ROOTFS_DIR/etc/lsb-release" > /dev/null << 'EOF'
DISTRIB_ID=ArxisOS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=Plasma
DISTRIB_DESCRIPTION="ArxisOS 1.0 (Plasma)"
DISTRIB_DEVELOPER="Brad Heffernan"
EOF

# Create first-boot service to finalize GRUB configuration after installation
# This ensures any duplicate entries from the live media are removed
echo "  - Creating first-boot GRUB cleanup service"
sudo tee "$ROOTFS_DIR/etc/systemd/system/arxisos-first-boot.service" > /dev/null << 'FIRSTBOOT_EOF'
[Unit]
Description=ArxisOS First Boot Setup
After=local-fs.target network.target
ConditionPathExists=!/var/lib/arxisos-first-boot-done

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
    # Only run on installed system (not live) \
    if [ ! -d /run/initramfs/live ] && ! grep -q "root=live:" /proc/cmdline 2>/dev/null; then \
        # Regenerate GRUB config \
        grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || true; \
        if [ -d /boot/efi/EFI/fedora ]; then \
            grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || true; \
        fi; \
        # Remove liveuser account (only on installed system) \
        if id liveuser &>/dev/null; then \
            userdel -r liveuser 2>/dev/null || true; \
            rm -f /etc/sudoers.d/liveuser 2>/dev/null || true; \
            rm -f /var/lib/AccountsService/users/liveuser 2>/dev/null || true; \
        fi; \
        # Set default avatar for all users without one \
        for user_home in /home/*; do \
            username=$(basename "$user_home"); \
            if [ -d "$user_home" ] && [ "$username" != "liveuser" ]; then \
                if [ ! -f "$user_home/.face.icon" ]; then \
                    cp /usr/share/sddm/faces/.face.icon "$user_home/.face.icon" 2>/dev/null || true; \
                    chown "$username:$username" "$user_home/.face.icon" 2>/dev/null || true; \
                fi; \
                # Set Plasma X11 as default session for all users \
                mkdir -p /var/lib/AccountsService/users; \
                if [ ! -f "/var/lib/AccountsService/users/$username" ]; then \
                    echo "[User]" > "/var/lib/AccountsService/users/$username"; \
                    echo "Session=plasmax11" >> "/var/lib/AccountsService/users/$username"; \
                    echo "XSession=plasmax11" >> "/var/lib/AccountsService/users/$username"; \
                    echo "Icon=$user_home/.face.icon" >> "/var/lib/AccountsService/users/$username"; \
                fi; \
            fi; \
        done; \
    fi'
ExecStartPost=/bin/touch /var/lib/arxisos-first-boot-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FIRSTBOOT_EOF

sudo chroot "$ROOTFS_DIR" systemctl enable arxisos-first-boot.service 2>/dev/null || true

# IMPORTANT: Set dnf releasever so package updates work after installation
# This overrides the os-release VERSION_ID for dnf purposes only
echo "  - Setting dnf releasever for Fedora 43 repos"
sudo mkdir -p "$ROOTFS_DIR/etc/dnf/vars"
echo "43" | sudo tee "$ROOTFS_DIR/etc/dnf/vars/releasever" > /dev/null

# Fix SELinux - DISABLE for live environment to avoid boot delays
# The autorelabel process takes too long and blocks desktop loading
echo "  - Disabling SELinux for live environment"
if [ -f "$ROOTFS_DIR/etc/selinux/config" ]; then
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' "$ROOTFS_DIR/etc/selinux/config"
    sudo sed -i 's/^SELINUX=permissive/SELINUX=disabled/' "$ROOTFS_DIR/etc/selinux/config"
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' "$ROOTFS_DIR/etc/sysconfig/selinux" 2>/dev/null || true
    sudo sed -i 's/^SELINUX=permissive/SELINUX=disabled/' "$ROOTFS_DIR/etc/sysconfig/selinux" 2>/dev/null || true
fi
# Remove autorelabel flag - we don't want relabeling on live boot
sudo rm -f "$ROOTFS_DIR/.autorelabel"

# Unmount rootfs if it was mounted
echo "Repackaging..."
if [ "$MOUNTED_ROOTFS" = true ]; then
    sudo umount "$ROOTFS_DIR"
fi

# Recreate squashfs
echo "Creating new squashfs (this may take a while)..."
mkdir -p "$WORK_DIR/new_iso/LiveOS"
sudo mksquashfs "$WORK_DIR/squashfs" "$WORK_DIR/new_iso/LiveOS/squashfs.img" -comp xz -b 1M

# Unmount original ISO
sudo umount "$WORK_DIR/iso"

# ============================================
# SETUP BIOS GRUB THEMING
# ============================================
echo "Setting up BIOS GRUB theming..."

if [ -f "$WORK_DIR/new_iso/images/eltorito.img" ]; then
    # Copy GRUB fonts for BIOS boot
    echo "  - Copying GRUB fonts..."
    sudo mkdir -p "$WORK_DIR/new_iso/boot/grub2/fonts"
    if [ -f /usr/share/grub/unicode.pf2 ]; then
        sudo cp /usr/share/grub/unicode.pf2 "$WORK_DIR/new_iso/boot/grub2/fonts/"
    elif [ -f /boot/grub2/fonts/unicode.pf2 ]; then
        sudo cp /boot/grub2/fonts/unicode.pf2 "$WORK_DIR/new_iso/boot/grub2/fonts/"
    fi

    # Copy i386-pc GRUB modules to ISO for runtime loading
    echo "  - Copying GRUB modules for BIOS..."
    sudo mkdir -p "$WORK_DIR/new_iso/boot/grub2/i386-pc"
    GRUB_I386_DIR=""
    if [ -d /usr/lib/grub/i386-pc ]; then
        GRUB_I386_DIR="/usr/lib/grub/i386-pc"
    elif [ -d /usr/share/grub2/i386-pc ]; then
        GRUB_I386_DIR="/usr/share/grub2/i386-pc"
    fi

    if [ -n "$GRUB_I386_DIR" ]; then
        sudo cp "$GRUB_I386_DIR"/*.mod "$WORK_DIR/new_iso/boot/grub2/i386-pc/" 2>/dev/null || true
        sudo cp "$GRUB_I386_DIR"/*.lst "$WORK_DIR/new_iso/boot/grub2/i386-pc/" 2>/dev/null || true

        # Rebuild eltorito.img with proper El Torito format (cdboot.img + core.img)
        if [ -f "$GRUB_I386_DIR/cdboot.img" ]; then
            echo "  - Rebuilding eltorito.img with graphics support..."

            # Modules to embed in the core image
            GRUB_MODULES="iso9660 biosdisk search search_label configfile normal boot linux echo part_gpt part_msdos fat ext2 all_video gfxterm gfxmenu png"

            # Create core.img
            GRUB_MKIMAGE=""
            if command -v grub2-mkimage &> /dev/null; then
                GRUB_MKIMAGE="grub2-mkimage"
            elif command -v grub-mkimage &> /dev/null; then
                GRUB_MKIMAGE="grub-mkimage"
            fi

            if [ -n "$GRUB_MKIMAGE" ]; then
                # Create the core image
                sudo $GRUB_MKIMAGE \
                    -O i386-pc \
                    -o "$WORK_DIR/core.img" \
                    -p /boot/grub2 \
                    $GRUB_MODULES \
                    2>/dev/null

                if [ -f "$WORK_DIR/core.img" ]; then
                    # Combine cdboot.img + core.img to create proper El Torito image
                    sudo cat "$GRUB_I386_DIR/cdboot.img" "$WORK_DIR/core.img" > "$WORK_DIR/new_iso/images/eltorito.img"
                    sudo rm -f "$WORK_DIR/core.img"
                    echo "    El Torito boot image rebuilt with graphics modules"
                else
                    echo "    Warning: Failed to create core.img, keeping original eltorito.img"
                fi
            else
                echo "    Warning: grub2-mkimage not found, keeping original eltorito.img"
            fi
        else
            echo "    Warning: cdboot.img not found, keeping original eltorito.img"
        fi
    fi
fi
# ============================================

# Create new ISO
echo "Creating new ISO with volume label: $ISO_LABEL"
# Check if isolinux exists (traditional) or eltorito.img (osbuild)
if [ -f "$WORK_DIR/new_iso/isolinux/isolinux.bin" ]; then
    # Traditional Fedora live ISO with isolinux
    sudo xorrisofs -o "$ISO_OUTPUT" \
        -R -J -V "$ISO_LABEL" \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e images/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        "$WORK_DIR/new_iso"
else
    # OSBuild format with eltorito.img for BIOS and efiboot.img for EFI
    sudo xorrisofs -o "$ISO_OUTPUT" \
        -R -J -V "$ISO_LABEL" \
        -b images/eltorito.img \
        -c images/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e images/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        "$WORK_DIR/new_iso"
fi

# Clean up
echo "Cleaning up..."
sudo rm -rf "$WORK_DIR"

echo ""
echo "=== Branding Complete ==="
echo "Output: $ISO_OUTPUT"
echo "Size: $(du -h "$ISO_OUTPUT" | cut -f1)"
