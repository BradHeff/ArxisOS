#!/bin/bash
set -euo pipefail

# ArxisOS branding script for osbuild-composer ISOs
# Applies: SDDM, Plasma, Plymouth, GRUB, icons, cursors, wallpapers, logos, skel
# Replaces GNOME with KDE Plasma, GDM with SDDM
# Creates live user with autologin, removes on install

BUILD_DIR="/home/bheffernan/arxisos-build"
BRANDING_DIR="$BUILD_DIR/branding"
PLASMA_CFG_DIR="$BUILD_DIR/PLASMA-CONFIGS"
SKEL_DIR="$BUILD_DIR/Skel"
WORK_DIR="/var/tmp/arxisos-composer-branding"
ISO_LABEL="ArxisOS-1-0-x86_64"

input_iso="${1:-}"
output_iso="${2:-$BUILD_DIR/ArxisOS-1.0-x86_64.iso}"

if [[ -z "$input_iso" || ! -f "$input_iso" ]]; then
    echo "Usage: $0 <input-iso> [output-iso]"
    exit 1
fi

# Cleanup function - handles ALL exit scenarios including Ctrl+C
cleanup_mounts() {
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "ERROR: Script failed (exit code: $exit_code). Cleaning up mounts..."
    fi

    # Unmount bind mounts first (in reverse order) - critical to prevent /dev/null errors
    for mount_point in run sys proc dev; do
        sudo umount -l "$WORK_DIR/squashfs/rootfs/$mount_point" 2>/dev/null || true
        sudo umount -l "$WORK_DIR/squashfs/$mount_point" 2>/dev/null || true
    done

    sleep 1

    # Unmount EFI image if mounted
    sudo umount -l "$WORK_DIR/efi" 2>/dev/null || true

    # Unmount rootfs.img if mounted
    sudo umount -l "$WORK_DIR/squashfs/rootfs" 2>/dev/null || true

    # Unmount squashfs
    sudo umount -l "$WORK_DIR/squashfs" 2>/dev/null || true

    # Unmount ISO
    sudo umount -l "$WORK_DIR/iso" 2>/dev/null || true

    # Detach loop devices
    for loop in $(losetup -a 2>/dev/null | grep "$WORK_DIR" | cut -d: -f1); do
        sudo losetup -d "$loop" 2>/dev/null || true
    done

    if [ $exit_code -ne 0 ]; then
        echo "Cleanup complete."
        exit $exit_code
    fi
}
trap cleanup_mounts EXIT
trap 'exit 1' INT TERM

echo "=== ArxisOS Branding Script (Composer ISO) ==="
echo "Input : $input_iso"
echo "Output: $output_iso"
echo ""

# Pre-flight cleanup of any leftover mounts from previous runs
echo "Cleaning up any previous work..."
for mount_point in run sys proc dev; do
    sudo umount -l "$WORK_DIR/squashfs/rootfs/$mount_point" 2>/dev/null || true
    sudo umount -l "$WORK_DIR/squashfs/$mount_point" 2>/dev/null || true
done
sudo umount -l "$WORK_DIR/efi" 2>/dev/null || true
sudo umount -l "$WORK_DIR/squashfs/rootfs" 2>/dev/null || true
sudo umount -l "$WORK_DIR/squashfs" 2>/dev/null || true
sudo umount -l "$WORK_DIR/iso" 2>/dev/null || true
for loop in $(losetup -a 2>/dev/null | grep "$WORK_DIR" | cut -d: -f1); do
    sudo losetup -d "$loop" 2>/dev/null || true
done
sleep 1

sudo rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"/{iso,squashfs,new_iso,efi}

# Helper function
copy_if_exists() {
    local src="$1" dest="$2"
    [[ -e "$src" ]] || return 0
    sudo mkdir -p "$(dirname "$dest")"
    sudo cp -r "$src" "$dest"
}

echo "Mounting ISO..."
sudo mount -o loop "$input_iso" "$WORK_DIR/iso"

echo "Copying ISO contents (excluding squashfs)..."
sudo rsync -a --exclude='LiveOS/squashfs.img' "$WORK_DIR/iso/" "$WORK_DIR/new_iso/"

echo "Extracting squashfs..."
sudo unsquashfs -d "$WORK_DIR/squashfs" "$WORK_DIR/iso/LiveOS/squashfs.img" > /dev/null

# Detect format and set ROOTFS_DIR
ROOTFS_IMG=$(sudo find "$WORK_DIR/squashfs" -maxdepth 2 -name "rootfs.img" 2>/dev/null | head -1)
MOUNTED_ROOTFS=false
if [[ -n "$ROOTFS_IMG" ]]; then
    echo "Traditional format detected (rootfs.img)"
    ROOTFS_DIR="$WORK_DIR/squashfs/rootfs"
    sudo mkdir -p "$ROOTFS_DIR"
    sudo mount -o loop "$ROOTFS_IMG" "$ROOTFS_DIR"
    MOUNTED_ROOTFS=true
else
    echo "OSBuild format detected (squashfs is rootfs)"
    ROOTFS_DIR="$WORK_DIR/squashfs"
fi

# Bind mounts for chroot operations
echo "Setting up chroot environment..."
sudo mount --bind /dev "$ROOTFS_DIR/dev"
sudo mount --bind /proc "$ROOTFS_DIR/proc"
sudo mount --bind /sys "$ROOTFS_DIR/sys"
sudo mount --bind /run "$ROOTFS_DIR/run"

# Ensure DNS works in chroot
if [[ -L "$ROOTFS_DIR/etc/resolv.conf" ]]; then
    sudo rm -f "$ROOTFS_DIR/etc/resolv.conf"
fi
sudo cp -L /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf" 2>/dev/null || \
    echo "nameserver 8.8.8.8" | sudo tee "$ROOTFS_DIR/etc/resolv.conf" >/dev/null

# ============================================
# INSTALL KDE PLASMA / REMOVE GNOME
# ============================================
echo ""
echo "=== Installing KDE Plasma Desktop ==="
echo "  (This may take 10-20 minutes...)"

sudo chroot "$ROOTFS_DIR" dnf install -y --releasever=43 --allowerasing \
    plasma-desktop plasma-workspace plasma-workspace-x11 sddm sddm-kcm \
    konsole dolphin kate ark gwenview okular spectacle \
    plasma-nm plasma-pa bluedevil powerdevil kscreen \
    kwin kwin-x11 breeze-gtk breeze-icon-theme \
    xorg-x11-server-Xorg xorg-x11-drv-libinput xorg-x11-xinit \
    plasma-systemmonitor plasma-discover \
    NetworkManager-wifi NetworkManager-bluetooth \
    dbus-x11 xdg-desktop-portal-kde \
    grub2-efi-x64 grub2-efi-x64-modules shim-x64 \
    grub2-tools grub2-tools-extra efibootmgr grub2-common \
    plymouth plymouth-system-theme plymouth-plugin-script \
    dracut \
    || echo "Warning: Some packages may have failed"

echo "Removing GNOME packages..."
sudo chroot "$ROOTFS_DIR" dnf remove -y --releasever=43 --noautoremove \
    gnome-shell gnome-session gnome-tour gnome-initial-setup \
    gdm gnome-control-center gnome-settings-daemon \
    2>/dev/null || true

# ============================================
# CONFIGURE DISPLAY MANAGER (SDDM)
# ============================================
echo ""
echo "=== Configuring SDDM and Plasma Session ==="

sudo chroot "$ROOTFS_DIR" systemctl set-default graphical.target 2>/dev/null || true
sudo chroot "$ROOTFS_DIR" systemctl disable gdm.service 2>/dev/null || true
sudo chroot "$ROOTFS_DIR" systemctl enable sddm.service 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/etc/systemd/system/display-manager.service"
sudo ln -sf /usr/lib/systemd/system/sddm.service "$ROOTFS_DIR/etc/systemd/system/display-manager.service"

# ============================================
# CREATE LIVE USER
# ============================================
echo ""
echo "=== Creating Live User ==="

if ! sudo chroot "$ROOTFS_DIR" id liveuser &>/dev/null; then
    sudo chroot "$ROOTFS_DIR" useradd -m -G wheel -s /bin/bash liveuser 2>/dev/null || true
    sudo chroot "$ROOTFS_DIR" passwd -d liveuser 2>/dev/null || true
fi

sudo mkdir -p "$ROOTFS_DIR/home/liveuser/.config"
sudo mkdir -p "$ROOTFS_DIR/home/liveuser/Desktop"

# Passwordless sudo for live user
echo "liveuser ALL=(ALL) NOPASSWD: ALL" | sudo tee "$ROOTFS_DIR/etc/sudoers.d/liveuser" > /dev/null
sudo chmod 440 "$ROOTFS_DIR/etc/sudoers.d/liveuser"

# ============================================
# LIVE SESSION AUTOLOGIN SERVICE
# ============================================
echo "  - Creating live session autologin service..."
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

# ============================================
# LIVEUSER SETUP SERVICE (ensures configs on boot)
# ============================================
echo "  - Creating liveuser setup service..."
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
# FIRST-BOOT SERVICE (removes liveuser after install)
# ============================================
echo "  - Creating first-boot cleanup service..."
sudo tee "$ROOTFS_DIR/etc/systemd/system/arxisos-first-boot.service" > /dev/null << 'FIRSTBOOT_EOF'
[Unit]
Description=ArxisOS First Boot Setup - Remove live user and configure Plasma
After=local-fs.target network.target systemd-user-sessions.service
Before=display-manager.service
ConditionPathExists=!/var/lib/arxisos-first-boot-done

[Service]
Type=oneshot
ExecStart=/usr/bin/bash /usr/local/bin/arxisos-first-boot.sh
ExecStartPost=/bin/touch /var/lib/arxisos-first-boot-done
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FIRSTBOOT_EOF

# Create the first-boot script (easier to debug than inline)
sudo tee "$ROOTFS_DIR/usr/local/bin/arxisos-first-boot.sh" > /dev/null << 'FIRSTBOOT_SCRIPT'
#!/bin/bash
# ArxisOS First Boot Script
# Runs once on first boot of INSTALLED system

LOG="/var/log/arxisos-first-boot.log"
echo "$(date): ArxisOS first-boot starting" > "$LOG"

# Check if this is a live environment
if [ -d /run/initramfs/live ] || grep -q "rd.live" /proc/cmdline 2>/dev/null; then
    echo "$(date): Live environment detected, skipping" >> "$LOG"
    exit 0
fi

echo "$(date): Installed system detected, running cleanup" >> "$LOG"

# Remove liveuser account
if id liveuser &>/dev/null; then
    echo "$(date): Removing liveuser account" >> "$LOG"
    pkill -u liveuser 2>/dev/null || true
    sleep 1
    userdel -rf liveuser 2>/dev/null || true
    rm -rf /home/liveuser 2>/dev/null || true
    rm -f /etc/sudoers.d/liveuser 2>/dev/null || true
    rm -f /var/lib/AccountsService/users/liveuser 2>/dev/null || true
fi

# Remove live autologin config
rm -f /etc/sddm.conf.d/live-autologin.conf 2>/dev/null || true

# Ensure SDDM is the display manager (not GDM)
echo "$(date): Ensuring SDDM is display manager" >> "$LOG"
systemctl disable gdm.service 2>/dev/null || true
systemctl enable sddm.service 2>/dev/null || true
rm -f /etc/systemd/system/display-manager.service 2>/dev/null || true
ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service 2>/dev/null || true

# Set Plasma X11 session for all users
echo "$(date): Setting Plasma session for users" >> "$LOG"
for user_home in /home/*; do
    username=$(basename "$user_home")
    if [ -d "$user_home" ] && [ "$username" != "liveuser" ] && id "$username" &>/dev/null; then
        mkdir -p /var/lib/AccountsService/users
        cat > "/var/lib/AccountsService/users/$username" << USEREOF
[User]
Session=plasmax11
XSession=plasmax11
SystemAccount=false
USEREOF
        echo "$(date): Configured $username for Plasma" >> "$LOG"
    fi
done

# Regenerate GRUB config with ArxisOS theme
echo "$(date): Regenerating GRUB config" >> "$LOG"

# Ensure GRUB theme exists
if [ ! -d /boot/grub2/themes/arxisos ]; then
    echo "$(date): WARNING - ArxisOS GRUB theme not found at /boot/grub2/themes/arxisos" >> "$LOG"
fi

# Regenerate GRUB for BIOS
grub2-mkconfig -o /boot/grub2/grub.cfg 2>>"$LOG" || true

# Regenerate GRUB for EFI (check multiple possible locations)
if [ -d /boot/efi/EFI/fedora ]; then
    grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>>"$LOG" || true
    echo "$(date): EFI GRUB config updated (fedora path)" >> "$LOG"
fi
if [ -d /boot/efi/EFI/arxisos ]; then
    grub2-mkconfig -o /boot/efi/EFI/arxisos/grub.cfg 2>>"$LOG" || true
    echo "$(date): EFI GRUB config updated (arxisos path)" >> "$LOG"
fi

# Regenerate initramfs with Plymouth
echo "$(date): Regenerating initramfs with Plymouth" >> "$LOG"
KERNEL_VER=$(uname -r)
if [ -n "$KERNEL_VER" ]; then
    dracut -f "/boot/initramfs-${KERNEL_VER}.img" "$KERNEL_VER" 2>>"$LOG" || true
    echo "$(date): initramfs regenerated for kernel $KERNEL_VER" >> "$LOG"
else
    # Regenerate for all installed kernels
    dracut -f 2>>"$LOG" || true
    echo "$(date): initramfs regenerated for all kernels" >> "$LOG"
fi

echo "$(date): First-boot complete" >> "$LOG"
FIRSTBOOT_SCRIPT

sudo chmod +x "$ROOTFS_DIR/usr/local/bin/arxisos-first-boot.sh"
sudo chroot "$ROOTFS_DIR" systemctl enable arxisos-first-boot.service 2>/dev/null || true

# ============================================
# UNMOUNT BIND MOUNTS (chroot operations done)
# ============================================
echo ""
echo "Unmounting chroot bind mounts..."
sync
sudo umount -l "$ROOTFS_DIR/run" 2>/dev/null || true
sudo umount -l "$ROOTFS_DIR/sys" 2>/dev/null || true
sudo umount -l "$ROOTFS_DIR/proc" 2>/dev/null || true
sudo umount -l "$ROOTFS_DIR/dev" 2>/dev/null || true
sleep 1

# Verify mounts released
if mount | grep -q "$ROOTFS_DIR/dev"; then
    echo "WARNING: /dev still mounted, forcing unmount..."
    sudo fuser -km "$ROOTFS_DIR/dev" 2>/dev/null || true
    sudo umount -f "$ROOTFS_DIR/dev" 2>/dev/null || true
fi

# ============================================
# PLYMOUTH THEME
# ============================================
echo ""
echo "=== Applying Plymouth Boot Splash ==="

if [[ -d "$BRANDING_DIR/plymouth/arxisos" ]]; then
    echo "  - Copying ArxisOS Plymouth theme..."
    sudo mkdir -p "$ROOTFS_DIR/usr/share/plymouth/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/plymouth/arxisos/"* "$ROOTFS_DIR/usr/share/plymouth/themes/arxisos/"

    # Configure Plymouth
    sudo mkdir -p "$ROOTFS_DIR/etc/plymouth"
    sudo tee "$ROOTFS_DIR/etc/plymouth/plymouthd.conf" >/dev/null <<'PLYCONF'
[Daemon]
Theme=spinner
ShowDelay=0
DeviceTimeout=8
PLYCONF

    # Replace watermarks in spinner and bgrt themes with ArxisOS logo
    # Watermark should be small (48-64px) - it appears at bottom of screen
    echo "  - Replacing Plymouth watermarks..."
    PLYMOUTH_LOGO="/tmp/arxisos-plymouth-watermark.png"
    WATERMARK_CREATED=false

    if [[ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]]; then
        # Try magick first (ImageMagick 7), then convert (ImageMagick 6)
        if command -v magick &> /dev/null; then
            magick "$BRANDING_DIR/logos/arxisos-logo.png" -resize 48x48 -background transparent -gravity center -extent 48x48 "$PLYMOUTH_LOGO" 2>/dev/null && WATERMARK_CREATED=true
        elif command -v convert &> /dev/null; then
            convert "$BRANDING_DIR/logos/arxisos-logo.png" -resize 48x48 -background transparent -gravity center -extent 48x48 "$PLYMOUTH_LOGO" 2>/dev/null && WATERMARK_CREATED=true
        fi

        # Only proceed if we successfully created a resized watermark
        if [[ "$WATERMARK_CREATED" == "true" && -f "$PLYMOUTH_LOGO" ]]; then
            echo "    - Created 48x48 watermark"

            # Replace in spinner theme
            if [[ -d "$ROOTFS_DIR/usr/share/plymouth/themes/spinner" ]]; then
                sudo cp "$PLYMOUTH_LOGO" "$ROOTFS_DIR/usr/share/plymouth/themes/spinner/watermark.png"
                echo "    - Replaced spinner watermark"
            fi

            # Replace in bgrt theme
            if [[ -d "$ROOTFS_DIR/usr/share/plymouth/themes/bgrt" ]]; then
                sudo cp "$PLYMOUTH_LOGO" "$ROOTFS_DIR/usr/share/plymouth/themes/bgrt/watermark.png"
                echo "    - Replaced bgrt watermark"
            fi
        else
            echo "    - WARNING: Could not resize logo, skipping watermark replacement"
        fi

        rm -f "$PLYMOUTH_LOGO"
    fi

    # Configure Plymouth for installed system
    echo "  - Configuring Plymouth for installed system..."

    # Create dracut configuration to include Plymouth
    sudo mkdir -p "$ROOTFS_DIR/etc/dracut.conf.d"
    sudo tee "$ROOTFS_DIR/etc/dracut.conf.d/plymouth.conf" > /dev/null << 'DRACUTCONF'
# Include Plymouth in initramfs for boot splash
add_dracutmodules+=" plymouth "
DRACUTCONF

    # Set Plymouth default theme
    if [[ -f "$ROOTFS_DIR/usr/sbin/plymouth-set-default-theme" ]]; then
        # Create symlink for default theme
        sudo mkdir -p "$ROOTFS_DIR/etc/alternatives"
        sudo ln -sf /usr/share/plymouth/themes/spinner/spinner.plymouth "$ROOTFS_DIR/etc/alternatives/default.plymouth" 2>/dev/null || true
    fi
fi

# ============================================
# MODIFY INITRD FOR BOOT SPLASH
# ============================================
echo ""
echo "=== Modifying initrd for boot splash ==="

INITRD_PATH="$WORK_DIR/new_iso/images/pxeboot/initrd.img"
if [[ -f "$INITRD_PATH" ]]; then
    INITRD_WORK="$WORK_DIR/initrd_work"
    sudo mkdir -p "$INITRD_WORK"
    cd "$INITRD_WORK"

    echo "  - Extracting initrd..."
    sudo xz -dc "$INITRD_PATH" 2>/dev/null | sudo cpio -idm 2>/dev/null || true

    # Check if Plymouth themes exist in initrd
    if [[ -d "$INITRD_WORK/usr/share/plymouth/themes" ]]; then
        echo "  - Adding ArxisOS Plymouth theme to initrd..."

        # Create ArxisOS theme in initrd
        sudo mkdir -p "$INITRD_WORK/usr/share/plymouth/themes/arxisos"
        sudo cp -r "$BRANDING_DIR/plymouth/arxisos/"* "$INITRD_WORK/usr/share/plymouth/themes/arxisos/" 2>/dev/null || true

        # Create resized logo for Plymouth watermark (48x48 - small bottom watermark)
        PLYMOUTH_LOGO="/tmp/arxisos-initrd-logo.png"
        WATERMARK_CREATED=false

        if [[ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]]; then
            if command -v magick &> /dev/null; then
                magick "$BRANDING_DIR/logos/arxisos-logo.png" -resize 48x48 -background transparent -gravity center -extent 48x48 "$PLYMOUTH_LOGO" 2>/dev/null && WATERMARK_CREATED=true
            elif command -v convert &> /dev/null; then
                convert "$BRANDING_DIR/logos/arxisos-logo.png" -resize 48x48 -background transparent -gravity center -extent 48x48 "$PLYMOUTH_LOGO" 2>/dev/null && WATERMARK_CREATED=true
            fi
        fi

        # Only replace watermarks if we successfully created a resized image
        if [[ "$WATERMARK_CREATED" == "true" && -f "$PLYMOUTH_LOGO" ]]; then
            echo "  - Replacing Fedora watermarks in initrd (48x48)..."

            # Only replace watermark files specifically (NOT logo files which may be larger)
            sudo find "$INITRD_WORK/usr/share/plymouth/themes" -name "*watermark*" -type f 2>/dev/null | while read -r pngfile; do
                echo "    Replacing: $pngfile"
                sudo cp "$PLYMOUTH_LOGO" "$pngfile" 2>/dev/null || true
            done

            # Explicitly replace spinner and bgrt watermarks
            [[ -d "$INITRD_WORK/usr/share/plymouth/themes/spinner" ]] && \
                sudo cp "$PLYMOUTH_LOGO" "$INITRD_WORK/usr/share/plymouth/themes/spinner/watermark.png" 2>/dev/null || true
            [[ -d "$INITRD_WORK/usr/share/plymouth/themes/bgrt" ]] && \
                sudo cp "$PLYMOUTH_LOGO" "$INITRD_WORK/usr/share/plymouth/themes/bgrt/watermark.png" 2>/dev/null || true
        else
            echo "  - WARNING: Could not resize logo for initrd, skipping watermark replacement"
        fi

        rm -f "$PLYMOUTH_LOGO"

        # Update Plymouth config in initrd
        sudo mkdir -p "$INITRD_WORK/etc/plymouth"
        sudo tee "$INITRD_WORK/etc/plymouth/plymouthd.conf" > /dev/null << 'PLYCONF_INITRD'
[Daemon]
Theme=spinner
ShowDelay=0
DeviceTimeout=8
PLYCONF_INITRD

        echo "  - Repacking initrd..."
        cd "$INITRD_WORK"
        sudo find . 2>/dev/null | sudo cpio -o -H newc 2>/dev/null | xz -9 --check=crc32 | sudo tee "$INITRD_PATH" > /dev/null

        echo "  - initrd modified successfully"
    else
        echo "  - No Plymouth themes found in initrd, skipping"
    fi

    cd "$WORK_DIR"
else
    echo "  - initrd.img not found at expected path, skipping"
fi

# ============================================
# GRUB THEME (inside rootfs for installed system)
# ============================================
echo ""
echo "=== Applying GRUB Theme ==="

if [[ -d "$BRANDING_DIR/grub/arxisos" ]]; then
    echo "  - Copying GRUB theme to rootfs..."
    sudo mkdir -p "$ROOTFS_DIR/boot/grub2/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/grub/arxisos/"* "$ROOTFS_DIR/boot/grub2/themes/arxisos/"

    # Generate GRUB fonts
    echo "  - Generating GRUB fonts..."
    GRUB_MKFONT=""
    if command -v grub2-mkfont &> /dev/null; then
        GRUB_MKFONT="grub2-mkfont"
    elif command -v grub-mkfont &> /dev/null; then
        GRUB_MKFONT="grub-mkfont"
    fi

    if [[ -n "$GRUB_MKFONT" ]]; then
        DEJAVU_REGULAR=$(find /usr/share/fonts -name "DejaVuSans.ttf" 2>/dev/null | head -1)
        DEJAVU_BOLD=$(find /usr/share/fonts -name "DejaVuSans-Bold.ttf" 2>/dev/null | head -1)

        if [[ -n "$DEJAVU_REGULAR" ]]; then
            sudo $GRUB_MKFONT -s 16 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_sans_16.pf2" "$DEJAVU_REGULAR" 2>/dev/null || true
            sudo $GRUB_MKFONT -s 11 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_sans_11.pf2" "$DEJAVU_REGULAR" 2>/dev/null || true
        fi
        if [[ -n "$DEJAVU_BOLD" ]]; then
            sudo $GRUB_MKFONT -s 16 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_sans_bold_16.pf2" "$DEJAVU_BOLD" 2>/dev/null || true
            sudo $GRUB_MKFONT -s 24 -o "$ROOTFS_DIR/boot/grub2/themes/arxisos/dejavu_sans_bold_24.pf2" "$DEJAVU_BOLD" 2>/dev/null || true
        fi
    fi

    # Copy unicode.pf2 fallback
    if [[ -f /usr/share/grub/unicode.pf2 ]]; then
        sudo cp /usr/share/grub/unicode.pf2 "$ROOTFS_DIR/boot/grub2/themes/arxisos/" 2>/dev/null || true
    elif [[ -f /boot/grub2/fonts/unicode.pf2 ]]; then
        sudo cp /boot/grub2/fonts/unicode.pf2 "$ROOTFS_DIR/boot/grub2/themes/arxisos/" 2>/dev/null || true
    fi

    # Configure GRUB defaults
    echo "  - Configuring GRUB defaults..."
    sudo sed -i '/^GRUB_THEME=/d;/^GRUB_DISTRIBUTOR=/d;/^GRUB_DISABLE_OS_PROBER=/d;/^GRUB_GFXMODE=/d;/^GRUB_GFXPAYLOAD_LINUX=/d' "$ROOTFS_DIR/etc/default/grub" 2>/dev/null || true

    # Ensure rhgb quiet is in GRUB_CMDLINE_LINUX for Plymouth splash
    if grep -q "^GRUB_CMDLINE_LINUX=" "$ROOTFS_DIR/etc/default/grub" 2>/dev/null; then
        # Add rhgb quiet if not already present
        if ! grep -q "rhgb" "$ROOTFS_DIR/etc/default/grub"; then
            sudo sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 rhgb quiet"/' "$ROOTFS_DIR/etc/default/grub"
        fi
    else
        echo 'GRUB_CMDLINE_LINUX="rhgb quiet"' | sudo tee -a "$ROOTFS_DIR/etc/default/grub" >/dev/null
    fi

    sudo mkdir -p "$ROOTFS_DIR/etc/default"
    sudo tee -a "$ROOTFS_DIR/etc/default/grub" >/dev/null <<'GRUBCONF'

# ArxisOS GRUB Configuration
GRUB_THEME="/boot/grub2/themes/arxisos/theme.txt"
GRUB_DISTRIBUTOR="ArxisOS"
GRUB_DISABLE_OS_PROBER=true
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUBCONF
fi

# ============================================
# GRUB THEME ON ISO BOOT (EFI and BIOS)
# ============================================
echo ""
echo "=== Branding ISO Boot Menu ==="

# Copy GRUB theme to ISO directories
if [[ -d "$BRANDING_DIR/grub/arxisos" ]]; then
    echo "  - Copying GRUB theme to ISO..."
    sudo mkdir -p "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/grub/arxisos/"* "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos/"
    sudo mkdir -p "$WORK_DIR/new_iso/boot/grub2/themes/arxisos"
    sudo cp -r "$BRANDING_DIR/grub/arxisos/"* "$WORK_DIR/new_iso/boot/grub2/themes/arxisos/"

    # Generate fonts for ISO theme directories
    if [[ -n "${GRUB_MKFONT:-}" ]]; then
        for THEME_DIR in "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos" "$WORK_DIR/new_iso/boot/grub2/themes/arxisos"; do
            if [[ -n "${DEJAVU_REGULAR:-}" ]]; then
                sudo $GRUB_MKFONT -s 16 -o "$THEME_DIR/dejavu_sans_16.pf2" "$DEJAVU_REGULAR" 2>/dev/null || true
            fi
            if [[ -n "${DEJAVU_BOLD:-}" ]]; then
                sudo $GRUB_MKFONT -s 24 -o "$THEME_DIR/dejavu_sans_bold_24.pf2" "$DEJAVU_BOLD" 2>/dev/null || true
            fi
            [[ -f /usr/share/grub/unicode.pf2 ]] && sudo cp /usr/share/grub/unicode.pf2 "$THEME_DIR/" 2>/dev/null || true
        done
    fi

    # Convert PNG files to GRUB-compatible format (24-bit RGB)
    if command -v convert &> /dev/null; then
        echo "  - Converting PNG files for GRUB compatibility..."
        for THEME_DIR in "$WORK_DIR/new_iso/EFI/BOOT/themes/arxisos" "$WORK_DIR/new_iso/boot/grub2/themes/arxisos"; do
            find "$THEME_DIR" -name "*.png" -type f 2>/dev/null | while read -r png_file; do
                sudo convert "$png_file" -background black -alpha remove -alpha off -depth 8 "$png_file.tmp" 2>/dev/null && \
                    sudo mv "$png_file.tmp" "$png_file" || sudo rm -f "$png_file.tmp"
            done
        done
    fi
fi

# Update EFI GRUB config
if [[ -f "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg" ]]; then
    echo "  - Updating EFI GRUB config..."
    sudo sed -i \
        -e "s/CDLABEL=Fedora-[0-9A-Za-z_-]*/CDLABEL=${ISO_LABEL}/g" \
        -e "s/-l 'Fedora-[^']*'/-l '${ISO_LABEL}'/g" \
        -e "s/Install Fedora [0-9]*/Start ArxisOS/g" \
        -e "s/Test this media & install Fedora [0-9]*/Test Media \& Start ArxisOS/g" \
        -e "s/Install Fedora [0-9]* in basic graphics mode/Start ArxisOS (Basic Graphics)/g" \
        -e "s/Rescue a Fedora system/Rescue ArxisOS System/g" \
        -e "s/--class fedora/--class arxisos/g" \
        "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"

    # Add selinux=0 and rhgb quiet to kernel parameters for boot splash
    sudo sed -i \
        -e '/^\s*linux/s/$/ selinux=0 rhgb quiet/' \
        -e '/^\s*linuxefi/s/$/ selinux=0 rhgb quiet/' \
        "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"

    # Add theme configuration
    if ! grep -q "set theme=" "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"; then
        {
            echo '# ArxisOS GRUB Theme'
            echo 'insmod all_video'
            echo 'insmod gfxterm'
            echo 'insmod gfxmenu'
            echo 'insmod png'
            echo 'set gfxmode=auto'
            echo 'terminal_output gfxterm'
            echo 'set theme=($root)/EFI/BOOT/themes/arxisos/theme.txt'
            echo ''
            cat "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"
        } | sudo tee "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg.new" > /dev/null
        sudo mv "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg.new" "$WORK_DIR/new_iso/EFI/BOOT/grub.cfg"
    fi
fi

# Update BIOS GRUB config
if [[ -f "$WORK_DIR/new_iso/boot/grub2/grub.cfg" ]]; then
    echo "  - Updating BIOS GRUB config..."
    sudo sed -i \
        -e "s/CDLABEL=Fedora-[0-9A-Za-z_-]*/CDLABEL=${ISO_LABEL}/g" \
        -e "s/-l 'Fedora-[^']*'/-l '${ISO_LABEL}'/g" \
        -e "s/Install Fedora [0-9]*/Start ArxisOS/g" \
        -e "s/Test this media & install Fedora [0-9]*/Test Media \& Start ArxisOS/g" \
        -e "s/Install Fedora [0-9]* in basic graphics mode/Start ArxisOS (Basic Graphics)/g" \
        -e "s/Rescue a Fedora system/Rescue ArxisOS System/g" \
        -e "s/--class fedora/--class arxisos/g" \
        "$WORK_DIR/new_iso/boot/grub2/grub.cfg"

    # Add selinux=0 and rhgb quiet for boot splash
    sudo sed -i \
        -e '/^\s*linux/s/$/ selinux=0 rhgb quiet/' \
        -e '/^\s*linuxefi/s/$/ selinux=0 rhgb quiet/' \
        "$WORK_DIR/new_iso/boot/grub2/grub.cfg"

    if ! grep -q "set theme=" "$WORK_DIR/new_iso/boot/grub2/grub.cfg"; then
        {
            echo '# ArxisOS GRUB Theme'
            echo 'insmod all_video'
            echo 'insmod gfxterm'
            echo 'insmod gfxmenu'
            echo 'insmod png'
            echo 'set gfxmode=auto'
            echo 'terminal_output gfxterm'
            echo 'set theme=($root)/boot/grub2/themes/arxisos/theme.txt'
            echo ''
            cat "$WORK_DIR/new_iso/boot/grub2/grub.cfg"
        } | sudo tee "$WORK_DIR/new_iso/boot/grub2/grub.cfg.new" > /dev/null
        sudo mv "$WORK_DIR/new_iso/boot/grub2/grub.cfg.new" "$WORK_DIR/new_iso/boot/grub2/grub.cfg"
    fi
fi

# ============================================
# SDDM THEME
# ============================================
echo ""
echo "=== Applying SDDM Theme ==="

SDDM_SRC=""
if [[ -d "$PLASMA_CFG_DIR/ArxisOS-SDDM" ]]; then
    SDDM_SRC="$PLASMA_CFG_DIR/ArxisOS-SDDM"
elif [[ -d "$BRANDING_DIR/sddm/arxisos" ]]; then
    SDDM_SRC="$BRANDING_DIR/sddm/arxisos"
fi

if [[ -n "$SDDM_SRC" ]]; then
    echo "  - Copying SDDM theme..."
    sudo mkdir -p "$ROOTFS_DIR/usr/share/sddm/themes/arxisos"
    sudo cp -r "$SDDM_SRC/"* "$ROOTFS_DIR/usr/share/sddm/themes/arxisos/"

    # Set ArxisOS logo as default face icon
    if [[ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]]; then
        sudo mkdir -p "$ROOTFS_DIR/usr/share/sddm/faces"
        sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/sddm/faces/.face.icon"
    fi
fi

# SDDM configuration
echo "  - Configuring SDDM..."
sudo mkdir -p "$ROOTFS_DIR/etc/sddm.conf.d"
sudo tee "$ROOTFS_DIR/etc/sddm.conf.d/arxisos.conf" >/dev/null <<'SDDMEOF'
[Theme]
Current=arxisos
CursorTheme=oreo_white_cursors

[General]
DefaultSession=plasmax11.desktop

[X11]
ServerArguments=-nolisten tcp

[Wayland]
SessionDir=/usr/share/wayland-sessions
SDDMEOF

# ============================================
# PLASMA THEMES AND LOOK-AND-FEEL (PurPurDay)
# ============================================
echo ""
echo "=== Applying Plasma Themes (PurPurDay) ==="

echo "  - Wallpapers..."
copy_if_exists "$BRANDING_DIR/wallpapers" "$ROOTFS_DIR/usr/share/wallpapers/arxisos"

echo "  - Logos..."
copy_if_exists "$BRANDING_DIR/logos" "$ROOTFS_DIR/usr/share/arxisos/logos"
copy_if_exists "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/arxisos-logo.png"

echo "  - Icon themes..."
if [[ -d "$BRANDING_DIR/icons/hicolor" ]]; then
    sudo mkdir -p "$ROOTFS_DIR/usr/share/icons/hicolor"
    sudo cp -r "$BRANDING_DIR/icons/hicolor/"* "$ROOTFS_DIR/usr/share/icons/hicolor/"
fi
copy_if_exists "$BRANDING_DIR/icons/Vivid-Glassy-Dark-Icons" "$ROOTFS_DIR/usr/share/icons/Vivid-Glassy-Dark-Icons"

echo "  - Cursor theme..."
copy_if_exists "$BRANDING_DIR/cursors/oreo_white_cursors" "$ROOTFS_DIR/usr/share/icons/oreo_white_cursors"

echo "  - GTK theme (PurPurDay)..."
copy_if_exists "$BRANDING_DIR/gtk-themes/PurPurDay-GTK" "$ROOTFS_DIR/usr/share/themes/PurPurDay-GTK"

echo "  - Plasma look-and-feel (PurPurDay)..."
copy_if_exists "$BRANDING_DIR/plasma-themes/PurPurDay-Global-6" "$ROOTFS_DIR/usr/share/plasma/look-and-feel/PurPurDay-Global-6"
copy_if_exists "$BRANDING_DIR/plasma-themes/PurPurDay-Splash-6" "$ROOTFS_DIR/usr/share/plasma/look-and-feel/PurPurDay-Splash-6"

echo "  - Plasma desktop theme (PurPurDay)..."
copy_if_exists "$BRANDING_DIR/plasma-themes/PurPurDay-Plasma" "$ROOTFS_DIR/usr/share/plasma/desktoptheme/PurPurDay-Plasma"

echo "  - Color scheme..."
# Copy existing color scheme or create from Global theme defaults
if [[ -f "$PLASMA_CFG_DIR/Archive-local-share/color-schemes/PurPurDayColor.colors" ]]; then
    copy_if_exists "$PLASMA_CFG_DIR/Archive-local-share/color-schemes/PurPurDayColor.colors" \
        "$ROOTFS_DIR/usr/share/color-schemes/PurPurDayColor.colors"
fi

echo "  - Aurorae window decoration (PurPurDay)..."
copy_if_exists "$BRANDING_DIR/aurorae/PurPurDayBlur-Aurorae-6" "$ROOTFS_DIR/usr/share/aurorae/themes/PurPurDayBlur-Aurorae-6"

# ============================================
# REPLACE FEDORA ICONS WITH ARXISOS
# ============================================
echo ""
echo "=== Replacing Fedora Icons ==="

# Install start.svg as the application menu icon (start-here, distributor-logo)
if [[ -f "$BRANDING_DIR/start.svg" ]]; then
    echo "  - Installing start.svg as application menu icon..."

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
            echo "    - Generating ${size}x${size} icons from start.svg..."
            sudo $CONVERT_CMD -background none "$BRANDING_DIR/start.svg" -resize ${size}x${size} "$ICON_DIR/start-here.png" 2>/dev/null || true
            sudo cp "$ICON_DIR/start-here.png" "$ICON_DIR/distributor-logo.png" 2>/dev/null || true
            sudo cp "$ICON_DIR/start-here.png" "$ICON_DIR/arxisos-start.png" 2>/dev/null || true
        done
    fi

    # Copy to pixmaps
    echo "  - Copying start.svg to pixmaps..."
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/pixmaps/start-here.svg" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/pixmaps/distributor-logo.svg" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/start.svg" "$ROOTFS_DIR/usr/share/pixmaps/arxisos-start.svg" 2>/dev/null || true
fi

# Install arxisos-logo.png for other branding (fedora replacements)
if [[ -f "$BRANDING_DIR/logos/arxisos-logo.png" ]]; then
    echo "  - Installing arxisos-logo.png for system branding..."

    # Replace fedora-logo icons in hicolor
    for size in 16 22 24 32 48 64 96 128 256 512; do
        ICON_DIR="$ROOTFS_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
        if [[ -d "$ICON_DIR" ]]; then
            if command -v convert &> /dev/null || command -v magick &> /dev/null; then
                CONVERT_CMD="convert"
                command -v magick &> /dev/null && CONVERT_CMD="magick"
                sudo $CONVERT_CMD "$BRANDING_DIR/logos/arxisos-logo.png" -resize ${size}x${size} "$ICON_DIR/fedora-logo-icon.png" 2>/dev/null || true
                sudo cp "$ICON_DIR/fedora-logo-icon.png" "$ICON_DIR/fedora-logo-small.png" 2>/dev/null || true
                sudo cp "$ICON_DIR/fedora-logo-icon.png" "$ICON_DIR/arxisos-logo.png" 2>/dev/null || true
            fi
        fi
    done

    # Replace in pixmaps
    echo "  - Replacing pixmaps..."
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-logo.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-logo-small.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/fedora-gdm-logo.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/system-logo-white.png" 2>/dev/null || true
    sudo cp "$BRANDING_DIR/logos/arxisos-logo.png" "$ROOTFS_DIR/usr/share/pixmaps/arxisos-logo.png" 2>/dev/null || true
fi

# ============================================
# USER SKELETON (PurPurDay THEME CONFIG)
# ============================================
echo ""
echo "=== Applying User Skeleton Config (PurPurDay Theme) ==="

# Create skel with PurPurDay theme elements (NOT Global theme - avoids layout issues)
# This applies: Plasma style, icons, cursors, colors, window decoration, splash
# Does NOT apply: Global theme (layout), wallpaper (uses Plasma default)

sudo mkdir -p "$ROOTFS_DIR/etc/skel/.config"

# Copy GTK configs if available
if [[ -d "$SKEL_DIR" ]]; then
    [[ -d "$SKEL_DIR/.config/gtk-3.0" ]] && sudo cp -r "$SKEL_DIR/.config/gtk-3.0" "$ROOTFS_DIR/etc/skel/.config/"
    [[ -d "$SKEL_DIR/.config/gtk-4.0" ]] && sudo cp -r "$SKEL_DIR/.config/gtk-4.0" "$ROOTFS_DIR/etc/skel/.config/"
    [[ -d "$SKEL_DIR/.config/environment.d" ]] && sudo cp -r "$SKEL_DIR/.config/environment.d" "$ROOTFS_DIR/etc/skel/.config/"
    [[ -f "$SKEL_DIR/.bashrc" ]] && sudo cp "$SKEL_DIR/.bashrc" "$ROOTFS_DIR/etc/skel/"
    [[ -d "$SKEL_DIR/.local" ]] && sudo cp -r "$SKEL_DIR/.local" "$ROOTFS_DIR/etc/skel/"
fi

# Create Plasma theme configs (individual elements, not Global theme)
echo "  - Creating PurPurDay Plasma configs..."

# plasmarc - Plasma desktop theme
sudo tee "$ROOTFS_DIR/etc/skel/.config/plasmarc" > /dev/null << 'PLASMARC'
[Theme]
name=PurPurDay-Plasma
PLASMARC

# kdeglobals - Icon theme and widget style (NO LookAndFeelPackage!)
sudo tee "$ROOTFS_DIR/etc/skel/.config/kdeglobals" > /dev/null << 'KDEGLOBALS'
[KDE]
widgetStyle=breeze

[Icons]
Theme=Vivid-Glassy-Dark-Icons
KDEGLOBALS

# kcminputrc - Cursor theme
sudo tee "$ROOTFS_DIR/etc/skel/.config/kcminputrc" > /dev/null << 'KCMINPUT'
[Mouse]
cursorTheme=oreo_white_cursors
cursorSize=24
KCMINPUT

# kwinrc - Window decoration (Aurorae)
sudo tee "$ROOTFS_DIR/etc/skel/.config/kwinrc" > /dev/null << 'KWINRC'
[org.kde.kdecoration2]
library=org.kde.kwin.aurorae
theme=__aurorae__svg__PurPurDayBlur-Aurorae-6

[Desktops]
Number=1
Rows=1

[DesktopSwitcher]
LayoutName=org.kde.breeze.desktop

[WindowSwitcher]
LayoutName=org.kde.breeze.desktop
KWINRC

# ksplashrc - Splash screen
sudo tee "$ROOTFS_DIR/etc/skel/.config/ksplashrc" > /dev/null << 'KSPLASH'
[KSplash]
Theme=PurPurDay-Splash-6
Engine=KSplashQML
KSPLASH

# Copy configs to liveuser
if [[ -d "$ROOTFS_DIR/home/liveuser" ]]; then
    echo "  - Setting up liveuser with PurPurDay theme..."
    sudo mkdir -p "$ROOTFS_DIR/home/liveuser/.config"
    sudo cp "$ROOTFS_DIR/etc/skel/.config/plasmarc" "$ROOTFS_DIR/home/liveuser/.config/"
    sudo cp "$ROOTFS_DIR/etc/skel/.config/kdeglobals" "$ROOTFS_DIR/home/liveuser/.config/"
    sudo cp "$ROOTFS_DIR/etc/skel/.config/kcminputrc" "$ROOTFS_DIR/home/liveuser/.config/"
    sudo cp "$ROOTFS_DIR/etc/skel/.config/kwinrc" "$ROOTFS_DIR/home/liveuser/.config/"
    sudo cp "$ROOTFS_DIR/etc/skel/.config/ksplashrc" "$ROOTFS_DIR/home/liveuser/.config/"

    # Copy GTK configs too
    [[ -d "$ROOTFS_DIR/etc/skel/.config/gtk-3.0" ]] && sudo cp -r "$ROOTFS_DIR/etc/skel/.config/gtk-3.0" "$ROOTFS_DIR/home/liveuser/.config/"
    [[ -d "$ROOTFS_DIR/etc/skel/.config/gtk-4.0" ]] && sudo cp -r "$ROOTFS_DIR/etc/skel/.config/gtk-4.0" "$ROOTFS_DIR/home/liveuser/.config/"

    sudo chown -R 1000:1000 "$ROOTFS_DIR/home/liveuser" 2>/dev/null || true
fi

echo "  - Theme configs created (Plasma style, icons, cursors, decoration, splash)"
echo "  - NOT applied: Global theme (layout), wallpaper (uses Plasma default)"

# ============================================
# SESSION AND DESKTOP HINTS
# ============================================
echo ""
echo "=== Configuring Session Defaults ==="

# Desktop preference
sudo mkdir -p "$ROOTFS_DIR/etc/sysconfig"
echo "PREFERRED=plasma" | sudo tee "$ROOTFS_DIR/etc/sysconfig/desktop" >/dev/null 2>&1

# AccountsService for liveuser
sudo mkdir -p "$ROOTFS_DIR/var/lib/AccountsService/users"
sudo tee "$ROOTFS_DIR/var/lib/AccountsService/users/liveuser" >/dev/null <<'ACCT'
[User]
Session=plasmax11
XSession=plasmax11
Icon=/usr/share/pixmaps/arxisos-logo.png
SystemAccount=false
ACCT

# Hide GNOME sessions from SDDM
for gnome_session in gnome gnome-xorg gnome-classic gnome-classic-xorg; do
    if [[ -f "$ROOTFS_DIR/usr/share/xsessions/${gnome_session}.desktop" ]]; then
        sudo sed -i 's/^NoDisplay=.*/NoDisplay=true/' "$ROOTFS_DIR/usr/share/xsessions/${gnome_session}.desktop" 2>/dev/null || \
        echo "NoDisplay=true" | sudo tee -a "$ROOTFS_DIR/usr/share/xsessions/${gnome_session}.desktop" > /dev/null
    fi
done

# Disable GNOME initial setup
sudo rm -f "$ROOTFS_DIR/etc/xdg/autostart/gnome-initial-setup-first-login.desktop" 2>/dev/null || true
sudo rm -f "$ROOTFS_DIR/etc/xdg/autostart/gnome-welcome-tour.desktop" 2>/dev/null || true

# ============================================
# INSTALLER SHORTCUT
# ============================================
echo ""
echo "=== Creating Installer Shortcut ==="

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
INSTALLER_EOF

# Add to desktop for live user
sudo mkdir -p "$ROOTFS_DIR/etc/skel/Desktop"
sudo cp "$ROOTFS_DIR/usr/share/applications/arxisos-installer.desktop" "$ROOTFS_DIR/etc/skel/Desktop/"
sudo chmod +x "$ROOTFS_DIR/etc/skel/Desktop/arxisos-installer.desktop"

if [[ -d "$ROOTFS_DIR/home/liveuser/Desktop" ]]; then
    sudo cp "$ROOTFS_DIR/usr/share/applications/arxisos-installer.desktop" "$ROOTFS_DIR/home/liveuser/Desktop/"
    sudo chmod +x "$ROOTFS_DIR/home/liveuser/Desktop/arxisos-installer.desktop"
fi

# ============================================
# OS RELEASE BRANDING
# ============================================
echo ""
echo "=== Applying OS Branding ==="

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

sudo tee "$ROOTFS_DIR/etc/lsb-release" > /dev/null << 'EOF'
DISTRIB_ID=ArxisOS
DISTRIB_RELEASE=1.0
DISTRIB_CODENAME=Plasma
DISTRIB_DESCRIPTION="ArxisOS 1.0 (Plasma)"
DISTRIB_DEVELOPER="Brad Heffernan"
EOF

# Set dnf releasever for Fedora 43 repos
sudo mkdir -p "$ROOTFS_DIR/etc/dnf/vars"
echo "43" | sudo tee "$ROOTFS_DIR/etc/dnf/vars/releasever" > /dev/null

# ============================================
# DISABLE SELINUX
# ============================================
echo "  - Disabling SELinux..."
if [[ -f "$ROOTFS_DIR/etc/selinux/config" ]]; then
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' "$ROOTFS_DIR/etc/selinux/config"
    sudo sed -i 's/^SELINUX=permissive/SELINUX=disabled/' "$ROOTFS_DIR/etc/selinux/config"
fi
sudo rm -f "$ROOTFS_DIR/.autorelabel"

# ============================================
# UPDATE ICON CACHES
# ============================================
echo ""
echo "=== Updating Icon Caches ==="
# Note: Can't chroot here as bind mounts are gone, but icons will cache on first boot

# ============================================
# REPACK SQUASHFS
# ============================================
echo ""
echo "=== Repacking Squashfs ==="
echo "  (This may take several minutes...)"

sudo mkdir -p "$WORK_DIR/new_iso/LiveOS"
sudo mksquashfs "$ROOTFS_DIR" "$WORK_DIR/new_iso/LiveOS/squashfs.img" \
    -e proc -e sys -e dev -e run \
    -comp xz -b 1048576 -noappend > /dev/null

# Unmount rootfs if mounted
if $MOUNTED_ROOTFS; then
    sudo umount -l "$ROOTFS_DIR" 2>/dev/null || true
fi

# ============================================
# UPDATE .discinfo
# ============================================
if [[ -f "$WORK_DIR/new_iso/.discinfo" ]]; then
    echo "Updating .discinfo..."
    sudo tee "$WORK_DIR/new_iso/.discinfo" > /dev/null << DISCINFO_EOF
$(date +%s.%N)
ArxisOS 1.0
x86_64
DISCINFO_EOF
fi

# ============================================
# BUILD ISO
# ============================================
echo ""
echo "=== Building ISO ==="
echo "  Volume label: $ISO_LABEL"

if [[ -f "$WORK_DIR/new_iso/isolinux/isolinux.bin" ]]; then
    sudo xorrisofs -o "$output_iso" \
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
    sudo xorrisofs -o "$output_iso" \
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

echo ""
echo "=== Branding Complete ==="
echo "Output: $output_iso"
echo "Size: $(du -h "$output_iso" | cut -f1)"
