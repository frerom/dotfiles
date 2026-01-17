# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../common.nix
    ];

  networking.hostName = "thinkpad"; # Define your hostname.
  
  boot.initrd.luks.devices."luks-2bfde333-e8e5-401e-92f8-b3b235565315".device = "/dev/disk/by-uuid/2bfde333-e8e5-401e-92f8-b3b235565315";


  system.stateVersion = "25.05";
}
