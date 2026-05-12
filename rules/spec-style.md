# Spec Style — specs describe WHAT, not HOW

Spec files (`dev/docs/spec/*.md`, `dev/docs/talk/*.md`, `init-state.json`'s `discoverySheet`, `dev/.my-harness/rules/*.md` outputs Claude produces during interview phases) describe **what the system does and the constraints it must honor**. They do NOT include implementation code. Implementation is Codex's job, and Codex must be free to choose the right code for the chosen frameworks/tools — not be anchored to a Claude-written snippet.

## Specs INCLUDE

- Requirements ("user can log in with email + password")
- API contracts ("`POST /api/auth/login` accepts `{email, password}` and returns `{token, user}`")
- Data model ("User has email, password_hash, created_at, last_login_at")
- UI flows ("Login → on success → Home; on failure → Login with inline error")
- Behavioral constraints ("password hashing uses bcrypt cost ≥ 12")
- State transitions ("Order: pending → paid → shipped → delivered; cancellable from any state except delivered")
- Acceptance criteria ("login form rejects empty email with a labeled error before hitting the API")
- Non-functional limits ("login endpoint: 10 req/min/IP rate limit; 250 ms p95 latency target")

## Specs do NOT include

- TypeScript / JavaScript / Bash / SQL / Python / Go / Rust / etc. code blocks
- React / Vue / Svelte component code ("`<Button onClick={...}>`")
- Tailwind class strings as code (`<div className="bg-primary-500 hover:...">`)
- Framework calls (`drizzle.insert(users).values({...})`, `app.post('/api/...', ...)`, `Z.object({...})`)
- Specific Tailwind utility values that are implementation choices (`max-w-7xl`, `text-neutral-900`) — describe the visual intent instead
- Library API references with concrete syntax (`bcrypt.hash(password, 12)`, `jwt.sign({...}, secret)`)
- Configuration file contents (`.toml`, `.yml`, `.json` config blocks)
- Tooling / CLI commands (`pnpm test`, `playwright test --grep`, `drizzle-kit generate`)

### Why this rule exists

Specs are **decision artifacts** that the implementation phase (= Codex) must be free to realize correctly. When the spec embeds code:

- Codex anchors on that code instead of choosing what's right for the actual codebase
- The spec becomes coupled to one implementation choice; switching frameworks means rewriting the spec
- Reviewers diff spec changes alongside code changes, doubling the review surface
- The spec rots when refactors land but the embedded snippets don't get updated alongside

The spec must survive a framework swap (Hono → Fastify → Express, Drizzle → Prisma → raw SQL) **without rewriting**. If it can't, it had implementation details in it.

## When "code-looking strings" ARE okay

These look like code but ARE legitimate spec content because they define the contract itself, not the implementation:

- **API path strings** — `POST /api/auth/login` (this IS the contract)
- **HTTP status codes** — `422 VALIDATION_FAILED`, `401 AUTH_REQUIRED` (same)
- **Hex colors** when the brand identity locks them in — `#14b8a6` (design-system decision)
- **Numeric thresholds** — `bcrypt cost ≥ 12`, `rate limit 100/min`, `max upload 25 MB` (constraints)
- **Identifiers in the data model** — `User.email`, `Order.status` (the names ARE the data shape)
- **JSON shapes for request/response examples** (`{"success": true, "data": {...}}`) — these ARE the contract

The distinction: **abstract identifiers + values that define the contract** stay. **Code that implements the contract** does not.

## Translating "code-like" requirements

When you find yourself wanting to write code in a spec, translate to the equivalent constraint:

| Don't write | Do write |
|---|---|
| `const user = await db.users.findFirst({ where: eq(users.email, email) });` | "Login lookup: find a user record by email (case-insensitive match)." |
| `import bcrypt; bcrypt.hash(password, 12);` | "Passwords are hashed with bcrypt, cost factor ≥ 12, before persistence." |
| `<button className="bg-primary-500 hover:bg-primary-600 px-4 py-2 rounded">` | "Primary button: brand `primary` background, hover darkens one shade, comfortable touch target on mobile." |
| `setTimeout(() => fetch(...), 3000);` | "Search debounce: 300 ms after the user stops typing before issuing the request." |
| `if (user.role === 'admin') ...` | "Only users with role `admin` can perform action X." |

Translation is from **WHAT code to run** to **WHAT behavior must result**.

## Diagrams / pseudo-code / state machines ARE okay

These are NOT code:

- Mermaid / ASCII state diagrams
- Sequence diagrams (Mermaid `sequenceDiagram`)
- Plain English / pseudo-code describing an algorithm at the level of "for each user, send a welcome email if `last_login < created_at + 24h`"

They ARE encouraged when prose alone is ambiguous.

The boundary is **executable syntax in a programming language**, not "anything that looks formal". Mermaid diagrams and pseudo-code stay above the boundary.

## When this rule does NOT apply

- `rules/*.md` files that describe **coding standards** (`coding-standards.md`, `tdd.md`, `drizzle.md`, etc.) — they intentionally show the right and wrong code, that IS their purpose. They are NOT specs; they are guidelines applied during implementation.
- `dev/AGENTS.md` / `dev/CLAUDE.md` — likewise instruction documents for AI agents, may show examples.
- Auto-generated artifacts (e.g., OpenAPI specs derived from code, type definitions emitted by tools) — they originate from code by definition.

The rule applies to **decision-recording** documents Claude produces during Phase 2-8 of `/my-harness-init`.
