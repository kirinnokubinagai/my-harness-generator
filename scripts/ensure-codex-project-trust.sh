#!/usr/bin/env bash
# ensure-codex-project-trust.sh — add the project root to Codex's trusted
# projects list in ~/.codex/config.toml so the daemon does not block on
# an interactive trust prompt that has no UI to answer it.
#
# Background:
# Codex CLI has TWO independent approval layers:
#   L1 — Project trust:   "may Codex run sessions in this directory?"
#                         Configured via ~/.codex/config.toml
#                         [projects."<absolute-path>"] trust_level = "trusted"
#   L2 — Action approval: "may Codex run this shell command / edit this file?"
#                         Configured via ThreadConfig.approval_policy
#
# Our codex-app-server-call.py already sets L2 to "never" (auto-approve), but
# L2 doesn't bypass L1. A daemon running `codex app-server` in a non-trusted
# directory raises an L1 approval request that nothing can answer (no UI),
# so the turn hangs forever and image_gen never fires. This script flips L1
# to trusted for the given root by appending the right TOML section.
#
# Idempotent: if the section already exists with trust_level="trusted" the
# script is a no-op. Existing config is preserved (we APPEND a fresh section
# rather than rewrite the file).
#
# Reference:
#   https://developers.openai.com/codex/config-reference
#   ('You can mark a project or worktree as trusted or untrusted')
#
# Usage:
#   bash scripts/ensure-codex-project-trust.sh <root>

set -u

ROOT_RAW="${1:?root required}"
# Resolve to absolute path (Codex stores absolute paths in the TOML key).
ROOT_ABS=$(cd "$ROOT_RAW" 2>/dev/null && pwd -P || printf '%s' "$ROOT_RAW")

CONFIG_PATH="${CODEX_HOME:-$HOME/.codex}/config.toml"

python3 - "$ROOT_ABS" "$CONFIG_PATH" <<'PY'
import os
import sys
import pathlib

root, config_path_str = sys.argv[1], sys.argv[2]
config_path = pathlib.Path(config_path_str)

# Use stdlib tomllib for parsing (Python 3.11+); fall back to a tolerant
# text-scan when tomllib is missing or the file has TOML errors we don't
# want to crash on.
try:
    import tomllib  # 3.11+
    have_tomllib = True
except ImportError:
    have_tomllib = False

already_trusted = False
already_present = False

if config_path.is_file():
    text = config_path.read_text(encoding="utf-8")
    if have_tomllib:
        try:
            data = tomllib.loads(text)
            projects = data.get("projects", {}) or {}
            entry = projects.get(root, {}) or {}
            already_present = root in projects
            already_trusted = entry.get("trust_level") == "trusted"
        except tomllib.TOMLDecodeError as e:
            print(f"::warning:: {config_path} has TOML decode error ({e}); falling back to text scan", file=sys.stderr)
            have_tomllib = False
    if not have_tomllib:
        # Text-scan fallback: look for the literal section header. Won't
        # catch every TOML edge case but is right for the format Codex
        # writes itself.
        needle = f'[projects."{root}"]'
        if needle in text:
            already_present = True
            # Trust-level check via simple line scan
            in_section = False
            for line in text.splitlines():
                stripped = line.strip()
                if stripped == needle:
                    in_section = True
                    continue
                if in_section:
                    if stripped.startswith("[") and stripped.endswith("]"):
                        break  # next section started
                    if stripped.startswith("trust_level"):
                        already_trusted = '"trusted"' in stripped
                        break

if already_trusted:
    print(f"[trust] {root} already trusted in {config_path}", file=sys.stderr)
    sys.exit(0)

if already_present and not already_trusted:
    print(f"::warning:: {config_path} already has [projects.\"{root}\"] but trust_level != \"trusted\". Manual review recommended; this script will not overwrite it.", file=sys.stderr)
    sys.exit(0)

# Append a fresh section.
config_path.parent.mkdir(parents=True, exist_ok=True)
needs_leading_newline = config_path.is_file() and not config_path.read_text(encoding="utf-8").endswith("\n")
with open(config_path, "a", encoding="utf-8") as f:
    if needs_leading_newline:
        f.write("\n")
    f.write(f'\n[projects."{root}"]\ntrust_level = "trusted"\n')
print(f"[trust] added [projects.\"{root}\"] trust_level=\"trusted\" to {config_path}", file=sys.stderr)
PY
