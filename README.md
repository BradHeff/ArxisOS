<p align="center">
  <img src="branding/logos/arxisos-logo.png" alt="ArxisOS Logo" width="200"/>
</p>

<h1 align="center">ArxisOS</h1>

<p align="center">
  <strong>A Modern, Elegant Linux Distribution Built for Performance and Beauty</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#installation">Installation</a> •
  <a href="#package-management">Package Management</a> •
  <a href="#building">Building</a> •
  <a href="#contributing">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0-blue?style=for-the-badge" alt="Version"/>
  <img src="https://img.shields.io/badge/base-Fedora%2043-51A2DA?style=for-the-badge" alt="Base"/>
  <img src="https://img.shields.io/badge/desktop-KDE%20Plasma%206-1D99F3?style=for-the-badge" alt="Desktop"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-green?style=for-the-badge" alt="License"/>
</p>

---

## Overview

**ArxisOS** is a beautifully crafted Linux distribution based on Fedora 43, featuring the KDE Plasma 6 desktop environment. Designed with a focus on aesthetics, performance, and user experience, ArxisOS combines the stability and security of Fedora with a stunning custom visual identity.

Whether you're a developer, creative professional, or everyday user, ArxisOS provides a polished, cohesive experience right out of the box.

---

## Features

### Desktop Experience

| Feature | Description |
|---------|-------------|
| **KDE Plasma 6** | The latest Plasma desktop with Wayland and X11 support |
| **PurPurDay Theme** | Custom global theme with matching colors, icons, and decorations |
| **Magna-Glassy Icons** | Beautiful glassy icon theme for a modern look |
| **Oreo Cursors** | Elegant white cursor theme |
| **Custom Plymouth** | ArxisOS branded boot splash |
| **SDDM Theme** | Matching login screen with ArxisOS branding |
| **GRUB Theme** | Custom bootloader theme |

### System Features

- **Fedora 43 Base** — Latest packages, cutting-edge kernel, and excellent hardware support
- **SELinux Enabled** — Enterprise-grade security out of the box
- **Flatpak Ready** — Access to thousands of applications via Flathub
- **DNF Package Manager** — Fast, reliable package management
- **Systemd** — Modern init system with excellent service management
- **Btrfs Support** — Advanced filesystem with snapshots and compression

### Pre-installed Applications

| Category | Applications |
|----------|-------------|
| **Web** | Firefox |
| **Office** | LibreOffice Suite |
| **Files** | Dolphin File Manager |
| **Terminal** | Konsole with custom ArxisOS profile |
| **Text Editor** | Kate |
| **Images** | Gwenview |
| **Documents** | Okular |
| **Archive** | Ark |
| **Screenshots** | Spectacle |
| **Remote Desktop** | Remmina (RDP, VNC, SPICE) |
| **System** | Plasma Discover, System Monitor |

---

## Screenshots

### Boot Experience

<p align="center">
  <img src="Screenshots/Screenshot_0.png" alt="ArxisOS GRUB Bootloader" width="800"/>
</p>

<p align="center">
  <em>GRUB Bootloader — Custom ArxisOS themed boot menu with sleek dark design</em>
</p>

### Desktop & Welcome Experience

<p align="center">
  <img src="Screenshots/Screenshot_1.png" alt="ArxisOS Desktop" width="800"/>
</p>

<p align="center">
  <em>ArxisOS Desktop — KDE Plasma 6 with PurPurDay theme, Welcome dialogs, and stunning cityscape wallpaper</em>
</p>

### Installation Process

<p align="center">
  <img src="Screenshots/Screenshot_2.png" alt="ArxisOS Installer - Language Selection" width="800"/>
</p>

<p align="center">
  <em>Anaconda Installer — Language and keyboard layout selection with ArxisOS branding</em>
</p>

<p align="center">
  <img src="Screenshots/Screenshot_3.png" alt="ArxisOS Installer - Installation Progress" width="800"/>
</p>

<p align="center">
  <em>Installation Progress — Clean, modern interface showing software installation status</em>
</p>

---

## System Requirements

### Minimum Requirements

| Component | Requirement |
|-----------|-------------|
| **Processor** | 64-bit (x86_64) CPU, 2 GHz or faster |
| **Memory** | 4 GB RAM |
| **Storage** | 20 GB available disk space |
| **Graphics** | GPU with OpenGL 3.3 support |
| **Display** | 1024x768 resolution |

### Recommended Requirements

| Component | Requirement |
|-----------|-------------|
| **Processor** | 64-bit quad-core CPU, 3 GHz or faster |
| **Memory** | 8 GB RAM or more |
| **Storage** | 50 GB SSD |
| **Graphics** | GPU with Vulkan support |
| **Display** | 1920x1080 or higher |

---

## Installation

### Download

Download the latest ArxisOS ISO from the [Releases](https://github.com/arxisos/arxisos/releases) page.

### Creating Bootable Media

#### Linux
```bash
sudo dd if=ArxisOS-1.0-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

#### Windows
Use [Rufus](https://rufus.ie/) or [balenaEtcher](https://www.balena.io/etcher/)

#### macOS
```bash
sudo dd if=ArxisOS-1.0-x86_64.iso of=/dev/diskN bs=4m
```

### Installation Process

1. Boot from the USB/DVD
2. Select **"Start ArxisOS"** from the boot menu
3. Once the live desktop loads, click **"Install ArxisOS"** on the desktop
4. Follow the Anaconda installer wizard
5. Reboot and enjoy ArxisOS!

### Live Session

The live environment includes a fully functional KDE Plasma desktop with automatic login. You can explore ArxisOS before installing.

- **Default User:** `liveuser` (no password, passwordless sudo)
- **Session:** Plasma X11

---

## Package Management

### Current: DNF (Fedora Package Manager)

ArxisOS currently uses DNF with access to Fedora 43 repositories:

```bash
# Update system
sudo dnf upgrade

# Install a package
sudo dnf install package-name

# Search for packages
dnf search keyword

# Remove a package
sudo dnf remove package-name
```

### Flatpak

Flatpak is pre-installed for sandboxed applications:

```bash
# Add Flathub repository
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install an application
flatpak install flathub org.application.Name

# Run a Flatpak application
flatpak run org.application.Name
```

---

## ApM — Arxis Package Manager

<p align="center">
  <img src="https://img.shields.io/badge/status-In%20Development-orange?style=for-the-badge" alt="Status"/>
</p>

### Coming Soon

We are developing **ApM (Arxis Package Manager)** — a next-generation package manager designed specifically for ArxisOS. Inspired by the simplicity and power of Arch Linux's pacman and AUR, ApM will provide:

| Feature | Description |
|---------|-------------|
| **Native `.apm` Packages** | Lightweight, efficient package format designed for ArxisOS |
| **RPM Compatibility** | Seamless installation of Fedora/RHEL `.rpm` packages |
| **ApR Repository** | Community-driven package repository (like Arch's AUR) |
| **APMBUILD System** | Simple, readable build scripts for package creation |
| **Built in Rust** | Blazing-fast performance with parallel downloads |

<p align="center">
  <a href="APM.md">
    <img src="https://img.shields.io/badge/📖_Read_the_Full_ApM_Documentation-4A90D9?style=for-the-badge" alt="ApM Documentation"/>
  </a>
</p>

> **Want to learn more?** Check out the **[ApM Documentation](APM.md)** for detailed information on package format, CLI usage, building packages, the ApR repository system, and RPM compatibility.

---

## Building ArxisOS

### Prerequisites

- Fedora 43 or compatible system
- `osbuild-composer` for image building
- Root/sudo access
- ~50GB free disk space

### Build Process

1. **Clone the repository:**
   ```bash
   git clone https://github.com/arxisos/arxisos-build.git
   cd arxisos-build
   ```

2. **Start osbuild-composer:**
   ```bash
   sudo systemctl start osbuild-composer.socket
   ```

3. **Build the base ISO:**
   ```bash
   ./scripts/build-iso.sh --wait
   ```

4. **Apply ArxisOS branding:**
   ```bash
   sudo ./scripts/apply-composer-branding.sh <base-iso> ArxisOS-1.0-x86_64.iso
   ```

### Project Structure

```
arxisos-build/
├── blueprints/           # osbuild-composer blueprints
│   └── arxisos-kde.toml  # Main KDE Plasma blueprint
├── branding/             # Visual assets
│   ├── logos/            # ArxisOS logos and icons
│   ├── wallpapers/       # Desktop wallpapers
│   ├── plymouth/         # Boot splash theme
│   ├── grub/             # Bootloader theme
│   ├── sddm/             # Login manager theme
│   ├── plasma-themes/    # KDE Plasma themes
│   ├── icons/            # Icon themes
│   └── cursors/          # Cursor themes
├── scripts/              # Build and branding scripts
│   ├── build-iso.sh      # ISO build script
│   └── apply-composer-branding.sh  # Branding application
├── Screenshots/          # OS screenshots for documentation
├── PLASMA-CONFIGS/       # KDE configuration files
├── Skel/                 # User skeleton files
├── APM.md                # ApM Package Manager documentation
└── README.md             # This file
```

---

## Customization

### Changing Themes

ArxisOS uses KDE Plasma's standard theming system:

1. Open **System Settings**
2. Navigate to **Appearance**
3. Customize:
   - **Global Theme** — Overall look and feel
   - **Plasma Style** — Panel and widget appearance
   - **Colors** — System color scheme
   - **Window Decorations** — Titlebar style
   - **Icons** — Icon theme
   - **Cursors** — Mouse cursor theme

### Wallpapers

Default wallpapers are located in `/usr/share/wallpapers/ArxisOS/`.

To add custom wallpapers, place them in `~/.local/share/wallpapers/`.

---

## Troubleshooting

### Boot Issues

**Black screen after boot:**
- Try booting with the "Basic Graphics" option
- Add `nomodeset` to kernel parameters

**Plymouth not showing:**
- Ensure `rhgb quiet` are in kernel parameters
- Rebuild initramfs: `sudo dracut -f`

### Display Issues

**Wrong resolution:**
- Open System Settings → Display and Monitor
- Configure your display settings

**Wayland issues:**
- Log out and select "Plasma (X11)" from the session menu

### Package Issues

**DNF slow:**
```bash
sudo dnf makecache
```

**Broken dependencies:**
```bash
sudo dnf distro-sync
```

---

## Contributing

We welcome contributions to ArxisOS! Here's how you can help:

### Reporting Issues

- Use the [GitHub Issues](https://github.com/arxisos/arxisos/issues) page
- Include system information: `fastfetch` or `inxi -F`
- Provide steps to reproduce the issue

### Development

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Areas of Contribution

- **Theming** — Improve or create new visual themes
- **Documentation** — Help improve docs and guides
- **Testing** — Test on different hardware configurations
- **Translations** — Help translate ArxisOS
- **ApM Development** — Contribute to the package manager

---

## Roadmap

### Version 1.0 (Current)
- [x] KDE Plasma 6 desktop
- [x] PurPurDay theme integration
- [x] Custom boot splash and login screen
- [x] GRUB theming
- [x] Pre-installed applications

### Version 1.1 (Planned)
- [ ] ApM package manager (alpha)
- [ ] ArxisOS Welcome application
- [ ] Additional wallpapers
- [ ] Improved installer experience

### Version 2.0 (Future)
- [ ] ApM package manager (stable)
- [ ] ApR community repository
- [ ] ArxisOS-specific applications
- [ ] ARM64 support

---

## Credits

### Developer

**Brad Heffernan** — Creator and Lead Developer

### Acknowledgments

- [Fedora Project](https://fedoraproject.org/) — Base distribution
- [KDE Community](https://kde.org/) — Plasma desktop environment
- [PurPurDay Theme](https://store.kde.org/) — Original theme inspiration
- All open-source contributors whose work makes ArxisOS possible

---

## License

ArxisOS is distributed under the **GNU General Public License v3.0**.

See [LICENSE](LICENSE) for more information.

---

## Links

- **Website:** [https://arxisos.com](https://arxisos.com)
- **Documentation:** [https://docs.arxisos.com](https://docs.arxisos.com)
- **Support:** [https://support.arxisos.com](https://support.arxisos.com)
- **GitHub:** [https://github.com/arxisos](https://github.com/arxisos)

---

<p align="center">
  <strong>ArxisOS</strong> — Where Beauty Meets Performance
</p>

<p align="center">
  Made with ❤️ in Australia
</p>
