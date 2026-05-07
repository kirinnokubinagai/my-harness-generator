---
name: harness-tdd
description: Enforces test-driven development (TDD). Must be applied before implementing new features, fixing bugs, refactoring, or changing behavior. Ensures the Red-Green-Refactor cycle is followed and no production code is written without a failing test. Fires when the user says "write a test", "do TDD", "before implementing", "fix a bug", or similar.
---

# harness-tdd

The TDD rules that apply to every production code change under the harness.

## Non-negotiable rule

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.
```

If production code was written without a failing test first, **delete the code and rewrite it**. No exceptions.

## The cycle

### RED (failing test)
Write a failing test that covers exactly one behavior.
- Test names should be in `$LANG` (read from `.my-harness/.config`, default: `en`):
  - If `en`: use the pattern `"should X"` / `"returns Y when Z"` (e.g. `"should create a user"`, `"returns null when user not found"`)
  - If `ja`: use the pattern `"〜できること"` / `"〜になること"` (e.g. `"ユーザーを作成できること"`)
- Use the AAA pattern (Arrange / Act / Assert, each section marked with a comment)
- Mock external dependencies only. Call real code directly.

```bash
LANG=$(grep -E "^LANG=" ".my-harness/.config" 2>/dev/null | cut -d= -f2)
LANG="${LANG:-en}"
```

### Verify RED (required)
```bash
nix develop --command pnpm exec vitest related --run <test>
```
- Confirm the test fails for the expected reason (not a typo)
- If it passes unexpectedly → the test is covering existing behavior. Fix the test.

### GREEN (minimal implementation)
Write the **minimum code** to make the test pass. YAGNI strictly enforced.

### Verify GREEN
```bash
nix develop --command pnpm exec vitest run
```
All other tests must also be green before moving on.

### REFACTOR
While staying green:
- Improve naming
- Split functions
- Add JSDoc/TSDoc (see `harness-jsdoc` skill)

Do not add new behavior during refactor.

## E2E TDD

For changes to UI or public API surfaces, apply the same cycle using Playwright (Web) or Maestro (Mobile):
1. Write a failing E2E test
2. Confirm it is red because the implementation does not exist
3. Implement
4. Green

## Prohibited patterns

- Writing tests after the production code
- Overusing `it.skip` / `test.todo`
- Moving forward with only "I verified it works manually"
- Leaving `console.log` debug statements in code
- Multiple assertions in one test (breaks independence)

## Commands inside the harness

```bash
nix develop --command pnpm exec vitest run                  # All tests
nix develop --command pnpm exec vitest related --run <f>    # Related tests only
nix develop --command pnpm exec playwright test             # Web E2E
nix develop --command maestro test tests/e2e/mobile         # Mobile E2E
```

## Definition of done

- [ ] Each new function / method has a corresponding test
- [ ] Personally witnessed each test failing
- [ ] Made it green with minimal implementation
- [ ] biome / tsc / vitest all green
- [ ] No warnings or errors in the output
