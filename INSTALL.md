# Headless NixOS Server Installation Guide

This guide explains how to install NixOS on a headless server (Dell OptiPlex 7060) without a keyboard or monitor.

## Overview

The server configuration includes:
- **Hostname:** server (accessible as `server.local` via mDNS)
- **Static IP:** 192.168.50.100
- **Services:** Jellyfin media server, Samba/SMB, NFS, WebDAV
- **SSH:** Key-based authentication only

## Prerequisites

- USB drive (8GB or larger)
- Network connection for the server (Ethernet cable)
- Another computer on the same network to perform the installation from
- GitHub repository with your dotfiles (push your changes before installation)

---

## Quick Start: Automated Installation (Recommended)

**The easiest way to install is using the automated installation script.**

### Step 1: Prepare Your Configuration

Make sure your latest configuration is pushed to GitHub:

```bash
cd ~/dotfiles
git add .
git commit -m "Prepare for server installation"
git push
```

The installation script is already configured to use: `https://github.com/frerom/dotfiles.git`

### Step 2: Build and Write Installer ISO

```bash
cd ~/dotfiles

# Build the installer ISO
nix build .#nixosConfigurations.installer.config.system.build.isoImage

# Write to USB (replace /dev/sdX with your USB device)
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

### Step 3: Boot Server from USB

1. Insert USB into the Dell OptiPlex 7060
2. Connect Ethernet cable
3. Power on the server
4. Wait 1-2 minutes for the installer to boot

### Step 4: Run Automated Installation

From your computer (on the same network):

```bash
cd ~/dotfiles
./scripts/install-server.sh
```

The script will:
- ✓ Find the installer on your network
- ✓ SSH into the installer
- ✓ Partition and format the disk
- ✓ Clone your configuration from GitHub
- ✓ Install NixOS
- ✓ Reboot the server
- ✓ Configure Samba and WebDAV passwords
- ✓ Verify all services are running

**That's it!** The entire installation is automated.

After completion, your server will be accessible at:
- SSH: `ssh frerom@192.168.50.100` or `ssh frerom@server.local`
- Jellyfin: `http://server.local:8096`
- Samba: `\\server.local\media`

Jump to [Part 10](#part-10-add-media-storage-drive) to add your media storage drive.

---

## Manual Installation (Alternative)

If you prefer to run each step manually or need more control, follow the detailed steps below.

## Part 1: Build Custom Installer ISO

The custom installer ISO has SSH auto-enabled for headless installation.

```bash
cd /home/frerom/dotfiles

# Build the installer ISO
nix build .#nixosConfigurations.installer.config.system.build.isoImage

# The ISO will be in result/iso/
ls -lh result/iso/
```

## Part 2: Create Bootable USB

```bash
# Identify your USB device
lsblk

# Write ISO to USB (replace /dev/sdX with your USB device)
# WARNING: This will erase all data on the USB drive!
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Safely eject the USB
sync
sudo eject /dev/sdX
```

## Part 3: Boot Server and Connect via SSH

### 3.1 Boot the Server

1. Insert USB drive into the Dell OptiPlex 7060
2. Connect Ethernet cable
3. Power on the server
4. Wait ~1-2 minutes for the installer to boot

### 3.2 Find the Server's IP Address

From your computer (on the same network):

```bash
# Option 1: Scan your network for new devices
nmap -sn 192.168.50.0/24 | grep -B 2 "Dell"

# Option 2: Check your router's DHCP leases page

# Option 3: Ping sweep
for i in {1..254}; do
  ping -c 1 -W 1 192.168.50.$i >/dev/null && echo "192.168.50.$i is up"
done
```

### 3.3 SSH into the Installer

```bash
# Connect via SSH (password: nixos, or use your SSH key)
ssh root@<IP-ADDRESS>

# Example:
# ssh root@192.168.50.205
```

## Part 4: Partition and Format Disk

Once connected via SSH to the installer:

```bash
# Identify the system disk (240GB SSD)
lsblk

# Set disk variable (adjust if needed)
# Use /dev/sda for SATA drives, /dev/nvme0n1 for NVMe drives
DISK=/dev/sda

# Partition the disk
# - 512MB EFI boot partition
# - 16GB swap (matching RAM)
# - Rest for root filesystem
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

# Verify mounts
df -h
```

## Part 5: Clone Configuration

```bash
# Install git if not available
nix-shell -p git

# Clone your dotfiles to the installation target
cd /mnt
git clone https://github.com/USERNAME/dotfiles.git etc/nixos

# If you haven't pushed to GitHub yet, copy from your local machine:
# On your local machine:
#   tar czf /tmp/dotfiles.tar.gz -C /home/frerom dotfiles
#   scp /tmp/dotfiles.tar.gz root@<SERVER-IP>:/mnt/tmp/
#
# On the server:
#   cd /mnt/etc
#   tar xzf /tmp/dotfiles.tar.gz
#   mv dotfiles nixos
```

## Part 6: Generate Hardware Configuration

```bash
cd /mnt/etc/nixos

# Generate hardware configuration
nixos-generate-config --root /mnt

# Copy generated hardware config to server host directory
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/server/

# Verify the UUIDs were detected
cat /mnt/etc/nixos/hosts/server/hardware-configuration.nix
```

## Part 7: Install NixOS

```bash
cd /mnt/etc/nixos

# Install NixOS with the server configuration
nixos-install --flake .#server --no-root-passwd

# This will:
# - Install NixOS with all packages
# - Set up Jellyfin, Samba, NFS, WebDAV
# - Configure networking and SSH
# - No password needed (SSH key authentication only)
```

## Part 8: Reboot

```bash
# Reboot the server
reboot

# Remove the USB drive during reboot
```

## Part 9: Post-Installation Setup

After the server reboots (wait ~30-60 seconds):

### 9.1 Connect to the New Server

```bash
# Via static IP
ssh frerom@192.168.50.100

# Or via mDNS
ssh frerom@server.local
```

### 9.2 Set Samba Password

```bash
# Set password for Samba file sharing
sudo smbpasswd -a frerom
# Enter password when prompted
```

### 9.3 Create WebDAV Password File

```bash
# Create password file for WebDAV
echo "frerom:$(openssl passwd -apr1)" | sudo tee /etc/nginx/webdav.passwd
sudo chmod 640 /etc/nginx/webdav.passwd
sudo chown root:nginx /etc/nginx/webdav.passwd
```

### 9.4 Verify Services

```bash
# Check service status
systemctl status jellyfin
systemctl status smbd nmbd
systemctl status nfs-server
systemctl status nginx
systemctl status avahi-daemon
systemctl status sshd
```

## Part 10: Add Media Storage Drive

When you add additional storage drives for media:

### 10.1 Format the Drive

```bash
# Connect the drive and identify it
lsblk

# Format the drive (assuming /dev/sdb)
sudo mkfs.ext4 -L media /dev/sdb

# Get the UUID
lsblk -f /dev/sdb
# Note the UUID shown
```

### 10.2 Update Hardware Configuration

```bash
# Edit hardware configuration
sudo vim /etc/nixos/hosts/server/hardware-configuration.nix

# Add this section:
# fileSystems."/mnt/media" = {
#   device = "/dev/disk/by-uuid/YOUR-UUID-HERE";
#   fsType = "ext4";
# };
```

### 10.3 Rebuild and Set Permissions

```bash
# Rebuild to apply changes
cd /etc/nixos
sudo nixos-rebuild switch --flake .#server

# Set permissions
sudo chown -R frerom:users /mnt/media
sudo chmod 755 /mnt/media
```

## Part 11: Configure Jellyfin

1. Open browser: `http://192.168.50.100:8096` or `http://server.local:8096`
2. Complete the setup wizard
3. Create admin account
4. Add media libraries:
   - Click "Add Media Library"
   - Choose type (Movies, TV Shows, Music, etc.)
   - Set path: `/mnt/media/movies` (or `/mnt/media/tv`, etc.)
5. Configure transcoding settings
6. Set up remote access (optional)

Create subdirectories for organized media:
```bash
ssh frerom@server.local
mkdir -p /mnt/media/{movies,tv,music,photos}
```

## Part 12: Test Services

### SSH Access
```bash
ssh frerom@192.168.50.100
ssh frerom@server.local
```

### Jellyfin Web UI
Open in browser:
- `http://192.168.50.100:8096`
- `http://server.local:8096`

### Samba/SMB Share

**From Linux:**
```bash
smbclient //server.local/media -U frerom
```

**From Windows:**
1. Open File Explorer
2. Enter in address bar: `\\server.local\media` or `\\192.168.50.100\media`
3. Enter username: `frerom` and password

**From macOS:**
1. Finder → Go → Connect to Server (⌘K)
2. Enter: `smb://server.local/media` or `smb://192.168.50.100/media`
3. Enter credentials

### NFS Mount

**From Linux:**
```bash
# Mount temporarily
sudo mount -t nfs server.local:/mnt/media /mnt/test
ls /mnt/test
sudo umount /mnt/test

# Mount permanently (add to /etc/fstab):
# server.local:/mnt/media /mnt/media nfs defaults 0 0
```

### WebDAV Access

**From command line:**
```bash
# Test with curl
curl -u frerom:password http://server.local/webdav/

# Mount on Linux
sudo mount -t davfs http://server.local/webdav /mnt/webdav
```

**From Windows:**
1. Map network drive
2. Enter: `http://server.local/webdav`

**From macOS:**
1. Finder → Go → Connect to Server (⌘K)
2. Enter: `http://server.local/webdav`

## Maintenance

### Update System

```bash
ssh frerom@server.local

# Update flake inputs
cd /etc/nixos
nix flake update

# Rebuild with updates
sudo nixos-rebuild switch --flake .#server
```

### Clean Up Old Generations

```bash
# Remove old system generations to free space
sudo nix-collect-garbage -d

# Optimize nix store
sudo nix-store --optimise
```

### View Logs

```bash
# Jellyfin logs
sudo journalctl -u jellyfin -f

# Samba logs
sudo journalctl -u smbd -f
sudo journalctl -u nmbd -f

# NFS logs
sudo journalctl -u nfs-server -f

# Nginx logs
sudo journalctl -u nginx -f

# SSH logs
sudo journalctl -u sshd -f
```

## Troubleshooting

### Cannot Find Server After Boot

- Wait longer (first boot can take 2-3 minutes)
- Check router DHCP leases for new device
- Scan network: `nmap -sn 192.168.50.0/24`
- Try connecting a monitor temporarily to see IP on console

### SSH Connection Refused

- Wait 30-60 seconds after boot for SSH to start
- Verify SSH service: `systemctl status sshd` (if you have console access)
- Check firewall allows port 22

### Samba Authentication Fails

- Verify Samba password is set: `sudo smbpasswd -a frerom`
- Check Samba is running: `systemctl status smbd`
- Verify network range in config matches your network
- Check Samba logs: `sudo journalctl -u smbd -f`

### Jellyfin Cannot Access Media

- Check directory exists: `ls -la /mnt/media`
- Ensure media drive is mounted: `df -h | grep media`
- Check permissions: `sudo chown -R jellyfin:jellyfin /mnt/media`
- Check Jellyfin logs: `sudo journalctl -u jellyfin -f`

### NFS Mount Fails

- Verify NFS server is running: `systemctl status nfs-server`
- Check exports: `sudo exportfs -v`
- Verify client IP is in allowed range (192.168.50.0/24)
- Check firewall allows NFS ports

### Out of Space on System Drive

- Clear old generations: `sudo nix-collect-garbage -d`
- Optimize nix store: `sudo nix-store --optimise`
- Check disk usage: `df -h`
- Move large files to media drive
- Clear Jellyfin cache: `sudo du -sh /var/lib/jellyfin`

### Static IP Not Working

If the network interface name isn't `eno1`:

```bash
# Find the actual interface name
ip link show

# Edit configuration
sudo vim /etc/nixos/hosts/server/configuration.nix

# Update line:
# networking.interfaces.ACTUAL-NAME.ipv4.addresses = [{

# Rebuild
sudo nixos-rebuild switch --flake .#server
```

## Network Configuration Reference

Current server network settings:
- **Network:** 192.168.50.0/24
- **Gateway:** 192.168.50.1
- **Server IP:** 192.168.50.100
- **DNS:** 192.168.50.1, 8.8.8.8
- **Hostname:** server
- **mDNS:** server.local

## Service Ports

| Service | Port(s) | Protocol | Purpose |
|---------|---------|----------|---------|
| SSH | 22 | TCP | Remote access |
| Samba | 139, 445 | TCP | File sharing |
| Samba | 137, 138 | UDP | File sharing |
| NFS | 2049 | TCP/UDP | File sharing |
| WebDAV | 80 | TCP | File sharing |
| Jellyfin | 8096 | TCP | Web UI |
| Jellyfin | 8920 | TCP | HTTPS |
| Jellyfin | 7359 | UDP | Discovery |
| Jellyfin | 1900 | UDP | DLNA |
| mDNS | 5353 | UDP | Local discovery |

## Backup Configuration

After successful installation, commit the hardware configuration:

```bash
# On your local machine
cd /home/frerom/dotfiles
scp frerom@server.local:/etc/nixos/hosts/server/hardware-configuration.nix hosts/server/
git add hosts/server/hardware-configuration.nix
git commit -m "Add server hardware configuration"
git push
```

Now your entire server configuration is backed up in git!
