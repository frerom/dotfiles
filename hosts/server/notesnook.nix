# Self-hosted Notesnook sync server, mirroring upstream's docker-compose:
# https://github.com/streetwriters/notesnook-sync-server
#
# Containers (podman) on a private "notesnook" network; only the four
# public services are published, on 127.0.0.1, behind nginx (see
# proxiedServices in configuration.nix):
#   https://notes.frerom.se         sync API        -> 5264
#   https://notes-auth.frerom.se    identity server -> 8264
#   https://notes-events.frerom.se  SSE server      -> 7264
#   https://notes-files.frerom.se   S3 attachments  -> 9000
#   https://notes-monograph.frerom.se  published notes -> 6264
#
# Secrets live in /var/lib/secrets/notesnook.env (root-only, not in git):
#   NOTESNOOK_API_SECRET=<random, >32 chars>
#   MINIO_ROOT_USER=<user>          S3_ACCESS_KEY_ID=<same user>
#   MINIO_ROOT_PASSWORD=<password>  S3_ACCESS_KEY=<same password>
#
# No SMTP is configured: email 2FA and password-reset mails don't work, so
# switch 2FA to an authenticator app after signing up.
{ config, pkgs, lib, ... }:

let
  domain = "frerom.se";
  secrets = "/var/lib/secrets/notesnook.env";
  network = "notesnook";
  subnet = "10.89.0.0/24";
  gateway = "10.89.0.1";

  # Shared settings for the Notesnook services (x-server-discovery upstream)
  common = {
    INSTANCE_NAME = "frerom";
    DISABLE_SIGNUPS = "false";
    SELF_HOSTED = "1";
    NOTESNOOK_SERVER_HOST = "notesnook-server";
    NOTESNOOK_SERVER_PORT = "5264";
    IDENTITY_SERVER_HOST = "identity-server";
    IDENTITY_SERVER_PORT = "8264";
    SSE_SERVER_HOST = "sse-server";
    SSE_SERVER_PORT = "7264";
    AUTH_SERVER_PUBLIC_URL = "https://notes-auth.${domain}";
    IDENTITY_SERVER_URL = "https://notes-auth.${domain}";
    NOTESNOOK_API_PUBLIC_URL = "https://notes.${domain}";
    ATTACHMENTS_SERVER_PUBLIC_URL = "https://notes-files.${domain}";
    NOTESNOOK_APP_PUBLIC_URL = "https://app.notesnook.com";
    NOTESNOOK_APP_HOST = "https://app.notesnook.com";
    MONOGRAPH_PUBLIC_URL = "https://notes-monograph.${domain}";
    # nginx's connections arrive via the podman bridge gateway; trusting it
    # makes the servers honour X-Forwarded-Proto and advertise https URLs.
    KNOWN_PROXIES = gateway;
  };

  container = { image, port ? null, containerPort ? port, environment ? { }, cmd ? [ ], deps ? [ ], extraOptions ? [ ], volumes ? [ ] }: {
    inherit image environment cmd volumes;
    environmentFiles = [ secrets ];
    ports = lib.optional (port != null) "127.0.0.1:${toString port}:${toString containerPort}";
    dependsOn = deps;
    extraOptions = [ "--network=${network}" ] ++ extraOptions;
  };
in
{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers = {
    notesnook-db = container {
      image = "docker.io/library/mongo:7.0.12";
      cmd = [ "--replSet" "rs0" "--bind_ip_all" ];
      volumes = [ "notesnook-db:/data/db" ];
      extraOptions = [
        "--hostname=notesnook-db"
        # Same as upstream: initialise the single-node replica set on first run
        "--health-cmd=echo 'try { rs.status() } catch (err) { rs.initiate() }; db.runCommand(\"ping\").ok' | mongosh mongodb://localhost:27017 --quiet"
        "--health-interval=40s"
        "--health-start-period=60s"
      ];
    };

    notesnook-s3 = container {
      image = "docker.io/pgsty/silo:RELEASE.2026-09-16T00-00-00Z";
      port = 9000;
      cmd = [ "server" "/data/s3" "--console-address" ":9090" ];
      volumes = [ "notesnook-s3:/data/s3" ];
      environment.MINIO_BROWSER = "off";
    };

    identity-server = container {
      image = "docker.io/streetwriters/identity:latest";
      port = 8264;
      deps = [ "notesnook-db" ];
      environment = common // {
        MONGODB_CONNECTION_STRING = "mongodb://notesnook-db:27017/identity?replSet=rs0";
        MONGODB_DATABASE_NAME = "identity";
      };
    };

    notesnook-server = container {
      image = "docker.io/streetwriters/notesnook-sync:latest";
      port = 5264;
      deps = [ "notesnook-db" "notesnook-s3" "identity-server" ];
      environment = common // {
        MONGODB_CONNECTION_STRING = "mongodb://notesnook-db:27017/?replSet=rs0";
        MONGODB_DATABASE_NAME = "notesnook";
        S3_INTERNAL_SERVICE_URL = "http://notesnook-s3:9000";
        S3_INTERNAL_BUCKET_NAME = "attachments";
        S3_SERVICE_URL = "https://notes-files.${domain}";
        S3_REGION = "us-east-1";
        S3_BUCKET_NAME = "attachments";
      };
    };

    sse-server = container {
      image = "docker.io/streetwriters/sse:latest";
      port = 7264;
      deps = [ "identity-server" "notesnook-server" ];
      environment = common;
    };

    # Public note publishing ("Monograph")
    monograph-server = container {
      image = "docker.io/streetwriters/monograph:latest";
      port = 6264;
      containerPort = 3000;
      deps = [ "notesnook-server" ];
      environment = common // {
        NODE_ENV = "production";
        HOST = "0.0.0.0";
        API_HOST = "https://notes.${domain}";
        PUBLIC_URL = "https://notes-monograph.${domain}";
      };
    };
  };

  # Every container needs the network to exist first
  systemd.services = lib.genAttrs
    (map (n: "podman-${n}") (lib.attrNames config.virtualisation.oci-containers.containers))
    (_: {
      requires = [ "podman-network-notesnook.service" ];
      after = [ "podman-network-notesnook.service" ];
    })
  // {
    # Private network with DNS, so containers find each other by name
    podman-network-notesnook = {
      description = "Podman network for Notesnook";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ pkgs.podman ];
      # Fixed subnet, so the gateway in KNOWN_PROXIES stays correct
      script = "podman network exists ${network} || podman network create --subnet=${subnet} --gateway=${gateway} ${network}";
    };

    # Create the attachments bucket (setup-s3 upstream). Idempotent.
    notesnook-setup-s3 = {
      description = "Create Notesnook attachments bucket";
      wantedBy = [ "multi-user.target" ];
      requires = [ "podman-notesnook-s3.service" ];
      after = [ "podman-notesnook-s3.service" ];
      before = [ "podman-notesnook-server.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ pkgs.podman ];
      script = ''
        podman run --rm --network=${network} --env-file=${secrets} \
          --entrypoint=/bin/bash docker.io/pgsty/mc:RELEASE.2026-09-13T00-00-00Z -c '
            for i in $(seq 60); do
              mc alias set silo http://notesnook-s3:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" && break
              sleep 1
            done
            mc mb silo/attachments -p'
      '';
    };
  };

  # nginx tweaks on top of the generic proxiedServices vhosts
  services.nginx.virtualHosts = {
    # Server-sent events: no buffering, long-lived connections
    "notes-events.${domain}".locations."/".extraConfig = ''
      proxy_buffering off;
      proxy_cache off;
      proxy_read_timeout 1d;
    '';
    # Attachments can be large; stream them straight through
    "notes-files.${domain}".locations."/".extraConfig = ''
      client_max_body_size 1G;
      proxy_request_buffering off;
    '';
  };
}
