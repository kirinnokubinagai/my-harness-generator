#!/usr/bin/env bash
# 概要: Claude から Codex に質問を投げて回答を受け取る、自前のブリッジスクリプト。
#       OMC など外部プラグインに依存せず、`codex exec` を直接呼ぶ。
#       --session KEY を指定すると Codex 側で session を維持し、真のマルチターン対話になる。
#
#       画像生成・モデル選択などは codex 側の機能なので、Claude が普通の対話で
#       「〇〇のロゴを <path> に保存してください」と頼むだけで OK。本ブリッジは余計なことをしない。
#
# 使い方:
#   codex-ask.sh "プロンプト"                                    # one-shot（session なし）
#   codex-ask.sh --session brainstorm "..."                       # session 維持（初回新規、2 回目以降 resume）
#   codex-ask.sh --session brainstorm --reset-session             # session を破棄
#   codex-ask.sh --role architect "..."                           # 役割プレフィックス
#   codex-ask.sh --context f1 f2 -- "..."                         # 文脈ファイル添付
#   codex-ask.sh --out reply.md "..."                             # 結果をファイル保存
#   codex-ask.sh --log session.jsonl --session brainstorm "..."   # JSONL 全イベントを保存
#   codex-ask.sh --set-active <project-root>                      # active session pointer を登録
#   codex-ask.sh --clear-active                                   # active pointer を破棄
#
# 役割（--role）:
#   architect / critic / analyst / planner / code-reviewer / security-reviewer / designer / tdd
#   engineer / e2e-reviewer / harness-reviewer  ← harness の subagent から委譲する用

set -euo pipefail

# ===== デフォルト =====
ROLE=""
MODEL=""        # 既定は空（Codex CLI のデフォルトモデルに任せる）
SANDBOX=""      # 既定は空（Codex CLI のデフォルトサンドボックス設定に任せる）
CONTEXT_FILES=()
OUT_FILE=""
LOG_FILE=""
SESSION_KEY=""
SESSION_DIR="${CODEX_SESSION_DIR:-./.codex-sessions}"
RESET_SESSION=0
SET_ACTIVE_PROJECT=""
CLEAR_ACTIVE=0
ACTIVE_POINTER="${CODEX_ACTIVE_POINTER:-$HOME/.codex-active-session}"

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
    --session)         SESSION_KEY="$2";   shift 2 ;;
    --session-dir)     SESSION_DIR="$2";   shift 2 ;;
    --reset-session)   RESET_SESSION=1;    shift ;;
    --set-active)      SET_ACTIVE_PROJECT="$2"; shift 2 ;;
    --clear-active)    CLEAR_ACTIVE=1;     shift ;;
    --help|-h)
      sed -n '1,/^set -euo pipefail/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# ===== --set-active / --clear-active 単独（Codex CLI 不要、純粋なファイル操作）=====
if [ "$CLEAR_ACTIVE" -eq 1 ]; then
  rm -f "$ACTIVE_POINTER"
  echo "[codex-ask] active session pointer を破棄: $ACTIVE_POINTER" >&2
  exit 0
fi
if [ -n "$SET_ACTIVE_PROJECT" ]; then
  ABS_PATH=$(cd "$SET_ACTIVE_PROJECT" 2>/dev/null && pwd) || {
    echo "::error:: --set-active のパスが存在しません: $SET_ACTIVE_PROJECT" >&2
    exit 1
  }
  if [ ! -f "$ABS_PATH/.my-harness/.config" ]; then
    echo "::error:: $ABS_PATH/.my-harness/.config が見つかりません（先に bootstrap しましたか？）" >&2
    exit 1
  fi
  printf '%s\n' "$ABS_PATH" > "$ACTIVE_POINTER"
  echo "[codex-ask] active session を設定: $ABS_PATH" >&2
  exit 0
fi

# ===== session 自動解決 =====
#       優先順位:
#       (1) --session が明示されている → それを使う
#       (2) ~/.codex-active-session に書かれたプロジェクトの .my-harness/.config（グローバルポインタ）
#       (3) cwd（および親ディレクトリ）の .my-harness/.config
load_config_from() {
  local project_root="$1"
  local cfg="$project_root/.my-harness/.config"
  [ -f "$cfg" ] || return 1
  local cfg_session
  cfg_session=$(grep -E "^CODEX_SESSION=" "$cfg" 2>/dev/null | head -1 | cut -d= -f2-)
  [ -n "$cfg_session" ] || return 1
  if [ -z "$SESSION_KEY" ]; then
    SESSION_KEY="$cfg_session"
  fi
  if [ "$SESSION_DIR" = "./.codex-sessions" ]; then
    SESSION_DIR="$project_root/.my-harness/codex-sessions"
  fi
  return 0
}

auto_resolve_session() {
  if [ -n "$SESSION_KEY" ]; then return 0; fi
  if [ -f "$ACTIVE_POINTER" ]; then
    local active_root
    active_root=$(head -1 "$ACTIVE_POINTER" 2>/dev/null)
    if [ -n "$active_root" ] && load_config_from "$active_root"; then
      echo "[codex-ask] session を active pointer から自動解決: $SESSION_KEY (project: $active_root)" >&2
      return 0
    fi
  fi
  local current_dir="$PWD"
  while [ "$current_dir" != "/" ] && [ -n "$current_dir" ]; do
    if load_config_from "$current_dir"; then
      echo "[codex-ask] session を cwd 配下から自動解決: $SESSION_KEY (project: $current_dir)" >&2
      return 0
    fi
    current_dir=$(dirname "$current_dir")
  done
}
auto_resolve_session

# ===== --reset-session 単独 =====
if [ "$RESET_SESSION" -eq 1 ]; then
  if [ -z "$SESSION_KEY" ]; then
    echo "::error:: --reset-session には --session KEY が必須です（または .my-harness/.config が必要）" >&2
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

# ===== ACTIVE_ROOT を捕捉（rescue state 保存先の特定用）=====
ACTIVE_ROOT=""
if [ -f "$ACTIVE_POINTER" ]; then
  ACTIVE_ROOT=$(head -1 "$ACTIVE_POINTER" 2>/dev/null)
fi

# ===== Codex 認証エラー時の rescue state 保存 =====
#       認証切れを検出したら、現在の依頼内容（session / role / prompt / context）を
#       JSON + .prompt.txt として `<root>/.my-harness/codex-auth-rescue/` に保存し、
#       team-lead が `codex login` 後に同 session で resume できるようにする。
save_codex_auth_rescue() {
  local reason="$1"
  if [ -z "$ACTIVE_ROOT" ] || [ ! -d "$ACTIVE_ROOT/.my-harness" ]; then
    echo "::warning:: rescue state を保存する root が不明です（--set-active 未実行?）" >&2
    return
  fi
  local rescue_dir="$ACTIVE_ROOT/.my-harness/codex-auth-rescue"
  mkdir -p "$rescue_dir"
  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)-$$
  local rescue_json="$rescue_dir/$stamp.json"
  local rescue_prompt="$rescue_dir/$stamp.prompt.txt"
  if [ -f "$TMP_PROMPT" ]; then
    cp "$TMP_PROMPT" "$rescue_prompt" 2>/dev/null || rescue_prompt=""
  else
    rescue_prompt=""
  fi
  # JSON はメタデータのみ（prompt 本文は別ファイル）
  {
    echo '{'
    echo "  \"reason\": \"$reason\","
    echo "  \"session_key\": \"${SESSION_KEY:-}\","
    echo "  \"session_id\": \"${SESSION_ID:-}\","
    echo "  \"role\": \"${ROLE:-}\","
    echo "  \"out_file\": \"${OUT_FILE:-}\","
    echo "  \"log_file\": \"${LOG_FILE:-}\","
    echo "  \"prompt_path\": \"$rescue_prompt\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    echo '}'
  } > "$rescue_json"
  echo "::error:: Codex 認証エラー（$reason）。rescue state を保存しました:" >&2
  echo "  $rescue_json" >&2
  echo "  ユーザーは \`codex login\` 後に team-lead に「resume」と指示してください。" >&2
}

# ===== Pre-flight 認証チェック =====
#       codex exec を呼ぶ前に check-codex-auth.sh で OAuth 状態を確認。
#       not-logged-in なら rescue state を保存して exit 100。
CHECK_AUTH="${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/check-codex-auth.sh"
if [ -x "$CHECK_AUTH" ]; then
  AUTH_STATE=$("$CHECK_AUTH" 2>/dev/null || true)
  if [ "$AUTH_STATE" != "logged-in" ]; then
    : "${TMP_PROMPT:=}"  # rescue 関数で参照される変数を事前定義（保存内容は空でも OK）
    save_codex_auth_rescue "preflight-$AUTH_STATE"
    exit 100
  fi
fi

# ===== プロンプト構築 =====
TMP_PROMPT=$(mktemp)
TMP_LOG=$(mktemp)
trap 'rm -f "$TMP_PROMPT" "$TMP_LOG"' EXIT

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
    architect)         prefix="あなたはシステムアーキテクトです。設計の妥当性、トレードオフ、長期保守性、依存方向、境界の観点で答えてください。" ;;
    critic)            prefix="あなたは批判的レビュアです。前提を疑い、見落としや誤りを指摘し、代替案を提示してください。" ;;
    analyst)           prefix="あなたは要件アナリストです。あいまいさ・矛盾・受け入れ基準の欠落を抽出し、明確化質問を投げてください。" ;;
    planner)           prefix="あなたはプロジェクトプランナです。実行可能な順序、依存、リスク、マイルストーンを整理してください。" ;;
    code-reviewer)     prefix="あなたはコードレビュアです。バグ・パフォーマンス・保守性・命名・テスト網羅性の問題を指摘してください。" ;;
    security-reviewer) prefix="あなたはセキュリティレビュアです。OWASP Top 10 / 認証・認可 / 入力検証 / 機密管理 / 監査の観点で診断してください。" ;;
    designer)          prefix="あなたは UI/UX デザイナです。配色、タイポ、情報設計、アクセシビリティ、操作性で改善提案してください。必要なら gpt-image-2 等で画像も生成してください。" ;;
    tdd)               prefix="あなたは TDD コーチです。テスト先行・最小実装・リファクタの順を保証してください。" ;;
    engineer)          prefix="あなたは harness の TypeScript/Hono エンジニアです。以下を厳守して実装してください: (1) TDD: 失敗するテストを先に書き、赤を確認してから最小実装。(2) Hono Clean Architecture: domain ← application ← infrastructure / interfaces の依存方向を厳守。(3) Nix pure: 全ツール実行は \`nix develop --command\` 経由。\`brew install\` 等の impure コマンド禁止。(4) JSDoc/TSDoc を全 export に必須、関数内コメント禁止、説明文は日本語。(5) Drizzle migrate-only: \`drizzle-kit push\` 絶対禁止、必ず \`drizzle-kit generate --name <descriptive>\` → \`migrate\`。(6) Biome 規約遵守。(7) コンフリクトは merge コミットのみで解消、rebase / reset --hard / push --force 禁止。" ;;
    e2e-reviewer)      prefix="あなたは E2E テストレビュアです。Playwright (Web) または Maestro (モバイル) でユーザーフローを検証し、結果を構造化して報告してください: (1) 影響判定: 変更が E2E に影響するか (yes/no)。(2) 実行結果: 各テストケースの pass/fail。(3) 失敗時: 具体的な再現手順とスクリーンショットの保存パス。(4) 推奨アクション: 通過 → マージ可、失敗 → 具体的な修正提案。AI 風モックではなく実機相当の検証を行ってください。" ;;
    harness-reviewer)  prefix="あなたは harness 規約レビュアです。コード変更を以下の観点で精査し、違反があれば file:line 単位で指摘してください: (1) 命名規約: camelCase 変数/関数、PascalCase 型/クラス、UPPER_SNAKE_CASE 定数、kebab-case ファイル。(2) JSDoc/TSDoc が全 export に付いているか。(3) 関数内コメント禁止。(4) Hono Clean Architecture の依存方向。(5) Nix pure (impure コマンド未使用)。(6) Lucide Icons のみ (絵文字・他アイコンライブラリ禁止)。(7) Drizzle migrate-only。(8) Zod バリデーション (API/フォーム入力)。(9) WCAG AA 準拠 (色コントラスト・aria-label)。(10) any 型・else 文・console.log・ハードコード機密の不在。違反 0 件なら明示的に \`PASS\` を出力。" ;;
    "") return 0 ;;
    *) prefix="あなたは $role です。役割に沿って回答してください。" ;;
  esac
  local NEW
  NEW=$(mktemp)
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

# ===== JSONL から assistant の最終メッセージだけを抽出 =====
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

# ===== Codex 実行用の共通フラグ =====
#       --model / --sandbox はユーザー明示時のみ付与（既定は Codex CLI に任せる）
COMMON_FLAGS=(--json)
[ -n "$MODEL" ]   && COMMON_FLAGS+=(--model "$MODEL")
[ -n "$SANDBOX" ] && COMMON_FLAGS+=(--sandbox "$SANDBOX")

# ===== Codex 実行 =====
PROMPT_TEXT=$(cat "$TMP_PROMPT")

if [ -n "$SESSION_KEY" ]; then
  mkdir -p "$SESSION_DIR"
  SESSION_FILE="$SESSION_DIR/$SESSION_KEY.id"

  if [ -f "$SESSION_FILE" ]; then
    SESSION_ID=$(cat "$SESSION_FILE")
    echo "[codex-ask] session '$SESSION_KEY' を resume (id=$SESSION_ID)" >&2
    # codex CLI syntax: `codex exec resume [OPTIONS] [SESSION_ID] [PROMPT]`
    # オプションを positional args より前に置かないと clap が誤解釈する可能性あり
    codex exec resume "${COMMON_FLAGS[@]}" "$SESSION_ID" "$PROMPT_TEXT" \
      2>"$TMP_LOG.err" | tee "$TMP_LOG" >/dev/null
  else
    echo "[codex-ask] session '$SESSION_KEY' を新規作成" >&2
    codex exec "${COMMON_FLAGS[@]}" "$PROMPT_TEXT" \
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
  codex exec "${COMMON_FLAGS[@]}" "$PROMPT_TEXT" \
    2>"$TMP_LOG.err" | tee "$TMP_LOG" >/dev/null
fi

# ===== Post-exec 認証 / サブスク エラー検出 =====
#       実行中に発生する 2 種類の障害を区別して拾う:
#       (a) login-expired   : OAuth トークンが無効/期限切れ → codex login で復旧
#       (b) subscription-or-quota : サブスク失効 / quota 超過 / billing → 別対応必要
if [ -f "$TMP_LOG.err" ]; then
  # サブスク / quota / billing を先に判定（login エラーより優先度高、誤分類防止）
  if grep -iE "subscription.*(expired|required|cancel|inactive)|no active subscription|plan.*(required|expired|inactive)|quota.*(exceeded|reached)|billing.*(required|issue|past due|invalid)|insufficient.*(quota|credit|funds)|payment.*required|usage.*limit.*(exceeded|reached)" \
       "$TMP_LOG.err" >/dev/null 2>&1; then
    save_codex_auth_rescue "subscription-or-quota"
    exit 100
  fi
  # 次に login / 認証トークン関連
  if grep -iE "not logged in|please log in|please run.*codex login|authentication failed|api key.*(required|missing|invalid)|unauthorized|401 [^0-9]|expired.*(token|session|credential)|invalid_grant|oauth.*(failed|invalid)" \
       "$TMP_LOG.err" >/dev/null 2>&1; then
    save_codex_auth_rescue "login-expired"
    exit 100
  fi
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
