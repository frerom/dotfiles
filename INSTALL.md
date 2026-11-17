# Headless NixOS Server Installation Guide

Complete automatic installation guide for the Dell OptiPlex 7060 server. No keyboard or monitor needed.

## Overview

**Server Specifications:**
- **Hardware:** Dell OptiPlex 7060 (i5-8500, 16GB RAM, 240GB SSD)
- **Hostname:** server (accessible as `server.local` via mDNS)
- **Static IP:** 192.168.50.100
- **Services:** Jellyfin media server, Samba/SMB, NFS file sharing
- **SSH:** Key-based authentication only

**Installation Method:**
- Fully automatic installation from USB
- No external computer required
- Powers off when complete

---

## Quick Start: Automatic Installation

### Step 1: Prepare Configuration

Push your latest configuration to GitHub:

```bash
cd ~/dotfiles
git add .
git commit -m "Prepare for server installation"
git push
```

The installer clones from: `https://github.com/frerom/dotfiles.git`

### Step 2: Build Installer ISO

```bash
cd ~/dotfiles

# Build the custom installer ISO
nix build .#nixosConfigurations.installer.config.system.build.isoImage

# Write to USB (replace /dev/sdX with your USB device)
# WARNING: This will erase all data on the USB drive
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Safely eject
sync
```

### Step 3: Boot and Install

1. **Insert USB** into server
2. **Connect Ethernet** cable
3. **Power on** the server
4. **Wait for 10-second countdown** (displayed on console if monitor connected)
   - Press Ctrl+C or power button to abort
5. **Automatic installation begins** (~15-30 minutes)
6. **Server powers off** when complete

### Step 4: First Boot

1. **Remove USB drive**
2. **Power on** the server
3. **Wait 1-2 minutes** for boot
4. **SSH into server:**
   ```bash
   ssh frerom@192.168.50.100
   # or
   ssh frerom@server.local
   # Uses your SSH key automatically (no password needed)
   ```

### Step 5: Post-Installation Setup

```bash
# (Optional) Change your password from "nixos" if you need console access
passwd

# Set Samba password for file sharing
sudo smbpasswd -a frerom

# Verify services are running
systemctl status jellyfin
systemctl status smbd
systemctl status nfs-server
systemctl status sshd
```

**That's it!** Your server is fully installed and ready to use.

---

## What the Automatic Installer Does

The installer ISO performs these steps automatically:

1. **10-Second Abort Window**
   - Displays countdown on console
   - Press Ctrl+C or power button to abort
   - SSH remains available for debugging

2. **Smart Disk Detection**
   - Finds smallest non-removable disk (150-350GB range)
   - Perfect for Dell OptiPlex 7060 with 240GB SSD
   - Skips USB drives and virtual devices

3. **Partitioning**
   - 512MB EFI boot partition
   - 16GB swap partition (matches RAM)
   - Remainder for root filesystem (ext4)

4. **Installation**
   - Clones configuration from GitHub
   - Generates hardware-configuration.nix
   - Installs NixOS with `.#server` flake
   - Configures all services

5. **Completion**
   - Powers off automatically on success
   - Displays error and stays running on failure
   - Full logs at `/var/log/auto-install.log`

---

## Accessing Services

### SSH Access
```bash
ssh frerom@192.168.50.100
ssh frerom@server.local
```

### Jellyfin Media Server
Open in browser:
- `http://192.168.50.100:8096`
- `http://server.local:8096`

**Initial Setup:**
1. Complete the setup wizard
2. Create admin account
3. Add media libraries (point to `/mnt/media`)

### Samba/SMB File Sharing

**From Windows:**
- File Explorer → `\\server.local\media` or `\\192.168.50.100\media`
- Username: `frerom`, Password: (set with `smbpasswd`)

**From macOS:**
- Finder → Go → Connect to Server (⌘K)
- Enter: `smb://server.local/media`

**From Linux:**
```bash
smbclient //server.local/media -U frerom
```

### NFS File Sharing

**Mount on Linux:**
```bash
# Temporary mount
sudo mount -t nfs server.local:/mnt/media /mnt/test

# Permanent (add to /etc/fstab):
server.local:/mnt/media /mnt/media nfs defaults 0 0
```

---

## Adding Media Storage Drive

When you add additional drives for media:

### 1. Format the Drive

```bash
ssh frerom@server.local

# Identify the drive
lsblk

# Format (assuming /dev/sdb)
sudo mkfs.ext4 -L media /dev/sdb

# Get UUID
lsblk -f /dev/sdb
# Note the UUID
```

### 2. Update Hardware Configuration

```bash
# Edit hardware config
sudo vim /etc/nixos/hosts/server/hardware-configuration.nix

# Add this section (replace YOUR-UUID-HERE):
fileSystems."/mnt/media" = {
  device = "/dev/disk/by-uuid/YOUR-UUID-HERE";
  fsType = "ext4";
};
```

### 3. Apply Changes

```bash
# Rebuild system
cd /etc/nixos
sudo nixos-rebuild switch --flake .#server

# Set permissions
sudo chown -R frerom:users /mnt/media
sudo chmod 755 /mnt/media

# Create media directories
mkdir -p /mnt/media/{movies,tv,music,photos}
```

### 4. Configure Jellyfin

1. Open Jellyfin: `http://server.local:8096`
2. Add Media Library → Choose type (Movies, TV Shows, etc.)
3. Set path: `/mnt/media/movies` (or `/mnt/media/tv`, etc.)

---

## Debugging Failed Installation

If the automatic installation fails, the server will stay running and display an error.

### SSH into the Installer

```bash
# Find the installer IP (check router or use nmap)
ssh root@192.168.50.XXX
# Password: nixos
```

### Check Installation Logs

```bash
# View full log
cat /var/log/auto-install.log

# View systemd service logs
journalctl -u auto-install

# Check service status
systemctl status auto-install
```

### Common Issues

**Network/Internet Down:**
- Git clone will fail
- Check Ethernet connection
- Verify internet access: `ping google.com`

**Wrong Disk Detected:**
- Review `/var/log/auto-install.log` for disk selection
- Check disk sizes: `lsblk`
- Only disks 150-350GB are considered

**GitHub Repository Not Accessible:**
- Verify `https://github.com/frerom/dotfiles.git` is public
- Test clone manually: `git clone https://github.com/frerom/dotfiles.git`

**nixos-install Failed:**
- Check hardware-configuration.nix was generated
- Review error messages in log
- Verify disk partitions: `lsblk`

### Manual Installation

If automatic installation fails and you need to install manually:

```bash
# Stop the auto-installer
systemctl stop auto-install
systemctl disable auto-install

# Follow the manual installation steps below
```

---

## Manual Installation (Alternative)

If you need more control or the automatic installer fails, follow these manual steps.

### 1. Boot Installer and Connect

```bash
# Boot from USB and find the server IP
# From your computer:
nmap -sn 192.168.50.0/24 | grep -B 2 "Dell"

# SSH into installer
ssh root@<IP-ADDRESS>
# Password: nixos
```

### 2. Partition Disk

```bash
# Identify disk
lsblk

# Set disk variable (adjust for your system)
DISK=/dev/sda

# Create partitions
parted $DISK -- mklabel gpt
parted $DISK -- mkpart ESP fat32 1MiB 512MiB
parted $DISK -- set 1 esp on
parted $DISK -- mkpart primary linux-swap 512MiB 16GiB
parted $DISK -- mkpart primary ext4 16GiB 100%

# Format partitions
mkfs.fat -F 32 -n BOOT ${DISK}1
mkswap -L swap ${DISK}2
mkfs.ext4 -L nixos ${DISK}3

# Mount filesystems
mount ${DISK}3 /mnt
mkdir -p /mnt/boot
mount ${DISK}1 /mnt/boot
swapon ${DISK}2
```

### 3. Clone Configuration

```bash
cd /mnt
git clone https://github.com/frerom/dotfiles.git etc/nixos
```

### 4. Generate Hardware Config

```bash
# Generate hardware configuration
nixos-generate-config --root /mnt

# Copy to server host directory
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/server/

# Verify
cat /mnt/etc/nixos/hosts/server/hardware-configuration.nix
```

### 5. Install NixOS

```bash
cd /mnt/etc/nixos
nixos-install --flake .#server --no-root-passwd
```

### 6. Reboot

```bash
reboot
# Remove USB drive during reboot
```

---

## Maintenance

### Update System

```bash
ssh frerom@server.local
cd /etc/nixos

# Update flake inputs
nix flake update

# Rebuild system
sudo nixos-rebuild switch --flake .#server
```

### Clean Up Old Generations

```bash
# Remove old system generations
sudo nix-collect-garbage -d

# Optimize nix store
sudo nix-store --optimise
```

### View Service Logs

```bash
# Jellyfin
sudo journalctl -u jellyfin -f

# Samba
sudo journalctl -u smbd -f

# NFS
sudo journalctl -u nfs-server -f

# SSH
sudo journalctl -u sshd -f
```

---

## Backup Configuration

After successful installation, back up the hardware configuration to git:

```bash
# On your local machine
cd ~/dotfiles
scp frerom@server.local:/etc/nixos/hosts/server/hardware-configuration.nix hosts/server/
git add hosts/server/hardware-configuration.nix
git commit -m "Add server hardware configuration"
git push
```

Now your entire server configuration is version controlled!

---

## Troubleshooting

### Cannot Find Server After Boot

- Wait 2-3 minutes for first boot
- Check router DHCP leases
- Scan network: `nmap -sn 192.168.50.0/24`
- Try connecting monitor temporarily

### SSH Connection Refused

- Wait 30-60 seconds for SSH to start
- Verify firewall allows port 22
- Check SSH service: `ssh frerom@server.local systemctl status sshd`

### Samba Authentication Fails

- Reset password: `ssh frerom@server.local sudo smbpasswd -a frerom`
- Check Samba is running: `systemctl status smbd`
- Verify network range in config
- Check logs: `sudo journalctl -u smbd -f`

### Jellyfin Cannot Access Media

- Verify directory exists: `ls -la /mnt/media`
- Check mount: `df -h | grep media`
- Fix permissions: `sudo chown -R frerom:users /mnt/media`
- Check logs: `sudo journalctl -u jellyfin -f`

### Static IP Not Working

```bash
# Find actual interface name
ip link show

# Edit configuration
sudo vim /etc/nixos/hosts/server/configuration.nix

# Update interface name from eno1 to your actual interface
# networking.interfaces.ACTUAL-NAME.ipv4.addresses = [{

# Rebuild
sudo nixos-rebuild switch --flake .#server
```

---

## Network Configuration

**Server Settings:**
- Network: 192.168.50.0/24
- Gateway: 192.168.50.1
- Server IP: 192.168.50.100
- DNS: 192.168.50.1, 8.8.8.8
- Hostname: server
- mDNS: server.local

**Service Ports:**

| Service | Port(s) | Protocol | Purpose |
|---------|---------|----------|---------|
| SSH | 22 | TCP | Remote access |
| Samba | 139, 445 | TCP | File sharing |
| Samba | 137, 138 | UDP | File sharing |
| NFS | 2049 | TCP/UDP | File sharing |
| Jellyfin | 8096 | TCP | Web UI |
| Jellyfin | 8920 | TCP | HTTPS |
| Jellyfin | 7359 | UDP | Discovery |
| Jellyfin | 1900 | UDP | DLNA |
| mDNS | 5353 | UDP | Local discovery |

---

## See Also

- [scripts/README.md](scripts/README.md) - Automatic installer documentation
- [CLAUDE.md](CLAUDE.md) - Repository architecture and guidance
- [iso/installer.nix](iso/installer.nix) - Installer ISO configuration
