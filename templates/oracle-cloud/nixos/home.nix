{ config, pkgs, ... }:

{
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
}
