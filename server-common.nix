# Server-specific base configuration
# Minimal configuration shared by all headless servers
{ config, pkgs, ... }:

{
  # Server packages (minimal)
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
    rsync
  ];

  # No desktop services
  # No audio services
  # No autologin
}
