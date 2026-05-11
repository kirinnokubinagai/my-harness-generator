#!/usr/bin/env bash
# gen-e2e.sh — spec/features.md から Playwright E2E テストを生成する。
# harness-gen-e2e skill のエントリポイント。
#
# Usage:
#   bash scripts/gen-e2e.sh                       # 全機能
#   bash scripts/gen-e2e.sh --feature <name>      # 単一機能
#   bash scripts/gen-e2e.sh --dry-run             # プロンプトだけ表示

set -u

DRY=0
FEATURE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1;        shift ;;
    --feature) FEATURE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

__resolve_root() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -d "$d/.bare" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  echo "${1:-$PWD}"
}
ROOT="$(__resolve_root "$PWD")"
SPEC="$ROOT/dev/docs/spec/features.md"
PROMPT_TMPL="$(dirname "$0")/../prompts/spec-to-e2e.md"
[ -f "$PROMPT_TMPL" ] || PROMPT_TMPL="$ROOT/.my-harness/prompts/spec-to-e2e.md"
[ -f "$SPEC" ]        || { echo "no $SPEC" >&2; exit 1; }
[ -f "$PROMPT_TMPL" ] || { echo "no prompt template at $PROMPT_TMPL" >&2; exit 1; }

mkdir -p "$ROOT/dev/tests/e2e"

# spec を H2 (## Feature: ) で分割
awk -v feature="$FEATURE" -v dry="$DRY" -v tmpl="$PROMPT_TMPL" -v root="$ROOT" -v plugin="$(dirname "$0")/.." '
  /^## Feature: / {
    if (title != "") flush()
    title = substr($0, 13)
    body = ""
    next
  }
  /^## / && title != "" { flush(); title = ""; next }
  title != "" { body = body $0 "\n" }
  END { if (title != "") flush() }

  function flush(    slug, out, prompt, cmd) {
    if (feature != "" && title != feature) return
    slug = tolower(title)
    gsub(/[^a-z0-9]+/, "-", slug)
    sub(/^-/, "", slug); sub(/-$/, "", slug)
    out = root "/dev/tests/e2e/" slug ".spec.ts"
    if (system("test -f " out) == 0) {
      printf "skip (exists): %s\n", out
      return
    }
    # プロンプト組み立て
    prompt = ""
    while ((getline line < tmpl) > 0) prompt = prompt line "\n"
    close(tmpl)
    gsub(/\{\{FEATURE_TITLE\}\}/, title, prompt)
    gsub(/\{\{FEATURE_BODY\}\}/,  body,  prompt)

    if (dry == 1) {
      printf "===PROMPT FOR: %s ===\n%s\n===END===\n", title, prompt
      return
    }
    # Codex / Claude にプロンプトを渡す
    tmp = "/tmp/gen-e2e-" PROCINFO["pid"] "-" slug ".txt"
    print prompt > tmp
    close(tmp)
    cmd = sprintf("bash \"%s/scripts/codex-ask.sh\" --role harness-engineer --input \"%s\" --output \"%s\"", plugin, tmp, out)
    if (system(cmd) == 0) {
      printf "generated: %s\n", out
    } else {
      printf "failed: %s (codex-ask.sh exit non-zero) — see %s\n", title, tmp
    }
  }
' "$SPEC"
