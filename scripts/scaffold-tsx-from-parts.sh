#!/usr/bin/env bash
# scaffold-tsx-from-parts.sh — generate a working TSX component for every
# cropped part PNG. Closes the last manual step in the Phase 5 pipeline.
#
# Baseline output: each component renders the transparent PNG via <img>. The
# component compiles, type-checks, and shows the right pixels immediately.
# A reviewer (or the implementation lane) can then upgrade specific parts to
# pure Tailwind reproductions and delete the <img> when ready — the swap is
# isolated to one file.
#
# Idempotent: skips files that already exist. Delete the file to force
# regeneration.
#
# Usage:
#   bash scripts/scaffold-tsx-from-parts.sh <root> <platform> <screen-slug>
#
# Requires: jq + a manifest.json + parts.ts already present at
#   <root>/dev/docs/design/parts/<form-factor>/<screen-slug>/
# (these are produced by crop-parts.sh).

set -u

ROOT="${1:?root required}"
PLATFORM="${2:?platform required}"
SCREEN_SLUG="${3:?screen-slug required}"

ASSET_DIR="$ROOT/dev/docs/design/parts/${PLATFORM}/${SCREEN_SLUG}"
TS_DIR="$ROOT/dev/src/components/design/${PLATFORM}/${SCREEN_SLUG}"
MANIFEST="$ASSET_DIR/manifest.json"

[ -f "$MANIFEST" ] || { echo "::error:: not found: $MANIFEST (run crop-parts.sh first)" >&2; exit 1; }
[ -f "$TS_DIR/parts.ts" ] || { echo "::error:: not found: $TS_DIR/parts.ts (run crop-parts.sh first)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error:: jq required" >&2; exit 3; }

mkdir -p "$TS_DIR"

# kebab-case → camelCase (for parts.ts key)
camel_case() {
  printf '%s' "$1" | awk -F'-' '{
    out=""
    for (i=1; i<=NF; i++) {
      w = $i
      if (i == 1) { out = tolower(w) }
      else { out = out toupper(substr(w,1,1)) tolower(substr(w,2)) }
    }
    print out
  }'
}

# kebab-case → PascalCase (for component name + file name)
pascal_case() {
  printf '%s' "$1" | awk -F'-' '{
    out=""
    for (i=1; i<=NF; i++) {
      w = $i
      out = out toupper(substr(w,1,1)) tolower(substr(w,2))
    }
    print out
  }'
}

# kebab-case → human-readable alt text
alt_text() {
  printf '%s' "$1" | tr '-' ' '
}

generated=0
skipped=0

jq -r '.cells[] | .name' "$MANIFEST" | while IFS= read -r NAME; do
  [ -z "$NAME" ] && continue
  COMP_NAME=$(pascal_case "$NAME")
  KEY=$(camel_case "$NAME")
  ALT=$(alt_text "$NAME")
  OUT="$TS_DIR/${COMP_NAME}.tsx"

  if [ -f "$OUT" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  cat > "$OUT" <<EOF
/**
 * 概要: ${PLATFORM} / ${SCREEN_SLUG} 画面の \`${NAME}\` パーツ。
 *       scaffold-tsx-from-parts.sh が初期実装として透過 PNG を直接表示するコンポーネントを生成。
 *       Tailwind / コードでの再現に置き換える際は <img> ブロックを削除し、
 *       parts.${KEY} の参照も削除する。残りの props 定義はそのまま使える。
 */
import { parts } from './parts';

export type ${COMP_NAME}Props = {
  /** 追加で適用したい Tailwind クラス */
  className?: string;
};

export function ${COMP_NAME}({ className }: ${COMP_NAME}Props) {
  return (
    <img
      src={parts.${KEY}}
      alt="${ALT}"
      className={\`block max-w-full h-auto \${className ?? ''}\`}
    />
  );
}

export default ${COMP_NAME};
EOF
  generated=$((generated + 1))
  echo "  generated: $OUT"
done

echo
echo "summary: $generated generated, $skipped skipped (already existed)"
echo "tsx dir: $TS_DIR"
