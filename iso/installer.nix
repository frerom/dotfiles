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
  services.getty.autologinUser = "root";

  # Add SSH key for root user
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFgWwucj/0VABqt2HakJhh8Bfb+amGDgOMl5uwhGkxdD roman.fredrik@gmail.com"
  ];

  # Helpful packages for installation
  environment.systemPackages = with pkgs; [
    vim
    git
    parted
    gptfdisk
  ];

  # Display IP address on login
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ]; then
      echo "==================================="
      echo "NixOS Installer Ready"
      echo "==================================="
      ip -4 addr show | grep inet
      echo "==================================="
      echo "SSH into this machine:"
      echo "  ssh root@<IP-ADDRESS>"
      echo "  Password: nixos"
      echo "==================================="
    fi
  '';
}
