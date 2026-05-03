#!/usr/bin/env bash
# 概要: Claude から Codex に質問を投げて回答を受け取る、自前のブリッジスクリプト。
#       OMC など外部プラグインに依存せず、`codex exec` を直接呼ぶ。
#
# 使い方:
#   codex-ask.sh "プロンプト"                              # 引数モード
#   echo "プロンプト" | codex-ask.sh                       # 標準入力モード
#   codex-ask.sh --role architect "..."                    # 役割を指定
#   codex-ask.sh --model gpt-5.3-codex "..."               # モデル指定
#   codex-ask.sh --context file1 file2 -- "..."            # 文脈ファイル
#   codex-ask.sh --json --schema schema.json "..."         # JSON 構造化出力
#   codex-ask.sh --out reply.md "..."                      # 標準出力ではなくファイル保存
#   codex-ask.sh --image "logo, minimalist" --image-out logo.png  # gpt-image-2 で画像生成
#
# 役割（--role）:
#   architect / critic / analyst / planner / code-reviewer / security-reviewer / designer / tdd

set -euo pipefail

# ===== デフォルト =====
ROLE=""
MODEL="${CODEX_MODEL:-gpt-5.3-codex}"
SANDBOX="workspace-write"
CONTEXT_FILES=()
JSON_MODE=""
SCHEMA_FILE=""
OUT_FILE=""
IMAGE_PROMPT=""
IMAGE_OUT=""

# ===== 引数パース =====
PARSE_CONTEXT=0
while [[ $# -gt 0 ]]; do
  if [ "$PARSE_CONTEXT" -eq 1 ]; then
    if [ "$1" = "--" ]; then
      PARSE_CONTEXT=0
      shift
      continue
    fi
    CONTEXT_FILES+=("$1")
    shift
    continue
  fi
  case "$1" in
    --role)        ROLE="$2";        shift 2 ;;
    --model)       MODEL="$2";       shift 2 ;;
    --sandbox)     SANDBOX="$2";     shift 2 ;;
    --context)     PARSE_CONTEXT=1;  shift ;;
    --json)        JSON_MODE=1;      shift ;;
    --schema)      SCHEMA_FILE="$2"; shift 2 ;;
    --out)         OUT_FILE="$2";    shift 2 ;;
    --image)       IMAGE_PROMPT="$2"; shift 2 ;;
    --image-out)   IMAGE_OUT="$2";   shift 2 ;;
    --help|-h)
      sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# ===== Codex CLI 存在確認 =====
if ! command -v codex >/dev/null 2>&1; then
  echo "::error:: codex CLI が見つかりません。インストール: npm i -g @openai/codex" >&2
  exit 127
fi

# ===== 画像生成モード =====
if [ -n "$IMAGE_PROMPT" ]; then
  if [ -z "$IMAGE_OUT" ]; then
    echo "::error:: --image-out で出力先パスを指定してください" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$IMAGE_OUT")"
  TMP_IMG_PROMPT=$(mktemp)
  trap 'rm -f "$TMP_IMG_PROMPT"' EXIT
  cat > "$TMP_IMG_PROMPT" <<EOS
gpt-image-2 を使って次のプロンプトで画像を生成し、結果を $IMAGE_OUT に保存してください。
プロンプト: $IMAGE_PROMPT

完了後、保存したファイルパスのみを 1 行で出力してください。
EOS
  codex exec --model "$MODEL" --sandbox "$SANDBOX" - < "$TMP_IMG_PROMPT"
  exit 0
fi

# ===== プロンプト構築 =====
TMP_PROMPT=$(mktemp)
trap 'rm -f "$TMP_PROMPT"' EXIT

if [ ! -t 0 ]; then
  cat > "$TMP_PROMPT"
elif [ $# -gt 0 ]; then
  printf '%s\n' "$*" > "$TMP_PROMPT"
else
  echo "::error:: プロンプトが渡されていません（引数 or stdin で指定）" >&2
  exit 1
fi

# ===== 役割プレフィックス =====
add_role_prefix() {
  local role="$1"
  local prefix=""
  case "$role" in
    architect)        prefix="あなたはシステムアーキテクトです。設計の妥当性、トレードオフ、長期保守性、依存方向、境界の観点で答えてください。" ;;
    critic)           prefix="あなたは批判的レビュアです。前提を疑い、見落としや誤りを指摘し、代替案を提示してください。" ;;
    analyst)          prefix="あなたは要件アナリストです。あいまいさ・矛盾・受け入れ基準の欠落を抽出し、明確化質問を投げてください。" ;;
    planner)          prefix="あなたはプロジェクトプランナです。実行可能な順序、依存、リスク、マイルストーンを整理してください。" ;;
    code-reviewer)    prefix="あなたはコードレビュアです。バグ・パフォーマンス・保守性・命名・テスト網羅性の問題を指摘してください。" ;;
    security-reviewer) prefix="あなたはセキュリティレビュアです。OWASP Top 10 / 認証・認可 / 入力検証 / 機密管理 / 監査の観点で診断してください。" ;;
    designer)         prefix="あなたは UI/UX デザイナです。配色、タイポ、情報設計、アクセシビリティ、操作性の観点で改善提案してください。" ;;
    tdd)              prefix="あなたは TDD コーチです。テスト先行・最小実装・リファクタの順を保証してください。" ;;
    "") return 0 ;;
    *) prefix="あなたは $role です。役割に沿って回答してください。" ;;
  esac
  local NEW=$(mktemp)
  {
    echo "# 役割"
    echo "$prefix"
    echo
    echo "# 質問"
    cat "$TMP_PROMPT"
  } > "$NEW"
  mv "$NEW" "$TMP_PROMPT"
}
add_role_prefix "$ROLE"

# ===== 文脈ファイルを末尾に添付 =====
if [ "${#CONTEXT_FILES[@]}" -gt 0 ]; then
  {
    echo
    echo "# 参考ファイル"
    for f in "${CONTEXT_FILES[@]}"; do
      [ -f "$f" ] || { echo "::warning:: $f が見つかりません" >&2; continue; }
      echo
      echo "## $f"
      echo '```'
      cat "$f"
      echo '```'
    done
  } >> "$TMP_PROMPT"
fi

# ===== Codex 実行 =====
ARGS=(exec --model "$MODEL" --sandbox "$SANDBOX")
[ -n "$JSON_MODE" ]    && ARGS+=(--json)
[ -n "$SCHEMA_FILE" ]  && ARGS+=(--output-schema "$SCHEMA_FILE")

if [ -n "$OUT_FILE" ]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  codex "${ARGS[@]}" - < "$TMP_PROMPT" > "$OUT_FILE"
  echo "[codex-ask] 回答を $OUT_FILE に保存しました" >&2
else
  codex "${ARGS[@]}" - < "$TMP_PROMPT"
fi
