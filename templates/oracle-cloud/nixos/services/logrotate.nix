{ config, ... }:

{
  services.logrotate = {
    enable = true;
    settings."daily-progress" = {
      files = "/home/opc/daily-progress-bot/cron.log";
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      copytruncate = true;
      create = "0600 opc opc";
      olddir = "/var/log/daily-progress";
      dateext = true;
      dateformat = "-%Y%m%d";
      su = "opc opc";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/daily-progress 0750 opc opc -"
  ];
}
