{ config, pkgs, lib, ... }:

# CLIProxyAPI — Go-based local proxy that wraps Codex CLI / Claude Code CLI
# subscriptions as OpenAI-compatible endpoints.
#
# GitHub: https://github.com/router-for-me/CLIProxyAPI
# Default listen port: 8317 (localhost only, via config.yaml host: "127.0.0.1")
#
# This module is imported into configuration.nix only when
# HERMES_AI_PROVIDER ∈ {codex, claude-code}. setup-oci-vm-nixos.sh decides
# whether to include this module based on the value it reads from
# .my-harness/.hermes-config.json — so no Nix-side conditional is needed here.
#
# Authentication:
#   codex      → auto-reads ~/.codex/auth.json  (deployed by ensure-codex-auth.sh)
#   claude-code → auto-reads ~/.claude/.credentials.json (from claude setup-token)
#
# CLIProxyAPI v7.0.6 provides a pre-built linux/aarch64 binary — preferred over
# buildGoModule to avoid the nix sandbox needing network access for go deps.
# The binary is downloaded during ExecStartPre (idempotent) so NixOS evaluation
# stays pure.

let
  # CLIProxyAPI release version and aarch64-linux download URL.
  # Bump these together when upgrading. Check:
  #   gh api repos/router-for-me/CLIProxyAPI/releases/latest
  cliproxyapiVersion = "7.0.6";
  cliproxyapiUrl = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${cliproxyapiVersion}/CLIProxyAPI_${cliproxyapiVersion}_linux_aarch64.tar.gz";

  # Download + install script (idempotent).
  installScript = pkgs.writeShellScript "cliproxyapi-install" ''
    set -eu
    INSTALL_DIR="/home/opc/cliproxyapi"
    BIN="$INSTALL_DIR/cliproxyapi"
    VERSION="${cliproxyapiVersion}"

    mkdir -p "$INSTALL_DIR"

    # Check if already installed at the right version.
    if [ -x "$BIN" ] && "$BIN" --version 2>/dev/null | grep -q "$VERSION"; then
      echo "[cliproxyapi] v$VERSION already installed — skipping download."
      exit 0
    fi

    echo "[cliproxyapi] downloading v$VERSION for linux/aarch64..."
    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT

    ${pkgs.curl}/bin/curl -fsSL \
      "${cliproxyapiUrl}" \
      -o "$TMPDIR/cliproxyapi.tar.gz"

    ${pkgs.gnutar}/bin/tar -xzf "$TMPDIR/cliproxyapi.tar.gz" -C "$TMPDIR"

    # The tarball extracts to a directory; find the binary.
    EXTRACTED_BIN="$(find "$TMPDIR" -name 'CLIProxyAPI' -o -name 'cliproxyapi' | head -1)"
    if [ -z "$EXTRACTED_BIN" ]; then
      echo "::error:: CLIProxyAPI binary not found in tarball" >&2
      exit 1
    fi

    install -m 0755 "$EXTRACTED_BIN" "$BIN"
    chown opc:opc "$BIN"
    echo "[cliproxyapi] installed $BIN (v$VERSION)"
  '';

in
{
  # curl + tar are needed by the install script (pulled via pkgs references above).
  # No extra environment.systemPackages needed — curl and gnutar are referenced
  # directly in the writeShellScript via ${pkgs.*} closures.

  # Persistent state directory for CLIProxyAPI config and auth cache.
  systemd.tmpfiles.rules = [
    "d /home/opc/cliproxyapi 0750 opc opc -"
  ];

  systemd.services.cliproxyapi = {
    description = "CLIProxyAPI — local OpenAI-compatible proxy for Codex/Claude Code CLI subscriptions";
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # Hermes Agent must start after CLIProxyAPI is ready.
    before   = [ "hermes-agent.service" ];

    serviceConfig = {
      Type  = "simple";
      User  = "opc";
      Group = "opc";
      WorkingDirectory = "/home/opc/cliproxyapi";

      # Download binary on first run / after version bump (idempotent).
      ExecStartPre = installScript;

      # Start the proxy. Config written by setup-oci-vm-nixos.sh.
      ExecStart = "/home/opc/cliproxyapi/cliproxyapi --config /home/opc/cliproxyapi/config.yaml";

      Restart    = "on-failure";
      RestartSec = "30s";

      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "cliproxyapi";

      # Give the first download enough time (binary is ~15-20 MB, fast on OCI egress).
      TimeoutStartSec = "120";
    };
  };
}
