# Hermes Agent — FHS environment wrapper (Approach B: buildFHSEnv hybrid).
#
# Why not buildPythonApplication (Approach A)?
#   Hermes is not published on PyPI. It is installed via `git clone` + `uv sync`
#   from source (tag v2026.5.7, internal version 0.13.0). Three core-dependency
#   packages are absent from nixpkgs 25.05:
#     - exa-py         (web search tool)
#     - parallel-web   (parallel HTTP fetch helper)
#     - fal-client     (Fal image-generation client)
#   Packaging all three + their transitive deps as sibling derivations would be
#   a large, fragile surface area to maintain as upstream evolves weekly
#   (Hermes uses date-based versioning: new tags every 7 days).
#
#   buildFHSEnv gives us the best trade-off:
#   - The Nix closure provides all in-nixpkgs Python deps so uv can skip
#     re-fetching them at runtime (PYTHONPATH pre-seeded).
#   - uv handles the git clone + the three missing packages + editable install
#     into /var/lib/hermes/venv/ on first start (idempotent; fast on re-runs).
#   - The FHS env itself is fully reproducible and Nix-managed. The venv state
#     at /var/lib/hermes/ is mutable runtime state — same as model weights.
#
# In-nixpkgs deps provided to the FHS env (so uv does NOT fetch them):
#   openai, anthropic, faster-whisper, discord.py, python-telegram-bot,
#   slack-bolt, slack-sdk, sounddevice, numpy, aiohttp, croniter, edge-tts,
#   pyjwt, requests, httpx, pyyaml, rich, tenacity, jinja2, pydantic,
#   prompt-toolkit, fire, qrcode, ptyprocess, firecrawl-py
#
# Packages NOT in nixpkgs — pip-installed by uv at first start:
#   exa-py, parallel-web, fal-client  (plus their transitive deps)
#
# Source: https://github.com/NousResearch/hermes-agent
# Pinned tag: v2026.5.7  (internal version: 0.13.0, Python ≥3.11)
# SRI hash: sha256-dbYp54emgWRxO2bR3RY8ZfhTR0ycd1zW8gZ5emKaosA=

{ pkgs, lib, ... }:

let
  python = pkgs.python311;

  # The subset of Hermes dependencies available in nixpkgs 25.05.
  # Pre-seeding PYTHONPATH avoids redundant uv downloads on every start.
  nixpkgsPythonDeps = with python.pkgs; [
    openai
    anthropic
    faster-whisper
    discordpy
    python-telegram-bot
    slack-bolt
    slack-sdk
    sounddevice
    numpy
    aiohttp
    croniter
    edge-tts
    pyjwt
    requests
    httpx
    pyyaml
    rich
    tenacity
    jinja2
    pydantic
    prompt-toolkit
    fire
    qrcode
    ptyprocess
    firecrawl-py
  ];

in pkgs.buildFHSEnv {
  name = "hermes-agent-env";

  targetPkgs = ps: with ps; [
    python
    python.pkgs.pip
    uv
    git
    ffmpeg     # required by faster-whisper for audio decode
    gcc        # for compiling any wheel that needs a C extension
    libffi     # common transitive C dependency
    openssl    # needed by cryptographic Python packages
  ] ++ nixpkgsPythonDeps;

  # The launcher script used as ExecStart in hermes-agent.nix.
  # It seeds PYTHONPATH with the nixpkgs deps and delegates to the uv-managed venv.
  runScript = pkgs.writeShellScript "hermes-agent-launcher" ''
    set -eu

    HERMES_HOME="/var/lib/hermes"
    HERMES_REPO="$HERMES_HOME/hermes-agent"
    HERMES_VENV="$HERMES_HOME/venv"
    HERMES_TAG="v2026.5.7"
    HERMES_BIN="$HERMES_VENV/bin/hermes"

    # ── First-run install (idempotent) ──────────────────────────────────────
    if [ ! -x "$HERMES_BIN" ]; then
      echo "[hermes-agent] first-run install: cloning hermes-agent $HERMES_TAG..."
      mkdir -p "$HERMES_HOME"

      # Clone or update the repo to the pinned tag.
      if [ -d "$HERMES_REPO/.git" ]; then
        git -C "$HERMES_REPO" fetch --quiet origin
        git -C "$HERMES_REPO" checkout --quiet "$HERMES_TAG"
      else
        git clone --quiet --branch "$HERMES_TAG" --depth 1 \
          https://github.com/NousResearch/hermes-agent.git \
          "$HERMES_REPO"
      fi

      # Create venv with Python 3.11 (already in PATH via FHS env).
      uv venv "$HERMES_VENV" --python python3.11 --quiet

      # Install Hermes + all extras into the venv.
      # The three packages absent from nixpkgs (exa-py, parallel-web, fal-client)
      # are fetched from PyPI here. All other deps are satisfied by PYTHONPATH
      # (the nixpkgs Python packages injected below), so uv will skip them.
      uv pip install --quiet \
        --python "$HERMES_VENV/bin/python" \
        --editable "$HERMES_REPO[messaging,voice]"

      echo "[hermes-agent] install complete."
    fi

    # ── Seed PYTHONPATH with nixpkgs-provided deps ─────────────────────────
    # This lets the venv Python find the in-nixpkgs packages without
    # re-downloading them via uv.
    NIX_SITE_PACKAGES="${python}/${python.sitePackages}"
    for dep in ${lib.concatMapStringsSep " " (d: "${d}/${python.sitePackages}") nixpkgsPythonDeps}; do
      if [ -d "$dep" ]; then
        export PYTHONPATH="$dep''${PYTHONPATH:+:$PYTHONPATH}"
      fi
    done
    # Venv site-packages take precedence over nixpkgs (must come first).
    VENV_SITE="$HERMES_VENV/lib/python3.11/site-packages"
    export PYTHONPATH="$VENV_SITE''${PYTHONPATH:+:$PYTHONPATH}"

    # ── Config symlink (maps hermes data dir to ~/.hermes convention) ───────
    HERMES_CFG_DIR="$HERMES_HOME/.hermes"
    mkdir -p "$HERMES_CFG_DIR"
    CONFIG_SRC="$HOME/hermes-agent/config.yaml"
    CONFIG_DST="$HERMES_CFG_DIR/config.yaml"
    if [ -f "$CONFIG_SRC" ] && [ ! -e "$CONFIG_DST" ]; then
      ln -sf "$CONFIG_SRC" "$CONFIG_DST"
    fi

    # ── Launch Hermes gateway ───────────────────────────────────────────────
    exec "$HERMES_BIN" gateway start --foreground "$@"
  '';

  meta = with lib; {
    description = "Hermes Agent FHS environment — NousResearch personal AI gateway (Discord + voice)";
    homepage    = "https://github.com/NousResearch/hermes-agent";
    license     = licenses.mit;
    platforms   = platforms.linux;
  };
}
