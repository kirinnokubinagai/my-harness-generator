---
name: harness-nix-pure
description: Enforces a fully pure environment via Nix flake. Prohibits impure execution (brew install, global npm, etc.). Requires automatic shell activation via direnv. Fires when the user says "run a command", "install a tool", "set up the environment", or similar.
---

# harness-nix-pure

Every tool invocation under the harness goes through **Nix flake only**. This guarantees that a completely fresh machine can achieve full reproducibility with a single `direnv allow`.

## Non-negotiable rules

| Item | Rule |
|------|------|
| Running tools | Via `nix develop --command ...` only |
| Automation | Add `use flake` to `.envrc`; `direnv allow` switches the shell automatically |
| Exceptions | Apple toolchain (Xcode / iOS Simulator) and Claude Code / Codex CLI only |
| Prohibited | `brew install` / global `npm install -g` / system `pip install` |

## Recommended flow (entering a project)

```bash
cd <project>/dev
direnv allow                          # First time only
# After this, cd-ing into the directory auto-switches to the flake.nix dev shell
node --version                        # Uses Nix's Node.js
pnpm --version                        # Uses Nix's pnpm
```

If direnv is not installed:
```bash
nix develop                           # Manually enter the flake shell
# To keep working after exiting: nix develop --command <cmd>
```

## Standard commands (always use the prefix)

```bash
nix develop --command pnpm install
nix develop --command pnpm exec biome check .
nix develop --command pnpm exec vitest run
nix develop --command pnpm exec tsc --noEmit
nix develop --command pnpm exec wrangler d1 migrations apply DB --local
nix develop --command pnpm exec playwright test
nix develop --command maestro test tests/e2e/mobile
nix develop --command bunx alchemy deploy --stage dev
nix develop --command sops -d secrets/cloudflare.enc.json
```

## Under /harness-team-lead: source the pre-built dev shell, do not invoke `nix develop --command`

`/harness-team-lead` Step 0.5 evaluates the flake once via `nix print-dev-env` and dumps the result to `$ROOT/.my-harness/.harness-devenv.sh`. All four lanes source the same file. **Engineers do not run `nix develop --command`.**

```bash
# Right — once per engineer turn:
source "$ROOT/.my-harness/.harness-devenv.sh"
pnpm install
pnpm exec vitest related --run <test>
pnpm exec tsc --noEmit
pnpm exec biome check . --write

# Wrong (re-evaluates flake every call, 200+ helper fork per call, 4 lanes × 200 = ~1000 helpers = kernel-watchdog panic):
nix develop --command pnpm install
```

Why source-based, not `nix develop --command`:

- The evaluator runs **once per session**, not per call. 4 lanes × ~10 commands each → 1 evaluation, not 40.
- Engineers only pay shell variable assignments on activation: ~10 ms, ~0 fork.
- Beats direnv: no `direnv allow` per worktree, no per-worktree cache, no manual user step.

Why `pnpm install` may still need `lane-lock.sh` on first run:

`pnpm install` itself forks worker-pool + per-package install scripts (~50–100 helpers per call). The first install per worktree across 4 lanes is still heavy. Subsequent installs are cache-resolved and cheap. See `agents/harness-engineer.md` for the conditional wrap pattern.

## Outside /harness-team-lead (one-shot user invocations)

When you run a single command manually, `nix develop --command ...` is fine — there is no parallel-lane fork-bomb risk. The mandatory source pattern above only applies inside an Agent-Teams session.

## Prohibited patterns

- `brew install pnpm` / `brew install nodejs`
- `npm install -g <anything>`
- `pip install --user <anything>`
- Installing tools via `curl ... | bash`
- Using the system's Python / Ruby / Go directly

## When updating flake.nix

```bash
# After editing flake.nix, always commit flake.lock too
git add flake.nix flake.lock .envrc
direnv reload   # Automatically re-evaluates nix develop
```

## Same rules apply in CI

In GitHub Actions:
```yaml
- uses: DeterminateSystems/nix-installer-action@v18
- run: nix develop --command pnpm install
- run: nix develop --command pnpm exec vitest run
```

## Exceptions (Apple / Claude Code / Codex)

- iOS Simulator depends on Xcode and cannot be Nix-ified (see `docs/IOS_DAST.md`)
- Android SDK platform-tools / build-tools are Google-distributed and difficult to Nix-ify
- Claude Code (this agent) and Codex CLI (`@openai/codex`) are interactive AIs and are exempt

## Checklist

- [ ] `.envrc` contains `use flake`
- [ ] `direnv allow` has been run (or shell is entered via `nix develop`)
- [ ] `command -v node | grep nix/store` confirms Nix's node is being used
- [ ] CI runs via `nix develop --command`
