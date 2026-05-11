# TDD

NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST. If production code was written without a failing test first, **delete the code and rewrite it**. No exceptions.

## Cycle

### RED — failing test
- One test = one behavior.
- Test names follow `$LANG` (read from `.my-harness/.config`, default `en`):
  - `en`: `"should X"` / `"returns Y when Z"`
  - `ja`: `"〜できること"` / `"〜になること"`
- AAA pattern (Arrange / Act / Assert), each section labelled with a comment.
- Mock external dependencies only. Call real code directly.

### Verify RED
```bash
"$DEVSH" pnpm exec vitest related --run <test>
```
Confirm it fails for the **expected** reason. If it passes unexpectedly the test is covering existing behaviour — fix the test.

### GREEN — minimal implementation
Write the **minimum code** to make the test pass. YAGNI.

### Verify GREEN
```bash
"$DEVSH" pnpm exec vitest run
```
All other tests must also be green before moving on.

### REFACTOR
While staying green: improve naming, split functions, add JSDoc/TSDoc. Do not add new behaviour during refactor.

## E2E TDD

For UI / public API changes: write a failing Playwright (web) or Maestro (mobile) test first, confirm red, implement, green.

## Prohibited

- Writing tests after the production code.
- `it.skip` / `test.todo` left in.
- "I verified it works manually" as the only verification.
- `console.log` left in production code.
- Multiple unrelated assertions in one test.

## Done

- [ ] Each new export has a corresponding test.
- [ ] Each test was personally observed failing first.
- [ ] Made green with minimal implementation.
- [ ] biome / tsc / vitest all green, no warnings.
