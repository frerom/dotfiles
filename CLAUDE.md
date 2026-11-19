# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS configuration repository using flakes and home-manager. It manages system configurations for three hosts:
- `thinkpad` - Laptop with LUKS encryption
- `office` - Desktop with NVIDIA GPU and gaming setup
- `server` - Headless Dell OptiPlex 7060 running Jellyfin and NAS services

## Build and Deploy Commands

### Rebuild System Configuration
```bash
# For thinkpad host
sudo nixos-rebuild switch --flake .#thinkpad

# For office host
sudo nixos-rebuild switch --flake .#office

# For server host (headless)
sudo nixos-rebuild switch --flake .#server
```

### Build Installer ISO
```bash
# Build custom headless installer ISO
nix build .#nixosConfigurations.installer.config.system.build.isoImage

# Write to USB
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### Automated Server Installation
```bash
# Build custom installer ISO with automatic installation
nix build .#nixosConfigurations.installer.config.system.build.isoImage

# Write to USB
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Boot server from USB - automatic installation starts after 10-second countdown
# Server will poweroff when installation complete (~15-30 minutes)

# See INSTALL.md for detailed guide and scripts/README.md for installer documentation
```

### Flake Operations
```bash
# Update flake inputs
nix flake update

# Check flake configuration
nix flake check

# Show flake info
nix flake show
```

## Architecture

### Four-Layer Configuration Structure

1. **Flake Entry Point** (`flake.nix`)
   - Defines three NixOS configurations: `office`, `thinkpad`, and `server`
   - Defines custom installer ISO configuration: `installer`
   - Integrates home-manager as a NixOS module
   - Uses `mkHost` helper function to create host configurations
   - All hosts share the same home-manager configuration (`home.nix`) for user `frerom`

2. **Common System Configuration** (`common.nix`)
   - Imported by ALL host configurations
   - Contains truly shared settings: timezone, locale, user definition, bootloader, NetworkManager
   - Minimal base packages (vim, git)
   - Nix flakes configuration

3. **Desktop-Specific Configuration** (`desktop-common.nix`)
   - Imported by desktop/laptop hosts (`thinkpad`, `office`)
   - GNOME desktop and GDM display manager
   - Autologin for user `frerom`
   - PipeWire audio stack
   - Printing (CUPS), Firefox browser
   - Kanata keyboard remapping (Caps Lock → Control)
   - Desktop packages and fonts

4. **Server-Specific Configuration** (`server-common.nix`)
   - Imported by headless server hosts (`server`)
   - Minimal server packages (htop, curl, wget, rsync)
   - No desktop services, audio, or autologin

5. **Host-Specific Configuration** (`hosts/{hostname}/configuration.nix`)
   - Each host imports `hardware-configuration.nix`, `common.nix`, and either `desktop-common.nix` or `server-common.nix`
   - **thinkpad**: LUKS encryption, wireless networking, imports desktop-common.nix
   - **office**: NVIDIA drivers, gaming packages (Steam, Lutris), custom display settings, imports desktop-common.nix
   - **server**: Static IP (192.168.50.100), SSH, Jellyfin, Samba, NFS, WebDAV, imports server-common.nix

6. **Home Manager Configuration** (`home.nix`)
   - User-level packages and configurations
   - Shared across all hosts
   - Configures git, emacs, and user packages

### Configuration Inheritance Flow
```
flake.nix
  └─> hosts/{hostname}/configuration.nix
        ├─> hardware-configuration.nix (hardware-specific)
        ├─> common.nix (shared base config)
        └─> desktop-common.nix (for desktop/laptop hosts)
            OR
            server-common.nix (for headless server hosts)
  └─> home.nix (user configuration via home-manager)
```

## Important Files

### Configuration Files
- `flake.nix` - Flake definition with host configurations and installer ISO
- `common.nix` - Shared base configuration for ALL hosts
- `desktop-common.nix` - Desktop-specific configuration (GNOME, audio, etc.)
- `server-common.nix` - Server-specific configuration (minimal packages)
- `home.nix` - Home-manager configuration for user `frerom`
- `hosts/thinkpad/configuration.nix` - ThinkPad-specific settings
- `hosts/office/configuration.nix` - Office desktop settings (NVIDIA, gaming)
- `hosts/server/configuration.nix` - Server settings (Jellyfin, NAS services)
- `iso/installer.nix` - Custom installer ISO with SSH auto-enabled
- `init.el` - Emacs configuration (not managed by home-manager, standalone file)

### Documentation
- `INSTALL.md` - Headless server installation guide (manual and automated)
- `CLAUDE.md` - This file, repository structure and guidance
- `scripts/README.md` - Installation scripts documentation

### Automation
- `iso/installer.nix` - Custom installer ISO with fully automatic installation
- Automatic installation script embedded at `/etc/auto-install.sh`
- Systemd oneshot service `auto-install.service`
- Legacy scripts archived in `scripts/old/` (no longer needed)

## Key Configuration Details

### System Settings (common.nix)
- Timezone: Europe/Stockholm
- Locale: en_US.UTF-8 with Swedish regional settings
- User: frerom (wheel group, NetworkManager access)
- Bootloader: systemd-boot with UEFI
- Minimal base packages: vim, git

### Desktop Settings (desktop-common.nix)
- Desktop: GNOME with GDM
- Autologin for user `frerom`
- Keyboard: Caps Lock remapped to Control via kanata
- Audio: PipeWire with ALSA and PulseAudio support
- Printing: CUPS enabled
- Fonts: Fira Code and Fira Code Nerd Font
- Desktop packages: ghostty, prusa-slicer, proton-pass, anki-bin

### Office Host Specifics
- NVIDIA proprietary drivers with open kernel module
- Custom display resolution: 3840x2160@120Hz on DP-1
- Gaming packages: Steam, Lutris, Heroic, ProtonUp-Qt
- Bluetooth and USB automounting enabled

### ThinkPad Specifics
- LUKS full disk encryption
- User-controlled wireless networking

### Server Host Specifics
- **Hardware:** Dell OptiPlex 7060 (i5-8500, 16GB RAM, 240GB SSD)
- **Network:** Static IP 192.168.50.100, accessible as server.local via mDNS
- **SSH:** Key-based authentication only, no password authentication
- **Installation:** Fully automatic from USB - powers off when complete
- **Services:**
  - Jellyfin media server at https://jellyfin.home.rekordfirman.se (nginx → 8096, port 8096 not exposed)
  - Grafana network monitor at https://grafana.home.rekordfirman.se
  - TLS: Let's Encrypt wildcard `*.home.rekordfirman.se` via DNS-01 (Loopia API, creds in `/var/lib/secrets/loopia.env`); names resolve to the server only via the LAN dnsmasq
  - Samba/SMB file sharing (ports 139, 445)
  - NFS file sharing (port 2049)
  - WebDAV via nginx (port 80) - currently disabled
  - Avahi for mDNS discovery
- **Media Storage:** /mnt/media (configured for separate storage drive)
- **Firewall:** Enabled with specific ports open for services
- See `INSTALL.md` for complete installation guide

### Installer ISO Specifics
- **Custom ISO:** `iso/installer.nix` with embedded automatic installation
- **Auto-Install Features:**
  - 10-second abort countdown on boot
  - Smart disk detection (150-350GB range, non-removable)
  - Automatic partitioning (512MB EFI + 16GB swap + rest root)
  - Clones from GitHub: https://github.com/frerom/dotfiles.git
  - Generates hardware-configuration.nix
  - Installs NixOS with `.#server` flake
  - Powers off on success, stays running on failure
- **Debugging:** SSH enabled (root password: "nixos"), logs at /var/log/auto-install.log
- **Safety:** 10-second abort window, full error reporting, can be stopped via `systemctl stop auto-install`

### Emacs Configuration
- Standalone `init.el` file (not managed via home-manager)
- Uses `use-package` for package management
- Packages: ivy, counsel, doom-modeline, which-key, rainbow-delimiters
- Font: Fira Code at size 130
