# Shared configuration for ALL hosts (desktop and server)
# Only truly common settings should be here
{ config, pkgs, ... }:

{
  # Nix configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Timezone and locale
  time.timeZone = "Europe/Stockholm";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "sv_SE.UTF-8";
    LC_IDENTIFICATION = "sv_SE.UTF-8";
    LC_MEASUREMENT = "sv_SE.UTF-8";
    LC_MONETARY = "sv_SE.UTF-8";
    LC_NAME = "sv_SE.UTF-8";
    LC_NUMERIC = "sv_SE.UTF-8";
    LC_PAPER = "sv_SE.UTF-8";
    LC_TELEPHONE = "sv_SE.UTF-8";
    LC_TIME = "sv_SE.UTF-8";
  };

  # User definition
  users.users.frerom = {
    isNormalUser = true;
    description = "Fredrik";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  # Bootloader (UEFI on all systems)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # NetworkManager for all hosts
  networking.networkmanager.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Minimal base packages for all systems
  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  system.stateVersion = "25.05";
}
