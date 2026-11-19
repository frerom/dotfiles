# Network monitoring: is a glitch caused by the router, the ISP, or the wider
# internet? Pings every checkpoint once per second and shows the result in
# Grafana at https://grafana.home.rekordfirman.se/ (proxied by nginx, see
# configuration.nix).
#
#   smokeping_prober  -> 1/s ICMP to router, ISP routers and public hosts
#   blackbox_exporter -> DNS + HTTPS checks every 5s
#   node_exporter     -> the server's own link (cable/NIC)
#   prometheus        -> storage + recording rules that classify the cause
#   grafana           -> phone-friendly dashboard (anonymous read-only)
{ config, pkgs, lib, ... }:

let
  # Checkpoints, ordered from closest to farthest. The ISP hops come from
  # `traceroute 1.1.1.1` (hop 2 does not answer ping). If the ISP changes
  # routing these may need updating.
  layers = {
    router = [ "192.168.50.1" ];
    isp = [ "46.227.64.64" "195.128.254.12" ];
    internet = [ "1.1.1.1" "8.8.8.8" "9.9.9.9" ];
  };

  lanInterface = "eno1";

  # Fraction of pings lost in a 15s window that counts as "a problem".
  # 0.1 = 2 lost pings, so a ~2s dropout is caught.
  lossThreshold = "0.1";

  ports = {
    grafana = 3000;
    prometheus = 9090;
    smokeping = 9374;
    blackbox = 9115;
    node = 9100;
  };

  # Cause codes. When several apply, the closest layer wins
  # (higher code = closer to the server).
  causes = [
    { code = 0; text = "OK"; color = "green"; cause = null; }
    { code = 1; text = "DNS"; color = "yellow"; cause = "dns"; }
    { code = 2; text = "Internet (beyond ISP)"; color = "purple"; cause = "internet"; }
    { code = 3; text = "ISP"; color = "orange"; cause = "isp"; }
    { code = 4; text = "Router / LAN"; color = "red"; cause = "router"; }
    { code = 5; text = "Server cable / NIC"; color = "blue"; cause = "server"; }
    { code = 6; text = "Monitor offline"; color = "text"; cause = "monitor"; }
  ];
  realCauses = lib.filter (c: c.cause != null && c.cause != "monitor") causes;

  # ---------------------------------------------------------------- rules --
  loss = layer: "max(layer:ping_loss:ratio{layer=\"${layer}\"}) >= ${lossThreshold}";

  rules = {
    groups = [{
      name = "network";
      interval = "5s";
      rules = [
        {
          record = "host:ping_loss:ratio";
          expr = ''
            clamp(1 - (
              increase(smokeping_response_duration_seconds_count[15s])
              / increase(smokeping_requests_total[15s])
            ), 0, 1)'';
        }
        {
          # Loss to *all* checkpoints of a layer (one flaky host doesn't count).
          record = "layer:ping_loss:ratio";
          expr = "min by (layer) (host:ping_loss:ratio)";
        }
        {
          record = "layer:ping_rtt:seconds";
          expr = ''
            avg by (layer) (
              increase(smokeping_response_duration_seconds_sum[15s])
              / increase(smokeping_response_duration_seconds_count[15s])
            )'';
        }
        {
          record = "network:problem:code";
          expr = ''
            (sum(absent(up{job="smokeping"} == 1)) * 0 + 6)
            or (sum(node_network_carrier{device="${lanInterface}"} == 0) * 0 + 5)
            or ((${loss "router"}) * 0 + 4)
            or (((${loss "internet"}) and on() (${loss "isp"})) * 0 + 3)
            or ((${loss "internet"}) * 0 + 2)
            or ((min(probe_success{check="dns"}) < 1) * 0 + 1)
            or vector(0)'';
        }
      ] ++ map (c: {
        # 1 while this cause is active; summed to get downtime per cause.
        record = "network:problem:active";
        expr = "network:problem:code == bool ${toString c.code}";
        labels.cause = c.cause;
      }) realCauses;
    }];
  };

  # ------------------------------------------------------------ dashboard --
  ds = { type = "prometheus"; uid = "prometheus"; };
  target = expr: legend: { datasource = ds; expr = expr; legendFormat = legend; refId = legend; };

  causeMappings = [{
    type = "value";
    options = lib.listToAttrs (map (c: {
      name = toString c.code;
      value = { text = c.text; color = c.color; index = c.code; };
    }) causes);
  }];

  lossThresholds = {
    mode = "absolute";
    steps = [
      { color = "green"; value = null; }
      { color = "yellow"; value = 0.01; }
      { color = "orange"; value = 0.1; }
      { color = "red"; value = 0.9; }
    ];
  };

  panel = id: gridPos: attrs: { inherit id gridPos; datasource = ds; } // attrs;

  dashboard = {
    uid = "network";
    title = "Network";
    tags = [ "network" ];
    timezone = "browser";
    refresh = "10s";
    time = { from = "now-6h"; to = "now"; };
    schemaVersion = 39;
    panels = [
      (panel 1 { x = 0; y = 0; w = 24; h = 4; } {
        type = "stat";
        title = "Right now";
        targets = [ (target "network:problem:code" "status") ];
        fieldConfig.defaults = { mappings = causeMappings; color.mode = "fixed"; };
        options = {
          colorMode = "background";
          graphMode = "none";
          textMode = "value";
          reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
        };
      })
      (panel 2 { x = 0; y = 4; w = 24; h = 5; } {
        type = "state-timeline";
        title = "Where is the problem?";
        description = "Closest failing layer. If your device glitched but this stays green, the problem is the device or its Wi-Fi.";
        targets = [ (target "max_over_time(network:problem:code[$__interval])" "Cause") ];
        fieldConfig.defaults = { mappings = causeMappings; color.mode = "fixed"; };
        options = { showValue = "never"; mergeValues = true; legend.showLegend = false; };
        interval = "5s";
      })
      (panel 3 { x = 0; y = 9; w = 24; h = 7; } {
        type = "state-timeline";
        title = "Packet loss per layer";
        targets = [
          (target "max_over_time(layer:ping_loss:ratio{layer=\"router\"}[$__interval])" "Router")
          (target "max_over_time(layer:ping_loss:ratio{layer=\"isp\"}[$__interval])" "ISP")
          (target "max_over_time(layer:ping_loss:ratio{layer=\"internet\"}[$__interval])" "Internet")
          (target "1 - min_over_time(min(probe_success{check=\"dns\"})[$__interval:5s])" "DNS")
        ];
        fieldConfig.defaults = {
          unit = "percentunit";
          min = 0;
          max = 1;
          thresholds = lossThresholds;
          color.mode = "thresholds";
        };
        options = { showValue = "never"; mergeValues = true; legend.showLegend = false; };
        interval = "5s";
      })
    ]
    ++ lib.imap0 (i: c: panel (10 + i) { x = 6 * i; y = 16; w = 6; h = 4; } {
      type = "stat";
      title = "${c.text} downtime";
      description = "Total time in the selected range where this was the cause.";
      targets = [ (target "sum_over_time(network:problem:active{cause=\"${c.cause}\"}[$__range]) * 5" c.cause) ];
      fieldConfig.defaults = {
        unit = "s";
        thresholds = { mode = "absolute"; steps = [ { color = "green"; value = null; } { color = c.color; value = 1; } ]; };
        color.mode = "thresholds";
      };
      options = {
        colorMode = "value";
        graphMode = "none";
        reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
      };
      interval = "5s";
    }) (lib.filter (c: lib.elem c.cause [ "router" "isp" "internet" "dns" ]) realCauses)
    ++ [
      (panel 20 { x = 0; y = 20; w = 24; h = 9; } {
        type = "timeseries";
        title = "Packet loss per checkpoint";
        targets = [ (target "max_over_time(host:ping_loss:ratio[$__interval])" "{{layer}} {{host}}") ];
        fieldConfig.defaults = {
          unit = "percentunit";
          min = 0;
          max = 1;
          custom = { drawStyle = "line"; lineWidth = 1; fillOpacity = 10; showPoints = "never"; };
        };
        options.legend = { displayMode = "list"; placement = "bottom"; };
        interval = "5s";
      })
      (panel 21 { x = 0; y = 29; w = 24; h = 9; } {
        type = "timeseries";
        title = "Latency per layer";
        targets = [ (target "max_over_time(layer:ping_rtt:seconds[$__interval])" "{{layer}}") ];
        fieldConfig.defaults = {
          unit = "s";
          min = 0;
          custom = { drawStyle = "line"; lineWidth = 1; fillOpacity = 0; showPoints = "never"; };
        };
        options.legend = { displayMode = "list"; placement = "bottom"; };
        interval = "5s";
      })
      (panel 22 { x = 0; y = 38; w = 24; h = 7; } {
        type = "timeseries";
        title = "DNS / HTTPS check time";
        targets = [ (target "probe_duration_seconds" "{{check}} {{instance}}") ];
        fieldConfig.defaults = {
          unit = "s";
          min = 0;
          custom = { drawStyle = "line"; lineWidth = 1; showPoints = "never"; };
        };
        options.legend = { displayMode = "list"; placement = "bottom"; };
      })
      (panel 23 { x = 0; y = 45; w = 24; h = 6; } {
        type = "timeseries";
        title = "Server link (${lanInterface}): carrier changes & errors";
        targets = [
          (target "increase(node_network_carrier_changes_total{device=\"${lanInterface}\"}[$__rate_interval])" "carrier changes")
          (target "increase(node_network_receive_errs_total{device=\"${lanInterface}\"}[$__rate_interval])" "rx errors")
          (target "increase(node_network_transmit_errs_total{device=\"${lanInterface}\"}[$__rate_interval])" "tx errors")
        ];
        fieldConfig.defaults = { min = 0; custom = { drawStyle = "bars"; fillOpacity = 80; }; };
        options.legend = { displayMode = "list"; placement = "bottom"; };
      })
    ];
  };

  dashboardDir = pkgs.writeTextDir "network.json" (builtins.toJSON dashboard);

  # Map ping targets to a "layer" label at scrape time.
  layerRelabel = lib.mapAttrsToList (layer: hosts: {
    source_labels = [ "host" ];
    regex = lib.concatMapStringsSep "|" lib.escapeRegex hosts;
    target_label = "layer";
    replacement = layer;
  }) layers;

  blackboxTargets = check: module: targets: {
    job_name = "blackbox-${check}";
    scrape_interval = "5s";
    scrape_timeout = "4s";
    metrics_path = "/probe";
    params.module = [ module ];
    static_configs = [{ inherit targets; labels.check = check; }];
    relabel_configs = [
      { source_labels = [ "__address__" ]; target_label = "__param_target"; }
      { source_labels = [ "__param_target" ]; target_label = "instance"; }
      { target_label = "__address__"; replacement = "127.0.0.1:${toString ports.blackbox}"; }
    ];
  };
in
{
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = ports.prometheus;
    retentionTime = "180d";
    globalConfig = {
      scrape_interval = "5s";
      evaluation_interval = "5s";
    };
    ruleFiles = [ (pkgs.writeText "network-rules.yml" (builtins.toJSON rules)) ];

    scrapeConfigs = [
      {
        job_name = "smokeping";
        static_configs = [{ targets = [ "127.0.0.1:${toString ports.smokeping}" ]; }];
        metric_relabel_configs = layerRelabel;
      }
      {
        job_name = "node";
        scrape_interval = "15s";
        static_configs = [{ targets = [ "127.0.0.1:${toString ports.node}" ]; }];
      }
      # Upstream DNS directly, and our own dnsmasq.
      (blackboxTargets "dns" "dns_a" [ "1.1.1.1" "127.0.0.1" ])
      (blackboxTargets "https" "https_2xx" [
        "https://www.google.com/generate_204"
        "https://cloudflare.com/cdn-cgi/trace"
      ])
    ];

    exporters = {
      smokeping = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = ports.smokeping;
        pingInterval = "1s";
        hosts = lib.concatLists (lib.attrValues layers);
      };

      node = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = ports.node;
      };

      blackbox = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = ports.blackbox;
        configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
          modules = {
            dns_a = {
              prober = "dns";
              timeout = "3s";
              dns = {
                query_name = "google.com";
                query_type = "A";
                transport_protocol = "udp";
                preferred_ip_protocol = "ip4";
              };
            };
            https_2xx = {
              prober = "http";
              timeout = "4s";
              http = {
                preferred_ip_protocol = "ip4";
                valid_status_codes = [ 200 204 ];
              };
            };
          };
        });
      };
    };
  };

  services.grafana = {
    enable = true;
    # Grafana 13 ships the Prometheus datasource as an external plugin.
    declarativePlugins = [ pkgs.grafanaPlugins.prometheus ];
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = ports.grafana;
        domain = "grafana.home.rekordfirman.se";
        root_url = "https://grafana.home.rekordfirman.se/";
      };
      # Generated on first start, see preStart below.
      security = {
        secret_key = "$__file{/var/lib/grafana/secret_key}";
        admin_password = "$__file{/var/lib/grafana/admin_password}";
      };
      # Read-only access without login, so the phone just opens the dashboard.
      "auth.anonymous" = {
        enabled = true;
        org_role = "Viewer";
      };
      analytics.reporting_enabled = false;
      dashboards.default_home_dashboard_path = "${dashboardDir}/network.json";
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [{
        name = "Prometheus";
        uid = "prometheus";
        type = "prometheus";
        url = "http://127.0.0.1:${toString ports.prometheus}";
        isDefault = true;
        jsonData.timeInterval = "5s";
      }];
      dashboards.settings.providers = [{
        name = "network";
        options.path = dashboardDir;
      }];
    };
  };

  # Generate Grafana secrets once (kept out of the Nix store).
  # Admin password: sudo cat /var/lib/grafana/admin_password  (user: admin)
  systemd.services.grafana.preStart = lib.mkBefore ''
    umask 077
    for f in secret_key admin_password; do
      [ -s "/var/lib/grafana/$f" ] || \
        head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' > "/var/lib/grafana/$f"
    done
  '';
}
