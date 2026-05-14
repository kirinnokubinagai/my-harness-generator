{ config, pkgs, lib, ... }:

let
  hermesEnabled = config.harness.hermesAgentEnabled or false;
in {
  options.harness.hermesAgentEnabled = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      When true, daily-progress.timer and event-watch.timer stay disabled
      because Hermes Agent's internal cron (session daily-report-<repo>,
      registered by register-agent-daily-report.sh) handles the daily report
      instead. The .sh scripts remain on disk for emergency manual invocation.
      Set to true by setup-oci-vm-nixos.sh when HERMES_AGENT_ENABLED=yes.
    '';
  };

  config = {
    # daily-progress.sh — once a day at 09:00 UTC (= 18:00 JST)
    systemd.services.daily-progress = {
      description = "Daily progress summary (GitHub → notification service)";
      serviceConfig = {
        Type = "oneshot";
        User = "opc";
        Group = "opc";
        WorkingDirectory = "/home/opc/daily-progress-bot";
        ExecStart = "/home/opc/daily-progress-bot/daily-progress.sh";
        # Keep writing to cron.log (preserves the 7.23.0 logrotate contract).
        StandardOutput = "append:/home/opc/daily-progress-bot/cron.log";
        StandardError = "append:/home/opc/daily-progress-bot/cron.log";
        # daily-progress.sh reads .env from $WorkingDirectory directly.
      };
    };

    systemd.timers.daily-progress = {
      enable = !hermesEnabled;
      description = "Run daily-progress.sh daily at 09:00 UTC (= 18:00 JST)";
      wantedBy = lib.mkIf (!hermesEnabled) [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 09:00:00 UTC";
        Persistent = true;
      };
    };

    # event-watch.sh — every hour
    systemd.services.event-watch = {
      description = "Hourly GitHub event watch";
      serviceConfig = {
        Type = "oneshot";
        User = "opc";
        Group = "opc";
        WorkingDirectory = "/home/opc/daily-progress-bot";
        ExecStart = "/home/opc/daily-progress-bot/event-watch.sh";
        StandardOutput = "append:/home/opc/daily-progress-bot/cron.log";
        StandardError = "append:/home/opc/daily-progress-bot/cron.log";
      };
    };

    systemd.timers.event-watch = {
      enable = !hermesEnabled;
      description = "Run event-watch.sh every hour";
      wantedBy = lib.mkIf (!hermesEnabled) [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };
  };
}
