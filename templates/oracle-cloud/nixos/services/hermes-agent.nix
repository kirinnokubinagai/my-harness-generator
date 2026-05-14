{ config, pkgs, lib, ... }:

# Hermes Agent — NousResearch's personal AI gateway with Voice Mode.
#
# STT: local Whisper Tiny (~75 MB, ARM64-safe, no external API).
# TTS: NeuTTS Air (~500 MB on first use, ARM64-safe, no external API).
# Discord: Auto Voice Reply (voice messages in text channels) +
#          Discord Voice Channels (bot joins VC, listens, speaks).
#
# Install method: official install.sh (Python-based CLI).
# The ExecStartPre step runs the installer idempotently — re-runs are
# fast (installer checks for existing ~/.hermes/bin/hermes).
#
# Secrets live in /home/opc/hermes-agent/.env (EnvironmentFile),
# written by setup-oci-vm-nixos.sh with umask 077.

{
  # Python 3 + pip are required by Hermes's install.sh.
  # Node.js is NOT needed — Hermes is a Python CLI, not npm.
  environment.systemPackages = with pkgs; [
    python312           # Hermes requires Python 3.10+; 3.12 is in nixpkgs 25.05
    python312Packages.pip
    ffmpeg              # required by faster-whisper for audio decoding
    # portaudio is for CLI mic; omitted — headless VM has no microphone.
    # Gateway voice (Discord VC) receives audio over the Discord API, not portaudio.
  ];

  # Persistent state directory for Hermes working data and model cache.
  systemd.tmpfiles.rules = [
    "d /home/opc/hermes-agent      0750 opc opc -"
    "d /home/opc/hermes-agent/data 0750 opc opc -"
  ];

  systemd.services.hermes-agent = {
    description = "Hermes Agent — NousResearch personal AI gateway (Voice + Discord)";
    after    = [ "network-online.target" "ollama.service" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type            = "simple";
      User            = "opc";
      Group           = "opc";
      WorkingDirectory = "/home/opc/hermes-agent";

      # EnvironmentFile holds DISCORD_BOT_TOKEN, OPENAI_API_KEY, OPENAI_BASE_URL, etc.
      # Written by setup-oci-vm-nixos.sh with chmod 600.
      EnvironmentFile = "/home/opc/hermes-agent/.env";

      # Idempotent install: if `hermes` binary already present, skip.
      # The official install.sh places the binary in ~/.hermes/bin/hermes.
      # We also install the [voice] and [messaging] extras via pip after
      # the base install, so STT (faster-whisper) and Discord gateway work.
      ExecStartPre = pkgs.writeShellScript "hermes-install" ''
        set -eu
        HERMES_BIN="$HOME/.hermes/bin/hermes"

        if [ ! -x "$HERMES_BIN" ]; then
          echo "[hermes-agent] installing Hermes Agent via official install.sh..."
          curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
        else
          echo "[hermes-agent] Hermes already installed at $HERMES_BIN — skipping install."
        fi

        # Ensure voice + messaging extras are present (idempotent pip install).
        # faster-whisper provides local Whisper STT; neutts provides NeuTTS TTS.
        HERMES_PYTHON="$HOME/.hermes/venv/bin/python"
        if [ -x "$HERMES_PYTHON" ]; then
          "$HERMES_PYTHON" -m pip install --quiet --upgrade \
            "hermes-agent[voice,messaging]" \
            faster-whisper \
            "neutts[all]" \
          || echo "[hermes-agent] pip install extras failed; core gateway may still work"
        fi

        # Symlink config if not already in place.
        HERMES_CFG_DIR="$HOME/.hermes"
        HERMES_CFG="$HERMES_CFG_DIR/config.yaml"
        OCI_CFG="$HOME/hermes-agent/config.yaml"
        if [ -f "$OCI_CFG" ] && [ ! -f "$HERMES_CFG" ]; then
          mkdir -p "$HERMES_CFG_DIR"
          ln -sf "$OCI_CFG" "$HERMES_CFG"
          echo "[hermes-agent] symlinked config.yaml → $HERMES_CFG"
        fi

        # Symlink .env so Hermes can also read it from its canonical location.
        OCI_ENV="$HOME/hermes-agent/.env"
        HERMES_ENV="$HERMES_CFG_DIR/.env"
        if [ -f "$OCI_ENV" ] && [ ! -f "$HERMES_ENV" ]; then
          ln -sf "$OCI_ENV" "$HERMES_ENV"
        fi
      '';

      # Launch Hermes gateway (Discord + voice modes).
      # `hermes gateway start` forks a daemon but we use Type=simple with
      # the --foreground flag so systemd tracks the PID properly.
      # If upstream drops --foreground, switch Type to forking.
      ExecStart = "/home/opc/.hermes/bin/hermes gateway start --foreground";

      Restart          = "on-failure";
      RestartSec       = "30s";
      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "hermes-agent";

      # Give the model download on first run plenty of time.
      # Whisper Tiny (~75 MB) + NeuTTS Air (~500 MB) = ~575 MB on first boot.
      TimeoutStartSec  = "15min";
    };
  };
}
