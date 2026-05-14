# OpenAI Codex CLI — Nix-built from npm.
# Upstream: https://github.com/openai/codex
# npm package: @openai/codex
#
# Pinned to: 0.130.0
# License: Apache-2.0 (npm metadata).
#
# Source hash:
#   curl -sL https://registry.npmjs.org/@openai/codex/-/codex-0.130.0.tgz \
#     | python3 -c 'import hashlib,base64,sys; h=hashlib.sha256(sys.stdin.buffer.read()).digest(); print("sha256-"+base64.b64encode(h).decode())'
#   => sha256-w//PJo0YALy/zlDcqWTgXWq8zY8dIOlEs7uHfnFkL8o=
#
# npmDepsHash: set to lib.fakeHash — update after the first `nixos-rebuild switch`
# error prints the correct hash (same pattern as pkgs/cliproxyapi.nix vendorHash).

{ lib, buildNpmPackage, fetchurl, nodejs_20 }:

buildNpmPackage rec {
  pname = "openai-codex";
  version = "0.130.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
    hash = "sha256-w//PJo0YALy/zlDcqWTgXWq8zY8dIOlEs7uHfnFkL8o=";
  };

  # FIXME: replace with hash from first `nix build` / `nixos-rebuild switch` error.
  # Run: nix build .#openai-codex 2>&1 | grep 'got:'
  # then substitute that value here and commit a 7.29.2.1 patch.
  npmDepsHash = lib.fakeHash;

  nodejs = nodejs_20;

  # The npm tarball provides a pre-built CLI; no separate build step needed.
  dontNpmBuild = true;

  meta = with lib; {
    description = "OpenAI Codex — AI coding agent CLI";
    homepage    = "https://github.com/openai/codex";
    license     = licenses.asl20;
    mainProgram = "codex";
    platforms   = platforms.linux;
  };
}
