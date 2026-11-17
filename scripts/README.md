# Installation Scripts

## Automatic Installation (Current)

The NixOS server uses a **fully automatic installation** system embedded in the installer ISO. No external computer or manual scripts are needed.

### How It Works

1. **Boot from USB** - Server boots from the custom installer ISO
2. **10-Second Countdown** - Display shows countdown with abort instructions
3. **Automatic Installation** - Installer detects disk, partitions, installs NixOS from GitHub
4. **Poweroff on Completion** - Server automatically powers off when done
5. **Boot from Disk** - Remove USB drive and boot from internal SSD

### Installation Process

**Step 1: Build the Installer ISO**
```bash
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

**Step 2: Write to USB**
```bash
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**Step 3: Boot Server from USB**
- Insert USB into server
- Power on (or reboot)
- Wait for automatic installation to complete
- Server will poweroff when done (~15-30 minutes)

**Step 4: First Boot**
- Remove USB drive
- Power on server
- SSH into server: `ssh frerom@192.168.50.100` (uses your SSH key)
- Set Samba password: `sudo smbpasswd -a frerom`
- (Optional) Set console password if needed: `sudo passwd frerom`

### Automatic Installer Features

**Smart Disk Detection:**
- Selects smallest non-removable disk (150-350GB range)
- Skips USB drives and virtual devices
- Perfect for Dell OptiPlex 7060 with 240GB SSD

**Partitioning Scheme:**
- 512MB EFI boot partition
- 16GB swap partition
- Remainder for root filesystem (ext4)

**Configuration Source:**
- Clones from: https://github.com/frerom/dotfiles.git
- Installs with flake: `.#server`
- Generates hardware-configuration.nix automatically

**Safety Features:**
- 10-second abort window on boot
- SSH remains available for debugging (port 22)
- Full logging to /var/log/auto-install.log
- Error messages displayed on console
- Won't poweroff on failure (for debugging)

### Debugging Failed Installation

If the automatic installation fails, the server will stay running and display an error message.

**SSH into the installer:**
```bash
# Find the installer IP (check your router or use nmap)
ssh root@192.168.50.XXX
# Password: nixos
```

**Check installation logs:**
```bash
# View full installation log
cat /var/log/auto-install.log

# View systemd service logs
journalctl -u auto-install

# Check service status
systemctl status auto-install
```

**Manual installation (if needed):**
```bash
# Stop the automatic installer
systemctl stop auto-install
systemctl disable auto-install

# Follow manual installation in INSTALL.md
# Or inspect /etc/auto-install.sh to see what failed
```

**Common issues:**
- **Network down**: Git clone will fail - check internet connection
- **Wrong disk detected**: Review /var/log/auto-install.log for disk selection
- **GitHub repo not accessible**: Verify https://github.com/frerom/dotfiles.git is public
- **nixos-install fails**: Check hardware-configuration.nix was generated correctly

### Stopping Automatic Installation

If you want to abort the automatic installation:

**During countdown (first 10 seconds):**
- Press Ctrl+C if connected via console
- Or press power button to shut down

**After installation starts:**
```bash
# SSH into the installer
ssh root@192.168.50.XXX

# Stop the installation
systemctl stop auto-install
```

## Configuration

The automatic installer is configured in `iso/installer.nix`:

```nix
# GitHub repository to clone
GITHUB_REPO="https://github.com/frerom/dotfiles.git"

# Disk size range for detection
MIN_DISK_SIZE=$((150 * 1024 * 1024 * 1024))  # 150GB
MAX_DISK_SIZE=$((350 * 1024 * 1024 * 1024))  # 350GB

# Target flake configuration
nixos-install --flake .#server
```

## Legacy Scripts

The old manual installation scripts have been moved to `scripts/old/`:
- `install-server.sh` - Required external computer and manual confirmations
- `find-installer.sh` - Network scanning (slow and unreliable)
- `remote-install.sh` - Remote installation script

These are kept for reference but are no longer needed with the automatic installer.

## Installer ISO Configuration

The automatic installer is defined in `iso/installer.nix` and includes:
- SSH enabled on boot (root password: `nixos`)
- Your SSH key pre-authorized for root access
- NetworkManager for automatic network setup
- Auto-install script at `/etc/auto-install.sh`
- Systemd service `auto-install.service` (oneshot)
- Helpful packages: vim, git, parted, gptfdisk, util-linux

See [INSTALL.md](../INSTALL.md) for complete installation guide and [iso/installer.nix](../iso/installer.nix) for the full implementation.
