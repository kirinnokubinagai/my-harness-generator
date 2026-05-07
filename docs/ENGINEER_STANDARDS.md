# Engineer Standards

## Coding

### Naming and Documentation

- Variable and constant names must be nouns that a reader can understand at a glance. Abbreviations and guesswork are prohibited.
- All variables and constants must have **JSDoc/TSDoc comments**.
- **Inline comments inside function bodies are prohibited**. If explanation is needed, split the function.
- Functions, types, and modules **require TSDoc**. Fill in `@param`, `@returns`, `@throws`, and `@example`.

```ts
/**
 * Creates a user from an email address and password.
 *
 * @param input - Input required for user registration (Zod-validated)
 * @returns The created user. On duplicate, returns Result.err
 * @throws DatabaseError - On DB connection failure
 */
export async function createUser(input: CreateUserInput): Promise<Result<User>> { ... }
```

### Hono Clean Architecture

```
src/
├── domain/          # Entities, value objects, repository interfaces
├── application/     # Use cases (orchestration)
├── infrastructure/  # Drizzle implementations, external APIs, Hono handlers
└── interfaces/      # Hono routers, input/output DTOs (Zod)
```

Dependency direction: `interfaces → application → domain ← infrastructure`.
domain does not depend on outer layers. infrastructure implements domain interfaces.

### Nix Pure (impure commands prohibited)

- Pin Node.js / pnpm / Biome / Playwright / Maestro / Trivy / Semgrep in `flake.nix`.
- Do not install tools by any means other than `nix develop` (`brew install` is prohibited).
- CI also runs via `nix develop --command pnpm ci`.
- Exceptions: Claude Code / Codex / GitHub CLI only.
- **direnv required**: write `use flake` in `.envrc` and run `direnv allow`; the nix shell activates automatically when entering the directory.
  This prevents both humans and AI from accidentally running impure commands due to forgetting `nix develop`.

### No Hardcoded Values (strictly enforced)

The following are blocked at commit time by the `husky pre-commit` `forbidden-patterns` check (`.harness/scripts/check-forbidden-patterns.sh`):

- **String literal hardcoding** of values that should be environment variables.
  Target keys: `JWT_SECRET` / `DATABASE_URL` / `*_API_KEY` / `*_TOKEN` / `STRIPE_SECRET` /
  `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `CLOUDFLARE_API_TOKEN` / `AWS_*` / `GITHUB_TOKEN` /
  `SUPABASE_*` / `SENTRY_DSN` / `REDIS_URL` / `SMTP_*` / `SESSION_SECRET` / `ENCRYPTION_KEY` / `WEBHOOK_SECRET`
- **URL credentials** such as `https://user:password@host`
- **Production DSNs** pointing to non-localhost hosts (e.g., `postgres://...`) hardcoded directly
- **Committing `.env` files themselves** (including `.env.local` / `.env.production`, etc.)
  → Only `.env.example` is allowed

Additionally, the following patterns are blocked by value (`gitleaks` + custom rules `.gitleaks.toml`):

- Stripe live keys (`sk_live_...`)
- OpenAI keys (`sk-...` / `sk-proj-...`)
- Anthropic keys (`sk-ant-...`)
- AWS Access Key IDs (`AKIA...`)
- GCP service account JSON (`"type":"service_account"`)
- Cloudflare API tokens
- GitHub tokens (`ghp_...` / `gho_...` / `ghu_...` / `ghs_...` / `ghr_...`)
- JWT three-segment strings (`eyJ...eyJ...`)
- PEM private key blocks

Example of an allowed pattern:

```ts
/** JWT signing key. Must always be injected via environment variable. Throws at startup if unset. */
const jwtSigningSecret = process.env.JWT_SECRET ?? (() => { throw new Error('JWT_SECRET is not set'); })();
```

### All Descriptions and Comments in $PROJECT_LANG

Read `PROJECT_LANG` from `.my-harness/.config`. Write the following in that language:

- TSDoc / JSDoc / file-level summary comments
- Commit message body, PR descriptions, issue descriptions, review comments

Only proper nouns, type names, command names, and URLs may remain in English.

When `PROJECT_LANG=en`:
- TSDoc: "Creates a user from email and password."
- Commit body: "Add email login feature"
- Error messages: "JWT_SECRET is not set"

When `PROJECT_LANG=ja`:
- TSDoc: "メールアドレスとパスワードからユーザーを作成する"
- Commit body: "メールアドレスでのログイン機能を追加"
- Error messages: "JWT_SECRET が未設定です"

## Design / UX / Accessibility

Reference: <https://www.shokasonjuku.com/ux-psychology>

### Top 10 of 47 Principles (Required)

1. **Hick's Law**: Reduce choices (1 screen, 1 primary action).
2. **Fitts's Law**: Tap targets ≥ 44×44pt; important CTAs within thumb reach.
3. **Miller's Law**: Groupings should not exceed 7 ± 2.
4. **Jakob's Law**: Follow existing conventions (avoid custom UI).
5. **Aesthetic-Usability Effect**: Do not underestimate visual polish.
6. **Peak-End Rule**: Make the final experience (success feedback) thoughtful.
7. **Doherty Threshold**: Action feedback within 400ms.
8. **Contrast**: WCAG AA 4.5:1 (body text) / 3:1 (large text).
9. **Keyboard operation**: Do not remove focus rings; Tab order must be logical.
10. **prefers-reduced-motion**: Always respect it.

### Prohibited (eliminate AI-like appearance)

- Gradients (especially purple → blue → pink), neon, glow, space backgrounds, floating particles.
- Decorative badges such as "AI Powered".

### Icons

- Emoji is prohibited; use `lucide-react` only. `aria-label` is required for icon-only buttons.

## E2E

| Target | Tool | Location |
|--------|------|----------|
| Web | Playwright | `tests/e2e/web/` |
| Mobile | Maestro | `tests/e2e/mobile/*.yaml` |

- Major user flows (signup, login, core CRUD, paywall, billing) must be covered.
- Use a dedicated test DB with seed data. Clean up after tests.
- Save screenshots + video only on failure.

## Reviewer Standards

Reviewer's top priority is **detecting violations of engineer conventions**.

### Checklist (compliance verification)

- [ ] No `any` / `else` / `console.log` / inline comments in function bodies
- [ ] All variables, constants, and functions have JSDoc/TSDoc
- [ ] Naming is self-evident to the reader
- [ ] 1 function = 1 responsibility, nesting ≤ 3 levels
- [ ] Hono follows Clean Architecture 4-layer separation
- [ ] DB operations use Drizzle ORM; `drizzle-kit push` is not used
- [ ] All input is validated with Zod; error messages are in `$PROJECT_LANG`
- [ ] Secrets managed via environment variables; no hardcoded values
- [ ] Lucide Icons used; no emoji, no AI-style design elements
- [ ] Pinned via Nix flake; no impure references
- [ ] Tests cover normal cases, error cases, and boundary values
- [ ] Errors use Result type or custom exceptions; messages are in `$PROJECT_LANG`

If violations are found, request fixes from engineer via analyst.
