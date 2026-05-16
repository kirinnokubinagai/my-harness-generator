{ config, pkgs, lib, ... }:

# OCI billing guard (7.34.0) — a systemd timer that polls the OCI Budget's
# actual-spend via Instance Principal and, the moment OCI reports ANY charge
# beyond Always Free, posts to the existing notification webhook
# (post-notification.sh: discord / slack / teams — the same webhook the
# daily-progress bot already uses).
#
# ── HONEST LATENCY (read this before assuming "instant") ──────────────────
# OCI billing data updates on a ~24h cycle. Budgets are evaluated roughly
# daily; the Usage API is officially unsupported on non-metered (Always Free)
# tenancies. Polling more frequently does NOT help — the upstream number does
# not move faster. ~24h is OCI's structural floor, not a defect in this code.
# The OCI Budget *email* alert created by ensure-oci-billing-alert.sh is a
# deliberate, VM-independent backup: if this script or the whole VM dies
# silently, the email path still fires (it lives entirely in OCI).
#
# Inert unless harness.billingCheckEnabled = true. setup-oci-vm-nixos.sh sets
# it via the harness-overlay when BILLING_ALERT_MODE is `chat` or `both`.
# Imported unconditionally by configuration.nix; mkIf is the correct
# conditional-module pattern (the imports-vs-config recursion fixed in
# 7.32.0.1 applies here too).

{
  config = lib.mkIf config.harness.billingCheckEnabled {
    # Per-month de-dupe sentinel lives here (one alert/month, not one/day).
    systemd.tmpfiles.rules = [
      "d /home/opc/daily-progress-bot/state 0750 opc opc -"
    ];

    systemd.services.billing-check = {
      description = "OCI billing guard — alert chat webhook on any charge beyond Always Free";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # oci CLI (instance principal), jq + curl (post-notification.sh),
      # bc (float compare), coreutils (date/mkdir).
      path = [ pkgs.oci-cli pkgs.jq pkgs.curl pkgs.bc pkgs.coreutils ];

      serviceConfig = {
        Type             = "oneshot";
        User             = "opc";
        Group            = "opc";
        WorkingDirectory = "/home/opc/daily-progress-bot";
        # NOTIFICATION_SERVICE / NOTIFICATION_WEBHOOK_URL / BILLING_BUDGET_OCID
        # are written into this .env by setup-oci-vm-nixos.sh.
        EnvironmentFile  = "/home/opc/daily-progress-bot/.env";
        # No ~/.oci/config on the VM — auth is the instance's own principal.
        Environment      = "OCI_CLI_AUTH=instance_principal";
        ExecStart        = "${pkgs.bash}/bin/bash /home/opc/daily-progress-bot/billing-check.sh";
        StandardOutput   = "journal";
        StandardError    = "journal";
        SyslogIdentifier = "billing-check";
      };
    };

    systemd.timers.billing-check = {
      description = "Daily OCI billing guard poll (OCI data lags ~24h regardless)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar         = "*-*-* 09:15:00";
        Persistent         = true;
        RandomizedDelaySec = "300";
      };
    };
  };
}
