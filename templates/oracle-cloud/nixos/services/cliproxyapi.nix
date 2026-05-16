{ config, pkgs, lib, ... }:

# CLIProxyAPI — Go-based local proxy that wraps Codex CLI / Claude Code CLI
# subscriptions as OpenAI-compatible endpoints.
#
# GitHub: https://github.com/router-for-me/CLIProxyAPI
# Default listen port: 8317 (localhost only, via config.yaml host: "127.0.0.1")
#
# 7.33.0: Migrated from the self-built buildGoModule derivation
# (pkgs/cliproxyapi.nix — deleted) to numtide/llm-agents.nix
# (pkgs.llm-agents.cli-proxy-api). It is now a binary-cache hit from
# https://cache.numtide.com, daily auto-updated upstream, with
# meta.mainProgram = "cli-proxy-api" (binary name unchanged). No more
# lib.fakeHash vendorHash placeholder to maintain.
#
# This module is always imported (cliproxyapi is active since 7.31.0 —
# dual-OAuth: daily-progress always routes through it).
#
# Authentication:
#   codex       → auto-reads ~/.codex/auth.json  (deployed by ensure-codex-auth.sh)
#   claude-code → auto-reads ~/.claude/.credentials.json (from claude setup-token)

{
  # Persistent state directory for CLIProxyAPI config and auth cache.
  # config.yaml is written by setup-oci-vm-nixos.sh via scp.
  systemd.tmpfiles.rules = [
    "d /home/opc/cliproxyapi 0750 opc opc -"
  ];

  systemd.services.cliproxyapi = {
    description = "CLIProxyAPI — local OpenAI-compatible proxy for Codex/Claude Code CLI subscriptions";
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # Hermes Agent must start after CLIProxyAPI is ready.
    before = [ "hermes-agent.service" ];

    serviceConfig = {
      Type  = "simple";
      User  = "opc";
      Group = "opc";
      WorkingDirectory = "/home/opc/cliproxyapi";

      # numtide binary from /nix/store (binary-cache hit) — no download on start.
      ExecStart = "${lib.getExe pkgs.llm-agents.cli-proxy-api} --config /home/opc/cliproxyapi/config.yaml";

      Restart    = "on-failure";
      RestartSec = "30s";

      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "cliproxyapi";
    };
  };
}
