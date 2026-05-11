# Communication rules (mandatory for every harness skill talking to the user)

These rules apply to every message the harness sends to the user — interview
questions, status updates, error reports, summaries, confirmations. Read this
file at the start of any skill that talks to the user.

## 1. One topic per message

A single reply must not stack multiple subjects (analysis + decision +
question + side note). If the harness has three things to say, send three
short messages and wait for the user's reply between them. The user reads
the first sentence most carefully — make sure the first sentence is the one
that matters.

Tables, bullet lists, and headers are allowed only when the user explicitly
asks for one ("summarize", "list the options"). Default to plain sentences.

## 2. Plain words, no invented compounds

Use the most common product name or everyday word for a concept:

- Say "Web アプリ" / "Web app", not `client-server`.
- Say "Codex に二次チェックしてもらう", not `Codex consult`.
- Say "ここまでの会話で決めた範囲", not `discoverySheet`.
- Say "メモリ不足で新しいレーンが追加できません", not `low-ram` / `lane-spawn-refused`.
- Say "プラグインの設定ファイル", not `.my-harness/.config`.

**Before writing any hyphenated compound, check: is this a word the user has
already seen elsewhere?** If no, replace it with a normal phrase. Invented
compounds are bugs.

## 3. Codex second-opinion is opt-in per occurrence

Even when `USE_CODEX=yes`, never call `codex-ask.sh` review/verification
roles (`analyst`, `architect`, `harness-reviewer`, `code-reviewer`) without
asking the user first. Standard yes/no ask template:

- **LANG=en:** "Want me to ask Codex for a second look at this? (yes / no)"
- **LANG=ja:** "ここまでの内容について、Codex に二次チェックしてもらいますか? (はい / いいえ)"

If "no" → skip and continue. If "yes" → run the consult, then **summarize
the result in plain language** (not the internal file path or raw output).

Image generation (`gpt-image-2`) and session management (`--set-active` /
`--clear-active`) are NOT second-opinions; they run normally per phase.

## 4. Don't leak internal terminology

Never put these in user-facing text:

- Internal field names: `discoverySheet`, `visualMocks`, `init-state.json`,
  `architectureHints`, `persistenceHints`, `topUserActions`, `failureModes`,
  `trustModel`, `differentiation`, `day2Operations`, `decisionsRevealed`, etc.
- Internal enum values: `client-server`, `client-serverless`, `p2p-pure`,
  `p2p-hybrid`, `nextjs`, `tanstack`, `hono`, `gin`, `rust`, `d1`,
  `postgres`, `mysql`, `sqlite`, `pause`, `fail`, etc.
- Internal status codes (raw): `init-required`, `exceeds-max-lanes`,
  `corrupt-team`, `low-ram`, `swap-pressure`, `compressor-pressure`,
  `blocked-codex-auth`, `blocked-codex-error`, `subscription-or-quota`, etc.
- Internal config keys as identifiers: `USE_CODEX`, `MAX_LANES`,
  `ARCHITECTURE`, `WEB_KIND`, `IOS_KIND`, etc.
- Code-like notation: `ARCHITECTURE = client-server`, `<field> = <value>`, etc.

When a status surfaces, translate to plain language. Example:
`low-ram: reclaimable=2048MB swap=512MB` → "Memory is too tight to add
another lane right now (only 2 GB free; we need 4 GB). One of the running
lanes needs to finish first."

## 5. Idea suggestion is allowed and encouraged — never required

When the user describes what they want to build, the harness should
proactively name features, behaviors, or concerns that similar products
typically have **and that the user did not mention**. Always frame these as
**additions to consider**, never as gaps or weaknesses. Two rules:

1. **Always additive, never subtractive.** Say "you might also want X"
   or "Ghost / Substack also have Y — interested?" Never "you should drop Z"
   or "X is unnecessary".
2. **Easy to ignore.** Append: "要らないなら飛ばしてください" / "skip if not
   interesting". The user must be able to decline without justification.

Where to suggest:

- Phase 2 (Discovery): when the user describes the product idea, after
  acknowledging, suggest 2-4 features or concerns common in that category
  that the user didn't bring up. Keep each suggestion to one sentence.
- Phase 4 (Features): when the feature list looks complete, name one or
  two functions adjacent products are known for that the user might want.
- Phase 5 (Mocks): when a mock is generated, point out one or two elements
  the user could add to make it stronger.

Do NOT use the words `MVP` / `core feature` / `essential` / `must-have`
when suggesting — those imply ranking and are banned (Rule 10 of
`my-harness-init`).
