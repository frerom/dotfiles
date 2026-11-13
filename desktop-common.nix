# Desktop-specific configuration
# Shared by all desktop/laptop hosts (thinkpad, office)
{ config, pkgs, ... }:

{
  # Autologin for desktop machines
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "frerom";
  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
  };

  # Enable CUPS to print documents
  services.printing.enable = true;

  # Enable sound with pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Install firefox
  programs.firefox.enable = true;

  # Keyboard remapping (Caps Lock -> Control)
  services.kanata = {
    enable = true;
    keyboards = {
      "default".config = ''
(defsrc
  caps
)

(deflayer default
  lctl
)
      '';
    };
  };

  # Desktop packages
  environment.systemPackages = with pkgs; [
    ghostty
    prusa-slicer
    kanata
    pipewire
    wireplumber
    pavucontrol
    proton-pass
    anki-bin
  ];

  # Fonts
  fonts.packages = with pkgs; [
    fira-code
    nerd-fonts.fira-code
  ];
}
