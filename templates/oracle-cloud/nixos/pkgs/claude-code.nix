# Anthropic Claude Code CLI — Nix-built from npm.
# Upstream: https://github.com/anthropics/claude-code
# npm package: @anthropic-ai/claude-code
#
# Pinned to: 2.1.141
# License: Proprietary — "SEE LICENSE IN README.md" (npm metadata).
#          Listed as unfree; users must agree to Anthropic's ToS.
#
# Source hash:
#   curl -sL https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.141.tgz \
#     | python3 -c 'import hashlib,base64,sys; h=hashlib.sha256(sys.stdin.buffer.read()).digest(); print("sha256-"+base64.b64encode(h).decode())'
#   => sha256-a35KoQBnG1hO3iMMrIfoBXOoZufFgSL76Q06LGuvfpw=
#
# npmDepsHash: set to lib.fakeHash — update after the first `nixos-rebuild switch`
# error prints the correct hash (same pattern as pkgs/cliproxyapi.nix vendorHash).

{ lib, buildNpmPackage, fetchurl, nodejs_20 }:

buildNpmPackage rec {
  pname = "claude-code";
  version = "2.1.141";

  src = fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    hash = "sha256-a35KoQBnG1hO3iMMrIfoBXOoZufFgSL76Q06LGuvfpw=";
  };

  # FIXME: replace with hash from first `nix build` / `nixos-rebuild switch` error.
  # Run: nix build .#claude-code 2>&1 | grep 'got:'
  # then substitute that value here and commit a 7.29.2.1 patch.
  npmDepsHash = lib.fakeHash;

  nodejs = nodejs_20;

  # The npm tarball provides a pre-built CLI; no separate build step needed.
  dontNpmBuild = true;

  meta = with lib; {
    description = "Anthropic Claude Code — agentic AI coding assistant CLI";
    homepage    = "https://github.com/anthropics/claude-code";
    license     = licenses.unfree;
    mainProgram = "claude";
    platforms   = platforms.linux;
  };
}
