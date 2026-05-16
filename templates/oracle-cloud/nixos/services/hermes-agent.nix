{ config, pkgs, lib, ... }:

# Hermes Agent — NousResearch personal AI gateway (Discord + Voice).
#
# 7.33.0: Replaced the 7.29.3 buildFHSEnv hybrid (pkgs/hermes-agent-fhs.nix —
# deleted) with numtide/llm-agents.nix (pkgs.llm-agents.hermes-agent).
#
# This is the single biggest win of the numtide migration. The old FHS
# launcher had to, on every first start: ghq-clone hermes-agent at a pinned
# tag, `uv venv` + `uv pip install --editable .[messaging,voice]`, and seed
# PYTHONPATH with ~25 hand-listed nixpkgs Python deps (because Hermes is not
# on PyPI and 3 deps — exa-py, parallel-web, fal-client — are absent from
# nixpkgs 25.05). numtide packages all of that as a binary-cache hit, daily
# auto-updated upstream, with meta.mainProgram = "hermes". No git clone, no
# uv, no venv, no PYTHONPATH surgery, no lib.fakeHash to maintain.
#
# What the launcher did that systemd still must do:
#   The numtide binary has NO wrapper, so Hermes uses its own default config
#   discovery (~/.hermes/config.yaml). setup-oci-vm-nixos.sh scps the rendered
#   config to /home/opc/hermes-agent/config.yaml, so ExecStartPre symlinks it
#   into ~/.hermes/ exactly as the old launcher did (idempotent). The
#   `hermes gateway start --foreground` subcommand is unchanged (it is a
#   Hermes-native subcommand, not a launcher invention).
#
# State layout (post-7.33.0):
#   /home/opc/.hermes/config.yaml   — symlink → ../hermes-agent/config.yaml
#   /home/opc/hermes-agent/         — user config + runtime data
#     config.yaml                   — written by setup-oci-vm-nixos.sh via scp
#     .env                          — secrets (EnvironmentFile); chmod 600
#     data/                         — runtime data / model cache
#   (/var/lib/hermes is GONE — there is no git checkout or venv to persist.)
#
# STT: local Whisper Tiny (~75 MB lazily fetched on first voice use via
#      faster-whisper / HuggingFace; not on service start).
# TTS: edge-tts (free Microsoft Edge TTS API — no local model download).

let
  hermesConfigLink = pkgs.writeShellScript "hermes-config-link" ''
    set -eu
    # Hermes (numtide binary, no launcher) reads ~/.hermes/config.yaml by
    # default. setup-oci-vm-nixos.sh writes the rendered config to
    # /home/opc/hermes-agent/config.yaml; mirror it into ~/.hermes/.
    # Absolute paths (not $HOME) so behaviour is independent of systemd's
    # environment — same robustness choice the old FHS launcher made.
    mkdir -p /home/opc/.hermes
    if [ -f /home/opc/hermes-agent/config.yaml ] && [ ! -e /home/opc/.hermes/config.yaml ]; then
      ln -sf /home/opc/hermes-agent/config.yaml /home/opc/.hermes/config.yaml
    fi
  '';
in {
  # Inert unless harness.hermesAgentEnabled = true (set by
  # setup-oci-vm-nixos.sh's harness-overlay when HERMES_AGENT_ENABLED=yes).
  # Imported unconditionally by configuration.nix; mkIf is the correct
  # NixOS conditional-module pattern (avoids the imports-vs-config
  # infinite recursion that lib.optional config.X would cause).
  config = lib.mkIf config.harness.hermesAgentEnabled {
  # Config + data dirs. No /var/lib/hermes anymore — numtide bundles the
  # whole agent, so there is no mutable git checkout / venv to persist.
  systemd.tmpfiles.rules = [
    "d /home/opc/.hermes            0750 opc opc -"
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

      # Mirror the scp'd config into Hermes's default discovery path.
      ExecStartPre = "${hermesConfigLink}";

      # numtide binary (binary-cache hit, meta.mainProgram = "hermes").
      # `gateway start --foreground` is a Hermes-native subcommand
      # (unchanged from the old launcher's final exec line).
      ExecStart = "${lib.getExe pkgs.llm-agents.hermes-agent} gateway start --foreground";

      Restart          = "on-failure";
      RestartSec       = "30s";
      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "hermes-agent";

      # No git clone / uv install on first start anymore. The only first-run
      # cost is a possible lazy Whisper Tiny fetch (~75 MB) the first time a
      # voice channel is used — that does not block start, so 5 min is ample.
      TimeoutStartSec  = "5min";

      ReadWritePaths   = [ "/home/opc/hermes-agent" "/home/opc/.hermes" ];
    };
  };
  };  # end config = lib.mkIf config.harness.hermesAgentEnabled
}
