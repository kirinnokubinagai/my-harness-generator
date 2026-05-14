# CLIProxyAPI — Nix-built Go package.
# Upstream: https://github.com/router-for-me/CLIProxyAPI
# Replaces the prebuilt-tarball download from 7.26.0 with a reproducible
# buildGoModule derivation pinned to a specific upstream commit.
#
# Pinned to: v7.0.6 (commit 3a9fb3780ed63d9c71efca760d0c5935b3f6fc19)
# Build target: aarch64-linux (Oracle Cloud A1.Flex)
#
# Binary: cli-proxy-api (from ./cmd/server/ per upstream .goreleaser.yml)
# Default listen port: 8317 (configured via config.yaml)

{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "cliproxyapi";
  version = "7.0.6";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    rev = "v${version}";
    hash = "sha256-VgLx9Zok24QfYDacmJmC4FS5y5jqNd/9eyh1MQ8Jhww=";
  };

  # FIXME: vendorHash must be updated on the first `nixos-rebuild switch`.
  # Set vendorHash = lib.fakeHash below, run the build, copy the
  # "expected vs actual" hash from the error message, and commit a 7.29.0.1 patch.
  vendorHash = lib.fakeHash;

  # Main package lives in ./cmd/server/ per upstream .goreleaser.yml.
  subPackages = [ "cmd/server" ];

  # Match upstream goreleaser ldflags; Commit/BuildDate omitted (reproducible).
  ldflags = [
    "-s"
    "-w"
    "-X" "main.Version=${version}"
  ];

  # The upstream binary is named cli-proxy-api (goreleaser `binary:` field).
  # We expose it under that name so ExecStart references are explicit.
  meta = with lib; {
    description = "Wrap Codex, Claude Code, Gemini CLI etc. as OpenAI/Claude-compatible APIs";
    homepage    = "https://github.com/router-for-me/CLIProxyAPI";
    license     = licenses.mit;
    mainProgram = "cli-proxy-api";
    platforms   = platforms.linux;
  };
}
