# Installation Scripts

Automated scripts for installing NixOS on the headless server.

## Scripts

### `install-server.sh` - Main Installation Script

The main orchestration script that automates the entire installation process.

**Usage:**
```bash
./scripts/install-server.sh
```

**What it does:**
1. Finds the NixOS installer on your network
2. SSHs into the installer
3. Uploads and runs the remote installation script
4. Waits for the server to reboot
5. Runs post-installation setup (Samba/WebDAV passwords)
6. Verifies all services are running

**Before running:**
- Edit the script and set `GITHUB_REPO` to your GitHub repository URL
- Make sure you've pushed your latest changes to GitHub
- Boot the server from the installer USB

### `find-installer.sh` - Network Scanner

Helper script to find the NixOS installer on your network.

**Usage:**
```bash
./scripts/find-installer.sh [network-range]

# Examples:
./scripts/find-installer.sh                    # Uses default 192.168.50.0/24
./scripts/find-installer.sh 192.168.1.0/24     # Scan different network
```

**What it does:**
- Scans the network for devices with SSH open
- Identifies which ones are NixOS installers (hostname = "nixos")
- Returns the IP address

### `remote-install.sh` - Remote Installation Script

The script that runs on the installer to perform the actual installation. This is automatically uploaded and executed by `install-server.sh`.

**Usage (typically called by install-server.sh):**
```bash
bash remote-install.sh <github-repo-url> [disk-device]

# Examples:
bash remote-install.sh https://github.com/user/dotfiles.git auto
bash remote-install.sh https://github.com/user/dotfiles.git /dev/sda
```

**What it does:**
1. Detects or verifies the system disk
2. Partitions the disk (EFI + swap + root)
3. Formats the partitions
4. Mounts filesystems
5. Clones configuration from GitHub
6. Generates hardware configuration
7. Installs NixOS
8. Reboots

**Disk detection:**
- `auto`: Automatically detects /dev/sda or /dev/nvme0n1
- Specific device: Uses the provided disk (e.g., /dev/sda)

## Configuration

Before using the scripts, update these settings in `install-server.sh`:

```bash
# Your GitHub repository URL
GITHUB_REPO="https://github.com/YOUR-USERNAME/dotfiles.git"

# Network range to scan for the installer
NETWORK="192.168.50.0/24"

# Disk device (or "auto" for automatic detection)
DISK="auto"

# SSH key location
SSH_KEY="$HOME/.ssh/id_ed25519"
```

## Troubleshooting

### Installer not found

If `find-installer.sh` can't find the installer:

1. Wait longer (installer takes 1-2 minutes to boot)
2. Check the network range is correct
3. Verify the server is connected to the network
4. Check your router's DHCP leases page
5. Try scanning a different network range

### Wrong disk detected

If auto-detection selects the wrong disk:

1. Edit `install-server.sh`
2. Set `DISK="/dev/sda"` (or the correct device)
3. Run the script again

### GitHub clone fails

If cloning from GitHub fails:

1. Verify the repository URL is correct
2. Make sure the repository is public (or configure SSH keys on the installer)
3. Check internet connectivity on the installer

### SSH connection fails

If SSH connection fails:

1. Verify your SSH key is at `~/.ssh/id_ed25519`
2. Check that the key is added to the installer ISO config
3. Try adding `-i ~/.ssh/id_ed25519` to SSH commands

## Manual Installation

If you prefer manual installation or need to debug, see the main [INSTALL.md](../INSTALL.md) guide for detailed step-by-step instructions.
