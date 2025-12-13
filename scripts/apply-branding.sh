#!/bin/bash
set -euo pipefail

# Apply ArxisOS branding to a Fedora live ISO

# Cleanup function for error handling
cleanup_on_error() {
    echo "ERROR: Script failed. Cleaning up..."
    local work_dir="/var/tmp/arxisos-remaster"
    sudo umount "$work_dir/squashfs/run" 2>/dev/null || true
    sudo umount "$work_dir/squashfs/sys" 2>/dev/null || true
    sudo umount "$work_dir/squashfs/proc" 2>/dev/null || true
    sudo umount "$work_dir/squashfs/dev" 2>/dev/null || true
    sudo umount "$work_dir/squashfs/rootfs" 2>/dev/null || true
    sudo umount "$work_dir/squashfs" 2>/dev/null || true
    sudo umount "$work_dir/iso" 2>/dev/null || true
    exit 1
}
trap cleanup_on_error ERR
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

# Clean up previous work - unmount any existing mounts first
echo "Cleaning up previous work..."
sudo umount "$WORK_DIR/squashfs/rootfs" 2>/dev/null || true
sudo umount "$WORK_DIR/squashfs" 2>/dev/null || true
sudo umount "$WORK_DIR/iso" 2>/dev/null || true
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

    # Add GRUB theme configuration at the beginning of the file
    if ! grep -q "set theme=" "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"; then
        # Create temp file with theme config prepended
        # Use ($root) to reference the boot device (ISO filesystem)
        {
            echo '# ArxisOS GRUB Theme'
            echo 'insmod gfxterm'
            echo 'insmod png'
            echo 'set gfxmode=auto'
            echo 'terminal_output gfxterm'
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

    # Add GRUB theme configuration for BIOS boot
    if ! grep -q "set theme=" "$WORK_DIR/new_iso/boot/grub2/grub.cfg"; then
        {
            echo '# ArxisOS GRUB Theme'
            echo 'insmod gfxterm'
            echo 'insmod png'
            echo 'set gfxmode=auto'
            echo 'terminal_output gfxterm'
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
        echo "  - Replacing Fedora logos in initrd Plymouth themes"

        # Create smaller, elegant version of logo for Plymouth (128px wide)
        PLYMOUTH_LOGO="/tmp/arxisos-plymouth-logo.png"
        if command -v convert &> /dev/null; then
            echo "    Creating resized Plymouth logo (128px)..."
            convert "$BRANDING_DIR/logos/arxisos-logo.png" -resize 128x128 -background transparent -gravity center "$PLYMOUTH_LOGO" 2>/dev/null || \
                cp "$BRANDING_DIR/logos/arxisos-logo.png" "$PLYMOUTH_LOGO"
        else
            cp "$BRANDING_DIR/logos/arxisos-logo.png" "$PLYMOUTH_LOGO"
        fi

        # Find ALL png files in plymouth themes and replace any that look like logos/watermarks
        sudo find "$INITRD_WORK/usr/share/plymouth/themes" -name "*.png" -type f | while read -r pngfile; do
            filename=$(basename "$pngfile")
            # Replace watermark, logo, fedora-related images
            case "$filename" in
                *watermark*|*logo*|*fedora*|*bgrt*)
                    echo "    Replacing: $pngfile"
                    sudo cp "$PLYMOUTH_LOGO" "$pngfile" 2>/dev/null || true
                    ;;
            esac
        done

        # Explicitly replace spinner watermark (this is the "fedora" logo at bottom)
        if [ -d "$INITRD_WORK/usr/share/plymouth/themes/spinner" ]; then
            sudo cp "$PLYMOUTH_LOGO" "$INITRD_WORK/usr/share/plymouth/themes/spinner/watermark.png" 2>/dev/null || true
        fi

        # Replace bgrt watermark
        if [ -d "$INITRD_WORK/usr/share/plymouth/themes/bgrt" ]; then
            sudo cp "$PLYMOUTH_LOGO" "$INITRD_WORK/usr/share/plymouth/themes/bgrt/watermark.png" 2>/dev/null || true
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
    mkdir -p "$ROOTFS_DIR"
    sudo mount -o loop "$ROOTFS_IMG" "$ROOTFS_DIR"
    ROOTFS_DIR="$ROOTFS_DIR"
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
sudo chroot "$ROOTFS_DIR" dnf install -y --releasever=43 --allowerasing \
    plasma-desktop plasma-workspace sddm sddm-kcm \
    konsole dolphin kate ark gwenview okular spectacle \
    plasma-nm plasma-pa bluedevil powerdevil kscreen \
    kwin breeze-gtk breeze-icon-theme \
    NetworkManager-wifi NetworkManager-bluetooth \
    2>&1 | tail -50 || echo "Warning: Some packages may have failed"

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

# Unmount bind mounts
sudo umount "$ROOTFS_DIR/run" 2>/dev/null || true
sudo umount "$ROOTFS_DIR/sys" 2>/dev/null || true
sudo umount "$ROOTFS_DIR/proc" 2>/dev/null || true
sudo umount "$ROOTFS_DIR/dev" 2>/dev/null || true

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

    # Create smaller, elegant version of logo for Plymouth (128px wide)
    PLYMOUTH_LOGO_ROOTFS="/tmp/arxisos-plymouth-logo-rootfs.png"
    if command -v convert &> /dev/null; then
        convert "$BRANDING_DIR/logos/arxisos-logo.png" -resize 128x128 -background transparent -gravity center "$PLYMOUTH_LOGO_ROOTFS" 2>/dev/null || \
            cp "$BRANDING_DIR/logos/arxisos-logo.png" "$PLYMOUTH_LOGO_ROOTFS"
    else
        cp "$BRANDING_DIR/logos/arxisos-logo.png" "$PLYMOUTH_LOGO_ROOTFS"
    fi

    # Replace Fedora watermark with ArxisOS logo in spinner theme
    if [ -d "$ROOTFS_DIR/usr/share/plymouth/themes/spinner" ]; then
        sudo cp "$PLYMOUTH_LOGO_ROOTFS" "$ROOTFS_DIR/usr/share/plymouth/themes/spinner/watermark.png" 2>/dev/null || true
    fi

    # Also replace in bgrt theme (BIOS/UEFI logo fallback)
    if [ -d "$ROOTFS_DIR/usr/share/plymouth/themes/bgrt" ]; then
        sudo cp "$PLYMOUTH_LOGO_ROOTFS" "$ROOTFS_DIR/usr/share/plymouth/themes/bgrt/watermark.png" 2>/dev/null || true
    fi

    rm -f "$PLYMOUTH_LOGO_ROOTFS"
fi

# Copy GRUB theme
if [ -d "$BRANDING_DIR/grub/arxisos" ]; then
    echo "  - GRUB theme"
    sudo mkdir -p "$ROOTFS_DIR/boot/grub2/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/grub/arxisos/"* "$ROOTFS_DIR/boot/grub2/themes/arxisos/"

    # Enable GRUB theme in configuration
    echo "  - Enabling GRUB theme"
    sudo mkdir -p "$ROOTFS_DIR/etc/default"
    if [ -f "$ROOTFS_DIR/etc/default/grub" ]; then
        # Remove any existing GRUB_THEME line
        sudo sed -i '/^GRUB_THEME=/d' "$ROOTFS_DIR/etc/default/grub"
    fi
    # Add GRUB_THEME configuration
    echo 'GRUB_THEME="/boot/grub2/themes/arxisos/theme.txt"' | sudo tee -a "$ROOTFS_DIR/etc/default/grub" > /dev/null
fi

# Copy SDDM theme
if [ -d "$BRANDING_DIR/sddm/arxisos" ]; then
    echo "  - SDDM theme"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/sddm/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/sddm/arxisos/"* "$ROOTFS_DIR/usr/share/sddm/themes/arxisos/"
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

# Copy Aurorae window decoration theme
if [ -d "$BRANDING_DIR/aurorae/PurPurNight-Blur-Aurorae-6" ]; then
    echo "  - PurPurNight Aurorae window decoration"
    sudo mkdir -p "$ROOTFS_DIR/usr/share/aurorae/themes"
    sudo cp -r "$BRANDING_DIR/aurorae/PurPurNight-Blur-Aurorae-6" "$ROOTFS_DIR/usr/share/aurorae/themes/"
fi

# Copy skel (default user configuration)
if [ -d "$BRANDING_DIR/skel" ]; then
    echo "  - User skeleton configuration"
    sudo cp -r "$BRANDING_DIR/skel/." "$ROOTFS_DIR/etc/skel/"
    # Ensure .local/bin is executable
    sudo chmod +x "$ROOTFS_DIR/etc/skel/.local/bin/"* 2>/dev/null || true
fi

# Update icon cache
echo "  - Updating icon caches"
sudo chroot "$ROOTFS_DIR" gtk-update-icon-cache -f /usr/share/icons/Vivid-Glassy-Dark-Icons 2>/dev/null || true
sudo chroot "$ROOTFS_DIR" gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

# Configure SDDM to use the theme and Plasma session
echo "  - SDDM configuration"
sudo mkdir -p "$ROOTFS_DIR/etc/sddm.conf.d"
sudo tee "$ROOTFS_DIR/etc/sddm.conf.d/arxisos.conf" > /dev/null << 'SDDM_EOF'
[Theme]
Current=arxisos
CursorTheme=oreo_white_cursors

[Autologin]
Session=plasma

[General]
DefaultSession=plasma.desktop
SDDM_EOF

# Set Plasma as default session and SDDM as display manager
echo "  - Setting Plasma as default session"
sudo mkdir -p "$ROOTFS_DIR/etc/X11/xinit"
echo "PREFERRED=plasma" | sudo tee "$ROOTFS_DIR/etc/sysconfig/desktop" > /dev/null 2>&1 || true

# Configure AccountsService for live user to use Plasma
echo "  - Configuring live user for Plasma session"
sudo mkdir -p "$ROOTFS_DIR/var/lib/AccountsService/users"
# Configure for common live user names
for liveuser in liveuser live arxis; do
    sudo tee "$ROOTFS_DIR/var/lib/AccountsService/users/$liveuser" > /dev/null << ACCOUNTSEOF
[User]
Session=plasma
XSession=plasma
Icon=/usr/share/pixmaps/arxisos-logo.png
SystemAccount=false
ACCOUNTSEOF
done

# Configure GDM custom.conf to use Plasma if GDM is used
echo "  - Configuring GDM for Plasma session"
sudo mkdir -p "$ROOTFS_DIR/etc/gdm"
sudo tee "$ROOTFS_DIR/etc/gdm/custom.conf" > /dev/null << 'GDMCONF'
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=liveuser
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

# Create default session symlink
sudo mkdir -p "$ROOTFS_DIR/usr/share/xsessions"
if [ -f "$ROOTFS_DIR/usr/share/xsessions/plasma.desktop" ]; then
    sudo ln -sf plasma.desktop "$ROOTFS_DIR/usr/share/xsessions/default.desktop" 2>/dev/null || true
fi

# Disable GNOME initial setup / Welcome to Fedora
echo "  - Disabling GNOME initial setup"
sudo rm -f "$ROOTFS_DIR/etc/xdg/autostart/gnome-initial-setup-first-login.desktop" 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/etc/xdg/autostart/gnome-welcome-tour.desktop" 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/usr/share/applications/org.gnome.Tour.desktop" 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/usr/share/applications/gnome-initial-setup.desktop" 2>/dev/null || true
# Also remove from autostart completely
sudo rm -rf "$ROOTFS_DIR/etc/xdg/autostart/org.gnome."* 2>/dev/null || true

# Replace Fedora icons with ArxisOS icons (keep filenames for compatibility)
echo "  - Replacing Fedora icons with ArxisOS icons"
if [ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]; then
    # Replace fedora-logo icons in various sizes
    for size in 16 22 24 32 48 64 96 128 256 512; do
        ICON_DIR="$ROOTFS_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
        if [ -d "$ICON_DIR" ]; then
            # Convert and copy ArxisOS logo as fedora-logo
            if command -v convert &> /dev/null; then
                sudo convert "$BRANDING_DIR/logos/arxisos-logo.png" -resize ${size}x${size} "$ICON_DIR/fedora-logo-icon.png" 2>/dev/null || true
                sudo cp "$ICON_DIR/fedora-logo-icon.png" "$ICON_DIR/fedora-logo-small.png" 2>/dev/null || true
                sudo cp "$ICON_DIR/fedora-logo-icon.png" "$ICON_DIR/start-here.png" 2>/dev/null || true
            fi
        fi
    done
    # Also replace in pixmaps
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-logo.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-logo-small.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-gdm-logo.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/system-logo-white.png" 2>/dev/null || true
fi

# Create ArxisOS installer desktop shortcut
echo "  - Creating ArxisOS installer shortcut"
sudo mkdir -p "$ROOTFS_DIR/usr/share/applications"
sudo tee "$ROOTFS_DIR/usr/share/applications/arxisos-installer.desktop" > /dev/null << 'INSTALLER_EOF'
[Desktop Entry]
Name=Install ArxisOS
Comment=Install ArxisOS to your hard drive
Exec=/usr/bin/liveinst
Icon=arxisos-logo
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
Icon=arxisos-logo
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

# IMPORTANT: Set dnf releasever so package updates work after installation
# This overrides the os-release VERSION_ID for dnf purposes only
echo "  - Setting dnf releasever for Fedora 43 repos"
sudo mkdir -p "$ROOTFS_DIR/etc/dnf/vars"
echo "43" | sudo tee "$ROOTFS_DIR/etc/dnf/vars/releasever" > /dev/null

# Fix SELinux - set to permissive to avoid boot issues from modified files
echo "  - Configuring SELinux for live environment"
if [ -f "$ROOTFS_DIR/etc/selinux/config" ]; then
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' "$ROOTFS_DIR/etc/selinux/config"
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' "$ROOTFS_DIR/etc/sysconfig/selinux" 2>/dev/null || true
fi
# Also create autorelabel flag for first boot after install
sudo touch "$ROOTFS_DIR/.autorelabel"

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
