# Custom NixOS installer ISO with SSH auto-enabled
# Allows for completely headless installation
{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Enable SSH immediately on boot
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Set root password to "nixos" for initial SSH access
  users.users.root.password = "nixos";

  # Enable NetworkManager for easier network setup
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;

  # Auto-login to show IP address on console (if monitor connected)
  services.getty.autologinUser = lib.mkForce "root";

  # Add SSH key for root user
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFgWwucj/0VABqt2HakJhh8Bfb+amGDgOMl5uwhGkxdD roman.fredrik@gmail.com"
  ];

  # Clear the initialHashedPassword to avoid conflicts
  users.users.root.initialHashedPassword = lib.mkForce null;

  # Helpful packages for installation
  environment.systemPackages = with pkgs; [
    vim
    git
    parted
    gptfdisk
    util-linux  # for partprobe
  ];

  # Automatic installation script
  environment.etc."auto-install.sh" = {
    text = ''
      #!/usr/bin/env bash
      # Fully automatic NixOS server installation
      set -euo pipefail

      GITHUB_REPO="https://github.com/frerom/dotfiles.git"
      LOG_FILE="/var/log/auto-install.log"
      MIN_DISK_SIZE=$((150 * 1024 * 1024 * 1024))  # 150GB in bytes
      MAX_DISK_SIZE=$((350 * 1024 * 1024 * 1024))  # 350GB in bytes

      # Logging helper
      log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      }

      # Error handler
      error_exit() {
        log "ERROR: $1"
        echo ""
        echo "════════════════════════════════════════"
        echo "❌ INSTALLATION FAILED"
        echo "════════════════════════════════════════"
        echo "$1"
        echo ""
        echo "Check logs: journalctl -u auto-install"
        echo "       or: cat $LOG_FILE"
        echo ""
        echo "System will NOT power off (for debugging)"
        echo "════════════════════════════════════════"
        exit 1
      }

      log "════════════════════════════════════════"
      log "NixOS Automatic Installation Starting"
      log "════════════════════════════════════════"

      # Abort countdown
      echo ""
      echo "════════════════════════════════════════"
      echo "⚠  AUTOMATIC INSTALLATION STARTING"
      echo "════════════════════════════════════════"
      echo "This will ERASE the smallest disk found!"
      echo ""
      echo "Press Ctrl+C or power off to abort..."
      for i in {10..1}; do
        echo "Starting in $i seconds..."
        sleep 1
      done
      echo ""
      log "Countdown complete, proceeding with installation"

      # Find all block devices
      log "Detecting available disks..."
      AVAILABLE_DISKS=()

      for disk in /sys/block/*; do
        DISK_NAME=$(basename "$disk")

        # Skip loop, zram, ram, sr (CD-ROM), and other virtual devices
        if [[ "$DISK_NAME" =~ ^(loop|zram|ram|sr|dm-) ]]; then
          continue
        fi

        # Skip removable devices (USB drives)
        if [ -f "$disk/removable" ] && [ "$(cat "$disk/removable")" = "1" ]; then
          log "  Skipping removable disk: $DISK_NAME"
          continue
        fi

        # Get disk size in bytes
        DISK_SIZE=$(cat "$disk/size")
        DISK_SIZE_BYTES=$((DISK_SIZE * 512))  # sectors to bytes

        # Only consider disks within our size range
        if [ "$DISK_SIZE_BYTES" -ge "$MIN_DISK_SIZE" ] && [ "$DISK_SIZE_BYTES" -le "$MAX_DISK_SIZE" ]; then
          AVAILABLE_DISKS+=("$DISK_NAME:$DISK_SIZE_BYTES")
          log "  Found suitable disk: $DISK_NAME ($(($DISK_SIZE_BYTES / 1024 / 1024 / 1024))GB)"
        else
          log "  Skipping disk $DISK_NAME (size out of range: $(($DISK_SIZE_BYTES / 1024 / 1024 / 1024))GB)"
        fi
      done

      # Check if we found any disks
      if [ ''${#AVAILABLE_DISKS[@]} -eq 0 ]; then
        error_exit "No suitable disk found (must be 150-350GB, non-removable)"
      fi

      # Sort by size and pick the smallest
      IFS=$'\n' SORTED_DISKS=($(sort -t: -k2 -n <<< "''${AVAILABLE_DISKS[*]}"))
      unset IFS

      SELECTED_DISK=$(echo "''${SORTED_DISKS[0]}" | cut -d: -f1)
      SELECTED_SIZE=$(echo "''${SORTED_DISKS[0]}" | cut -d: -f2)

      DISK="/dev/$SELECTED_DISK"

      log "Selected disk: $DISK ($(($SELECTED_SIZE / 1024 / 1024 / 1024))GB)"

      # Verify disk exists
      if [ ! -b "$DISK" ]; then
        error_exit "Disk $DISK does not exist as block device"
      fi

      # Show disk info
      log "Disk information:"
      lsblk "$DISK" | tee -a "$LOG_FILE"

      # Partition the disk
      log "Partitioning $DISK..."
      parted "$DISK" -- mklabel gpt || error_exit "Failed to create partition table"
      parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB || error_exit "Failed to create ESP partition"
      parted "$DISK" -- set 1 esp on || error_exit "Failed to set ESP flag"
      parted "$DISK" -- mkpart primary linux-swap 512MiB 16GiB || error_exit "Failed to create swap partition"
      parted "$DISK" -- mkpart primary ext4 16GiB 100% || error_exit "Failed to create root partition"

      # Wait for kernel to recognize partitions
      sleep 2
      partprobe "$DISK" 2>/dev/null || true
      sleep 1

      # Determine partition naming
      if [[ "$DISK" == /dev/nvme* ]]; then
        BOOT="''${DISK}p1"
        SWAP="''${DISK}p2"
        ROOT="''${DISK}p3"
      else
        BOOT="''${DISK}1"
        SWAP="''${DISK}2"
        ROOT="''${DISK}3"
      fi

      log "Partitions created:"
      log "  Boot: $BOOT"
      log "  Swap: $SWAP"
      log "  Root: $ROOT"

      # Format partitions
      log "Formatting partitions..."
      mkfs.fat -F 32 -n BOOT "$BOOT" || error_exit "Failed to format boot partition"
      mkswap -L swap "$SWAP" || error_exit "Failed to format swap partition"
      mkfs.ext4 -L nixos "$ROOT" || error_exit "Failed to format root partition"
      log "Partitions formatted successfully"

      # Mount filesystems
      log "Mounting filesystems..."
      mount "$ROOT" /mnt || error_exit "Failed to mount root partition"
      mkdir -p /mnt/boot
      mount "$BOOT" /mnt/boot || error_exit "Failed to mount boot partition"
      swapon "$SWAP" || error_exit "Failed to enable swap"
      log "Filesystems mounted successfully"

      # Clone configuration from GitHub
      log "Cloning configuration from GitHub: $GITHUB_REPO"
      cd /mnt
      git clone "$GITHUB_REPO" etc/nixos || error_exit "Failed to clone repository from GitHub"
      log "Configuration cloned successfully"

      # Generate hardware configuration
      log "Generating hardware configuration..."
      nixos-generate-config --root /mnt || error_exit "Failed to generate hardware config"
      cp /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/server/ || error_exit "Failed to copy hardware config"
      log "Hardware configuration generated"

      log "Hardware configuration:"
      cat /mnt/etc/nixos/hosts/server/hardware-configuration.nix | tee -a "$LOG_FILE"

      # Install NixOS
      log "Installing NixOS (this may take 10-30 minutes)..."
      cd /mnt/etc/nixos
      nixos-install --flake .#server --no-root-passwd || error_exit "NixOS installation failed"

      log "════════════════════════════════════════"
      log "✓ INSTALLATION COMPLETE"
      log "════════════════════════════════════════"

      echo ""
      echo "════════════════════════════════════════"
      echo "✓ Installation successful!"
      echo "════════════════════════════════════════"
      echo "Server will be accessible at:"
      echo "  - ssh frerom@192.168.50.100"
      echo "  - ssh frerom@server.local"
      echo ""
      echo "SSH uses your authorized key (no password)"
      echo "Passwordless sudo enabled"
      echo ""
      echo "Powering off in 10 seconds..."
      echo "Remove USB drive before next boot."
      echo "════════════════════════════════════════"
      sleep 10

      log "Powering off system"
      systemctl poweroff --no-block
    '';
    mode = "0755";
  };

  # Automatic installation service
  systemd.services.auto-install = {
    description = "Automatic NixOS Installation";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "sshd.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "no";
      ExecStart = "/etc/auto-install.sh";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };

  # Display IP address and auto-install status on login
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ]; then
      echo "==================================="
      echo "NixOS Auto-Installer"
      echo "==================================="
      ip -4 addr show | grep inet
      echo "==================================="
      echo "Auto-installation is running..."
      echo "Check progress: journalctl -fu auto-install"
      echo ""
      echo "To abort: systemctl stop auto-install"
      echo "For manual install: systemctl disable auto-install"
      echo ""
      echo "SSH access (for debugging):"
      echo "  ssh root@<IP-ADDRESS>"
      echo "  Password: nixos"
      echo "==================================="
    fi
  '';
}
