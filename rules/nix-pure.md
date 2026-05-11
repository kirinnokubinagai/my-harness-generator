# Nix-pure environment

Every tool invocation goes through Nix. A fresh machine reaches full reproducibility with one `direnv allow`.

## Rules

| Item | Rule |
|---|---|
| Run tools | Through the per-worktree devshell wrapper (`"$DEVSH" <command>`) |
| Activation | `.envrc` contains `use flake`; `direnv allow` once |
| Exceptions | Apple toolchain (Xcode / iOS Simulator), Android SDK, Claude Code, Codex CLI |
| Prohibited | `brew install`, global `npm install -g`, system `pip install`, `curl ... \| bash` |

## The devshell wrapper (mandatory inside `/harness-team-lead`)

```bash
WORKTREE="<your lane's worktree>"   # supplied by analyst-N's ASSIGNMENT/TEST/REVIEW
DEVSH=$(bash "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}/skills/harness-team-lead/scripts/build-dev-env.sh" "$WORKTREE")

cd "$WORKTREE"
"$DEVSH" pnpm install
"$DEVSH" pnpm exec vitest related --run <test>
"$DEVSH" pnpm exec tsc --noEmit
"$DEVSH" pnpm exec biome check . --write
"$DEVSH" git status
"$DEVSH" gh pr create --base dev --title "..."
```

`nix develop --command` is **prohibited** inside `/harness-team-lead` — it forks 200+ helper processes per call and crashes the kernel watchdog under 4-lane parallel load. The wrapper evaluates the flake once per content-version (sha256 cache) and then OS-execs the command directly.

The wrapper is callable from any caller shell (bash 3.2 / zsh / fish / sh) because it's an OS exec, not a shell-source.

## Outside `/harness-team-lead` (one-shot user invocations)

`nix develop --command <cmd>` is fine — there's no parallel-lane fork-bomb risk in single-shot use.

## When updating `flake.nix`

```bash
git add flake.nix flake.lock .envrc
direnv reload
```

`flake.lock` MUST be committed alongside `flake.nix`.

## CI

```yaml
- uses: DeterminateSystems/nix-installer-action@v18
- run: nix develop --command pnpm install
- run: nix develop --command pnpm exec vitest run
```

## Done

- [ ] `.envrc` contains `use flake`
- [ ] `direnv allow` has run (or `nix develop` shell entered)
- [ ] `command -v node | grep nix/store` confirms Nix's node is in use
- [ ] Inside `/harness-team-lead` runs use `"$DEVSH" <cmd>`, not `nix develop --command`
