{ config, pkgs, lib, ... }:

# OpenClaw — open-source self-hosted AI gateway (Discord + voice).
# Mutually exclusive with hermes-agent: exactly one of
# harness.hermesAgentEnabled or harness.openClawEnabled may be true.
#
# 7.30.0: OpenClaw integration (Hermes alternative).
#
# Packaging approach: buildNpmPackage (Approach npm — preferred).
#   OpenClaw is published to npm as `openclaw` (Node 24 recommended).
#   Unlike Hermes (git-only Python), it ships a self-contained npm tarball.
#   buildNpmPackage gives a fully reproducible Nix closure with atomic rollback.
#   No runtime git clone or pip install — the binary is in the Nix store.
#
# Config layout:
#   ~/.openclaw/openclaw.json    — written by setup-oci-vm-nixos.sh via scp
#                                  (rendered from templates/oracle-cloud/openclaw/config.example.yaml
#                                  at deploy time — placeholders substituted from
#                                  .my-harness/.openclaw-config.json)
#   /home/opc/openclaw/.env     — secrets (EnvironmentFile); chmod 600
#                                  written by setup-oci-vm-nixos.sh OPENCLAW_ENABLED branch
#
# Voice: ElevenLabs TTS (if API key provided) or system TTS fallback.
#        STT: built-in OpenClaw transcription (no local Whisper install required).
#        Voice mode uses macOS/iOS wake words on client side; the OCI VM gateway
#        receives audio over Discord's API (headless-compatible).
#
# Cron / daily-report:
#   openclaw cron add \
#     --name daily-report \
#     --cron "0 9 * * *" \
#     --session session:daily-report-<repo> \
#     --message "<prompt content>" \
#     --announce
#   The register-agent-daily-report.sh openclaw branch uses this command.

let
  openclaw-pkg = pkgs.callPackage ./../pkgs/openclaw.nix { };
in {
  # Config directory for openclaw (~/.openclaw/ convention).
  systemd.tmpfiles.rules = [
    "d /home/opc/.openclaw          0750 opc opc -"
    "d /home/opc/openclaw           0750 opc opc -"
    "d /home/opc/openclaw/prompts   0750 opc opc -"
  ];

  systemd.services.openclaw = {
    description = "OpenClaw — open-source self-hosted AI gateway (Discord + voice)";
    after    = [ "network-online.target" "cliproxyapi.service" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type            = "simple";
      User            = "opc";
      Group           = "opc";
      WorkingDirectory = "/home/opc/openclaw";

      # EnvironmentFile holds DISCORD_BOT_TOKEN, OPENCLAW_AI_PROVIDER,
      # OPENROUTER_API_KEY, ANTHROPIC_API_KEY, ELEVENLABS_API_KEY, etc.
      # Written by setup-oci-vm-nixos.sh with chmod 600.
      EnvironmentFile = "/home/opc/openclaw/.env";

      # openclaw gateway start reads ~/.openclaw/openclaw.json automatically.
      # The config file path can also be overridden with --config <path>.
      ExecStart = "${openclaw-pkg}/bin/openclaw gateway start --foreground";

      Restart          = "on-failure";
      RestartSec       = "30s";
      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "openclaw";

      # Allow time for first startup and any initial auth/config validation.
      TimeoutStartSec  = "5min";

      ReadWritePaths   = [ "/home/opc/.openclaw" "/home/opc/openclaw" ];
    };
  };
}
