# Server configuration for Dell OptiPlex 7060
# Headless NixOS server running Jellyfin and NAS services
{ config, pkgs, lib, ... }:

let
  serverIP = "192.168.50.100";
  localDomain = "home.arpa";

  # Public domain used for TLS. Names under it only exist in the LAN DNS
  # (dnsmasq below); the public Loopia zone only gets the temporary
  # _acme-challenge TXT records Let's Encrypt needs to issue the cert.
  tlsDomain = "frerom.se";

  # Friendly names -> local port. Each name resolves (via dnsmasq) to this
  # server and nginx proxies https://<name>.frerom.se/ to the port.
  # http://<name>/ and http://<name>.home.arpa/ redirect there.
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

  # Jellyfin media server. Only reachable through nginx (HTTPS); the
  # discovery/DLNA UDP ports are opened in the firewall section below.
  services.jellyfin = {
    enable = true;
    openFirewall = false;
  };

  # Remote access: the server advertises its own LAN IP to the tailnet, so
  # https://<name>.frerom.se (public DNS -> 192.168.50.100) works from any
  # device running Tailscale. Route must be approved once in the admin console.
  services.tailscale = {
    enable = true;
    openFirewall = true;  # UDP 41641 for direct connections
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-routes=${serverIP}/32" ];
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
      # address=/name/ip matches "name", "name.home.arpa" and
      # "name.frerom.se".
      address = lib.concatMap (name: [
        "/${name}/${serverIP}"
        "/${name}.${localDomain}/${serverIP}"
        "/${name}.${tlsDomain}/${serverIP}"
      ]) ([ "server" ] ++ lib.attrNames proxiedServices);
    };
  };

  # TLS certificate: one wildcard cert for *.frerom.se from
  # Let's Encrypt, validated via DNS-01 through the Loopia API, so nothing
  # has to be exposed to the internet. Renewed automatically.
  #
  # Needs /var/lib/secrets/loopia.env (root-only, not in git):
  #   LOOPIA_API_USER=<api user>@loopiaapi
  #   LOOPIA_API_PASSWORD=<api password>
  # The Loopia API user needs: addZoneRecord, getZoneRecords,
  # removeZoneRecord, removeSubdomain.
  # Until it exists, nginx serves a self-signed placeholder cert.
  security.acme = {
    acceptTerms = true;
    certs.${tlsDomain} = {
      domain = "*.${tlsDomain}";
      dnsProvider = "loopia";
      environmentFile = "/var/lib/secrets/loopia.env";
      group = "nginx";
    };
  };

  # Reverse proxy: https://<name>.frerom.se/ -> 127.0.0.1:<port>
  # http://<name>/ and http://<name>.home.arpa/ redirect to it.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts = lib.concatMapAttrs (name: port: {
      "${name}.${tlsDomain}" = {
        useACMEHost = tlsDomain;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
        };
        # Jellyfin image/subtitle uploads
        extraConfig = ''
          client_max_body_size 100M;
        '';
      };
      ${name} = {
        serverAliases = [ "${name}.${localDomain}" ];
        locations."/".return = "301 https://${name}.${tlsDomain}$request_uri";
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
      80    # HTTP (nginx, redirects to HTTPS)
      443   # HTTPS (nginx reverse proxy)
      139   # Samba
      445   # Samba
      2049  # NFS
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
