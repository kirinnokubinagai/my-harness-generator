---
name: my-harness-init
description: Runs the full new-project pipeline end-to-end: interview → spec generation → harness auto-setup. Claude asks only the minimum direct questions, optionally consults Codex for a second opinion, generates logos and UI mocks via Codex using gpt-image-2, then runs bootstrap.sh in non-interactive mode to launch the project. Fires when the user runs /my-harness-init or wants to start a new project from scratch.
---

# /my-harness-init

## Installation & Quick start

### Prerequisites

- **Claude Code** (latest) — the agent that runs this plugin
- **git**, **bash**, **jq** — standard Unix tools, must be on `PATH`
- **direnv** — for automatic Nix shell activation (`brew install direnv` or `nix profile install nixpkgs#direnv`)
- **Optional:** Codex CLI for AI-assisted design and second-opinion reviews:
  ```bash
  npm install -g @openai/codex
  codex login
  ```

### Install the plugin

Inside Claude Code, run:

```
/plugin marketplace add https://github.com/kirinnokubinagai/my-harness-generator
/plugin install my-harness@my-harness-generator
```

### Activate the new skills

Restart Claude Code (or run `/clear` in the current session) so that the newly registered skills and hooks are loaded.

### Start a new project

```
/my-harness-init
```

Claude will guide you through the interview phase one question at a time. If `.my-harness/init-state.json` already exists in the current directory (or a parent), the skill auto-detects it and offers to resume from where you left off.

### Keeping the plugin up to date

```
/plugin marketplace update
```

> **Never `git clone` this repository to use the plugin.** Cloning freezes you to a single revision and bypasses the plugin update mechanism. Always install and update through the Claude Code plugin commands above.

---

A slash command that starts from "I have a vague idea of what to build" and, through conversation, locks in **only the information needed to set up the system**, then **immediately builds the harness** from that spec.

## Design principles

- **Only ask about things that directly determine system decisions.** Marketing, brand strategy, and long-term vision are off-limits.
- **Keep questions concrete.** If Claude improvises abstract questions ("brand world-view", "tone", "device focus", etc.), conversations balloon unnecessarily. The SKILL.md fixes the exact question wording.
- **One question per turn.** Batch questions are prohibited.
- **Offer easy-to-answer choices.** Prefer y/n or enumerated options over free-text answers.

## Who executes this skill

This skill is a procedure that **Claude (you)** executes. Codex is an external supplementary LLM — Claude calls it by **launching `codex-ask.sh` via Bash**, reads the response, and incorporates it. Codex does not interact with the user directly on Claude's behalf.

## Prerequisites

- `~/my-harness-generator/scripts/bootstrap.sh` exists
- For Codex integration only: `~/my-harness-generator/scripts/codex-ask.sh` and `check-codex-auth.sh` exist and are executable

## Persistent artifact layout (under the project root)

| Directory | Purpose | Git-tracked |
|-----------|---------|-------------|
| `<root>/dev/docs/spec/` | Spec documents | Yes |
| `<root>/dev/docs/design/` | Logos / OG images / UI mocks | Yes |
| `<root>/dev/docs/talk/` | Conversation logs (masked) | Yes |
| `<root>/dev/docs/task/` | Tasks (when USE_GITHUB_ISSUES=no) | Yes |
| `<root>/.my-harness/` | Internal work files (Codex session IDs, etc.) | Excluded via gitignore |

## Secret masking (strictly enforced)

If any of the following appear in user conversation, they must be masked before writing to any file:

| Type | Masked as |
|------|-----------|
| API keys / tokens (`sk-...`, `sk-ant-...`, `ghp_...`, `xoxb-...`, etc.) | `<MASKED:api-key>` |
| AWS access keys (`AKIA...`) | `<MASKED:aws-key>` |
| Passwords | `<MASKED:password>` |
| Email addresses (personally identifiable) | `<MASKED:email>` |
| Credentials embedded in URLs (`https://user:pass@...`) | `<MASKED:url-cred>` |
| Phone numbers | `<MASKED:phone>` |
| Credit card numbers | `<MASKED:cc>` |
| PEM private keys | `<MASKED:private-key>` |
| JWT three-part dot strings | `<MASKED:jwt>` |

Apply before writing to `docs/talk/` or `docs/spec/`. When in doubt, confirm with the user. The git pre-commit hook with `gitleaks` + `check-forbidden-patterns.sh` provides a second layer of defense.

## Flow (5 phases)

For each phase:
1. Ask the user **only the fixed questions below**, one per turn
2. Append the response (after masking) to both `docs/spec/<phase>.md` and `docs/talk/<phase>.md`
3. If USE_CODEX=yes and at the end of the phase, run one Codex consult (optional, not mandatory)
4. At the end of the phase, confirm with the user: "Ready to continue?"
5. **Update `<root>/.my-harness/init-state.json`** (for pause/resume support)

### Managing init-state.json (for pause/resume)

At the completion of each phase, always write the following. `current_phase` is the **next** phase name to advance to; `phases_completed` is the list of **already finished** phase names:

```bash
# Example: after Phase 2 (platform) completes → next is backend
ROOT=<root>
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$ROOT/.my-harness"
cat > "$ROOT/.my-harness/init-state.json" <<EOF
{
  "schema_version": "1",
  "project_name": "<PROJECT_NAME>",
  "lang": "en",
  "root": "$ROOT",
  "current_phase": "backend",
  "phases_completed": ["language", "setup", "what", "platform"],
  "next_action": "interview",
  "next_action_command": "Continue /my-harness-init (Phase 3: backend)",
  "working_directory": "$ROOT",
  "timestamp": "$TIMESTAMP"
}
EOF
```

Phase names (in order):
- `language` → `setup` → `what` → `platform` → `backend` → `data-model` → `visual` → `bootstrap` → `tasks` → `completed`

`data-model` is skipped when USE_DB=no. bootstrap.sh writes the state automatically (`current_phase: "bootstrap-completed"`).

### Pause/resume support

When the user says "pause for a bit", "stop", or similar:
- Update `init-state.json` to the latest state at the current phase boundary, tell the user where it was saved and what command to resume with, then stop.

When the user comes back (e.g. runs `/my-harness-init` again):
- Read `<root>/.my-harness/init-state.json` and check `current_phase`
- Resume from the first question of that phase (existing docs/spec and docs/talk are carried forward)

---

### At startup: auto-detecting init-state.json

When `/my-harness-init` is called, **first** check whether `.my-harness/init-state.json` exists in the user's cwd or any parent directory:

```bash
find_existing_state() {
  local d="$PWD"
  for _ in 1 2 3 4 5; do
    if [ -f "$d/.my-harness/init-state.json" ]; then
      echo "$d/.my-harness/init-state.json"
      return 0
    fi
    d=$(dirname "$d")
  done
  return 1
}
```

If found:
1. Read `current_phase`
2. Ask the user: "You were last at the `<current_phase>` phase. Resume from where you left off? (y/n)"
3. y → Resume from the first question of that phase (continue using existing `docs/spec/` and `docs/talk/`)
4. n → Confirm with the user (discard and start fresh, or specify a different directory)

If not found: proceed to Phase 0 below as a new init.

---

### Phase 0: Language (new init only)

**First question:**

> "Should I speak Japanese with you, or English? (`en` or `ja`, default `en`)"

- `en`: All output in English (TSDoc, commit messages, error messages, docs — all in English)
- `ja`: All output in Japanese (TSDoc, commit messages, error messages, docs — all in Japanese)

From this point, all conversation, all generated docs, JSDoc text, error messages, and issue templates use the chosen language. **Every prompt in Phase 1 and beyond must be delivered in the language chosen here.**

**Acknowledgment after Phase 0 (language-aware — pick the matching variant):**

- If `LANG=en`:
  > "Got it — I'll continue in English from here. Let's move on to the setup questions."
- If `LANG=ja`:
  > "はい、ここから先は日本語で進めます。では、セットアップの質問に移ります。"

Save to `.my-harness/.config` (first entry, before all other keys):
```bash
LANG=<en|ja>
```

Update `init-state.json`:
```bash
cat > "$ROOT/.my-harness/init-state.json" <<EOF
{
  "schema_version": "1",
  "project_name": "",
  "lang": "${LANG:-en}",
  "root": "$ROOT",
  "current_phase": "setup",
  "phases_completed": ["language"],
  "next_action": "interview",
  "next_action_command": "Continue /my-harness-init (Phase: setup)",
  "working_directory": "$ROOT",
  "timestamp": "$TIMESTAMP"
}
EOF
```

---

### Setup phase (startup + selections, new init only)

Confirm each of the following **one question at a time**. For each question, use the **`LANG=en`** block when `LANG=en`, and the **`LANG=ja`** block when `LANG=ja`.

---

#### Setup Q1: Project root directory

**LANG=en prompt:**
> "Where should the project live? (default: `~/projects/<project-name>` once you set a name, or `~/projects/my-project` as a placeholder)"
>
> **What this controls:** This becomes the parent directory on disk. All source code, git worktrees, and spec files are created inside it. The `dev/` worktree where you do day-to-day work lives at `<root>/dev`. If the directory does not exist it will be created automatically. Default is `~/projects/<name>` — a sensible choice for most setups.

**LANG=ja prompt:**
> "プロジェクトをどこに作成しますか？（デフォルト: `~/projects/<プロジェクト名>`）"
>
> **この設定が影響する箇所:** ディスク上の親ディレクトリになります。ソースコード・gitワークツリー・spec ファイルはすべてここに作成されます。日常作業は `<root>/dev` ワークツリーで行います。ディレクトリが存在しない場合は自動作成されます。

---

#### Setup Q2: Project name

**LANG=en prompt:**
> "What is the project name? (optional — press Enter to use `harness-project-<random6>`)"
>
> **What this controls:**
> - Becomes the **directory name** under your chosen root (e.g., `~/projects/todo-app`).
> - Becomes the **`name` field in `package.json`** of the generated project.
> - Used as the **display name** in the auto-generated `dev/README.md` and `dev/CLAUDE.md`.
> - The lowercase-hyphen form is used as the **git branch namespace** (`feat/<name>-<n>`, `hotfix/<name>-<n>`) and as the **default Codex session name** when Codex consultations happen.
>
> Providing a name is **strongly recommended** for real projects. If omitted, the fallback `harness-project-<random6>` is fine for throwaway tests but produces ugly branch names and directory paths.

**LANG=ja prompt:**
> "プロジェクト名を入力してください（省略すると `harness-project-<ランダム6文字>` が使われます）"
>
> **この設定が影響する箇所:**
> - 選択したルートパス直下の **ディレクトリ名** になります（例: `~/projects/todo-app`）。
> - 生成プロジェクトの **`package.json` の `name` フィールド** になります。
> - 自動生成される `dev/README.md` と `dev/CLAUDE.md` の **表示名** として使われます。
> - 小文字ハイフン形式が **git ブランチ名前空間**（`feat/<name>-<n>`）と **Codex セッション名** に使われます。
>
> 実際のプロジェクトには名前の設定を**強く推奨**します。省略時の `harness-project-<ランダム6文字>` はテスト用途には十分ですが、ブランチ名やパスが分かりにくくなります。

**Internal slug derivation (never shown to user):** After the user answers, derive `PROJECT_SLUG` automatically:
```bash
# lowercase, spaces→hyphens, strip non-alnum except hyphens
PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
```
Do **not** show the word "slug" anywhere in the conversation.

---

#### Setup Q3: Codex integration

**LANG=en prompt:**
> "Use Codex for AI-assisted design and code review? (y/n, default: n)"
>
> **What this controls:** Codex (OpenAI's CLI) can be called at the end of each phase to get a second opinion, and is used during Phase 5 to generate logo and UI mock images via `gpt-image-2`.
>
> **Codex is completely optional.** If you say `n`, the plugin still works end-to-end:
> - The interview proceeds in Claude alone.
> - Logo and UI mock generation are skipped (you can supply your own images later).
> - Engineer / e2e-reviewer / reviewer subagents run in Claude — no Codex delegation.
> - All bootstrap, branch protection, CI, hooks, and 4-lane parallel features work unchanged.
> - You can always re-enable Codex later by editing `.my-harness/.config` and setting `USE_CODEX=yes`.

**LANG=ja prompt:**
> "Codex（OpenAI CLI）を使ったAI支援デザイン・コードレビューを有効にしますか？ (y/n、デフォルト: n)"
>
> **この設定が影響する箇所:** 各フェーズ終了時にセカンドオピニオンとして Codex を呼び出せます。フェーズ5ではロゴや UI モック画像を `gpt-image-2` で生成します。
>
> **Codex は完全にオプションです。** `n` を選んでもプラグインはすべて動作します:
> - インタビューは Claude だけで進みます。
> - ロゴ・UI モックの自動生成はスキップされます（後から自分で用意できます）。
> - エンジニア / e2e-reviewer / reviewer サブエージェントは Claude で実行されます。
> - ブートストラップ・ブランチ保護・CI・フック・4レーン並列実装はすべて変わらず動作します。
> - 後から `.my-harness/.config` で `USE_CODEX=yes` に変更すれば有効化できます。

**If USE_CODEX=no:** Skip Q3a, Q3b, Q3c, Q3d entirely. Set all three `USE_CODEX_*` flags to `no` automatically.

**If USE_CODEX=yes:** Proceed to Q3a through Q3d below.

---

#### Setup Q3a: Codex auth check (only when USE_CODEX=yes)

Run immediately after the user answers `y` to Q3:
```bash
bash ~/my-harness-generator/scripts/check-codex-auth.sh
```
- `not-installed` → Guide user to `npm i -g @openai/codex`; re-ask Q3
- `not-logged-in` → Ask user to run `codex login`. After 3 failures, automatically set USE_CODEX=no and continue
- `logged-in` → Confirm to the user (language-aware):
  - **LANG=en:** "Codex is ready. I'll resume Codex conversations in session `<PROJECT_SLUG>-init` so multi-turn dialog persists."
  - **LANG=ja:** "Codex の認証を確認しました。マルチターン対話が維持されるよう、セッション `<PROJECT_SLUG>-init` で Codex との会話を継続します。"

`CODEX_SESSION` is derived automatically as `<PROJECT_SLUG>-init`. This is never asked as a question.

Note: during implementation (after `/harness-team-lead`), each subagent spawn gets its own fresh Codex session — sessions are never shared across subagent boundaries. A new spawn for the same role and issue always starts a new session (except when resuming after a `blocked-codex-auth` pause, where the paused session id is explicitly inherited).

注: 実装フェーズ（`/harness-team-lead` 以降）では、各サブエージェントのスポーンは独自の新しい Codex セッションを取得します。セッションはサブエージェントの境界を越えて共有されません。同じロール・issue に対する新しいスポーンは常に新しいセッションを開始します（`blocked-codex-auth` 一時停止後の再開時を除く — その場合は一時停止時のセッション ID が明示的に引き継がれます）。

---

#### Setup Q3b: Delegate engineer to Codex? (only when USE_CODEX=yes)

**LANG=en:** "Delegate the engineer (implementation) subagent to Codex? (y/n, default: y — Codex is strong at code generation)"

**LANG=ja:** "エンジニア（実装）サブエージェントを Codex に委任しますか？ (y/n、デフォルト: y — Codex はコード生成が得意です)"

---

#### Setup Q3c: Delegate e2e-reviewer to Codex? (only when USE_CODEX=yes)

**LANG=en:** "Delegate the e2e-reviewer subagent to Codex? (y/n, default: n)"
>
> **What this controls:** E2E tests (Playwright / Maestro) always run **locally inside the worktree** — Claude executes `nix develop --command pnpm exec playwright test ...` and/or `nix develop --command maestro test ...` directly. Codex never runs Playwright or Maestro itself.
>
> When `n` (default): Claude runs the tests AND synthesizes the structured failure report.
> When `y`: Claude still runs the tests locally; **the only thing Codex does** is take the raw test output (failures, console errors, network errors, screenshot paths) and synthesize the structured failure report (file / test / expected / actual / hypothesis). Codex acts as the report writer / diagnostician.
>
> **Why default `n`:** Claude is already in the worktree, has direct file and log access, and generates the same structured report without an extra round-trip. Codex delegation is worth it only if you specifically want a second-opinion diagnosis.

**LANG=ja:** "e2e-reviewer サブエージェントを Codex に委任しますか？ (y/n、デフォルト: n)"
>
> **この設定が影響する箇所:** E2E テスト（Playwright / Maestro）は**常にワークツリー内でローカル実行**されます — Claude が `nix develop --command pnpm exec playwright test ...` や `nix develop --command maestro test ...` を直接実行します。Codex が Playwright や Maestro を実行することは一切ありません。
>
> `n`（デフォルト）の場合: Claude がテストを実行し、構造化された失敗レポートも合成します。
> `y` の場合: Claude が引き続きテストをローカルで実行します。**Codex が行うのは唯一つ** — 生のテスト出力（失敗・コンソールエラー・ネットワークエラー・スクリーンショットパス）を受け取り、構造化された失敗レポート（ファイル / テスト / 期待値 / 実際値 / 仮説）を合成することだけです。Codex はレポートライター・診断者として機能します。
>
> **デフォルトが `n` の理由:** Claude はすでにワークツリー内にあり、ファイルやログに直接アクセスでき、追加のラウンドトリップなしに同じ構造化レポートを生成できます。Codex 委任が有効なのは、第二意見による診断を特に求める場合だけです。

---

#### Setup Q3d: Delegate reviewer to Codex? (only when USE_CODEX=yes)

**LANG=en:** "Delegate the reviewer (convention review) subagent to Codex? (y/n, default: y — Codex is strong at code review)"

**LANG=ja:** "reviewer（規約レビュー）サブエージェントを Codex に委任しますか？ (y/n、デフォルト: y — Codex はコードレビューが得意です)"

---

#### Setup Q4: Task management

**LANG=en prompt:**
> "How should tasks be tracked? (`issues` = GitHub Issues, `local` = markdown files in `dev/docs/task/`, default: `local`)"
>
> **What this controls:** With `issues`, tasks are created as GitHub Issues with lane assignments and you need a GitHub repo. With `local`, tasks are markdown files with front matter stored in the repo — no GitHub dependency, works offline, and the files are git-tracked alongside your spec.

**LANG=ja prompt:**
> "タスク管理の方法を選んでください。(`issues` = GitHub Issues、`local` = `dev/docs/task/` のマークダウン、デフォルト: `local`)"
>
> **この設定が影響する箇所:** `issues` を選ぶと GitHub Issues にレーン割り当てつきで作成されます（GitHub リポジトリが必要）。`local` を選ぶとフロントマター付きマークダウンとしてリポジトリ内に保存されます。オフラインで動き、spec と一緒に git 管理されます。

---

Save the answers:

```bash
mkdir -p <root>/.my-harness <root>/dev/docs/spec <root>/dev/docs/design <root>/dev/docs/talk <root>/dev/docs/task

cat > <root>/.my-harness/.config <<EOF
LANG=<en|ja>
PROJECT_NAME=<name as entered by user>
PROJECT_SLUG=<derived lowercase-hyphen form, never shown to user>
ROOT=<root>
USE_CODEX=<yes|no>
CODEX_SESSION=<PROJECT_SLUG>-init  # Only written when USE_CODEX=yes
USE_CODEX_ENGINEER=<yes|no>        # Only meaningful when USE_CODEX=yes; if no, Claude implements
USE_CODEX_E2E_REVIEWER=<yes|no>    # Only meaningful when USE_CODEX=yes; default no — Claude runs E2E tests locally AND synthesizes the report; yes = Claude runs tests, Codex synthesizes the failure report
USE_CODEX_REVIEWER=<yes|no>        # Only meaningful when USE_CODEX=yes; if no, Claude does review
ON_CODEX_AUTH_FAIL=pause           # Default pause: notify user and wait on auth/subscription failure; fail = immediate error
USE_GITHUB_ISSUES=<yes|no>
EOF
```

When USE_CODEX=yes, register the active session pointer:
```bash
~/my-harness-generator/scripts/codex-ask.sh --set-active <root>
```

---

### Phase 1: What to build

**Fixed questions (one per turn — never improvise). Use the LANG=en variant when `LANG=en`, and the LANG=ja variant when `LANG=ja`.**

**Question 1:**
- **LANG=en:** "In one sentence, what are you building?" (e.g. task management app / inventory SaaS / blog site / internal tool)
- **LANG=ja:** "一文で教えてください。何を作りますか？" （例: タスク管理アプリ / 在庫管理SaaS / ブログサイト / 社内ツール）

**Question 2:**

- **LANG=en:** "List the features required for v1 — the first release you'd be willing to ship publicly. Don't trim for MVP scope; include everything you'd need before saying 'this is done'. One feature per line. Continue listing until you have nothing more to add."
- **LANG=ja:** "v1（最初に公開してもいいと思える完成度のリリース）に必要な機能をすべて挙げてください。MVP として削るのではなく、『これで完成』と言える状態に必要な全機能を含めてください。1 行に 1 機能。これ以上書くものが無くなるまで続けてください。"

**What this controls (en + ja):**

> Each feature listed here becomes one or more issues / task files in your project. You're not committing to specific implementation order — that comes at /harness-team-lead time. The list is just the truth about what v1 means to you. Take your time.
>
> ここで挙げた機能はそれぞれ 1 つ以上の issue / task ファイルになります。実装順序を今決める必要はありません — それは `/harness-team-lead` のタイミングで行います。このリストは「v1 として何が必要か」という事実を記録するためのものです。じっくり考えてください。

That's it. Do **not** ask "who uses it / personas / why existing services don't work / what success looks like in 5 years". Who uses it will surface naturally in Phase 3 (authentication) and Phase 5 (visual impression) as concrete choices — asking abstractly adds no value.

Save to: `dev/docs/spec/01-what.md` / `dev/docs/talk/01-what.md`

If USE_CODEX=yes, run a Codex consult at the end:
```bash
~/my-harness-generator/scripts/codex-ask.sh --role analyst \
  --out <root>/.my-harness/codex-phase1.md \
  "Project summary: <one sentence>. v1 feature list: <enumerated>. Point out any logical contradictions, ambiguities, or missing items."
```

---

### Phase 2: Platform + framework

**Ask as a single multi-select, then follow up per selected platform.** Use the LANG=en phrasing when `LANG=en`, and LANG=ja phrasing when `LANG=ja`.

#### 2.0 Platform selection (single question)

**LANG=en prompt:**
> "Which platforms? Select one or more (comma-separated): `web`, `desktop`, `mobile`"
>
> **What this controls:** Each selected platform creates its own subdirectory in the generated project (e.g., `dev/web/`, `dev/ios/`, `dev/android/`, `dev/desktop/`) with its own framework setup, CI workflow, and lane assignment. You can combine any subset — web-only is fine, web+mobile is fine, desktop+mobile without web is fine.

**LANG=ja prompt:**
> "対応プラットフォームをすべて選んでください（カンマ区切り）: `web`, `desktop`, `mobile`"
>
> **この設定が影響する箇所:** 選択したプラットフォームごとに専用のサブディレクトリ（例: `dev/web/`、`dev/ios/`、`dev/android/`、`dev/desktop/`）が生成され、それぞれ独自のフレームワーク設定・CI ワークフロー・レーン割当が行われます。任意の組み合わせが可能です。web のみ、web+mobile、desktop+mobile（web なし）なども問題ありません。

After the user answers, render a checklist preview (Claude outputs this, not a prompt):

```
Selected:
[x] Web        (if chosen)
[x] Desktop    (if chosen)
[x] Mobile     (if chosen — iOS and/or Android will be clarified next)
```

Then proceed with **only the follow-up questions for selected platforms**, in the order: Web → Desktop → Mobile. Skip any platform not selected entirely.

#### 2.1 Web framework (only when web was selected)

**LANG=en:** "Which web framework? (`nextjs` = Next.js 16 App Router / `tanstack` = TanStack Start)"

**LANG=ja:** "Web フレームワークを選んでください。(`nextjs` = Next.js 16 App Router / `tanstack` = TanStack Start)"

#### 2.2 Desktop framework + OS (only when desktop was selected)

**LANG=en step 1:** "Which desktop framework? (`tauri` = Rust shell + web frontend, lightweight / `electron` = Node.js shell + web frontend, rich ecosystem)"

**LANG=ja step 1:** "デスクトップフレームワークを選んでください。(`tauri` = Rust シェル + Web フロントエンド、軽量 / `electron` = Node.js シェル + Web フロントエンド、エコシステム豊富)"

**LANG=en step 2:** "Which OS targets? Select one or more (comma-separated): `macos`, `windows`, `linux` (default: all)"

**LANG=ja step 2:** "対象 OS を選んでください（カンマ区切り）: `macos`, `windows`, `linux`（デフォルト: すべて）"

#### 2.3 Mobile: iOS / Android split (only when mobile was selected)

**LANG=en step 1:** "Which mobile platforms? Select one or more (comma-separated): `ios`, `android`"

**LANG=ja step 1:** "対応するモバイルプラットフォームを選んでください（カンマ区切り）: `ios`, `android`"

**LANG=en step 2 (only when ios selected):** "Which iOS implementation? (`swift` = Swift + SwiftUI native / `expo` = React Native Expo / `flutter` = Flutter)"

**LANG=ja step 2 (only when ios selected):** "iOS の実装方法を選んでください。(`swift` = Swift + SwiftUI ネイティブ / `expo` = React Native Expo / `flutter` = Flutter)"

**LANG=en step 3 (only when android selected):** "Which Android implementation? (`kotlin` = Kotlin + Jetpack Compose native / `expo` = React Native Expo / `flutter` = Flutter)"

**LANG=ja step 3 (only when android selected):** "Android の実装方法を選んでください。(`kotlin` = Kotlin + Jetpack Compose ネイティブ / `expo` = React Native Expo / `flutter` = Flutter)"

#### Validation

- At least one platform must be selected (re-ask if none)
- If both iOS and Android are selected and both choose `expo` or both choose `flutter` → **inform the user they share a single codebase** (one directory under `mobile/`)
- iOS `swift` + Android `kotlin` combination → separate codebases (`ios/` and `android/`)
- iOS and Android choosing different cross-platform frameworks (e.g. `expo` vs `flutter`) → warn about the inconsistency and suggest aligning to one

Save to: `dev/docs/spec/02-platform.md` / `dev/docs/talk/02-platform.md`

Append to `.my-harness/.config`:
```bash
USE_WEB=<yes|no>
WEB_KIND=<nextjs|tanstack>          # Only when USE_WEB=yes
USE_IOS=<yes|no>
IOS_KIND=<swift|expo|flutter>       # Only when USE_IOS=yes
USE_ANDROID=<yes|no>
ANDROID_KIND=<kotlin|expo|flutter>  # Only when USE_ANDROID=yes
USE_DESKTOP=<yes|no>
DESKTOP_KIND=<tauri|electron>       # Only when USE_DESKTOP=yes
DESKTOP_OS=macos,windows,linux      # Only when USE_DESKTOP=yes
```

**Important (bug prevention)**: A framework choice is **only asked when that platform's y/n is yes**. A choice for one platform must never bleed into another (e.g. choosing DESKTOP_KIND=tauri does not set IOS_KIND to anything).

---

### Phase 3: Backend configuration

**Fixed questions (one per turn). Use the LANG=en phrasing when `LANG=en`, and LANG=ja phrasing when `LANG=ja`.**

1. **LANG=en:** "Build a backend? (y/n — frontend-only or serverless-only projects can answer no)"
   **LANG=ja:** "バックエンドを作りますか？ (y/n — フロントエンドのみ、またはサーバーレスのみのプロジェクトは no でも構いません)"

2. If y — **LANG=en:** "Which backend language/framework? (`hono` = TypeScript + Hono on Cloudflare Workers / `gin` = Go + Gin / `rust` = Rust + axum)"
   If y — **LANG=ja:** "バックエンドの言語・フレームワークを選んでください。(`hono` = TypeScript + Hono on Cloudflare Workers / `gin` = Go + Gin / `rust` = Rust + axum)"

3. **LANG=en:** "Need a database? (y/n)"
   **LANG=ja:** "データベースは必要ですか？ (y/n)"

4. If y — **LANG=en:** "Which database? (`d1` = Cloudflare D1 / `postgres` = PostgreSQL / `mysql` = MySQL / `sqlite` = SQLite — recommended: `d1` for hono, `postgres` for gin/rust)"
   If y — **LANG=ja:** "データベースを選んでください。(`d1` = Cloudflare D1 / `postgres` = PostgreSQL / `mysql` = MySQL / `sqlite` = SQLite — 推奨: hono には `d1`、gin/rust には `postgres`)"

5. **LANG=en:** "Need email sending? (y/n — yes sets up Resend for password reset etc.)"
   **LANG=ja:** "メール送信機能は必要ですか？ (y/n — yes を選ぶとパスワードリセット等のために Resend をセットアップします)"

6. **LANG=en:** "How much authentication do you need? (`none` / `password` / `oauth`)"
   **LANG=ja:** "認証の種類を選んでください。(`none` = なし / `password` = パスワード認証 / `oauth` = OAuth)"

7. **LANG=en:** "How much E2E testing? (`web` = Playwright / `mobile` = Maestro / `both` / `none`)"
   **LANG=ja:** "E2E テストの範囲を選んでください。(`web` = Playwright / `mobile` = Maestro / `both` = 両方 / `none` = なし)"

8. **LANG=en:** "Use Claude Code Action in CI for automated PR review? (y/n)"
   **LANG=ja:** "CI で Claude Code Action を使った自動 PR レビューを有効にしますか？ (y/n)"

9. If y — **LANG=en:** "Authentication method for Claude Code Action? (`api` = API key / `oauth` = OAuth app)"
   If y — **LANG=ja:** "Claude Code Action の認証方法を選んでください。(`api` = API キー / `oauth` = OAuth アプリ)"

Save to: `dev/docs/spec/03-backend.md` / `dev/docs/talk/03-backend.md`

Append to `.my-harness/.config`:
```bash
USE_BACKEND=<yes|no>
BACKEND_KIND=<hono|gin|rust>        # Only when USE_BACKEND=yes
USE_DB=<yes|no>
DB_KIND=<d1|postgres|mysql|sqlite>  # Only when USE_DB=yes
USE_EMAIL=<yes|no>
AUTH_KIND=<none|password|oauth>
E2E_SCOPE=<web|mobile|both|none>
USE_PLAYWRIGHT=<yes|no>             # yes when E2E_SCOPE is web|both
USE_MAESTRO=<yes|no>                # yes when E2E_SCOPE is mobile|both
USE_CLAUDE_ACTION=<yes|no>
CLAUDE_AUTH=<api|oauth>             # Only when USE_CLAUDE_ACTION=yes
```

**Important (bug prevention)**: A BACKEND_KIND choice must never bleed into other variables (e.g. choosing BACKEND_KIND=rust does not affect DESKTOP_KIND — they are fully independent).

If USE_CODEX=yes, verify from an architect perspective:
```bash
~/my-harness-generator/scripts/codex-ask.sh --role architect \
  --out <root>/.my-harness/codex-phase3.md \
  "Platform: <Web/iOS/Android/Desktop>. Backend: <DB/Email/Auth/E2E>. Point out design validity and tradeoffs."
```

---

### Phase 4: Data model (only when USE_DB=yes; skip if no)

**Fixed questions (use the variant matching `LANG`)**:

1. **LANG=en:** "List 3–7 entities for your data model." (e.g. User / Task / Comment)
   **LANG=ja:** "データモデルのエンティティを 3〜7 個リストアップしてください。"（例: User / Task / Comment）

2. **LANG=en:** "Bullet out the main fields for each entity."
   **LANG=ja:** "各エンティティの主なフィールドを箇条書きで教えてください。"

3. **LANG=en:** "Describe relationships between entities in mermaid ER style." (e.g. User 1—N Task)
   **LANG=ja:** "エンティティ間のリレーションシップを mermaid ER スタイルで説明してください。"（例: User 1—N Task）

4. **LANG=en:** "Which fields contain PII?" (email, phone, address, etc.)
   **LANG=ja:** "個人情報（PII）を含むフィールドはどれですか？"（メール・電話番号・住所など）

Claude assembles a mermaid ER diagram from the answers and saves it to `dev/docs/spec/04-data-model.md`.

If USE_CODEX=yes, run an architect normalization check.

---

### Phase 5: Visual (logo + key screen UI mocks)

**Absolute image format rules**:
- **PNG only**. SVG is **prohibited** as a generated image format. Transparent PNG (alpha background) is allowed.
- Resolution: logos at minimum 1024×1024; UI mocks at the resolution specified below
- After generation, **always auto-open with the `open` command** (macOS) so the user can review immediately:
  - macOS: `open <path>`
  - Linux: `xdg-open <path>`
  - Windows: `start "" <path>`
  - Claude detects the OS with `uname` and chooses the appropriate command

**Prompting strategy**: Trust Codex's designer capability — **give a high-level request and let it decide**.

Claude does not over-specify. Pass the spec files via `--context dev/docs/spec/*.md` and keep the request brief: "Generate 3 logo concepts as PNG, save to ...". Color, shape, and layout decisions are left to Codex.

Never write:
- Code-style instructions (coordinates, pixel values, CSS properties, Tailwind classes, SVG paths, HTML tags)
- Over-specification of visual details

Do write:
- What to create (logo / screen name) and how many concepts
- That the format is PNG, the save path, and the resolution (e.g. 1024×1024)
- Assume Codex will read the context (spec files)

**Fixed questions** (one per turn, minimal — use the variant matching `LANG`):

1. **LANG=en:** "Any color hint for the design? (optional — e.g. `#14b8a6` / 'blue tones' / 'no preference')"
   **LANG=ja:** "デザインの色のヒントはありますか？（任意 — 例: `#14b8a6` / 「青系」/ 「特になし」）"

2. **LANG=en:** "List 3–5 screens you want mocked." (e.g. Login / Home / Detail / Settings)
   **LANG=ja:** "UI モックを作成したい画面を 3〜5 個リストアップしてください。"（例: ログイン / ホーム / 詳細 / 設定）

That's it. Do **not** ask about logo direction, impression, or tone. Codex reads `dev/docs/spec/*.md` and decides on its own.

#### Logo generation (when USE_CODEX=yes)

```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --context <root>/dev/docs/spec/*.md \
  --out <root>/.my-harness/codex-logo.md \
  "\$imagegen Please generate 3 logo concepts for $PROJECT_NAME.

**You must use the image_gen tool (gpt-image-2) to generate PNG files directly**. Writing HTML/CSS and taking a screenshot, writing SVG, or going through code are all prohibited.

Read the spec files and design something that fits the project — your judgment. <If a color hint was given: Primary color: <hint>>

Specs:
- Format: PNG (transparent background)
- Resolution: 1024x1024 or larger
- Call image_gen separately for each concept (3 calls total)

Save to:
- <root>/dev/docs/design/logo-1.png
- <root>/dev/docs/design/logo-2.png
- <root>/dev/docs/design/logo-3.png"
```

After generation, immediately open all 3 concepts (macOS example):

```bash
open <root>/dev/docs/design/logo-1.png \
     <root>/dev/docs/design/logo-2.png \
     <root>/dev/docs/design/logo-3.png
```

On Linux use `xdg-open` 3 times; on Windows use `start "" <path>` 3 times. Branch with `uname -s`.

**File format verification** (run immediately after generation):
```bash
file <root>/dev/docs/design/logo-{1,2,3}.png | grep -v "PNG image"
```
If anything other than PNG (SVG / JPEG, etc.) appears, ask Codex to regenerate. If SVG was generated, delete it and regenerate as PNG.

User selects one concept → copy to `<root>/dev/docs/design/logo-final.png` (real copy, not a symlink, for clean git management).

#### Interactive refinement (important)

When the user gives refinement instructions like "**make concept 1 bluer**" or "**make the text in concept 2 larger**", **resume the same session and call codex-ask.sh again**:

```bash
# Additional prompt to the same session (codex-ask.sh auto-resumes)
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --out <root>/.my-harness/codex-logo-r1.md \
  "Make concept 1 a bit more blue and simpler. Regenerate and overwrite the same path."
```

Key points:
- **Never add `--reset-session`** (that destroys the session and loses prior context)
- **Never re-attach `--context` with the spec** (it is already in the session)
- Codex remembers what concept 1 looked like, so a delta instruction is enough to refine
- Open the result again with `open` after each generation

Repeat this N times to **iteratively refine**. Once the user approves, copy the chosen concept to `logo-final.png`.

#### UI mock generation (per screen)

For each screen:

```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --context <root>/dev/docs/spec/*.md <root>/dev/docs/design/logo-final.png \
  --out <root>/.my-harness/codex-mock-<screen>.md \
  "\$imagegen Please generate 2 mock concepts for the <screen name> screen of $PROJECT_NAME.

**You must use the image_gen tool (gpt-image-2) to generate PNG files directly.**
- Writing HTML/CSS and using Playwright/Puppeteer to screenshot is **absolutely prohibited**
- Writing SVG or rasterizing via \`<canvas>\` is also **prohibited**
- Do not write code — **have the image generation AI draw it visually**

Read the spec and the chosen logo, then design using your own judgment. Use Lucide Icons-style icons; no AI-style gradients.

Specs:
- Format: PNG
- Resolution: <1280x800 for Web/Desktop; 375x812 for mobile>
- Call image_gen separately for each concept (2 calls total)

Save to:
- <root>/dev/docs/design/mock-<screen>-1.png
- <root>/dev/docs/design/mock-<screen>-2.png"
```

After generation, immediately open both concepts:
```bash
open <root>/dev/docs/design/mock-<screen>-{1,2}.png
```

Run the same `file` command PNG verification. 2 concepts per screen → user selects one. OG image / favicon follow the same approach (**all PNG**).

#### Interactive refinement for mocks

Same as logos. When the user gives instructions like "**move the search bar to the top on the home screen**" or "**make the button on the detail screen round**", **resume the same session and call again**:

```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --out <root>/.my-harness/codex-mock-home-r1.md \
  "Move the search bar in home screen concept 1 to the top and regenerate. Overwrite the same path."
```

`--reset-session` prohibited; re-attaching `--context` prohibited (the session remembers prior turns). Repeat N times to finalize.

#### Iteration (important)

If the mocks reveal that requirements have changed, **go back to one of phases 1–4 to update the spec**. Return to this phase afterward and regenerate only the affected mocks. **Maximum 3 iteration cycles.**

When USE_CODEX=no, skip mock generation and record the visual direction (primary color, impression, layout approach per screen) as text in `dev/docs/design/brand.md`. The user handles design manually later with Figma or similar.

#### Completion criteria

- [ ] One logo concept finalized
- [ ] Mocks selected for 3–5 key screens (USE_CODEX=yes only)
- [ ] OG image / favicon generated
- [ ] If spec changed during iteration, `docs/spec/*.md` is up to date

Save to: `dev/docs/spec/05-visual.md` / `dev/docs/design/{logo-*,mock-*,og,favicon}.png`

---

### Phase 6: Spec finalization + bootstrap + issue/task generation

#### 6.1 Final spec review

Read all of `dev/docs/spec/0[1-5]-*.md` and present a summary to the user for approval.

If USE_CODEX=yes, run a final cross-check with Codex code-reviewer:
```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh --role code-reviewer \
  --context <root>/dev/docs/spec/*.md <root>/dev/docs/design/*.png -- \
  "Point out any inconsistencies between the spec / mocks / tech stack, logical contradictions, and missing functionality."
```

If there are corrections, go back to one of phases 1–5 and then return here.

#### 6.2 Bootstrap execution (non-interactive)

```bash
bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/bootstrap.sh "<root>" --config "<root>/.my-harness/.config"
```

bootstrap scaffolds the dev worktree and creates the initial commit → `docs/spec/`, `docs/design/`, and `docs/talk/` are all included in git.

#### 6.3 Issue / task generation (branching on USE_GITHUB_ISSUES)

Split the feature list from phase 1 into **child issues of at most 300 lines each**, declaring file ownership to prevent conflicts.

- **USE_GITHUB_ISSUES=yes**: Create parent + child issues with `gh issue create` (including 4-lane assignments)
- **USE_GITHUB_ISSUES=no**: Represent parent/child as files:
  ```
  <root>/dev/docs/task/parent/0001-<slug>.md
  <root>/dev/docs/task/child/0001-<feature>.md
  ```
  Each file uses front matter to express `parent: 0001` / `lane: 1–4` / `status: pending`.

#### 6.4 Clear the active session pointer (if USE_CODEX=yes was set)

```bash
~/my-harness-generator/scripts/codex-ask.sh --clear-active
```

#### 6.5 Generate dev/README.md and dev/CLAUDE.md for the first time

Read `dev/docs/spec/*.md` and `.my-harness/.config`, then Claude **manually creates** the following 2 files (reflecting the spec content):

##### Structure of `<root>/dev/README.md`

```markdown
# <PROJECT_NAME>

<1–2 line summary from spec/01-what.md>

## Features

<v1 feature list from spec/01-what.md as bullet points, each with `[ ] not implemented / [x] done` checkbox>

## Tech stack

- Frontend: <WEB_KIND if USE_WEB>, <IOS_KIND if USE_IOS>, ...
- Backend: <BACKEND_KIND if USE_BACKEND>
- DB: <DB_KIND if USE_DB>
- Auth: <AUTH_KIND>
- E2E: <E2E_SCOPE>

## Setup

\`\`\`bash
cd dev
direnv allow
nix develop --command pnpm install
nix develop --command pnpm exec husky
\`\`\`

## Development flow

The harness (my-harness-generator) orchestrates:
- `/harness-team-lead` — drive all issues in parallel across 4 lanes at once
- `/harness-new-feature <issue#>` — start a specific issue
- Re-run `/my-harness-init` — resume from where you left off (`init-state.json` is auto-detected)

## Environment variables

<TBD — engineers append to this as implementation progresses>

## License

<TBD>
```

##### Structure of `<root>/dev/CLAUDE.md`

```markdown
# <PROJECT_NAME> — Instructions for Claude Code

This project runs on a harness generated by my-harness-generator.

## Project purpose

<From spec/01-what.md>

## Architecture

- 4-layer Clean Architecture (domain / application / infrastructure / interfaces)
- DB: <DB_KIND> + Drizzle ORM (when USE_DB=yes)
- Auth: <AUTH_KIND>

## Data model

<Copy the mermaid ER diagram from spec/04-data-model.md (only when DB is used)>

## Key screens / API

<Key screen list from spec/05-visual.md and expected API endpoints>

## Conventions

The harness auto-firing skills enforce:
- harness-tdd (t-wada / Kent Beck style TDD)
- harness-hono-clean-arch
- harness-drizzle-rules (migrate-only)
- harness-nix-pure
- harness-design-rules (Lucide Icons only, no AI-style design)
- harness-jsdoc (JSDoc/TSDoc required on all exports)
- harness-git-discipline (no rebase / reset / force-push)
- harness-no-hardcoded-secrets

## Agent responsibilities (4-lane parallel implementation)

- team-lead: issue assignment (avoiding file conflicts), progress aggregation, user approval relay
- analyst: in-lane orchestration, git add / commit / push / gh pr create
- engineer: implementation only (no git operations; updates README/CLAUDE.md alongside implementation)
- e2e-reviewer: runs Playwright/Maestro
- reviewer: convention + docs consistency review

## Key files

<Empty — engineers append to this whenever a feature is implemented>

## Current feature status

<Initialize the v1 feature list from spec/01-what.md with `pending`; update to `done` as issues complete>
```

After Claude writes these 2 files to `dev/`, stage and commit them in the dev worktree. Write the commit message in `$LANG`:

```bash
cd "<root>/dev"
git add README.md CLAUDE.md
# If LANG=en:
git -c user.name="harness-bot" -c user.email="harness@local" \
  commit --no-verify -m "docs: generate initial README.md and CLAUDE.md from spec"
# If LANG=ja:
git -c user.name="harness-bot" -c user.email="harness@local" \
  commit --no-verify -m "docs: README.md と CLAUDE.md の初版を spec から生成"
```

From this point on, engineers update these files with each feature addition and the reviewer checks consistency.


#### 6.6 Update init-state.json + stop + guide user to dev (important)

Once issue / task generation is complete, update `<root>/.my-harness/init-state.json` to **`current_phase: "completed"`**:

```bash
ROOT=<root>
ISSUE_COUNT=<number of child issues generated>
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$ROOT/.my-harness/init-state.json" <<EOF
{
  "schema_version": "1",
  "project_name": "<PROJECT_NAME>",
  "lang": "${LANG:-en}",
  "root": "$ROOT",
  "current_phase": "completed",
  "phases_completed": ["language", "setup", "what", "platform", "backend", "data-model", "visual", "bootstrap", "tasks"],
  "next_action": "implementation",
  "next_action_command": "/harness-team-lead (or /harness-new-feature <issue#>)",
  "working_directory": "$ROOT/dev",
  "issue_count": $ISSUE_COUNT,
  "lanes_assigned": true,
  "timestamp": "$TIMESTAMP"
}
EOF
```

Then **present the following message to the user and stop automatically** (do not proceed with any further work):

```
/my-harness-init complete

Spec:    <root>/dev/docs/spec/
Mocks:   <root>/dev/docs/design/
Tasks:   <root>/dev/docs/task/  or GitHub Issues
State:   <root>/.my-harness/init-state.json (current_phase=completed)

From here, work happens in the dev worktree. Steps:

1) In your terminal:
     cd <root>/dev
     direnv allow
     pnpm install
     pnpm exec husky

2) Push to GitHub (whenever you're ready):
     git remote add origin git@github.com:<owner>/<repo>.git
     git push --all origin
     # Then set up branch protection and GitHub Secrets:
     bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
     bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>

3) End this session, run `cd <root>/dev` in your terminal,
   then restart Claude Code. In the new session, run one of:

     /harness-team-lead               # Drive all issues in parallel across 4 lanes (recommended)
     /harness-new-feature <issue#>    # Start a specific feature
     /my-harness-init                 # Resume from where you left off (auto-detects init-state.json)
```

**Claude (you) stops here.** Do not proceed with any further work until the user starts a new session in dev/.

---

## Codex role selection (reference)

| Situation | role |
|-----------|------|
| Detect ambiguity or contradictions in requirements | analyst |
| Validate design, analyze tradeoffs | architect |
| Design proposals / image generation | designer |
| Logic review of spec documents | code-reviewer |
| Security perspective | security-reviewer |

**Do not use `critic` or `planner`** — they are product-strategy oriented and not directly tied to system decisions.

## Failure fallbacks

- `codex` not installed → automatically set USE_CODEX to no and continue with Claude alone
- `codex login` not run → guide user; after 3 failures, fall back to no
- `bootstrap.sh` fails → display stderr and let the user decide
- Existing file conflict → ask user whether to continue / abort / specify a different directory

## Artifact layout summary

```
<root>/
├── .my-harness/                       Internal work files (gitignored)
│   ├── .config                          Selections (including USE_DESKTOP, etc.)
│   ├── codex-sessions/<KEY>.id          (gitignored)
│   ├── codex-phase*.md                  (gitignored)
│   └── codex.jsonl                      (gitignored)
├── dev/                                 Standard structure created by bootstrap
│   └── docs/
│       ├── spec/01-what.md ...          Masked requirements (5 files)
│       ├── design/logo-*.png ...        Generated images
│       ├── talk/01-*.md ...             Masked Q&A full text
│       └── task/                        When USE_GITHUB_ISSUES=no
│           ├── parent/0001-*.md
│           └── child/0001-*.md
├── stage/  main/  lanes/                Standard worktrees
└── .bare/                               Bare git repo
```

## How to conduct the conversation (Claude's behavior)

- **Read only the question text written in this SKILL.md.** Do not improvise derivative questions ("Which device do you focus on?", "What's your brand's world view?", "What does success look like in 5 years?", etc.).
- One question per turn. Batch questions prohibited.
- Every turn: receive answer → mask → append to file. Always in this order.
- If a string looks like it could be sensitive, say "I'll mask this" before writing it out.
- At the end of each phase, present a summary and ask "Ready to continue?".
- If the user says "stop", save the current state and halt.
