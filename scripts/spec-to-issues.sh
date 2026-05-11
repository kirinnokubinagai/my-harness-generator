#!/usr/bin/env bash
# spec-to-issues.sh — dev/docs/spec/features.md から GitHub Issue を一括生成。
# 各 H2 セクションを 1 issue にし、owned_files YAML フロントマターを抽出して
# `gh issue create` のラベルに反映する。harness-team-lead がそれを読んで
# ファイル所有を計算する。
#
# spec/features.md フォーマット:
#   ## Feature: ユーザー登録
#   ---
#   owned_files: ["dev/src/interfaces/http/routes/auth.ts", "dev/src/application/auth/login.ts"]
#   lane_hint: 2
#   ---
#   本文 (issue body にそのまま入る)
#
# Usage:
#   bash scripts/spec-to-issues.sh [--dry-run]
#
# 既存の同名 issue は skip される (重複防止)。

set -u

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

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
[ -f "$SPEC" ] || { echo "spec not found: $SPEC" >&2; exit 1; }

if [ "$DRY" -eq 0 ]; then
  command -v gh >/dev/null 2>&1 || { echo "gh CLI required" >&2; exit 3; }
fi

# 既存 issue タイトル一覧
EXISTING=""
if [ "$DRY" -eq 0 ]; then
  EXISTING=$(gh issue list --state all --limit 200 --json title --jq '.[].title' 2>/dev/null || true)
fi

# H2 セクションごとに分割して処理
awk '
  /^## Feature: / {
    if (title != "") print_section()
    title = substr($0, 13)
    body = ""
    frontmatter = ""
    in_fm = 0
    next
  }
  /^---$/ && title != "" {
    if (in_fm == 0) { in_fm = 1; next } else { in_fm = 2; next }
  }
  title != "" {
    if (in_fm == 1) frontmatter = frontmatter $0 "\n"
    else if (in_fm == 2) body = body $0 "\n"
  }
  END { if (title != "") print_section() }

  function print_section() {
    printf "===SECTION===\nTITLE: %s\nFRONTMATTER:\n%sBODY:\n%s===ENDSECTION===\n", title, frontmatter, body
  }
' "$SPEC" | awk -v existing="$EXISTING" -v dry="$DRY" '
  BEGIN { section = 0 }
  /^===SECTION===/ { section = 1; title = ""; fm = ""; body = ""; mode = "" ; next }
  /^TITLE: /   && section { title = substr($0, 8); next }
  /^FRONTMATTER:/ && section { mode = "fm";   next }
  /^BODY:/        && section { mode = "body"; next }
  /^===ENDSECTION===/ && section {
    section = 0
    if (index(existing, title) > 0) {
      printf "skip (exists): %s\n", title
      next
    }
    cmd_label = "lane-hint:" lh_of(fm)
    of = owned_of(fm)
    if (dry == 1) {
      printf "would create: %s [%s] owned=%s\n", title, cmd_label, of
    } else {
      tmpb = "/tmp/harness-issue-body-" PROCINFO["pid"] ".md"
      print "<!-- owned_files: " of " -->\n" body > tmpb
      close(tmpb)
      cmd = sprintf("gh issue create --title %s --body-file %s --label %s", shq(title), shq(tmpb), shq(cmd_label))
      system(cmd)
    }
    next
  }
  section && mode == "fm"   { fm = fm $0 "\n" }
  section && mode == "body" { body = body $0 "\n" }

  function lh_of(s,   r) { r=""; if (match(s, /lane_hint:[ ]*[0-9]+/)) r = substr(s, RSTART, RLENGTH); sub(/lane_hint:[ ]*/, "", r); return r=="" ? "0" : r }
  function owned_of(s,   r) { r=""; if (match(s, /owned_files:[ ]*\[[^]]*\]/)) r = substr(s, RSTART, RLENGTH); sub(/owned_files:[ ]*/, "", r); return r }
  function shq(x,   y) { y = x; gsub(/'\''/, "'\''\\'\'\''", y); return "'\''" y "'\''" }
'
