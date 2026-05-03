#!/usr/bin/env bash
# 概要: Claude から Codex に質問を投げて回答を受け取る、自前のブリッジスクリプト。
#       OMC など外部プラグインに依存せず、`codex exec` を直接呼ぶ。
#       --session KEY を指定すると Codex 側で session を維持し、真のマルチターン対話になる。
#
# 使い方:
#   codex-ask.sh "プロンプト"                                    # one-shot（session なし）
#   codex-ask.sh --session brainstorm "..."                       # session 維持（初回は新規、2 回目以降は resume）
#   codex-ask.sh --session brainstorm --reset-session             # session を破棄
#   codex-ask.sh --role architect "..."                           # 役割プレフィックス
#   codex-ask.sh --context f1 f2 -- "..."                         # 文脈ファイル添付
#   codex-ask.sh --out reply.md "..."                             # 結果をファイル保存
#   codex-ask.sh --image "logo, vector" --image-out logo.png      # gpt-image-2 で画像生成
#   codex-ask.sh --log session.jsonl --session brainstorm "..."   # JSONL 全イベントを保存
#
# session ファイルの場所:
#   既定: ./.codex-sessions/<KEY>.id
#   --session-dir で変更可
#
# 役割（--role）:
#   architect / critic / analyst / planner / code-reviewer / security-reviewer / designer / tdd

set -euo pipefail

# ===== デフォルト =====
ROLE=""
MODEL="${CODEX_MODEL:-gpt-5.3-codex}"
SANDBOX="workspace-write"
CONTEXT_FILES=()
OUT_FILE=""
LOG_FILE=""
IMAGE_PROMPT=""
IMAGE_OUT=""
SESSION_KEY=""
SESSION_DIR="${CODEX_SESSION_DIR:-./.codex-sessions}"
RESET_SESSION=0

# ===== 引数パース =====
PARSE_CONTEXT=0
while [[ $# -gt 0 ]]; do
  if [ "$PARSE_CONTEXT" -eq 1 ]; then
    if [ "$1" = "--" ]; then PARSE_CONTEXT=0; shift; continue; fi
    CONTEXT_FILES+=("$1"); shift; continue
  fi
  case "$1" in
    --role)            ROLE="$2";          shift 2 ;;
    --model)           MODEL="$2";         shift 2 ;;
    --sandbox)         SANDBOX="$2";       shift 2 ;;
    --context)         PARSE_CONTEXT=1;    shift ;;
    --out)             OUT_FILE="$2";      shift 2 ;;
    --log)             LOG_FILE="$2";      shift 2 ;;
    --image)           IMAGE_PROMPT="$2";  shift 2 ;;
    --image-out)       IMAGE_OUT="$2";     shift 2 ;;
    --session)         SESSION_KEY="$2";   shift 2 ;;
    --session-dir)     SESSION_DIR="$2";   shift 2 ;;
    --reset-session)   RESET_SESSION=1;    shift ;;
    --help|-h)
      sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# ===== プロジェクトの .harness-init/.config から session を自動解決 =====
#       cwd（または親ディレクトリ）に .harness-init/.config があり、CODEX_SESSION が定義されていれば
#       --session 未指定時に自動採用する。これで Claude が毎回 --session を書かなくても
#       同じ session が resume され続ける。
auto_resolve_session() {
  local current_dir="$PWD"
  while [ "$current_dir" != "/" ] && [ -n "$current_dir" ]; do
    if [ -f "$current_dir/.harness-init/.config" ]; then
      # shellcheck disable=SC1091
      local cfg_session
      cfg_session=$(grep -E "^CODEX_SESSION=" "$current_dir/.harness-init/.config" 2>/dev/null | head -1 | cut -d= -f2-)
      if [ -n "$cfg_session" ]; then
        if [ -z "$SESSION_KEY" ]; then
          SESSION_KEY="$cfg_session"
          echo "[codex-ask] session を .harness-init/.config から自動解決: $SESSION_KEY" >&2
        fi
        if [ "$SESSION_DIR" = "./.codex-sessions" ]; then
          SESSION_DIR="$current_dir/.harness-init/codex-sessions"
        fi
      fi
      return 0
    fi
    current_dir=$(dirname "$current_dir")
  done
}
auto_resolve_session

# ===== --reset-session 単独（Codex CLI 不要、純粋なファイル操作なので先に実行）=====
if [ "$RESET_SESSION" -eq 1 ]; then
  if [ -z "$SESSION_KEY" ]; then
    echo "::error:: --reset-session には --session KEY が必須です（または .harness-init/.config が必要）" >&2
    exit 1
  fi
  rm -f "$SESSION_DIR/$SESSION_KEY.id"
  echo "[codex-ask] session '$SESSION_KEY' を破棄しました" >&2
  exit 0
fi

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
  echo "::error:: プロンプトが渡されていません（引数 or stdin）" >&2
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
    designer)         prefix="あなたは UI/UX デザイナです。配色、タイポ、情報設計、アクセシビリティ、操作性で改善提案してください。" ;;
    tdd)              prefix="あなたは TDD コーチです。テスト先行・最小実装・リファクタの順を保証してください。" ;;
    "") return 0 ;;
    *) prefix="あなたは $role です。役割に沿って回答してください。" ;;
  esac
  local NEW=$(mktemp)
  { echo "# 役割"; echo "$prefix"; echo; echo "# 質問"; cat "$TMP_PROMPT"; } > "$NEW"
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

# ===== JSONL から assistant の最終メッセージだけを抽出（jq があれば使う、無ければ簡易抽出） =====
extract_assistant_text() {
  local jsonl="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r 'select(.type=="agent_message" or .type=="message" or .type=="assistant_message") | .content // .message // empty' "$jsonl" 2>/dev/null \
      | grep -v '^$' | tail -1
  else
    grep -oE '"content":"[^"]*"' "$jsonl" | tail -1 | sed 's/"content":"//; s/"$//'
  fi
}

# ===== JSONL から session_id を抽出 =====
extract_session_id() {
  local jsonl="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r 'select(.session_id) | .session_id' "$jsonl" 2>/dev/null | head -1
  else
    grep -oE '"session_id":"[^"]+"' "$jsonl" | head -1 | sed 's/"session_id":"//; s/"$//'
  fi
}

# ===== Codex 実行 =====
TMP_LOG=$(mktemp)
APPEND_TRAP="rm -f \"$TMP_PROMPT\" \"$TMP_LOG\""
trap "$APPEND_TRAP" EXIT

PROMPT_TEXT=$(cat "$TMP_PROMPT")

if [ -n "$SESSION_KEY" ]; then
  mkdir -p "$SESSION_DIR"
  SESSION_FILE="$SESSION_DIR/$SESSION_KEY.id"

  if [ -f "$SESSION_FILE" ]; then
    SESSION_ID=$(cat "$SESSION_FILE")
    echo "[codex-ask] session '$SESSION_KEY' を resume (id=$SESSION_ID)" >&2
    codex exec resume "$SESSION_ID" --json --model "$MODEL" --sandbox "$SANDBOX" "$PROMPT_TEXT" \
      2>"$TMP_LOG.err" | tee "$TMP_LOG" >/dev/null
  else
    echo "[codex-ask] session '$SESSION_KEY' を新規作成" >&2
    codex exec --json --model "$MODEL" --sandbox "$SANDBOX" "$PROMPT_TEXT" \
      2>"$TMP_LOG.err" | tee "$TMP_LOG" >/dev/null
    NEW_ID=$(extract_session_id "$TMP_LOG")
    if [ -z "$NEW_ID" ]; then
      # フォールバック: ~/.codex/sessions の直近 jsonl からファイル名で取得
      NEW_ID=$(find "${HOME}/.codex/sessions" -name "*.jsonl" -mmin -1 2>/dev/null \
        | xargs -I{} basename {} .jsonl 2>/dev/null | head -1)
    fi
    if [ -n "$NEW_ID" ]; then
      echo "$NEW_ID" > "$SESSION_FILE"
      echo "[codex-ask] session id を $SESSION_FILE に保存" >&2
    else
      echo "::warning:: session ID を取得できませんでした。次回も新規 session になります。" >&2
    fi
  fi
else
  # session 維持しない one-shot
  codex exec --json --model "$MODEL" --sandbox "$SANDBOX" "$PROMPT_TEXT" \
    2>"$TMP_LOG.err" | tee "$TMP_LOG" >/dev/null
fi

# ===== ログ保存 =====
if [ -n "$LOG_FILE" ]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  cp "$TMP_LOG" "$LOG_FILE"
  echo "[codex-ask] JSONL ログを $LOG_FILE に保存" >&2
fi

# ===== 標準出力には assistant の本文のみを出す =====
ASSISTANT_TEXT=$(extract_assistant_text "$TMP_LOG")

if [ -z "$ASSISTANT_TEXT" ]; then
  echo "::warning:: assistant の本文を抽出できませんでした。--log で JSONL を保存してご確認ください。" >&2
  cat "$TMP_LOG" >&2
  exit 1
fi

if [ -n "$OUT_FILE" ]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf '%s\n' "$ASSISTANT_TEXT" > "$OUT_FILE"
  echo "[codex-ask] 回答を $OUT_FILE に保存" >&2
else
  printf '%s\n' "$ASSISTANT_TEXT"
fi
