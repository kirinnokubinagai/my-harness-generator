{ config, pkgs, lib, ... }:

{
  # fail2ban — SSH brute-force protection. Primary defense when Tailscale
  # is OFF (SSH still on 0.0.0.0/0). When Tailscale is ON and SSH port 22
  # is closed at the OCI Security List, fail2ban is harmless belt-and-braces.
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      multipliers = "2 4 8 16 32 64";
      maxtime = "168h";  # 1 week cap
    };
    jails.sshd.settings = {
      enabled = true;
      port = "22";
      filter = "sshd";
      maxretry = 3;
    };
  };

  # Automatic security updates. allowReboot=false — never auto-reboot a
  # headless VM running the daily-progress bot / Hermes; surface kernel
  # updates that need a reboot in the journal instead. flake-based so it
  # pulls the pinned nixpkgs the harness flake tracks.
  system.autoUpgrade = {
    enable = true;
    dates = "weekly";
    allowReboot = false;
    flags = [ "--update-input" "nixpkgs" "--no-write-lock-file" ];
  };

  # Extra SSH hardening on top of configuration.nix's
  # PasswordAuthentication=false / PermitRootLogin=no.
  services.openssh.settings = {
    MaxAuthTries = 3;
    LoginGraceTime = 20;
    KbdInteractiveAuthentication = false;
    ClientAliveInterval = 300;
    ClientAliveCountMax = 2;
    AllowTcpForwarding = "no";
    X11Forwarding = false;
    AllowAgentForwarding = "no";
  };

  # sudo: keep NOPASSWD (setup scripts depend on it) but restrict sudo to
  # the wheel group only — no other group/user can escalate even if added.
  security.sudo.execWheelOnly = true;

  # Kernel / sysctl hardening — conservative, won't break the bot.
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
  };
}
