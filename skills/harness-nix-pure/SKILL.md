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

## Under /harness-team-lead: use the per-worktree devshell wrapper, do not invoke `nix develop --command`

`/harness-team-lead` Step 0.5 warms the project-root flake. **Each lane teammate then runs `build-dev-env.sh "<their worktree>"` themselves** to get a per-worktree devshell wrapper that reflects any `flake.nix` edits the lane made for the current issue. The script is **content-hash-cached** — second-and-later calls return instantly when the flake content is unchanged, and rebuild automatically when content changes. **Engineers do not run `nix develop --command`.**

```bash
# Right — at the start of every teammate turn:
WORKTREE="<your lane's worktree path>"   # supplied by analyst-N's ASSIGNMENT/REVIEW/TEST message
DEVSH=$(bash "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}/skills/harness-team-lead/scripts/build-dev-env.sh" "$WORKTREE")

cd "$WORKTREE"
"$DEVSH" pnpm install
"$DEVSH" pnpm exec vitest related --run <test>
"$DEVSH" pnpm exec tsc --noEmit
"$DEVSH" pnpm exec biome check . --write
"$DEVSH" git status
"$DEVSH" gh pr create --base dev --title "..."

# Wrong (re-evaluates flake every call, 200+ helper fork per call, 4 lanes × 200 = ~1000 helpers = kernel-watchdog panic):
nix develop --command pnpm install
```

Why a wrapper, not shell-source:

- `nix print-dev-env` emits bash-4+ syntax. macOS bash 3.2 can't parse it; zsh accepts the parse but doesn't execute it as bash; fish has its own syntax entirely. Source is unsound across shells.
- The wrapper's shebang is **nix-provided bash 5+**. It sources the env there, then OS-execs your command. The wrapper itself is callable from bash 3.2 / zsh / fish / sh — any caller shell.
- shellHook side effects (`PNPM_HOME`, `PLAYWRIGHT_BROWSERS_PATH`, `MAESTRO_DRIVER_STARTUP_TIMEOUT`, etc.) are fully evaluated. Verified.

Why per-worktree, not one shared wrapper:

- /nix/store is system-shared (one copy of every derivation), but the **evaluator output** must reflect the lane's current `flake.nix` content. lane-3 editing `flake.nix` as part of an issue must not be forced to use lane-1's stale evaluation.
- Hash-based caching ensures correctness even when two edits happen in the same wall-clock second (mtime-based caching with macOS bash's second-resolution `-nt` would miss this).
- Touching `flake.nix` with no real change does **not** trigger a rebuild — only content changes do.

Why this beats `nix develop --command`:

- The evaluator runs **once per flake-content-version**, not per call. 4 lanes × ~10 commands each → 4 evaluations total (one per lane), not 40.
- Each subsequent invocation is a single nix-bash exec (~5 ms), zero evaluator fork.
- Beats direnv: no `direnv allow` per worktree, no manual user step.

Why `pnpm install` may still need `lane-lock.sh` on first run:

`pnpm install` itself forks worker-pool + per-package install scripts (~50–100 helpers per call). The first install per worktree across 4 lanes is still heavy. Subsequent installs are cache-resolved and cheap. See `agents/harness-engineer.md` for the conditional wrap pattern (`bash $LL pnpm-install "$DEVSH" pnpm install`).

## Fish / zsh users running tools manually

Outside `/harness-team-lead`, you can use the same wrapper for ad-hoc commands. fish syntax:

```fish
set DEVSH (bash $HOME/.claude/plugins/cache/.../my-harness/skills/harness-team-lead/scripts/build-dev-env.sh ./)
$DEVSH pnpm install
$DEVSH git status
```

Or stay with `nix develop --command` for one-shot user invocations — there's no parallel-lane fork-bomb risk in single-shot use.

## Outside /harness-team-lead (one-shot user invocations)

When you run a single command manually, `nix develop --command ...` is fine — there is no parallel-lane fork-bomb risk. The mandatory wrapper pattern above only applies inside an Agent-Teams session.

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
