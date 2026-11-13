# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS configuration repository using flakes and home-manager. It manages system configurations for two hosts (`thinkpad` and `office`) with shared common settings.

## Build and Deploy Commands

### Rebuild System Configuration
```bash
# For thinkpad host
sudo nixos-rebuild switch --flake .#thinkpad

# For office host
sudo nixos-rebuild switch --flake .#office
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

### Three-Layer Configuration Structure

1. **Flake Entry Point** (`flake.nix`)
   - Defines two NixOS configurations: `office` and `thinkpad`
   - Integrates home-manager as a NixOS module
   - Uses `mkHost` helper function to create host configurations
   - All hosts share the same home-manager configuration (`home.nix`) for user `frerom`

2. **Common System Configuration** (`common.nix`)
   - Imported by all host-specific configurations
   - Contains shared system settings: timezone, locale, user definition, bootloader, GNOME desktop, fonts
   - Defines system-wide packages and services (kanata keyboard remapping, pipewire audio)
   - Sets up autologin for user `frerom`

3. **Host-Specific Configuration** (`hosts/{hostname}/configuration.nix`)
   - Each host imports `hardware-configuration.nix` and `../../common.nix`
   - **thinkpad**: Minimal configuration with LUKS encryption setup, wireless networking
   - **office**: Gaming-focused with NVIDIA drivers, Steam, Lutris, custom kernel parameters for 4K@120Hz display

4. **Home Manager Configuration** (`home.nix`)
   - User-level packages and configurations
   - Shared across both hosts
   - Configures git, emacs, and user packages

### Configuration Inheritance Flow
```
flake.nix
  └─> hosts/{hostname}/configuration.nix
        ├─> hardware-configuration.nix (hardware-specific)
        └─> common.nix (shared system config)
  └─> home.nix (user configuration via home-manager)
```

## Important Files

- `flake.nix` - Flake definition with host configurations
- `common.nix` - Shared system configuration for all hosts
- `home.nix` - Home-manager configuration for user `frerom`
- `hosts/thinkpad/configuration.nix` - ThinkPad-specific settings
- `hosts/office/configuration.nix` - Office desktop settings (NVIDIA, gaming)
- `init.el` - Emacs configuration (not managed by home-manager, standalone file)

## Key Configuration Details

### System Settings (common.nix)
- Timezone: Europe/Stockholm
- Locale: en_US.UTF-8 with Swedish regional settings
- Desktop: GNOME with GDM
- Keyboard: Caps Lock remapped to Control via kanata
- Fonts: Fira Code and Fira Code Nerd Font

### Office Host Specifics
- NVIDIA proprietary drivers with open kernel module
- Custom display resolution: 3840x2160@120Hz on DP-1
- Gaming packages: Steam, Lutris, Heroic, ProtonUp-Qt
- Bluetooth and USB automounting enabled

### ThinkPad Specifics
- LUKS full disk encryption
- User-controlled wireless networking

### Emacs Configuration
- Standalone `init.el` file (not managed via home-manager)
- Uses `use-package` for package management
- Packages: ivy, counsel, doom-modeline, which-key, rainbow-delimiters
- Font: Fira Code at size 130
