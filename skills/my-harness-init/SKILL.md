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

From this point, all conversation, all generated docs, JSDoc text, error messages, and issue templates use the chosen language.

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

Confirm each of the following **one question at a time**:

1. Project root directory (default: `~/<project-name>`)
2. Project name (slug: lowercase letters + hyphens)
3. Use Codex integration? (y / n)
   - y: Codex consulted at the end of each phase; image generation during the visual phase
   - n: Claude proceeds alone
4. If y: Verify Codex login status:
   ```bash
   bash ~/my-harness-generator/scripts/check-codex-auth.sh
   ```
   - `not-installed` → Guide user to `npm i -g @openai/codex`; re-ask the question
   - `not-logged-in` → Ask user to run `codex login`. After 3 failures, automatically set to n
   - `logged-in` → Continue
5. If y: Session name (default: `my-harness-init`)
6. **If y: Which subagents should be delegated to Codex?** (one question per turn, default is all y)
   - **Delegate engineer (implementation) to Codex?** y/n (default: y — Codex is strong at code generation)
   - **Delegate e2e-reviewer to Codex?** y/n (default: y — Codex can run tests from the CLI)
   - **Delegate reviewer (convention review) to Codex?** y/n (default: y — Codex is strong at code review)
7. Task management: GitHub Issues or local `docs/task/`
8. Inherit global `~/.claude/CLAUDE.md`? y/n

When USE_CODEX=no, all three options in step 6 are automatically set to `no` (master switch takes precedence).

Save the answers:

```bash
mkdir -p <root>/.my-harness <root>/dev/docs/spec <root>/dev/docs/design <root>/dev/docs/talk <root>/dev/docs/task

cat > <root>/.my-harness/.config <<EOF
LANG=<en|ja>
PROJECT_NAME=<slug>
ROOT=<root>
USE_CODEX=<yes|no>
CODEX_SESSION=<session>            # Only when USE_CODEX=yes
USE_CODEX_ENGINEER=<yes|no>        # Only meaningful when USE_CODEX=yes; if no, Claude implements
USE_CODEX_E2E_REVIEWER=<yes|no>    # Only meaningful when USE_CODEX=yes; if no, Claude runs E2E
USE_CODEX_REVIEWER=<yes|no>        # Only meaningful when USE_CODEX=yes; if no, Claude does review
ON_CODEX_AUTH_FAIL=pause           # Default pause: notify user and wait on auth/subscription failure; fail = immediate error
USE_GITHUB_ISSUES=<yes|no>
USE_GLOBAL_CLAUDE=<yes|no>
EOF
```

When USE_CODEX=yes, register the active session pointer:
```bash
~/my-harness-generator/scripts/codex-ask.sh --set-active <root>
```

---

### Phase 1: What to build

**Fixed questions (one per turn — never improvise)**:

1. **"In one sentence, what are you building?"** (e.g. task management app / inventory SaaS / blog site / internal tool)
2. **"List 3–7 features required for the MVP"** (numbered)

That's it. Do **not** ask "who uses it / personas / why existing services don't work / what success looks like in 5 years". Who uses it will surface naturally in Phase 3 (authentication) and Phase 5 (visual impression) as concrete choices — asking abstractly adds no value.

Save to: `dev/docs/spec/01-what.md` / `dev/docs/talk/01-what.md`

If USE_CODEX=yes, run a Codex consult at the end:
```bash
~/my-harness-generator/scripts/codex-ask.sh --role analyst \
  --out <root>/.my-harness/codex-phase1.md \
  "Project summary: <one sentence>. MVP feature list: <enumerated>. Point out any logical contradictions, ambiguities, or missing items."
```

---

### Phase 2: Platform + framework

**Ask in two steps per target**: first y/n, then the framework choice if y. **Strictly one question per turn — no batch questions.**

#### 2.1 Web

1. **Build a web frontend?** y/n
2. If y: **Which framework?** (choices: `nextjs` / `tanstack`)
   - `nextjs`: Next.js 16 (App Router)
   - `tanstack`: TanStack Start (SSR + TanStack Router)

#### 2.2 iOS

1. **Build an iOS app?** y/n
2. If y: **Which implementation?** (choices: `swift` / `expo` / `flutter`)
   - `swift`: Swift + SwiftUI native
   - `expo`: React Native (Expo)
   - `flutter`: Flutter

#### 2.3 Android

1. **Build an Android app?** y/n
2. If y: **Which implementation?** (choices: `kotlin` / `expo` / `flutter`)
   - `kotlin`: Kotlin + Jetpack Compose native
   - `expo`: React Native (Expo)
   - `flutter`: Flutter

#### 2.4 Desktop

1. **Build a desktop app?** y/n
2. If y: **Which framework?** (choices: `tauri` / `electron`)
   - `tauri`: Rust shell + web frontend, lightweight
   - `electron`: Node.js shell + web frontend, rich ecosystem
3. If y: **Which OS targets?** (macOS / Windows / Linux, multiple selections allowed, default: all)

#### Validation

- At least one platform must be y (re-ask if all are n)
- If both iOS and Android are y and both choose `expo` or both choose `flutter` → **inform the user they share a single codebase** (one directory under `mobile/`)
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

**Fixed questions (one per turn)**:

1. **Build a backend?** y/n (frontend-only or serverless-only projects can answer no)
2. If y: **Which language/framework?** (choices: `hono` / `gin` / `rust`)
   - `hono`: TypeScript + Hono on Cloudflare Workers (lightweight, edge)
   - `gin`: Go + Gin (high performance, conventional)
   - `rust`: Rust + axum (type-safe, maximum speed)
3. **Need a database?** y/n
4. If y: **Which DB?** (choices: `d1` / `postgres` / `mysql` / `sqlite`)
   - Recommendation: `d1` for `hono` backends; `postgres` for `gin` / `rust` backends
5. **Need email sending?** y/n (y → Resend, for password reset, etc.)
6. **How much authentication do you need?** (choices: `none` / `password` / `oauth`)
7. **How much E2E testing?** (choices: `web` / `mobile` / `both` / `none`)
   - `web` → Playwright, `mobile` → Maestro, `both` → both, `none` → none
8. **Use Claude Code Action in CI?** y/n (automated PR review)
9. If y: **Authentication method** (`api` / `oauth`)

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

**Fixed questions**:

1. **List 3–7 entities** (e.g. User / Task / Comment)
2. **Bullet out the main fields for each entity**
3. **Describe relationships between entities in mermaid ER style** (e.g. User 1—N Task)
4. **Which fields contain PII?** (email, phone, address, etc.)

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

**Fixed questions** (one per turn, minimal):

1. **Any color hint?** (optional, e.g. `#14b8a6` / "blue tones" / "no preference")
2. **List 3–5 screens you want mocked** (e.g. Login / Home / Detail / Settings)

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

<MVP feature list from spec/01-what.md as bullet points, each with `[ ] not implemented / [x] done` checkbox>

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

<Initialize the MVP feature list from spec/01-what.md with `pending`; update to `done` as issues complete>
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
