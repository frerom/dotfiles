# Server configuration for Dell OptiPlex 7060
# Headless NixOS server running Jellyfin and NAS services
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../common.nix
    ../../server-common.nix
  ];

  networking.hostName = "server";

  # Static IP configuration
  networking.useDHCP = false;
  networking.interfaces.eno1.ipv4.addresses = [{
    address = "192.168.50.100";
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.50.1";
  networking.nameservers = [ "192.168.50.1" "8.8.8.8" ];

  # mDNS for .local discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  # SSH server configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
    openFirewall = true;
  };

  # SSH authorized keys
  users.users.frerom.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFgWwucj/0VABqt2HakJhh8Bfb+amGDgOMl5uwhGkxdD roman.fredrik@gmail.com"
  ];

  # Set initial password (change with 'passwd' after first login)
  users.users.frerom.initialPassword = "nixos";

  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # Samba/SMB file sharing
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "NixOS Server";
        "netbios name" = "server";
        security = "user";
        "hosts allow" = "192.168.50. 127.0.0.1 localhost";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "bad user";
      };
      media = {
        path = "/mnt/media";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "frerom";
      };
    };
  };

  # NFS file sharing
  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/media 192.168.50.0/24(rw,sync,no_subtree_check)
    '';
  };

  # WebDAV (via nginx) - Disabled for now, will configure after installation
  # services.nginx = {
  #   enable = true;
  #   virtualHosts."server.local" = {
  #     listen = [
  #       { addr = "0.0.0.0"; port = 80; }
  #     ];
  #     locations."/webdav" = {
  #       extraConfig = ''
  #         dav_methods PUT DELETE MKCOL COPY MOVE;
  #         dav_ext_methods PROPFIND OPTIONS;
  #         dav_access user:rw group:rw all:r;
  #
  #         auth_basic "Restricted";
  #         auth_basic_user_file /etc/nginx/webdav.passwd;
  #
  #         client_max_body_size 0;
  #         create_full_put_path on;
  #
  #         alias /mnt/media/;
  #       '';
  #     };
  #   };
  # };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22    # SSH
      # 80    # HTTP (WebDAV) - Disabled for now
      139   # Samba
      445   # Samba
      2049  # NFS
      8096  # Jellyfin HTTP
      8920  # Jellyfin HTTPS
    ];
    allowedUDPPorts = [
      137   # Samba
      138   # Samba
      2049  # NFS
      5353  # mDNS
      7359  # Jellyfin discovery
      1900  # Jellyfin DLNA
    ];
  };

  # Create media directory
  systemd.tmpfiles.rules = [
    "d /mnt/media 0755 frerom users -"
  ];

  system.stateVersion = "25.05";
}
