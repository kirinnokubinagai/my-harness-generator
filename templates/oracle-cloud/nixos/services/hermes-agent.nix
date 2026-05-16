{ config, pkgs, lib, ... }:

# Hermes Agent — NousResearch personal AI gateway (Discord + Voice).
#
# 7.29.3: Replaced the 7.25.0/7.26.0 `curl install.sh | bash` + `pip install`
# deploy pattern with a Nix-managed buildFHSEnv derivation
# (pkgs/hermes-agent-fhs.nix). This is step 4 of 4 in the Nix-pure migration.
#
# Approach B (buildFHSEnv hybrid) was chosen because:
#   - Hermes is NOT on PyPI; it installs via git clone + uv (editable install).
#   - 3 deps absent from nixpkgs 25.05: exa-py, parallel-web, fal-client.
#   - Date-based versioning (new tag every ~7 days) makes per-dep packaging
#     maintenance-heavy — Approach A (full buildPythonApplication) would require
#     packaging those deps as sibling derivations and keeping them current.
#   - buildFHSEnv provides a reproducible Nix-managed environment with all
#     in-nixpkgs Python deps pre-seeded; uv handles only the 3 missing packages
#     plus the editable hermes install into /var/lib/hermes/ on first start.
#
# State layout:
#   /var/lib/hermes/hermes-agent/   — git checkout (tag v2026.5.7)
#   /var/lib/hermes/venv/           — uv-managed Python 3.11 venv
#   /home/opc/hermes-agent/         — user config (config.yaml, .env, data/)
#     config.yaml                   — written by setup-oci-vm-nixos.sh via scp
#     .env                          — secrets (EnvironmentFile); chmod 600
#     data/                         — runtime data / model cache
#
# STT: local Whisper Tiny (~75 MB on first use via faster-whisper / HuggingFace).
# TTS: edge-tts (free, no local model download — uses Microsoft Edge TTS API).
# NeuTTS (local TTS) removed from this deployment: not in nixpkgs and the
# headless VM gateway does not require local synthesis (Discord voice channel
# audio is synthesised client-side or via edge-tts).

let
  hermes-env = pkgs.callPackage ./../pkgs/hermes-agent-fhs.nix { };
in {
  # Inert unless harness.hermesAgentEnabled = true (set by
  # setup-oci-vm-nixos.sh's harness-overlay when HERMES_AGENT_ENABLED=yes).
  # Imported unconditionally by configuration.nix; mkIf is the correct
  # NixOS conditional-module pattern (avoids the imports-vs-config
  # infinite recursion that lib.optional config.X would cause).
  config = lib.mkIf config.harness.hermesAgentEnabled {
  # Persistent state directory for Hermes's git checkout and venv.
  # These must survive nixos-rebuild switch (hence StateDirectory, not tmpfiles).
  systemd.tmpfiles.rules = [
    "d /var/lib/hermes              0750 opc opc -"
    "d /home/opc/hermes-agent       0750 opc opc -"
    "d /home/opc/hermes-agent/data  0750 opc opc -"
  ];

  systemd.services.hermes-agent = {
    description = "Hermes Agent — NousResearch personal AI gateway (Discord + voice)";
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type            = "simple";
      User            = "opc";
      Group           = "opc";
      WorkingDirectory = "/home/opc/hermes-agent";

      # EnvironmentFile holds DISCORD_BOT_TOKEN, OPENAI_MODEL, OPENAI_BASE_URL,
      # OPENROUTER_API_KEY, ANTHROPIC_API_KEY, etc.
      # Written by setup-oci-vm-nixos.sh with chmod 600.
      EnvironmentFile = "/home/opc/hermes-agent/.env";

      # The FHS env wrapper handles:
      #   1. First-run git clone of hermes-agent at v2026.5.7 into /var/lib/hermes/
      #   2. uv pip install --editable .[messaging,voice] into /var/lib/hermes/venv/
      #   3. PYTHONPATH seeding with in-nixpkgs deps (openai, anthropic, faster-whisper, etc.)
      #   4. hermes gateway start --foreground
      # Subsequent starts skip steps 1-2 (idempotent check on venv/bin/hermes).
      ExecStart = "${hermes-env}/bin/hermes-agent-env";

      Restart          = "on-failure";
      RestartSec       = "30s";
      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "hermes-agent";

      # First-run: git clone + uv pip install + Whisper Tiny download (~75 MB).
      # Allow 15 min on a cold ARM64 VM with a slow connection.
      TimeoutStartSec  = "15min";

      # State directory persists across nixos-rebuild switch (Nix manages /nix/store;
      # the venv at /var/lib/hermes/ is mutable runtime state, like model weights).
      ReadWritePaths   = [ "/var/lib/hermes" "/home/opc/hermes-agent" ];
    };
  };
  };  # end config = lib.mkIf config.harness.hermesAgentEnabled
}
