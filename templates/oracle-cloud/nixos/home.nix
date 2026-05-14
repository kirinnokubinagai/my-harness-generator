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
    '';
  };

  # fzf — fuzzy finder with Ctrl-R history search and Ctrl-T file finder.
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

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
