---
name: my-harness-init
description: Runs the full new-project pipeline end-to-end. Phase 0 picks language, Phase 1 collects only the truly orthogonal setup flags, Phase 2 holds an open multi-turn discovery conversation that drills into the user's idea and produces a structured discoverySheet, Phase 3 fires AskUserQuestion only for decisions still ambiguous after discovery (architecture, package manager, platforms, frameworks, backend, database, email, e2e), Phases 4–7 cover features / data model / visual / bootstrap. Triggered by /my-harness-init.
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

This skill replaces blind structured questionnaires with a **two-step interview**:

1. **An open discovery conversation** (Phase 2) where Claude asks free-form, drilling questions and maintains a structured `discoverySheet` internally — this is where requirements actually crystallize.
2. **Targeted disambiguation** (Phase 3) using `AskUserQuestion` only for decisions the discoverySheet has **not** already resolved.

**Cardinal rules — applied every turn:**

- **Never ask a question whose answer is already implied by what the user said.** Before composing any prompt, re-read the discoverySheet and skip questions whose field is already populated.
- **Drill down at least one level.** If a user answer is vague ("a chat app"), the immediate next question must narrow the space ("ephemeral or stored history? group or 1:1? media or text only?").
- **One question per turn.** Batch questions are prohibited.
- **Discovery before structured choice.** Phase 2 must happen before Phase 3. Do not jump to `AskUserQuestion` until the discoverySheet meets the exit criteria below.
- **Bilingual parity.** Every user-facing prompt and explanation has both an `LANG=en` and `LANG=ja` variant. After Phase 0, render only the chosen language.
- **No marketing / brand strategy / 5-year vision.** Stay system-relevant.

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

## Flow (8 phases)

`language` → `setup` → `discovery` → `disambiguation` → `features` → `data-model` → `visual` → `bootstrap` → `tasks` → `completed`

`data-model` is skipped when the disambiguation phase determines no DB. bootstrap.sh writes the state automatically (`current_phase: "bootstrap-completed"`).

### Managing init-state.json (for pause/resume)

At the completion of each phase, write the following. `current_phase` is the **next** phase to advance to; `phases_completed` is the list of **already finished** phases:

```bash
ROOT=<root>
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$ROOT/.my-harness"
cat > "$ROOT/.my-harness/init-state.json" <<EOF
{
  "schema_version": "2",
  "project_name": "<PROJECT_NAME>",
  "lang": "en",
  "root": "$ROOT",
  "current_phase": "<next phase>",
  "phases_completed": ["language", "setup", "discovery"],
  "next_action": "interview",
  "next_action_command": "Continue /my-harness-init (Phase: <next>)",
  "working_directory": "$ROOT",
  "discoverySheet": { /* Phase 2 schema, populated as it grows */ },
  "timestamp": "$TIMESTAMP"
}
EOF
```

### Pause/resume

When the user says "pause", "stop", or similar:
- Update `init-state.json` and `discoverySheet` to the latest state, tell the user where it was saved and the resume command, then stop.

When the user comes back:
- Read `<root>/.my-harness/init-state.json` and check `current_phase`. Resume from the first question of that phase. Existing `docs/spec/` and `docs/talk/` are carried forward.

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

If found, ask: "You were last at the `<current_phase>` phase. Resume? (y/n)". `y` → resume; `n` → confirm discard or different directory. If not found → start at Phase 0.

---

## Phase 0 — Language

**Ask once:**

> "Should I speak Japanese with you, or English? (`en` or `ja`, default `en`)"

Persist `LANG=en|ja`. From here every prompt renders **only** in the chosen language.

**Acknowledgment:**

- `LANG=en`: "Got it — I'll continue in English. Let's pin down a few setup details, then we'll have a real conversation about what you're building."
- `LANG=ja`: "了解しました。ここから先は日本語で進めます。最小限のセットアップ確認をしてから、何を作るのか会話で深掘りします。"

Save to `.my-harness/.config` (first entry):
```
LANG=<en|ja>
```

Update `init-state.json` with `current_phase: "setup"`, `phases_completed: ["language"]`.

---

## Phase 1 — Minimal setup (only orthogonal flags)

Ask the following one at a time. **Do not ask the project name here** — let it emerge from Phase 2's conversation. Only re-ask at the end of Phase 2 if it has not surfaced.

### Setup Q1: Project root directory

**LANG=en:**
> "Where should the project live on disk? (default: `~/projects/<name>` once a name is settled, or `~/projects/my-project` as placeholder)"
>
> **What this controls:** Parent directory for source, worktrees, spec files. `<root>/dev` is the day-to-day worktree. Auto-created if missing.

**LANG=ja:**
> "プロジェクトをどこに作成しますか？（デフォルト: `~/projects/<プロジェクト名>`、未定なら `~/projects/my-project`）"
>
> **これが影響する箇所:** ソース・ワークツリー・spec の親ディレクトリ。`<root>/dev` が日常作業用。無ければ自動作成。

### Setup Q2: Codex integration

**LANG=en:**
> "Use Codex for AI-assisted design and code review? (y/n, default: n)"
>
> **What this controls:** Codex (OpenAI CLI) supplies second opinions, generates logos and UI mocks via `gpt-image-2`. Completely optional — `n` works end-to-end with Claude alone. Re-enable later via `.my-harness/.config`.

**LANG=ja:**
> "Codex（OpenAI CLI）を使ったAI支援デザイン・コードレビューを有効にしますか？ (y/n、デフォルト: n)"
>
> **これが影響する箇所:** Codex はセカンドオピニオン生成と `gpt-image-2` でのロゴ・UIモック生成を行います。完全任意で、`n` でも全機能が Claude 単体で動作します。後から `.my-harness/.config` で `USE_CODEX=yes` に変更可能。

#### If USE_CODEX=yes — sub-toggles

##### Q2a: Codex auth check

```bash
bash ~/my-harness-generator/scripts/check-codex-auth.sh
```
- `not-installed` → guide user to `npm i -g @openai/codex`; re-ask Q2
- `not-logged-in` → ask user to `codex login`; after 3 failures auto-set USE_CODEX=no
- `logged-in` → confirm:
  - **LANG=en:** "Codex is ready. I'll resume Codex conversations in session `<PROJECT_SLUG>-init`."
  - **LANG=ja:** "Codex の認証を確認しました。セッション `<PROJECT_SLUG>-init` で会話を継続します。"

`CODEX_SESSION = <PROJECT_SLUG>-init`. Never asked.

##### Q2b: Delegate engineer to Codex?

- **LANG=en:** "Delegate the engineer (implementation) subagent to Codex? (y/n, default: y — Codex is strong at code generation)"
- **LANG=ja:** "エンジニア（実装）サブエージェントを Codex に委任しますか？ (y/n、デフォルト: y — Codex はコード生成が得意)"

##### Q2c: Delegate e2e-reviewer to Codex?

- **LANG=en:** "Delegate the e2e-reviewer subagent to Codex? (y/n, default: n — Claude runs Playwright/Maestro locally regardless; `y` only routes the failure-report synthesis to Codex)"
- **LANG=ja:** "e2e-reviewer サブエージェントを Codex に委任しますか？ (y/n、デフォルト: n — Playwright/Maestro は常に Claude がローカル実行。`y` は失敗レポート合成のみを Codex に依頼)"

##### Q2d: Delegate reviewer to Codex?

- **LANG=en:** "Delegate the reviewer (convention review) subagent to Codex? (y/n, default: y)"
- **LANG=ja:** "reviewer（規約レビュー）サブエージェントを Codex に委任しますか？ (y/n、デフォルト: y)"

If USE_CODEX=no, all three sub-flags forced to `no`.

### Setup Q3: Inherit global CLAUDE.md

**LANG=en:**
> "Inherit your global `~/.claude/CLAUDE.md` in this project? (y/n, default: y)"
>
> **What this controls:** `n` writes `dev/.claude/settings.json` with `claudeMdExcludes` listing your absolute `~/.claude/CLAUDE.md` path so the project starts isolated from your personal global instructions.

**LANG=ja:**
> "個人グローバル `~/.claude/CLAUDE.md` をこのプロジェクトに引き継ぎますか？ (y/n、デフォルト: y)"
>
> **これが影響する箇所:** `n` を選ぶと `dev/.claude/settings.json` の `claudeMdExcludes` に絶対パス指定で `~/.claude/CLAUDE.md` を登録し、Claude Code がこのプロジェクトでは個人指示を読み込まないようにします。

Persist `USE_GLOBAL_CLAUDE=yes|no`.

### Setup Q4: Task management

**LANG=en:**
> "Track tasks via GitHub Issues, or as local markdown in `dev/docs/task/`? (`issues` / `local`, default: `local`)"

**LANG=ja:**
> "タスク管理は GitHub Issues、それとも `dev/docs/task/` のローカルマークダウン？ (`issues` / `local`、デフォルト: `local`)"

After these are answered, update `init-state.json` with `current_phase: "discovery"`, `phases_completed: ["language", "setup"]`. Move to Phase 2.

---

## Phase 2 — Open discovery conversation (the centerpiece)

This is the longest and most important phase. **Plan for 10–30 turns** — do not bail early.

Phase 2 starts with one open question and continues as a free-form, multi-turn conversation until the **exit criteria** below are met. There are no scripted questions here — Claude reads each answer, updates the internal `discoverySheet`, and composes the next question dynamically based on what is still missing or still vague.

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
    "openQuestions": ["..."]
  }
}
```

Initialize all fields to empty / `undecided` at Phase 2 start.

### Exit criteria

End Phase 2 when **(a) OR (b)**:

(a) The user explicitly says they're done ("that's all", "that's enough", "もう十分", "以上で").

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

If `projectName` is still empty when (b) hits, ask once before exit:
- **LANG=en:** "Before we move on, what should we call this project? (becomes directory name, package.json `name`, branch namespace)"
- **LANG=ja:** "ここまでで決めた範囲を踏まえて、プロジェクト名は何にしますか？（ディレクトリ名・package.json の `name`・ブランチ名前空間に使われます）"

### Opening prompt

- **LANG=en:** "Tell me about what you're building. Don't worry about format — start anywhere that feels natural. I'll ask follow-up questions and we'll narrow it down together."
- **LANG=ja:** "作りたいものについて自由に話してください。形式は気にせず、自然に始まる場所から。フォローアップの質問をしながら一緒に絞り込んでいきましょう。"

### How Claude asks open questions and drills down

After every user reply, run this internal checklist **before composing the next question**:

1. **Mask** the reply (apply secret-masking rules) and append to `dev/docs/talk/02-discovery.md`.
2. **Update the discoverySheet.** For every field the reply just touched, fill it in or refine it. Persist.
3. **Drill check:** "Have I drilled at least one level deep on this?" If the answer is vague (one sentence, no specifics), the next question MUST narrow.
4. **Coverage check:** "Which discoverySheet fields are still empty or vague?" The next question targets the most consequential one — typically the one that unlocks subsequent decisions (e.g., scale before persistence; offline before sync model; privacy before backend choice).
5. **No-redundancy check:** "Have I already asked something close to this?" Skip if yes.
6. **One thing at a time:** ask exactly one question.

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
  - Good (en): "If I assume 1–100 users for the first year, does that match? And is the data only useful to you (private), or do friends see each other's stuff (shared)?"
  - Good (ja): "初年度は 1〜100 ユーザー想定でいいですか？データは自分専用（プライベート）ですか、友人同士で見える（共有）ですか？"
- User: "Should work on the subway."
  - Good (en): "So full offline write/read, then sync when online? Or read-only cache while offline?"
  - Good (ja): "オフラインでも書き込み・読み込みOK、繋がった時に同期？それともオフライン時は閲覧のみキャッシュ？"

### Open-question stems Claude can adapt

- **What does the user actually do with this?** ("walk me through a typical session, step by step")
- **Who's the primary user?** ("If only one type of person uses this, who?")
- **Who pays for the infrastructure?** (rules out free-tier-only / steers toward serverless vs always-on)
- **How do users find each other / find content?** (search, social graph, link-share, public feed)
- **Does the data have to stay on-device or in a region?** (privacy, residency)
- **What happens when two users edit the same thing at once?** (sync model)
- **What's the worst-case latency the user will tolerate?** (drives architecture)
- **How big does it get in year one? Year three?** (scale)
- **Is there anything regulated about the data?** (HIPAA, GDPR, PCI, SOC2)
- **Is there a reason this can't run on a normal client + server?** (this surfaces P2P intuitions naturally)

### Mid-conversation pulse-checks

Every ~5 turns, summarize the discoverySheet back to the user in one or two sentences and ask "Is that right? Anything to adjust?". Update the sheet from the correction.

### Exit ritual

When exit criteria met, **show the discoverySheet to the user as a formatted summary** (not raw JSON — use a numbered list grouped by topic) and ask:

- **LANG=en:** "Here's what I have. Anything to correct or add before we move to the structured choices?"
- **LANG=ja:** "ここまでの整理です。次の構造化された質問に進む前に、修正・追加はありますか？"

If the user corrects, update sheet and repeat ritual. Once confirmed, persist final discoverySheet, write `dev/docs/spec/02-discovery.md` (the formatted summary), update `init-state.json` to `current_phase: "disambiguation"`, and proceed to Phase 3.

If USE_CODEX=yes, run a Codex consult at the end:
```bash
~/my-harness-generator/scripts/codex-ask.sh --role analyst \
  --out <root>/.my-harness/codex-phase2.md \
  "DiscoverySheet: <paste JSON>. Point out logical contradictions, ambiguities, or missing items."
```

---

## Phase 3 — Disambiguation via `AskUserQuestion`

For each decision below, **first re-read the discoverySheet**. Only fire `AskUserQuestion` when the sheet has **not** already locked the answer.

When the sheet already implies a decision, say it explicitly and skip:
- **LANG=en:** "From our conversation I already know `<decision> = <value>` (because you said `<reason>`). Skipping that question."
- **LANG=ja:** "先ほどの会話から `<決定> = <値>` は確定していると判断しました（`<理由>` のため）。この質問はスキップします。"

Use the actual `AskUserQuestion` Claude Code tool. Up to 4 choices per question, max 4 questions per turn. Use `multiSelect: true` where appropriate. Use `preview` (single-select only) for choices that need comparison. Mark the recommended choice as `(Recommended)` and put it first.

### Decision 1 — Architecture (only when `architectureHints == "undecided"`)

Single-select. Use `preview` to show one-line ASCII diagrams.

| Choice | Preview |
|--------|---------|
| `Client + REST/GraphQL backend (Recommended)` | `[Client] ⇄ HTTPS ⇄ [Backend API] ⇄ [DB]` |
| `Client + serverless functions` | `[Client] ⇄ HTTPS ⇄ [Edge fn] ⇄ [DB]` |
| `Pure P2P (no central server)` | `[Peer A] ⇄ DHT/relay ⇄ [Peer B]` |
| `P2P + coordinator/bootstrap server (hybrid)` | `[Peer A] ⇄ [Coord] ⇄ [Peer B]   data: peer↔peer direct` |

**LANG=en question:** "Which overall architecture? Pick one — preview shows the data-flow shape."

**LANG=ja question:** "全体アーキテクチャを選んでください。プレビューはデータの流れ図です。"

Persist `ARCHITECTURE=client-server|client-serverless|p2p-pure|p2p-hybrid`.

### Decision 2 — Package manager (always)

Single-select.

| Choice | Note |
|--------|------|
| `pnpm (Recommended — fastest cold install, content-addressable store)` | mature, monorepo-friendly |
| `bun` | faster runtime, native test runner, single binary |
| `npm` | universal, slowest |
| `yarn` | classic alternative |

**LANG=en:** "Which Node package manager?"
**LANG=ja:** "Node のパッケージマネージャーは？"

Persist `PACKAGE_MANAGER=pnpm|bun|npm|yarn`.

### Decision 3 — Platforms (always, multiSelect)

`multiSelect: true`. Choices: `web`, `desktop`, `mobile`. At least one required (re-ask if empty).

**LANG=en:** "Which platforms? (one or more)"
**LANG=ja:** "対応プラットフォームは？（複数選択可）"

Persist `USE_WEB`, `USE_DESKTOP`, `USE_MOBILE` (intermediate; the per-mobile-OS flags come below).

### Decision 4 — Web framework (only when `web` selected)

Single-select with `preview`.

| Choice | Preview |
|--------|---------|
| `Next.js (Recommended)` | `app/`, `app/api/`, RSC, edge or node runtime |
| `TanStack Start` | `routes/`, file-based, fully typed, type-safe loaders |
| `SvelteKit` | `src/routes/`, server hooks, light footprint |

Persist `WEB_KIND=nextjs|tanstack|sveltekit`.

### Decision 5 — Mobile platform split (only when `mobile` selected)

`multiSelect`: `iOS`, `Android`. At least one.

#### Decision 5a — iOS framework (only when iOS chosen)

| Choice | Note |
|--------|------|
| `Swift / SwiftUI (Recommended for iOS-only)` | native, App Store standard |
| `Expo (React Native)` | cross-platform with Android, JS/TS shared |
| `Flutter` | Dart, cross-platform, custom rendering |

Persist `IOS_KIND=swift|expo|flutter`.

#### Decision 5b — Android framework (only when Android chosen)

| Choice | Note |
|--------|------|
| `Kotlin / Compose (Recommended for Android-only)` | native, Play Store standard |
| `Expo (React Native)` | cross-platform with iOS |
| `Flutter` | Dart, cross-platform |

Persist `ANDROID_KIND=kotlin|expo|flutter`.

If both iOS and Android are chosen and select the same cross-platform framework (Expo or Flutter), tell the user they share one codebase. If they pick different cross-platform frameworks, warn and suggest aligning.

### Decision 6 — Desktop framework + OS (only when `desktop` selected)

Framework single-select with `preview`:

| Choice | Preview |
|--------|---------|
| `Tauri (Recommended — small footprint, Rust shell)` | `src-tauri/`, `~10MB binaries` |
| `Electron` | full Node.js, ~120MB binaries, mature ecosystem |

Persist `DESKTOP_KIND=tauri|electron`.

OS multiSelect: `macOS`, `Windows`, `Linux` (default all). Persist `DESKTOP_OS`.

### Decision 7 — Backend framework (only when `ARCHITECTURE in {client-server, p2p-hybrid}`)

Skip when `ARCHITECTURE in {client-serverless, p2p-pure}`.

| Choice | Note |
|--------|------|
| `Hono on Cloudflare Workers (Recommended)` | edge, TypeScript, sub-50ms cold start |
| `Go (Gin)` | mature, fast, large standard library |
| `Rust (Axum)` | typed, performant, steep ramp |

Persist `BACKEND_KIND=hono|gin|rust`.

For `p2p-hybrid`, the backend is a lightweight coordinator/bootstrap server (signaling, peer discovery, optional auth). Tell the user this in the question copy.

### Decision 8 — Database (skip when `persistenceHints == "file"` or `ARCHITECTURE == "p2p-pure"`)

| Choice | Note |
|--------|------|
| `Cloudflare D1 (Recommended for hono/edge)` | SQLite at edge, paired well with Workers |
| `PostgreSQL` | full SQL, JSON, recommended for gin/rust |
| `MySQL` | full SQL alternative |
| `SQLite (local)` | embedded, single-file |

Recommendation flips based on `BACKEND_KIND`:
- `hono` → D1
- `gin` / `rust` → PostgreSQL
- `p2p-hybrid` with light backend → D1 or SQLite
- No backend → SQLite or file

Persist `DB_KIND=d1|postgres|mysql|sqlite|none` (none when skipped).

### Decision 9 — Email (always, single-select)

| Choice | Note |
|--------|------|
| `Resend (Recommended)` | modern API, React Email templates |
| `SendGrid` | enterprise standard |
| `none` | no transactional email |

Persist `USE_EMAIL=yes|no` and `EMAIL_KIND=resend|sendgrid|none`.

### Decision 10 — Authentication (always, single-select; skip if discoverySheet implies)

| Choice | Note |
|--------|------|
| `OAuth (Recommended for consumer apps)` | social sign-in, less password handling |
| `Password (email + password)` | full control, more compliance burden |
| `none` | no auth |

Persist `AUTH_KIND=none|password|oauth`.

### Decision 11 — E2E testing (always, multiSelect)

`multiSelect` choices:

- `Playwright (web/desktop)`
- `Maestro (mobile)`
- `none`

Filter to the user's chosen platforms (don't offer Playwright if no web/desktop, don't offer Maestro if no mobile). Persist `E2E_SCOPE=web|mobile|both|none`, derived `USE_PLAYWRIGHT` / `USE_MAESTRO`.

### Decision 12 — Claude Code Action (always)

Single-select y/n via AskUserQuestion if not implied.

- `Yes — automated PR review (Recommended)`
- `No`

Persist `USE_CLAUDE_ACTION=yes|no`. If yes, follow up with auth method:

- `OAuth (Recommended)`
- `API key`

Persist `CLAUDE_AUTH=api|oauth`.

### After Phase 3

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

The two new keys `PACKAGE_MANAGER` and `ARCHITECTURE` go at the **end** of the file so older readers stay compatible.

When USE_CODEX=yes, register the active session pointer:
```bash
~/my-harness-generator/scripts/codex-ask.sh --set-active <root>
```

`PROJECT_SLUG` derivation (internal, never shown):
```bash
PROJECT_SLUG=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
```

Save phase 1+3 results to `dev/docs/spec/03-decisions.md` and `dev/docs/talk/03-decisions.md`. Update `init-state.json` to `current_phase: "features"`.

If USE_CODEX=yes, run an architect consult:
```bash
~/my-harness-generator/scripts/codex-ask.sh --role architect \
  --out <root>/.my-harness/codex-phase3.md \
  "DiscoverySheet + decisions: <paste config>. Point out design validity, tradeoffs, and any contradictions."
```

---

## Phase 4 — Features (v1 list)

**Question (one per turn):**

- **LANG=en:** "List the features required for v1 — the first release you'd be willing to ship publicly. Don't trim for MVP scope; include everything you'd need before saying 'this is done'. One feature per line. Continue until you have nothing more to add."
- **LANG=ja:** "v1（最初に公開してもいいと思える完成度のリリース）に必要な機能をすべて挙げてください。MVP として削るのではなく、『これで完成』と言える状態に必要な全機能を含めてください。1 行に 1 機能。これ以上書くものが無くなるまで続けてください。"

After the user lists features, **drill at least 2 follow-ups per feature**:

1. **Access path:** "How does the user reach this feature? (route, button, gesture)"
   - **LANG=ja:** "どこからこの機能にたどり着きますか？（URL・ボタン・ジェスチャー）"
2. **Failure modes:** "What goes wrong, and what does the user see when it does?"
   - **LANG=ja:** "失敗するパターンは？そのときユーザーには何が見えますか？"
3. **Observability:** "Do we need analytics or alerting on this feature? If yes, which event/metric?"
   - **LANG=ja:** "分析やアラートは必要ですか？必要なら、どのイベント・指標？"

Save to: `dev/docs/spec/04-features.md` / `dev/docs/talk/04-features.md`.

Each feature listed becomes one or more issues / task files at /harness-team-lead time. The list is the source of truth for what v1 means.

If USE_CODEX=yes:
```bash
~/my-harness-generator/scripts/codex-ask.sh --role analyst \
  --out <root>/.my-harness/codex-phase4.md \
  "v1 feature list with access paths, failure modes, observability requirements: <paste>. Point out gaps."
```

Update `init-state.json` to `current_phase: "data-model"` (or `"visual"` if `USE_DB=no` AND `ARCHITECTURE=p2p-pure`).

---

## Phase 5 — Data model (only when `USE_DB=yes` OR persistence is non-trivial)

Skip entirely when `DB_KIND=none` AND `persistenceHints=file`. Otherwise:

**Questions (one per turn — use the variant matching `LANG`):**

1. **LANG=en:** "List 3–7 entities for your data model." (e.g. User / Task / Comment)
   **LANG=ja:** "データモデルのエンティティを 3〜7 個リストアップしてください。"
2. **LANG=en:** "Bullet out the main fields for each entity."
   **LANG=ja:** "各エンティティの主なフィールドを箇条書きで教えてください。"
3. **LANG=en:** "Describe relationships in mermaid ER style." (e.g. User 1—N Task)
   **LANG=ja:** "エンティティ間のリレーションシップを mermaid ER スタイルで説明してください。"
4. **LANG=en:** "Which fields contain PII?" (email, phone, address, etc.)
   **LANG=ja:** "個人情報（PII）を含むフィールドはどれですか？"

After the initial sketch, Claude assembles a **draft mermaid ER diagram** and shows it back, asking:
- **LANG=en:** "Here's the ER diagram I drew from your sketch. Anything to edit?"
- **LANG=ja:** "ご提示内容から ER 図を起こしました。修正点はありますか？"

**Drill at least 1 round per entity** on:
- **Lifecycle:** when does it get created / updated / deleted? (en/ja)
- **Access patterns:** which queries hit it most often?
- **Retention:** is the data kept forever, archived, or deleted on a schedule?

Save the final mermaid + answers to `dev/docs/spec/05-data-model.md`.

If USE_CODEX=yes, run an architect normalization check.

Update `init-state.json` to `current_phase: "visual"`.

---

## Phase 6 — Visual (logo + key screen UI mocks)

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

2. **LANG=en:** "List 3–5 screens you want mocked." (e.g. Login / Home / Detail / Settings)
   **LANG=ja:** "UI モックを作成したい画面を 3〜5 個リストアップしてください。"

### Logo generation (when USE_CODEX=yes)

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

After generation, immediately open all 3 (macOS):
```bash
open <root>/dev/docs/design/logo-1.png \
     <root>/dev/docs/design/logo-2.png \
     <root>/dev/docs/design/logo-3.png
```

**File format verification:**
```bash
file <root>/dev/docs/design/logo-{1,2,3}.png | grep -v "PNG image"
```
If anything other than PNG appears, ask Codex to regenerate.

User selects one → copy to `<root>/dev/docs/design/logo-final.png` (real copy, not symlink).

### Interactive refinement

When user says "**make concept 1 bluer**", **resume the same session and call codex-ask.sh again**:

```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh \
  --role designer \
  --out <root>/.my-harness/codex-logo-r1.md \
  "Make concept 1 a bit more blue and simpler. Regenerate and overwrite the same path."
```

Key points:
- **Never add `--reset-session`** (destroys context)
- **Never re-attach `--context`** with the spec (it's already in session)
- Repeat N times to iteratively refine. Once approved, copy to `logo-final.png`.

### UI mock generation (per screen)

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

Read the spec and the chosen logo, then design using your own judgment. Use Lucide Icons-style icons; no AI-style gradients.

Specs:
- Format: PNG
- Resolution: <1280x800 for Web/Desktop; 375x812 for mobile>
- Call image_gen separately for each concept (2 calls total)

Save to:
- <root>/dev/docs/design/mock-<screen>-1.png
- <root>/dev/docs/design/mock-<screen>-2.png"
```

Open both, run the same `file` PNG verification, user picks one. OG image / favicon follow the same approach (all PNG).

### Iteration

If mocks reveal that requirements have changed, go back to phases 2–5 to update spec, return here, regenerate only affected mocks. **Maximum 3 iteration cycles.**

When USE_CODEX=no, skip mock generation and record visual direction (primary color, impression, layout) as text in `dev/docs/design/brand.md`.

### Completion criteria

- [ ] One logo concept finalized
- [ ] Mocks selected for 3–5 key screens (USE_CODEX=yes only)
- [ ] OG image / favicon generated
- [ ] If spec changed during iteration, `docs/spec/*.md` is up to date

Save to: `dev/docs/spec/06-visual.md` / `dev/docs/design/{logo-*,mock-*,og,favicon}.png`.

---

## Phase 7 — Spec finalization + bootstrap + issue/task generation

### 7.1 Final spec review

Read all of `dev/docs/spec/0[1-6]-*.md` and present a summary to the user for approval.

If USE_CODEX=yes, run final cross-check with Codex code-reviewer:
```bash
${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/codex-ask.sh --role code-reviewer \
  --context <root>/dev/docs/spec/*.md <root>/dev/docs/design/*.png -- \
  "Point out inconsistencies between the spec / mocks / tech stack, logical contradictions, and missing functionality."
```

If there are corrections, go back to phases 2–6 then return.

### 7.2 Bootstrap execution (non-interactive)

```bash
bash ${CLAUDE_PLUGIN_ROOT:-$HOME/my-harness-generator}/scripts/bootstrap.sh "<root>" --config "<root>/.my-harness/.config"
```

bootstrap reads `PACKAGE_MANAGER` and `ARCHITECTURE` from `.my-harness/.config` and:
- Uses the chosen package manager (pnpm/bun/npm/yarn) for all install / exec / run lines in generated `flake.nix`, husky setup, CI workflows, and the printed next-steps banner.
- For `ARCHITECTURE=p2p-pure`, **skips** backend bootstrap entirely.
- For `ARCHITECTURE=p2p-hybrid`, writes a minimal **coordinator/bootstrap server** stub.
- For p2p modes, drops a starter at `dev/p2p/README.md` noting that the P2P transport library will be selected at `/harness-team-lead` time based on chosen platforms.

### 7.3 Issue / task generation

Split the v1 feature list from Phase 4 into **child issues of at most 300 lines each**, declaring file ownership to prevent conflicts.

- **USE_GITHUB_ISSUES=yes**: Create parent + child issues with `gh issue create` (with 4-lane assignments).
- **USE_GITHUB_ISSUES=no**:
  ```
  <root>/dev/docs/task/parent/0001-<slug>.md
  <root>/dev/docs/task/child/0001-<feature>.md
  ```
  Each file uses front matter to express `parent: 0001` / `lane: 1–4` / `status: pending`.

### 7.4 Clear active session pointer (if USE_CODEX=yes)

```bash
~/my-harness-generator/scripts/codex-ask.sh --clear-active
```

### 7.5 Generate dev/README.md and dev/CLAUDE.md for the first time

Read `dev/docs/spec/*.md` and `.my-harness/.config`, then Claude **manually creates** the following 2 files (reflecting spec content). Use `$PACKAGE_MANAGER` for the install / exec lines.

#### `<root>/dev/README.md` (template)

```markdown
# <PROJECT_NAME>

<1–2 line summary from spec/02-discovery.md>

## Features

<v1 feature list from spec/04-features.md as bullet checkboxes [ ] / [x]>

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
- `/harness-new-feature <issue#>` — start a specific issue
- Re-run `/my-harness-init` — resume from where you left off

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

<Copy mermaid ER diagram from spec/05-data-model.md (only when DB used)>

## Key screens / API

<Key screen list from spec/06-visual.md and expected API endpoints>

## Conventions

The harness auto-firing skills enforce:
- harness-tdd
- harness-hono-clean-arch
- harness-drizzle-rules (migrate-only)
- harness-nix-pure
- harness-design-rules (Lucide Icons only, no AI-style design)
- harness-jsdoc
- harness-git-discipline
- harness-no-hardcoded-secrets

## Agent responsibilities (4-lane parallel implementation)

- team-lead: issue assignment (avoiding file conflicts), progress aggregation, user approval relay
- analyst: in-lane orchestration, git add / commit / push / gh pr create
- engineer: implementation only (no git ops; updates README/CLAUDE.md alongside code)
- e2e-reviewer: runs Playwright/Maestro
- reviewer: convention + docs consistency review

## Key files

<Empty — engineers append to this whenever a feature is implemented>

## Current feature status

<Initialize the v1 feature list from spec/04-features.md with `pending`; flip to `done` as issues complete>
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

### 7.6 Update init-state.json + stop + guide user to dev

```bash
ROOT=<root>
ISSUE_COUNT=<number of child issues generated>
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$ROOT/.my-harness/init-state.json" <<EOF
{
  "schema_version": "2",
  "project_name": "<PROJECT_NAME>",
  "lang": "${LANG:-en}",
  "root": "$ROOT",
  "current_phase": "completed",
  "phases_completed": ["language", "setup", "discovery", "disambiguation", "features", "data-model", "visual", "bootstrap", "tasks"],
  "next_action": "implementation",
  "next_action_command": "/harness-team-lead (or /harness-new-feature <issue#>)",
  "working_directory": "$ROOT/dev",
  "issue_count": $ISSUE_COUNT,
  "lanes_assigned": true,
  "timestamp": "$TIMESTAMP"
}
EOF
```

Then **present the following message and stop automatically** (do not proceed). Use `$PACKAGE_MANAGER` in the placeholders.

```
/my-harness-init complete

Spec:    <root>/dev/docs/spec/
Mocks:   <root>/dev/docs/design/
Tasks:   <root>/dev/docs/task/  or GitHub Issues
State:   <root>/.my-harness/init-state.json (current_phase=completed)

From here, work happens in the dev worktree:

1) In your terminal:
     cd <root>/dev
     direnv allow
     <PACKAGE_MANAGER> install
     <PACKAGE_MANAGER> exec husky    # or: bun husky / npm exec husky / yarn husky

2) Push to GitHub when ready:
     git remote add origin git@github.com:<owner>/<repo>.git
     git push --all origin
     bash .my-harness/scripts/setup-branch-protection.sh <owner>/<repo>
     bash .my-harness/scripts/setup-secrets.sh <owner>/<repo>

3) End this session, run `cd <root>/dev` in your terminal,
   then restart Claude Code. In the new session, run one of:

     /harness-team-lead               # Drive all issues in parallel across 4 lanes
     /harness-new-feature <issue#>    # Start a specific feature
     /my-harness-init                 # Resume from where you left off
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

- `codex` not installed → auto-set USE_CODEX=no, continue with Claude alone
- `codex login` not run → guide user; after 3 failures fall back to no
- `bootstrap.sh` fails → display stderr, let user decide
- File conflict → ask user to continue / abort / specify a different directory

## Artifact layout summary

```
<root>/
├── .my-harness/                       Internal work files (gitignored)
│   ├── .config                          Selections (incl. PACKAGE_MANAGER, ARCHITECTURE)
│   ├── init-state.json                  Phase + discoverySheet
│   ├── codex-sessions/<KEY>.id          (gitignored)
│   ├── codex-phase*.md                  (gitignored)
│   └── codex.jsonl                      (gitignored)
├── dev/                                 Standard structure created by bootstrap
│   ├── docs/
│   │   ├── spec/02-discovery.md ...     Masked requirements
│   │   ├── design/logo-*.png ...        Generated images
│   │   ├── talk/02-discovery.md ...     Masked Q&A
│   │   └── task/                        When USE_GITHUB_ISSUES=no
│   │       ├── parent/0001-*.md
│   │       └── child/0001-*.md
│   └── p2p/README.md                    Only when ARCHITECTURE in p2p-pure|p2p-hybrid
├── stage/  main/  lanes/                Standard worktrees
└── .bare/                               Bare git repo
```

## How to conduct the conversation (Claude's behavior, summary)

- **Phase 2 is a real conversation, not a checklist.** Open questions, drill, summarize, repeat. 10–30 turns is normal.
- **Phase 3 only fires AskUserQuestion for decisions the discoverySheet has not already settled.** Skip with explicit notice when implied.
- **One question per turn.** Always.
- **Mask before persisting.** Always.
- **Never improvise abstract questions** (brand world-view, 5-year vision, tone).
- **Drill check after every reply.** "Have I gone at least one level deeper than the surface answer?"
- **If the user says 'stop'**, save state and halt.
