<p align="center">
  <img src="branding/logos/arxisos-logo.png" alt="ApM Logo" width="120"/>
</p>

<h1 align="center">ApM — Arxis Package Manager</h1>

<p align="center">
  <strong>A Modern, Fast, and Flexible Package Manager for ArxisOS</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-In%20Development-orange?style=for-the-badge" alt="Status"/>
  <img src="https://img.shields.io/badge/language-Rust-B7410E?style=for-the-badge" alt="Language"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-green?style=for-the-badge" alt="License"/>
</p>

<p align="center">
  <a href="#overview">Overview</a> •
  <a href="#features">Features</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#package-format">Package Format</a> •
  <a href="#usage">Usage</a> •
  <a href="#building-packages">Building Packages</a> •
  <a href="#repository">Repository</a>
</p>

---

## Overview

**ApM (Arxis Package Manager)** is a next-generation package manager designed specifically for ArxisOS. Inspired by the simplicity of Arch Linux's `pacman` and the community-driven AUR, ApM combines ease of use with powerful features.

### Design Philosophy

- **Simplicity** — Intuitive commands that feel natural
- **Speed** — Built in Rust for blazing-fast performance
- **Flexibility** — Native `.apm` packages with RPM compatibility
- **Community** — User-contributed packages via ApR (Arxis Package Repository)
- **Transparency** — Clear, readable build scripts

---

## Features

### Core Features

| Feature | Description |
|---------|-------------|
| **Native `.apm` Format** | Lightweight, efficient package format designed for ArxisOS |
| **RPM Compatibility** | Seamless installation of Fedora/RHEL `.rpm` packages |
| **Parallel Downloads** | Multi-threaded package downloads for faster operations |
| **Dependency Resolution** | Automatic handling of package dependencies |
| **Transaction Safety** | Atomic operations with rollback support |
| **Delta Updates** | Download only changed portions of packages |

### Repository System

| Repository | Description |
|------------|-------------|
| **core** | Essential system packages maintained by ArxisOS team |
| **extra** | Additional software maintained by ArxisOS team |
| **community** | User-contributed packages from ApR |
| **fedora** | Compatibility layer for Fedora RPM repositories |

### Package Sources

```
┌─────────────────────────────────────────────────────────┐
│                    ApM Package Sources                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   ┌─────────────┐    ┌─────────────┐    ┌────────────┐  │
│   │  .apm       │    │  .rpm       │    │  ApR       │  │
│   │  (Native)   │    │  (Fedora)   │    │  (Source)  │  │
│   └──────┬──────┘    └──────┬──────┘    └──────┬─────┘  │
│          │                  │                   │        │
│          └──────────────────┴───────────────────┘        │
│                             │                            │
│                    ┌────────▼────────┐                   │
│                    │  ApM Runtime    │                   │
│                    │  (Unified API)  │                   │
│                    └────────┬────────┘                   │
│                             │                            │
│                    ┌────────▼────────┐                   │
│                    │   ArxisOS       │                   │
│                    │   System        │                   │
│                    └─────────────────┘                   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## Architecture

### Component Overview

```
apm/
├── libapm/              # Core library
│   ├── src/
│   │   ├── package.rs   # Package handling
│   │   ├── repo.rs      # Repository management
│   │   ├── resolve.rs   # Dependency resolution
│   │   ├── download.rs  # Parallel downloader
│   │   ├── install.rs   # Installation logic
│   │   ├── rpm.rs       # RPM compatibility layer
│   │   └── db.rs        # Local database
│   └── Cargo.toml
├── apm-cli/             # Command-line interface
│   ├── src/
│   │   ├── main.rs
│   │   ├── commands/
│   │   │   ├── install.rs
│   │   │   ├── remove.rs
│   │   │   ├── upgrade.rs
│   │   │   ├── search.rs
│   │   │   ├── query.rs
│   │   │   └── build.rs
│   │   └── config.rs
│   └── Cargo.toml
├── apm-build/           # Package build system
│   ├── src/
│   │   ├── apmbuild.rs  # APMBUILD parser
│   │   ├── builder.rs   # Package builder
│   │   └── compress.rs  # Compression handling
│   └── Cargo.toml
└── apm-repo/            # Repository tools
    ├── src/
    │   ├── server.rs    # Repo server
    │   └── sync.rs      # Sync utilities
    └── Cargo.toml
```

### Database Structure

ApM uses a SQLite database for tracking installed packages:

```
/var/lib/apm/
├── local.db             # Installed packages database
├── sync/                # Synced repository databases
│   ├── core.db
│   ├── extra.db
│   ├── community.db
│   └── fedora.db
├── cache/               # Downloaded packages
│   ├── apm/
│   └── rpm/
└── logs/                # Transaction logs
```

---

## Package Format

### `.apm` Package Structure

An `.apm` package is a compressed archive containing:

```
package-1.0.0-1.apm
├── .PKGINFO             # Package metadata (TOML format)
├── .MTREE               # File integrity database
├── .INSTALL             # Pre/post install scripts (optional)
└── data/                # Actual package files
    ├── usr/
    │   ├── bin/
    │   ├── lib/
    │   └── share/
    └── etc/
```

### Package Metadata (.PKGINFO)

```toml
[package]
name = "example-app"
version = "1.0.0"
release = 1
description = "An example application for ArxisOS"
url = "https://example.com"
license = "MIT"
arch = "x86_64"

[maintainer]
name = "Developer Name"
email = "dev@example.com"

[dependencies]
runtime = ["glibc>=2.38", "qt6-base"]
optional = ["example-plugins"]

[build]
makedepends = ["cmake", "gcc", "qt6-tools"]

[files]
backup = ["/etc/example/config.toml"]
```

### Compression

ApM packages use **zstd** compression for optimal balance of speed and size:

| Compression | Speed | Size | ApM Default |
|-------------|-------|------|-------------|
| gzip        | Fast  | Large | No |
| xz          | Slow  | Small | No |
| **zstd**    | Fast  | Small | **Yes** |

---

## Usage

### Basic Commands

```bash
# Synchronize package databases
apm sync

# Update all packages
apm upgrade

# Install a package
apm install package-name

# Install from .apm file
apm install ./package-1.0.0-1.apm

# Install RPM package (compatibility mode)
apm install package.rpm

# Remove a package
apm remove package-name

# Search for packages
apm search keyword

# Show package information
apm info package-name

# List installed packages
apm list

# List explicitly installed packages
apm list --explicit

# Clean package cache
apm clean
```

### Advanced Usage

```bash
# Install without dependencies (not recommended)
apm install --nodeps package-name

# Download only, don't install
apm install --downloadonly package-name

# Reinstall a package
apm install --reinstall package-name

# Remove package and its orphaned dependencies
apm remove --recursive package-name

# Query files owned by a package
apm query --files package-name

# Find which package owns a file
apm query --owns /usr/bin/example

# List packages from a specific repository
apm list --repo core

# Check for package updates
apm check-updates
```

### Repository Management

```bash
# List configured repositories
apm repo list

# Add a repository
apm repo add myrepo https://repo.example.com/arxisos

# Remove a repository
apm repo remove myrepo

# Disable a repository temporarily
apm repo disable fedora

# Enable a repository
apm repo enable fedora
```

---

## Building Packages

### APMBUILD File

The `APMBUILD` file is a shell script that defines how to build a package:

```bash
# Maintainer: Your Name <your.email@example.com>

pkgname=example-app
pkgver=1.0.0
pkgrel=1
pkgdesc="An example application for ArxisOS"
arch=('x86_64')
url="https://github.com/example/app"
license=('MIT')
depends=('glibc' 'qt6-base')
makedepends=('cmake' 'gcc' 'qt6-tools')
source=("https://github.com/example/app/archive/v${pkgver}.tar.gz")
sha256sums=('abc123def456...')

prepare() {
    cd "$srcdir/$pkgname-$pkgver"
    # Apply patches, prepare source
}

build() {
    cd "$srcdir/$pkgname-$pkgver"
    cmake -B build \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build build
}

check() {
    cd "$srcdir/$pkgname-$pkgver"
    cmake --build build --target test
}

package() {
    cd "$srcdir/$pkgname-$pkgver"
    DESTDIR="$pkgdir" cmake --install build

    # Install license
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
```

### Building a Package

```bash
# Navigate to directory with APMBUILD
cd ~/packages/example-app

# Build the package
apm-build

# Build and install
apm-build --install

# Build with specific architecture
apm-build --arch x86_64

# Clean build directory
apm-build --clean
```

### Package Validation

```bash
# Validate package before publishing
apm-build --check

# Lint APMBUILD file
apm-lint APMBUILD

# Test installation in container
apm-build --test
```

---

## Repository

### ApR — Arxis Package Repository

ApR is the community-driven package repository for ArxisOS, similar to the AUR for Arch Linux.

#### Submitting Packages

1. **Create an ApR account** at [apr.arxisos.com](https://apr.arxisos.com)

2. **Prepare your package:**
   ```bash
   # Create package directory
   mkdir mypackage && cd mypackage

   # Create APMBUILD
   vim APMBUILD

   # Generate .SRCINFO
   apm-build --geninfo
   ```

3. **Submit to ApR:**
   ```bash
   # Initialize ApR repository
   git init

   # Add ApR remote
   git remote add apr ssh://apr@apr.arxisos.com/mypackage.git

   # Push your package
   git push apr main
   ```

#### Installing from ApR

```bash
# Install ApR helper (included by default)
apm install apr-helper

# Search ApR
apr search package-name

# Install from ApR (builds from source)
apr install package-name

# Update ApR packages
apr upgrade
```

### Repository Configuration

Repository configuration is stored in `/etc/apm/repos.d/`:

```ini
# /etc/apm/repos.d/core.conf
[core]
Server = https://repo.arxisos.com/$repo/$arch
Enabled = true
SigLevel = Required

# /etc/apm/repos.d/fedora.conf
[fedora]
Type = rpm
Server = https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$arch
Enabled = true
SigLevel = Optional
```

---

## RPM Compatibility

### How It Works

ApM includes a compatibility layer that allows seamless installation of RPM packages:

```
┌─────────────────────────────────────────────────────────┐
│                   RPM Compatibility Layer                │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   ┌─────────────┐         ┌─────────────────────────┐   │
│   │  .rpm       │   ───►  │  ApM RPM Handler        │   │
│   │  Package    │         │  • Parse RPM spec       │   │
│   └─────────────┘         │  • Convert dependencies │   │
│                           │  • Extract files        │   │
│                           │  • Run scriptlets       │   │
│                           └───────────┬─────────────┘   │
│                                       │                  │
│                           ┌───────────▼─────────────┐   │
│                           │  ApM Database           │   │
│                           │  (Unified tracking)     │   │
│                           └─────────────────────────┘   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Installing RPM Packages

```bash
# Install RPM from file
apm install ./package-1.0.0.x86_64.rpm

# Install RPM from Fedora repos
apm install --repo fedora package-name

# Query RPM package info
apm info --repo fedora package-name

# List available RPM packages
apm search --repo fedora keyword
```

### Dependency Resolution

When installing RPM packages, ApM:

1. Checks for native `.apm` equivalents first
2. Falls back to RPM if no native package exists
3. Tracks all packages in unified database
4. Handles mixed dependency chains seamlessly

---

## Configuration

### Main Configuration

`/etc/apm/apm.conf`:

```ini
[options]
# Root directory for installation
RootDir = /

# Cache directory for downloads
CacheDir = /var/cache/apm

# Database directory
DBPath = /var/lib/apm

# Log file
LogFile = /var/log/apm.log

# GPG key directory
GPGDir = /etc/apm/gnupg

# Architecture
Architecture = auto

# Parallel downloads
ParallelDownloads = 5

# Check available disk space
CheckSpace = true

# Default signature verification level
SigLevel = Required DatabaseRequired

[colors]
# Enable colored output
Color = auto
```

### Mirror Configuration

`/etc/apm/mirrorlist`:

```
# ArxisOS Official Mirrors
Server = https://repo.arxisos.com/$repo/$arch
Server = https://mirror1.arxisos.com/$repo/$arch
Server = https://mirror2.arxisos.com/$repo/$arch

# Geographic mirrors
Server = https://au.mirror.arxisos.com/$repo/$arch
Server = https://us.mirror.arxisos.com/$repo/$arch
Server = https://eu.mirror.arxisos.com/$repo/$arch
```

---

## Comparison

### ApM vs Other Package Managers

| Feature | ApM | pacman | DNF | apt |
|---------|-----|--------|-----|-----|
| Native Format | `.apm` | `.pkg.tar.zst` | `.rpm` | `.deb` |
| RPM Support | ✅ | ❌ | ✅ | ❌ |
| DEB Support | ❌ | ❌ | ❌ | ✅ |
| Parallel Downloads | ✅ | ✅ | ✅ | ❌ |
| Delta Updates | ✅ | ❌ | ✅ | ❌ |
| AUR-like Repo | ✅ ApR | ✅ AUR | ❌ COPR | ❌ PPA |
| Written In | Rust | C | Python | C++ |
| Transaction Safety | ✅ | ✅ | ✅ | ✅ |

---

## Development Status

### Current Phase: Design & Implementation

| Component | Status | Progress |
|-----------|--------|----------|
| Core Library | 🔄 In Progress | ██░░░░░░░░ 20% |
| CLI Interface | 📋 Planned | ░░░░░░░░░░ 0% |
| Build System | 📋 Planned | ░░░░░░░░░░ 0% |
| RPM Compat | 📋 Planned | ░░░░░░░░░░ 0% |
| Repository | 📋 Planned | ░░░░░░░░░░ 0% |
| Documentation | 🔄 In Progress | ██████░░░░ 60% |

### Roadmap

#### Phase 1: Foundation (Q1 2025)
- [ ] Core library implementation
- [ ] Basic CLI commands (install, remove, query)
- [ ] Local package installation
- [ ] Package database

#### Phase 2: Repositories (Q2 2025)
- [ ] Repository synchronization
- [ ] Dependency resolution
- [ ] Parallel downloads
- [ ] Mirror support

#### Phase 3: RPM Compatibility (Q3 2025)
- [ ] RPM parsing and installation
- [ ] Fedora repository support
- [ ] Mixed dependency resolution

#### Phase 4: Build System (Q4 2025)
- [ ] APMBUILD parser
- [ ] Package building
- [ ] ApR integration

---

## Contributing

We welcome contributions to ApM! See the main [ArxisOS README](README.md#contributing) for general contribution guidelines.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/arxisos/apm.git
cd apm

# Install Rust (if not installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Build the project
cargo build

# Run tests
cargo test

# Run with debug output
RUST_LOG=debug cargo run -- install example
```

### Code Style

- Follow Rust standard formatting (`cargo fmt`)
- Use `clippy` for linting (`cargo clippy`)
- Write tests for new features
- Document public APIs

---

## License

ApM is distributed under the **GNU General Public License v3.0**.

---

<p align="center">
  <strong>ApM</strong> — Simple. Fast. Flexible.
</p>

<p align="center">
  Part of the <a href="README.md">ArxisOS</a> project
</p>
