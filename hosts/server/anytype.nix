# Self-hosted Anytype sync network, via any-sync-bundle: all official any-sync
# services (coordinator, consensus, sync node, file node) plus MongoDB and
# Redis in one container. https://github.com/grishy/any-sync-bundle
#
# Clients talk any-sync's own protocol directly (not HTTP, no nginx):
#   TCP 33010 (DRPC) and UDP 33020 (QUIC), advertised as notes.frerom.se and
#   the LAN IP, so it works on the LAN and over Tailscale.
#
# Apps join the network by importing client-config.yml, served at
#   https://notes.frerom.se/client-config.yml
#   smb://files.frerom.se/anytype/client-config.yml
#
# State (incl. the network's private keys in bundle-config.yml) lives in
# /var/lib/any-sync-bundle (root-only). Back it up only after a clean stop.
{ config, pkgs, lib, ... }:

let
  domain = "notes.frerom.se";
  dataDir = "/var/lib/any-sync-bundle";
  publicDir = "/var/lib/anytype-client-config";  # world-readable copy for nginx
  version = "1.7.0-2026-10-12";
in
{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers.any-sync-bundle = {
    image = "ghcr.io/grishy/any-sync-bundle:${version}";
    ports = [ "33010:33010" "33020:33020/udp" ];
    volumes = [ "${dataDir}:/data" ];
    environment = {
      # Only read on first start; later changes go in bundle-config.yml
      ANY_SYNC_BUNDLE_INIT_EXTERNAL_ADDRS = "${domain},192.168.50.100";
    };
    # Upstream recommends a 2 minute stop timeout so MongoDB shuts down cleanly
    extraOptions = [ "--stop-timeout=120" ];
  };

  systemd.services.podman-any-sync-bundle.serviceConfig.TimeoutStopSec = lib.mkForce 150;

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 root root -"
    "d ${publicDir} 0755 root root -"
  ];

  # Publish client-config.yml (regenerated on each start) for nginx
  systemd.paths.anytype-client-config = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = "${dataDir}/client-config.yml";
  };
  systemd.services.anytype-client-config = {
    description = "Publish Anytype client-config.yml";
    serviceConfig.Type = "oneshot";
    script = ''
      install -m 0644 ${dataDir}/client-config.yml ${publicDir}/client-config.yml
    '';
  };

  # Also offer it over SMB: smb://files.frerom.se/anytype (read-only)
  services.samba.settings.anytype = {
    path = publicDir;
    comment = "Anytype client-config.yml";
    browseable = "yes";
    "read only" = "yes";
    "guest ok" = "no";
    "valid users" = "frerom";
  };

  networking.firewall = {
    allowedTCPPorts = [ 33010 ];
    allowedUDPPorts = [ 33020 ];
  };

  services.nginx.virtualHosts.${domain} = {
    useACMEHost = "frerom.se";
    forceSSL = true;
    locations."= /client-config.yml" = {
      alias = "${publicDir}/client-config.yml";
      extraConfig = ''
        default_type application/x-yaml;
        add_header Content-Disposition 'attachment; filename="client-config.yml"';
      '';
    };
    locations."/".return = ''200 "Anytype self-hosted sync network. To join, choose a self-hosted network in the Anytype app and import https://${domain}/client-config.yml\n"'';
    locations."/".extraConfig = "default_type text/plain;";
  };
}
