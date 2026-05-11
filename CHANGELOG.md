# Changelog

All notable changes documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [7.3.1] — 2026-05-12

### Fixed

- **Phase-5 Turn 1 hanging forever when the project root is not in
  Codex's trusted-projects list.** Codex CLI has two independent
  approval layers — L2 (per-action: shell exec / file edit), which
  our `codex-app-server-call.py` already sets to `"never"`, and L1
  (project trust, configured in `~/.codex/config.toml`). L1 is NOT
  bypassed by `approval_policy="never"`. A `codex app-server` daemon
  running on behalf of an untrusted project raises an L1 trust prompt
  that has nowhere to be answered (the daemon has no UI), so every
  `thread/start` hangs until inactivity timeout. No image_gen call
  fires, no file lands, the bridge appears to "succeed" but the page
  PNG never exists.

### Added

- **`scripts/ensure-codex-project-trust.sh`** — appends
  `[projects."<ROOT>"]` with `trust_level = "trusted"` to
  `~/.codex/config.toml` (idempotent — no-op when already trusted).
  Uses Python's stdlib `tomllib` for parsing with a tolerant text-scan
  fallback. Preserves existing config (append-only, never rewrites
  other sections). Schema matches the official Codex
  [config reference](https://developers.openai.com/codex/config-reference).
- **Phase 1 Setup Q5 split into Q5.a + Q5.b** (in `SKILL.md`):
    - Q5.a — `ensure-codex-project-trust.sh "$ROOT"` (always before daemon)
    - Q5.b — `ensure-codex-daemon.sh "$ROOT"` (unchanged)
  Order matters: the daemon reads `config.toml` at start time, so
  trust must be in place first.

---

## [7.3.0] — 2026-05-11

Phase 5 redesigned around (a) edit-mode chaining for the image-generation
pipeline — the page and the parts grid now SHARE the same visual style
because the grid is generated using the page as an `image_gen` edit-mode
reference, not from scratch — and (b) moving HTML authorship from Codex
to Claude, since Claude already has multimodal vision and writing the
HTML round-trip through another agent saves nothing.

### Changed

- **`image_gen` calls are now chained via edit mode (the official
  consistency primitive).** Previously, `gen-page-parts.sh` packaged
  page-mock + parts-grid generation into one prompt and Codex called
  `image_gen` independently per artifact. Because `image_gen` is
  stateless across calls, the two artifacts drifted visually (different
  palette saturation, different illustration style, different character
  proportions) — even when the prompt said "match the page". The new
  pipeline splits the work into two turn types:
    - **Turn 1** — `image_gen generate` produces `page-<>.png` and
      writes a JSON `style_guide` (palette hex codes, illustration
      style phrase, line weight, character design, decorative motifs)
      to its text response. The style_guide is Codex's own declared
      design language, captured verbatim.
    - **Turn 2..N** — `image_gen edit` against the page image (still
      in the session's conversation context, per Codex's official
      `$imagegen` skill docs). The prompt for each grid echoes the
      style_guide as IMMUTABLE INVARIANTS and lists the cells to
      render. Edit mode + invariant echo + same-session = page and
      grids share style.
  Reference: `codex-rs/skills/src/assets/samples/imagegen/SKILL.md`
  ("Built-in edit mode is for images already visible in the
  conversation context, such as attached images or images generated
  earlier in the thread."). Also reference Issue #19136 — `image_gen`
  takes only a `prompt` argument, but session-context image references
  via edit mode work without explicit argument passing.
- **`gen-page-parts.sh` rewritten** as a two-phase pipeline (Turn 1:
  page + manifest; Turn 2..N: edit-mode grids) on the same
  `design-image-<project-slug>` session. Each grid turn retries up to
  3× if the PNG didn't land. Existing `crop-parts.sh` /
  `scaffold-tsx-from-parts.sh` / `upscale-part.sh` are unchanged — they
  already operate on the manifest format which now just carries the
  extra `style_guide` field that they ignore.
- **HTML generation moves from Codex to Claude.** `gen-page-html.sh`
  is removed. The new Phase 5 procedure has Claude `Read` the page
  mock PNG (multimodal vision), `Read` the manifest, then `Write` the
  Tailwind HTML file directly. Saves a Codex session, ~30-60 seconds
  per screen, and a few thousand tokens — and Claude's output is
  easier to control because there is no extra agent boundary.
- **`refine-design.sh` simplified to image-only.** The `<kind>`
  argument is removed; the script always resumes the image session.
  HTML refinements are done by Claude with the `Edit` tool directly,
  no Codex session needed. If a refinement to the page mock affects
  the parts grid, the prompt asks Codex to regenerate the grid in edit
  mode against the new page (style invariants preserved).

### Added

- **`prompts/codex-page-mock.md`** — Turn 1 prompt template. Codex
  generates the page mock and emits the style_guide manifest.
- **`prompts/codex-parts-grid-edit.md`** — Turn 2+ prompt template
  with `<STYLE_GUIDE_JSON>` and `<CELLS_JSON>` placeholders. Echoes
  the style_guide back as immutable invariants on every grid call.

### Removed

- **`scripts/gen-page-html.sh`** — replaced by Claude's direct
  `Read → Write` flow.
- **`prompts/codex-page-and-parts.md`** — replaced by the two-turn
  templates above.
- **`prompts/codex-page-to-html.md`** — no longer needed (Claude
  doesn't need a prompt for itself).

### Migration

For projects mid-Phase-5 with the old pipeline, the existing
`page-<>.png` and `parts-grid-<>-0.png` files remain valid. Regenerate
only if you want the new edit-mode style consistency between page and
grid — running `gen-page-parts.sh` again on the same screen overwrites
both artifacts using the new two-turn flow. The on-disk `manifest.json`
gets the new `style_guide` field, which downstream scripts ignore if
absent.

---

## [7.2.2] — 2026-05-11

### Fixed

- **Magenta residue at asset edges after cropping.** With `fuzz=10%` and
  no morphology, anti-aliased magenta→asset boundary pixels (which the
  image generator emits as pink / light-purple / dusty-rose blends) were
  too far from pure magenta in RGB-distance terms to be caught by
  `-transparent`, so a 1-2 pixel residue remained around every asset.
  Raised default fuzz to `30%` and added a 1-pixel alpha erosion
  (`-morphology Erode Octagon:1`) so the asset boundary is pulled in
  just enough to nibble the residue away. Empirically: alpha mean
  dropped from "noisy halo" to "clean transparent edge" on synthetic
  test cells. Override via `CHROMA_FUZZ` / `CHROMA_ERODE` env vars.

### Added

- **Chroma-key color is now configurable per project.** Set
  `HARNESS_CHROMA_KEY` when running `gen-page-parts.sh` to pick a
  different background color (e.g. `#00FF00` lime green) when the
  design legitimately uses magenta-family colors. The value is
  persisted to `.my-harness/chroma-key.txt` so subsequent `crop-parts.sh`
  invocations read the same key without re-passing the env var.
  Resolution order: explicit `CHROMA_KEY` env > `HARNESS_CHROMA_KEY` env
  > saved file > default (`#FF00FF`).

### Changed

- **Prompt now demands pixel-perfect aliased background↔asset boundary.**
  Codex was producing a soft anti-aliased boundary by default, which is
  the root cause of the magenta-residue bug above. The prompt now
  explicitly says: "Every pixel is EITHER exactly `<CHROMA_KEY>`
  background OR a definite asset color. There must NEVER be any
  in-between pixel along the boundary. Imagine rendering with
  `image-rendering: pixelated`." Combined with the cropper-side
  improvements, residue is reduced further when Codex obeys.
- **Prompt uses `<CHROMA_KEY>` placeholder** (was hardcoded `#FF00FF`).
  Allows the same prompt template to work with any chroma key.

---

## [7.2.1] — 2026-05-11

### Fixed

- **Image-only Codex turns: real fix.** The 7.2.0 attempt at this bug
  was based on a wrong assumption. `codex-app-server-call.py` was reading
  `ChatResult.raw_events` from the `chat_once()` return value — but the
  SDK's `chat_once()` raises `CodexProtocolError("turn completed but no
  final assistant message could be resolved")` *unconditionally* when
  `final_text` is empty, before returning. The result object never
  reaches our code, so the post-result image-detection added in 7.2.0
  never ran.

  Confirmed from `codex_app_server_sdk/client.py` lines 1183-1190
  (final_text empty → raise) and lines 1204-1310 (streaming `chat()`
  returns cleanly on `session.completed` regardless of text content).

  Real fix: switch from `chat_once()` to the streaming `chat()` API
  (`AsyncIterator[ConversationStep]`). Each ConversationStep is captured
  as it arrives via `model_dump(mode="json")`. We aggregate
  `item_type == "agentMessage"` text ourselves and scan the full step
  list for image-generation hints. The SDK no longer raises on empty
  text because streaming completion is decoupled from text presence.

  End-to-end verified: constructed a real ConversationStep with
  `item_type="image_generation_call"` and `data.saved_path="/tmp/test.png"`;
  `_extract_image_paths` recovers the path correctly.

---

## [7.2.0] — 2026-05-11

Phase 5 redesigned around an HTML deliverable + shared project-wide Codex
sessions, plus three serious bridge-layer bugs that were silently
deleting Phase-5 work, plus a SKILL.md refactor that extracted ~80 lines
of inline bash into reviewable / lint-able scripts.

### Added

- **Phase 5 ends with a self-contained Tailwind HTML file per screen.**
  `scripts/gen-page-html.sh` converts the approved page-mock PNG into a
  self-contained HTML document (Tailwind Play CDN, Google Fonts, parts
  referenced via relative `<img>` paths). Opens directly in a browser
  via `file://` — no React build needed. Implementation-phase Codex
  later converts the HTML to TSX. Prompt template at
  `prompts/codex-page-to-html.md`.
- **Per-platform mock orchestrator.** `scripts/gen-page-cross-platform.sh`
  generates the same screen's mock on multiple platforms (web + ios +
  android …) in series with independent sessions per platform, then
  opens every result PNG (page + grids) simultaneously so users can
  compare side by side.
- **Auto-open hooks in image / crop scripts.** `gen-page-parts.sh` opens
  the page PNG and every grid PNG on completion; `crop-parts.sh` opens
  every cropped part PNG. OS-aware helper `scripts/lib/open-file.sh`
  (`open` / `xdg-open` / `start`). Suppress with `HARNESS_SKIP_OPEN=1`.
- **Multi-page parts grid.** When a screen has > 28 non-HTML assets,
  Codex paginates into `parts-grid-<platform>-<screen>-0.png`, `-1.png`, …
  `gen-page-parts.sh` retries with per-image-specific nudges if any
  declared grid PNG is missing.
- **Project-wide Codex sessions.** Sessions moved from screen-scoped
  (`design-page-<platform>-<screen-slug>`) to project-scoped
  (`design-image-<project-slug>` for image generation,
  `design-html-<project-slug>` for HTML conversion). One thread per
  project per task — palette / typography / icon language / brand voice /
  button rounding all propagate from screen 1 to every later screen.
  Refinement prompts must name the target screen explicitly since the
  session now contains multiple screens.
- **Auto-start of the shared `codex app-server` daemon at Phase 1.**
  `scripts/ensure-codex-daemon.sh` runs at the end of Phase 1 when
  `USE_CODEX=yes`: branches on `status` exit code (0 = healthy/no-op,
  1 = start, 2 = restart). Eliminates per-call cold-start overhead for
  every later Codex invocation in the session.
- **Bridge image-event awareness.** `codex-app-server-call.py` now
  scans `ChatResult.raw_events` for `image_generation_call` /
  `imageGeneration` / `image_gen` hints and accepts an empty
  `final_text` as success when image paths are detected. Logs each
  detected path to stderr. Detection is protocol-version-agnostic.
- **`--context` binary-aware embedding.** `codex-ask.sh` runs
  `file --mime-type` per context file: text/JSON/script files are
  embedded as before; PNGs/JPEGs/PDFs are referenced by absolute path
  only with an instruction for Codex to open them via its file-read /
  image-input tool. Stops UTF-8 corruption that was breaking every
  Phase-5 `--context "$PAGE_PNG"` call.

### Changed

- **Background-removal switched from white flood-fill to chroma-key on
  pure magenta (`#FF00FF`).** Old approach: 4-corner flood-fill on white
  background — anti-aliased cloud edges blended into the background and
  the flood-fill walked into the cloud interior, destroying white pixels
  that should have been preserved. New approach: Codex paints the grid
  background pure magenta (a color no real design uses) and labels in
  black; `crop-parts.sh` removes pixels near `#FF00FF` with 10 % fuzz
  tolerance. White pixels inside assets (clouds, paper, snow, white
  speech bubbles, white logos) are preserved as opaque white in the
  cropped PNG. Override via `CHROMA_KEY` / `CHROMA_FUZZ` env vars.
- **SKILL.md inline-bash refactor.** Eight bash heredocs / multi-line
  ceremony blocks extracted out of `skills/my-harness-init/SKILL.md`:
  - Logic → callable scripts: `find-existing-state.sh`,
    `ensure-codex-daemon.sh`, `refine-design.sh image|html`,
    `commit-initial-docs.sh`.
  - File-emission heredocs → `Write`-tool JSON / ini templates with
    `<...>` placeholders (init-state.json at Phase 3 boundary, `.config`
    at end of Phase 6, init-state.json at completion).
  Bash blocks in SKILL.md: 26 → 22; every remaining block is a
  single-line `bash scripts/<name>.sh …` call. Script-syntax errors now
  surface at lint time, not at skill runtime.

### Fixed

- **Image-only Codex turns no longer drop the generated PNG.** Before,
  `codex-app-server-call.py` saw `final_text=""` (Codex returned only
  `image_generation_call`, no follow-up `agent_message`) and exited 1,
  so the shell layer reported failure and downstream callers retried
  pointlessly. Now treated as success when image events are detected.
- **PNG attached via `--context` no longer corrupts the JSON-RPC
  payload.** `codex-ask.sh` previously `cat`'d binary file bytes into a
  UTF-8 prompt — PNG magic bytes are not valid UTF-8 and the
  SDK/transport rejected the prompt. Now binary files are referenced by
  absolute path only.
- **Shell layer no longer overrides helper-success as failure.**
  `codex-ask.sh` exited non-zero whenever `ASSISTANT_TEXT` was empty,
  even when the python helper reported `CODEX_EXIT=0`. Now empty body +
  helper-success is treated as a legitimate image-only turn (warning
  logged, downstream verifies the PNG on disk itself).

### Migration

No user action required. New projects automatically use the new
project-wide sessions and chroma-key cropping. Existing in-progress
sessions: if you regenerate any screen on an existing run after this
upgrade, the bridge bug fixes apply immediately. Previously-cropped
parts on white backgrounds need re-generation only if you want the
white-pixel-preservation benefit; on-disk PNGs remain valid as-is.

---

## [7.1.0] — 2026-05-11

A bundle of interview behavior, communication, design pipeline, and
reliability changes — driven by direct user feedback during a real
`/my-harness-init` blog-app run.

### Added — honesty rules (mandatory across all agents)

`rules/honesty.md` defines 7 rules: say "I don't understand" out loud
via `status=blocked-needs-clarification`; don't claim success without
reading actual output; no vague jargon ("looks consistent" / "should
work"); bad news first with concrete counts; never `status=pass` when
any check failed; concrete next actions only ("Reading log at
<path>"), never "investigating"; don't manipulate the user with
intentional confusion.

Applied as a 5-6-line restatement, calibrated per role, to:
- `agents/harness-analyst.md`
- `agents/harness-engineer.md`
- `agents/harness-reviewer.md`
- `agents/harness-e2e-reviewer.md`
- `skills/harness-team-lead/SKILL.md`

### Added — canonical communication rules

`rules/communication.md` collects the 5 user-facing message rules:
- One topic per message (no stacking analysis + decision + question).
- Plain language, no harness-invented compounds.
- Codex second-opinion is opt-in per occurrence.
- Don't leak internal terminology (`discoverySheet`, enum values,
  status codes, config keys, code notation).
- Idea suggestion is allowed and encouraged — never required.

Referenced from every user-facing skill (`my-harness-init`,
`harness-team-lead`, `my-harness-adopt`).

### Added — proactive idea suggestion (Phase 2 Rule 11)

When the user describes the product, the harness suggests 2-4
features that adjacent products in the same category typically have
and that the user did not mention. Always additive, never
subtractive. "Skip if not interesting" appended. Words "MVP" / "core"
/ "essential" / "must-have" forbidden. Bilingual examples
(blog domain) provided.

### Changed — Phase 5 (Visual) redesigned around page + parts mocks

The logo generation step is **removed entirely**. Per-screen flow:

1. One Codex call produces ONE high-quality (2048 × 2880) PNG with two
   sections: full page mock (top 65 %) and a 4-column grid of every
   distinct UI component used (bottom 35 %, white background, labels).
2. Claude reads the bottom grid via Vision, produces a manifest.json.
3. `scripts/crop-parts.sh` slices each cell deterministically and
   removes the white background by 4-corner flood-fill, leaving
   transparent PNGs.
4. Output lands at `dev/public/design/parts/<platform>/<screen-slug>/<name>.png`
   so the running app can reach `/design/parts/...` directly.
5. `dev/src/components/design/<platform>/<screen-slug>/parts.ts` is
   auto-generated as a typed const object mapping each camelCased
   part name to its public URL.
6. Claude writes one TSX component per part — Tailwind code for
   recreatable elements, `<img src={parts.X} />` for decorative
   graphics that can't cleanly be recreated in code.

### Added — reliability for Codex image generation

`scripts/gen-page-parts.sh` now:
- Pins a deterministic `--session` key per (platform, screen-slug),
  persisted at `$ROOT/.my-harness/codex-session-design-<...>.txt`.
- Verifies the PNG actually exists AND is a valid PNG after each call.
- On failure, follows up in the same Codex session with an explicit
  nudge ("you replied with text but did not save the image — call
  image_gen now and save to <path>"), up to 3 retries
  (`HARNESS_GEN_RETRY` overridable).
- Exits non-zero only when retries exhaust; the session is preserved
  so the user can resume manually.

`crop-parts.sh` bug fix: the false-positive `-list option | grep fuzz`
detection was silently zeroing `FUZZ_OPT` on every install (because
`-list option` does not enumerate `-fuzz`), so flood-fill was running
without tolerance. `-fuzz 5%` is now unconditional.

### Added — explicit USE_CODEX=no path

The no-Codex path was a one-line afterthought ("skip image generation,
draft a text mock"). Now it is a fully specified branch:

- Each screen gets a structured `text-mock-<platform>-<screen-slug>.md`
  with Layout / Visible elements / Parts list / Interactions sections.
- TSX component stubs are still generated, one per "Parts list" entry,
  with state-variant props and `rules/design.md`-compliant Tailwind.
- No PNG and no `parts.ts` on this path; `visualMocks[].path` points
  to the markdown file.
- Switching the project to `USE_CODEX=yes` later regenerates the
  same screen and overlays the image artifacts.

### Added — Codex second-opinion consult wrappers

`scripts/consult-phase.sh` plus six `prompts/codex-consult-phase-N.md`
templates (Phase 2 / 3 / 4 / 6 / 7 / 8). The wrapper auto-pastes the
right data into each prompt's placeholder (discoverySheet from
init-state.json, feature list from spec, data model from spec,
config + visualMocks for tool review, full `--context` attach for
the Phase 8 cross-check).

Every consult site in `my-harness-init/SKILL.md` was rewritten to
ask the user first and then `bash consult-phase.sh N "$ROOT"` —
shrinking 6 bash blocks (~10 lines each) to 1 line each.

### Added — discovery NON-NEGOTIABLE rules 6 → 11

The Phase 2 ruleset grew over the release to cover real failures from
the interview transcript:

- Rule 6: Universal-default policy — never ask about engineering
  practices that have industry-standard answers (security layers /
  log sinks / rate limiting / encryption strength / etc).
- Rule 7: Question length cap — ≤ 5 lines including preamble.
- Rule 8: Binary when binary — never synthesize 3-option questions
  where (C) is "A and B with conditions".
- Rule 9: Never ask for unknowable future predictions ("monthly PV
  next year").
- Rule 10: Never force feature-ranking, "core" selection, or "MVP
  framing".
- Rule 11: Proactively suggest ideas (additive only).

### Fixed — purged stale "logo" references

13 user-visible mentions of the removed logo step were updated in
`skills/my-harness-init/SKILL.md` (9), `README.md` (3),
`README.ja.md` (3), and `scripts/codex-ask.sh` usage comment (1).
The single remaining "logo" string is the policy statement "No logo
generation step exists" (intentional — it makes the absence explicit).

## [7.0.4] — 2026-05-11

User feedback during a real-project interview (blog app):

> Security is universal. Why are you asking me about it every time? Apply
> complete security automatically without asking. There's too much of this.
> The questions are too long. Fix what can be improved.

Three Phase 2 NON-NEGOTIABLE rules added to structurally prevent the failure.

### Rule 6: Universal-default policy

Engineering practices governed by `rules/production.md` are **applied
automatically without asking**. The interview asks only about **product**
decisions (features / entities / UX). Specific forbidden question patterns
documented in `SKILL.md` (9 cases):

- "Which security layer should we invest in first?" → forbidden (all layers always on)
- "Where should logs go?" → forbidden (pino default; env override only)
- "What encryption strength?" → forbidden (TLS 1.3 + bcrypt ≥ 12 + AES-256)
- "Should we have rate limiting?" → forbidden (always yes)
- "Backup retention?" → forbidden (30 d hot + 1 y cold)
- "CSP report-only vs enforce?" → forbidden (7 d report → enforce automatic)
- "Should LLM auto-post require approval?" → forbidden (draft + human gate is the only sane default)
- "How strict should TypeScript be?" → forbidden (always strict + `noUncheckedIndexedAccess`)
- "Pre-commit hooks?" → forbidden (always husky + biome + gitleaks)

When in doubt: apply the strictest production default and document it in
`rules/production.md` or a runbook. Never ask.

### Rule 7: Question length cap

Every user-facing question (preamble included) must fit in ≤ 5 lines. Long
threat-model / 4-layer-framework explanations belong in `rules/` or `docs/`
files for agents to read silently — never in the user-facing prompt. If
> 5 lines of preamble are needed, the question is structurally wrong; break
it into atomic questions or apply a default and skip.

### Rule 8: Binary when binary

When the realistic answer space is yes/no (e.g., "include local-LLM auto-post
in v1?"), ask yes/no. 3-option questions where (C) is just "A and B with
conditions" are forbidden — that's a `yes` with caveats, ask yes/no and apply
caveats as defaults.

### Privacy housekeeping (same commit)

- `LICENSE` copyright holder changed from the personal macOS username to
  `my-harness-generator contributors`.
- All git history blobs scrubbed of the long-form personal username via
  `git filter-repo --replace-text` (`anonymous` substitution).
- All commits' author/committer rewritten to `anonymous <anonymous@noreply.local>`.
- Local `.git/config` set to anonymous so future commits stay anonymous.

After this commit, `marketplace.json` / `plugin.json` / `LICENSE` / git history
blobs / commit authorship contain zero personal markers. The only remaining
exposure is the GitHub URL's short-form handle, which is structural.

## [7.0.2] — 2026-05-11

Removed the **scope-reduction bug** in Phase 2 (Discovery). User feedback
from a real-project interview:

> The questions are not on point. The only thing to consider is making the
> best possible product; nothing else is acceptable. The questions also
> duplicate what I just answered. This feels shallow.

Phase 2 had several structural flaws:

### Fixed — opening prompt declared "we'll narrow it down"

- **Before:** "I'll ask follow-up questions and we'll narrow it down together." (Japanese variant updated to match.)
- **After:** "Your feature scope is yours to set; I won't try to talk you out of anything. What I will drill into is the constraints we'll need downstream..." (Japanese variant says equivalent: no scope-cutting questions; respect the feature list; drill into downstream constraints only.)

### Fixed — frequency probe used a scope-reduction framing

The `scaleBreakpoints` probe asked "when does the simple version stop working?"
That presupposes a simple version, and reducing features when it breaks. Wrong
for production-grade. **Fix:** ask "what's the peak load this needs to handle
without degrading" — a capacity target, not a feature-cut threshold. "We will
scale to meet it" is now stated explicitly.

### Added — 5 NON-NEGOTIABLE rules at the top of Phase 2

1. **Discovery NEVER reduces scope.** Production-grade means N features
   listed by the user are all in scope. Frequency / volume questions are
   for capacity targets only. Phrasings like "if only 5/month then DB is
   overkill" are forbidden.
2. **Max-scope fast-path.** Detect max-scope answers in either language
   (English: "all", "max", "everything", "maximum", "fully equipped";
   Japanese equivalents covered) — set `scaleExpectation = max` and skip
   all volume probes. Re-asking with different wording is a bug.
3. **First message ≥ 5 features → feature scope is locked.** Never ask
   "do you need X?" for anything in the first message.
4. **STRICT no-redundancy.** Rewording an already-asked question is a bug.
   Three explicit ban examples added from the real transcript:
   - User answers "everything matters" → harness asks "but how many posts per month?" ← banned (scope-reduction rephrase)
   - User answers "max scale" → harness asks "but how many users specifically?" ← banned (volume rephrase)
   - User answers "cross-genre" → harness restates then re-asks the same intent ← banned (echo + redundant)
5. **Probes describe constraints, not choices.** Scope is fixed; only the
   budget is being elicited.

### Added — two new steps in the internal checklist

- **Max-scope detector**: scan every reply for max-scope signals; once set,
  volume / frequency probes are unreachable.
- **Feature-list-from-first-message detector**: if the first message
  enumerated ≥ 5 features, mark `topUserActions` derived and skip feature
  probes entirely.

With these rules, when the user lists "blog app + AI + rich editor +
scheduled posts + ads + search + Skills export + video embeds + X
integration + SEO + GA + local LLM + RSS + PWA…", the harness no longer
tries to cut features. It locks `scaleExpectation = max` and focuses
exclusively on failure modes / trust / day-2 ops / latency budget.

## [7.0.1] — 2026-05-11

UX/copy patch. Removed every `(Recommended)` label (and its Japanese
equivalent) from interview choices, plus all `MVP` wording from
user-facing surfaces. The interview is the user's decision space; the
harness must not steer it with unjustified opinions.

### Fixed — all steering language removed from interview (`skills/my-harness-init/SKILL.md`)

- Q2b Engineer runner: `Codex (Recommended)` → `Codex`
- Q2c E2E reviewer: `Claude (Recommended)` → `Claude` (description reworked to trade-off form)
- Q2d Reviewer runner: `Codex (Recommended)` → `Codex`
- Q3 Global CLAUDE.md: `Inherit (Recommended)` → `Inherit`
- Q4 Task management: `Local markdown (Recommended)` → `Local markdown` (description reworked to trade-off form)
- Every Map line strips `(Recommended)` and adds `No default applied.`

### Changed — Recommendation policy hardened to strict

The SKILL.md trailing policy was upgraded from "Recommended is OK if
justified" to **"Never add `Recommended`, `Default`, or their Japanese
equivalents to any choice label or description"**. If a real
user-derived justification exists, surface it as a separate sentence before
the question — never as a label on a choice.

### Added — MVP wording forbidden policy

`SKILL.md` policy section now bans "MVP" in user-facing copy. Replacements:
`first version` / `initial release` / `before launch`.

### Fixed — MVP wording removed

- `rules/production.md`: "what an MVP must add" → "what every generated project must have before its first launch"
- `docs/PRODUCTION.md`: "not just MVPs" → "with full controls"
- `README.md`: "no longer scaffolds an MVP" → "scaffolds projects with production controls wired in"
- `README.ja.md`: same direction in Japanese
- `docs/MULTI_TENANT.md`: "POC / MVP stage" → "personal project / validation stage" (in Japanese in the file itself)
- `CHANGELOG.md` 5.0.0 / 7.0.0 entries' MVP mentions rewritten to neutral phrasing

### Fixed — asymmetric `USE_CODEX_E2E_REVIEWER` default

`bootstrap.sh` had `USE_CODEX_E2E_REVIEWER` default as `"n"` (Claude) while
the other `USE_CODEX_*` (analyst / engineer / reviewer) defaulted to `"y"`
(Codex). The unjustified asymmetry is removed (all four now default `"y"`).
The misleading prompt suffix "test execution stays local" was replaced with
"Playwright/Maestro always run under Claude" (behaviour unchanged — only
synthesis goes to Codex; execution always runs in Claude).

## [7.0.0] — 2026-05-11

**Ops surface release.** Research-flavored ideas (items 16–24) shipped as
MVP implementations. The scaffold itself was complete at 6.0.0; 7.0.0
covers the **operations phase** with tooling that pays off after the
project is live.

### Added — Pipeline performance benchmark (item 16)

- `scripts/bench.sh` — runs bootstrap against a fixed `.config` and appends
  the timing (ms) to `bench-results.jsonl`. Run on every plugin update to
  detect performance regressions early. Output includes git rev so diffs
  are readable.

### Added — Spec → Playwright E2E generation (item 17)

- New skill `harness-gen-e2e` (`skills/harness-gen-e2e/SKILL.md`).
- `scripts/gen-e2e.sh` — splits `dev/docs/spec/features.md` on
  `## Feature: <name>` with awk, embeds each feature into
  `prompts/spec-to-e2e.md`, and passes the result to `codex-ask.sh --role harness-engineer`.
- `prompts/spec-to-e2e.md` — fixes the generation rules: 1 happy + 2 sad
  paths, `data-testid` priority, no API mocking, user-perspective
  assertions.
- Existing tests skipped; `--dry-run` shows just the prompt.

### Added — Time-travel debugging (item 18)

- `scripts/replay-agent.sh` — filters `.my-harness/logs/agents.log` by
  `--lane <N>` / `--name <teammate>` / `--since <ISO>` / `--until <ISO>`
  and replays past lane activity in chronological order. Useful for
  postmortems and as teaching material.

### Added — Living architecture diagram (item 19)

- `scripts/architecture-diagram.sh` — traces relative imports under
  `dev/src/`, clusters files by Clean Architecture layer (interfaces /
  application / domain / infrastructure), emits a Mermaid diagram at
  `dev/docs/architecture.mmd`. Layer-rule violations
  (`domain ← application ← others`) listed in `architecture-meta.json`
  with exit 2 on violation.
- `templates/github/workflows/architecture-diagram.yml` — re-runs on PRs
  that touch `src/**`; fails the PR on violations, otherwise commits the
  refreshed diagram automatically.

### Added — AI-suggested rollback (item 20)

- `templates/github/workflows/auto-revert.yml` — fires when
  `pr-to-stage.yml` returns workflow_run failure:
  1. Identifies the most recent main → stage merge commit.
  2. Branches `revert/auto-<run-id>` and runs `git revert -m 1`.
  3. Opens a PR with labels `approved-for-stage` + `auto-revert`
     (skipping the 24-h soak).
  4. Embeds postmortem guidance for on-call in the body.

### Added — Codex cost transparency (item 22)

- `scripts/cost.sh` — reads `.my-harness/logs/codex-cost.jsonl` and
  aggregates by role / model / time range. `--json` for machine output.
  Default unit prices: gpt-5 ($5/1M in, $15/1M out), o4-pro ($10/$30),
  codex-mini ($1/$4).
- Note: token-counting in `codex-ask.sh` / `codex-exec.sh` (the producer
  side) is deferred to 7.1.0. This release ships only the aggregation layer.

### Added — Spec → Issue → Lane closed loop (item 24)

- `scripts/spec-to-issues.sh` — turns each `## Feature: <name>` in
  `features.md` into one GitHub issue. Extracts `owned_files` /
  `lane_hint` from YAML frontmatter and labels the issue with
  `lane-hint:<N>`. Idempotent (skips when title already exists).
  `--dry-run` for preview.
- The lead-side wiring (reading the `lane-hint:` label and
  `<!-- owned_files: [...] -->` body comment for lane assignment) is
  deferred to 7.1.0.

### Added — Cloudflare MCP server (item 23)

- `templates/mcp/cloudflare-server.ts` — stdio MCP server built on
  `@modelcontextprotocol/sdk`. Tools exposed to Claude Code / Cursor /
  Aider:
  - `list_workers` — list Workers in the account
  - `list_deployments` — deployment history for a Worker
  - `rollback_deployment` — roll back to a specific deployment id
  - `d1_query` — execute **SELECT only** queries (DML is rejected
    server-side)

### Added — Multi-tenant migration guide (item 21)

- `docs/MULTI_TENANT.md` — full procedure for retrofitting `tenant_id`
  columns, designing the `tenants` table, adding `tid` JWT claims,
  writing a tenant middleware, forcing `tenantId` as the second
  parameter of every repository function, converting rate-limit to
  per-tenant, composite UNIQUE constraints, deletion policy (`onDelete:
  restrict` + 30-day logical delete + GDPR), and CI enforcement.
- Includes a comparison table of three strategies (shared DB / schema
  isolation / per-tenant D1). The harness default is intentionally
  single-tenant — multi-tenant is **cheaper the earlier you do it**, so
  the doc explicitly says "consider before production".

### Known deferrals (planned for 7.1.0 and later)

- Codex token instrumentation (modify `codex-ask.sh` / `codex-exec.sh` to
  write `codex-cost.jsonl`).
- Wire the `lane-hint:` label into `harness-team-lead` SKILL.md.
- Multi-tenant ESLint custom rule.
- Auto-generate `tests/e2e/fixtures/auth.ts` for spec-to-e2e.

## [6.0.0] — 2026-05-11

**The "you can actually ship to production" release.** Bundles 5.2.1
(bug fixes), 5.3.0 (tests + DX), 5.4.0 (OpenAPI), and a thin but real auth
scaffold. The harness now goes from `/my-harness-init` to "an API with
working login, audit logging, rate limiting, idempotency, and
auto-generated OpenAPI docs" in one bootstrap.

### Added — auth scaffold (real, not stubbed)

- `dev/src/interfaces/http/routes/auth.ts` — `/auth/login`, `/auth/password-reset/request`, `/auth/password-reset/confirm` with full Zod schemas, rate-limit (5/15min login, 3/h password-reset), audit-log on every outcome, and OpenAPI definitions.
- `dev/src/application/auth/login.ts` — bcrypt-ts password verify + jose HS256 JWT issuance (15min TTL).
- `dev/src/application/auth/password-reset.ts` — 2-phase flow: SHA-256 hex token storage (never plaintext), 30-min expiry, `consumed_at` for replay prevention, enumeration-attack-resistant request endpoint.
- `dev/src/infrastructure/persistence/user-repository.ts` — Drizzle D1 adapter (`findUserByEmail`, reset-token CRUD, password update via D1 `batch` for atomicity).

### Added — OpenAPI + Scalar UI

- `@hono/zod-openapi` replaces `Hono` in `app.ts`. Every route declared with `createRoute({...})` produces OpenAPI 3.1 automatically.
- `GET /openapi.json` — machine-readable spec.
- `GET /docs` — Scalar API reference UI.
- Generated clients (TS / Python / Go / Rust) can be produced with `pnpm dlx openapi-typescript /openapi.json`.

### Added — Production Readiness Score

- `scripts/score.sh` — evaluates 18 production-readiness checks (runbooks, wrangler config, audit_log, Renovate, CodeQL, SBOM, license, k6, Lighthouse, SOPS, middleware suite, auth route, OpenAPI, tests) and prints a 0-100 score. `--json` for machine output.
- Exit codes: `0` (≥80), `1` (60-79), `2` (<60) — wire into CI as a release gate.

### Added — Tests (TDD compliance)

`rules/production.md` requires TDD strict but 5.0–5.2 shipped untested middleware. Now:

- `templates/web/src/interfaces/http/middleware/rate-limit.test.ts` — window boundary, limit enforcement, 429 response shape, Retry-After header.
- `templates/web/src/interfaces/http/middleware/idempotency.test.ts` — GET passthrough, replay caching, short-key 400, key-less passthrough.
- `templates/web/src/infrastructure/audit/audit-log.test.ts` — adapter contract verification, metadata JSON encoding, sql tag invocation.
- `templates/web/src/infrastructure/feature-flags/feature-flag.test.ts` — boolean / 0% / 100% / stable hash / WeakMap memoize.

### Added — 4.x → 5.x/6.x upgrade automation

- `scripts/upgrade-4-to-5.sh` — idempotent. Detects 4.x patterns (Node `@hono/node-server`, old `app.ts` signature, `wrangler.toml` only, missing `audit_log`), warns about manual steps, automatically removes the bad deps + drops missing runbooks. Run once after `/my-harness-adopt` against an adopted 4.x project.

### Added — Operational guidance baked in

- `templates/dotmyharness/learnings.md` → `dev/.my-harness/learnings.md` at bootstrap. All lane agents read this at ASSIGNMENT-time; new findings accumulate via PR review (blameless, no per-issue/lane names).
- `templates/dotmyharness/secrets-README.md` → `dev/secrets/README.md`. Concrete age-keygen + sops encrypt commands; CI integration via `AGE_SECRET_KEY_STAGE`.

### Changed — `doctor.sh` wired into the team-lead preflight

`skills/harness-team-lead/SKILL.md` Precondition now invokes
`bash $CLAUDE_PLUGIN_ROOT/scripts/doctor.sh` after `preflight.sh`. WARN
is advisory; FAIL stops the lead before the first lane spawn.

### Changed — package.json deps (USE_WEB=yes)

Added: `@hono/zod-openapi`, `@scalar/hono-api-reference`, `bcrypt-ts`, `jose`.

### Fixed — 5.2.0 carry-over bugs

- `wrangler.jsonc` / `alchemy.run.ts` / `lighthouserc.json` now have **`PROJECT_NAME`** substituted at bootstrap (was hard-coded `harness-app` / `harness`).
- `strictCors` no longer throws at module load when `ALLOWED_ORIGINS` is missing — defaults to `http://localhost:{3000,8787}` in non-prod (`ENVIRONMENT !== 'prod'`). Production still requires explicit allowlist.
- `pnpm dev` defaults to `wrangler dev --local --persist-to=.wrangler/state` so first-run works without real Cloudflare resource IDs. `pnpm dev:remote` opts in to the cloud bindings.
- `tsx watch` removed from `dev` script; `tsx` no longer relevant for Workers target.

### Removed

- `build: tsc -p tsconfig.build.json` script — Workers bundles internally via wrangler.

## [5.2.0] — 2026-05-11

Integration pass. 5.0/5.1 added production middleware / docs / CI workflows
but never connected them — the templates referenced KV bindings that didn't
exist in `wrangler.jsonc`, the worker entrypoint was Node-flavoured while
the deploy path was Workers, and `templates/backend/hono/` duplicated
`templates/web/src/`. This release wires it all together.

### BREAKING — Workers becomes the only production runtime

The harness now ships **Cloudflare Workers + D1** as the documented production
target. `@hono/node-server` is removed from generated `package.json`. Local
development uses `wrangler dev` (so KV / D1 / R2 bindings behave identically
to prod). Existing 4.x/5.x projects keep working but new `dev/src/main.ts`
is a `export default { fetch }` Workers handler.

### Added — real integration

- `templates/web/src/main.ts` rewritten as Workers entrypoint with full `Env` type (D1 / RATE_LIMIT_KV / IDEMPOTENCY_KV / BackupBucket / SENTRY_DSN / etc.).
- `templates/web/src/interfaces/http/app.ts` wires production middleware in the canonical order: `requestLogger → secureHeaders (with explicit CSP/COOP/CORP/Permissions-Policy) → strictCors → idempotency → routes`.
- `templates/web/src/interfaces/http/routes/health.ts` exposes `/healthz`, `/livez`, `/readyz` (with D1 ping), plus legacy `/health`.
- `templates/web/src/infrastructure/logging/pino-logger.ts` — pino factory with redact for `authorization` / `cookie` / `*.password` / `*.token`.
- `templates/db/d1/src/db/schema.ts` adds the `audit_log` table (indexed by actor + action) referenced by `rules/production.md`.
- `templates/db/d1/drizzle/0001_production_tables.sql` initial migration including `users`, `password_reset_tokens`, and `audit_log`.
- `templates/db/d1/wrangler.jsonc` (new JSON variant) declares **all** bindings: D1 (`DB`), KV (`RATE_LIMIT_KV`, `IDEMPOTENCY_KV`), R2 (`BackupBucket`) per dev / stage / prod environments.
- `templates/web/alchemy.run.ts` declares the Alchemy v2 stack (D1 + 2× KV + R2 + Worker).
- `templates/web/tests/load/smoke.js` — k6 baseline (p95 < 500 ms, error < 1 %).
- `templates/web/lighthouserc.json` — Lighthouse CI budgets (perf ≥ 0.85, a11y ≥ 0.95).

### Added — harness self-CI (`.github/workflows/`)

The plugin repo had no CI of its own. New `lint.yml` runs:
- `bash -n` on every script (scripts / skills / tests)
- shellcheck (warning level) on the same set
- `bash tests/spawn-lane-decision.sh` smoke test
- `tsc --noEmit` on `templates/web/src/` against pinned deps

Catches regressions before they hit users via `/plugin marketplace update`.

### Changed — middleware layout follows Clean Architecture

5.0/5.1 placed middleware at `templates/backend/hono/middleware/`, lib at
`templates/backend/hono/lib/`. That broke the existing `templates/web/src/`
layered structure and would have shipped to `dev/src/middleware/` instead
of the canonical layered location. 5.2.0 moves everything into the right
layer:

| 5.1 path | 5.2 path |
|---|---|
| `templates/backend/hono/middleware/security-headers.ts` | (deleted — uses built-in `hono/secure-headers` with options) |
| `templates/backend/hono/middleware/cors.ts` | `templates/web/src/interfaces/http/middleware/cors.ts` |
| `templates/backend/hono/middleware/rate-limit.ts` | `templates/web/src/interfaces/http/middleware/rate-limit.ts` |
| `templates/backend/hono/middleware/idempotency.ts` | `templates/web/src/interfaces/http/middleware/idempotency.ts` |
| `templates/backend/hono/middleware/logger.ts` | `templates/web/src/interfaces/http/middleware/request-logger.ts` |
| `templates/backend/hono/routes/health.ts` | (merged into `templates/web/src/interfaces/http/routes/health.ts`) |
| `templates/backend/hono/lib/sentry.cloudflare.ts` | `templates/web/src/infrastructure/monitoring/sentry.cloudflare.ts` |
| `templates/backend/hono/lib/sentry.node.ts` | (deleted — Workers-only stack) |
| `templates/backend/hono/lib/audit-log.ts` | `templates/web/src/infrastructure/audit/audit-log.ts` |
| `templates/backend/hono/lib/feature-flag.ts` | `templates/web/src/infrastructure/feature-flags/feature-flag.ts` |
| (no pino factory) | `templates/web/src/infrastructure/logging/pino-logger.ts` |

`templates/backend/` is removed entirely.

### Fixed — duplicate workflow distribution

`scripts/lib/distribute-production.sh` was copying the CI workflows that
`scripts/setup-common.sh` already distributes via `cp_glob_if_missing`. Now
the production-distribute helper handles **only** the runbooks (which
`templates/docs/runbooks/` is exclusively responsible for).

### Fixed — `sbom.yml` for pnpm

Switched from `@cyclonedx/cyclonedx-npm` (npm-only) to `@cyclonedx/cdxgen`
which auto-detects pnpm / yarn / bun.

### Fixed — `generate-package-json.sh` deps

- Adds `@sentry/cloudflare` to deps when `USE_WEB=yes`.
- Adds `alchemy`, `effect`, `@effect/platform-bun` to devDeps.
- Removes `@hono/node-server` (Workers-target).
- `dev` script: `tsx watch src/main.ts` → `wrangler dev`.

### Documentation

- `docs/PRODUCTION.md` — every path updated for the new layout, plus new rows for `wrangler.jsonc`, `alchemy.run.ts`, k6, Lighthouse, and `audit_log` schema.
- `rules/production.md` — paths corrected.

## [5.1.0] — 2026-05-11

Refactor pass on top of 5.0.0. No behaviour change; the harness now has a
cleaner internal API, faster TS templates, and tighter docs.

### Refactored — internal libraries (shared by ≥ 2 callers)

- `scripts/lib/memory-probe.sh` — single source of truth for `detect_total_ram_gb` / `detect_avail_ram_mb` / `detect_swap_total_gb` / `detect_swap_used_mb` / `detect_compressor_mb` / `detect_pressure`. `spawn-lane-decision.sh`, `recommend-lanes.sh`, and `doctor.sh` all source it (previously duplicated probe code across three files).
- `scripts/lib/rsync-excludes.sh` — wired into `bootstrap.sh` (was dead code in 5.0.0). The harness self-copy now goes through `harness_rsync`; patterns are edited in one place.
- `scripts/lib/distribute-production.sh` — production-template distribution extracted from `bootstrap.sh` to its own sourced library (`distribute_production_templates`).

### Refactored — bootstrap.sh

- New `copy_if_absent <src-glob> <dst-dir>` helper consolidates the five near-identical loops that distribute runbooks / CI workflows / Renovate / Dependabot / Hono middleware. Generated projects keep user-edited files (non-destructive).

### Refactored — doctor.sh

- `RESULTS` accumulator: string-parsing → three parallel bash arrays (`KINDS` / `NAMES` / `MSGS`). Removes a fragile pipe-into-while-IFS read.
- `--json` output: hand-rolled `sed`-based escaping → proper `jq -n --arg` construction. Now correctly handles backslash / newline / control chars in messages.

### Refactored — Hono templates

- `lib/audit-log.ts` — DB-specific `DrizzleD1Database` dependency removed. New `AuditWriter` adapter contract with a `drizzleAuditWriter(db, sql)` factory works against any Drizzle dialect (D1 / Postgres / MySQL / SQLite).
- `lib/sentry.ts` → `lib/sentry.cloudflare.ts` + `lib/sentry.node.ts`. Workers and Node/Bun deployments each get a focused helper without conditional bundling tricks.
- `lib/feature-flag.ts` — `parse(env)` result is now memoized in a `WeakMap` keyed by the env object. Removes the per-call parse cost.

## [5.0.0] — 2026-05-11

**Production-grade rebuild.** The harness now scaffolds projects that can ship
to production with full controls. Every concern that's hard to retrofit (security
headers, rate limiting, structured logging with request-id propagation,
idempotency, health endpoints, Sentry, audit log, feature flags, CodeQL,
SBOM, license audit, k6, Lighthouse, Renovate, Dependabot, six runbooks)
is wired in at `bootstrap.sh` time and enforced by `rules/production.md`.

### Added — production scaffold

- **Hono middleware suite** in `templates/backend/hono/`:
  `security-headers.ts` (CSP/HSTS/XFO/COOP/CORP/Permissions-Policy),
  `rate-limit.ts` (KV-backed token-bucket per-bucket: login / password-reset / api),
  `logger.ts` (pino + `x-request-id` propagation, redacts authorization / cookie / password),
  `idempotency.ts` (`Idempotency-Key` 24 h KV cache),
  `cors.ts` (allowlist from `ALLOWED_ORIGINS`, no `*`).
- **Health endpoints** (`templates/backend/hono/routes/health.ts`):
  `/healthz` / `/readyz` (DB ping + smoke checks) / `/livez`.
- **Lib helpers**: `sentry.ts` (`@sentry/cloudflare` Workers init),
  `audit-log.ts` (append-only `audit_log` table), `feature-flag.ts`
  (env-var driven with stable-hash % rollout).
- **CI workflows**: `codeql.yml` (PR + weekly), `sbom.yml` (CycloneDX on
  release), `license-check.yml` (fail on GPL/AGPL/SSPL/SSPL),
  `k6-smoke.yml` (PR → stage), `lighthouse.yml` (PR → main/stage).
- **Dependency automation**: `renovate.json` (grouped minor/patch,
  manual majors, beta-pin) + `dependabot.yml` (GH Actions ecosystem).
- **Runbooks** (`templates/docs/runbooks/`): `incident-response.md`,
  `deploy.md`, `rollback.md`, `dr-plan.md`, `oncall.md`,
  `postmortem.md` — required by `rules/production.md`'s pre-launch
  checklist.
- **`rules/production.md`** — single source of truth for production
  expectations (observability / security headers / rate limits / CORS /
  idempotency / health / audit log / backups / DR / dependencies /
  SAST/DAST / supply chain / runbooks / pre-launch checklist).
- **`docs/PRODUCTION.md`** — guide that maps each concern to its file
  in the generated project.

### Changed — OS-aware MAX_LANES recommendation

- New `scripts/lib/recommend-lanes.sh` accounts for **macOS memory
  compression** (+33 % effective RAM via `vm.compressor`) and live
  `memory_pressure -Q` (green/yellow/red), and Linux swap. The naive
  "TOTAL_RAM >= 24 GB → 4 lanes" rule was wrong: a 16 GB Mac in
  green pressure now correctly recommends 4 lanes.
- `bootstrap.sh` and `scripts/doctor.sh` both use the new lib.

### Added — harness operations

- `scripts/doctor.sh` — pre-flight diagnostics
  (bare repo / .config / MAX_LANES vs recommendation / required tools /
  Codex CLI auth / Codex daemon liveness / spawn-lane-decision dry-run /
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).
  `--json` for machine-readable output.
- `scripts/prune-lanes.sh` — remove teammates whose lane number exceeds
  the current `MAX_LANES` from the team config (`--max <n>`,
  `--dry-run`). Resolves the "stale teammates after lowering MAX_LANES"
  pitfall.
- `scripts/lib/rsync-excludes.sh` — single source of truth for
  `dev/.my-harness/` rsync rules. Sourced by bootstrap and adopt-refresh.
- `tests/spawn-lane-decision.sh` — pure-bash smoke test (11 cases,
  no bats dependency) covering every REFUSE / SKIP / SPAWN path.

### Changed — `spawn-lane-decision.sh` cleanup

- Removed redundant hard-coded `1..4` validation (MAX_LANES is the
  ceiling). Invalid input is now caught generically (positive integer).
- `exceeds-max-lanes` reason now suggests `prune-lanes.sh` explicitly.

### Added — bootstrap distributes production templates

`bootstrap.sh` now copies, when applicable:

- `templates/docs/runbooks/*.md` → `dev/docs/runbooks/`
- `templates/github/workflows/{codeql,sbom,license-check,k6-smoke,lighthouse}.yml` → `dev/.github/workflows/`
- `templates/github/renovate.json` → `dev/renovate.json`
- `templates/github/dependabot.yml` → `dev/.github/dependabot.yml`
- `templates/backend/hono/{middleware,routes,lib}/*.ts` → `dev/src/{middleware,routes,lib}/`
  (only when `USE_BACKEND=yes` and `BACKEND_KIND=hono`)

All copies are non-destructive: existing files are kept.

### BREAKING

- Generated projects now expect `RATE_LIMIT_KV` and `IDEMPOTENCY_KV` KV
  bindings in `wrangler.jsonc` and `alchemy.run.ts`. Adopt these by
  rerunning `/harness-deploy` (setup mode adds the missing bindings).
- `dev/src/middleware/`, `dev/src/routes/health.ts`, `dev/src/lib/{sentry,audit-log,feature-flag}.ts`
  are now reserved paths owned by the harness; user code must not
  overwrite them. Rename your files if you previously claimed these
  paths.
- Adopted projects upgrading from 4.x: rerun `/my-harness-adopt` to
  receive the new templates and runbooks (refresh path is non-destructive
  on existing files).

## [4.7.0] — 2026-05-11

Comprehensive surface reduction and observability tighten-up.

### Configurable lane cap

- `MAX_LANES` (1..4, default 4) is now a first-class option in `.my-harness/.config`. `bootstrap.sh` asks for it at Setup; `spawn-lane-decision.sh` refuses lanes > MAX_LANES with reason `exceeds-max-lanes`. Lower this on tight machines without touching code.

### Skill / slash-command consolidation

- `/harness-deploy-setup` + `/harness-deploy-execute` collapsed into a single idempotent `/harness-deploy` (auto-detects mode from `dev/alchemy.run.ts` presence). Slash-command surface: 6 → 5 (`/my-harness-init`, `/my-harness-adopt`, `/harness-team-lead`, `/harness-deploy`, `/harness-codex-daemon`). Skill count: 6 → 5.

### Documentation consolidation

- Deleted `docs/SECURITY.md` — security policy merged into `docs/SETUP.md` (one place to look for "what do I configure once after creating the repo").
- Deleted `docs/ENGINEER_STANDARDS.md` — content was already mirrored by `rules/*.md` (the single source of truth).
- Deleted `templates/prs/` — zero references in the dispatch path.

### Prose compression

- `README.md`: 372 → ~190 lines (-49 %). Same content, less repetition.
- `README.ja.md`: 341 → ~180 lines (-47 %).
- `CHANGELOG.md`: pre-4.7 history collapsed to a one-line-per-version summary table.

### Misc

- `dev/.my-harness/` rsync now excludes `.git`, `node_modules`, `*.test.ts`, internal CHANGELOG / docs / README — only runtime assets ship to user projects.
- Stale `.harness/docs/ENGINEER_STANDARDS.md` reference in `templates/android/.../MainActivity.kt` updated to `.my-harness/rules/design.md`.

No behaviour change beyond the cap.

## Pre-4.7 history (summary)

| Version | Highlight |
|---|---|
| 4.6.0 | Removed 4 auxiliary slash commands replaceable by one-line manual ops (`/harness-branch-protection`, `/harness-check-codex-auth`, `/harness-check-secrets`, `/harness-setup-secrets`). Skill SKILL.md compression (`harness-codex-daemon`/`harness-deploy-setup`/`harness-deploy-execute` shrunk a combined 146 lines). |
| 4.5.0 | Semantic-preserving prose compression on the high-context-frequency files (agents/*, SKILL.md, rules/*) — 1560 → 1274 lines (-18 %). No rule body / status enum / bash command changed. |
| 4.4.0 | `/my-harness-update` folded into `/my-harness-adopt` (branches on `.bare/` presence). Removed 8 thin-wrapper rule skills — bodies live in `rules/*.md` and are loaded by `dev/CLAUDE.md` / `dev/AGENTS.md` / agents / `codex-ask.sh --role`. |
| 4.3.0 | Dropped 10 unused scripts, 6 thin-wrapper skills, 1 niche workflow template. Stripped all TEST-LOG debug blocks (superseded by 4.1.0 logging). CHANGELOG / README / plugin descriptions rewritten for the 4.x architecture. |
| 4.2.0 | `/my-harness-update` skill — idempotent counterpart of `/my-harness-adopt` for plugin upgrades. (Folded into adopt in 4.4.0.) |
| 4.1.0 | Observability + auto-intervention: per-teammate `agent-log.sh`, `monitor-agents.sh` view + `--watchdog` mode, anomaly classification (stagnation / repeated-blocked / codex-exec-failure / codex-no-op / suffixed-name), lead Step 3.0 deterministic intervention. Fixed BSD `date -j -f` timezone bug (`-ujf`). |
| 4.0.0 (BREAKING) | True Codex delegation. `codex-exec.sh` performs real file edits inside lane worktrees; engineer / reviewer Claude become monitors. `analyst` gains `USE_CODEX_ANALYST`. New status `blocked-codex-error`. |
| 3.10.0 | `rules/` became the single source of truth shared across Claude and Codex; `dev/CLAUDE.md` + `dev/AGENTS.md` reference `rules/*.md`; `codex-ask.sh` auto-attaches the same files via `--context`. |
| 3.9.x | `codex-ask.sh` absolute path; `owned_files` as dispatch hint; engineer hard rules + `blocked-workspace-not-ready`; drop `start-dev.sh` launcher; `/my-harness-adopt` for existing-repo conversion. |
| 3.8.x | Parallel dispatch with sequential spawn; root-resolution from any cwd; vendor-neutral cleanup; lane-by-lane spawn gate + name-collision guard. |
| 3.0 – 3.7 | Iterative kernel-panic-prevention path (preflight gate, lane-lock, devshell wrapper, content-hash cache, task lifecycle, worktree management). Largely subsumed by 3.8+. |
| 2.x | Agent Teams architecture (4 lanes × 4 roles persistent teammates); shared Codex daemon; Cloudflare IaC moved from OpenTofu to Alchemy v2. |
| 1.0.0 | Initial plugin release: skills + agents + hooks + secret masking. |
