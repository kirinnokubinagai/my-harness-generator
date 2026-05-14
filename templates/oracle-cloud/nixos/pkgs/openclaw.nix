# OpenClaw — Nix-built from npm (buildNpmPackage).
#
# Why buildNpmPackage (not buildFHSEnv / buildPythonApplication)?
#   OpenClaw is published to npm as the `openclaw` package (Node 24 recommended,
#   Node 22.16+ supported). Unlike Hermes (git-only, Python, missing PyPI deps),
#   OpenClaw ships a self-contained npm tarball with no external git clone step.
#   buildNpmPackage is the idiomatic Nix approach for npm-published CLIs — it
#   produces a reproducible closure without runtime network access.
#
# Pinned to: 2026.5.7
# Install method: npm install -g openclaw@2026.5.7
#
# Source hash (npm tarball):
#   curl -sL https://registry.npmjs.org/openclaw/-/openclaw-2026.5.7.tgz \
#     | python3 -c 'import hashlib,base64,sys; h=hashlib.sha256(sys.stdin.buffer.read()).digest(); print("sha256-"+base64.b64encode(h).decode())'
#
# FIXME: Replace lib.fakeHash placeholders with real values from first
# `nix build` / `nixos-rebuild switch` error output (same pattern as claude-code.nix).
# The build will print: "got: sha256-<actual>"
# 1. Set `hash` to the printed value for the src fetchurl.
# 2. Set `npmDepsHash` to the value from the second build attempt.
# Commit the corrected hashes in a 7.30.0.1 patch.

{ lib, buildNpmPackage, fetchurl, nodejs_24 ? null, nodejs_22 ? null, nodejs_20 }:

let
  # Prefer Node 24 (OpenClaw recommended), fall back to Node 22, then 20.
  nodejs = if nodejs_24 != null then nodejs_24
           else if nodejs_22 != null then nodejs_22
           else nodejs_20;
in

buildNpmPackage rec {
  pname = "openclaw";
  version = "2026.5.7";

  src = fetchurl {
    url = "https://registry.npmjs.org/openclaw/-/openclaw-${version}.tgz";
    # FIXME: replace with real sha256 from first `nix build` failure.
    # Run: nix build .#openclaw 2>&1 | grep 'got:'
    hash = lib.fakeHash;
  };

  # FIXME: replace with real npm-deps hash from second `nix build` failure.
  # Run: nix build .#openclaw 2>&1 | grep 'got:'
  npmDepsHash = lib.fakeHash;

  inherit nodejs;

  # OpenClaw is pre-built in the npm tarball; no separate build step needed.
  dontNpmBuild = true;

  meta = with lib; {
    description = "OpenClaw — open-source self-hosted AI gateway (Discord + voice, alternative to Hermes)";
    homepage    = "https://docs.openclaw.ai/";
    license     = licenses.mit;
    mainProgram = "openclaw";
    platforms   = platforms.linux;
  };
}
