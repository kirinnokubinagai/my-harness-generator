{ config, pkgs, ... }:

let
  botSrc = ../daily-progress-bot;
in {
  home.stateVersion = "25.05";
  home.username = "opc";
  home.homeDirectory = "/home/opc";

  home.packages = [ ];

  programs.bash = {
    enable = true;
    bashrcExtra = ''
      # Path for claude / codex CLI installed via `npm install -g`
      # under $HOME/.npm-global (set by setup-oci-vm-nixos.sh post-install).
      export PATH="$HOME/.npm-global/bin:$PATH"

      # daily-progress-bot scripts dir on PATH so the timer commands
      # work without absolute paths.
      [ -d "$HOME/daily-progress-bot" ] && export PATH="$PATH:$HOME/daily-progress-bot"

      # ghq: every `ghq get` clones under ~/ghq/github.com/<owner>/<repo>.
      # Keeps interactive-SSH clones consistent with the Hermes systemd
      # checkout layout (which uses GHQ_ROOT=/var/lib/hermes/ghq).
      export GHQ_ROOT="$HOME/ghq"
    '';
  };

  # fzf — fuzzy finder with Ctrl-R history search and Ctrl-T file finder.
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

  # ghq — repo manager. home-manager 25.05 has NO programs.ghq module,
  # so configuration is just: (1) the ghq binary (in configuration.nix
  # environment.systemPackages since 7.29.1) + (2) GHQ_ROOT exported in
  # bashrcExtra above. `ghq get <url>` then clones into
  # ~/ghq/github.com/<owner>/<repo> — no scattered ad-hoc git clones.

  # Daily-progress bot scripts placed declaratively (read-only symlinks
  # into the Nix store). The .env file (secrets) is NOT here — it is
  # written by setup-oci-vm-nixos.sh on first deploy and is mutable.
  home.file = {
    "daily-progress-bot/daily-progress.sh" = {
      source = "${botSrc}/daily-progress.sh";
      executable = true;
    };
    "daily-progress-bot/event-watch.sh" = {
      source = "${botSrc}/event-watch.sh";
      executable = true;
    };
    "daily-progress-bot/lib/ai-provider.sh".source = "${botSrc}/lib/ai-provider.sh";
    "daily-progress-bot/lib/post-notification.sh".source = "${botSrc}/lib/post-notification.sh";
    "daily-progress-bot/crontab.example".source = "${botSrc}/crontab.example";
    "daily-progress-bot/logrotate.conf".source = "${botSrc}/logrotate.conf";
    # README.md and .env.example intentionally NOT placed — they are
    # docs/templates only relevant on the dev machine.
  };
}
