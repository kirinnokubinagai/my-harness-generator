---
name: my-harness-init
description: Runs the full new-project pipeline end-to-end. Phase 0 picks language, Phase 1 collects only the truly orthogonal setup flags, Phase 2 holds an open multi-turn discovery conversation that drills aggressively into the user's idea (failure modes, resistance, scale breakpoints, trust, differentiation, day-2 ops) and produces a structured discoverySheet, Phase 3 settles only the structural shape (architecture + platforms), Phase 4 elaborates the complete feature list with deep per-feature drills (onboarding / power-user / empty / failure / latency), Phase 5 generates per-form-factor (pc/mobile, auto-derived from platform flags) page+parts mocks via Codex with edit-mode chaining and project-wide style_guide inheritance, then Claude reads each PNG and writes the matching Tailwind HTML — all artifacts land under dev/docs/design/ (page-<ff>-<screen>.png, .html, and parts/<ff>/<screen>/<name>.png) which become the source of truth, Phase 6 picks concrete tools (framework / backend / DB / package manager / email / e2e / Claude Code Action) — each prompt referencing the approved mocks, Phase 7 drills the data model deeply (lifecycle / GDPR / permissions / cardinality / migration), Phase 8 finalizes spec and runs bootstrap. Triggered by /my-harness-init.
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
3. **Visual mocks become the source of truth** (Phase 5) — 3–5 page+parts mocks per chosen platform are generated and iterated on (one image per screen contains the full page on top and a transparent-cropped grid of every UI component on the bottom). Visible elements (lists, forms, charts, real-time indicators, offline banners) drive every downstream decision.
4. **Tool selection is informed by mocks** (Phase 6). Frameworks, DB, package manager, email, e2e, Claude Code Action are chosen with the mocks open so we can say "this dashboard needs real-time → choose framework with realtime story" rather than asking blind.
5. **Data model is reverse-engineered from mocks + discovery** (Phase 7) and drilled deeply — GDPR scope, access permissions, cardinality reality, migration scenarios.

**Cardinal rules — applied every turn:**

User-facing message style (one topic per message, plain language no invented compounds, Codex second-opinion opt-in, no internal terminology leaks, idea-suggestion guidance) — **canonical: `rules/communication.md`**. Read it once at skill start; do not restate its rules inline anywhere.

**Codex handoff** (when `USE_CODEX=yes`): Claude is the orchestrator, NOT the code author. Do not paste diffs / code snippets / function bodies / starter code as proposals. Describe the symptom + desired behavior + verification, delegate the implementation to Codex via `codex-ask.sh`. Exceptions (typo fixes, docs, mechanical config edits, direct user override, harness internal code) are listed in **canonical: `rules/codex-handoff.md`** — read it once at skill start; do not restate.

**Spec style** (every interview phase that writes a spec file): Specs describe **WHAT and the constraints**, not HOW. No TypeScript / SQL / Tailwind class strings / framework calls / config-file contents inside `dev/docs/spec/*.md`, `init-state.json`'s `discoverySheet`, or any decision-recording artifact Claude produces. The spec must survive a framework swap without rewriting. Pseudo-code, Mermaid diagrams, API paths, HTTP status codes, hex colors, and numeric thresholds ARE okay (they define the contract). Full ruleset + translation table: **canonical: `rules/spec-style.md`**.

Interview-specific rules (applied to every Phase 1-7 question, not just Phase 2):

- **Never ask a question whose answer is already implied** by what the user said or by an approved mock. Re-read the internal notes (without exposing their names to the user) before composing; skip what's already on file.
- **Drill down at least one level.** Vague answer ("a chat app") → next question narrows ("group or 1:1? ephemeral or stored? text only or media?"). For failure / resistance / scale / trust probes, push for concrete scenarios, not platitudes.
- **One question per turn.** Batch questions banned.
- **Phase order is strict.** Discovery → structure → mocks → tools → data. No skipping ahead.
- **Bilingual parity.** Every user-facing prompt has `LANG=en` and `LANG=ja` variants; after Phase 0, render only the chosen language.
- **No marketing / brand / 5-year-vision questions.** Stay system-relevant. The differentiation probe is allowed only because it surfaces system constraints; "what's your North Star metric?" is not.

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
| 5 | Visual | 3–5 page+parts mocks per form factor (pc / mobile, auto-derived from platform flags); auto-crop transparent parts → assets; mocks + HTML by Claude become source of truth |
| 6 | Tools | Framework / backend / DB / package manager / email / e2e / Claude Code Action — informed by mocks |
| 7 | Data model | Per-entity drill (lifecycle / GDPR / permissions / cardinality / migration) |
| 8 | Bootstrap | Spec finalize + bootstrap.sh + issues / tasks |

### Managing init-state.json (for pause/resume)

At the completion of each phase, write the following. `current_phase` is the **next** phase to advance to; `phases_completed` is the list of **already finished** phases:

Use the `Write` tool to create `$ROOT/.my-harness/init-state.json` directly (no shell heredoc needed). Replace every `<...>` placeholder with the actual value gathered so far. `timestamp` is the current UTC time in ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`).

```json
{
  "schema_version": "3",
  "project_name": "<PROJECT_NAME>",
  "lang": "en",
  "root": "<ROOT>",
  "current_phase": "<next phase>",
  "phases_completed": ["language", "setup", "discovery", "structure"],
  "next_action": "interview",
  "next_action_command": "Continue /my-harness-init (Phase: <next>)",
  "working_directory": "<ROOT>",
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
  "timestamp": "<UTC ISO-8601>"
}
```

### Pause/resume

When the user says "pause", "stop", or similar:
- Update `init-state.json`, `discoverySheet`, and `visualMocks` to the latest state, tell the user where it was saved and the resume command, then stop.

When the user comes back:
- Read `<root>/.my-harness/init-state.json` and check `current_phase`. Resume from the first question of that phase. Existing `docs/spec/`, `docs/design/`, and `docs/talk/` are carried forward.

### At startup: auto-detect init-state.json

```bash
STATE_FILE=$(bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/find-existing-state.sh") && {
  # resume — STATE_FILE points to the init-state.json that should be loaded
  :
} || {
  # not found — proceed with fresh start
  :
}
```

Implementation: walks up to 5 parent directories from `$PWD`. Source: `scripts/find-existing-state.sh`.

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
      { "label": "Claude only", "description": "Default. Everything runs end-to-end with Claude alone — no extra setup. Visual phase falls back to text-only mock descriptions (no generated images)." },
      { "label": "Claude + Codex", "description": "Adds OpenAI's Codex CLI for second-opinion design/code review and `gpt-image-2` page+parts mock generation. Requires `npm install -g @openai/codex` and `codex login` (ChatGPT subscription)." }
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
      { "label": "Claude のみ", "description": "デフォルト。追加セットアップ不要で Claude 単体で全機能が動作。ビジュアルフェーズは画像生成なしのテキスト記述に置換 (モック画像は生成されない)。" },
      { "label": "Claude + Codex", "description": "OpenAI の Codex CLI を併用してセカンドオピニオン (設計・コードレビュー) と `gpt-image-2` での「ページ + パーツ一覧」モック生成を有効化。`npm install -g @openai/codex` と `codex login` (ChatGPT サブスクリプション) が必要。" }
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

### Setup Q5: Trust the project root + start the codex daemon — **only when USE_CODEX=yes**

When `USE_CODEX=yes`, two things must be set up before any later phase calls `codex-ask.sh` — in this exact order:

**Q5.a — Mark the project as trusted in `~/.codex/config.toml`** (required, otherwise the daemon hangs):

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/ensure-codex-project-trust.sh" "$ROOT"
```

Why this matters: Codex has TWO independent approval layers. **L2 (action approval — shell exec, file edit)** is set to `"never"` by our `codex-app-server-call.py`, but **L1 (project trust — "may Codex run in this directory?")** is enforced separately from `~/.codex/config.toml` and our `approval_policy="never"` does NOT bypass it. A daemon running in a non-trusted directory raises an L1 approval request that has no UI to answer it, so `thread/start` hangs forever and every `image_gen` call (and every other Codex call) silently times out. The script appends a `[projects."<ROOT>"] trust_level = "trusted"` section to `~/.codex/config.toml` (idempotent — no-op when already present).

**Q5.b — Pin Codex's reasoning effort (ask the user: `xhigh` or `high`)**:

Ask the user with `AskUserQuestion`. Match `LANG`:

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "How deeply should Codex reason on each turn?",
    "header": "Codex effort",
    "multiSelect": false,
    "options": [
      { "label": "xhigh", "description": "Highest reasoning depth. Best output quality on hard tasks (design / complex implementation). Slower and consumes the Codex usage allowance faster." },
      { "label": "high", "description": "One step below xhigh. Faster and lighter on usage; slightly less thorough on multi-step reasoning. Adequate for most everyday tasks." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "Codex の推論の深さはどうしますか？",
    "header": "Codex 推論レベル",
    "multiSelect": false,
    "options": [
      { "label": "xhigh", "description": "最高の推論深度。デザイン / 複雑な実装などハードなタスクで品質が最も高い。時間と Codex 利用枠を多く消費する。" },
      { "label": "high", "description": "xhigh の 1 段下。速くて軽い。多段の推論はやや劣るが、日常的なタスクには十分。" }
    ]
  }]
}
```

Map: `xhigh` → `xhigh`, `high` → `high`. No default applied — the user must choose.

Then write the choice to `~/.codex/config.toml`:

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/ensure-codex-effort.sh" "<chosen-level>"
```

This adds `model_reasoning_effort = "<chosen-level>"` at the top of `~/.codex/config.toml` if the key is not already present. Idempotent: if the user already set a value in a previous session, it's left alone (no overwrite). The script validates the level against the SDK's allowed values (`none|minimal|low|medium|high|xhigh`); anything else is rejected with a clear error.

**Q5.c — Start the shared codex app-server daemon**:

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/ensure-codex-daemon.sh" "$ROOT"
```

Without a shared daemon, each Codex call spawns a fresh `codex app-server` Node process (cold-start cost per call). One persistent daemon eliminates that cost and is reused across every subsequent Codex call in this and future sessions. Implementation: reads `USE_CODEX` from `.config`; if `yes`, branches on daemon `status` (0 = healthy, 1 = start, 2 = restart). Best-effort: failure only loses the cold-start savings, never blocks the init flow. Source: `scripts/ensure-codex-daemon.sh`.

Order matters: trust + effort must be in place **before** the daemon comes up, because the daemon reads `config.toml` at start time. If the daemon is already running and trust / effort has just been added, `ensure-codex-daemon.sh` will see a healthy daemon and skip; force-restart with `bash $D restart` (where `$D` is the daemon script) to pick up the new entries.

When `USE_CODEX=no`, skip Q5.a, Q5.b, and Q5.c entirely — no Codex calls will be made, so trust / effort / daemon all serve no purpose.

### Setup Q6: Notification service

Use `AskUserQuestion` with **named options** (do NOT phrase as a free-text "which one?"):

**LANG=en — `AskUserQuestion` payload:**
```json
{
  "questions": [{
    "question": "Enable notifications? Choose a service:",
    "header": "Notifications",
    "multiSelect": false,
    "options": [
      { "label": "Discord",  "description": "Free, easy. Recommended for personal projects." },
      { "label": "Slack",    "description": "Better for teams already on Slack." },
      { "label": "Teams",    "description": "Microsoft Teams. Slightly more setup." },
      { "label": "Disable",  "description": "Skip notifications. You can enable later with `bash scripts/ensure-notification-webhook.sh ...`." }
    ]
  }]
}
```

**LANG=ja — `AskUserQuestion` payload:**
```json
{
  "questions": [{
    "question": "通知を有効にしますか？サービスを選択してください:",
    "header": "通知",
    "multiSelect": false,
    "options": [
      { "label": "Discord",  "description": "無料・簡単。個人プロジェクトに最適。" },
      { "label": "Slack",    "description": "既に Slack を使っているチームに最適。" },
      { "label": "Teams",    "description": "Microsoft Teams。設定はやや多め。" },
      { "label": "無効化",   "description": "通知をスキップ。あとから `bash scripts/ensure-notification-webhook.sh ...` で有効化可能。" }
    ]
  }]
}
```

Map the user's choice to `$SERVICE` (lowercase): `Discord` → `discord`, `Slack` → `slack`, `Teams` → `teams`, `Disable` / `無効化` → `none`.

**Already-configured detection (option α) for Q6:**

Before asking, check whether the relevant config already exists:

```bash
if [ -f "$ROOT/.my-harness/.notification.env" ] && grep -q '^NOTIFICATION_SERVICE=' "$ROOT/.my-harness/.notification.env"; then
  CURRENT_SERVICE="$(grep '^NOTIFICATION_SERVICE=' "$ROOT/.my-harness/.notification.env" | cut -d= -f2)"
  CURRENT_URL="$(grep '^NOTIFICATION_WEBHOOK_URL=' "$ROOT/.my-harness/.notification.env" | cut -d= -f2)"
  # Mask URL: show only the first 20 chars + "..."
  MASKED_URL="$(printf '%.20s...' "$CURRENT_URL")"
fi
```

If a prior config exists, show the masked current value and ask:

- **LANG=en:** "Current config: `$CURRENT_SERVICE` → `$MASKED_URL`. Change it?"
- **LANG=ja:** "現在の設定: `$CURRENT_SERVICE` → `$MASKED_URL`。変更しますか?"

Options (single-select): `Keep` / `保持する` → skip Q6/Q7 entirely, retain current values; `Change` / `変更する` → ask the original Q6 question above.

**Behavior after Q6:**

If `$SERVICE == "none"`:

```bash
bash scripts/ensure-notification-webhook.sh "$ROOT" none
```

This wipes any prior config. **Skip Q7-Q9 entirely** and jump to the Phase 1 wrap-up.

Otherwise, continue to Q7.

### Setup Q7: Webhook URL acquisition (only when `$SERVICE != none`)

Use `AskUserQuestion`. Substitute `<Service>` in each option with the selected `$SERVICE` (rendered as `Discord` / `Slack` / `Teams`).

**LANG=en — payload:**
```json
{
  "questions": [{
    "question": "How would you like to provide the webhook URL?",
    "header": "Webhook URL",
    "multiSelect": false,
    "options": [
      { "label": "I have it — I will paste",
        "description": "I already created the webhook in <Service>. I'll paste the URL on the next prompt." },
      { "label": "Walk me through creating it",
        "description": "Open templates/notifications/SETUP.md with step-by-step instructions for <Service>, including signing up for a free account if needed." },
      { "label": "Auto-acquire via Chrome",
        "description": "Use Claude in Chrome to navigate the <Service> UI and pull the URL automatically. Falls back to manual paste if anything fails. Currently only works for Discord — Slack/Teams must use manual paste." }
    ]
  }]
}
```

**LANG=ja — payload:**
```json
{
  "questions": [{
    "question": "Webhook URL の入力方法を選んでください:",
    "header": "Webhook URL",
    "multiSelect": false,
    "options": [
      { "label": "持っているので貼り付ける",
        "description": "<Service> で Webhook を既に作成済み。次のプロンプトで URL を貼り付ける。" },
      { "label": "作り方を案内してほしい",
        "description": "templates/notifications/SETUP.md を開いて <Service> の手順を順に説明（無料アカウント作成手順も含む）。" },
      { "label": "Chrome で自動取得する",
        "description": "Claude in Chrome で <Service> の画面を操作して URL を自動取得。失敗時は手動貼り付けにフォールバック。現状 Discord のみ対応 — Slack/Teams は手動貼り付けが必要。" }
    ]
  }]
}
```

**Behavior per choice:**

#### "I have it — I will paste" / 「持っているので貼り付ける」

Ask via `AskUserQuestion` (single freeform option):

- **LANG=en** question: "Paste the webhook URL:"
- **LANG=ja** question: "Webhook URL を貼り付けてください:"

Then validate:

```bash
bash scripts/ensure-notification-webhook.sh "$ROOT" "$SERVICE" "$URL"
```

Exit code 0 → success, continue to Q8. Exit code 2 (bad shape) → show the script's stderr and reprompt (loop). Exit code 3 should not happen here (URL is provided); treat as a script bug and surface the error.

#### "Walk me through creating it" / 「作り方を案内してほしい」

Print the absolute path to `templates/notifications/SETUP.md`:

- **LANG=en:** "Open `<absolute-path-to>/templates/notifications/SETUP.md` and follow the `<Service>` section. Return here when you have the URL."
- **LANG=ja:** "`<absolute-path-to>/templates/notifications/SETUP.md` を開いて `<Service>` のセクションに従ってください。URL を取得したら戻ってきてください。"

Wait for user acknowledgement (`continue` / `done`), then `AskUserQuestion` for the URL (same as the paste path above) and validate via `ensure-notification-webhook.sh`.

#### "Auto-acquire via Chrome" / 「Chrome で自動取得する」

Only valid when `$SERVICE == "discord"`. For Slack/Teams, downgrade to the paste path with a one-line note:

- **LANG=en:** "Auto-acquire is only supported for Discord. Falling back to manual paste."
- **LANG=ja:** "自動取得は現状 Discord のみ対応。手動貼り付けにフォールバックします。"

For Discord, attempt the following (best-effort — selectors are volatile):

1. Use `mcp__claude-in-chrome__tabs_context_mcp` to look for an open Discord tab. If none, call `tabs_create_mcp` and `navigate` to `https://discord.com/channels/@me`.
2. If the resulting URL contains `/login`, pause and ask the user to log in:
   - **LANG=en:** "Please log in to Discord in the opened tab, then say `continue`."
   - **LANG=ja:** "開いたタブで Discord にログインしてから `continue` と入力してください。"
3. Once logged in, ask the user via `AskUserQuestion` (freeform) which server they want, or ask them to manually navigate to the destination channel and say `continue`. (We do NOT navigate the server picker — too brittle.)
4. Navigate to channel settings → Integrations → Webhooks → New Webhook. Use `mcp__claude-in-chrome__find` to locate "Integrations" and click; repeat for "Webhooks" and "New Webhook" / "Create Webhook".
5. Use `mcp__claude-in-chrome__javascript_tool` to read the Webhook URL from the DOM, or click "Copy Webhook URL" and read the clipboard via `navigator.clipboard.readText()`. The clipboard read might require a permission prompt; if denied, fall back to manual paste.
6. Validate the URL via `ensure-notification-webhook.sh`.
7. **On ANY failure** (timeout, element not found, clipboard denied, browser tools fail) → fall back to manual paste with a clear explanation of what went wrong and what to do next. The manual paste path IS the happy path; auto-acquire is just nice-to-have.

Reality check: Discord's SPA is volatile and these selectors will break over time. Treat the entire auto-acquire flow as best-effort.

### Setup Q8: GitHub PAT

**Already-configured detection (option α) for Q8:**

```bash
if [ -f "$ROOT/.my-harness/.notification.env" ] && grep -q '^GH_TOKEN=' "$ROOT/.my-harness/.notification.env"; then
  CURRENT_PAT="$(grep '^GH_TOKEN=' "$ROOT/.my-harness/.notification.env" | cut -d= -f2)"
  MASKED_PAT="$(printf '%.20s...' "$CURRENT_PAT")"
fi
```

If a prior PAT exists, ask first:

- **LANG=en:** "Current PAT: `$MASKED_PAT`. Change it?"
- **LANG=ja:** "現在の PAT: `$MASKED_PAT`。変更しますか?"

Options: `Keep` / `保持する` → skip Q8 entirely. `Change` / `変更する` → ask the original question below.

**Q8 — `AskUserQuestion` payload:**

**LANG=en:**
```json
{
  "questions": [{
    "question": "How would you like to provide a GitHub read-only token?",
    "header": "GitHub PAT",
    "multiSelect": false,
    "options": [
      { "label": "I have it — I will paste",
        "description": "Fine-grained PAT with READ scopes for contents, issues, pull-requests, actions." },
      { "label": "Walk me through creating it",
        "description": "Open templates/notifications/SETUP.md → GitHub PAT section." }
    ]
  }]
}
```

**LANG=ja:**
```json
{
  "questions": [{
    "question": "GitHub の読み取り専用トークンの入力方法を選んでください:",
    "header": "GitHub PAT",
    "multiSelect": false,
    "options": [
      { "label": "持っているので貼り付ける",
        "description": "Fine-grained PAT、READ 権限のみ（contents / issues / pull-requests / actions）。" },
      { "label": "作り方を案内してほしい",
        "description": "templates/notifications/SETUP.md の GitHub PAT セクションを開く。" }
    ]
  }]
}
```

For "I have it — I will paste": ask for the PAT via `AskUserQuestion` (freeform), validate via:

```bash
bash scripts/ensure-github-pat.sh "$ROOT" "$PAT"
```

Exit 0 → success; exit 2 → bad shape, reprompt; exit 3 → script bug (PAT should have been provided).

For "Walk me through creating it": print the path to `templates/notifications/SETUP.md` (Section 4 — GitHub fine-grained PAT), wait for `continue`, then ask + validate as above.

### Setup Q9: Oracle Cloud daily-progress VM

**Already-configured detection (option α) for Q9:**

```bash
if [ -f "$ROOT/.my-harness/.oci-vm.env" ]; then
  CURRENT_VM_NAME="$(grep '^OCI_VM_NAME=' "$ROOT/.my-harness/.oci-vm.env" | cut -d= -f2)"
  CURRENT_VM_IP="$(grep '^OCI_VM_PUBLIC_IP=' "$ROOT/.my-harness/.oci-vm.env" | cut -d= -f2)"
fi
```

If `.oci-vm.env` exists, ask:

- **LANG=en:** "Current VM: `$CURRENT_VM_NAME` @ `$CURRENT_VM_IP`. Change it?"
- **LANG=ja:** "現在の VM: `$CURRENT_VM_NAME` @ `$CURRENT_VM_IP`。変更しますか?"

Options: `Keep` / `保持する` → skip Q9 entirely. `Change` / `変更する` → ask the original Q9 question below.

**Q9 — `AskUserQuestion` payload:**

**LANG=en:**
```json
{
  "questions": [{
    "question": "Provision an Oracle Cloud VM for the daily-progress bot?",
    "header": "OCI VM",
    "multiSelect": false,
    "options": [
      { "label": "Yes — provision now",
        "description": "Create a new Always-Free A1.Flex VM (4 OCPU, 24 GB RAM). Requires `oci` CLI configured (~/.oci/config). The script will guide you if missing." },
      { "label": "Already have one — connect to it",
        "description": "Tell me the public IP + SSH key path, I'll deploy the bot there." },
      { "label": "Skip — set up later",
        "description": "I'll run scripts/ensure-oci-vm.sh + setup-oci-vm.sh manually later. Don't ask again this session." }
    ]
  }]
}
```

**LANG=ja:**
```json
{
  "questions": [{
    "question": "デイリープログレスボット用の Oracle Cloud VM をプロビジョニングしますか？",
    "header": "OCI VM",
    "multiSelect": false,
    "options": [
      { "label": "はい — 今すぐ作成",
        "description": "Always-Free A1.Flex VM (4 OCPU / 24 GB RAM) を新規作成。`oci` CLI と `~/.oci/config` が必要。未設定なら案内する。" },
      { "label": "既存の VM に接続",
        "description": "public IP と SSH 鍵パスを教えてくれれば、そこにボットをデプロイする。" },
      { "label": "スキップ — あとで自分でやる",
        "description": "scripts/ensure-oci-vm.sh と setup-oci-vm.sh を後で手動実行する。今セッションでは再度尋ねない。" }
    ]
  }]
}
```

**Behavior per choice:**

#### "Skip — set up later" / 「スキップ — あとで自分でやる」

Continue to the Phase 1 wrap-up. Do not ask again this session.

#### "Already have one — connect to it" / 「既存の VM に接続」

Ask via `AskUserQuestion` (freeform):

1. Public IP of the existing VM.
2. SSH key filename (default `kirin_oracle_cloud.key`, relative to `~/.ssh/`).

Write the answers to `.my-harness/.oci-vm.env` manually:

```bash
mkdir -p "$ROOT/.my-harness"
cat > "$ROOT/.my-harness/.oci-vm.env" <<EOF
# Manually configured — pointed at an existing VM.
OCI_VM_NAME=existing
OCI_VM_REGION=unknown
OCI_VM_INSTANCE_ID=
OCI_VM_PUBLIC_IP=$VM_IP
OCI_VM_SSH_KEY=$HOME/.ssh/$SSH_KEY_FILENAME
EOF
chmod 600 "$ROOT/.my-harness/.oci-vm.env"
```

Then deploy:

```bash
bash scripts/setup-oci-vm.sh "$ROOT"
```

#### "Yes — provision now" / 「はい — 今すぐ作成」

Ask 3 follow-up sub-questions in order:

##### Q9a — VM name

Freeform via `AskUserQuestion`, default `kirin` (matches the existing `whoami` convention).

- **LANG=en:** "VM display name (default: `kirin`):"
- **LANG=ja:** "VM の表示名 (デフォルト: `kirin`):"

##### Q9b — Region

`AskUserQuestion`, `multiSelect: false`:

**LANG=en:**
```json
{
  "questions": [{
    "question": "Which OCI region?",
    "header": "Region",
    "multiSelect": false,
    "options": [
      { "label": "Osaka (ap-osaka-1)",                     "description": "Default. Closest to Japan-based users." },
      { "label": "Tokyo (ap-tokyo-1)",                     "description": "Alternative Japan region." },
      { "label": "Ashburn (us-ashburn-1) — best for capacity availability",
                                                            "description": "US East. Historically the most A1 capacity available." },
      { "label": "Frankfurt (eu-frankfurt-1)",             "description": "EU region." },
      { "label": "I'll type my own",                        "description": "Enter any other region code (e.g. `ap-seoul-1`, `uk-london-1`)." }
    ]
  }]
}
```

**LANG=ja:**
```json
{
  "questions": [{
    "question": "OCI のリージョンを選んでください:",
    "header": "リージョン",
    "multiSelect": false,
    "options": [
      { "label": "大阪 (ap-osaka-1)",                       "description": "デフォルト。日本ユーザーに最も近い。" },
      { "label": "東京 (ap-tokyo-1)",                       "description": "もう一つの日本リージョン。" },
      { "label": "アッシュバーン (us-ashburn-1) — 容量豊富",
                                                            "description": "米国東部。A1 容量が最も多い傾向にある。" },
      { "label": "フランクフルト (eu-frankfurt-1)",         "description": "EU リージョン。" },
      { "label": "自分で入力する",                           "description": "他のリージョンコード（例: `ap-seoul-1`, `uk-london-1`）を入力。" }
    ]
  }]
}
```

If "I'll type my own" / 「自分で入力する」 is selected, ask via a follow-up freeform `AskUserQuestion` for the region code.

Map the chosen label to the region code (parenthesized part). Persist as `$REGION`.

##### Q9c — SSH key filename

Freeform via `AskUserQuestion`, default `kirin_oracle_cloud.key`.

- **LANG=en:** "SSH key filename (under `~/.ssh/`, will be generated if missing). Default: `kirin_oracle_cloud.key`:"
- **LANG=ja:** "SSH 鍵ファイル名 (`~/.ssh/` 配下、無ければ生成)。デフォルト: `kirin_oracle_cloud.key`:"

##### After Q9a/b/c — provision

Call:

```bash
bash scripts/ensure-oci-vm.sh "$ROOT" "$VM_NAME" "$REGION" "$SSH_KEY"
```

Handle exit codes:

- **Exit 0:** success — proceed to `bash scripts/setup-oci-vm.sh "$ROOT"`.
- **Exit 1** (missing `~/.oci/config` or `oci` CLI not on PATH): the script prints its own setup hint. ALSO point the user at `templates/notifications/SETUP.md` Section 5 (Oracle Cloud). Pause and ask:
  - **LANG=en:** "Set up `~/.oci/config` per the instructions, then choose:"
  - **LANG=ja:** "`~/.oci/config` を上記の手順でセットアップしてから、選んでください:"
  - Options: `Retry` / `再試行` → re-run `ensure-oci-vm.sh`; `Skip — set up later` / `スキップ — あとで` → continue to wrap-up.
- **Exit 2** (network / "Out of Host Capacity" after retries):
  - **LANG=en:** "OCI launch failed (likely Out of Host Capacity — the Always-Free A1 region is exhausted). Skipping VM provisioning for now. Re-run `bash scripts/ensure-oci-vm.sh "$ROOT" "$VM_NAME" "$REGION" "$SSH_KEY"` later, or try another region."
  - **LANG=ja:** "OCI VM の起動に失敗しました（Always-Free A1 の容量切れの可能性が高い）。今回は VM プロビジョニングをスキップします。後で `bash scripts/ensure-oci-vm.sh "$ROOT" "$VM_NAME" "$REGION" "$SSH_KEY"` を再実行するか、別リージョンを試してください。"

On success (Exit 0) call `bash scripts/setup-oci-vm.sh "$ROOT"` to install dependencies, deploy the bot, and register the crontab inside the VM.

### Setup Q9.5: Claude Code subscription OAuth token

Run this question only when Q9 resulted in actual VM provisioning ("Yes — provision now") or "Already have one — connect to it". Skip entirely if Q9 was "Skip — set up later".

> **Security note:** This token grants approximately 1 year of inference access on your Claude Pro/Max subscription. Treat it like a password. It is stored in `.my-harness/.notification.env` (gitignored, chmod 600) and never leaves this machine except when `setup-secrets.sh` pushes it to GitHub Secrets.

**Already-configured detection (option α) for Q9.5:**

```bash
if [ -f "$ROOT/.my-harness/.notification.env" ] && grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' "$ROOT/.my-harness/.notification.env"; then
  CURRENT_TOKEN="$(grep '^CLAUDE_CODE_OAUTH_TOKEN=' "$ROOT/.my-harness/.notification.env" | cut -d= -f2)"
  TOKEN_LEN="${#CURRENT_TOKEN}"
fi
```

If a non-empty `CLAUDE_CODE_OAUTH_TOKEN` is already saved, ask first:

- **LANG=en:** "Current OAuth token already saved (length: `$TOKEN_LEN`). Change it?"
- **LANG=ja:** "OAuth トークンは保存済みです（長さ: `$TOKEN_LEN`）。変更しますか?"

Options: `Keep` / `保持する` → skip Q9.5 entirely. `Change` / `変更する` → ask the original question below.

**Q9.5 — `AskUserQuestion` payload:**

**LANG=en:**
```json
{
  "questions": [{
    "question": "How would you like to provide your Claude subscription OAuth token?",
    "header": "Claude OAuth token",
    "multiSelect": false,
    "options": [
      { "label": "I have it — I will paste",
        "description": "I already ran `claude setup-token` on this Mac and have the token ready. I'll paste it on the next prompt." },
      { "label": "Walk me through generating it",
        "description": "Show me the steps to run `claude setup-token` and obtain the token." },
      { "label": "Skip for now",
        "description": "The daily-progress bot will fail to call Claude until a token is set. Run `bash scripts/ensure-claude-oauth-token.sh <root> <token>` manually later." }
    ]
  }]
}
```

**LANG=ja:**
```json
{
  "questions": [{
    "question": "Claude サブスクリプション OAuth トークンの入力方法を選んでください:",
    "header": "Claude OAuth トークン",
    "multiSelect": false,
    "options": [
      { "label": "持っているので貼り付ける",
        "description": "この Mac で既に `claude setup-token` を実行済みで、トークンが手元にある。次のプロンプトで貼り付ける。" },
      { "label": "生成方法を案内してほしい",
        "description": "`claude setup-token` の実行手順とトークンの取得方法を画面で案内する。" },
      { "label": "あとでやる",
        "description": "トークンが設定されるまでボットは Claude を呼び出せません。後で `bash scripts/ensure-claude-oauth-token.sh <root> <token>` を手動実行してください。" }
    ]
  }]
}
```

**Behavior per choice:**

#### "Skip for now" / 「あとでやる」

Continue to the Phase 1 wrap-up without saving a token.

#### "Walk me through generating it" / 「生成方法を案内してほしい」

Print the following step-by-step guidance to the screen verbatim, then wait for the user to acknowledge with `continue` / `done` / 完了 before proceeding to the paste step below.

**LANG=en — display this text to the user:**

```
To generate a 1-year Claude OAuth token, do the following on THIS Mac:

  1. Open a new terminal window/tab (Cmd+T in iTerm / Terminal.app), or
     run the next command from inside this Claude Code session by
     prefixing it with `!` so it runs in the host shell:

         ! claude setup-token

     Running it as a normal shell command in a separate terminal works
     equally well.

  2. Your browser will open to claude.ai for authorization. Sign in to
     the SAME Claude.ai account that holds your Pro / Max / Team /
     Enterprise subscription. Approve the access prompt.

  3. The terminal where you ran `claude setup-token` will print a
     single long line starting with `sk-ant-oat01-`. That entire line
     is the token. Select and copy it.

  4. Return here and type `continue`. I'll then ask you to paste the
     token, validate its shape, and save it to
     `.my-harness/.notification.env` (chmod 600, gitignored). The
     token is valid for ~1 year and does not need to be refreshed.

Security note: this token grants ~1 year of inference access on your
subscription. Do NOT commit it, do NOT paste it into public chat. If
it leaks, regenerate via `claude setup-token` again (the new token
invalidates the old one on first use).
```

**LANG=ja — display this text to the user:**

```
1 年有効な Claude OAuth トークンを生成する手順 (この Mac で実行):

  1. 新しいターミナル (iTerm / Terminal.app で Cmd+T) を開いて
     実行してください。あるいはこの Claude Code セッション内で
     次のコマンドの先頭に `!` を付けてホストシェルで実行しても OK:

         ! claude setup-token

     どちらでも結果は同じです。

  2. ブラウザが claude.ai に開いて認可を求めます。Pro / Max /
     Team / Enterprise サブスクリプションを契約している Claude.ai
     アカウントでサインインし、アクセスを承認してください。

  3. `claude setup-token` を実行したターミナルに `sk-ant-oat01-`
     で始まる長い 1 行が出力されます。その 1 行全体がトークン
     です。選択してコピーしてください。

  4. ここに戻り `continue` と入力してください。次にトークンの
     貼り付けを求めますので、検証後に
     `.my-harness/.notification.env` (chmod 600、.gitignore 済み)
     に保存します。トークンは約 1 年有効でリフレッシュは不要です。

セキュリティ注意: このトークンは約 1 年間サブスクリプションを使った
推論アクセスを許可します。git にコミットしない / 公開チャットに貼らない
ようにしてください。万一漏洩した場合は `claude setup-token` を再実行し
て新しいトークンを発行すれば、新トークンの初回使用時に古いトークンは
無効化されます。
```

After the user types `continue` (or any acknowledgement), drop into the paste step described below.

#### "I have it — I will paste" / 「持っているので貼り付ける」

Ask for the token via a follow-up freeform `AskUserQuestion`:

- **LANG=en** question: "Paste the OAuth token (`sk-ant-oat01-...`):"
- **LANG=ja** question: "OAuth トークン (`sk-ant-oat01-...`) を貼り付けてください:"

Then validate:

```bash
bash scripts/ensure-claude-oauth-token.sh "$ROOT" "$TOKEN"
```

Exit codes:

- **Exit 0:** token saved. Proceed to Phase 1 wrap-up.
- **Exit 2:** bad shape (whitespace, length < 30, or disallowed characters). Show the script's error output, then reprompt for the token only (do NOT loop back through Q9.5's three options).
- **Exit 3:** token was empty (should not reach here). Treat as "Skip for now".

### Setup Q11: AI provider for the OCI daily-progress bot

Run this question ONLY when Q9 resulted in actual VM provisioning ("Yes — provision now") or "Already have one — connect to it". Skip entirely if Q9 was "Skip — set up later".

**Already-configured detection (option α) for Q11:**

```bash
if [ -f "$ROOT/.my-harness/.notification.env" ] && grep -q '^AI_PROVIDER=' "$ROOT/.my-harness/.notification.env"; then
  CURRENT_AI=$(grep '^AI_PROVIDER=' "$ROOT/.my-harness/.notification.env" | cut -d= -f2)
fi
```

If `AI_PROVIDER` is already saved, ask first:

- **LANG=en:** "Current AI provider: `$CURRENT_AI`. Change it?"
- **LANG=ja:** "現在の AI provider: `$CURRENT_AI`。変更しますか?"

Options: `Keep` / `保持する` → skip Q11 entirely. `Change` / `変更する` → ask the original question below.

**Q11 — `AskUserQuestion` payload:**

**LANG=en:**
```json
{
  "questions": [{
    "question": "Which AI should the OCI VM call from daily-progress.sh and event-watch.sh?",
    "header": "VM AI provider",
    "multiSelect": false,
    "options": [
      { "label": "Claude Code (uses Q9.5 OAuth token)",
        "description": "Reuses the Claude OAuth token captured in Q9.5. The VM runs `claude -p` for summaries. No extra setup. Best for Claude Pro/Max subscribers." },
      { "label": "Codex (ChatGPT Plus/Pro subscription)",
        "description": "Mac runs `codex login` once; harness copies ~/.codex/auth.json to the VM. Refresh token lifetime ~3 months — re-run `codex login` and re-deploy when it expires. No OpenAI API key billing." },
      { "label": "Gemma 4 (local, no auth)",
        "description": "Installs Ollama daemon and downloads gemma4:e4b (~5 GB) on the VM. No subscription, no external API calls. Inference is 3-6 tok/s on the A1.Flex's 4 ARM cores; daily-progress 1 run takes 30-60 seconds. Fully free forever." }
    ]
  }]
}
```

**LANG=ja:**
```json
{
  "questions": [{
    "question": "OCI VM の daily-progress.sh と event-watch.sh が呼び出す AI を選択してください:",
    "header": "VM AI provider",
    "multiSelect": false,
    "options": [
      { "label": "Claude Code(Q9.5 の OAuth トークンを使う)",
        "description": "Q9.5 で保存した Claude OAuth トークンをそのまま使用。VM 上で `claude -p` を実行。追加設定不要。Claude Pro/Max 加入者向け。" },
      { "label": "Codex(ChatGPT Plus/Pro サブスクリプション)",
        "description": "Mac で `codex login` を 1 回実行 → harness が ~/.codex/auth.json を VM にコピー。refresh トークンは約 3 ヶ月、失効時に `codex login` の再実行と再デプロイが必要。OpenAI API キーの課金は不要。" },
      { "label": "Gemma 4(ローカル、認証不要)",
        "description": "VM 上に Ollama daemon をインストールし gemma4:e4b(~5 GB)をダウンロード。サブスクリプション不要、外部 API 呼び出しなし。A1.Flex の 4 ARM コアで推論 3-6 tok/s、daily-progress 1 回 30-60 秒。完全無料、永続。" }
    ]
  }]
}
```

**Behavior per choice:**

#### "Claude Code" / 「Claude Code」

Nothing extra to do. Q9.5 already captured the token. Persist `AI_PROVIDER=claude` to `.notification.env`:

```bash
NOTIF="$ROOT/.my-harness/.notification.env"
{ grep -v '^AI_PROVIDER=' "$NOTIF" 2>/dev/null || true; echo "AI_PROVIDER=claude"; } > "$NOTIF.tmp"
mv "$NOTIF.tmp" "$NOTIF"
chmod 600 "$NOTIF"
```

#### "Codex" / 「Codex」

Print bilingual step-by-step guidance to the screen, then wait for `continue` / `done` / 完了:

**LANG=en — display verbatim:**

```
To use Codex on the VM, do the following on THIS Mac:

  1. Make sure the Codex CLI is installed locally:

         ! npm install -g @openai/codex

  2. Run:

         ! codex login

     A browser opens. Sign in with your ChatGPT Plus / Pro account
     and authorize. The CLI writes ~/.codex/auth.json with your
     OAuth tokens.

  3. Return here and type `continue`. The harness will copy
     ~/.codex/auth.json to .my-harness/.codex-auth.json and
     setup-oci-vm.sh will scp it to the VM's ~/.codex/auth.json
     automatically.

Lifetime: the refresh token typically lasts ~3 months. When daily-progress
starts failing with auth errors on the VM, re-run `codex login` on this
Mac and re-run scripts/setup-oci-vm.sh — the harness will pick up the
refreshed auth.json.

Security: ~/.codex/auth.json grants ~3 months of inference access on
your ChatGPT subscription. Stored as chmod 600 in .my-harness/ (gitignored).
```

**LANG=ja — display verbatim:**

```
Codex を VM で使う手順 (この Mac で実行):

  1. Codex CLI をローカルにインストール:

         ! npm install -g @openai/codex

  2. 実行:

         ! codex login

     ブラウザが開きます。ChatGPT Plus / Pro アカウントでサインインし
     認可してください。CLI が OAuth トークンを ~/.codex/auth.json
     に保存します。

  3. ここに戻り `continue` と入力してください。harness が
     ~/.codex/auth.json を .my-harness/.codex-auth.json にコピーし、
     setup-oci-vm.sh が VM の ~/.codex/auth.json に scp します。

寿命: refresh トークンは通常約 3 ヶ月です。VM 上の daily-progress が
認証エラーで失敗するようになったら、この Mac で `codex login` を
再実行し scripts/setup-oci-vm.sh を再実行してください。harness が
新しい auth.json を自動的に拾います。

セキュリティ: ~/.codex/auth.json は約 3 ヶ月分の ChatGPT サブスク経由
推論アクセスを許可します。.my-harness/ 配下に chmod 600 (.gitignore
済み) で保存されます。
```

After the user types `continue`, run:

```bash
bash scripts/ensure-codex-auth.sh "$ROOT"
```

Exit codes:
- **Exit 0:** auth captured. Persist `AI_PROVIDER=codex` to `.notification.env` (same merge snippet as Claude path above with `codex` instead of `claude`), then proceed.
- **Exit 3:** ~/.codex/auth.json missing. Re-display the guidance and re-loop.

#### "Gemma 4" / 「Gemma 4」

Print a bilingual notice and persist `AI_PROVIDER=gemma4`:

**LANG=en:**
```
Gemma 4 needs no credentials. setup-oci-vm.sh will:

  1. Install Ollama on the VM (via the official one-line installer).
  2. Pull `gemma4:e4b` (~5 GB). This first download takes 5-15 minutes
     depending on your VM's network speed.
  3. Enable the `ollama` systemd service so it survives reboots.

Inference will run at 3-6 tokens/second on the A1.Flex's 4 ARM cores
(no GPU). A daily-progress summary typically completes in 30-60 seconds.

Nothing for you to do here — proceed.
```

**LANG=ja:**
```
Gemma 4 は認証情報不要です。setup-oci-vm.sh が次を実行します:

  1. VM 上に Ollama をインストール (公式の 1-line installer)。
  2. `gemma4:e4b` (~5 GB) をダウンロード。初回は VM のネットワーク
     速度に応じて 5-15 分かかります。
  3. `ollama` systemd サービスを enable して再起動後も生存させる。

A1.Flex の 4 ARM コア (GPU 無し) で推論は 3-6 tokens/秒です。
daily-progress の要約 1 回は通常 30-60 秒で完了します。

ここで人手作業は不要です — 次に進みます。
```

Persist `AI_PROVIDER=gemma4` to `.notification.env` (same merge snippet).

### Phase 1 wrap-up

After Q6-Q11 answered (or skipped via Q6=Disable / Q9=Skip / Q9.5=Skip / Q11=Skip), update `init-state.json` with `current_phase: "discovery"`, `phases_completed: ["language", "setup"]`. Move to Phase 2.

---

## Phase 2 — Open discovery conversation (the centerpiece, deeper drill)

This is the longest and most important phase. **Plan for 15–40 turns** — do not bail early. The probes (failure modes, resistance, scale breakpoints, trust, differentiation, day-2 ops) typically add 5–10 turns over a basic flow.

Phase 2 starts with one open question and continues as a free-form, multi-turn conversation until the **exit criteria** below are met. There are no scripted questions here — Claude reads each answer, updates the internal `discoverySheet`, and composes the next question dynamically based on what is still missing or still vague.

### NON-NEGOTIABLE rules for this phase

Full text + examples + bilingual ban lists are in **`rules/discovery-policy.md`** (read once at phase start, refer back as needed). The 11 rule headers below are the index; the canonical body lives in the rule file. Restating the long form here would risk Claude treating duplicate text as separate rules.

1. **Discovery NEVER reduces scope.** N features listed → N in scope. Volume / frequency questions are capacity targets only.
2. **Max-scope fast-path.** "全部 / max / fully equipped" → set `scaleExpectation = "max"`, skip all volume probes.
3. **Read the first message fully.** ≥ 5 features enumerated → feature scope locked.
4. **Strict no-redundancy.** Re-wording an already-asked question is a bug.
5. **Probes describe constraints, not choices.** "Upper bound" not "simple vs complex".
6. **Universal-default policy.** Don't ask about security / observability / quality / ops.
7. **Question length ≤ 5 lines.** Long preamble → split or skip.
8. **Binary when binary.** If (C) is "A+B with conditions", ask yes/no instead.
9. **Never ask for unknowable future predictions.** No "PV 1 年後 / year-1 user count / revenue forecast".
10. **Never force feature-ranking / `MVP核` / "core" selection.**
11. **Proactively suggest ideas the user didn't mention** (additive only, 2-4 per turn, never gap framing).

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

## Phase 5 — Visual (per-form-factor page+parts mocks; mocks are source of truth)

The mocks generated here become the **source of truth** for Phase 6 (tool selection) and Phase 7 (data model). Their visible elements (lists, forms, toggles, tabs, charts, real-time indicators, offline banners) are the inputs for tool decisions.

### Form factors, not platforms

Mocks are organized by **form factor** (`pc` / `mobile`), not by individual platform (web/ios/android/desktop). One form factor covers every platform that shares that viewport class:

- **`pc`** — covers `USE_WEB` (desktop view) and `USE_DESKTOP` (Electron/Tauri). Viewport ~1280-1440 px wide. Multi-column where appropriate.
- **`mobile`** — covers `USE_WEB` (mobile view), `USE_IOS`, and `USE_ANDROID`. Viewport ~390 px wide. Single-column. Bottom or top nav, not sidebar.

What gets generated is computed automatically from `.config`:

| `.config` flag | Triggers |
|---|---|
| `USE_WEB=yes` | both `pc` AND `mobile` (web is responsive) |
| `USE_DESKTOP=yes` | `pc` |
| `USE_IOS=yes` OR `USE_ANDROID=yes` | `mobile` |

The user never has to say "make me a PC mock" — `gen-page-auto.sh` reads `.config` and produces whatever form factors are implied. The user only lists the screens.

### Two paths

Read `USE_CODEX` from `.config`:

- `yes` → **image path**: `gen-page-auto.sh` calls `gen-page-parts.sh` once per needed form factor per screen.
- `no` → **text-spec path**: no image generation. Structured markdown per screen + TSX stubs derived from the markdown. See "USE_CODEX=no path" below.

Both paths run the same 3-question post-mock drill. Technical specifics live in `prompts/codex-page-mock.md` (Turn 1) + `prompts/codex-parts-grid-edit.md` (Turn 2+) + `scripts/gen-page-parts.sh` — do **not** restate them here. Auto-opening happens inside the scripts.

### Fixed questions (one per turn — match `LANG`)

1. Color hint (optional)
   - en: "Any color hint? (optional — e.g. `#14b8a6` / 'blue tones' / 'no preference')"
   - ja: "デザインの色のヒントはありますか？（任意 — 例: `#14b8a6` / 「青系」/ 「特になし」）"

2. Screen list — **one pass for the whole project** (form factor is automatic). Do NOT repeat per platform.
   - en: "List the 3–5 most-traveled screens for this app."
   - ja: "このアプリで最も使われる画面を 3〜5 個リストアップしてください。"

### Design philosophy (image path)

Trust Codex. No prescriptive palette / icon / layout instructions in the prompt — Codex chooses on the first artifact, the user picks, every subsequent artifact (next screen, other form factor) inherits via the locked-in style_guide.

### Pre-Stage: Skeleton bootstrap (one-time, idempotent)

Phase 5 commits per-screen design artifacts (see "Per-screen commit gate" below), which requires the harness's `.bare/` + main/stage/dev worktree layout to already exist. We do that here as a skeleton-only bootstrap — the heavier Phase 8 bootstrap (common files, platform templates, flake.nix generation, project-name substitution) runs later.

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/bootstrap.sh" "$ROOT" --skeleton
```

What `--skeleton` does:
1. Creates `<root>/.bare/` and main / stage / dev branches off an empty initial commit.
2. Adds main / stage / dev git worktrees so `<root>/{main,stage,dev}/` each track their own branch.
3. Creates the minimum directory tree `<root>/dev/docs/{spec,design,talk,task}/`.
4. Writes a baseline `<root>/dev/.gitignore` (only if absent).
5. Makes one initial `chore: skeleton bootstrap` commit on `dev` so subsequent `commit-design-screen.sh` calls have a parent commit.
6. Exits 0. Does NOT distribute common files, platform templates, flake.nix, etc. (those come in Phase 8).

Idempotent: re-running is a no-op. Phase 8 invokes `bootstrap.sh` again (without `--skeleton`); the early stages skip because `.bare/` already exists, and the remaining stages run for the first time.

After this step, every design artifact path mentioned below lives in `<root>/dev/` (the dev worktree) and every `commit-design-screen.sh` call commits into the `dev` branch.

### Phase 5 has THREE stages — do them in order

```
Stage 1  PNG + crop, all screens (one gen-page-auto.sh per screen)
Stage 2  HTML, all (form-factor, screen) pairs at once (one gen-html-all.sh for the whole project)
Stage 3  Claude polish of every HTML — read PNG, open HTML, fix layout defects
```

Stages must be done in this order: don't generate HTML for screen A before screen B's PNGs exist, because B's mocks influence the project's settled style_guide and Codex's edit-mode context for HTML.

### Stage 1 — Page + parts grid generation (per screen, automatic form-factor fan-out)

For each screen the user listed, run **one command** — `gen-page-auto.sh` handles which form factor(s) to produce based on `.config`. Loop through every screen first; **do not** invoke any HTML generation in this stage.

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/gen-page-auto.sh" \
  "$ROOT" "<screen-name>" "$PROJECT_NAME"
```

What this does internally:

1. Reads `USE_WEB`, `USE_IOS`, `USE_ANDROID`, `USE_DESKTOP` from `$ROOT/.my-harness/.config`.
2. Derives `NEED_PC` and `NEED_MOBILE` (see the table above).
3. For each needed form factor in order **PC then Mobile**, calls `gen-page-parts.sh` (page + grid in image-edit-mode chain) followed by `crop-parts.sh` (chroma-key cropping into transparent parts). PC is always first when both are needed, so Mobile inherits PC's locked-in `style_guide` AND **shared chrome** (header / footer / sidebar / bottom-nav — labels, order, icons, active states) via the project-wide Codex session AND via prior-manifest discovery. The first generated screen establishes the chrome; every subsequent screen reproduces it pixel-for-pixel via Codex's image-edit-mode context (only the main content region is redesigned per screen). See `prompts/codex-page-mock.md` "SHARED CHROME" section for the full rule.
4. Suppresses per-form-factor auto-open via `HARNESS_SKIP_OPEN=1`, then opens **all** produced PNGs together at the end so the user sees PC + Mobile side by side.
5. **Does NOT** generate HTML. HTML happens in Stage 2 after every screen's PNGs are settled.

### Per-screen commit gate (after every approval)

After the user confirms a screen's mock(s) look right (either on the first generation or after `refine-design.sh` iterations have settled), **always** commit that screen's design artifacts before moving on:

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/commit-design-screen.sh" \
  "$ROOT" "<screen-slug>" "<screen-display-name>"
```

This stages exactly the files for that screen (page-pc-\<slug\>.png, page-mobile-\<slug\>.png, parts-grid-\*-\<slug\>-\*.png, parts/\<ff\>/\<slug\>/, src/components/design/\<ff\>/\<slug\>/), commits with message `design(<slug>): mock approved -- pc+mobile` (or whichever form factors exist), and never touches files for other screens. Idempotent: if nothing changed since the previous commit (= the user said OK without any modification), it is a clean no-op.

**Why per-screen, not per-form-factor:** `gen-page-auto.sh` produces both form factors as a unit and the user reviews them together (PC + Mobile side by side via the bulk auto-open). A "screen approved" event covers both. Committing per form factor would split a single approval into two commits and bloat the log.

**Why before Stage 2:** HTML generation happens in batch after every screen's PNG is locked in. By the time `gen-html-all.sh` runs, each screen has already been committed individually, so the HTML batch commits cleanly on top as a separate Stage 2 commit (which Claude does at the end of Stage 3 polish — see below).

**When refining:** every accepted `refine-design.sh` round also calls `commit-design-screen.sh` for the affected screen. The history reads like a real designer's commit log: one commit per approved iteration per screen, naming the screen explicitly.

**LANG=en — what Claude says when committing:** "I'm committing the approved design for `<screen-name>` to the project repo (`design(<slug>): mock approved`). Other screens are untouched."

**LANG=ja — what Claude says when committing:** "承認された `<screen-name>` のデザインをプロジェクトリポジトリにコミットします (`design(<slug>): mock approved`)。他の画面には影響しません。"

### Stage 2 — Batch HTML generation (one command, all screens × all form factors)

After every `gen-page-auto.sh` call has finished (= every screen's PNGs are locked in), run **once**:

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/gen-html-all.sh" "$ROOT"
```

What this does:

1. Reads `USE_CODEX` from `.config`. If `no`, exits 0 immediately (HTML is then Claude's job — see USE_CODEX=no path below).
2. Walks `dev/docs/design/parts/*/*/manifest.json` to discover every (form-factor, screen-slug) pair that has a settled PNG mock.
3. For each pair, calls `gen-page-html.sh` on the shared `design-html-<project-slug>` Codex session. The session sees every page-mock PNG via `--context` attachment and inherits the locked-in `style_guide` from each manifest.
4. Suppresses per-pair auto-open, then opens **all** produced HTML files together so the user can scan the batch.

Why batch rather than per-screen-inline: the user said so explicitly (PNGs first, HTML second). It also means the whole visual identity has been reviewed/approved across every screen before any markup is committed.

**Style consistency across the project** is enforced two ways:

- **Session-context inheritance** — every `gen-page-parts.sh` invocation uses the same Codex session `design-image-<project-slug>`. The session keeps every prior generated image visible in conversation context, so later turns can edit-mode-reference them.
- **Style-guide invariant echoing** — `gen-page-parts.sh` scans all prior `manifest.json` files under the project, lifts the first found `style_guide`, and injects it into the next Turn-1 prompt as IMMUTABLE INVARIANTS. The first artifact's design language (palette / illustration / character / line weight / motifs) becomes locked-in for every later screen and every later form factor.

**Ask first** (Cardinal rule: Codex opt-in per occurrence). If the user says yes, run `gen-page-auto.sh` once per screen.

The prompt bodies live at `prompts/codex-page-mock.md` (Turn 1) and `prompts/codex-parts-grid-edit.md` (Turn 2+ edit-mode grids) — edit them there, not in this SKILL.

### Iterative refinement

When the user says "the buttons should be more rounded" or "this card needs a shadow", `refine-design.sh` resumes the same project-wide Codex image session (`design-image-<project-slug>`) and names the target screen explicitly:

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/refine-design.sh" \
  "$ROOT" "<form-factor>" "<SCREEN_NAME>" "<user's edit request>"
```

If the parts grid for that screen is affected, the refinement prompt asks Codex to regenerate it in edit mode against the new page, preserving every immutable style invariant.

Iterate until the user approves. Once approved, proceed to the cropping step below.

**Reliability:** `gen-page-parts.sh` retries each turn up to 3× in the same session. If retries exhaust, the script exits non-zero. Surface plainly to the user: "Codex did not produce the PNG after 3 attempts. Session preserved — want to retry, or skip this screen for now?"

### What's in the parts grid (and what is NOT)

The parts grid catalogs **only non-HTML assets** — visual elements that cannot be cleanly recreated in HTML/CSS:

- **Include:** custom illustrations, brand marks / logos / badges, decorative graphics, bespoke icons not in Lucide / common libraries, hand-drawn shapes, texture patterns.
- **Exclude:** buttons, inputs, dropdowns, cards, nav items, list rows, modals, typography, library icons (Lucide / Heroicons), and any element that is "a colored box with text". Those are HTML-rendered and never live as PNG assets.

If a screen has zero non-HTML assets, `gen-page-parts.sh` produces only the page mock and a manifest with `"rows": 0`. Cropping and TSX scaffolding are then no-ops (`parts.ts` is still emitted but empty).

### Slicing the parts grid into transparent PNGs (fully automated)

Cropping is deterministic — cells are a fixed 256×256 (override via `CELL_SIZE` env var). The manifest produced by `gen-page-parts.sh` is already at the right path; Claude does NOT need to look at the image via Vision.

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/crop-parts.sh" \
  "$ROOT" "<form-factor>" "<screen-slug>"
```

Run once per form factor that `gen-page-auto.sh` produced (typically `pc` and/or `mobile`). Outputs:

- `$ROOT/dev/docs/design/parts/<form-factor>/<screen-slug>/<name>.png` — transparent-background PNG per cell. **Chroma key on pure magenta `#FF00FF`** removes the grid background — which means **white pixels inside assets are preserved** (clouds, paper, white logos, snow, white speech bubbles all stay opaque white). Background removal uses Aral Balkan's chroma-key formula adapted for magenta — `alpha = g - min(r, b) + 1` — which drives every pure-magenta pixel to fully transparent. The pipeline then applies `-channel A -level <CHROMA_FLOOR>x100%` (default `30%`) to cut residual magenta-tinted edge pixels (alpha ≤ floor → 0) while LINEARLY STRETCHING the remainder so real anti-aliased asset edges stay soft (not binarized). Raise `CHROMA_FLOOR` toward `50%` for stricter residue removal at the cost of slightly tighter edges; lower toward `15%` to preserve more anti-aliasing. Phase-5 HTML references these via a simple relative path (`parts/<form-factor>/<screen-slug>/<name>.png` from `dev/docs/design/`); implementation-phase TSX can either copy this tree to `dev/public/design/parts/` for runtime serving or import each PNG directly via the bundler.
- `$ROOT/dev/src/components/design/<form-factor>/<screen-slug>/parts.ts` — TS asset map (written by `scaffold-tsx-from-parts.sh`, used only in the implementation phase).

`crop-parts.sh` auto-opens every cropped part PNG on completion (suppress with `HARNESS_SKIP_OPEN=1` if scripting a batch). On macOS they all open in Preview as a single window list; on Linux each is opened via `xdg-open`.

Requires ImageMagick (`magick` or `convert` on `$PATH`). If missing, surface plainly: "ImageMagick is required to slice the parts grid. Install with `brew install imagemagick` (macOS) or `apt install imagemagick` (Linux), then retry."

### Upscaling a part when the display size exceeds 256×256

The 256×256 source is the default size. When the page calls for an asset at a larger display size (e.g., a hero illustration at 1600×800), regenerate **just that part** at the target size via Codex (same session — palette and style are preserved):

```bash
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/upscale-part.sh" \
  "$ROOT" "<form-factor>" "<screen-slug>" "<part-name>" <width> <height>
```

Output:

- `$ROOT/dev/docs/design/parts/<form-factor>/<screen-slug>/<part>-<W>x<H>.png` — the upscaled PNG.
- `parts.ts` gets a new entry, e.g., `heroIllustration1600x800: '/design/parts/.../hero-illustration-1600x800.png'`.

The original 256×256 PNG is left in place. Components import whichever size matches their display context.

Decide when to upscale based on the page mock: if a part is rendered larger than 256px on either axis in the page, upscale it. Otherwise, the source is enough.

### Page HTML generation (final Phase 5 deliverable)

There are **two paths** depending on `USE_CODEX`:

#### USE_CODEX=yes — Codex writes the initial HTML (Stage 2), Claude polishes it (Stage 3, BOTH REQUIRED)

**Important — Claude's role in Stage 3 is verification + iteration, NOT silent rewriting.** All three Codex prompts (`codex-page-mock.md`, `codex-parts-grid-edit.md`, `codex-page-to-html.md`) now end with a "NON-NEGOTIABLE QUALITY BAR" section that forbids Codex from shipping partial output and requires it to emit `ABORT: <reason>` instead of glossing over a gap. When reviewing Codex output, Claude's job is to **read carefully**, surface any drift between the mock and the HTML to the user, and call `refine-design.sh` / `gen-page-html.sh` again with explicit feedback — NOT to quietly patch the HTML and pretend it was Codex's output. The user's explicit instruction (7.21.0): Claude must not make its own interpretations; Codex is responsible for the deliverable, and if Codex's output is wrong, Codex re-does it with stronger guidance.

**Step 1 — Codex writes the first cut** (Stage 2 of Phase 5, batch-driven by `gen-html-all.sh`):

After every screen's PNGs are settled (Stage 1 complete), `gen-html-all.sh` walks the manifest tree and calls `gen-page-html.sh` once per (form-factor, screen). The Codex HTML session is `design-html-<project-slug>`, separate from the image session, and each call receives:

- The page-mock PNG as a `--context` attachment (so Codex must visually reference it to fulfill the prompt).
- The full `manifest.json` as inline JSON (so Codex knows every available cropped part).
- The `style_guide` from the manifest as immutable invariants.

Output lands at `$ROOT/dev/docs/design/page-<form-factor>-<screen-slug>.html`. Source: `scripts/gen-page-html.sh` + `prompts/codex-page-to-html.md`.

**Step 2 — Claude polishes the layout (Stage 3 of Phase 5, MANDATORY)** ⛔️

Codex's HTML is a first cut, not a finished deliverable. Its `file_write` tool cannot iterate on layout — it commits one snapshot. Common defects in the Codex output:

- Elements that overflow their container ("潰れているところ") — text bleeding past edges, overlapping blocks
- Component spacing off (gap / padding values wrong vs. the PNG)
- Wrong column count on PC layouts
- Missing aria attributes on icon-only buttons
- An asset listed in manifest but never used in markup (or vice versa)
- State variants implemented as duplicated elements instead of pseudo-classes

For EACH `page-<form-factor>-<screen-slug>.html` that Codex produced:

1. **`Read`** `$ROOT/dev/docs/design/page-<form-factor>-<screen-slug>.png` — multimodal vision context loaded.
2. **Open** the HTML in the browser (`open <path>` macOS / `xdg-open` Linux / `start "" <path>` Windows) — get the rendered view.
3. **Compare** PNG vs rendered HTML. List concrete defects (be specific: "header logo overflows on PC at >1280px", not "looks off").
4. **`Edit`** the HTML file to fix each defect. One Edit per defect when possible — easier to review.
5. **Repeat** Steps 2-4 until the rendered HTML visually matches the PNG within reason. Hard stop after 3 polish iterations even if not perfect — diminishing returns.

This Step 2 is NOT optional. Skipping it means shipping Codex's raw output, which routinely has 3-8 layout defects per screen even when the prompt was clear.

Refinements requested by the user later (after the polish pass) can be applied either via `Edit` directly (Claude's tool) or — if the request is large — via the Codex session for re-generation:

```bash
SESSION_KEY=$(cat "$ROOT/.my-harness/codex-session-design-html.txt")
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/codex-ask.sh" \
  --role designer \
  --session "$SESSION_KEY" \
  --out "$ROOT/.my-harness/codex-html-<ff>-<screen>-rN.md" \
  "Apply this change to the <SCREEN_NAME> screen on <FORM_FACTOR>: <user's request>. Overwrite the same HTML file."
```

After a Codex-driven refinement, Claude must redo Step 2 (polish) since Codex may have re-introduced defects.

#### USE_CODEX=no — Claude writes the HTML directly

When Codex is not available, Claude (you) writes the HTML. Procedure (per screen × per form factor):

1. `Read` the page mock PNG at `$ROOT/dev/docs/design/page-<form-factor>-<screen-slug>.png` — this loads the image into Claude's vision context so you can see the actual design.
2. `Read` the manifest at `$ROOT/dev/docs/design/parts/<form-factor>/<screen-slug>/manifest.json` — this lists every cropped transparent PNG you can `<img>` into the markup.
3. `Write` the HTML file to `$ROOT/dev/docs/design/page-<form-factor>-<screen-slug>.html` using the rules below.

**HTML file structure (use this exact scaffold):**

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><screen> — <project></title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Noto+Sans+JP:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    body { font-family: 'Inter', 'Noto Sans JP', -apple-system, BlinkMacSystemFont, sans-serif; }
  </style>
</head>
<body class="bg-neutral-50 text-neutral-900 antialiased">
  <!-- page markup matching the PNG exactly -->
</body>
</html>
```

**Markup rules:**

- Tailwind utility classes only. No custom CSS beyond the `<style>` block above.
- No JavaScript (no `<script>` besides Tailwind CDN). No event handlers.
- State variants (hover / focus / disabled / active / selected) → Tailwind pseudo-class utilities (`hover:bg-primary-600`, `disabled:opacity-50`, etc.) plus `aria-*` attributes. One canonical element per UI piece.
- Realistic content (no Lorem Ipsum). Japanese stays Japanese; English stays English.
- Semantic HTML (`<header>`, `<main>`, `<nav>`, `<section>`, `<article>`, `<button>`, `<label>`, `<input>` …). `aria-label` on icon-only buttons.
- Inline `<svg>` for small Lucide-style icons; no JS-loaded icon library.
- Cropped parts: HTML lives in `dev/docs/design/` and parts live in `dev/docs/design/parts/<form-factor>/<screen-slug>/`, so the relative path is just `parts/<form-factor>/<screen-slug>/<name>.png`. Example: `<img src="parts/<form-factor>/<screen-slug>/<name>.png" alt="..." class="...">`. Decorative-only assets: `alt=""` + `aria-hidden="true"`.
- Page container max-width by form factor: `pc` → `max-w-7xl`, `mobile` → `max-w-[430px]`. Always mobile-responsive even on PC.
- HTML must render correctly from `file://` (no dev server, no build step). Verify the relative parts paths resolve.

After writing, run:

```bash
open "$ROOT/dev/docs/design/page-<form-factor>-<screen-slug>.html"  # macOS — auto-open in default browser
```

(use `xdg-open` on Linux, `start ""` on Windows).

**Why this path only when USE_CODEX=no:** when Codex is available, automating HTML through it removes the risk that Claude writes HTML from prompt-derived guesses without reading the PNG. With Codex disabled, the harness has no choice but to fall back to Claude — which works fine as long as Claude actually reads the PNG (see the enforcement checklist above).

### Iteration (USE_CODEX=no path)

When Claude wrote the HTML, refinements: edit the file directly with the `Edit` tool. If the change is large enough that re-reading the PNG would help, `Read` the page-mock PNG first and rewrite the relevant section.

### Iteration on the page mock (always Codex)

Refinements to the page-mock PNG itself: `scripts/refine-design.sh "$ROOT" "<form-factor>" "<SCREEN_NAME>" "<change>"` (resumes the `design-image-<project-slug>` session).

### Implementation-phase TSX conversion (NOT part of Phase 5)

`scripts/scaffold-tsx-from-parts.sh` exists for **the implementation phase**, not Phase 5. It generates one thin TSX wrapper per cropped PNG (each renders `<img src={parts.<key>} />`). Use it only when you've decided to start React-izing the design. The natural alternative — and usually the better one — is to ask Codex during implementation to convert the HTML directly into one or more TSX components, since the HTML already encodes the structure and Tailwind classes.

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

If a mock reveals that requirements have changed (the answer to drill #3 surfaces a new entity, permission, or integration), update the internal notes, log the constraint, and either regenerate the affected mock or note it for Phase 6 / 7. **Maximum 3 iteration cycles per screen.**

### USE_CODEX=no path (no image generation)

When `USE_CODEX=no`, the image pipeline above is skipped entirely (no Codex calls, no PNG, no auto-crop). Each screen still gets:

1. **A text-spec markdown file** at `dev/docs/design/text-mock-<platform>-<screen-slug>.md` with a defined structure:

   ```markdown
   # <Screen Name> — <Platform>

   ## Layout
   <one-paragraph description of overall layout, hierarchy, grid>

   ## Visible elements (top to bottom, left to right)
   - <element>: <one-sentence description with state variants>
   - <element>: ...

   ## Parts list
   - <part-name>: <component type + key props + state variants>
   - <part-name>: ...

   ## Interactions
   - <action>: <result>
   ```

   Claude composes this from the spec + the user's screen list. The user reviews and corrects.

2. **TSX component stubs** at `dev/src/components/design/<platform>/<screen-slug>/<PartName>.tsx`, one per entry in the "Parts list" section. Each stub:
   - Has a `/** 概要: ... */` JSDoc comment naming the part and referencing the text-mock file.
   - Has props for the state variants listed in the text spec.
   - Uses Tailwind classes following `rules/design.md` (Lucide icons, no AI-style gradients).
   - Renders a working component — not just a `TODO` — but visual polish is deferred to the implementation phase.

3. **No `parts.ts` and no transparent PNGs** are produced on this path. If the user later switches to `USE_CODEX=yes`, the same screen can be regenerated and the image-path artifacts will overlay the text-spec path.

The 3-question post-mock drill runs on the text-spec markdown (treat the markdown as the mock).

`visualMocks[].path` for `USE_CODEX=no` screens points to the `text-mock-*.md` file rather than a PNG.

### Completion criteria

- [ ] One page+parts concept per screen finalized
- [ ] 3–5 mocks selected per chosen platform (USE_CODEX=yes only; text mocks otherwise)
- [ ] Every mock has the 3-question post-mock drill answered
- [ ] OG image / favicon generated
- [ ] `visualMocks[]` in `init-state.json` populated, `decisionsRevealed` non-empty for every entry

Save to: `dev/docs/spec/05-visual.md` and `dev/docs/design/page-<form-factor>-<screen-slug>.png` (one page mock per screen × form factor). Cropped transparent parts auto-land at `dev/docs/design/parts/<form-factor>/<screen-slug>/<name>.png`; the implementation-phase TSX import manifest (if scaffolded) lives at `dev/src/components/design/<form-factor>/<screen-slug>/parts.ts`. Update `init-state.json` to `current_phase: "tools"`.

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

**Token reuse note:** If `USE_CLAUDE_ACTION=yes` and `CLAUDE_AUTH=oauth`, check whether `.my-harness/.notification.env` already contains a non-empty `CLAUDE_CODE_OAUTH_TOKEN` (written by Q9.5 during Phase 1). If present, skip any further OAuth token collection here — `setup-secrets.sh` will read and push the saved value automatically. Only prompt the user if the key is absent.

### After Phase 6

Save the consolidated config to `<root>/.my-harness/.config`. Create the directory tree first, then use the `Write` tool to drop the config in place (no shell heredoc):

```bash
mkdir -p "$ROOT/.my-harness" "$ROOT/dev/docs/spec" "$ROOT/dev/docs/design" "$ROOT/dev/docs/talk" "$ROOT/dev/docs/task"
```

Then `Write` `$ROOT/.my-harness/.config` with this template (replace every `<...>` placeholder with the value chosen during Phases 1 / 3 / 6):

```ini
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
bash "${CLAUDE_PLUGIN_ROOT:?}/scripts/commit-initial-docs.sh" "$ROOT" "$LANG"
```

Implementation: cd into `$ROOT/dev`, git add (only files that exist), commit with `harness-bot` identity and `--no-verify`. Commit message is language-aware (`ja` → Japanese, else English). Source: `scripts/commit-initial-docs.sh`.

### 8.6 Update init-state.json + stop + guide user to dev

Use the `Write` tool to overwrite `$ROOT/.my-harness/init-state.json` with the completion state. `timestamp` is the current UTC time in ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`):

```json
{
  "schema_version": "3",
  "project_name": "<PROJECT_NAME>",
  "lang": "<LANG (en|ja)>",
  "root": "<ROOT>",
  "current_phase": "completed",
  "phases_completed": ["language", "setup", "discovery", "structure", "features", "visual", "tools", "data-model", "bootstrap", "tasks"],
  "next_action": "implementation",
  "next_action_command": "/harness-team-lead",
  "working_directory": "<ROOT>/dev",
  "issue_count": <number of child issues generated>,
  "lanes_assigned": true,
  "timestamp": "<UTC ISO-8601>"
}
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
│   │   ├── design/page-<form-factor>-<screen>.png  Page mock per screen × form factor (pc / mobile)
│   │   ├── design/parts-grid-<form-factor>-<screen>-N.png  Codex parts-grid for chroma-key cropping
│   │   ├── design/page-<form-factor>-<screen>.html  Tailwind HTML (Claude-written from page PNG)
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
