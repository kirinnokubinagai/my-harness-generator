---
name: my-harness-init
description: Runs the full new-project pipeline end-to-end. Phase 0 picks language, Phase 1 collects only the truly orthogonal setup flags, Phase 2 holds an open multi-turn discovery conversation that drills aggressively into the user's idea (failure modes, resistance, scale breakpoints, trust, differentiation, day-2 ops) and produces a structured discoverySheet, Phase 3 settles only the structural shape (architecture + platforms), Phase 4 elaborates the complete feature list with deep per-feature drills (onboarding / power-user / empty / failure / latency), Phase 5 generates the logo + per-platform UI mocks (3–5 screens each) which become the source of truth, Phase 6 picks concrete tools (framework / backend / DB / package manager / email / e2e / Claude Code Action) — each prompt referencing the approved mocks, Phase 7 drills the data model deeply (lifecycle / GDPR / permissions / cardinality / migration), Phase 8 finalizes spec and runs bootstrap. Triggered by /my-harness-init.
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

Restart Claude Code (or run `/clear`) so newly registered skills and hooks load.

### Start a new project

```
/my-harness-init
```

If `.my-harness/init-state.json` already exists in the cwd or a parent, the skill auto-detects it and offers to resume.

### Keeping the plugin up to date

```
/plugin marketplace update
```

> **Never `git clone` this repository to use the plugin.** Cloning freezes you to a single revision and bypasses the plugin update mechanism.

---

## Design principles (read this every run)

This skill replaces blind structured questionnaires with a **mocks-before-tools interview**:

1. **An open discovery conversation** (Phase 2) where Claude asks free-form, drilling questions and maintains a structured `discoverySheet` internally — including failure modes, resistance, scale breakpoints, trust, differentiation, and day-2 operations. Discovery is where requirements actually crystallize.
2. **Structural choices first** (Phase 3) — only architecture and platforms. Specific tools are deferred.
3. **Visual mocks become the source of truth** (Phase 5) — the logo plus 3–5 mocks per chosen platform are generated and iterated on, then the visible elements (lists, forms, charts, real-time indicators, offline banners) drive every downstream decision.
4. **Tool selection is informed by mocks** (Phase 6). Frameworks, DB, package manager, email, e2e, Claude Code Action are chosen with the mocks open so we can say "this dashboard needs real-time → choose framework with realtime story" rather than asking blind.
5. **Data model is reverse-engineered from mocks + discovery** (Phase 7) and drilled deeply — GDPR scope, access permissions, cardinality reality, migration scenarios.

**Cardinal rules — applied every turn (full enumeration in `rules/communication.md`):**

- **One topic per user-facing message.** A single reply must not stack multiple distinct subjects (analysis + decision + question + side note). If the harness has 3 things to convey, send 3 short messages, not 1 long one. Wait for the user's response before moving to the next subject. Tables, bullet lists, and headers are only allowed when the user explicitly asked for one (e.g., "summarize", "list the options"). Default to plain sentences.

- **Plain language the user already understands. No harness-invented compounds.** Use the most common product name or everyday Japanese / English word for a concept. Examples: say "Web アプリ" / "Web app" rather than `client-server`; say "Codex の二次チェック" / "second look from Codex" rather than `Codex consult`; say "前の会話で決めた範囲" rather than `discoverySheet`. **If you are about to write a hyphenated compound, stop and check: is this a word the user has seen elsewhere?** If not, replace with a normal phrase. Made-up compounds are a bug.

- **Codex second-opinion is opt-in per occurrence.** The harness must NEVER run `codex-ask.sh --role analyst|architect|harness-reviewer|code-reviewer` (or any Codex second-opinion call) without asking the user first. Even when `USE_CODEX=yes`, treat each occurrence as a separate ask. Image generation (logo / UI mocks) and session management (`--set-active` / `--clear-active`) are NOT second-opinions — those run normally per phase. Only the **review / verification** calls require asking. The ask template:
  - **LANG=en:** "Want me to ask Codex for a second look at this? (yes / no)"
  - **LANG=ja:** "ここまでの内容について、Codex に二次チェックしてもらいますか? (はい / いいえ)"

  If "no" → skip the consult and continue. If "yes" → run the consult, then summarize the result in plain language (no `codex-phase2.md` filename in the user message).

- **NEVER leak harness-internal terminology to the user.** The user reads product terms; Claude reads code. The following are **forbidden** in any user-facing message (questions, skip announcements, summaries, error displays, confirmations):
  - Internal field names: `discoverySheet`, `visualMocks`, `initState`, `init-state.json`, `architectureHints`, `persistenceHints`, `topUserActions`, `scaleExpectation`, `failureModes`, `resistance`, `scaleBreakpoints`, `trustModel`, `differentiation`, `day2Operations`, `decisionsRevealed`, etc.
  - Internal enum values: `client-server`, `client-serverless`, `p2p-pure`, `p2p-hybrid`, `nextjs`, `tanstack`, `sveltekit`, `swift`, `expo`, `flutter`, `kotlin`, `tauri`, `electron`, `hono`, `gin`, `rust`, `d1`, `postgres`, `mysql`, `sqlite`, `resend`, `pause`, `fail`, `oauth`, `api`. The user sees product names ("Next.js", "Cloudflare D1", "PostgreSQL", "Resend") or plain phrases ("Web app", "P2P app").
  - Internal status codes (raw): `init-required`, `exceeds-max-lanes`, `corrupt-team`, `partial-lane`, `low-ram`, `swap-pressure`, `compressor-pressure`, `blocked-codex-auth`, `blocked-codex-error`, `subscription-or-quota`, `codex-no-op`, `suffixed-name`. If a status surfaces in chat, translate to plain language (e.g., `low-ram` → "memory is too low to spawn a new lane" / "メモリが足りないので新しいレーンを追加できません").
  - Internal config keys (as identifiers): `USE_CODEX`, `USE_GLOBAL_CLAUDE`, `USE_GITHUB_ISSUES`, `MAX_LANES`, `ARCHITECTURE`, `WEB_KIND`, `IOS_KIND`, `ANDROID_KIND`, `DESKTOP_KIND`, `BACKEND_KIND`, `DB_KIND`, etc. Show the *concept* ("Codex integration", "max parallel lanes"), never the key.
  - Internal file/script names (as identifiers): `SKILL.md`, `bootstrap.sh`, `spawn-lane-decision.sh`, `recommend-lanes.sh`, etc. These belong in operator docs, not in a Phase-2 interview question.
  - Code-like notation: `ARCHITECTURE = client-server`, `<field> = <value>`, etc. The user sees natural sentences.

  When in doubt: "would I show this string to a non-engineer end user?" — if no, it doesn't belong in a user-facing prompt. **Violation is a bug**, regardless of how technically accurate the term is.

- **Never ask a question whose answer is already implied by what the user said or by an approved mock.** Before composing any prompt, re-read the internal notes (without exposing their names to the user) and skip questions whose answer is already on file.
- **Drill down at least one level — and on hard topics, drill aggressively.** If a user answer is vague ("a chat app"), the immediate next question must narrow the space ("ephemeral or stored history? group or 1:1? media or text only?"). For probes around failure modes / resistance / scale / trust, push for concrete scenarios, not platitudes.
- **One question per turn.** Batch questions are prohibited.
- **Discovery before structure, structure before mocks, mocks before tools, tools before data.** Phases must run in order. Do not skip ahead.
- **Bilingual parity.** Every user-facing prompt and explanation has both an `LANG=en` and `LANG=ja` variant. After Phase 0, render only the chosen language.
- **No marketing / brand strategy / 5-year vision.** Stay system-relevant. Differentiation probe is allowed because it surfaces system constraints; "what's your North Star metric?" is not.

## Who executes this skill

This skill is a procedure that **Claude (you)** executes. Codex is an external supplementary LLM — Claude calls it by **launching `codex-ask.sh` via Bash**, reads the response, and incorporates it. Codex does not interact with the user directly.

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
| `<root>/.my-harness/` | Internal work files (Codex session IDs, init-state, discoverySheet, etc.) | Excluded via gitignore |

## Secret masking (strictly enforced)

If any of the following appear in user conversation, they must be masked before writing to any file:

| Type | Masked as |
|------|-----------|
| API keys / tokens (`sk-...`, `sk-ant-...`, `ghp_...`, `xoxb-...`, etc.) | `<MASKED:api-key>` |
| AWS access keys (`AKIA...`) | `<MASKED:aws-key>` |
| Passwords | `<MASKED:password>` |
| Email addresses | `<MASKED:email>` |
| Credentials embedded in URLs (`https://user:pass@...`) | `<MASKED:url-cred>` |
| Phone numbers | `<MASKED:phone>` |
| Credit card numbers | `<MASKED:cc>` |
| PEM private keys | `<MASKED:private-key>` |
| JWT three-part dot strings | `<MASKED:jwt>` |

Apply before writing to `docs/talk/` or `docs/spec/`. The pre-commit hook (`gitleaks` + `check-forbidden-patterns.sh`) provides a second layer.

---

## Flow (9 phases)

`language` → `setup` → `discovery` → `structure` → `features` → `visual` → `tools` → `data-model` → `bootstrap` → `tasks` → `completed`

`data-model` is skipped when the tools phase determines no DB AND `ARCHITECTURE=p2p-pure`. bootstrap.sh writes the state automatically (`current_phase: "bootstrap-completed"`).

### Phase numbering (canonical)

| # | Name | Purpose |
|---|------|---------|
| 0 | Language | en / ja |
| 1 | Setup | Orthogonal setup flags |
| 2 | Discovery | Open conversation + deep drill (failure / resistance / scale / trust / differentiation / day-2) |
| 3 | Structure | Architecture + platform multi-select only |
| 4 | Features | Complete feature list + deep per-feature drill |
| 5 | Visual | Logo + 3–5 mocks per platform; mocks become source of truth |
| 6 | Tools | Framework / backend / DB / package manager / email / e2e / Claude Code Action — informed by mocks |
| 7 | Data model | Per-entity drill (lifecycle / GDPR / permissions / cardinality / migration) |
| 8 | Bootstrap | Spec finalize + bootstrap.sh + issues / tasks |

### Managing init-state.json (for pause/resume)

At the completion of each phase, write the following. `current_phase` is the **next** phase to advance to; `phases_completed` is the list of **already finished** phases:

```bash
ROOT=<root>
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$ROOT/.my-harness"
cat > "$ROOT/.my-harness/init-state.json" <<EOF
{
  "schema_version": "3",
  "project_name": "<PROJECT_NAME>",
  "lang": "en",
  "root": "$ROOT",
  "current_phase": "<next phase>",
  "phases_completed": ["language", "setup", "discovery", "structure"],
  "next_action": "interview",
  "next_action_command": "Continue /my-harness-init (Phase: <next>)",
  "working_directory": "$ROOT",
  "discoverySheet": {
    "projectName": "...",
    "oneLineDescription": "...",
    "primaryUser": "...",
    "secondaryUsers": ["..."],
    "topUserActions": ["...", "...", "..."],
    "scaleExpectation": { "users": "1-100|100-10k|10k-1M|1M+", "dataSize": "MB|GB|TB", "concurrency": "low|medium|high" },
    "latencyTolerance": "ms|seconds|minutes",
    "offlineSupport": "none|cache-only|full-offline",
    "syncModel": "none|optimistic|eventual|strong",
    "privacy": { "pii": "none|minimal|sensitive|regulated", "compliance": ["gdpr", "hipaa", "soc2", "pci", "none"] },
    "architectureHints": "client-server|client-serverless|p2p-pure|p2p-hybrid|undecided",
    "persistenceHints": "relational|document|kv|file|hybrid|undecided",
    "uiSurfaceHints": ["web", "ios", "android", "desktop"],
    "failureModes": ["..."],
    "resistance": ["..."],
    "scaleBreakpoints": ["..."],
    "trustModel": "...",
    "differentiation": ["..."],
    "day2Operations": "...",
    "openQuestions": ["..."]
  },
  "visualMocks": [
    { "platform": "web", "screen": "Dashboard", "path": "dev/docs/design/mock-dashboard-1.png", "caption": "...", "decisionsRevealed": ["needs realtime", "needs filtering"] }
  ],
  "timestamp": "$TIMESTAMP"
}
EOF
```

### Pause/resume

When the user says "pause", "stop", or similar:
- Update `init-state.json`, `discoverySheet`, and `visualMocks` to the latest state, tell the user where it was saved and the resume command, then stop.

When the user comes back:
- Read `<root>/.my-harness/init-state.json` and check `current_phase`. Resume from the first question of that phase. Existing `docs/spec/`, `docs/design/`, and `docs/talk/` are carried forward.

### At startup: auto-detect init-state.json

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

**Pre-Phase 0 messages are also shown bilingually** because `LANG` isn't set yet:

- **State found** → call `AskUserQuestion` with question text:
  > "I found a saved interview at `<phase>`. Resume?  /  保存済みのインタビュー（`<phase>` 段階）が見つかりました。再開しますか？"
  >
  > Options: `Resume / 再開する` (description: "Continue from where you left off / 続きから再開") and `Start over / 最初からやり直す` (description: "Discard the saved state and start a fresh interview / 保存済み状態を破棄して新規インタビュー").

- **No state found** → no message at all. Go straight to Phase 0; do not announce that you couldn't find anything.

---

## Phase 0 — Language

**Use the `AskUserQuestion` Claude Code tool**. Do not write the bilingual prompt as plain markdown — that wraps badly in the CLI. Instead invoke `AskUserQuestion` with this exact shape:

```json
{
  "questions": [{
    "question": "What language should I use? — どの言語で進めますか？\n(Both our conversation and everything I generate — README, code comments, error messages — will be in your choice. / 私との会話も、これから生成する README・コードコメント・エラー文も、選んだ言語で書きます。)",
    "header": "Language",
    "multiSelect": false,
    "options": [
      { "label": "English",  "description": "Chat in English. README / docs / code comments / error messages will all be in English." },
      { "label": "日本語",  "description": "会話は日本語。README / ドキュメント / コードコメント / エラー文も全て日本語で書きます。" }
    ]
  }]
}
```

Read the user's selection. Map `English` → `LANG=en`, `日本語` → `LANG=ja`. Persist immediately.

**Acknowledgment — render ONLY the variant matching the chosen LANG (do NOT show both):**

- If `LANG=en` selected → "Got it — English from here. Next: a few quick setup choices, then a real conversation about what you're building, then visual mocks, then concrete tool picks."
- If `LANG=ja` selected → "了解しました、ここから日本語で進めます。次は簡単なセットアップ、その後で何を作るかをじっくり相談、ビジュアルモック、最後に具体的なツール選定の順です。"

Save to `.my-harness/.config` (first entry):
```
LANG=<en|ja>
```

Update `init-state.json` with `current_phase: "setup"`, `phases_completed: ["language"]`.

---

## ENFORCEMENT — language rules apply to every prompt from Phase 1 onward

**Critical:** The user's global `~/.claude/CLAUDE.md` may contain a directive like "Always respond in 日本語". That directive is overridden inside this skill once `LANG` is set. The interview, every generated prompt, every acknowledgment, every error message, and every clarifying question MUST be in the language the user picked in Phase 0 — even if the global file says otherwise. This skill's instructions are the contract; the global file does not apply to `/my-harness-init` interactions after Phase 0 completes.

**Every turn from Phase 1 onward, before composing any user-facing message:**

1. **Read `LANG` from authoritative source.** Run `grep -E "^LANG=" "$ROOT/.my-harness/.config" | cut -d= -f2` (or read `init-state.json`'s `lang` field). Confirm the value before composing the prompt.
2. **Render ONLY the matching variant.** Each question below has both an `LANG=en` block and an `LANG=ja` block. Output exactly the matching one, verbatim. Never render both. Never produce a mixed-language response.
3. **Free-form prompts (Phase 2 discovery drill, Phase 4 features drill, Phase 5 mock follow-ups, Phase 7 entity drill) MUST be composed in the chosen `LANG`.** When `LANG=en`, write the question in English; when `LANG=ja`, write in Japanese. This applies even when the user replies in the opposite language — keep emitting `LANG`.
4. **Codex prompts you compose for `codex-ask.sh`** stay in English regardless of `LANG` (Codex's role prefixes are English). The user-visible Codex output is then translated/rephrased by you into `LANG` before showing the user.
5. **If you accidentally output the wrong language**, immediately re-issue the message in `LANG` with a brief one-line apology in `LANG`.
6. **Variable interpolation, code blocks, file paths, shell commands, JSON keys, env var names** stay in their original ASCII form — only natural-language prose is language-switched.

This ENFORCEMENT block is non-negotiable. Treat it as a hard precondition for every output line.

---

## Phase 1 — Minimal setup (only orthogonal flags)

Ask the following one at a time. **Do not ask the project name here** — let it emerge from Phase 2's conversation. Only re-ask at the end of Phase 2 if it has not surfaced.

**Tool usage rule for Phase 1:** Q1 is free-text input (where to create the project). Q2 / Q2a–d / Q3 / Q4 MUST be asked via the `AskUserQuestion` Claude Code tool with named, descriptive options — never as `y/n` text prompts. The user picks from clearly labeled choices, not abbreviated boolean answers. Persist the underlying flag (`yes`/`no` etc.) based on which option was selected.

### Setup Q1: Project root directory

Free-text input (not `AskUserQuestion`).

**LANG=en:**
> "Where should the project live on disk? (default: `~/projects/<name>` once a name is settled, or `~/projects/my-project` as placeholder)"
>
> **What this controls:** Parent directory for source, worktrees, spec files. `<root>/dev` is the day-to-day worktree. Auto-created if missing.

**LANG=ja:**
> "プロジェクトをどこに作成しますか？（デフォルト: `~/projects/<プロジェクト名>`、未定なら `~/projects/my-project`）"
>
> **これが影響する箇所:** ソース・ワークツリー・spec の親ディレクトリ。`<root>/dev` が日常作業用。無ければ自動作成。

### Setup Q2: Codex integration

Use `AskUserQuestion` with **named options** (do NOT phrase as y/n):

**LANG=en — `AskUserQuestion` payload:**
```json
{
  "questions": [{
    "question": "Which AI helpers should drive this project?",
    "header": "AI helpers",
    "multiSelect": false,
    "options": [
      { "label": "Claude only", "description": "Default. Everything runs end-to-end with Claude alone — no extra setup. Visual phase falls back to text-only brand briefs (no generated logo/mocks)." },
      { "label": "Claude + Codex", "description": "Adds OpenAI's Codex CLI for second-opinion design/code review and `gpt-image-2` logo + UI mock generation. Requires `npm install -g @openai/codex` and `codex login` (ChatGPT subscription)." }
    ]
  }]
}
```

**LANG=ja — `AskUserQuestion` payload:**
```json
{
  "questions": [{
    "question": "このプロジェクトで使うAIヘルパーはどちら？",
    "header": "AIヘルパー",
    "multiSelect": false,
    "options": [
      { "label": "Claude のみ", "description": "デフォルト。追加セットアップ不要で Claude 単体で全機能が動作。ビジュアルフェーズはテキストのブランドブリーフに置換（ロゴ・モック画像は生成されません）。" },
      { "label": "Claude + Codex", "description": "OpenAI の Codex CLI を併用してセカンドオピニオン（設計・コードレビュー）と `gpt-image-2` でのロゴ・UIモック生成を有効化。`npm install -g @openai/codex` と `codex login`（ChatGPT サブスクリプション）が必要。" }
    ]
  }]
}
```

Map: `Claude only` / `Claude のみ` → `USE_CODEX=no`. `Claude + Codex` → `USE_CODEX=yes`. Re-enable later via `.my-harness/.config`.

#### If USE_CODEX=yes — sub-toggles

##### Q2a: Codex auth check

Codex CLI uses ChatGPT subscription auth via `codex login`. Run:

```bash
bash ~/my-harness-generator/scripts/check-codex-auth.sh
```

- `not-installed` →
  - **LANG=en:** "Codex CLI is not installed. Run `npm install -g @openai/codex` in another terminal, then type `done` here to re-check."
  - **LANG=ja:** "Codex CLI がインストールされていません。別のターミナルで `npm install -g @openai/codex` を実行してから、ここで `done` と入力して再確認してください。"
  - After 3 failures: auto-set `USE_CODEX=no` and continue without Codex.
- `not-logged-in` →
  - **LANG=en:** "Please run `codex login` in another terminal, then type `done` here to re-check. (After 3 failures I'll set USE_CODEX=no and continue without Codex.)"
  - **LANG=ja:** "別のターミナルで `codex login` を実行してから、ここで `done` と入力して再確認してください。（3 回失敗した場合は USE_CODEX=no に設定して Codex なしで続行します。）"
  - After 3 failures: auto-set `USE_CODEX=no` and continue without Codex.
- `logged-in` → confirm:
  - **LANG=en:** "Codex is authenticated via ChatGPT subscription. I'll resume Codex conversations in session `<PROJECT_SLUG>-init`."
  - **LANG=ja:** "ChatGPT サブスクリプションで Codex の認証を確認しました。セッション `<PROJECT_SLUG>-init` で会話を継続します。"

`CODEX_SESSION = <PROJECT_SLUG>-init`. Never asked.

##### Q2b: Who runs the engineer (implementation) subagent?

Use `AskUserQuestion` (do NOT phrase as y/n):

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "Who should run the engineer (implementation) subagent?",
    "header": "Engineer runner",
    "multiSelect": false,
    "options": [
      { "label": "Codex", "description": "Routes implementation work to Codex. Trade-off: separate AI surface, additional API round-trip, but Codex's coding model can differ from Claude's." },
      { "label": "Claude", "description": "Keep implementation in Claude. Trade-off: single AI surface, no Codex round-trip, but no second-opinion code generation." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "エンジニア（実装）サブエージェントは誰が担当しますか？",
    "header": "実装担当",
    "multiSelect": false,
    "options": [
      { "label": "Codex", "description": "実装を Codex に委任。AI サーフェスが分離し API ラウンドトリップが増えるが、Codex のコーディングモデルは Claude と異なる挙動を持つ。" },
      { "label": "Claude", "description": "実装は Claude のまま。AI サーフェスを 1 つに統一でき Codex ラウンドトリップ無し。コード生成のセカンドオピニオンは得られない。" }
    ]
  }]
}
```

Map: `Codex` → `USE_CODEX_ENGINEER=yes`. `Claude` → `USE_CODEX_ENGINEER=no`. No default applied.

##### Q2c: Who synthesizes the e2e failure report?

Use `AskUserQuestion`. Note: Playwright/Maestro themselves always run locally under Claude — this question only chooses **who composes the failure-report write-up afterward**.

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "Who should synthesize the e2e-reviewer failure report? (Playwright/Maestro always run locally under Claude regardless)",
    "header": "E2E reviewer",
    "multiSelect": false,
    "options": [
      { "label": "Claude", "description": "Claude both runs the tests and writes the failure-report synthesis. Single tool surface, no Codex round-trip." },
      { "label": "Codex", "description": "Claude runs the tests; Codex composes the failure-report write-up afterward. Adds a Codex round-trip but gives independent synthesis." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "e2e-reviewer の失敗レポートは誰が合成しますか？（Playwright/Maestro 自体は常に Claude がローカル実行）",
    "header": "E2Eレビュー担当",
    "multiSelect": false,
    "options": [
      { "label": "Claude", "description": "テスト実行と失敗レポート合成の両方を Claude が担当。AI サーフェスを 1 つに統一でき Codex ラウンドトリップ無し。" },
      { "label": "Codex", "description": "テストは Claude、失敗レポート合成のみ Codex に委任。Codex ラウンドトリップ 1 回増えるが独立した視点でのまとめが得られる。" }
    ]
  }]
}
```

Map: `Claude` → `USE_CODEX_E2E_REVIEWER=no`. `Codex` → `USE_CODEX_E2E_REVIEWER=yes`. No default applied.

##### Q2d: Who runs the reviewer (convention review) subagent?

Use `AskUserQuestion`:

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "Who should run the reviewer (convention review) subagent?",
    "header": "Reviewer runner",
    "multiSelect": false,
    "options": [
      { "label": "Codex", "description": "Convention/style review runs in Codex (second AI surface)." },
      { "label": "Claude", "description": "Convention/style review stays in Claude (single AI surface)." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "reviewer（規約レビュー）サブエージェントは誰が担当しますか？",
    "header": "レビュー担当",
    "multiSelect": false,
    "options": [
      { "label": "Codex", "description": "規約・スタイルレビューを Codex (別 AI サーフェス) で実施。" },
      { "label": "Claude", "description": "規約・スタイルレビューを Claude (単一 AI サーフェス) で実施。" }
    ]
  }]
}
```

Map: `Codex` → `USE_CODEX_REVIEWER=yes`. `Claude` → `USE_CODEX_REVIEWER=no`. No default applied.

If USE_CODEX=no, all three sub-flags forced to `no` (skip Q2b/c/d entirely).

### Setup Q3: Inherit global CLAUDE.md

Use `AskUserQuestion` (do NOT phrase as y/n):

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "How should this project handle your global `~/.claude/CLAUDE.md`?",
    "header": "Global CLAUDE.md",
    "multiSelect": false,
    "options": [
      { "label": "Inherit", "description": "Your personal global instructions in `~/.claude/CLAUDE.md` apply to this project too." },
      { "label": "Isolate", "description": "Writes `dev/.claude/settings.json` with `claudeMdExcludes` pointing at your absolute `~/.claude/CLAUDE.md` path so the project starts free of personal global instructions." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "個人グローバル `~/.claude/CLAUDE.md` をこのプロジェクトでどう扱いますか？",
    "header": "グローバル CLAUDE.md",
    "multiSelect": false,
    "options": [
      { "label": "引き継ぐ", "description": "`~/.claude/CLAUDE.md` の個人グローバル指示をこのプロジェクトでも適用。" },
      { "label": "切り離す", "description": "`dev/.claude/settings.json` の `claudeMdExcludes` に `~/.claude/CLAUDE.md` の絶対パスを登録し、このプロジェクトでは個人グローバル指示を読み込まない。" }
    ]
  }]
}
```

Map: `Inherit` / `引き継ぐ` → `USE_GLOBAL_CLAUDE=yes`. `Isolate` / `切り離す` → `USE_GLOBAL_CLAUDE=no`. No default applied.

### Setup Q4: Task management

Use `AskUserQuestion` with named options:

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "Where should tasks be tracked?",
    "header": "Task tracking",
    "multiSelect": false,
    "options": [
      { "label": "Local markdown", "description": "Task files live in `dev/docs/task/` as plain markdown — no GitHub account needed, fully offline-capable. Trade-off: no built-in collaboration / audit trail." },
      { "label": "GitHub Issues", "description": "Use `gh issue create` to manage tasks as GitHub Issues. Requires `gh` auth and a remote repo. Trade-off: full audit trail, collaboration UI, requires online GitHub access." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "タスク管理はどこで行いますか？",
    "header": "タスク管理",
    "multiSelect": false,
    "options": [
      { "label": "ローカルマークダウン", "description": "`dev/docs/task/` のマークダウンでタスク管理。GitHub アカウント不要、オフライン可。コラボレーション / 監査ログ機能は無い。" },
      { "label": "GitHub Issues", "description": "`gh issue create` を使って GitHub Issues でタスク管理。`gh` 認証とリモートリポジトリが必要。監査ログ・コラボレーション UI 完備、オンライン GitHub アクセス必須。" }
    ]
  }]
}
```

Map: `Local markdown` / `ローカルマークダウン` → `USE_GITHUB_ISSUES=no`. `GitHub Issues` → `USE_GITHUB_ISSUES=yes`. No default applied.

After all four are answered, update `init-state.json` with `current_phase: "discovery"`, `phases_completed: ["language", "setup"]`. Move to Phase 2.

---

## Phase 2 — Open discovery conversation (the centerpiece, deeper drill)

This is the longest and most important phase. **Plan for 15–40 turns** — do not bail early. The probes (failure modes, resistance, scale breakpoints, trust, differentiation, day-2 ops) typically add 5–10 turns over a basic flow.

Phase 2 starts with one open question and continues as a free-form, multi-turn conversation until the **exit criteria** below are met. There are no scripted questions here — Claude reads each answer, updates the internal `discoverySheet`, and composes the next question dynamically based on what is still missing or still vague.

### NON-NEGOTIABLE rules for this phase

**1. Discovery NEVER reduces scope.** The harness produces production-grade scaffolds. If the user has listed N features, all N are in scope. Frequency / volume / "how often" questions are **only for capacity targets** (peak RPS, peak concurrent writers, retention horizon) — never to suggest that a feature should be dropped. Phrasings like "if only 5/month then DB is overkill" or "if monthly then static SSG is enough" are **forbidden**. The harness does not scope down. It capacities up.

**2. Treat "全部 / max / フル装備 / all / everything / maximum / unlimited / 最高のもの / fully equipped" answers as a fast-path signal.** When the user gives any of these answers (or any clear "do not reduce scope" statement):
   - Set `scaleExpectation = "max"` (`users: "1M+"`, `dataSize: "TB"`, `concurrency: "high"`) unless the user provides specifics.
   - Skip any further volume / frequency / "how big" / "how often" probes.
   - Do **not** re-ask the same question hoping for a smaller number. Move on to **constraint** discovery (failure / trust / day-2 / privacy / latency budget).

**3. Read the user's first message completely before the first follow-up.** If their first message already enumerates ≥ 5 concrete features (e.g., "AI text, scheduled posts, ads, search, embeds, RSS, PWA, ..."), the feature scope is established. Do not ask "do you really need X". Move directly to architecture / constraint questions.

**4. No question may be asked twice in different phrasing.** If Claude's next planned question is a rewording of a question already asked, the planned question is dropped — pick a different empty `discoverySheet` field instead. The "no-redundancy check" below is **strict** — violating it is a bug.

**5. Probes describe constraints, not choices.** Reframe any "simple vs complex" probe as "what's the upper bound the system must handle". The user's scope is fixed; only the budget is being elicited.

**6. Universal-default policy (DO NOT ask about security / observability / quality / operations).** Production-grade defaults are decided by `rules/production.md` and applied **automatically** at bootstrap. The interview NEVER asks the user to choose between defense layers, log sinks, quality gates, or operational practices that have an industry-standard correct answer. The interview asks about **product** decisions (what features, what entities, what user-visible behavior), not about engineering practices.

   Specifically **forbidden** question patterns:

   | Forbidden | Why | What the harness does instead |
   |---|---|---|
   | "Which security layer should we invest in first?" / "シークレット混入の主犯はどっち？" | All layers always on by default | gitleaks pre-commit + GH Push Protection + GHA re-scan + Sentry source-map upload — all wired |
   | "Where should logs go?" / "ログ送信先は？" | pino default; env var override only | `infrastructure/logging/pino-logger.ts` with redact; user can wire Axiom/Datadog later |
   | "What encryption strength?" / "暗号化はどのくらい？" | Industry standard | TLS 1.3, bcrypt cost ≥ 12, AES-256, age for at-rest |
   | "Should we have rate limiting?" / "レート制限は？" | Always yes | `middleware/rate-limit.ts` with login/password-reset/api buckets |
   | "Backup retention?" / "バックアップ保持期間は？" | 30 d hot + 1 y cold default | Set in `rules/production.md`; user overrides only if regulator demands |
   | "CSP report-only vs enforce?" / "CSP は報告のみ・強制？" | report-only 7d → enforce auto | `docs/runbooks/deploy.md` documents the cutover |
   | "Should LLM auto-post require approval?" / "LLM 自動投稿に承認は要る？" | Yes, always — draft + human gate is the only sane default | Default for any auto-ingest path |
   | "How strict should TypeScript be?" / "TS の strict 設定は？" | Always strict | `tsconfig.json` has `strict: true`, `noImplicitAny`, `noUncheckedIndexedAccess` |
   | "Pre-commit hooks?" / "コミット前 hook は？" | Always yes | Husky + biome + commitlint + gitleaks |

   When in doubt: **apply the strictest production-grade default and document it in `rules/production.md` or a runbook**, do not surface it as a question.

**7. Question length cap.** Every question Claude sends to the user must fit in ≤ 5 lines as rendered. Long threat models / 4-layer frameworks / architectural explanations belong in `rules/` or `docs/` files for the agents to read silently — **not** in the user-facing question. If Claude needs > 5 lines of preamble to ask a question, the question is structurally wrong — break it into smaller atomic questions, or apply a default and skip asking entirely.

**8. Binary when binary, multi-choice only when it matters.** If the realistic answer space is yes/no (e.g., "include local-LLM auto-post in v1?"), ask yes/no. Do not synthesize 3-option questions where (C) is just "both of A and B with conditions" — that's a `yes` with caveats; ask "yes/no" and apply the caveats as defaults.

**10. Never force feature-ranking, "core" selection, or "MVP核" framing.** Once the user has listed N features, **all N are in scope** (Rule 1). Asking variants like:

- "Which **one** feature, without which this project has no reason to exist?"
- "What's the **core** that defines the MVP?"
- "If you had to pick **one** differentiator, which one?"
- "Rank these features by essentiality."
- "Which feature is the heart of the product?"
- Japanese variants: "これが無いなら作る意味がない、と一番強く感じる機能 1 つ" / "MVP の核を決めます" / "コア機能"

…are **forbidden**. They are scope-reduction disguised as discovery. The harness is **not** producing an MVP — it produces a production-grade scaffold that implements **all** features the user listed.

The differentiation probe (next section) asks **about competitive positioning** ("why does someone pick this over Notion/Substack/Ghost?") — that is allowed. It is **not** the same as "which of your features is THE one". Positioning is about the *whole product vs the world*; feature-ranking is about *cutting features from your own list*. Do not confuse them.

When the user has already said "実装すればいい / build everything / all of the above / 全部やる" or equivalent, **no further prioritization questions are allowed at all** — proceed to the next discoverySheet field.

**11. Proactively suggest ideas the user didn't mention** (additive only — never subtractive). When the user describes the product in Phase 2, after acknowledging what they said, name 2-4 features, behaviors, or concerns that adjacent products in the same category typically have **and that the user did not mention**. Frame each as an addition to consider, not a gap. Easy to ignore.

   Examples (compose in `$LANG` — both shown):

   **LANG=ja:**
   - User: "ブログを作りたい。AI で文章書ける、リッチエディタ、予約投稿、広告、検索、Skills エクスポート、動画埋め込み、X 投稿、サムネ、GSC/GA、ローカル LLM、Atom/RSS、PWA"
   - Acknowledge: "全部含めて進めます。"
   - Then suggest (one sentence each, max 4):
     - "下書き共有 URL (公開前に他人にプレビューさせる) もブログだとよく使われます。要りますか?"
     - "コメント欄を入れる場合、スパム対策 (Akismet 系 or hCaptcha) のチェックを後で挟みますか?"
     - "Webmention / トラックバック対応 (個人ブログ界で復活してる流れ) を入れますか?"
     - "シリーズ機能 (連載記事を順番にナビゲートできる) もよく出ます。"
   - Then: "要らないものは飛ばしてください。次は ◯◯ について聞きます。"

   **LANG=en:**
   - User: "I want to build a blog. AI-assisted writing, rich text editor, scheduled posts, ads, search, Skills export, video embeds, X posting, thumbnails, GSC/GA, local LLM, Atom/RSS, PWA"
   - Acknowledge: "Got it — all of those are in scope."
   - Then suggest (one sentence each, max 4):
     - "Preview-share URLs (let others read a draft before publishing) are common in blogs — want that?"
     - "If you're enabling comments, want a spam-filter step (Akismet / hCaptcha) added in?"
     - "Webmention / trackback support (making a comeback in indie blogs) — interested?"
     - "Series navigation (linking sequential posts in order) is also common."
   - Then: "Skip whatever doesn't fit. Next I'll ask about ◯◯."

   **Forbidden** when suggesting:
   - The words "MVP", "core", "essential", "must-have", "the one" — these imply ranking (Rule 10 violation).
   - "You're missing X" / "X が足りない" — that frames as a gap; banned. Use "X もよくあります" / "X も入れますか" instead.
   - More than 4 suggestions per turn (overwhelm).
   - Suggestions outside the product category (e.g., suggesting "newsletter" for a CLI tool).

   Source of suggestions: known features of well-known products in the same category (Ghost, Substack, Note, Hashnode for blogs; Linear, Jira, Asana for issue trackers; etc.). Do not invent novel features.

**9. Never ask for unknowable future predictions.** The user cannot know "how many readers in year 1", "how many users at year 3", "monthly PV after launch", "revenue forecast". These are guesses, not constraints. **Forbidden** patterns:
   - "1 年後の読者規模は？" / "PV はどれくらい？" / "ユーザー数の年 1/年 3 目安は？"
   - "How big does it get in year one? Year three?"
   - "What's the year-1 vs year-3 expected peak?"

   The harness builds for **autoscale by default** (Cloudflare Workers / D1 / KV / R2 scale to billions of requests transparently). Architecture decisions never ride on speculative growth numbers. The user volunteers concrete commitments (e.g., "we've signed a contract for 10k concurrent connections", "we've got 50k existing newsletter subscribers"); otherwise assume max and move on. If the user does volunteer a number, capture it in `discoverySheet.scaleExpectation` and proceed.

### Internal `discoverySheet` (the state Claude maintains)

Persist as `discoverySheet` inside `<root>/.my-harness/init-state.json`. Update after **every** user reply.

```json
{
  "discoverySheet": {
    "projectName": "...",
    "oneLineDescription": "...",
    "primaryUser": "...",
    "secondaryUsers": ["..."],
    "topUserActions": ["...", "...", "..."],
    "scaleExpectation": {
      "users": "1-100|100-10k|10k-1M|1M+",
      "dataSize": "MB|GB|TB",
      "concurrency": "low|medium|high"
    },
    "latencyTolerance": "ms|seconds|minutes",
    "offlineSupport": "none|cache-only|full-offline",
    "syncModel": "none|optimistic|eventual|strong",
    "privacy": {
      "pii": "none|minimal|sensitive|regulated",
      "compliance": ["gdpr", "hipaa", "soc2", "pci", "none"]
    },
    "architectureHints": "client-server|client-serverless|p2p-pure|p2p-hybrid|undecided",
    "persistenceHints": "relational|document|kv|file|hybrid|undecided",
    "uiSurfaceHints": ["web", "ios", "android", "desktop"],
    "failureModes": ["..."],
    "resistance": ["..."],
    "scaleBreakpoints": ["..."],
    "trustModel": "...",
    "differentiation": ["..."],
    "day2Operations": "...",
    "openQuestions": ["..."]
  }
}
```

Initialize all fields to empty / `undecided` at Phase 2 start.

### Exit criteria (stricter than before)

End Phase 2 when **(a) AND (b)**:

(a) The user explicitly says they're done ("that's all", "that's enough", "もう十分", "以上で") **or** Claude has cycled through all probe categories at least once with non-vague answers.

(b) The discoverySheet has at minimum **all of**:
- `oneLineDescription`
- `primaryUser`
- `topUserActions` (≥ 3)
- `scaleExpectation` (all three sub-fields)
- `latencyTolerance`
- `offlineSupport`
- `syncModel`
- `privacy.pii` and `privacy.compliance`
- `architectureHints`
- `persistenceHints`
- `failureModes` (≥ 2 concrete scenarios — not "anything could fail")
- `resistance` (≥ 1 concrete actor — "skeptical co-founder", "user's IT department", "spouse who pays the bill")
- `scaleBreakpoints` (≥ 1 concrete inflection point — "above 10k users the inbox sort breaks")
- `trustModel` (≥ 1 sentence describing why a user would entrust their data)
- `differentiation` (≥ 1 concrete competitor or alternative AND why this is different)
- `day2Operations` (≥ 1 sentence on what running this looks like in 6 months)

**Vague-entry rule:** if any field above contains a one-word filler ("everything", "fine", "nothing"), it does **not** count. Probe again.

If `projectName` is still empty when (b) hits, ask once before exit:
- **LANG=en:** "Before we move on, what should we call this project? (becomes directory name, package.json `name`, branch namespace)"
- **LANG=ja:** "ここまでで決めた範囲を踏まえて、プロジェクト名は何にしますか？（ディレクトリ名・package.json の `name`・ブランチ名前空間に使われます）"

### Opening prompt

- **LANG=en:** "Tell me about what you're building. Don't worry about format — start anywhere that feels natural. Your feature scope is **yours to set**; I won't try to talk you out of anything. What I will drill into is the constraints we'll need downstream: failure modes, capacity targets, who would object, what running it in 6 months looks like — those drive the architecture, not the feature list."
- **LANG=ja:** "作りたいものについて自由に話してください。形式は気にせず、自然に始まる場所から。**機能スコープを削る方向の質問はしません**。私が深掘りするのは、下流で必要になる制約（失敗パターン・容量目標・反対しそうな人・半年後の運用）です。それがアーキテクチャを決める材料になります。機能リストは尊重します。"

### How Claude asks open questions and drills down

After every user reply, run this internal checklist **before composing the next question**:

1. **Mask** the reply (apply secret-masking rules) and append to `dev/docs/talk/02-discovery.md`.
2. **Update the discoverySheet.** For every field the reply just touched, fill it in or refine it. Persist.
3. **Max-scope detector:** If the latest reply (or any prior reply in this phase) contains "全部 / max / フル装備 / all / everything / maximum / unlimited / 最高のもの / fully equipped", set `scaleExpectation` to max immediately and mark all volume / frequency probes as **already answered**. They must not be asked.
4. **Feature-list-from-first-message detector:** If the user's first message already listed ≥ 5 concrete features, mark `topUserActions` as derived from that list and do not probe for features again. Do not ask "do you need X" for anything in their first message.
5. **Drill check:** "Have I drilled at least one level deep on this?" If the answer is vague (one sentence, no specifics), the next question MUST narrow — but the narrowing question is about **constraint** (failure / latency / trust), not about cutting features.
6. **Probe-coverage check:** "Which of the six probes (failure / resistance / scale / trust / differentiation / day-2) have I touched, and which still hold a vague or empty value?" Prioritize whichever is empty.
7. **Coverage check:** "Which discoverySheet fields are still empty or vague?" The next question targets the most consequential one — typically the one that unlocks subsequent decisions (e.g., latency budget before architecture; privacy before backend choice; failure modes before persistence).
8. **No-redundancy check (STRICT):** "Have I already asked something close to this — same field, different wording?" If yes, the planned question is **dropped**. Asking the same question twice in different phrasing is a bug. Examples of the bug to avoid:
   - User: "全部大事" → "全部だと答えにならないので、月何本書く？"  ← banned: this is a rephrase, not a new question
   - User: "max scale" → "but specifically how many users?"            ← banned: max was already accepted
   - User: "ジャンル横断で" → re-state "ジャンル横断" then ask the same  ← banned: redundant echo
9. **One thing at a time:** ask exactly one question.

### Drill-down examples

The point is not to accept first answers as final. Examples:

- User: "It's a chat app."
  - Bad next question: "What features do you want?" (jumps too far)
  - Good next question (en): "Group or 1:1? Ephemeral or stored history? Media or text only?"
  - Good next question (ja): "グループチャットですか、1:1ですか？履歴は残しますか、消えますか？テキストだけですか、画像・動画もですか？"
- User: "Some kind of marketplace."
  - Good (en): "Two-sided marketplace? Who pays — buyers, sellers, both? Goods, services, or digital? How do listings get discovered?"
  - Good (ja): "二者間マーケットプレイスですか？支払うのは買い手・売り手・両方？商品・サービス・デジタル？出品はどう見つけてもらいますか？"
- User: "Just for me, maybe a few friends."
  - Good (en): "Is the data only useful to you (private), or do friends see each other's stuff (shared)?" (Do NOT ask for a year-1 user count — that's a guess, not a constraint.)
  - Good (ja): "データは自分専用（プライベート）ですか、友人同士で見える（共有）ですか？（年 1 のユーザー数は推測でしかないので聞かない）"
- User: "Should work on the subway."
  - Good (en): "So full offline write/read, then sync when online? Or read-only cache while offline?"
  - Good (ja): "オフラインでも書き込み・読み込みOK、繋がった時に同期？それともオフライン時は閲覧のみキャッシュ？"

### Open-question stems Claude can adapt (existing)

- **What does the user actually do with this?** ("walk me through a typical session, step by step")
- **Who's the primary user?** ("If only one type of person uses this, who?")
- **Who pays for the infrastructure?** (rules out free-tier-only / steers toward serverless vs always-on)
- **How do users find each other / find content?** (search, social graph, link-share, public feed)
- **Does the data have to stay on-device or in a region?** (privacy, residency)
- **What happens when two users edit the same thing at once?** (sync model)
- **What's the worst-case latency the user will tolerate?** (drives architecture)
- (REMOVED — banned by Rule 9. Do not ask for year-1 / year-3 size projections.)
- **Is there anything regulated about the data?** (HIPAA, GDPR, PCI, SOC2)
- **Is there a reason this can't run on a normal client + server?** (this surfaces P2P intuitions naturally)

### NEW probe stems — drill aggressively (use at least one from each category)

#### Failure modes (`failureModes`)
- **LANG=en:** "What's the worst-case scenario for a user — not the system crashing, but the bad outcome the user actually feels? (e.g. 'they show up to the wrong meeting', 'their photo is shared with the wrong group', 'their job application disappears')"
- **LANG=ja:** "ユーザーにとって最悪のシナリオは何ですか？システムが落ちるという話ではなく、ユーザー本人が痛みを感じる結果のこと。（例: 「違う会議に出てしまう」「写真が違うグループに共有される」「応募データが消える」）"
- Follow-ups: "How would they recover?" "Whose problem is it then — yours, theirs, or a third party's?"

#### Resistance (`resistance`)
- **LANG=en:** "Who in the user's life or organization would push back on them using this? (a skeptical co-founder, IT department, partner, regulator, an existing tool's vendor)"
- **LANG=ja:** "このプロダクトを使うことに、ユーザーの周りで反対しそうな人は誰ですか？（懐疑的な共同創業者、情シス、パートナー、規制当局、既存ツールのベンダー）"
- Follow-ups: "What's their concrete objection?" "How do you neutralize it — feature, policy, contract, screenshot?"

#### Scale breakpoints (`scaleBreakpoints`)
- **LANG=en:** "What's the **peak load** this system needs to handle without degrading? Concrete numbers, not 'a lot'. (e.g. 'peak 50 simultaneous editors', '10k rows in the dashboard with sub-2-second render', '100k articles searchable in <300ms p95'). These are **capacity targets** — not 'when do we cut features'. We will scale to meet them."
- **LANG=ja:** "このシステムが**ピーク時に**性能劣化なく処理する必要があるのは具体的にどの規模ですか？「沢山」じゃなく数字で。（例: 「同時編集ピーク 50」「ダッシュボード 1 万行 2 秒以内で描画」「10 万記事を p95 300ms 以内で検索」）これは**容量目標**です — 「ここを越えたら機能を諦める」ではなく、ここまで持つように作ります。"
- Follow-up (only if the user has volunteered concrete numbers): "Which target is hardest to meet — write throughput, query latency, or storage?" Do **not** ask the user to predict year-1 or year-3 peaks; the harness defaults to autoscale.

#### Trust (`trustModel`)
- **LANG=en:** "Why would a user trust this with their data? What's the concrete chain — encryption, audit, hosting choice, social proof, an org behind it, the user's own machine?"
- **LANG=ja:** "ユーザーはなぜ自分のデータをこれに預けると思いますか？暗号化・監査・ホスティング・社会的証明・運営組織・ユーザー自身のマシン上で動く、など、具体的な根拠の連鎖は？"
- Follow-ups: "Who could read this data if our DB leaked tomorrow?" "Is the answer different for the primary vs the secondary user?"

#### Differentiation (`differentiation`)

**Strict scope:** this probe is about **competitive positioning** (whole product vs the world), not about feature-ranking inside the user's own list. Do **not** ask "which feature is the core" / "what's the one feature without which it doesn't matter" — that's Rule 10 territory.

- **LANG=en:** "What's the closest existing service to what you're building? Why does someone pick yours over theirs? (One concrete framing per side, like 'Notion but offline-first' or 'Substack but self-hostable'.)"
- **LANG=ja:** "作ろうとしているものに一番近い既存サービスは？なぜ既存ではなくこっちを選ぶ？(片側ずつ具体的に。「Notion だがオフライン優先」「Substack だがセルフホスト可能」のような形)"
- Follow-up: "If their alternative dropped its main weakness next month, would this still have a reason to exist?"
- **Forbidden follow-ups:** "Which feature is the core?", "Which one feature without which this has no reason?", "Rank your features", "MVP の核は？" — all banned by Rule 10.

#### Day-2 operations (`day2Operations`)
- **LANG=en:** "Six months in, what does running this look like for whoever operates it? Backups? Bug-report inbox? On-call? Per-user support load? Something needs upgrading every 3 months?"
- **LANG=ja:** "リリースして半年後、運用する人にとっての日常はどうなっていますか？バックアップ・バグ報告対応・障害対応・1 ユーザーあたりのサポート負荷・3 ヶ月ごとの定期更新、など。"
- Follow-ups: "Is operations one person, a team, or fully automated?"

### Mid-conversation pulse-checks

Every ~5 turns, summarize the discoverySheet back to the user in one or two sentences and ask "Is that right? Anything to adjust?". Update the sheet from the correction.

### Exit ritual

When exit criteria met, **show the discoverySheet to the user as a formatted summary** (not raw JSON — use a numbered list grouped by topic, with the six new probes called out as their own block) and ask:

- **LANG=en:** "Here's what I have. Anything to correct or add before we move to the structural choices? Pay extra attention to the failure / resistance / scale / trust / differentiation / day-2 block — those drive everything downstream."
- **LANG=ja:** "ここまでの整理です。次の構造化された質問に進む前に、修正・追加はありますか？特に「失敗パターン・反対者・スケール限界・信頼根拠・差別化・運用」のブロックは下流すべてに効くので注意して見てください。"

If the user corrects, update sheet and repeat ritual. Once confirmed, persist final discoverySheet, write `dev/docs/spec/02-discovery.md` (the formatted summary), update `init-state.json` to `current_phase: "structure"`, and proceed to Phase 3.

If USE_CODEX=yes, **ask the user first** (Cardinal rule: Codex second-opinion is opt-in). If "yes", paste the discoverySheet JSON into `prompts/codex-consult-phase-2.md` placeholder, then run:
```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/consult-phase.sh" 2 "$ROOT"
```
Then summarize the findings in plain language. If "no", skip.

---

## Phase 3 — Structural decisions (architecture + platforms only)

Only **two** decisions are made here. Every concrete tool choice (framework, DB, package manager, email, e2e, Claude Code Action) is deferred to Phase 6, after we've seen the mocks. Re-read the discoverySheet first; skip a question whose answer is already locked.

When the discoverySheet already implies a decision, say it explicitly using the **user-visible label** (never the internal enum value) and skip:
- **LANG=en:** "Based on what you told me, this will be a `<user-visible label>` (because you mentioned `<plain-language reason>`). Skipping this question."
- **LANG=ja:** "ここまでの会話から `<user-visible ラベル>` で進めます（`<平易な理由>` のため）。この質問はスキップします。"

**Forbidden in skip messages:**
- Internal enum values like `client-server` / `client-serverless` / `p2p-pure` / `p2p-hybrid`
- Internal field names like `discoverySheet` / `architectureHints` / `ARCHITECTURE`
- Code-like notation like `ARCHITECTURE = client-server`

**Required in skip messages:**
- The user-visible label from each Decision's table (e.g., "Web アプリ" / "Web app")
- A plain-language reason summarized from the user's own words (not jargon)

Use the actual `AskUserQuestion` Claude Code tool. Up to 4 choices per question, max 4 questions per turn. Use `multiSelect: true` where appropriate. Use `preview` (single-select only) for choices that need comparison.

**Recommendation policy (strict):** **Never** add `(Recommended)` / `(推奨)` / "Default" / "デフォルト" to any choice label or description in any `AskUserQuestion` payload. The interview is the user's decision space; the harness must not steer it with unjustified opinions. Choices stay in neutral order, descriptions describe trade-offs only ("Trade-off: X but Y"). If a real user-derived justification exists in `discoverySheet` or `visualMocks[].decisionsRevealed`, surface it as a separate sentence before the question — never as a label on a choice.

**MVP wording is forbidden anywhere user-facing.** The harness generates production-grade scaffolds; never frame the project as "an MVP" in questions, descriptions, or generated docs. Use "first version", "initial release", or "before launch" instead.

### Decision 1 — Architecture (only when `architectureHints == "undecided"`)

Single-select. **User-facing labels MUST use standard product terms; never expose the internal `ARCHITECTURE` enum value to the user.** The labels below are what the user sees; the enum on the right is internal only.

| User-visible label (EN) | User-visible label (JA) | Preview | Internal enum |
|---|---|---|---|
| `Web app (server + database)` | `Web アプリ (サーバー + データベース)` | `[ブラウザ] ⇄ HTTPS ⇄ [サーバー] ⇄ [DB]` | `client-server` |
| `Serverless web app` | `サーバーレス Web アプリ` | `[ブラウザ] ⇄ HTTPS ⇄ [サーバーレス関数] ⇄ [DB]` | `client-serverless` |
| `P2P app (no central server)` | `P2P アプリ (中央サーバー無し)` | `[端末 A] ⇄ DHT / リレー ⇄ [端末 B]` | `p2p-pure` |
| `P2P app with bootstrap server` | `P2P アプリ + 軽量サーバー` | `[端末 A] ⇄ [調整サーバー] ⇄ [端末 B]、データは端末同士で直接` | `p2p-hybrid` |

**LANG=en question:** "What kind of app are you building? (preview shows where the data flows)"

**LANG=ja question:** "どんな種類のアプリですか？（プレビューはデータがどこを流れるかの図）"

Map user choice to internal `ARCHITECTURE` enum from the table above. Do **not** print the enum value back to the user; reference the chosen app type in subsequent skip messages using the user-visible label (e.g., "Web アプリで進めます", not "client-server で進めます").

### Decision 2 — Platforms (always, multiSelect)

`multiSelect: true`. Choices: `web`, `desktop`, `mobile`. At least one required (re-ask if empty).

**LANG=en:** "Which platforms? (one or more)"
**LANG=ja:** "対応プラットフォームは？（複数選択可）"

Persist `USE_WEB`, `USE_DESKTOP`, `USE_MOBILE` (intermediate; the per-mobile-OS sub-choice and per-OS sub-choice come below).

#### Decision 2a — Mobile platform split (only when `mobile` selected)

`multiSelect`: `iOS`, `Android`. At least one. Persist `USE_IOS`, `USE_ANDROID`.

#### Decision 2b — Desktop OS multi-select (only when `desktop` selected)

`multiSelect`: `macOS`, `Windows`, `Linux` (default all). Persist `DESKTOP_OS`.

### After Phase 3

Update `init-state.json` to `current_phase: "features"`, `phases_completed: ["language", "setup", "discovery", "structure"]`. Save Phase 1 + 3 partial decisions to `dev/docs/spec/03-structure.md`. Move to Phase 4. (Concrete tool choices wait for Phase 6.)

If USE_CODEX=yes, **ask the user first** (Cardinal rule). If "yes":
```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/consult-phase.sh" 3 "$ROOT"
```
Then summarize the findings in plain language. If "no", skip.

---

## Phase 4 — Features (deeper drill)

**Question (one per turn):**

- **LANG=en:** "List every feature this project needs. Don't trim — list everything required before you'd call this complete. One per line. Continue until you have nothing more to add."
- **LANG=ja:** "このプロジェクトに必要な機能をすべて挙げてください。削らずに、『これで完成』と言える状態に必要な全機能を一行ずつ挙げてください。これ以上書くものが無くなるまで続けてください。"

Stop only when the user explicitly says "that's all" / "以上で" / equivalent. Then re-read the list and run the deep drill below per feature.

### Per-feature drill (deeper — 8 probes per feature, one question per turn)

For **each** feature listed, drill **at least 8 follow-ups**, one per turn:

1. **Access path:** "How does the user reach this feature? (route, button, gesture)"
   - **LANG=ja:** "どこからこの機能にたどり着きますか？（URL・ボタン・ジェスチャー）"
2. **Failure modes:** "What goes wrong, and what does the user see when it does?"
   - **LANG=ja:** "失敗するパターンは？そのときユーザーには何が見えますか？"
3. **Observability:** "Do we need analytics or alerting on this feature? If yes, which event/metric?"
   - **LANG=ja:** "分析やアラートは必要ですか？必要なら、どのイベント・指標？"
4. **Onboarding hand-off:** "How does a brand-new user discover this feature for the first time? Tooltip, empty-state CTA, onboarding tour, or just by looking at the screen?"
   - **LANG=ja:** "初めてのユーザーは、この機能の存在をどう知りますか？ツールチップ・空状態のCTA・オンボーディングツアー・画面を見れば自明、のどれですか？"
5. **Power-user shortcut:** "What does a 100th-time user want? Keyboard shortcut, bulk action, saved filter, API access?"
   - **LANG=ja:** "100 回目のユーザーが欲しがるのは何ですか？キーボードショートカット・一括操作・保存フィルター・API、など？"
6. **Empty state:** "What does this feature show when there's no data yet? (a brand-new user, an emptied-out view)"
   - **LANG=ja:** "データがまだ無いとき、この機能は何を表示しますか？（新規ユーザー・データを全部消した状態）"
7. **Failure recovery:** "If this feature errors mid-flow (network drop, validation fail, server 500), what does the user see and what do they do next?"
   - **LANG=ja:** "この機能の途中でエラーが出たとき（通信断・検証失敗・サーバ 500）、ユーザーには何が見え、次に何をしますか？"
8. **Latency budget:** "What's the max wait time before a user gives up on this feature? Concrete number — 200ms? 1s? 5s? Are we OK with a spinner or do we need optimistic UI?"
   - **LANG=ja:** "この機能で『遅い』と感じるユーザーが諦めるまでの最大待機時間は具体的に何秒ですか？200ms? 1秒? 5秒? スピナーで OK か、楽観的 UI が要るか？"

### Re-read sweep

After the user says they're done, **re-read the feature list** and verify every feature has all 8 drill answers. For any feature missing onboarding / power / empty / fail / latency entries, ask once more for that specific feature's gap. Only then exit Phase 4.

Save to: `dev/docs/spec/04-features.md` / `dev/docs/talk/04-features.md` (one section per feature with the 8 drill answers).

Each feature listed becomes one or more issues / task files at /harness-team-lead time. The list is the source of truth for what this project delivers.

If USE_CODEX=yes, **ask the user first** (Cardinal rule). If "yes":
```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/consult-phase.sh" 4 "$ROOT"
```
Then summarize findings in plain language. If "no", skip.

Update `init-state.json` to `current_phase: "visual"`.

---

## Phase 5 — Visual (logo + per-platform UI mocks; mocks are source of truth)

The mocks generated here become the **source of truth** for Phase 6 (tool selection) and Phase 7 (data model). Their visible elements (lists, forms, toggles, tabs, charts, real-time indicators, offline banners) are the inputs for tool decisions.

**Absolute image format rules:**
- **PNG only.** SVG is **prohibited** as a generated format. Transparent PNG (alpha background) is allowed.
- Resolution: logos ≥ 1024×1024; UI mocks at the resolution specified below.
- After generation, **always auto-open** so the user can review:
  - macOS: `open <path>`
  - Linux: `xdg-open <path>`
  - Windows: `start "" <path>`
  - Detect OS with `uname`.

**Prompting strategy:** trust Codex's designer capability — give a high-level request and let it decide. Pass spec files via `--context dev/docs/spec/*.md` and keep the request brief.

**Never write:**
- Code-style instructions (coordinates, pixel values, CSS, Tailwind classes, SVG paths, HTML tags)
- Over-specification of visual details

**Do write:**
- What to create and how many concepts
- Format (PNG), save path, resolution
- Assume Codex will read the context

**Fixed questions** (one per turn — use the variant matching `LANG`):

1. **LANG=en:** "Any color hint for the design? (optional — e.g. `#14b8a6` / 'blue tones' / 'no preference')"
   **LANG=ja:** "デザインの色のヒントはありますか？（任意 — 例: `#14b8a6` / 「青系」/ 「特になし」）"

2. **For each chosen platform**, ask separately:
   **LANG=en:** "List the 3–5 most-traveled screens for the `<platform>` build." (e.g. for web: Login / Home / Detail / Settings / Search)
   **LANG=ja:** "`<プラットフォーム>` 版で最も使われる画面を 3〜5 個リストアップしてください。"

   Repeat per chosen platform — so a project that picked `web + ios` will yield 3–5 web mocks AND 3–5 iOS mocks.

### Design philosophy

**Trust Codex's imagination.** The harness gives Codex the spec and lets it design freely — palette, type, icon language, layout are all Codex's call. Only technical constraints (format, save path, "use image_gen, not HTML/SVG") are dictated. The implementation phase reconciles to `rules/design.md` later. No logo generation step exists; the harness scaffolds the page directly.

### Page + parts grid generation (per screen, per platform)

For each screen in each platform's list, the harness generates a single high-quality PNG that contains **two stacked sections** in one image:

- **Top 65 %:** the full page mock at native aspect ratio.
- **Bottom 35 %:** a 4-column grid of every distinct UI component used in the page above, each component isolated, labeled, in its own cell, with no overlap. Every state variant (hover / active / disabled / selected) is its own cell.

This is one Codex call per screen. Generated at the highest resolution available (target 2048 × 2880).

**Ask first** (Cardinal rule: Codex opt-in per occurrence). If the user says yes:

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/gen-page-parts.sh" \
  "$ROOT" "<platform>" "<screen-name>" "$PROJECT_NAME"
```

Auto-open the resulting PNG (`open` / `xdg-open` / `start`) so the user can review.

The prompt body lives at `prompts/codex-page-and-parts.md` — edit it there, not in this SKILL.

### Iterative refinement

When the user says "the buttons should be more rounded" or "this card needs a shadow", **resume the same Codex session** (don't re-attach `--context`, don't pass `--reset-session`):

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/codex-ask.sh" \
  --role designer \
  --out "$ROOT/.my-harness/codex-page-<platform>-<screen-slug>-r1.md" \
  "Apply this change: <user's edit request>. Regenerate and overwrite the same PNG path."
```

Iterate until the user approves. Once approved, proceed to the cropping step below.

### Slicing the parts grid into individual PNGs

Once the user approves the page+parts image, read the bottom 35 % via Vision and produce a manifest at `$ROOT/dev/docs/design/parts/<platform>/<screen-slug>/manifest.json`:

```json
{
  "rows": 3,
  "cells": [
    { "row": 0, "col": 0, "name": "primary-button" },
    { "row": 0, "col": 1, "name": "primary-button-hover" },
    { "row": 0, "col": 2, "name": "primary-button-disabled" }
  ]
}
```

`name` is a `kebab-case` slug derived from the visible label under each cell.

Then crop deterministically:

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/crop-parts.sh" \
  "$ROOT" "<platform>" "<screen-slug>" \
  "$ROOT/dev/docs/design/parts/<platform>/<screen-slug>/manifest.json"
```

Output: `$ROOT/dev/docs/design/parts/<platform>/<screen-slug>/<name>.png` for every cell.

Requires ImageMagick (`magick` or `convert` on `$PATH`). If missing, surface plainly: "ImageMagick is required for slicing the parts grid. Install with `brew install imagemagick` (macOS) or `apt install imagemagick` (Linux), then retry."

### TSX component extraction

For every cropped part PNG, read the image (Vision) and write a real React + Tailwind component at:

```
$ROOT/dev/src/components/design/<platform>/<screen-slug>/<PartName>.tsx
```

Each component:

- Implements the visual using Tailwind classes (or `rules/design.md`-compliant CSS).
- Uses Lucide icons where icons appear.
- Accepts props matching the visible variants (`disabled`, `variant`, `size`, etc.) — one prop per state variant seen in the grid.
- Includes a `/** 概要: ... */` JSDoc comment naming the part.
- Imports nothing AI-style (no gradients, no purple-blue gradients per `rules/design.md`).

The cropped PNG remains as a reference (path noted in JSDoc); the TSX component is the canonical implementation used by `harness-team-lead` during the build phase.

### Crucial post-mock drill (NEW — runs after EVERY mock)

After each mock is shown to the user, ask exactly these 3 questions, one per turn:

1. **Missing element:**
   - **LANG=en:** "Is anything missing from this screen that the user needs to complete their task here?"
   - **LANG=ja:** "この画面で、ユーザーがやりたいことを完遂するのに足りない要素はありますか？"
2. **Confusing / low-priority element:**
   - **LANG=en:** "Is any element on this screen confusing, redundant, or unnecessary?"
   - **LANG=ja:** "この画面の中で、ユーザーが混乱しそう・冗長・不要、と感じる要素はありますか？"
3. **Hidden constraint:**
   - **LANG=en:** "Does this mock reveal any constraint we haven't discussed yet — a new entity, new permission, new external integration, a dependency we hadn't named? If so, I'll record it and adjust later questions."
   - **LANG=ja:** "このモックを見て、まだ会話に出ていない新しい制約（新しいエンティティ・権限・外部連携・依存）が浮かびましたか？あれば記録して、以降の質問に反映します。"

### Persisting mocks

Append every accepted mock to `init-state.json`'s `visualMocks`:

```json
{
  "visualMocks": [
    {
      "platform": "web",
      "screen": "Dashboard",
      "path": "dev/docs/design/mock-web-dashboard-1.png",
      "caption": "Realtime metrics with filter chips and an offline banner",
      "decisionsRevealed": ["needs realtime", "needs offline indicator", "needs at-least-3 chart variants"]
    }
  ]
}
```

`decisionsRevealed` is the single most important field — it's what Phase 6 reads to make tool choices.

### Iteration

If a mock reveals that requirements have changed (the answer to drill #3 surfaces a new entity, permission, or integration), update the discoverySheet, log the constraint, and either regenerate the affected mock or note it for Phase 6 / 7. **Maximum 3 iteration cycles per screen.**

When USE_CODEX=no, skip image generation and instead, for each screen, **draft a text mock** (markdown bullet list of visible elements) and run the same 3-question post-mock drill. Persist the text mock under `dev/docs/design/text-mock-<platform>-<screen>.md` and reference it from `visualMocks[].path`.

### Completion criteria

- [ ] One logo concept finalized
- [ ] 3–5 mocks selected per chosen platform (USE_CODEX=yes only; text mocks otherwise)
- [ ] Every mock has the 3-question post-mock drill answered
- [ ] OG image / favicon generated
- [ ] `visualMocks[]` in `init-state.json` populated, `decisionsRevealed` non-empty for every entry

Save to: `dev/docs/spec/05-visual.md` / `dev/docs/design/{logo-*,mock-*,og,favicon}.png`. Update `init-state.json` to `current_phase: "tools"`.

---

## Phase 6 — Tool selection (informed by mocks)

Now we pick concrete tools, **with the mocks open**. Every prompt below MUST reference at least one entry from `visualMocks[].decisionsRevealed`. If a tool is fully implied by discoverySheet AND visualMocks, skip with explicit notice.

For each decision:
1. Re-read the discoverySheet, structural decisions, and visualMocks.
2. If the answer is implied, skip with notice (en: "From the dashboard mock you approved, you'll need real-time updates, so I'm choosing X. Skipping the question." / ja: "承認いただいたダッシュボードモックからリアルタイムが必要なので X を選びます。質問はスキップします。")
3. Otherwise fire `AskUserQuestion`. The question prompt **must include a one-line reference to which mock(s) drove the question.**

### Decision 1 — Package manager (always)

Single-select.

| Choice | Note |
|--------|------|
| `pnpm` | fastest cold install, content-addressable store, monorepo-friendly |
| `bun` | faster runtime, native test runner, single binary |
| `npm` | universal, slowest |
| `yarn` | classic alternative |

**LANG=en:** "From your mocks (count of npm-package-driven UI surfaces visible: <N>), which Node package manager?"
**LANG=ja:** "モックから見える npm パッケージ依存の UI サーフェス数 <N> を踏まえて、Node のパッケージマネージャーは？"

Persist `PACKAGE_MANAGER=pnpm|bun|npm|yarn`.

### Decision 2 — Web framework (only when `web` selected)

Single-select with `preview`.

| Choice | Preview |
|--------|---------|
| `Next.js` | `app/`, `app/api/`, RSC, edge or node runtime |
| `TanStack Start` | `routes/`, file-based, fully typed, type-safe loaders |
| `SvelteKit` | `src/routes/`, server hooks, light footprint |

**LANG=en (template):** "Your web mocks show <X> (e.g. 'real-time activity feed', 'heavy form-driven settings page', 'SEO-driven public landing'). Which web framework?"
**LANG=ja (template):** "Web モックには <X>（例: 「リアルタイム活動フィード」「重いフォーム中心の設定画面」「SEO 重視の公開 LP」）が見えます。Web フレームワークは？"

Persist `WEB_KIND=nextjs|tanstack|sveltekit`.

### Decision 3 — iOS framework (only when iOS chosen)

| Choice | Note |
|--------|------|
| `Swift / SwiftUI` | native, App Store standard |
| `Expo (React Native)` | cross-platform with Android, JS/TS shared |
| `Flutter` | Dart, cross-platform, custom rendering |

**LANG=en (template):** "Your iOS mocks show <X> (e.g. 'native sheet/segmented control', 'shared component vocabulary with web', 'heavy custom canvas'). iOS framework?"
**LANG=ja (template):** "iOS モックには <X>（例: 「ネイティブの sheet / segmented control」「Web と共通のコンポーネント語彙」「重いカスタム canvas」）が見えます。iOS フレームワークは？"

Persist `IOS_KIND=swift|expo|flutter`.

### Decision 4 — Android framework (only when Android chosen)

| Choice | Note |
|--------|------|
| `Kotlin / Compose` | native, Play Store standard |
| `Expo (React Native)` | cross-platform with iOS |
| `Flutter` | Dart, cross-platform |

**LANG=en (template):** "Your Android mocks show <X>. Android framework?"
**LANG=ja (template):** "Android モックには <X> が見えます。Android フレームワークは？"

Persist `ANDROID_KIND=kotlin|expo|flutter`.

If both iOS and Android are chosen and select the same cross-platform framework (Expo or Flutter), tell the user they share one codebase. If they pick different cross-platform frameworks, warn and suggest aligning.

### Decision 5 — Desktop framework (only when `desktop` selected)

Framework single-select with `preview`:

| Choice | Preview |
|--------|---------|
| `Tauri` | `src-tauri/`, `~10MB binaries`, Rust shell |
| `Electron` | full Node.js, ~120MB binaries, mature ecosystem |

**LANG=en (template):** "Your desktop mocks show <X> (e.g. 'tray-resident with notifications', 'OS-integrated file picker', 'multi-window'). Desktop framework?"
**LANG=ja (template):** "Desktop モックには <X>（例: 「常駐 + 通知」「OS ネイティブのファイルピッカー」「複数ウィンドウ」）が見えます。Desktop フレームワークは？"

Persist `DESKTOP_KIND=tauri|electron`.

### Decision 6 — Backend framework (only when `ARCHITECTURE in {client-server, p2p-hybrid}`)

Skip when `ARCHITECTURE in {client-serverless, p2p-pure}`.

| Choice | Note |
|--------|------|
| `Hono on Cloudflare Workers` | edge, TypeScript, sub-50ms cold start |
| `Go (Gin)` | mature, fast, large standard library |
| `Rust (Axum)` | typed, performant, steep ramp |

**LANG=en (template):** "Your mocks reveal <X> (e.g. 'streaming responses', 'CPU-bound image processing', 'low-latency edge requirements'). Backend framework?"
**LANG=ja (template):** "モックから読み取れる <X>（例: 「ストリーミング応答」「CPU バウンドな画像処理」「エッジ低レイテンシ」）を踏まえて、バックエンドフレームワークは？"

Persist `BACKEND_KIND=hono|gin|rust`.

For `p2p-hybrid`, the backend is a lightweight coordinator/bootstrap server (signaling, peer discovery, optional auth). Tell the user this in the question copy.

### Decision 7 — Database (skip when `persistenceHints == "file"` or `ARCHITECTURE == "p2p-pure"`)

| Choice | Note |
|--------|------|
| `Cloudflare D1` | SQLite at edge, pairs well with Workers |
| `PostgreSQL` | full SQL, JSON, suited for gin/rust with heavy joins |
| `MySQL` | full SQL alternative |
| `SQLite (local)` | embedded, single-file |

Recommendation flips based on `BACKEND_KIND` and what the mocks reveal:
- `hono` + mocks show edge / global users → D1
- `gin` / `rust` + mocks show heavy joins / analytics → PostgreSQL
- `p2p-hybrid` with light backend → D1 or SQLite
- No backend / mocks show offline-first → SQLite (local)

**LANG=en (template):** "Your mocks show <X> entities and <Y> relationships (e.g. 'a comments tree on the post detail screen', 'a per-user notification stream'). Database?"
**LANG=ja (template):** "モックから見えるエンティティ <X> 個・関係 <Y> 個（例: 「投稿詳細にコメントツリー」「ユーザー別の通知ストリーム」）を踏まえて、データベースは？"

Persist `DB_KIND=d1|postgres|mysql|sqlite|none` (none when skipped).

### Decision 8 — Email (always, single-select)

| Choice | Note |
|--------|------|
| `Resend` | modern API, React Email templates |
| `SendGrid` | enterprise standard |
| `none` | no transactional email |

**LANG=en (template):** "Your mocks show <X email touchpoints> (e.g. 'password reset', 'invite flow', 'digest email'). Email provider?"
**LANG=ja (template):** "モックから見えるメール接点 <X>（例: 「パスワードリセット」「招待フロー」「ダイジェストメール」）を踏まえて、メールプロバイダーは？"

Persist `USE_EMAIL=yes|no` and `EMAIL_KIND=resend|sendgrid|none`.

### Decision 9 — Authentication (always, single-select; skip if discoverySheet implies)

| Choice | Note |
|--------|------|
| `OAuth` | social sign-in, less password handling |
| `Password (email + password)` | full control, more compliance burden |
| `none` | no auth |

**LANG=en (template):** "Your login/signup mocks show <X>. Auth method?"
**LANG=ja (template):** "ログイン / サインアップモックには <X> が見えます。認証方式は？"

Persist `AUTH_KIND=none|password|oauth`.

### Decision 10 — E2E testing (always, multiSelect)

`multiSelect` choices:

- `Playwright (web/desktop)`
- `Maestro (mobile)`
- `none`

Filter to the user's chosen platforms (don't offer Playwright if no web/desktop, don't offer Maestro if no mobile). Persist `E2E_SCOPE=web|mobile|both|none`, derived `USE_PLAYWRIGHT` / `USE_MAESTRO`.

**LANG=en (template):** "Mocks span <platforms>. Pick E2E tools to cover them."
**LANG=ja (template):** "モックは <platforms> にまたがります。E2E ツールを選んでください。"

### Decision 11 — Claude Code Action (always)

Use `AskUserQuestion` with named options (do NOT phrase as y/n):

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "Should this project use Claude Code Action for automated PR review on GitHub?",
    "header": "PR review automation",
    "multiSelect": false,
    "options": [
      { "label": "Enable automated PR review", "description": "Installs the GitHub Action that auto-reviews pull requests with Claude. Requires either OAuth or an API key (asked next)." },
      { "label": "Skip PR automation", "description": "No GitHub Action is installed. PR reviews stay fully manual." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "Claude Code Action による PR 自動レビューを使いますか？",
    "header": "PR自動レビュー",
    "multiSelect": false,
    "options": [
      { "label": "自動 PR レビューを有効化", "description": "Claude が PR を自動レビューする GitHub Action をインストール。OAuth か API キーのいずれかが必要（次の質問で選択）。" },
      { "label": "PR 自動化を入れない", "description": "GitHub Action は入れず、PR レビューは完全に手動。" }
    ]
  }]
}
```

Map: `Enable automated PR review` / `自動 PR レビューを有効化` → `USE_CLAUDE_ACTION=yes`. `Skip PR automation` / `PR 自動化を入れない` → `USE_CLAUDE_ACTION=no`.

If `USE_CLAUDE_ACTION=yes`, follow up with auth method via `AskUserQuestion`:

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "Which Claude auth should the GitHub Action use?",
    "header": "Action auth",
    "multiSelect": false,
    "options": [
      { "label": "OAuth", "description": "Browser-based one-time login. No API key in repo secrets." },
      { "label": "API key", "description": "Anthropic API key stored in `ANTHROPIC_API_KEY` repo secret. Bills the key's account directly." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "GitHub Action で使う Claude 認証方式は？",
    "header": "Action 認証",
    "multiSelect": false,
    "options": [
      { "label": "OAuth", "description": "ブラウザでワンタイムログイン。リポジトリ Secrets に API キーを置かなくて済む。" },
      { "label": "API キー", "description": "Anthropic API キーを `ANTHROPIC_API_KEY` Secrets に保存。キーのアカウントへ直接課金。" }
    ]
  }]
}
```

Persist `CLAUDE_AUTH=api|oauth`.

### After Phase 6

Save the consolidated config to `<root>/.my-harness/.config`:

```bash
mkdir -p <root>/.my-harness <root>/dev/docs/spec <root>/dev/docs/design <root>/dev/docs/talk <root>/dev/docs/task

cat > <root>/.my-harness/.config <<EOF
LANG=<en|ja>
PROJECT_NAME=<from discoverySheet.projectName>
PROJECT_SLUG=<derived lowercase-hyphen>
ROOT=<root>
USE_CODEX=<yes|no>
CODEX_SESSION=<PROJECT_SLUG>-init
USE_CODEX_ENGINEER=<yes|no>
USE_CODEX_E2E_REVIEWER=<yes|no>
USE_CODEX_REVIEWER=<yes|no>
ON_CODEX_AUTH_FAIL=pause
USE_GITHUB_ISSUES=<yes|no>
USE_GLOBAL_CLAUDE=<yes|no>
USE_WEB=<yes|no>
WEB_KIND=<nextjs|tanstack|sveltekit>
USE_IOS=<yes|no>
IOS_KIND=<swift|expo|flutter>
USE_ANDROID=<yes|no>
ANDROID_KIND=<kotlin|expo|flutter>
USE_DESKTOP=<yes|no>
DESKTOP_KIND=<tauri|electron>
DESKTOP_OS=macos,windows,linux
USE_BACKEND=<yes|no>
BACKEND_KIND=<hono|gin|rust>
USE_DB=<yes|no>
DB_KIND=<d1|postgres|mysql|sqlite|none>
USE_EMAIL=<yes|no>
EMAIL_KIND=<resend|sendgrid|none>
AUTH_KIND=<none|password|oauth>
E2E_SCOPE=<web|mobile|both|none>
USE_PLAYWRIGHT=<yes|no>
USE_MAESTRO=<yes|no>
USE_CLAUDE_ACTION=<yes|no>
CLAUDE_AUTH=<api|oauth>
PACKAGE_MANAGER=<pnpm|bun|npm|yarn>
ARCHITECTURE=<client-server|client-serverless|p2p-pure|p2p-hybrid>
EOF
```

The two keys `PACKAGE_MANAGER` and `ARCHITECTURE` go at the **end** of the file so older readers stay compatible.

When USE_CODEX=yes, register the active session pointer:
```bash
~/my-harness-generator/scripts/codex-ask.sh --set-active <root>
```

`PROJECT_SLUG` derivation (internal, never shown):
```bash
PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
```

Save phase 1+3+6 results to `dev/docs/spec/06-tools.md` and `dev/docs/talk/06-tools.md`. Update `init-state.json` to `current_phase: "data-model"`.

If USE_CODEX=yes, **ask the user first** (Cardinal rule). If "yes":
```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/consult-phase.sh" 6 "$ROOT"
```
Then summarize findings in plain language. If "no", skip.

---

## Phase 7 — Data model (deeper drill)

Skip entirely when `DB_KIND=none` AND `persistenceHints=file` AND `ARCHITECTURE=p2p-pure`. Otherwise:

### 7.0 Reverse-engineer the initial entity sketch

Before asking the user, draft an initial entity list **from**:
- `discoverySheet.topUserActions` — actions imply nouns (entities)
- Every `visualMocks[].decisionsRevealed` entry — visible lists, forms, charts each imply entities and fields

Show the draft to the user:
- **LANG=en:** "From your mocks and the actions we discussed, I see these entities: <list>. Does that match? Anything missing or wrongly grouped?"
- **LANG=ja:** "モックと先ほど挙げた主要アクションから、エンティティを次のように推測しました: <一覧>。合っていますか？足りないもの・くくりが間違っているものは？"

Update from the user's correction.

### 7.1 Initial questions (one per turn — use the variant matching `LANG`)

1. **LANG=en:** "Confirm or adjust the entity list — 3–7 entities for this project."
   **LANG=ja:** "プロジェクトのエンティティ一覧を確定してください（3〜7 個）。"
2. **LANG=en:** "Bullet out the main fields for each entity."
   **LANG=ja:** "各エンティティの主なフィールドを箇条書きで教えてください。"
3. **LANG=en:** "Describe relationships in mermaid ER style." (e.g. User 1—N Task)
   **LANG=ja:** "エンティティ間のリレーションシップを mermaid ER スタイルで説明してください。"

### 7.2 Mermaid ER preview

Claude assembles a **draft mermaid ER diagram** and shows it back, asking:
- **LANG=en:** "Here's the ER diagram I drew from your sketch. Anything to edit?"
- **LANG=ja:** "ご提示内容から ER 図を起こしました。修正点はありますか？"

### 7.3 Per-entity deep drill (NEW — 7 probes per entity, one per turn)

For **each** entity, drill **at least 7 follow-ups** in this order:

1. **Lifecycle:** when does it get created / updated / deleted?
   - **LANG=ja:** "いつ生成・更新・削除されますか？"
2. **Access patterns:** which queries hit it most often?
   - **LANG=ja:** "最もよく走るクエリは何ですか？"
3. **Retention:** is the data kept forever, archived, or deleted on a schedule?
   - **LANG=ja:** "データは永続保持・アーカイブ・スケジュール削除のどれですか？"
4. **PII / GDPR scope:** does this entity contain personal data? If yes, how does the user delete it (export, hard delete, soft delete + scrub)? What's our retention obligation?
   - **LANG=ja:** "このエンティティに個人情報は含まれますか？含まれるなら、ユーザーはどう削除しますか（エクスポート・物理削除・論理削除＋スクラブ）？保持義務は？"
5. **Access permissions:** who reads it, who writes it, who admins it? (owner only / shared / org-scoped / public / role-based)
   - **LANG=ja:** "誰が読み・誰が書き・誰が管理しますか？（所有者のみ・共有・組織内・公開・ロールベース）"
6. **Cardinality reality:** how many of these will exist at scale? (per user, per org, total) Is there a fan-out hot spot?
   - **LANG=ja:** "実規模で何件できますか？（ユーザーあたり・組織あたり・全体）ファンアウトのホットスポットは？"
7. **Migration scenario:** what will rename or restructure look like in 12 months? Are there fields you already suspect will need to split or move?
   - **LANG=ja:** "12 ヶ月後にリネーム・再編が起きるとしたら何が起きそうですか？すでに『これ分割しそう』と思うフィールドは？"

Save the final mermaid + answers + the 7 drill answers per entity to `dev/docs/spec/07-data-model.md`.

If USE_CODEX=yes, **ask the user first** (Cardinal rule). If "yes":
```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/consult-phase.sh" 7 "$ROOT"
```
Then summarize findings in plain language. If "no", skip.

Update `init-state.json` to `current_phase: "bootstrap"`.

---

## Phase 8 — Spec finalization + bootstrap + issue/task generation

### 8.1 Final spec review

Read all of `dev/docs/spec/0[1-7]-*.md` and `init-state.json` (`visualMocks[]`) and present a summary to the user for approval.

If USE_CODEX=yes, **ask the user first** (Cardinal rule). If "yes":
```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/consult-phase.sh" 8 "$ROOT"
```
Then summarize findings in plain language. If "no", skip.

If there are corrections, go back to phases 2–7 then return.

### 8.2 Bootstrap execution (non-interactive)

```bash
bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/bootstrap.sh "<root>" --config "<root>/.my-harness/.config"
```

bootstrap reads `PACKAGE_MANAGER` and `ARCHITECTURE` from `.my-harness/.config` and:
- Uses the chosen package manager (pnpm/bun/npm/yarn) for all install / exec / run lines in generated `flake.nix`, husky setup, CI workflows, and the printed next-steps banner.
- For `ARCHITECTURE=p2p-pure`, **skips** backend bootstrap entirely.
- For `ARCHITECTURE=p2p-hybrid`, writes a minimal **coordinator/bootstrap server** stub.
- For p2p modes, drops a starter at `dev/p2p/README.md` noting that the P2P transport library will be selected at `/harness-team-lead` time based on chosen platforms.

### 8.3 Issue / task generation

Split the complete feature list from Phase 4 into **child issues of at most 300 lines each**, declaring file ownership to prevent conflicts.

- **USE_GITHUB_ISSUES=yes**: Create parent + child issues with `gh issue create` (with 4-lane assignments).
- **USE_GITHUB_ISSUES=no**:
  ```
  <root>/dev/docs/task/parent/0001-<slug>.md
  <root>/dev/docs/task/child/0001-<feature>.md
  ```
  Each file uses front matter to express `parent: 0001` / `lane: 1–4` / `status: pending`.

### 8.4 Clear active session pointer (if USE_CODEX=yes)

```bash
~/my-harness-generator/scripts/codex-ask.sh --clear-active
```

### 8.5 Generate dev/README.md and dev/CLAUDE.md for the first time

Read `dev/docs/spec/*.md` and `.my-harness/.config`, then Claude **manually creates** the following 2 files (reflecting spec content). Use `$PACKAGE_MANAGER` for the install / exec lines.

#### `<root>/dev/README.md` (template)

```markdown
# <PROJECT_NAME>

<1–2 line summary from spec/02-discovery.md>

## Features

<feature list from spec/04-features.md as bullet checkboxes [ ] / [x]>

## Tech stack

- Architecture: <ARCHITECTURE>
- Frontend: <WEB_KIND if USE_WEB>, <IOS_KIND if USE_IOS>, ...
- Backend: <BACKEND_KIND if USE_BACKEND>
- DB: <DB_KIND if USE_DB>
- Auth: <AUTH_KIND>
- E2E: <E2E_SCOPE>
- Package manager: <PACKAGE_MANAGER>

## Setup

\`\`\`bash
cd dev
direnv allow
nix develop --command <PACKAGE_MANAGER> install
nix develop --command <PACKAGE_MANAGER> exec husky
\`\`\`

## Development flow

The harness orchestrates:
- `/harness-team-lead` — drive all issues in parallel across 4 lanes
- Re-run `/my-harness-init` — resume from where you left off
- Re-run `/my-harness-adopt` from an already-adopted project to refresh dev/.my-harness/ after a plugin upgrade (idempotent refresh path)

## Environment variables

<TBD — engineers append as implementation progresses>

## License

<TBD>
```

#### `<root>/dev/CLAUDE.md` (template)

```markdown
# <PROJECT_NAME> — Instructions for Claude Code

This project runs on a harness generated by my-harness-generator.

## Project purpose

<From spec/02-discovery.md>

## Architecture

- High-level shape: <ARCHITECTURE>
- 4-layer Clean Architecture (domain / application / infrastructure / interfaces)
- DB: <DB_KIND> + Drizzle ORM (when USE_DB=yes)
- Auth: <AUTH_KIND>
- Package manager: <PACKAGE_MANAGER>

## Data model

<Copy mermaid ER diagram from spec/07-data-model.md (only when DB used)>

## Key screens / API

<Key screen list from spec/05-visual.md (visualMocks[]) and expected API endpoints>

## Conventions

The harness conventions live in `rules/*.md` (Single Source of Truth):
- TDD: `rules/tdd.md`
- Hono Clean Architecture: `rules/hono-clean-arch.md`
- Drizzle migrate-only: `rules/drizzle.md`
- Nix pure: `rules/nix-pure.md`
- Design (Lucide Icons only, no AI-style design): `rules/design.md`
- JSDoc/TSDoc: `rules/jsdoc.md`
- No-hardcoded-secrets: `rules/no-hardcoded-secrets.md`

These files are mirrored to `<root>/dev/.my-harness/rules/` by bootstrap, embedded in `dev/CLAUDE.md` and `dev/AGENTS.md` (Claude Code / Codex CLI / Cursor / Aider all read them automatically), and auto-attached to Codex via `codex-ask.sh --role engineer / harness-reviewer / harness-analyst`.

## Agent responsibilities (4-lane parallel implementation)

- team-lead: issue assignment (avoiding file conflicts), progress aggregation, user approval relay
- analyst: in-lane orchestration, git add / commit / push / gh pr create
- engineer: implementation only (no git ops; updates README/CLAUDE.md alongside code)
- e2e-reviewer: runs Playwright/Maestro
- reviewer: convention + docs consistency review

## Key files

<Empty — engineers append to this whenever a feature is implemented>

## Current feature status

<Initialize the project feature list from spec/04-features.md with `pending`; flip to `done` as issues complete>
```

After Claude writes these 2 files to `dev/`, stage and commit in dev. Use `$LANG`:

```bash
cd "<root>/dev"
git add README.md CLAUDE.md
# LANG=en:
git -c user.name="harness-bot" -c user.email="harness@local" \
  commit --no-verify -m "docs: generate initial README.md and CLAUDE.md from spec"
# LANG=ja:
git -c user.name="harness-bot" -c user.email="harness@local" \
  commit --no-verify -m "docs: README.md と CLAUDE.md の初版を spec から生成"
```

### 8.6 Update init-state.json + stop + guide user to dev

```bash
ROOT=<root>
ISSUE_COUNT=<number of child issues generated>
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$ROOT/.my-harness/init-state.json" <<EOF
{
  "schema_version": "3",
  "project_name": "<PROJECT_NAME>",
  "lang": "${LANG:-en}",
  "root": "$ROOT",
  "current_phase": "completed",
  "phases_completed": ["language", "setup", "discovery", "structure", "features", "visual", "tools", "data-model", "bootstrap", "tasks"],
  "next_action": "implementation",
  "next_action_command": "/harness-team-lead",
  "working_directory": "$ROOT/dev",
  "issue_count": $ISSUE_COUNT,
  "lanes_assigned": true,
  "timestamp": "$TIMESTAMP"
}
EOF
```

Then **present the following message and stop automatically** (do not proceed). Use `$PACKAGE_MANAGER` in the placeholders. Render only the block matching `$LANG`.

**LANG=en:**

```
Bootstrap is done. The project lives at <root>.

I cannot switch this Claude Code session to <root>/dev/ automatically —
Claude Code does not expose a way to change CWD and reload CLAUDE.md /
settings.json mid-session. To continue:

  1. Type /exit (or Ctrl+D) to end this session.
  2. In your terminal, run:    cd <root>/dev && claude
  3. In the new session, run:  /harness-team-lead

That's it. Your project-local CLAUDE.md and settings
(claudeMdExcludes when applicable, plus project conventions) will load
on the new session's startup.

---
Spec:    <root>/dev/docs/spec/
Mocks:   <root>/dev/docs/design/
Tasks:   <root>/dev/docs/task/  or GitHub Issues
State:   <root>/.my-harness/init-state.json (current_phase=completed)

Additional steps before /harness-team-lead (run inside the new session):

  direnv allow
  nix develop --command <PACKAGE_MANAGER> install
  nix develop --command <PACKAGE_MANAGER> exec husky
  nix develop --command <PACKAGE_MANAGER> exec vitest run

Push to GitHub when ready:
  git remote add origin git@github.com:<owner>/<repo>.git
  git push --all origin
  bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
  bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

**LANG=ja:**

```
bootstrap が完了しました。プロジェクトは <root> にあります。

このセッションの作業ディレクトリを <root>/dev/ に切り替えることはできません。
Claude Code にはセッション途中で CWD を変更し、CLAUDE.md / settings.json を
再ロードする手段が公式に存在しないためです。続けるには:

  1. /exit（または Ctrl+D）でこのセッションを終了する。
  2. ターミナルで実行:    cd <root>/dev && claude
  3. 新しいセッションで:  /harness-team-lead

以上です。新セッション起動時にプロジェクトローカルの CLAUDE.md と
settings.json（claudeMdExcludes の設定、プロジェクト規約など）が自動でロードされます。

---
仕様書:  <root>/dev/docs/spec/
モック:  <root>/dev/docs/design/
タスク:  <root>/dev/docs/task/  または GitHub Issues
状態:   <root>/.my-harness/init-state.json (current_phase=completed)

/harness-team-lead の前に行う追加手順（新しいセッション内で実行）:

  direnv allow
  nix develop --command <PACKAGE_MANAGER> install
  nix develop --command <PACKAGE_MANAGER> exec husky
  nix develop --command <PACKAGE_MANAGER> exec vitest run

準備ができたら GitHub へ push:
  git remote add origin git@github.com:<owner>/<repo>.git
  git push --all origin
  bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
  bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>
```

**Claude (you) stops here.**

---

## Codex role selection (reference)

| Situation | role |
|-----------|------|
| Detect ambiguity / contradictions in requirements | analyst |
| Validate design, analyze tradeoffs | architect |
| Design proposals / image generation | designer |
| Logic review of spec documents | code-reviewer |
| Security perspective | security-reviewer |

**Do not use `critic` or `planner`** — they are product-strategy oriented.

## Failure fallbacks

- `codex` not installed → auto-set USE_CODEX=no, continue with Claude alone (Phase 5 falls back to text mocks)
- `codex login` not run → guide user; after 3 failures fall back to no
- `bootstrap.sh` fails → display stderr, let user decide
- File conflict → ask user to continue / abort / specify a different directory

## Artifact layout summary

```
<root>/
├── .my-harness/                       Internal work files (gitignored)
│   ├── .config                          Selections (incl. PACKAGE_MANAGER, ARCHITECTURE)
│   ├── init-state.json                  Phase + discoverySheet + visualMocks
│   ├── codex-sessions/<KEY>.id          (gitignored)
│   ├── codex-phase*.md                  (gitignored)
│   └── codex.jsonl                      (gitignored)
├── dev/                                 Standard structure created by bootstrap
│   ├── docs/
│   │   ├── spec/02-discovery.md ...     Masked requirements
│   │   ├── spec/05-visual.md            Mock catalog with decisionsRevealed
│   │   ├── spec/06-tools.md             Tool choices linked back to mocks
│   │   ├── spec/07-data-model.md        Per-entity drills
│   │   ├── design/logo-*.png ...        Generated images
│   │   ├── design/mock-<platform>-<screen>-*.png ...  Per-platform mocks
│   │   ├── talk/02-discovery.md ...     Masked Q&A
│   │   └── task/                        When USE_GITHUB_ISSUES=no
│   │       ├── parent/0001-*.md
│   │       └── child/0001-*.md
│   └── p2p/README.md                    Only when ARCHITECTURE in p2p-pure|p2p-hybrid
├── stage/  main/  lanes/                Standard worktrees
└── .bare/                               Bare git repo
```

## How to conduct the conversation (Claude's behavior, summary)

- **Phase 2 is a real conversation, not a checklist.** Open questions, drill aggressively on the six new probes (failure / resistance / scale / trust / differentiation / day-2), summarize, repeat. 15–40 turns is normal.
- **Phase 3 is just architecture + platforms.** Defer all tool questions until after the mocks.
- **Phase 4 drills 8 probes per feature.** Re-read the list at the end and fill gaps before exiting.
- **Phase 5's mocks become the source of truth.** Run the 3-question post-mock drill (missing / confusing / hidden constraint) after every mock and persist `decisionsRevealed`.
- **Phase 6 only fires AskUserQuestion for tools the discoverySheet + visualMocks have not already settled.** Every prompt must reference at least one mock entry.
- **Phase 7 drills 7 probes per entity.** Lifecycle, access, retention, GDPR, permissions, cardinality, migration.
- **One question per turn.** Always.
- **Mask before persisting.** Always.
- **Never improvise abstract questions** (brand world-view, 5-year vision, tone). Differentiation probe targets system-relevant constraints, not strategy.
- **Drill check after every reply.** "Have I gone at least one level deeper than the surface answer?"
- **If the user says 'stop'**, save state and halt.
