{ config, pkgs, lib, ... }:

{
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
    acceleration = null;  # A1.Flex has no GPU
  };

  # Pull gemma4:e4b once Ollama is up. Idempotent — re-runs are no-ops.
  systemd.services.ollama-pull-gemma4 = {
    description = "Pull gemma4:e4b after Ollama daemon comes up";
    after = [ "ollama.service" ];
    requires = [ "ollama.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 10";
      ExecStart = "${pkgs.ollama}/bin/ollama pull gemma4:e4b";
      RemainAfterExit = true;
      TimeoutStartSec = "30min";  # ~5 GB download
    };
  };
}
