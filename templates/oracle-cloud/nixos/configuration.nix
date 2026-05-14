{ config, pkgs, lib, ... }:

let
  claude-code  = pkgs.callPackage ./pkgs/claude-code.nix { };   # added 7.29.2
  openai-codex = pkgs.callPackage ./pkgs/openai-codex.nix { };  # added 7.29.2
in
{
  imports = [
    ./services/daily-progress.nix
    ./services/logrotate.nix
    # cliproxyapi.nix is conditionally injected by setup-oci-vm-nixos.sh when
    # HERMES_AI_PROVIDER ∈ {codex, claude-code}. Not listed here statically so
    # the base config evaluates cleanly without it.
  ];

  system.stateVersion = "25.05";

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking = {
    hostName = "harness-daily-progress";
    useDHCP = lib.mkForce true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  users.users.opc = {
    isNormalUser = true;
    description = "Oracle Cloud default user";
    extraGroups = [ "wheel" ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keyFiles = [
      "/etc/ssh/authorized_keys.d/opc"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
  };

  environment.systemPackages = with pkgs; [
    curl jq gh git tmux htop vim ripgrep
    nodejs_20  # runtime dependency for claude / codex (and ad-hoc npm use)
    fzf        # fuzzy finder (history, files, branches)
    ghq        # GitHub repo manager (ghq get owner/repo)
  ] ++ [
    claude-code   # Anthropic Claude Code CLI — buildNpmPackage derivation (added 7.29.2)
    openai-codex  # OpenAI Codex CLI        — buildNpmPackage derivation (added 7.29.2)
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.opc = import ./home.nix;
  };
}
