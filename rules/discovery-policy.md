# Discovery policy — Phase 2 NON-NEGOTIABLE rules (full text)

`my-harness-init` Phase 2 ("Open discovery conversation") obeys these rules
on every turn. SKILL.md keeps a 1-line summary per rule; the full
explanation lives here so Claude reads the canonical version once instead
of merging duplicate restatements.

Violating any of these is a bug.

---

## 1. Discovery NEVER reduces scope

If the user listed N features, all N are in scope. Frequency / volume /
"how often" questions are **only for capacity targets** (peak RPS, peak
concurrent writers, retention horizon) — never to suggest a feature
should be dropped. Phrasings like "if only 5/month then DB is overkill"
or "if monthly then static SSG is enough" are forbidden.

The harness does not scope down. It capacities up.

## 2. Max-scope fast-path

When the user answers any volume / completeness question with `全部 /
max / フル装備 / all / everything / maximum / unlimited / 最高のもの /
fully equipped` (or any clear "do not reduce scope" statement):

- Set `scaleExpectation = "max"` (`users: "1M+"`, `dataSize: "TB"`,
  `concurrency: "high"`) unless the user provides specifics.
- Skip every further volume / frequency / "how big" / "how often" probe.
- Do **not** re-ask the same question hoping for a smaller number. Move
  on to **constraint** discovery (failure / trust / day-2 / privacy /
  latency budget).

## 3. Read the user's first message completely before the first follow-up

If their first message enumerates ≥ 5 concrete features (e.g., "AI text,
scheduled posts, ads, search, embeds, RSS, PWA"), the feature scope is
established. Do not ask "do you really need X". Move directly to
architecture / constraint questions.

## 4. No question may be asked twice in different phrasing

If the next planned question is a rewording of one already asked, drop
it — pick a different empty `discoverySheet` field. Strict.

Ban examples (from a real transcript):

- User said "全部大事" → Claude asked "月何本書く？" (rephrased volume) ← banned
- User said "max scale" → Claude asked "but how many users specifically?" ← banned
- User said "ジャンル横断で" → Claude restated then re-asked the same ← banned

## 5. Probes describe constraints, not choices

Reframe any "simple vs complex" probe as "what's the upper bound the
system must handle". The user's scope is fixed; only the budget is
being elicited.

## 6. Universal-default policy (don't ask about engineering practice)

Production-grade defaults are decided by `rules/production.md` and applied
automatically at bootstrap. The interview NEVER asks the user to choose
between defense layers, log sinks, quality gates, or operational
practices that have an industry-standard correct answer. The interview
asks about **product** decisions (features / entities / user-visible
behavior), not engineering practices.

| Forbidden | Why | Harness applies instead |
|---|---|---|
| "Which security layer first?" / "シークレット混入の主犯はどっち？" | All on by default | gitleaks pre-commit + GH Push Protection + GHA re-scan + Sentry source-map upload |
| "Where do logs go?" / "ログ送信先は？" | pino default; env override | `infrastructure/logging/pino-logger.ts` |
| "What encryption strength?" / "暗号化は？" | Industry standard | TLS 1.3, bcrypt ≥ 12, AES-256, age |
| "Should we have rate limiting?" / "レート制限は？" | Always yes | `middleware/rate-limit.ts` |
| "Backup retention?" / "バックアップ保持期間？" | 30 d hot + 1 y cold | `rules/production.md` |
| "CSP report-only or enforce?" / "CSP は報告のみ?" | report-only 7d → enforce auto | `docs/runbooks/deploy.md` |
| "LLM auto-post approval?" / "LLM 自動投稿に承認は要る？" | Always yes — draft + human gate | Default for any auto-ingest path |
| "TypeScript strict?" / "TS strict は？" | Always strict | `tsconfig.json` |
| "Pre-commit hooks?" / "コミット前 hook?" | Always | Husky + biome + commitlint + gitleaks |

When in doubt: apply the strictest production-grade default and document
it in `rules/production.md` or a runbook. Never surface as a question.

## 7. Question length cap — ≤ 5 lines

Every question (preamble included) fits in 5 lines as rendered. Threat
models, 4-layer frameworks, architectural explanations belong in `rules/`
/ `docs/` for the agent to read silently — not in the user-facing
prompt. If > 5 lines of preamble feel necessary, the question is
structurally wrong: break it into atomic questions or apply a default
and skip.

## 8. Binary when binary

If the realistic answer space is yes / no (e.g., "include local-LLM
auto-post in v1?"), ask yes / no. 3-option questions where (C) is
"both A and B with conditions" are banned — that's a `yes` with
caveats; ask yes / no and apply the caveats as defaults.

## 9. Never ask for unknowable future predictions

The user cannot know "how many readers year 1", "monthly PV next year",
"revenue forecast". These are guesses, not constraints. Forbidden:

- "1 年後の読者規模は？" / "PV はどれくらい？" / "ユーザー数の年 1/年 3 目安は？"
- "How big does it get in year one? Year three?"
- "What's the year-1 vs year-3 expected peak?"

The harness builds for autoscale by default (Cloudflare Workers / D1 /
KV / R2 scale transparently). Architecture never rides on speculative
growth numbers. The user volunteers concrete commitments (e.g.,
"contract for 10k concurrent connections", "existing 50k newsletter
subscribers"); otherwise assume max and move on.

## 10. Never force feature-ranking / "core" selection / MVP framing

Once N features are listed, all N are in scope (Rule 1). These are
banned:

- "Which one feature, without which this project has no reason to exist?"
- "What's the core that defines the MVP?"
- "If you had to pick one differentiator, which one?"
- "Rank these features by essentiality."
- "Which feature is the heart of the product?"
- Japanese: "これが無いなら作る意味がない、と一番強く感じる機能 1 つ" / "MVP の核を決めます" / "コア機能"

These are scope-reduction disguised as discovery. The harness produces
a production-grade scaffold that implements **all** listed features.

The differentiation probe (Phase 2 probe set) asks about **competitive
positioning** ("why pick this over Notion/Substack/Ghost?") — that is
allowed. It is not the same as "which of your features is THE one".
Positioning is whole-product-vs-world; feature-ranking is cutting from
your own list. Do not confuse them.

When the user has said "実装すればいい / build everything / all of the
above / 全部やる" or equivalent, NO further prioritization questions are
allowed — proceed to the next `discoverySheet` field.

## 11. Proactively suggest ideas the user didn't mention (additive only)

After acknowledging the user's described product, name 2-4 features /
behaviors / concerns that adjacent products in the same category
typically have and that the user did not mention. Frame as additions
to consider, not gaps.

**Forbidden when suggesting:**

- The words `MVP` / `core` / `essential` / `must-have` / `the one` (Rule 10).
- Gap framing: "You're missing X" / "X が足りない". Use "X もよくあります" /
  "X も入れますか" instead.
- More than 4 suggestions per turn.
- Suggestions outside the product category (don't suggest "newsletter"
  for a CLI tool).

**Source of suggestions:** known features of well-known products in the
same category (Ghost / Substack / Note / Hashnode for blogs; Linear /
Jira / Asana for issue trackers). Do not invent novel features.

Bilingual examples (compose in `$LANG`):

**ja:**

- User: "ブログを作りたい。AI で文章書ける、リッチエディタ、予約投稿、広告、検索、Skills エクスポート、動画埋め込み、X 投稿、サムネ、GSC/GA、ローカル LLM、Atom/RSS、PWA"
- Acknowledge: "全部含めて進めます。"
- Suggest:
  - "下書き共有 URL (公開前に他人にプレビューさせる) もブログだとよく使われます。要りますか?"
  - "コメント欄を入れる場合、スパム対策 (Akismet 系 or hCaptcha) のチェックを後で挟みますか?"
  - "Webmention / トラックバック対応 (個人ブログ界で復活してる流れ) を入れますか?"
  - "シリーズ機能 (連載記事を順番にナビゲートできる) もよく出ます。"
- Then: "要らないものは飛ばしてください。次は ◯◯ について聞きます。"

**en:**

- User: "I want to build a blog. AI-assisted writing, rich text editor, scheduled posts, ads, search, Skills export, video embeds, X posting, thumbnails, GSC/GA, local LLM, Atom/RSS, PWA"
- Acknowledge: "Got it — all of those are in scope."
- Suggest:
  - "Preview-share URLs (let others read a draft before publishing) are common in blogs — want that?"
  - "If you're enabling comments, want a spam-filter step (Akismet / hCaptcha) added in?"
  - "Webmention / trackback support (making a comeback in indie blogs) — interested?"
  - "Series navigation (linking sequential posts in order) is also common."
- Then: "Skip whatever doesn't fit. Next I'll ask about ◯◯."
