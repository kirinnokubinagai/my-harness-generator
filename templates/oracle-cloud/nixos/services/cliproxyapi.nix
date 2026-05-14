{ config, pkgs, lib, ... }:

# CLIProxyAPI — Go-based local proxy that wraps Codex CLI / Claude Code CLI
# subscriptions as OpenAI-compatible endpoints.
#
# GitHub: https://github.com/router-for-me/CLIProxyAPI
# Default listen port: 8317 (localhost only, via config.yaml host: "127.0.0.1")
#
# 7.29.0: Replaced the 7.26.0 ExecStartPre curl/tar binary download with a
# buildGoModule derivation (pkgs/cliproxyapi.nix). The binary now lives in
# /nix/store/...-cliproxyapi-7.0.6/bin/cli-proxy-api and is resolved at
# nixos-rebuild time — no network access needed at service start.
#
# This module is imported into configuration.nix only when
# HERMES_AI_PROVIDER ∈ {codex, claude-code}. setup-oci-vm-nixos.sh decides
# whether to include this module based on .my-harness/.hermes-config.json —
# no Nix-side conditional is needed here.
#
# Authentication:
#   codex       → auto-reads ~/.codex/auth.json  (deployed by ensure-codex-auth.sh)
#   claude-code → auto-reads ~/.claude/.credentials.json (from claude setup-token)

let
  cliproxyapi = pkgs.callPackage ./../pkgs/cliproxyapi.nix { };
in
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

      # Binary resolved from /nix/store at nixos-rebuild time — no download on start.
      ExecStart = "${cliproxyapi}/bin/cli-proxy-api --config /home/opc/cliproxyapi/config.yaml";

      Restart    = "on-failure";
      RestartSec = "30s";

      StandardOutput   = "journal";
      StandardError    = "journal";
      SyslogIdentifier = "cliproxyapi";
    };
  };
}
