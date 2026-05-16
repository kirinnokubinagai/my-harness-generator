{ config, pkgs, lib, ... }:

# OpenClaw — open-source self-hosted AI gateway (Discord + voice).
# Mutually exclusive with hermes-agent: exactly one of
# harness.hermesAgentEnabled or harness.openClawEnabled may be true.
#
# 7.30.0: OpenClaw integration (Hermes alternative).
# 7.33.0: Migrated from the self-built buildNpmPackage derivation
# (pkgs/openclaw.nix — deleted) to numtide/llm-agents.nix
# (pkgs.llm-agents.openclaw). binary-cache hit, daily auto-updated
# upstream, meta.mainProgram = "openclaw" (binary name unchanged).
# No more lib.fakeHash npmDepsHash placeholder to maintain.
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

{
  # Inert unless harness.openClawEnabled = true. Imported unconditionally
  # by configuration.nix; mkIf is the correct NixOS conditional pattern.
  config = lib.mkIf config.harness.openClawEnabled {
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

      # numtide binary (binary-cache hit). openclaw gateway start reads
      # ~/.openclaw/openclaw.json automatically; --config <path> overrides.
      ExecStart = "${lib.getExe pkgs.llm-agents.openclaw} gateway start --foreground";

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
  };  # end config = lib.mkIf config.harness.openClawEnabled
}
