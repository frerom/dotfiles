# Server configuration for Dell OptiPlex 7060
# Headless NixOS server running Jellyfin and NAS services
{ config, pkgs, lib, ... }:

let
  serverIP = "192.168.50.100";
  localDomain = "home.arpa";

  # Friendly names -> local port. Each name resolves (via dnsmasq) to this
  # server and nginx proxies http://<name>/ to the port.
  # Reachable as http://<name>/ and http://<name>.home.arpa/
  proxiedServices = {
    jellyfin = 8096;
    grafana = 3000;  # Grafana, see network-monitor.nix
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../common.nix
    ../../server-common.nix
    ./network-monitor.nix
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

  # No password needed - SSH key auth only
  # Set password later if console access needed: ssh frerom@server.local passwd

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

  # LAN DNS server (point the router's DHCP DNS setting at 192.168.50.100)
  services.dnsmasq = {
    enable = true;
    settings = {
      # Upstream resolvers. Deliberately NOT the router, to avoid a loop if
      # the router itself is configured to use this server.
      no-resolv = true;
      server = [ "1.1.1.1" "9.9.9.9" ];

      no-hosts = true;  # /etc/hosts maps "server" to 127.0.0.2
      domain-needed = true;
      bogus-priv = true;
      local = "/${localDomain}/";
      domain = localDomain;
      expand-hosts = true;
      cache-size = 1000;

      # "server" and each proxied service -> this machine.
      # address=/name/ip matches both "name" and "name.home.arpa".
      address = map (name: "/${name}/${serverIP}")
        ([ "server" ] ++ lib.attrNames proxiedServices)
        ++ map (name: "/${name}.${localDomain}/${serverIP}")
        ([ "server" ] ++ lib.attrNames proxiedServices);
    };
  };

  # Reverse proxy: http://<name>/ -> 127.0.0.1:<port>
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts = lib.mapAttrs (name: port: {
      serverAliases = [ "${name}.${localDomain}" ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
      };
    }) proxiedServices;
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
      53    # DNS (dnsmasq)
      80    # HTTP (nginx reverse proxy)
      139   # Samba
      445   # Samba
      2049  # NFS
      8096  # Jellyfin HTTP
      8920  # Jellyfin HTTPS
    ];
    allowedUDPPorts = [
      53    # DNS (dnsmasq)
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

  # Claude Code remote control service
  systemd.services.claude-remote-control = {
    description = "Claude Code Remote Control for Dotfiles Editing";
    documentation = [ "https://code.claude.com/docs" ];

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "frerom";
      Group = "users";
      WorkingDirectory = "/etc/nixos";

      # Start remote control in background
      ExecStart = "${pkgs.claude-code}/bin/claude --remote-control --name 'Dotfiles Server' --bg";

      # Stop the background session when service stops
      ExecStop = "${pkgs.bash}/bin/bash -c '${pkgs.claude-code}/bin/claude agents --format json | ${pkgs.jq}/bin/jq -r \".[] | select(.name == \\\"Dotfiles Server\\\") | .id\" | xargs -r ${pkgs.claude-code}/bin/claude stop'";

      # Restart on failure with faster recovery
      Restart = "on-failure";
      RestartSec = 10;

      # Ensure systemd tracks and manages all child processes
      KillMode = "mixed";

      # Environment
      Environment = [
        "PATH=/run/current-system/sw/bin:/home/frerom/.nix-profile/bin"
        "HOME=/home/frerom"
      ];
    };
  };

  # Healthcheck timer to restart claude-remote-control if the process dies
  systemd.services.claude-remote-control-healthcheck = {
    description = "Check if Claude Code Remote Control is running";
    serviceConfig = {
      Type = "oneshot";
      # Run as root so it can restart the service without sudo
      # Check if the "Dotfiles Server" session is running, restart service if not
      ExecStart = "${pkgs.bash}/bin/bash -c 'su - frerom -c \"${pkgs.claude-code}/bin/claude agents --json 2>/dev/null\" | ${pkgs.jq}/bin/jq -e ''.[] | select(.name == \"Dotfiles Server\")'' > /dev/null || ${pkgs.systemd}/bin/systemctl restart claude-remote-control.service'";
    };
  };

  systemd.timers.claude-remote-control-healthcheck = {
    description = "Timer for Claude Code Remote Control healthcheck";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "claude-remote-control-healthcheck.service";
    };
  };

  system.stateVersion = "25.05";
}
