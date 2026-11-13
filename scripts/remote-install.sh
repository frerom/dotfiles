#!/usr/bin/env bash
# Remote installation script that runs on the NixOS installer
# This script is uploaded and executed by install-server.sh

set -euo pipefail

GITHUB_REPO="${1:-}"
DISK="${2:-auto}"

if [ -z "$GITHUB_REPO" ]; then
    echo "Usage: $0 <github-repo-url> [disk-device]"
    echo "Example: $0 https://github.com/username/dotfiles.git /dev/sda"
    exit 1
fi

echo "========================================"
echo "NixOS Server Installation"
echo "========================================"
echo "GitHub repo: $GITHUB_REPO"
echo "Target disk: $DISK"
echo

# Detect disk if auto
if [ "$DISK" = "auto" ]; then
    echo "Auto-detecting system disk..."

    # Try to find the primary disk (prefer SSD/NVMe, exclude USB)
    if [ -e /dev/sda ]; then
        DISK=/dev/sda
    elif [ -e /dev/nvme0n1 ]; then
        DISK=/dev/nvme0n1
    else
        echo "❌ Could not auto-detect disk. Available disks:"
        lsblk -d -o NAME,SIZE,TYPE | grep disk
        exit 1
    fi

    echo "✓ Detected disk: $DISK"
fi

# Verify disk exists
if [ ! -b "$DISK" ]; then
    echo "❌ Error: Disk $DISK does not exist"
    lsblk -d
    exit 1
fi

# Show disk info and confirm
echo
echo "Disk information:"
lsblk "$DISK"
echo
echo "⚠ WARNING: This will ERASE ALL DATA on $DISK"
echo "Press Enter to continue or Ctrl+C to cancel..."
read -r

# Partition the disk
echo
echo "Partitioning $DISK..."
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK" -- set 1 esp on
parted "$DISK" -- mkpart primary linux-swap 512MiB 16GiB
parted "$DISK" -- mkpart primary ext4 16GiB 100%

# Determine partition naming
if [[ "$DISK" == /dev/nvme* ]]; then
    BOOT="${DISK}p1"
    SWAP="${DISK}p2"
    ROOT="${DISK}p3"
else
    BOOT="${DISK}1"
    SWAP="${DISK}2"
    ROOT="${DISK}3"
fi

echo "✓ Disk partitioned"
echo "  Boot: $BOOT"
echo "  Swap: $SWAP"
echo "  Root: $ROOT"

# Format partitions
echo
echo "Formatting partitions..."
mkfs.fat -F 32 -n BOOT "$BOOT"
mkswap -L swap "$SWAP"
mkfs.ext4 -L nixos "$ROOT"
echo "✓ Partitions formatted"

# Mount filesystems
echo
echo "Mounting filesystems..."
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$BOOT" /mnt/boot
swapon "$SWAP"
echo "✓ Filesystems mounted"

df -h /mnt
echo

# Clone configuration from GitHub
echo
echo "Cloning configuration from GitHub..."
cd /mnt
nix-shell -p git --run "git clone $GITHUB_REPO etc/nixos"
echo "✓ Configuration cloned"

# Generate hardware configuration
echo
echo "Generating hardware configuration..."
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/server/
echo "✓ Hardware configuration generated"

echo
echo "Generated hardware config:"
cat /mnt/etc/nixos/hosts/server/hardware-configuration.nix
echo

# Install NixOS
echo
echo "Installing NixOS..."
echo "This may take 10-30 minutes depending on internet speed..."
cd /mnt/etc/nixos
nixos-install --flake .#server --no-root-passwd

echo
echo "========================================"
echo "✓ Installation complete!"
echo "========================================"
echo
echo "The server will be accessible at:"
echo "  - ssh frerom@192.168.50.100"
echo "  - ssh frerom@server.local"
echo
echo "Next steps:"
echo "  1. Remove USB drive"
echo "  2. Reboot: 'reboot'"
echo "  3. SSH into the server and run post-installation setup"
echo
echo "Press Enter to reboot..."
read -r
reboot
