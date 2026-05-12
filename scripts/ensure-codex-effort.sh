#!/usr/bin/env bash
# ensure-codex-effort.sh — set Codex's global `model_reasoning_effort` in
# ~/.codex/config.toml if it isn't already set. Default level: `xhigh`
# (the highest reasoning depth, ~best output quality at the cost of
# latency + included-usage budget).
#
# Idempotent and non-destructive:
#   - If the key already exists in config.toml, the user's value wins
#     (we don't overwrite, we just log what's there).
#   - If absent, we append a fresh `model_reasoning_effort = "<level>"`
#     line at the file's top-level. Other config sections are untouched.
#
# Reference: https://developers.openai.com/codex/config-reference
#   reasoning_effort ∈ { none, minimal, low, medium, high, xhigh }
#
# Usage:
#   bash scripts/ensure-codex-effort.sh           # default level = xhigh
#   bash scripts/ensure-codex-effort.sh high      # explicit level

set -u

LEVEL="${1:-xhigh}"

# Validate level against the SDK's ReasoningEffort literal.
case "$LEVEL" in
  none|minimal|low|medium|high|xhigh) : ;;
  *)
    echo "::error:: invalid effort level '$LEVEL' — expected one of: none|minimal|low|medium|high|xhigh" >&2
    exit 1
    ;;
esac

CONFIG_PATH="${CODEX_HOME:-$HOME/.codex}/config.toml"

python3 - "$LEVEL" "$CONFIG_PATH" <<'PY'
import os
import sys
import pathlib

level, config_path_str = sys.argv[1], sys.argv[2]
config_path = pathlib.Path(config_path_str)

# tomllib (3.11+) for parsing; tolerant text-scan fallback.
try:
    import tomllib  # 3.11+
    have_tomllib = True
except ImportError:
    have_tomllib = False

current = None

if config_path.is_file():
    text = config_path.read_text(encoding="utf-8")
    if have_tomllib:
        try:
            data = tomllib.loads(text)
            # model_reasoning_effort lives at top level in Codex config.toml.
            current = data.get("model_reasoning_effort")
        except tomllib.TOMLDecodeError as e:
            print(f"::warning:: {config_path} has TOML decode error ({e}); falling back to text scan", file=sys.stderr)
            have_tomllib = False
    if not have_tomllib:
        # Text scan: any unindented `model_reasoning_effort = ...` line BEFORE
        # the first `[section]` header counts as the top-level value.
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                break
            if stripped.startswith("model_reasoning_effort"):
                # Extract quoted value
                parts = stripped.split("=", 1)
                if len(parts) == 2:
                    v = parts[1].strip().strip('"').strip("'")
                    current = v
                break

if current is not None:
    print(f"[effort] model_reasoning_effort already set to '{current}' in {config_path} — leaving as-is", file=sys.stderr)
    sys.exit(0)

# Need to write a new key. Insert at the top of the file (before any
# [section] header) so it stays top-level even after later appends.
config_path.parent.mkdir(parents=True, exist_ok=True)

if config_path.is_file():
    existing = config_path.read_text(encoding="utf-8")
else:
    existing = ""

new_line = f'model_reasoning_effort = "{level}"\n'

# Find where the first [section] header starts and inject our line just
# before it. If no section header exists, prepend at the very top.
lines = existing.splitlines(keepends=True)
insert_at = 0
for idx, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        insert_at = idx
        break
else:
    # No section header found — put at the very top, with a trailing newline
    # so adjacent existing content stays valid TOML.
    insert_at = 0

if insert_at == 0 and not existing:
    config_path.write_text(new_line, encoding="utf-8")
else:
    lines.insert(insert_at, new_line)
    config_path.write_text("".join(lines), encoding="utf-8")

print(f"[effort] added model_reasoning_effort = \"{level}\" to {config_path}", file=sys.stderr)
PY
