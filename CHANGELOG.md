# Changelog

All notable changes documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [7.34.2] — 2026-05-16

### Added — per-turn JSONL diagnostics for the Phase-5 image pipeline

**7.34.1 actually worked — verified by evidence, not assumption.** The user's project has `dev/docs/design/page-pc-home.png` at **1,463,553 bytes, mtime 2026-05-16 19:02:30** — generated **11 minutes after the 7.34.1 commit (18:51:29)**. Turn 1a (image-only) succeeds: `image_gen` produces the real 1.4 MB page mock. "PNG creation failed" was a misread.

What actually did not complete: there is **no `manifest.json` and `parts/` is empty**, and the user's run log showed **`(timeout 5m)`**. The most likely cause is NOT a Turn 1b code bug but the run hitting the 5-minute timeout: a single `image_gen` turn is slow, and the invocation attempted 28 screens × (PC + Mobile) in one timeboxed call, so the process was killed at/just after the first screen's Turn 1a — Turn 1b (and screens 2..28) never ran.

This release does **not** guess-patch Turn 1b (no evidence yet = no fix, per systematic-debugging). It adds evidence collection so the next run is diagnosable from facts:

- `scripts/gen-page-parts.sh`: every Turn 1a / 1b `codex-ask.sh` call (first attempt + retries) now passes `--log` → a full JSONL event stream at `.my-harness/codex-1a-<ff>-<slug>.jsonl` and `.my-harness/codex-1b-<ff>-<slug>.jsonl`. Reveals per turn: was `image_generation_call` emitted, what `agent_message` text returned, how `codex-app-server-call.py` classified the turn. Retries overwrite the same path (final failed attempt is what matters for root-cause).

### Verified
- `bash -n scripts/gen-page-parts.sh` → syntax OK; 4 `--log` lines wired (1a first/retry, 1b first/retry).

### Verification scope (honest)
This is **instrumentation, not a fix**. Turn 1b's real behaviour is still unproven because the prior run never reached it (timeout). Next step: run a SINGLE screen with NO timeout (or a generous one); the two JSONL files then show exactly what Turn 1a and Turn 1b did. **Do not run all 56 screens under a 5-minute timeout** — `image_gen` is minutes per turn.

## [7.34.1] — 2026-05-16

### Fixed — Phase-5 image pipeline: Turn 1 split into 1a (image) + 1b (JSON)

**Symptom (user-reported):** `$imagegen` + page-mock + JSON-manifest in one Codex turn failed with exit 1 after 3 retries, while a plain image_gen call succeeded.

**Root cause (found by reading the code, not guessing):** `prompts/codex-page-mock.md` required Codex to make an `image_gen` tool call **and** emit a JSON manifest as `agent_message` text **in the same turn**. `scripts/codex-app-server-call.py`'s own comment (~L289-294) documents that Codex returns **no agent_message on an image_gen turn** — the entire Phase-5 flow depends on image-only turns being empty-text. So "image + JSON in one turn" produced neither, the classify branch at L335-337 (`if not text and not images: return 1`) fired → exit 1, and retrying the same self-contradictory request merely exhausted the 3 attempts. A plain image_gen call worked precisely because it did *not* also demand JSON text in the same turn.

**Fix (root, not symptom):** the turn is now two single-responsibility turns in the same Codex session:
- `prompts/codex-page-mock.md` (rewritten): **image only** — one `image_gen` call, no JSON. Explicitly states the JSON is asked for in a separate follow-up turn.
- `prompts/codex-page-manifest.md` (new): **text only** — describe the just-generated image as exactly one ```json block; `image_gen` explicitly forbidden. Same session, so Codex still has the 1a image in conversation context.
- `scripts/gen-page-parts.sh`: Turn 1 is now Turn 1a (retry on `is_png $OUT_PAGE` only) → Turn 1b (retry on `extract_manifest` only), same `$SESSION_KEY`. Everything from `IMG_COUNT` onward is unchanged (still reads `$MANIFEST_JSON`).

### Verified
- `bash -n scripts/gen-page-parts.sh` → syntax OK.
- Variable continuity confirmed: no stale `TURN1_RESPONSE`/`TURN1_MAX_RETRY`/`TURN1_RETRY`; `MANIFEST_JSON` is still produced by Turn 1b and consumed unchanged by `IMG_COUNT` / `OUT_MANIFEST` / Turn 2..N.

### Verification scope (honest)
Syntax + variable-flow only. The actual Codex pipeline was **NOT executed** — there is no Codex auth in this environment (same constraint as the OCI work). Whether Codex's image-only Turn 1a reliably saves to `$OUT_PAGE`, and whether the text-only Turn 1b reliably emits the JSON while seeing the 1a image in session context, is a real-Codex layer confirmable only by running `/my-harness-init` Phase 5 against live Codex. The fix is grounded in `codex-app-server-call.py`'s own documented turn-classification behaviour; the design contradiction it removes is concrete and code-evidenced.

## [7.34.0] — 2026-05-16

### Added — OCI billing alert + free-tier maximum spec

Two user requests: (1) alert when OCI charges anything beyond Always Free, to the configured Discord/Slack; (2) make the VM the Always-Free maximum.

**Honest constraint (stated up front — in the Q9.9 prompt and here):** OCI billing data updates on a **~24h cycle**; the Usage API is officially unsupported on non-metered (Always Free) tenancies. There is **no real-time billing alert on Always Free** — ~24h is OCI's structural floor, not fixable here. Researched against OCI docs, not assumed.

#### Billing alert (researcher-confirmed architecture)
- `scripts/ensure-oci-billing-alert.sh` (new): idempotently creates an OCI Budget ($1, MONTHLY, target=tenancy) + Alert Rule (ACTUAL, 1% ≈ $0.01, recipients=email). For chat/both it also creates a dynamic-group + policy (`read budgets in tenancy`) so the VM's instance principal can read actual-spend. Everything looked up by name → safe to re-run.
- `templates/oracle-cloud/nixos/services/billing-check.nix` (new, `mkIf harness.billingCheckEnabled`): daily systemd timer → reads budget actual-spend via `OCI_CLI_AUTH=instance_principal`, posts via the existing `post-notification.sh` (discord/slack/teams — the **same webhook the daily-progress bot already uses, so Discord works with no relay**). De-dupes one alert per month.
- `templates/oracle-cloud/daily-progress-bot/billing-check.sh` (new): the poll+notify script.
- Why this shape: OCI Budget Alert Rules deliver **email only** (no ONS-topic field — confirmed in the Terraform `oci` provider + Budgets docs), and ONS has no native Discord protocol plus a confirmation handshake Discord rejects. The email path (lives entirely in OCI, VM-independent) is the **mandatory backup in every mode**; the VM poll is what reaches chat. ONS / Monitoring-alarm / OCI-Functions all turned out unnecessary.
- `configuration.nix`: `harness.billingCheckEnabled` option + `./services/billing-check.nix` import. `home.nix`: places `billing-check.sh`.
- `setup-oci-vm-nixos.sh`: `BILLING_ALERT_MODE` (off|email|chat|both) gate; runs `ensure-oci-billing-alert.sh`; merges `harness.billingCheckEnabled = true` into the harness-overlay (same merge-or-create pattern as the Tailscale overlay); writes `BILLING_BUDGET_OCID` into the VM `.env`.
- `skills/my-harness-init/SKILL.md` Q9.9 (bilingual): "Email + chat / Email only / No billing alert". The ~24h limitation is shown verbatim before the question. Chat reuses the existing Q6 webhook — no new webhook asked. "Email + chat" on a non-NixOS VM degrades to email only (billing-check.nix is NixOS-only; the OCI Budget email still works).

#### Free-tier maximum spec
- `scripts/ensure-oci-vm.sh`: added `--boot-volume-size-in-gbs 200`. CPU/RAM were already at the Always Free max (`ocpus:4, memoryInGBs:24`); the boot volume was defaulting to ~47 GB. 200 GB = the full Always Free Boot+Block allowance (no separate block volume is created, so it stays free). `disko.nix` is `root="100%"` so `/` auto-expands to ~199 GB.

### Verified
- `nix flake check --no-build` → **`all checks passed!`** after wiring `billing-check.nix` + the option/import (the standard git-untracked-file gate appeared first; `git add` then passed — same as prior releases). Validates the systemd unit/timer structure, the `mkIf` conditional, and that `pkgs.oci-cli` / `bc` / `coreutils` resolve.

### Verification scope (honest — unchanged discipline)
`nix flake check` is eval-level (NixOS side only). It does **NOT** prove the OCI side: there is no OCI account here and `oci budgets` was **never executed**. Unconfirmed until a real deploy: (a) whether `oci budgets budget get` actual-spend returns a value on an Always Free (non-metered) tenancy — OCI docs do not explicitly guarantee it; (b) the exact `oci budgets alert-rule create --recipients` argument form across CLI versions; (c) that Budget creation is accepted on a pure Always Free account. The code follows the official-docs research (two researcher passes, citations in those reports); the OCI API behaviour is a real-VM layer. And regardless of code: detection is **~24h, never real-time** — that is an OCI limitation, not a defect here.

## [7.33.0] — 2026-05-16

### Changed — all 5 self-built Nix derivations replaced by numtide/llm-agents.nix

The OCI NixOS host built claude-code, codex, cli-proxy-api, hermes-agent and openclaw from scratch via 5 hand-maintained derivations under `templates/oracle-cloud/nixos/pkgs/`. Three carried `lib.fakeHash` placeholders (vendorHash / npmDepsHash) that only resolve on the *first* `nixos-rebuild switch` error — the long-standing **#2 concern**. `hermes-agent-fhs.nix` was a 167-line `buildFHSEnv` that, on every first start, ghq-cloned the repo at a pinned tag, ran `uv venv` + `uv pip install --editable .[messaging,voice]`, and seeded PYTHONPATH with ~25 hand-listed nixpkgs Python deps (Hermes is not on PyPI; 3 deps absent from nixpkgs 25.05).

[numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix) packages all 5 (and 90+ other agents), aarch64-linux, **daily auto-updated upstream**, served prebuilt from `https://cache.numtide.com`. This eliminates the fakeHash class of bug entirely and removes ~250 lines of fragile, weekly-rotting packaging.

### Added
- `templates/oracle-cloud/flake.nix`: input `llm-agents.url = "github:numtide/llm-agents.nix"` (deliberately **not** `inputs.nixpkgs.follows = "nixpkgs"` — keeping numtide's pinned nixpkgs is precisely what makes the binary cache hit; following ours would force a full from-source rebuild of every agent on every deploy). A `{ nixpkgs.overlays = [ llm-agents.overlays.default ]; }` module exposes `pkgs.llm-agents.<name>`.
- `configuration.nix`: `nix.settings.extra-substituters = [ "https://cache.numtide.com" ]` + `extra-trusted-public-keys` (numtide `niks3` key) so `nixos-rebuild` does not compile any agent from source.
- CLI tools default set added to `environment.systemPackages`: `bat eza yq delta tldr` (joining the existing curl/jq/gh/git/tmux/htop/vim/ripgrep/fzf/ghq) — interactive SSH sessions on the VM are now actually pleasant.

### Changed
- `configuration.nix`: removed the `let claude-code/openai-codex = pkgs.callPackage ./pkgs/…` bindings; `systemPackages` now uses `pkgs.llm-agents.claude-code` + `pkgs.llm-agents.codex`. `allowUnfreePredicate` widened to `[ "claude-code" "codex" "openai-codex" ]` (numtide's claude-code/codex are unfree; the legacy self-built pname is kept for robustness).
- `services/cliproxyapi.nix` → `lib.getExe pkgs.llm-agents.cli-proxy-api` (binary name unchanged: `cli-proxy-api`).
- `services/openclaw.nix` → `lib.getExe pkgs.llm-agents.openclaw`.
- `services/hermes-agent.nix`: the entire FHS launcher is gone. numtide's `hermes-agent` is a self-contained binary (`meta.mainProgram = "hermes"`). `ExecStartPre` now only symlinks the scp'd `/home/opc/hermes-agent/config.yaml` into Hermes's default discovery path `~/.hermes/config.yaml` (the one thing the old launcher did that systemd still must); `ExecStart = hermes gateway start --foreground` (a Hermes-native subcommand, unchanged from the old launcher's final exec). `/var/lib/hermes` (git checkout + venv) is gone — no mutable state to persist. `TimeoutStartSec` 15min → 5min (no clone/install on start).
- `setup-oci-vm-nixos.sh`: comments + deploy-time `echo`s updated — they no longer print "First-run will git clone + uv install" (which was about to show false info to every user).

### Removed
- `templates/oracle-cloud/nixos/pkgs/{claude-code,openai-codex,cliproxyapi,hermes-agent-fhs,openclaw}.nix` (5 files, ~250 lines incl. 3 `lib.fakeHash` placeholders + a 167-line `buildFHSEnv`). The `pkgs/` directory no longer exists.

### Verified
Confirmed via real `nix` commands here (not assumed):
- `nix flake lock` resolved `llm-agents` (rev `44e88554`, 2026-05-16) + its full closure.
- `nix eval …#packages.aarch64-linux` confirmed exact attr names + `meta.mainProgram`: `claude-code`→`claude`, `codex`→`codex`, `cli-proxy-api`→`cli-proxy-api`, `hermes-agent`→`hermes`, `openclaw`→`openclaw` (all have `mainProgram` → `lib.getExe` is safe, no hard-coded `/bin/` paths).
- `nix flake check --no-build` → **`all checks passed!`** (overlay wiring, module structure, the widened unfree predicate, every service module's `lib.getExe`).

### Verification scope (honest)
`nix flake check` is eval-level. It does NOT prove: (a) the numtide binary cache actually serves an aarch64-linux build for every agent at deploy time — if a cache entry is missing, that agent builds from numtide's pinned nixpkgs (slow, but correct, not broken); (b) runtime — whether numtide's `hermes` reads `~/.hermes/config.yaml` the way the old launcher's symlink assumed, and whether it accepts `gateway start --foreground` identically. Those need a real VM. **But the fakeHash class (#2 concern) is now structurally impossible**, and ~250 lines of weekly-rotting packaging are gone.

## [7.32.1] — 2026-05-16

### Changed — Hermes install uses `ghq get` instead of ad-hoc `git clone`

User policy: repositories must be cloned via `ghq` so they live under a predictable `$GHQ_ROOT/github.com/<owner>/<repo>` path, not scattered ad-hoc `git clone` directories.

- `templates/oracle-cloud/nixos/pkgs/hermes-agent-fhs.nix`:
  - Launcher's first-run install changed from `git clone --branch <tag> https://github.com/NousResearch/hermes-agent.git /var/lib/hermes/hermes-agent` to `ghq get https://github.com/NousResearch/hermes-agent.git` with `GHQ_ROOT=/var/lib/hermes/ghq`. The repo now lives at `/var/lib/hermes/ghq/github.com/NousResearch/hermes-agent`. Tag pinning (`v2026.5.7`) is still done via an explicit `git checkout` after the clone (ghq manages *where* repos live, not *which* ref).
  - `ghq` added to the buildFHSEnv `targetPkgs` so the launcher can call it.
- `templates/oracle-cloud/nixos/home.nix`:
  - `export GHQ_ROOT="$HOME/ghq"` added to bash so interactive-SSH `ghq get` is consistent with the Hermes systemd checkout layout.
  - NOTE: home-manager 25.05 has **no** `programs.ghq` module (verified — `nix flake check` rejected `programs.ghq` with "option does not exist"). ghq is configured purely via the binary (in `configuration.nix` `environment.systemPackages` since 7.29.1) + the `GHQ_ROOT` env var.

### Verified
`nix flake check --no-build` run after each change — `all checks passed!`. The non-existent `programs.ghq` module was caught by flake check before any deploy (same eval-level validation that found the 7.32.0.1 bugs).

## [7.32.0.1] — 2026-05-16

### Fixed — 4 NixOS evaluation bugs found by running `nix flake check` locally

The OCI NixOS config had **never been validated**. Running `nix flake check --no-build` against `templates/oracle-cloud/` surfaced 4 fatal evaluation errors, each fixed here. `nix flake check` now reports `all checks passed!`.

1. **`configuration.nix` module structure** (7.32.0 regression): adding top-level `options.harness.*` (7.32.0's tailscaleEnabled) made the module system reject the bare `boot`/`networking`/`services`/… attributes. All config attributes are now nested under `config = { … }`; `imports` and `options` stay top-level.
2. **`imports` infinite recursion** (latent since **7.27.0**): `imports = [ … ] ++ lib.optional config.harness.X ./services/Y.nix` referenced `config` to compute `imports`, and `config` needs `imports` → infinite recursion. **Every NixOS deploy since 7.27.0 (Hermes integration) would have failed** — it was simply never run. Fixed by importing all service modules unconditionally and wrapping each conditional module's body in `config = lib.mkIf config.harness.X { … }` (the correct NixOS conditional-module pattern).
3. **Unfree license refused** (latent since 7.29.2): `claude-code` / `openai-codex` derivations are `licenses.unfree`; NixOS refuses unfree by default. Added a scoped `nixpkgs.config.allowUnfreePredicate` that allows ONLY those two — all other unfree packages still refused.
4. **`keyFiles` absolute path in pure eval** (latent since 7.24.0): `openssh.authorizedKeys.keyFiles = ["/etc/ssh/authorized_keys.d/opc"]` is read at eval time and forbidden in pure mode, breaking `nix flake check` and hiding downstream bugs. Switched the template to a literal `keys` placeholder; `setup-oci-vm-nixos.sh`'s injection regex updated from `keyFiles` to `keys` (still replaces it with the real pubkey at deploy time, but the template is now pure-eval clean).

Also: `daily-progress.nix` no longer redeclares `options.harness.hermesAgentEnabled` (duplicate of configuration.nix's declaration — now read-only via the `hermesEnabled` let-binding). `hermes-agent.nix` / `openclaw.nix` / `tailscale.nix` bodies wrapped in `config = lib.mkIf config.harness.X { }`. `templates/oracle-cloud/flake.lock` committed (pins nixpkgs for reproducible deploys).

### Verification scope (honest)
`nix flake check --no-build` validates **eval-level correctness** (syntax, types, module structure). It does NOT cover: (a) the `lib.fakeHash` placeholders in `pkgs/cliproxyapi.nix` / `claude-code.nix` / `openai-codex.nix` — those still need the real hash from the first `nixos-rebuild switch` error (designed behaviour since 7.29.0); (b) runtime behaviour (does Hermes actually reach Discord, does daily-report actually post). Those are separate layers requiring a real VM. But the "deploy fails 4 times in a row before it even starts" class of problem is now eliminated.

## [7.32.0] — 2026-05-16

### Security audit + hardening

A full security audit of the generated OCI VM found: SSH open to 0.0.0.0/0, no fail2ban, no automatic security updates, sudo NOPASSWD with no wheel restriction. This release closes all of them, with Tailscale as the strongest single fix.

### Added
- `templates/oracle-cloud/nixos/services/security.nix` (new, always imported):
  - `services.fail2ban` — 3-strike SSH jail with escalating ban (2× up to 1 week).
  - `system.autoUpgrade` — weekly, `allowReboot = false` (never auto-reboots the headless bot host; reboot-needing kernel updates surface in journal).
  - Extra SSH hardening: `MaxAuthTries=3`, `LoginGraceTime=20`, `KbdInteractiveAuthentication=false`, `ClientAliveInterval=300`, no TCP/agent/X11 forwarding.
  - `security.sudo.execWheelOnly = true` (NOPASSWD kept — setup scripts depend on it — but only wheel can sudo).
  - Conservative sysctl hardening (rp_filter, tcp_syncookies, kptr_restrict, dmesg_restrict).
- `templates/oracle-cloud/nixos/services/tailscale.nix` (new, conditional on `harness.tailscaleEnabled`):
  - `services.tailscale.enable` + `authKeyFile = /home/opc/.tailscale-authkey` (non-interactive headless join).
  - `extraUpFlags = ["--ssh" "--accept-dns=false" "--hostname=harness-oci"]`, `useRoutingFeatures = "server"`.
  - Firewall: UDP 41641 + trusted `tailscale0` interface. State persists at /var/lib/tailscale.
- `scripts/ensure-tailscale-authkey.sh` (new) — captures the user's tagged auth key (validates `tskey-auth-...` shape) → `.my-harness/.tailscale-authkey` (chmod 600).
- `skills/my-harness-init/SKILL.md` Q9.8 (Tailscale, bilingual, recommended) + a "⚠️ Leaked credential remediation" section listing how to revoke/regenerate every credential type (Claude OAuth, GitHub PAT, Discord webhook, Codex auth, Tailscale key) — the harness cannot revoke them; only the user can.

### Changed
- `templates/oracle-cloud/nixos/configuration.nix` always imports `security.nix`; conditionally imports `tailscale.nix` via the new `harness.tailscaleEnabled` option (mirrors `harness.hermesAgentEnabled` from 7.27.0).
- `scripts/setup-oci-vm-nixos.sh`: when `TAILSCALE_ENABLED=yes`, scp's the auth key, sets `harness.tailscaleEnabled = true`, and — only AFTER verifying Tailscale SSH connectivity works — closes SSH port 22 in the OCI Security List (fail-safe: if Tailscale check fails, port 22 stays open and the user is warned, so we never lock ourselves out).
- `scripts/ensure-oci-vm.sh`: new `OCI_SSH_SOURCE_CIDR` env (default `0.0.0.0/0`; set to `<my-ip>/32` to restrict). Adds a UDP 41641 ingress rule (harmless when Tailscale off, required when on).

### Rationale
Defense in depth. With Tailscale ON the public SSH attack surface is removed entirely (port 22 closed at the cloud Security List; the VM is only reachable inside the user's private Tailnet) — this is strictly better than fail2ban, which only slows brute-force on a still-public port. fail2ban + sysctl + SSH hardening remain as the baseline for users who decline Tailscale. Tailscale requires a free Tailscale account and a manually-generated **tagged, non-reusable, non-ephemeral** auth key (cannot be automated — it's account-bound); SKILL.md Q9.8 walks the user through it.

### Note
- The biggest real-world risk surfaced by the audit is not harness code but credentials that were pasted into chat / committed during this project's development. The new SKILL.md "Leaked credential remediation" section documents the revoke steps; the user must perform them.

## [7.31.0.1] — 2026-05-16

### Fixed
- `scripts/codex-ask.sh` now forwards `--disable-plugin <id>` (repeatable) to `codex-app-server-call.py`. Previously codex-ask.sh only passed `--model` / `--log-file`, so callers had no per-call way to disable a Codex plugin through the wrapper — the only escape was editing `~/.codex/config.toml` by hand (persistent, breaks other Codex uses).
- `scripts/gen-page-parts.sh` now passes `--disable-plugin "cloudflare@openai-curated"` on every Phase 5 image_gen codex-ask.sh invocation. The cloudflare plugin was observed to interfere with image_gen turns, which led Claude sessions to hand-edit config.toml. Now disabled PER-CALL (config.toml untouched).
- `scripts/codex-ask.sh` reasoning-model warning text updated: "GPT-5 / GPT-4o" → "GPT-5.5 — the Codex default since 2026-04-23" (doc accuracy; GPT-5.5 rolled out 2026-04-23).

### Added
- HARD RULE 5 in `skills/my-harness-init/SKILL.md`: never hand-edit `~/.codex/config.toml` to toggle plugins; use `codex-ask.sh --disable-plugin` (per-call, non-destructive) or `$MY_HARNESS_CODEX_DISABLE_PLUGINS`.
- `hooks/guard-codex-direct.sh` second detection arm: blocks Bash-level edits of `~/.codex/config.toml` (sed -i / >> / tee / dd) with the same escape hatch as the codex-direct guard.

### Rationale
A user observed a Claude session repeatedly doing `Update(~/.codex/config.toml)` to flip `cloudflare@openai-curated` `enabled = true → false` before each Phase 5 image_gen run. Investigation showed: (1) the cloudflare plugin genuinely interferes with image_gen; (2) the harness had a per-call disable mechanism in codex-app-server-call.py but codex-ask.sh didn't expose it; (3) so the only path Claude found was hand-editing the global config, which persists and breaks Codex elsewhere. This patch closes the gap end-to-end: the wrapper forwards --disable-plugin, Phase 5 uses it automatically, the rule is documented at the top of SKILL.md, and the hook blocks the bad pattern technically.

Codex model selection unchanged — Phase 5 still delegates to the Codex CLI default (GPT-5.5 as of 2026-04-23), per decision (a). No explicit --model is added (would re-introduce the 7.29.3.1 reasoning-model footgun).

## [7.31.0] — 2026-05-15

### Added
- Phase 1 Setup Q5.5 (NEW): "Default Claude Code model for this project". Writes `PROJECT_CLAUDE_MODEL` to `.my-harness/.config`; bootstrap.sh reads it instead of the previous hardcoded `claude-opus-4-6`. Choices: claude-opus-4-7 (recommended) / claude-sonnet-4-6 / claude-opus-4-6 / claude-haiku-4-5.
- Q11 rewritten as 5-model selection (claude-sonnet-4-6, claude-opus-4-7, claude-opus-4-6, gpt-5.5, gpt-5.4-mini). Replaces the previous "claude vs codex" 2-choice. Persisted as `AI_MODEL=<choice>` in `.notification.env`.
- Q12.6 sub-questions updated: claude-code branch now offers `claude-opus-4-7`; codex branch now offers `gpt-5.5`. Both bilingual.

### Changed
- `templates/oracle-cloud/cliproxyapi/config.example.yaml` enables BOTH `codex` and `claude-code` OAuth providers simultaneously (was mutually exclusive). 5 model aliases declared explicitly so daily-progress / Hermes / OpenClaw can switch via `{"model": "..."}` request body.
- `templates/oracle-cloud/daily-progress-bot/lib/ai-provider.sh` rewritten as a single curl to CLIProxyAPI on `${CLIPROXY_URL:-http://localhost:8317}` with `${AI_MODEL}` in the request body. Provider-agnostic.
- `templates/oracle-cloud/daily-progress-bot/.env.example` `AI_PROVIDER=claude|codex` replaced by `AI_MODEL=<5-choice>` with documented options + recommended default.
- `scripts/setup-oci-vm-nixos.sh` and `scripts/setup-oci-vm.sh` deploy CLIProxyAPI always (both auth files scp'd if present locally). Legacy `AI_PROVIDER=claude|codex` env auto-translated to `AI_MODEL=claude-sonnet-4-6` or `AI_MODEL=gpt-5.5` with a stderr warning.
- `scripts/bootstrap.sh` reads `PROJECT_CLAUDE_MODEL` from `.my-harness/.config` instead of hardcoding `claude-opus-4-6`. Fallback default is now `claude-opus-4-7` (was `claude-opus-4-6`).

### Verified model availability (2026-05)
- Anthropic: claude-opus-4-7 (latest GA), claude-sonnet-4-6 (current), claude-opus-4-6 (legacy, supported). Source: docs.claude.com/en/about-claude/models/overview.
- OpenAI: gpt-5.5 (rolled out 2026-04-23 to Plus/Pro/Business/Enterprise + Codex), gpt-5.4-mini (previous gen, still available). Source: openai.com/index/introducing-gpt-5-5/.

### Backward compatibility
- `.notification.env` from 7.22.0–7.30.x with `AI_PROVIDER=claude|codex` is auto-translated to `AI_MODEL=<default>` on the first 7.31.0 setup-oci-vm-nixos.sh run. Re-run /my-harness-init Q11 for explicit selection.
- `dev/.claude/settings.json` already-existing with `model` field is NOT overwritten (`.model // $m` jq guard preserves user customization, unchanged behavior).

## [7.30.0.1] — 2026-05-15

### Added
- `skills/my-harness-init/SKILL.md` gains a top-level **HARD RULES** section (4 rules) at the very top of the file — the first thing any Claude session reading SKILL.md encounters. The four rules consolidate the absolute prohibitions established in 7.21.0, 7.29.2.1, 7.29.3.1 and add two new ones:
  - Rule 3: Never propose `OPENAI_API_KEY` (subscription auth only, per 7.22.0).
  - Rule 4: Never call `codex exec` / `codex chat` / `codex app-server` directly; always go through `scripts/codex-ask.sh`.
- `hooks/guard-codex-direct.sh` (new file, first under `hooks/`) — a Claude Code PreToolUse hook that detects and BLOCKS direct codex CLI invocations at the Bash-tool level. Reads the tool input JSON from stdin, matches `codex (exec|chat|run|app-server|message)`, and exits 2 (block) unless `HARNESS_ALLOW_DIRECT_CODEX=yes` is set. Optional install via `~/.claude/settings.json`; instructions in SKILL.md Q12.11.
- `scripts/codex-ask.sh` auth-error translation: when Codex's stderr mentions `OPENAI_API_KEY` and the command exits non-zero, the wrapper prepends an explicit "IGNORE that hint, refresh subscription auth instead" block — surfacing HARD RULE 3 to Claude on the spot.
- SKILL.md Q12.11 (new, optional, bilingual) asks the user whether to install the PreToolUse hook. Default = install.

### Rationale
Two real Claude-session incidents motivated this patch:

1. A session ran `codex exec -s danger-full-access -C <dir> "..."` directly, bypassing every harness defense (reasoning-model guard, retry, error translation).
2. Another session proposed `! export OPENAI_API_KEY="sk-..."` despite the 7.22.0 user decision against API keys.

Both incidents indicated that documentation in deep SKILL.md subsections wasn't being read. The fix is three-pronged:
- Move all prohibitions to a top-of-file HARD RULES block that any Claude session must encounter early.
- Translate Codex's own misleading error hint at the harness wrapper layer.
- Provide a technical PreToolUse hook for users who want enforcement, not just suggestion.

This concludes 7.30.x. The staged release plan (7.22.0 → 7.30.0) was structured improvements; 7.30.0.1 is the hardening pass for the documented-but-bypassable rules.

## [7.30.0] — 2026-05-15

### Added
- **OpenClaw integration** as a Hermes alternative. Phase 1 Setup Q12.5's OpenClaw option is no longer a placeholder; selecting it deploys OpenClaw on the VM with the same 4-provider AI matrix (codex / claude-code / openrouter / claude-api) and the same daily-report agent-cron migration as Hermes.
- `templates/oracle-cloud/nixos/pkgs/openclaw.nix` (new) — Nix-packaged OpenClaw.
- `templates/oracle-cloud/nixos/services/openclaw.nix` (new) — systemd service module, conditional on `harness.openClawEnabled` (mirrors `harness.hermesAgentEnabled` from 7.27.0).
- `templates/oracle-cloud/openclaw/config.example.yaml` (new) — config template with `${VAR}` placeholders.
- `templates/oracle-cloud/openclaw/SETUP.md` (new) — bilingual Discord bot setup walkthrough mirroring `hermes-agent/SETUP.md`.
- `scripts/ensure-openclaw-config.sh` (new) — config capture (bot token, channels, AI provider, credentials) → `.my-harness/.openclaw-config.json`.
- `scripts/register-agent-daily-report.sh` `openclaw)` branch implemented (was a 7.28.0 stub).
- `OPENCLAW_ENABLED=yes|no` env wired through `setup-oci-vm-nixos.sh` (mutually exclusive with `HERMES_AGENT_ENABLED`).

### Changed
- `templates/oracle-cloud/nixos/configuration.nix` conditionally imports `openclaw.nix` via the new `harness.openClawEnabled` option.
- `skills/my-harness-init/SKILL.md` Q12.5 now offers a fully-functional OpenClaw option (Hermes / OpenClaw / None — mutually exclusive single-select).

### Not implemented (intentional)
- `scripts/setup-oci-vm.sh` (the legacy Oracle Linux dnf path) does NOT yet deploy OpenClaw. Since 7.24.0 NixOS is the recommended default and Oracle Linux is legacy-only; users selecting OpenClaw should be on NixOS. If you need OpenClaw on Oracle Linux, open an issue or migrate the VM to NixOS first.

### Rationale
OpenClaw and Hermes occupy the same niche (open-source self-hosted Discord-AI gateway) but with different ecosystems, plugin communities, and personalities (Hermes = NousResearch's "agent that grows with you", OpenClaw = the 🦞 lobster-mascot Anglo-Saxon community fork). Users with existing OpenClaw familiarity can now select it in Q12.5 instead of Hermes. The daily-report cron migration (7.27.0) works identically on both via `register-agent-daily-report.sh`.

### Staged release plan: complete
7.22.0 → 7.30.0 staged release plan is now fully complete. No further planned releases are pending. Future work is user-request driven.

## [7.29.3.1] — 2026-05-14

### Fixed
- `scripts/codex-ask.sh` now prints a loud stderr warning when `--model` is set to an OpenAI reasoning model (`o1` / `o3-mini` / `o4-mini` / `o5-mini` / `-preview` variants). Reasoning models are text-only and silently break image_gen tool calls — the documented failure mode "turn ended with no agent_message and no image_generation_call" in `codex-app-server-call.py`. The warning sleeps 3 seconds before continuing (or skips the sleep when `CODEX_ALLOW_REASONING_MODEL=yes`); it does NOT block (in case the user wants reasoning behavior for non-image work).
- `skills/my-harness-init/SKILL.md` Phase 5 Stage 1 gains a "Model selection for Codex image generation (CRITICAL)" subsection that explicitly tells Claude NEVER to pass `--model` to `codex-ask.sh` for Phase 5 image-generation turns. The right escalation for failure is `refine-design.sh`, not switching models.

### Rationale
A real user-observed cascade: a Claude session decided "image generation failing → let me try a different model" and added `--model o4-mini`. o4-mini is reasoning-only and cannot call image_gen at all, so every image turn silently failed with the exact error message above. The Claude session then interpreted these failures as "Codex broken" and considered substituting its own image generation — which 7.29.2.1 closed off. This patch closes the upstream gap: the model choice that caused the failure in the first place.

## [7.29.3] — 2026-05-14

### Added
- `templates/oracle-cloud/nixos/pkgs/hermes-agent-fhs.nix` (new) — `buildFHSEnv` derivation that wraps Python 3.11 + all in-nixpkgs Hermes deps + `uv` + `git` + `ffmpeg`. On first systemd start the launcher script clones `NousResearch/hermes-agent` at tag `v2026.5.7` into `/var/lib/hermes/` and runs `uv pip install --editable .[messaging,voice]`. Subsequent starts skip the install step (idempotent check on `/var/lib/hermes/venv/bin/hermes`).

### Changed
- `templates/oracle-cloud/nixos/services/hermes-agent.nix` — completely rewritten. The `ExecStartPre` block that ran `curl -fsSL .../install.sh | bash` and `pip install "hermes-agent[voice,messaging]"` is removed. `ExecStart` now points at the Nix-store `hermes-agent-env` binary produced by `pkgs/hermes-agent-fhs.nix`. The FHS env launcher handles the full install lifecycle.
- `scripts/setup-oci-vm-nixos.sh` — removed the `systemctl enable --now hermes-agent.service` call from the Hermes deploy block (NixOS enables the service via `wantedBy = [ "multi-user.target" ]` at `nixos-rebuild switch` time, same pattern as CLIProxyAPI in 7.29.0). The `config.yaml` scp, `.env` write, and `register-agent-daily-report.sh` call are retained.

### Approach: B (buildFHSEnv hybrid)

`buildPythonApplication` (Approach A) was considered but rejected because:
1. Hermes is NOT published on PyPI — it requires a git clone + `uv sync` editable install.
2. Three core dependencies are absent from nixpkgs 25.05: `exa-py`, `parallel-web`, `fal-client`. Packaging each as a sibling derivation is feasible but creates a high-maintenance burden given Hermes's weekly date-based release cadence (`v2026.5.7`, `v2026.4.30`, ...).
3. The project uses `uv.lock` (SHA256-verified transitive deps) for supply-chain safety — reproducing that in a `buildPythonApplication` would require vendoring the entire lock graph.

`buildFHSEnv` (Approach B) provides the best trade-off: the Nix closure is fully reproducible and manages all in-nixpkgs deps; `uv` handles only the 3 missing packages and the editable install into `/var/lib/hermes/` (mutable runtime state, same as model weights).

### Deps: in-nixpkgs vs packaged vs left-to-uv

**In nixpkgs 25.05 (pre-seeded to FHS env's PYTHONPATH):**
`openai`, `anthropic`, `faster-whisper`, `discordpy`, `python-telegram-bot`, `slack-bolt`, `slack-sdk`, `sounddevice`, `numpy`, `aiohttp`, `croniter`, `edge-tts`, `pyjwt`, `requests`, `httpx`, `pyyaml`, `rich`, `tenacity`, `jinja2`, `pydantic`, `prompt-toolkit`, `fire`, `qrcode`, `ptyprocess`, `firecrawl-py`

**NOT in nixpkgs — fetched by uv on first start (3 packages):**
`exa-py` (web search tool), `parallel-web` (parallel HTTP fetch), `fal-client` (Fal image-generation client)

**NeuTTS removed:** The 7.25.0/7.26.0 deploy installed `neutts[all]` for local TTS. NeuTTS is not in nixpkgs and requires ~500 MB of model weights. The gateway deployment uses `edge-tts` (free, no local model, already in nixpkgs) for synthesis. This is a deliberate simplification for the headless Oracle Cloud A1.Flex VM — NeuTTS can be added back as a sibling derivation if local TTS is required.

### No `lib.fakeHash` placeholders
`buildFHSEnv` does not compute a source hash at build time (the FHS env itself is built from the Nix store closure; the git clone happens at service start time). There are no hash-related first-build fixups required for this derivation.

### Pinned source
Hermes tag `v2026.5.7` (internal package version `0.13.0`, Python ≥3.11). The tag is pinned in the FHS launcher script at `/var/lib/hermes/hermes-agent`. SHA-256 of the `v2026.5.7` tarball (for reference / future Approach A migration): `sha256-dbYp54emgWRxO2bR3RY8ZfhTR0ycd1zW8gZ5emKaosA=`

### 4 of 4 Nix-pure steps complete
The full NixOS VM is now deployable via a single `nixos-rebuild switch` (or `nixos-anywhere` for initial install) with zero imperative install commands:
- 7.29.0: CLIProxyAPI — `buildGoModule`
- 7.29.1: daily-progress-bot scripts — `home-manager` `home.file`
- 7.29.2: Claude Code + OpenAI Codex CLIs — `buildNpmPackage`
- **7.29.3: Hermes Agent — `buildFHSEnv` (this release)**

## [7.29.2.1] — 2026-05-14

### Fixed
- `skills/my-harness-init/SKILL.md` Phase 5 Stage 1 now explicitly forbids Claude from substituting when Codex fails to call `image_gen` or emit the manifest. The 7.21.0 NON-NEGOTIABLE QUALITY BAR only spelled out Stage 3 (HTML); Stage 1 (image / manifest) was implicit and got misinterpreted by a Claude session that started writing Pillow scripts as a fallback.

The rule is identical at every stage: **Claude verifies + iterates (via `refine-design.sh`), Claude never substitutes**. Claude must not generate the PNG via Pillow/ImageMagick/HTML, must not hand-write the manifest, must not silently move on. Up to 3 refine retries; then STOP and ask the user.

Stage 3 description also gained a one-line back-reference to Stage 1 so the two rules are visibly linked.

### Rationale
A real user session was observed where Codex returned exit-1 (turn ended without image_generation_call event) and Claude proceeded to attempt self-substitution. This is the exact failure mode 7.21.0 was meant to prevent — the patch closes the Stage 1 gap.

## [7.29.2] — 2026-05-14

### Added
- `templates/oracle-cloud/nixos/pkgs/claude-code.nix` — `buildNpmPackage` derivation for `@anthropic-ai/claude-code` v2.1.141. Source tarball hash precomputed (`sha256-a35KoQBnG1hO3iMMrIfoBXOoZufFgSL76Q06LGuvfpw=`); `npmDepsHash` set to `lib.fakeHash` (see Known followups).
- `templates/oracle-cloud/nixos/pkgs/openai-codex.nix` — `buildNpmPackage` derivation for `@openai/codex` v0.130.0. Source tarball hash precomputed (`sha256-w//PJo0YALy/zlDcqWTgXWq8zY8dIOlEs7uHfnFkL8o=`); `npmDepsHash` set to `lib.fakeHash`.
- Both CLIs added to `environment.systemPackages` in `templates/oracle-cloud/nixos/configuration.nix` via `let claude-code = pkgs.callPackage ./pkgs/claude-code.nix {}; openai-codex = pkgs.callPackage ./pkgs/openai-codex.nix {};` pattern.

### Changed
- `scripts/setup-oci-vm-nixos.sh` no longer runs `npm install -g @anthropic-ai/claude-code` or `npm install -g @openai/codex` — NixOS handles the install declaratively at `nixos-rebuild switch` time. The codex auth.json scp block is retained (runtime secret, not managed by Nix).

### Rationale
Step 3 of 4 in the Nix-pure migration. After this release the AI CLIs ship with the NixOS closure — atomic rollback works, version pin is in the derivation files, and a `nixos-rebuild switch` swaps them cleanly with no network access at deploy time (Nix fetches the npm tarballs during build, not during setup-oci-vm-nixos.sh).

Neither `claude-code` nor `openai-codex` is packaged in nixpkgs 25.05 (confirmed via GitHub code search on NixOS/nixpkgs). Custom `buildNpmPackage` derivations used for both.

### Known followups
- `npmDepsHash` in both `pkgs/claude-code.nix` and `pkgs/openai-codex.nix` is `lib.fakeHash`. On the first `nixos-rebuild switch`, the build will fail with the correct hash; copy it in and commit a 7.29.2.1 patch (same pattern as 7.29.0's `vendorHash` for CLIProxyAPI). Source tarball hashes are correctly precomputed and will not cause an error.

### Remaining
- 7.29.3: Hermes Agent via `buildPythonApplication` (final step — faster-whisper, NeuTTS deps to resolve).

## [7.29.1] — 2026-05-14

### Added
- `fzf` and `ghq` added to `environment.systemPackages` in `templates/oracle-cloud/nixos/configuration.nix`. `programs.fzf.enableBashIntegration = true` wired in `home.nix` (Ctrl-R history search, Ctrl-T file finder). `ghq` package provides the `~/ghq/` repo manager on the VM.
- `programs.fzf` block in `nixos/home.nix` with `enableBashIntegration = true`.

### Changed
- `templates/oracle-cloud/flake.nix` (was `templates/oracle-cloud/nixos/flake.nix`) — moved up one level so the flake's git tree can see sibling directories (`daily-progress-bot/`, `hermes-agent/`, `cliproxyapi/`). Module paths updated to `./nixos/configuration.nix`, `./nixos/disko.nix`, `./nixos/hardware-configuration.nix`.
- `templates/oracle-cloud/nixos/home.nix` now places `daily-progress.sh`, `event-watch.sh`, `lib/ai-provider.sh`, `lib/post-notification.sh`, `crontab.example`, `logrotate.conf` declaratively via `home.file` (read-only Nix-store symlinks under `/home/opc/daily-progress-bot/`). The `.env` file (secrets) is still managed imperatively by `setup-oci-vm-nixos.sh`.
- `scripts/setup-oci-vm-nixos.sh` — `NIXOS_SRC` now points at `templates/oracle-cloud/` (flake root); staging copies the full oracle-cloud tree; python key-injection and harness-overlay scripts updated to reference `$STAGE_DIR/nixos/configuration.nix`. The scp block that copied bot scripts to the VM is removed — home-manager handles placement declaratively.

### Rationale
Step 2 of 4 in the Nix-pure migration. Scripts are now part of the NixOS closure — a future `nixos-rebuild switch` swaps versions atomically, with rollback support. The user's earlier requirement "redeploy cleanly to AWS Graviton / GCP Tau T2A" is now closer: the bot's behavior moves with the flake, no extra rsync of script directories needed.

`fzf` + `ghq` added at user request — useful when SSH'd into the VM for ad-hoc debugging and repo management.

### Known
- After this change, hand-editing `/home/opc/daily-progress-bot/daily-progress.sh` on the VM has no effect (it's a read-only Nix-store symlink). Edits must happen in the harness repo + redeploy. This is the intended trade-off for declarative ops.
- `programs.ghq` home-manager module is not available in all nixpkgs branches; `ghq` is therefore added as a system package only (no declarative `~/ghq/` root config required — `ghq` defaults to `~/ghq/` out of the box).

## [7.29.0] — 2026-05-14

### Added
- `templates/oracle-cloud/nixos/pkgs/cliproxyapi.nix` (new) — `buildGoModule` derivation for CLIProxyAPI v7.0.6. Replaces the 7.26.0 prebuilt-tarball download. Pinned to `router-for-me/CLIProxyAPI` at commit `3a9fb3780ed63d9c71efca760d0c5935b3f6fc19` (tag `v7.0.6`); source hash locked (`sha256-VgLx9Zok24QfYDacmJmC4FS5y5jqNd/9eyh1MQ8Jhww=`). Main package at `./cmd/server`, binary name `cli-proxy-api`.

### Changed
- `templates/oracle-cloud/nixos/services/cliproxyapi.nix` now consumes the Nix-built derivation via `pkgs.callPackage ./../pkgs/cliproxyapi.nix {}`. `ExecStart` references the `/nix/store/...-cliproxyapi-7.0.6/bin/cli-proxy-api` path; `ExecStartPre` curl/tar dance removed.
- `scripts/setup-oci-vm-nixos.sh` no longer calls `systemctl enable --now cliproxyapi.service` — NixOS enables the service via `wantedBy = [ "multi-user.target" ]` at `nixos-rebuild switch` time. Config rendering (config.yaml scp) and Codex auth.json deploy are retained.

### Rationale
First of 4 steps toward a fully-Nix VM. CLIProxyAPI was chosen first because:
1. Single Go binary with no runtime deps — clean `buildGoModule` fit.
2. Localized change (one module file + one new derivation), low risk.
3. The 7.26.0 curl/tar dance was the simplest impurity to eliminate.

The remaining 3 steps:
- 7.29.1: home-manager for daily-progress-bot scripts (declarative file placement).
- 7.29.2: Claude / Codex CLIs (`buildNpmPackage` or nixpkgs).
- 7.29.3: Hermes Agent (`buildPythonApplication` — most complex due to faster-whisper / NeuTTS deps).

### Known followups
- `vendorHash` in `pkgs/cliproxyapi.nix` is set to `lib.fakeHash` — must be updated on the first `nixos-rebuild switch`. The build will fail with the correct hash; copy it in and commit a 7.29.0.1 patch.

## [7.28.0] — 2026-05-14

### Removed
- Gemma 4 as an `AI_PROVIDER` option for daily-progress / event-watch. The 3-way SKILL.md Q11 choice is now a 2-way (Claude Code / Codex).
- `templates/oracle-cloud/nixos/services/ollama.nix` — Ollama daemon is no longer needed on the VM under any provider configuration (Hermes already removed Gemma 4 in 7.26.0; daily-progress drops it now in 7.28.0).
- Ollama install / `ollama pull gemma4:e4b` steps from `setup-oci-vm.sh` and `setup-oci-vm-nixos.sh`.
- `OLLAMA_URL` and `GEMMA_MODEL` override examples from `.env.example`.

### Changed
- `lib/ai-provider.sh` rejects `gemma4` with a clear "removed in 7.28.0" error message. Same defensive rejection in `setup-oci-vm.sh` and `setup-oci-vm-nixos.sh`.
- `ensure-hermes-config.sh` retains its `gemma4` rejection arm (added in 7.26.0) as a defensive guard for users editing env files manually.

### Rationale
Gemma 4 was the "fully free local" option but in practice the A1.Flex ARM4 CPU produces only 3-6 tok/s on Gemma 4 E4B, and the 8 GB RAM the model needs sits idle alongside Hermes's voice models (Whisper + NeuTTS), wasting the limited 24 GB shared resource. Subscription-based Codex (free via ChatGPT Plus/Pro) and Claude Code (free via Pro/Max) deliver dramatically better quality at zero marginal cost, so Gemma 4 had no audience left. Removed cleanly across all paths.

NixOS `services.ollama` import gone, the corresponding service file deleted, deploy scripts simplified — net reduction of ~150 lines.

## [7.27.0] — 2026-05-14

### Added
- `templates/oracle-cloud/hermes-agent/prompts/daily-report.md` (new) — the prompt Hermes runs on its internal cron (`0 9 * * *` UTC) to produce the daily progress report. Collects the same 6 GitHub data sources as `daily-progress.sh` but with the agent advantage: runs in session `daily-report-<repo>` so it remembers previous days' reports and writes continuity notes ("継続: 昨日からの priority/p1 issue ...").
- `scripts/register-agent-daily-report.sh` (new) — registers the cron job inside the running Hermes Agent via its `hermes cronjob add` CLI (with JSON-RPC fallback to `POST /api/cronjobs`). Idempotent (re-registering with the same name updates). Handles `openclaw)` arm with a "planned for 7.28.0" no-op exit.
- NixOS module option `harness.hermesAgentEnabled` (in `templates/oracle-cloud/nixos/services/daily-progress.nix`) controls whether `daily-progress.timer` and `event-watch.timer` auto-start. Defaults to `false` (= unchanged legacy behavior). `setup-oci-vm-nixos.sh` writes a `harness-overlay.nix` into the staged NixOS config and sets the option to `true` when `HERMES_AGENT_ENABLED=yes`.

### Changed
- `scripts/setup-oci-vm-nixos.sh` — after `hermes-agent.service` is up, calls `register-agent-daily-report.sh`, then disables `daily-progress.timer` and `event-watch.timer` via `systemctl disable --now` when `HERMES_AGENT_ENABLED=yes`. When `HERMES_AGENT_ENABLED=no` (or unset), the legacy timer-enable path is unchanged.
- `scripts/setup-oci-vm.sh` (Oracle Linux path) — after Hermes is deployed, calls `register-agent-daily-report.sh`, then strips `daily-progress.sh` and `event-watch.sh` lines from the opc crontab via `crontab -l | grep -v ... | crontab -` when `HERMES_AGENT_ENABLED=yes`.
- `skills/my-harness-init/SKILL.md` Q12.5 Hermes Agent branch now notes the daily-report cron migration (EN + JA).
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` bumped to 7.27.0.

### Rationale
The shell-cron path is one-shot AI calls without memory — every day starts from scratch. Moving daily-report into Hermes lets the agent track multi-day patterns (a priority/p1 that has been open 3 days running, a CI flake that keeps recurring, a feature whose PR has been in review since yesterday). Output to the user is identical (Japanese 3-5 bullet summary, emoji prefixes, posted to the same Discord channel). When the user picks "None" for Q12.5, the legacy shell-cron path stays exactly as it was.

OpenClaw is planned for 7.28.0; this release leaves a clean `openclaw)` placeholder in `register-agent-daily-report.sh`.

## [7.26.0] — 2026-05-14

### Added
- `templates/oracle-cloud/nixos/services/cliproxyapi.nix` (new) — NixOS module for [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI), a Go-based local proxy that wraps Codex CLI / Claude Code CLI subscriptions as OpenAI-compatible endpoints (port 8317). Deployed only when HERMES_AI_PROVIDER ∈ {codex, claude-code}. Downloads the pre-built aarch64-linux binary (v7.0.6) idempotently in ExecStartPre. Starts before hermes-agent.service so Hermes can reach the proxy on boot.
- `templates/oracle-cloud/cliproxyapi/config.example.yaml` (new) — proxy config template with `${CODEX_EXCLUDED}` / `${CLAUDE_EXCLUDED}` placeholders substituted at deploy time to enable exactly one OAuth provider channel. Exposes stable model aliases (`hermes-codex-default`, `hermes-claude-default`) so Hermes config.yaml doesn't track versioned model IDs.
- Phase 1 Setup Q12.6 rewritten to offer 4 Hermes AI provider choices: Codex (CLIProxyAPI + ChatGPT subscription), Claude Code (CLIProxyAPI + Claude subscription), OpenRouter (API key, free models available), Anthropic Claude API (paid API key). Walk-me-through paths for all four options.

### Removed
- Gemma 4 as a Hermes AI provider option. Running Ollama + Gemma 4 alongside Hermes + Whisper Tiny + NeuTTS Air on the A1.Flex's 24 GB RAM was too tight in practice. Daily-progress bot's `AI_PROVIDER=gemma4` is unaffected — Gemma 4 stays available there.

### Changed
- `scripts/ensure-hermes-config.sh` accepts 4-value provider enum (`codex | claude-code | openrouter | claude-api`) instead of 2. Rejects `gemma4` with a clear error message. The `<openai-key>` arg is renamed to `<provider-credential>`: empty for codex/claude-code (OAuth auto-discovered), `sk-or-...` for openrouter, `sk-ant-api...` for claude-api. JSON schema now uses `ai_provider`, `openrouter_api_key`, `anthropic_api_key` fields.
- `scripts/setup-oci-vm-nixos.sh` and `scripts/setup-oci-vm.sh` conditionally deploy CLIProxyAPI when codex/claude-code is chosen; pass OPENROUTER_API_KEY or ANTHROPIC_API_KEY directly to Hermes .env otherwise. Hermes config rendered via new `${HERMES_PROVIDER_BLOCK}` placeholder.
- `templates/oracle-cloud/hermes-agent/config.example.yaml` model section replaced with `${HERMES_PROVIDER_BLOCK}` substituted at deploy time into one of 4 provider stanzas (custom/openrouter/anthropic).
- `templates/oracle-cloud/hermes-agent/SETUP.md` adds Section 3.6 "Choosing an AI Provider" — bilingual 4-provider comparison table, CLIProxyAPI explanation, and RAM rationale for removing Gemma 4.
- `skills/my-harness-init/SKILL.md` Q12.6 fully rewritten: 4-option AskUserQuestion (EN + JA), walk-me-through paths for each provider, Q12.8 expanded to cover openrouter and claude-api credential flows.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` bumped to 7.26.0.

### Rationale
The user explicitly rejected Gemma 4 for Hermes (RAM pressure) and asked for subscription-based zero-cost options. CLIProxyAPI is the idiomatic open-source solution: production-ready Go binary, supports both Codex and Claude Code OAuth out of the box, exposes a standard OpenAI-compatible endpoint. Our previous self-rolled `codex-bridge.py` plan was abandoned in favor of this. Anthropic API key + OpenRouter remain as direct-connection fallbacks for users who don't have a Codex/Claude subscription or who want OpenRouter's free models.

## [7.25.1] — 2026-05-14

### Added
- Phase 1 Setup Q12.9 (Discord home channel name) and Q12.10 (Discord application channel name), bilingual. Both saved to `.my-harness/.hermes-config.json` and exported on the VM as `DISCORD_HOME_CHANNEL_NAME` and `DISCORD_APP_CHANNEL_NAME` so Hermes resolves channels by name on startup without the user having to run `/sethome` interactively.
- `templates/oracle-cloud/hermes-agent/SETUP.md` — new section "3.5. Creating the two channels Hermes uses" (bilingual) walks the user through creating `#bot-updates` and `#bot-chat` (or equivalents) before the deploy.

### Changed
- `scripts/ensure-hermes-config.sh` accepts two more positional args (home channel + app channel) and merges them into the existing JSON config (preserves prior values when args are empty — same pattern as ensure-notification-webhook.sh).
- `scripts/setup-oci-vm-nixos.sh` and `scripts/setup-oci-vm.sh` write the two channel names into the VM-side Hermes `.env`.
- `templates/oracle-cloud/hermes-agent/config.example.yaml` references `${DISCORD_HOME_CHANNEL_NAME}` and `${DISCORD_APP_CHANNEL_NAME}` placeholders.

### Rationale
Without this, the user has to deploy Hermes, manually join Discord, run `/sethome` in the right channel, and remember which channel is "application". Q12.9/Q12.10 surface both decisions during setup so the bot self-resolves channel IDs from names at startup. The app-channel value is informational today (Hermes doesn't gate on it as of 2026-05-14) but stored so future Hermes versions can use it.

## [7.25.0] — 2026-05-14

### Added
- Hermes Agent (NousResearch's personal AI gateway) integration with **Voice Mode enabled out-of-the-box**. Hermes runs as a systemd service on the OCI VM and bridges Discord (both Auto Voice Reply for voice messages in chat AND Discord Voice Channels where the bot joins and speaks) to the chosen AI backend. STT = local Whisper Tiny (~75 MB, no external API). TTS = NeuTTS Air (~0.5B params, on-device, no external API). Both fully free forever and ARM64-compatible.
- `templates/oracle-cloud/nixos/services/hermes-agent.nix` (new) — declarative NixOS systemd service for Hermes. Installs via the official install.sh, pip-installs `hermes-agent[voice,messaging]` + `faster-whisper` + `neutts[all]`, symlinks config and .env, runs `hermes gateway start --foreground`.
- `templates/oracle-cloud/hermes-agent/config.example.yaml` (new) — config template with `${OPENAI_MODEL}` and `${OPENAI_BASE_URL}` substitution placeholders. Voice settings hardcoded: STT = local Whisper Tiny, TTS = NeuTTS Air, Auto Voice Reply + Discord Voice Channels enabled, CLI Interactive Voice disabled (headless VM).
- `templates/oracle-cloud/hermes-agent/SETUP.md` (new) — bilingual Discord bot creation walkthrough (Developer Portal, Privileged Intents, OAuth2 invite URL, smoke tests, troubleshooting table, token rotation).
- `scripts/ensure-hermes-config.sh` (new) — captures Discord bot token (validated via `MT[A-Za-z0-9_.-]{50,}` regex), Hermes AI provider (codex|gemma4), OpenAI API key (when codex). Saves to `.my-harness/.hermes-config.json` (chmod 600). Exits 3 when called with no args (signals SKILL.md to use AskUserQuestion).
- `skills/my-harness-init/SKILL.md` Q12.5 (additional AI agent: None / Hermes Agent / OpenClaw-placeholder) and follow-up sub-questions Q12.6 (Hermes AI provider — codex or gemma4; re-uses Q11 selection when compatible) / Q12.7 (Discord bot token with walk-me-through and paste options) / Q12.8 (OpenAI API key when codex, with portal link). Bilingual (EN + JA).

### Changed
- `scripts/setup-oci-vm-nixos.sh` now deploys Hermes Agent when `HERMES_AGENT_ENABLED=yes` in `.notification.env`. Reads `.my-harness/.hermes-config.json`, renders config.yaml (substituting model + base URL), writes `~/hermes-agent/.env` on the VM (chmod 600), enables `hermes-agent.service` via systemd.
- `scripts/setup-oci-vm.sh` (Oracle Linux legacy path) similarly deploys Hermes Agent when `HERMES_AGENT_ENABLED=yes`: installs Python 3 + pip + ffmpeg via dnf if missing, runs the official Hermes install.sh idempotently, pip-installs voice+messaging extras, writes a `/etc/systemd/system/hermes-agent.service` unit, and `systemctl enable --now`.
- `skills/my-harness-init/SKILL.md` Phase 1 wrap-up updated: "After Q6-Q12.x answered..." to reflect new questions.
- `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` bumped to 7.25.0.

### Rationale
User wants voice chat capability without ongoing costs. Hermes Agent's `local` STT (Whisper Tiny) and `neutts` TTS providers were chosen specifically because both are first-class Hermes-supported, both run on-device on ARM CPU, and both are permanent-free. We considered Kokoro TTS (higher MOS, but no Hermes integration), Moonshine v2 STT (ultra-lightweight, but Hermes doesn't ship support), and Edge/ElevenLabs/OpenAI TTS (all involve external dependencies). The chosen pair gives the best "Hermes-native + free + ARM" intersection.

Hermes is a Python CLI installed via official install.sh (not npm) — the install.sh creates a venv at `~/.hermes/venv/` and places the binary at `~/.hermes/bin/hermes`. The NixOS service module installs it idempotently in ExecStartPre and runs `hermes gateway start --foreground` as a simple systemd service.

OpenClaw integration ships in 7.26.0 (mutually exclusive with Hermes — the Q12.5 option exists as a placeholder for now).

### Known limitations
- First Hermes deploy downloads Whisper Tiny (~75 MB) and NeuTTS Air model (~500 MB). Allow 5-10 min on slow links. The service has `TimeoutStartSec=15min` to accommodate this.
- Hermes config schema may shift between releases; the generated config is a best-effort snapshot of the docs at 2026-05-14. If Hermes upgrades break it, regenerate via `bash scripts/ensure-hermes-config.sh <root>`.
- `AI_PROVIDER=claude` is incompatible with Hermes (Hermes wants an OpenAI-compatible endpoint). Q12.6 forces a separate codex or gemma4 choice.
- `hermes gateway start --foreground` flag must exist in the installed Hermes version. If upstream drops it, change `Type=simple` to `Type=forking` in `hermes-agent.nix` / the OL systemd unit and remove `--foreground`.

## [7.24.0] — 2026-05-14

### Added
- `templates/oracle-cloud/nixos/` — full NixOS configuration tree for the daily-progress-bot host. Files: `flake.nix` (nixpkgs 25.05, disko, home-manager, aarch64-linux), `configuration.nix` (OS-wide), `disko.nix` (declarative `/dev/sda` GPT layout), `hardware-configuration.nix` (qemu-guest profile), `home.nix` (opc user via home-manager), and `services/{daily-progress,ollama,logrotate}.nix` (systemd timers + Ollama + log rotation, all declarative).
- `scripts/setup-oci-vm-nixos.sh` — runs `nix run github:nix-community/nixos-anywhere` to kexec the existing OS to NixOS, then deploys daily-progress-bot, sets up env, enables systemd timers, smoke-tests with `systemctl start daily-progress.service`.
- `skills/my-harness-init/SKILL.md` Phase 1 Setup Q9.6 — bilingual OS choice (NixOS recommended, Oracle Linux 9 legacy).
- `scripts/setup-oci-vm.sh` now reads `OS_KIND` from `.notification.env` and execs `setup-oci-vm-nixos.sh` when `OS_KIND=nixos`; falls through to the existing dnf path otherwise.

### Rationale
The user wants every part of the VM (OS, packages, services, dotfiles, rotation rules) declared in Nix so the same flake redeploys cleanly to any aarch64 cloud (AWS Graviton, GCP Tau T2A, Hetzner ARM, etc.). Cron is replaced with systemd timers (declarative, journald-integrated). home-manager handles the opc user's bash setup. Disko handles partition layout reproducibly. The legacy Oracle Linux path stays as an opt-in fallback for users with existing dnf-based deployments (e.g. kirinnkubinagaiyo's current VM is untouched).

NixOS-equivalent of 7.23.0's `services.logrotate.settings."daily-progress"` is bundled in `services/logrotate.nix` — same semantics, different syntax.

### Known limitations
- Deployment requires `nix` command on the developer's Mac. First-time setup: https://nixos.org/download.html (~3 min).
- nixos-anywhere kexec re-partitions the disk — any existing data on the VM is lost. Only run on freshly-provisioned VMs or after confirming you don't need the current data.
- Smoke test depends on Ollama having finished pulling gemma4:e4b (~5 GB, can take 5-15 min on slow links). When AI_PROVIDER=gemma4 the first daily-progress.service run may fail until ollama-pull-gemma4.service completes; subsequent timer firings work normally.

## [7.23.0] — 2026-05-14

### Added
- `templates/oracle-cloud/daily-progress-bot/logrotate.conf` (new). Logrotate config for `/home/opc/daily-progress-bot/cron.log`: weekly, 4 weeks retention, gzip + delaycompress, copytruncate (preserves the append fd of daily-progress.sh and event-watch.sh), `create 0600 opc opc`, ISO-style date suffix, rotated files under `/var/log/daily-progress/`.
- `scripts/setup-oci-vm.sh` now installs that logrotate config into `/etc/logrotate.d/daily-progress` on the VM and validates with `logrotate -d` before declaring success.

### Rationale
The daily-progress + event-watch crons append to a single `cron.log` indefinitely. Over months that file grows hundreds of MB on a 47 GB ARM A1 root partition, and grep'ing it gets sluggish. Standard Linux logrotate solves it; the only non-default knob is `copytruncate` — without it logrotate would rename the file and the long-lived append file descriptors held by cron'd shell scripts would silently keep writing to the renamed (rotated) file. `copytruncate` preserves the inode so appends keep flowing into the now-empty file.

The matching NixOS-side `services.logrotate.settings."daily-progress"` ships in 7.24.0 alongside the broader NixOS migration. The semantics are identical; only the declaration syntax differs.

## [7.22.1] — 2026-05-14

### Added
- `scripts/bootstrap.sh --skeleton` flag (new). Builds ONLY the `.bare/` repo + main/stage/dev branches/worktrees + minimal `dev/docs/{spec,design,talk,task}/` dirs + baseline `dev/.gitignore` + initial `chore: skeleton bootstrap` commit on dev, then exits. Heavier setup (common files, platform templates, flake.nix, project-name substitution) is deferred to the Phase 8 full bootstrap.
- `skills/my-harness-init/SKILL.md` Phase 5 now has a "Pre-Stage: Skeleton bootstrap" subsection that runs `bootstrap.sh --skeleton` before Stage 1. This makes the per-screen commit gate (7.20.0) actually work in the harness layout.

### Fixed
- `scripts/commit-design-screen.sh` now `cd`s into `<root>/dev/` (the dev worktree) instead of `<root>` (the bare-repo wrapper, which has no working tree and silently failed `git add`). All staged paths are now relative to `<root>/dev/` (e.g. `docs/design/page-pc-home.png` not `dev/docs/design/page-pc-home.png`).

### Rationale
The 7.20.0 per-screen commit gate was designed assuming a standard git repo at `<root>`, but the harness uses `.bare/` + `<root>/{main,stage,dev}/` worktrees. The bare-repo wrapper has no working tree, so the existing `cd "$ROOT" && git add dev/...` would have failed silently. The fix is two-fold: (a) make sure the worktree layout exists before Phase 5 starts (via `--skeleton`), and (b) commit from inside the dev worktree, not its parent.

## [7.22.0] — 2026-05-14

### Added
- Multi-provider AI for the OCI daily-progress bot. Phase 1 Setup Q11 lets users pick the AI backend: `claude` (existing, reuses Q9.5 OAuth token), `codex` (ChatGPT Plus/Pro subscription via `codex login` + auth.json transfer — NOT API key billing), or `gemma4` (local Ollama with `gemma4:e4b`, no auth, ~5 GB model auto-downloaded on the VM).
- `templates/oracle-cloud/daily-progress-bot/lib/ai-provider.sh` (new). Single dispatch point `ai_provider_run "<prompt>"` that branches on `$AI_PROVIDER`. Sourced by both `daily-progress.sh` and `event-watch.sh`.
- `scripts/ensure-codex-auth.sh` (new). Copies Mac's `~/.codex/auth.json` to `.my-harness/.codex-auth.json` (chmod 600) so `setup-oci-vm.sh` can scp it to the VM.

### Changed
- `daily-progress.sh` and `event-watch.sh` switched from hardcoded `claude -p ...` to `ai_provider_run "..."` from the new lib. Dependency and credential checks gate on `$AI_PROVIDER`.
- `templates/oracle-cloud/daily-progress-bot/.env.example` now shows `AI_PROVIDER=claude|codex|gemma4` as the first env var, with provider-specific overrides (`CODEX_EXEC_CMD`, `OLLAMA_URL`, `GEMMA_MODEL`).
- `scripts/setup-oci-vm.sh` now reads `$AI_PROVIDER` from `.notification.env` and runs provider-specific VM setup: Claude (claude CLI + token env), Codex (codex CLI + auth.json scp), Gemma 4 (Ollama install + `gemma4:e4b` pull + systemd enable).

### Rationale
7.21.0 only worked for Claude Code subscribers. To support users who prefer ChatGPT subscription or want a fully free local setup, the AI backend is now a single env var. Codex uses OAuth via auth.json transfer (NOT API key) because the user explicitly rejected API-key billing. Gemma 4 E4B fits in ~8 GB of the A1.Flex's 24 GB and runs at 3-6 tok/s on 4 ARM cores — fine for cron-driven summarization. OpenCode is intentionally NOT used: daily-progress only needs single-shot LLM calls, not agent loops, so Ollama's HTTP API directly is simpler and removes a dependency.

## [7.21.0] — 2026-05-14

### Changed
- Three Codex prompts (`prompts/codex-page-mock.md`, `prompts/codex-parts-grid-edit.md`, `prompts/codex-page-to-html.md`) end with a new NON-NEGOTIABLE QUALITY BAR section. Codex is now explicitly told: no compromise, no partial output expecting Claude to fill in gaps, and if a constraint cannot be honored, emit `ABORT: <specific reason>` instead of shipping defective work.
- `skills/my-harness-init/SKILL.md` Stage 3 description clarifies that Claude's role is verification + iteration (calling `refine-design.sh` / `gen-page-html.sh` again with explicit feedback), NOT silently rewriting Codex output.

### Rationale
User feedback: "Claude must not make its own interpretations — Codex should be made to do its maximum effort." Earlier rounds of Phase 5 had Claude silently smoothing over partial Codex output, which masked Codex defects and produced inconsistent design quality. Pushing every "quality decision" onto Codex itself, and pushing every failure into an `ABORT: <reason>` that surfaces to the user, makes the quality bar explicit and removes Claude's interpretive layer.

## [7.20.0] — 2026-05-14

### Added
- `scripts/commit-design-screen.sh` (new). Stages exactly one screen's design artifacts across whichever form factors exist (page PNG, parts-grid PNGs, `parts/<ff>/<slug>/` tree, `src/components/design/<ff>/<slug>/` tree) and creates a `design(<slug>): mock approved — <ff-list>` commit in the user's project repo. Idempotent — no-op when no staged change.
- `skills/my-harness-init/SKILL.md` Phase 5 Stage 1 now has an explicit "Per-screen commit gate" subsection: after every user OK event for a screen's mock(s), the harness commits that screen's design artifacts before moving to the next screen. Wired into the "Iterative refinement" subsection too so every accepted refine round commits.

### Rationale
User wants a real design commit log — one commit per approved screen so the project history reads as a sequence of explicit design decisions, not one giant Phase 5 batch. Per-screen (not per-form-factor): `gen-page-auto.sh` produces both form factors as a unit and the user reviews them together, so one approval event = one commit.

## [7.19.0] — 2026-05-13

### Added
- `prompts/codex-page-mock.md` "SHARED CHROME" section. The first generated screen establishes header / footer / sidebar / bottom-nav (labels, order, icons, active states); every subsequent screen must reproduce them pixel-for-pixel via Codex image-edit-mode context. Only the main content region is redesigned per screen.
- `skills/my-harness-init/SKILL.md` Phase 5 description now calls out that **shared chrome** is inherited alongside `style_guide` across screens and form factors.
- env var `CHROMA_FLOOR` (default `30%`). Raise toward 50% for stricter magenta cut at the cost of tighter edges; lower toward 15% to preserve more anti-aliasing.

### Changed
- `scripts/crop-parts.sh` chroma-key cut switched from `-threshold` (hard binarization at 50%) to `-level <floor>x100%` (cuts ≤ floor to fully transparent, linearly stretches the rest). This preserves anti-aliased softness on real asset edges while still killing magenta-tinted edge pixels.

### Removed
- env var `CHROMA_THRESHOLD` (replaced by `CHROMA_FLOOR`).

### Rationale
User wants both "magenta absolutely never remains" AND "asset edges still look natural (not stair-stepped from binarization)". `-threshold` could only do the former at the cost of the latter; `-level <floor>x100%` does both because the Aral Balkan formula naturally separates magenta pixels into the low-alpha band and real asset pixels into the high-alpha band with a fade between them.

## [7.18.1] — 2026-05-13

### Changed
- `scripts/crop-parts.sh` chroma-key pipeline replaced with Aral Balkan's industry-standard formula adapted for magenta: `alpha = g - min(r, b) + 1`. Single per-pixel calculation that mathematically guarantees pure magenta → alpha=0 and leaves all non-magenta RGB untouched.

### Removed
- env vars `CHROMA_FUZZ`, `CHROMA_HALO_COLOR`, `CHROMA_FUZZ_HALO`, `CHROMA_ERODE`, `CHROMA_DESPILL` (replaced by the formula above). They are silently ignored if still set.

### Added
- env var `CHROMA_THRESHOLD` (default `50%`). Controls where the half-transparent anti-aliased fade gets cut to fully transparent — raise to e.g. `70%` for stricter magenta-residue removal, lower to e.g. `25%` to preserve more edge softness.

### Rationale
7.18.0's four-layer defense (fuzz pass + halo pass + erode + despill `-fx`) was hand-rolled and brittle: the fuzz passes risked eating asset-internal magenta-family colors and the `-fx` despill was slow. Aral Balkan's formula (https://ar.al/2021/11/23/how-to-apply-a-chroma-key-using-imagemagick/) is the documented industry-standard approach: one ImageMagick `-fx` call that computes alpha directly from the RGB channels with zero risk of touching asset interior pixels. `CHROMA_KEY` resolution kept for backwards-compat but is no longer consulted by the magick command (formula assumes magenta).

## [7.18.0] — 2026-05-13

### Changed
- `scripts/crop-parts.sh` chroma-key pipeline hardened from a single `-transparent` pass to a four-layer defense (primary fuzz raised to 40%, new secondary `-transparent` on `#FF80FF` with 25% fuzz, alpha erode raised to `Octagon:2`, new despill `-fx` filter that suppresses residual magenta cast on opaque edge pixels).
- `skills/my-harness-init/SKILL.md` Phase 5 docs updated with the new env defaults.

### Rationale
User reported magenta still showing through on cropped parts. The single-pass fuzz on pure `#FF00FF` did not catch antialiased rim pixels that render as pink (`#FF80FF` family), and there was no per-pixel cast suppression for whatever opaque pixels survived. The four layers together guarantee no magenta residue under default settings.

### Compatibility
Every parameter is env-overridable. Set `CHROMA_DESPILL=no` to skip the `-fx` filter if performance matters or assets legitimately contain magenta-family colors.

## [7.17.2] — 2026-05-13

### Reverted — the three model-ID changes from 7.17.1

`templates/oracle-cloud/daily-progress-bot/daily-progress.sh` and
`event-watch.sh` are back to `--model claude-sonnet-4-6` (cheap batch
summaries are the right call for an hourly / daily cron job).
`templates/github/workflows/pr-to-dev.yml` is back to
`claude_args: '{"model": "claude-opus-4-7"}'` (PR review benefits from
the strongest available model).

### Rationale

7.17.1 was a misread of the user's intent. The user wanted Claude Code
itself (their interactive editor) to default to Opus 4.6, not the
harness's per-script hardcoded models. That preference belongs in
`~/.claude/settings.json`'s `"model"` field, not in this repository.

`scripts/bootstrap.sh:529` `DEFAULT_PROJECT_MODEL=claude-opus-4-6`
was untouched in 7.17.1 and remains unchanged here.

## [7.17.1] — 2026-05-13

### Changed — default model for daily-progress-bot summaries switched from `claude-sonnet-4-6` to `claude-opus-4-6`

Both `templates/oracle-cloud/daily-progress-bot/daily-progress.sh` and
`event-watch.sh` now call `claude --model claude-opus-4-6`. This matches the
`scripts/bootstrap.sh:529` `DEFAULT_PROJECT_MODEL` constant, making the
daily-progress bot consistent with the rest of the harness default.

### Changed — default model for generated `templates/github/workflows/pr-to-dev.yml` Claude Action PR review switched from `claude-opus-4-7` to `claude-opus-4-6`

The `claude_args` field in the generated GitHub Actions workflow now references
`claude-opus-4-6` for PR review, consistent with the project-wide default.

### Rationale

User prefers Opus 4.6 as the project-wide default. The dateless
`claude-opus-4-6` ID is the official pinned snapshot per
`platform.claude.com/docs/en/about-claude/models/overview` (Legacy section,
still available; same alias, same pricing as 4.7).

## [7.17.0] — 2026-05-13

### Added — `scripts/ensure-claude-oauth-token.sh`

New bash building block (mirrors `ensure-notification-webhook.sh` and
`ensure-github-pat.sh`). Accepts `<root> [<token>]`, validates token
shape (no whitespace, length ≥ 30, alphabet `[A-Za-z0-9_=+/.~-]`),
and merges `CLAUDE_CODE_OAUTH_TOKEN=<token>` into
`<root>/.my-harness/.notification.env` (chmod 600, preserving all
other keys). Exit 0 = saved; exit 2 = bad shape; exit 3 = token empty.

### Added — Setup Q9.5 in `skills/my-harness-init/SKILL.md`

New question group inserted between Q9 (OCI VM) and the Phase 1
wrap-up. Runs when Q9 resulted in actual VM provisioning or
"Already have one — connect to it". Captures the 1-year OAuth token
produced by `claude setup-token` and stores it in `.notification.env`
so both the daily-progress bot (OCI VM) and the GitHub claude-code-action
can consume it from a single source.

Follows the same pattern as Q6/Q8: already-configured detection (option α)
shows current token length with a Keep / Change prompt; new-token path
explains `claude setup-token`, accepts a paste, and validates via
`ensure-claude-oauth-token.sh` with exit-code loop on bad shape. Fully
bilingual (EN/JA).

Decision 11 (Phase 6) updated with a reuse note: when `CLAUDE_AUTH=oauth`
and `.notification.env` already contains `CLAUDE_CODE_OAUTH_TOKEN`,
`setup-secrets.sh` auto-fills without prompting.

### Changed — `scripts/setup-oci-vm.sh`

No longer reads the macOS Keychain or `~/.claude/.credentials.json`.
Requires `CLAUDE_CODE_OAUTH_TOKEN` from `.my-harness/.notification.env`
only, which is guaranteed to be present after Q9.5 completes.

### Changed — `scripts/setup-secrets.sh`

Added `auto_secret()` helper for non-interactive GitHub Secret pushes.
The Claude Action block now checks `.my-harness/.notification.env` for
a saved `CLAUDE_CODE_OAUTH_TOKEN` before prompting: if found, calls
`auto_secret` and prints which path was taken; if absent, falls through
to the existing `ask_secret` interactive prompt.

### Changed — `templates/oracle-cloud/daily-progress-bot/.env.example`

Header comment updated to describe `claude setup-token` (~1 year
lifetime) instead of `claude login` (90-day access token).

### Removed — `scripts/sync-claude-creds-to-vm.sh`

Deleted. This script was a workaround for short-lived 90-day access
tokens that required hourly Mac→VM syncs. The 1-year token from
`claude setup-token` makes it unnecessary: once written to
`.notification.env` and pushed to the VM during `setup-oci-vm.sh`,
no further Mac involvement is required until the token expires.

### Rationale

`claude setup-token` produces the same `CLAUDE_CODE_OAUTH_TOKEN` that
GitHub's claude-code-action consumes. One capture during Q9.5 serves
both consumers — the daily-progress bot on the OCI VM and the PR-review
Action in CI. No refresh daemon, no hourly cron, no Keychain dependency.
Mac involvement after the first capture is zero.

---

## [7.16.0] — 2026-05-12

### Added — Phase 1 Setup orchestration for notifications + OCI VM (Step E)

This commit ties the 4 bash building blocks from 7.15.0 into the
`/my-harness-init` Phase 1 conversational flow. Users now configure
notifications and the daily-progress bot **during initial project
setup**, with re-runs detecting existing config and offering to keep
or change each piece independently.

#### `skills/my-harness-init/SKILL.md` — 4 new question groups (Q6–Q9)

  - **Q6** — Notification service (Discord / Slack / Teams / Disable),
    bilingual EN/JA. Discord recommended for personal projects.
  - **Q7** — Webhook URL acquisition: (a) paste manually,
    (b) walk-through via `templates/notifications/SETUP.md`,
    (c) Discord-only auto-acquire via `claude-in-chrome` (best-effort,
    falls back to paste on any failure). Validates URL shape via
    `ensure-notification-webhook.sh`.
  - **Q8** — GitHub PAT (read-only): paste or walk-through. Validates
    PAT shape (ghp_* / github_pat_* / 40-hex). Saves to the same
    `.notification.env` as Q7.
  - **Q9** — OCI VM: provision now / use existing host / skip. Provision
    path asks Q9a VM name (default `kirin`), Q9b region (Osaka /
    Tokyo / Ashburn / Frankfurt / custom), Q9c SSH key filename
    (default `kirin_oracle_cloud.key`). Invokes `ensure-oci-vm.sh`
    + `setup-oci-vm.sh` to provision + deploy + start cron end-to-end.

**Already-configured detection (option α)**: Each of Q6/Q8/Q9 first
checks for prior config in `.my-harness/.notification.env` or
`.my-harness/.oci-vm.env`. If present, the current value is shown
(URL/PAT masked to first 20 chars) with a Keep/Change prompt. Q7 is
skipped when Q6 was answered "Keep".

#### `templates/notifications/SETUP.md` (438 lines, bilingual JA-first)

Step-by-step account creation + secret generation walkthroughs:

  1. **Discord** — sign up, create server (optional), Channel Settings
     → Integrations → Webhooks → Copy URL
  2. **Slack** — workspace creation, app, Incoming Webhook activation
  3. **Microsoft Teams** — Channel → ⋯ → Connectors → Incoming Webhook
  4. **GitHub fine-grained PAT** — exact scopes (contents / issues /
     pull-requests / actions, all Read-only), one-time visibility
     warning, `.gitignore` reminder
  5. **Oracle Cloud** — account creation (credit-card requirement is
     explained in bold), API key generation in User Settings, the
     `~/.oci/config` template with `chmod 600 ~/.oci/oci_api_key.pem`
     warning, "never commit the private key" warning

Plus a troubleshooting table and a final "Where the secrets live" recap.

### Tests

23/23 bats + 11/11 spawn-lane still pass (no script changes in this
commit — SKILL.md + docs only).

### Open items (flagged by the executor)

- Auto-acquire fallback on Slack/Teams currently goes straight to paste
  rather than re-showing Q7. Could be a 5-line change if we want the
  full 3-option re-prompt.
- "Already have one" OCI path sets `OCI_VM_REGION=unknown` since the
  user only provides IP + SSH key. Verify against `setup-oci-vm.sh`'s
  expected inputs before relying on it.

---

## [7.15.0] — 2026-05-12

### Added — Steps C + D of the notification rework (4 new scripts + 9 bats tests)

These scripts are the building blocks; SKILL.md will orchestrate them
with `AskUserQuestion` in the next commit.

#### `scripts/ensure-notification-webhook.sh`
Persists `NOTIFICATION_SERVICE` + `NOTIFICATION_WEBHOOK_URL` to
`<root>/.my-harness/.notification.env` (chmod 600). Validates URL shape
per service:
  - Discord: `https://discord.com/api/webhooks/<id>/<token>`
  - Slack: `https://hooks.slack.com/services/T.../B.../xxx`
  - Teams: `https://*.office.com/...` or `https://*.webhook.office.com/...`
Exit codes: 0=saved, 1=bad service, 2=bad URL shape, 3=no URL supplied
(= signals SKILL.md to AskUserQuestion). Service `none` wipes the file
cleanly (= opt-out).

#### `scripts/ensure-github-pat.sh`
Appends/updates `GH_TOKEN` in the same `.notification.env`. Validates
PAT shape: `ghp_*` / `github_pat_*` / legacy 40-hex classic. Exit 3
when no PAT supplied (= SKILL.md prompts).

#### `scripts/ensure-oci-vm.sh`
Idempotent OCI VM provisioner via the `oci` CLI:
  1. SSH key auto-generation (`ssh-keygen -t ed25519`) if not present
  2. `~/.oci/config` existence check (multi-line setup guide on miss)
  3. Discovers an Always-Free A1.Flex AD in `<region>` (tries up to
     3 ADs with `Out of Host Capacity` retry loop)
  4. Discovers latest Oracle Linux 9 ARM image
  5. Reuses or creates default VCN+subnet
  6. Launches `VM.Standard.A1.Flex` with 4 OCPU + 24 GB RAM (the
     Always-Free maximum) with `--wait-for-state RUNNING`
  7. Persists state to `.my-harness/.oci-vm.env`
  8. Idempotency: if `.oci-vm.env` exists AND the instance is still
     `RUNNING`, skip everything

#### `scripts/setup-oci-vm.sh`
After `ensure-oci-vm.sh` completes, SSH into the VM and bootstrap the
daily-progress bot end-to-end:
  1. SSH connectivity test (`ssh -o ConnectTimeout=10`)
  2. Install Node LTS + Claude CLI + gh + jq + curl on the VM
  3. Read user's local `~/.claude/.credentials.json` for the OAuth
     token (errors with `claude login` hint if missing)
  4. Detects `REPO_OWNER`/`REPO_NAME` from `git -C $ROOT remote get-url
     origin`
  5. `scp` the daily-progress-bot/ directory to the VM
  6. Build the bot's `.env` on the VM (CLAUDE_CODE_OAUTH_TOKEN +
     NOTIFICATION_* + GH_TOKEN + REPO_*) with chmod 600
  7. Smoke test `daily-progress.sh` on the VM
  8. Install the crontab from crontab.example
  9. Print success summary with SSH command

### Added — `tests/bats/ensure-notification-webhook.bats` (9 tests)

  - rejects invalid service
  - service=none with prior config → wipes file
  - service=none with no prior config → exits 0
  - discord with valid URL writes file with **chmod 600** (verified
    via `stat` — `ls -l` is unreliable on macOS due to `@`/`+`)
  - discord with malformed URL → exit 2
  - slack with valid URL writes file
  - teams with both URL formats writes file
  - no URL provided → exit 3 (signals AskUserQuestion needed)

### Total test suite

23 bats tests (was 14) + 11 spawn-lane tests, all passing.

### Remaining

Next commit: `skills/my-harness-init/SKILL.md` Phase 1 questions
(N-1/N-2/N-3 + O-1〜O-5), invocation of these scripts, and the
"existing-config detected → confirm or re-prompt" behavior (option α).

---

## [7.14.2] — 2026-05-12

### Added

- **`templates/dotnpmrc`** — `.npmrc` template that bootstrap.sh
  installs as `dev/.npmrc` for new projects whose package manager is
  `pnpm`. Settings:
  - **`minimum-release-age=4320`** (= 4320 minutes = 3 days) — refuses
    to install package versions that have been on the registry for
    less than 3 days. Blocks typosquats, retracted releases, and
    malicious publications that get taken down within hours.
  - `frozen-lockfile=true` — installs from lockfile only; force a
    deliberate `pnpm install --no-frozen-lockfile` to add/update deps.
  - `audit-level=high` — quiet install-time advisories below `high`
    (the `husky pre-push` hook runs `pnpm audit --audit-level low`
    which is stricter; both gates working in concert).
- **`scripts/bootstrap.sh`** — copies `dotnpmrc` to `dev/.npmrc` when
  `PACKAGE_MANAGER=pnpm` and no existing `.npmrc` is present (= won't
  clobber a user-edited file).

### Why 3 days

Most supply-chain attacks on npm get reported and the package
unpublished within hours to days. A 3-day quarantine window blocks
the dangerous initial-release period while staying short enough to
not strand projects on outdated security patches.

### Scope

`.npmrc` is only placed in **generated projects** (`dev/`), not in
the harness root (`my-harness-generator/`). The harness itself has
no `package.json` and never runs `pnpm install` against its own
directory — only the generated projects do.

---

## [7.14.1] — 2026-05-12

### Added — Step B of the Phase-1-init notification rework

- **`flake.nix`** gains `pkgs.oci-cli` in `buildInputs`. The Oracle
  Cloud CLI is now available inside `nix develop` on every platform
  (nixpkgs lists it as 3.81.0 with `darwin / linux / windows / freebsd`
  in `meta.platforms`, so no conditional gate needed). This is the
  prerequisite for Step D — `scripts/ensure-oci-vm.sh` will use
  `oci compute instance launch` to provision the daily-progress-bot
  VM declaratively rather than asking the user to click through the
  Web Console.

### Verified

- `nix flake check` on aarch64-darwin: all checks passed
- 14/14 bats + 11/11 spawn-lane still pass

---

## [7.14.0] — 2026-05-12

### Changed — multi-service notification (Step A of the Phase-1-init flow)

The `daily-progress-bot` is now service-agnostic. Discord, Slack, and
Teams webhooks are all supported with the same scripts; the choice is
a single env var.

- **New file `lib/post-notification.sh`** — shared helper that
  dispatches a `post_notification "<title>" "<body>" "<color>"` call
  to the right service-specific payload builder. Three payload
  generators:
  - Discord: Embed with title / description / color / timestamp
  - Slack: Block Kit (header + section with mrkdwn body)
  - Teams: MessageCard with themeColor / title / text
- **`daily-progress.sh` and `event-watch.sh`** — replaced hardcoded
  Discord `curl` blocks with a single `post_notification` call.
  Source the helper near the top, then reuse the same one-liner.
  Both scripts still accept legacy `DISCORD_WEBHOOK_URL` env var as
  a fallback for already-deployed bots.
- **`.env.example`** — new vars `NOTIFICATION_SERVICE` (`discord` /
  `slack` / `teams`; default `discord`) and `NOTIFICATION_WEBHOOK_URL`
  replacing the old `DISCORD_WEBHOOK_URL`. Comments document where
  to obtain the webhook URL for each service.

### Fixed

- **Bash parse error in `daily-progress.sh`** — an unescaped
  apostrophe inside a `${VAR:?word}` parameter expansion's `word`
  swallowed all quote tracking until EOF (bash's quote-tracking
  rules inside `${...:?...}` differ from ordinary `"..."` strings).
  Bash reported the error at line 126 but the actual culprit was line
  32. Fixed by rewording the error message to avoid the apostrophe
  (`service's docs` → `services docs`).

### Step A done. Remaining steps (planned):

- B: `flake.nix` adds `oci-cli`
- C: `scripts/ensure-notification-webhook.sh` + Phase 1 Q-A/Q-B
  (claude-in-chrome auto-acquire → manual paste fallback)
- D: `scripts/ensure-oci-vm.sh` + Phase 1 Q-C/Q-D/Q-E
  (`~/.oci/config` check → VM provision or instructions)
- E: `templates/notifications/SETUP.md` (account-creation walkthroughs
  for Discord / Slack / Teams / OCI, EN + JA)

---

## [7.13.0] — 2026-05-12

### Added — three Discord notification routes

(1) **GitHub Actions → Discord (event-driven, instant)**
  - `templates/github/workflows/_reusable-discord-notify.yml` — reusable
    workflow that posts a Discord embed via `secrets.DISCORD_WEBHOOK_URL`.
    When the secret is missing, exits 0 silently (optional design — the
    workflow runs on every project but only acts when the user opts in).
  - Supports optional `mention_role_id` for on-call role pings.
  - `pr-to-main.yml` now invokes `_reusable-discord-notify.yml` from a
    new `discord-on-failure` job that triggers when **quality / e2e /
    security** gates fail. Body line includes which gate failed.

(2) **OCI VM → Discord — hourly event-watch (Claude-judged)**
  - `templates/oracle-cloud/daily-progress-bot/event-watch.sh` — runs
    every hour, collects GitHub events since last invocation (state
    file `~/daily-progress-bot/.last-event-watch`), asks Claude to
    decide if anything is notable. Discord post only happens when
    Claude judges there's something worth saying (= ignores routine
    commits, normal PRs). Stays silent when the project is quiet to
    avoid notification noise.
  - Always reminds about open `priority/p1` issues, even if no new
    activity — keeps urgent work visible.
  - `crontab.example` updated with `0 * * * *` entry alongside the
    existing `0 9 * * *` daily entry.

(3) **OCI VM → Discord — daily progress (already existed in 7.12.0)**
  - `daily-progress.sh` unchanged.

### Updated

- `templates/oracle-cloud/daily-progress-bot/README.md` — added "2 つの
  cron が動きます" section documenting daily-progress vs event-watch
  responsibilities, and the silent-skip condition for event-watch.

### Division of labor (intentional)

  - **Real-time / latency-sensitive** (CI failure, security alarm) →
    GitHub Actions side, via `_reusable-discord-notify.yml`. Fires
    seconds after the failure.
  - **Judgment-required / noise-suppressed** (which of these new
    events actually matters?) → OCI VM `event-watch.sh`. 1-hour delay
    is acceptable for these; Claude's filtering is the value.
  - **Daily wrap-up** → OCI VM `daily-progress.sh`. Always posts at
    18:00 JST.

---

## [7.12.0] — 2026-05-12

### Added

- **`templates/oracle-cloud/daily-progress-bot/`** — optional scaffold
  for a "Claude reads GitHub at 18:00 and posts a Japanese summary to
  Discord" bot. Designed to run on an Oracle Cloud Always-Free VM under
  cron, using the user's existing Claude Pro/Max subscription via
  `CLAUDE_CODE_OAUTH_TOKEN`.
  - **Cost: ¥0** (existing Pro/Max + OCI Always Free + Discord free)
  - **Time precision: seconds** (dedicated VM cron, not GitHub Actions'
    ~15-minute cron delay)
  - **Officially permitted** per Anthropic's Consumer ToS exemption for
    Claude Code CLI ("one human, one subscription, one beneficiary")
  - Files:
      - `daily-progress.sh` — bash script that collects 24 hours of
        commits / opened+closed issues / opened+closed PRs / latest
        workflow runs / `priority/p1` open issues via the `gh` CLI,
        asks `claude -p` to summarize in Japanese as 3-5 emoji-prefixed
        bullets, then posts an embed to the Discord webhook.
      - `.env.example` — `CLAUDE_CODE_OAUTH_TOKEN`, `DISCORD_WEBHOOK_URL`,
        `GH_TOKEN`, `REPO_OWNER`, `REPO_NAME`, optional `LANG_TAG` and
        `LOOKBACK_HOURS`.
      - `crontab.example` — `0 9 * * *` (UTC 09:00 = JST 18:00).
      - `README.md` — full setup walkthrough: OCI VM creation, Node /
        Claude CLI / `gh` / `jq` install, OAuth token transfer from a
        desktop machine, file deployment via `scp`, smoke test, cron
        registration, troubleshooting, and OAuth token rotation
        (~90 days) reminder.
- **`scripts/bootstrap.sh`** — copies `templates/oracle-cloud/daily-progress-bot`
  to `dev/oracle-cloud/daily-progress-bot/` so projects can opt in
  later by following the README. Skipped silently if already present.

### Why OCI VM instead of GitHub Actions for the daily cron

GitHub Actions' `schedule` event:
  - ~15 minute delay (officially documented as "best-effort, not guaranteed")
  - extra delay near the top of an hour (official guidance: "avoid the
    top of the hour")
  - workflow auto-disabled after 60 days of repo inactivity
  - workflow disabled on forks
OCI Always-Free VM cron has none of these — it's a dedicated scheduler
with seconds precision.

### Why subscription (Pro/Max) instead of API key

- Cost: ¥0 (subscription already paid) vs ~$1-2/mo with API key
- Allowed by Anthropic's Consumer ToS: "Claude Code CLI running on your
  own computer is Anthropic's official product built for scripted and
  automated use, and the Consumer ToS exempts it from the prohibition
  on automated access."
- Constraint: `one human, one subscription, one beneficiary` — fine for
  a personal/sole-developer's own daily progress digest; not OK for
  multi-developer teams (use Anthropic Team Plan instead).

---

## [7.11.1] — 2026-05-12

### Changed

- **`templates/husky/pre-push`** — tightened `pnpm audit` from
  `--audit-level high` to `--audit-level low`. Push is now blocked
  by **any** advisory at severity `low` / `moderate` / `high` /
  `critical`; only purely-informational notices (`info`) pass.
  Rationale per user: "high 以外も禁止させてほしい" — moderate / low
  vulnerabilities should be resolved at push time rather than
  accumulating async-managed by Renovate / Dependabot.

---

## [7.11.0] — 2026-05-12

### Discovered (no work needed)

- **OWASP ZAP `stage → main` PR gate is already implemented** —
  `templates/github/workflows/_reusable-security.yml` runs
  `zaproxy/action-baseline@v0.13.0` against `vars.STAGE_URL` whenever
  `pr-to-main.yml`'s `security` job fires (`github.head_ref == 'stage'`),
  with `fail_action: true` (HIGH severity blocks the PR merge) and
  `allow_issue_writing: true` (findings auto-file GitHub issues), plus
  a follow-up `maybeCreateIssue` step that adds `[security:zap]
  baseline failed` issue with labels `security` and `priority/p1`.
  User's request for "stage → main で ZAP / 問題があれば issue 自動作成
  / その issue を最優先" was already met by this existing template.

### Added

- **`flake.nix`** — added `pkgs.zap` to `buildInputs` via
  `lib.optionals stdenv.isLinux [ zap ]`. Means GitHub Actions runners
  (= Linux) and Linux developers get ZAP via `nix develop --command
  zap.sh ...` without leaving the Nix-managed environment. macOS
  developers don't need ZAP locally (the workflow runs against the
  staged URL in CI); the `optionals` gate avoids the
  `meta.platforms = linux only` build failure on darwin without needing
  `NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1`.
- **`templates/husky/pre-push`** — added `pnpm audit --audit-level high`
  step. The pre-push hook now covers: gitleaks (history scan) +
  forbidden-patterns + biome (lint/format) + tsc (typecheck) + vitest
  (tests) + **pnpm audit (dependency vulnerabilities, high+)**. Lower
  severity vulnerabilities (moderate/low) intentionally don't block —
  Renovate / Dependabot handle them async.

### Changed

- **`skills/harness-team-lead/scripts/list-pending-issues.sh`** —
  pending issues are now sorted so anything with `priority/p1` or
  `priority:highest` label appears at the top of the dispatch queue,
  ahead of normal feature issues. This lets the ZAP / MobSF
  security-scan workflows file findings that the lead picks up
  immediately on the next session, ahead of regular feature work.
  Sort is stable: within the same priority bucket, ascending issue
  number (= roughly chronological).

### Verified

- `flake check` passes on aarch64-darwin (the dev shell still builds
  with the conditional zap; on darwin the `lib.optionals` evaluates to
  `[]` so no unsupported package gets pulled).
- All 14 bats tests + 11 spawn-lane tests still pass.
- `bash -n` clean on `pre-push` and `list-pending-issues.sh`.

---

## [7.10.0] — 2026-05-12

### Added

- **`tests/bats/`** — bats (Bash Automated Testing System) suite for
  the harness's own shell scripts. 14 tests across 3 files, all
  passing:
    - `ensure-codex-effort.bats` (6 tests) — validates the
      `model_reasoning_effort` writer: invalid level rejection,
      every valid level accepted, fresh-file write, idempotency
      (existing value preserved), top-level placement above `[section]`
      headers.
    - `ensure-codex-project-trust.bats` (4 tests) — validates the
      `[projects."<root>"] trust_level = "trusted"` appender:
      empty-file append, idempotency, preservation of unrelated
      sections, refusal to overwrite an existing `untrusted` entry.
    - `find-existing-state.bats` (4 tests) — validates the
      `.my-harness/init-state.json` walker: exits 1 when absent,
      finds at depth 0, depth 1, depth 3.
- **`tests/run-bats.sh`** — convenience runner. Auto-discovers all
  `*.bats` files; accepts a pattern arg to filter (`run-bats.sh
  ensure-codex` runs only the matching files); accepts `--tap` and
  other bats flags. Checks for `bats` on PATH and gives a helpful
  message if it isn't.
- **`flake.nix`** — added `pkgs.bats` to `buildInputs` so the dev
  shell ships bats out of the box. No env-var override, no PATH
  surgery — just `nix develop` and `bats` is there.

### macOS path note

bats tests that create temp directories and then invoke scripts that
use `cd $ROOT && pwd -P` (which `ensure-codex-project-trust.sh` does
to resolve the absolute path) must themselves run `pwd -P` on the
mktemp output. macOS's `mktemp -d` returns `/var/folders/...` but
`pwd -P` returns `/private/var/folders/...` (the underlying physical
path of the `/var` symlink). The test helper does this normalization
in setup().

### Why bats, not bash-only

- Per-test isolation (each `@test` has its own `setup` / `teardown`)
- Assertion failures point to the exact line that failed, not just
  "exit 1 somewhere"
- TAP output for CI integration is one flag away
- `nix develop` has bats by default now

The legacy `tests/spawn-lane-decision.sh` (custom PASS/FAIL format)
stays in place — bats is for new tests, not a forced migration.

---

## [7.9.2] — 2026-05-12

### Added

- **`rules/spec-style.md`** — canonical rule: spec files describe
  WHAT the system does and the constraints, not HOW. No TypeScript /
  SQL / Bash / framework calls / Tailwind class strings / config-file
  contents inside spec artifacts (`dev/docs/spec/*.md`,
  `init-state.json`'s `discoverySheet`, etc.). The spec must survive
  a framework swap without rewriting; if it can't, it had
  implementation details that belonged in code.

  What IS allowed (defines the contract, not the implementation):
    - API path strings (`POST /api/auth/login`)
    - HTTP status codes (`422 VALIDATION_FAILED`)
    - Hex colors locked in by brand identity (`#14b8a6`)
    - Numeric thresholds (`bcrypt cost ≥ 12`, `rate limit 100/min`)
    - JSON request/response shape examples
    - Identifiers in the data model (`User.email`)
    - Mermaid diagrams, ASCII state machines, pseudo-code

  Translation table shows how to rewrite the typical code-shaped
  requirements as behavior constraints ("`bcrypt.hash(password, 12)`"
  → "Passwords are hashed with bcrypt, cost factor ≥ 12, before
  persistence").

  Exemption: `rules/*.md` files that describe coding standards (TDD,
  Drizzle conventions, etc.) intentionally show right/wrong code —
  those are guidelines, not specs.

- **Cardinal-rule reference** in `skills/my-harness-init/SKILL.md`
  pointing at `rules/spec-style.md` (alongside `communication.md`
  and `codex-handoff.md`). Claude reads it once at skill start; does
  not restate inline.

### Why

Specs that embed code anchor Codex on Claude's specific syntax instead
of letting Codex pick the right implementation for the actual
framework, couple the spec to one toolchain (re-writing spec on
framework swap), double the review surface (spec changes diff
alongside code changes), and rot when refactors update code but not
the embedded snippets.

---

## [7.9.1] — 2026-05-12

### Added

- **rules/codex-handoff.md — "Spec changes vs implementation" section**.
  Beyond the existing code-vs-prose boundary, there's a higher layer:
  **decisions vs execution**. Claude owns decisions (requirements / API
  contracts / data model / UI flow / scope / security posture / perf
  budgets — anything that changes WHAT the system does), Codex owns
  execution (anything that changes HOW the system achieves the existing
  WHAT — refactors, bug fixes, tests, formatting, log additions, code
  documentation).

  Rule of thumb: **WHAT** changes → Claude; **HOW** changes → Codex.

  Concrete examples table covers the typical confusing cases ("add 2FA",
  "button doesn't activate on click", "move logic to a service",
  "switch password→OAuth", "add tests for pricing service", "GDPR-
  classify every entity", "tighten rate limit") and shows which side
  owns each.

  When a Codex turn discovers the spec is incomplete or contradictory,
  Codex does NOT invent the missing decision — it reports "spec
  incomplete: <question>" back through the lane and waits for Claude
  to extend the spec.

---

## [7.9.0] — 2026-05-12

### Changed

- **reviewer and e2e-reviewer now run as Codex + Claude dialog** when
  `USE_CODEX=yes` AND the respective `USE_CODEX_REVIEWER` /
  `USE_CODEX_E2E_REVIEWER` flag is `yes`. Previous behavior was "Codex
  produces the report, Claude forwards" — single-source review that
  could ship Codex's false positives or miss issues Claude would have
  caught. New behavior: both reviewers do an **independent pass**, then
  **cross-check** each other's findings, and reach an agreed-on
  consolidated list.

### Dialog protocol (3-round cap)

  - **Round 1 — Independent reviews (parallel)**: Codex produces JSON
    findings via codex-ask.sh; Claude produces an equivalent JSON list
    by reading the diff / test output directly.
  - **Round 2 — Cross-check**: Each side reads the OTHER's findings and
    classifies each item as `keep` / `reject (specific reason)` /
    `clarify (question)`. Codex's classifications come back through a
    second codex-ask.sh call on the same session.
  - **Round 3 — Resolution (only if disagreements remain)**: Codex is
    asked to pick the technically correct side in one sentence per
    disputed finding.
  - Unresolved after 3 rounds → BOTH positions written verbatim with
    `disputed=true`, no silent picking.

### Why dialog over solo Codex

  - Codex false positives get filtered (Claude rejects with a specific
    reason)
  - Claude blind spots get caught (Codex flags issues Claude misses)
  - The analyst sees an honest "two reviewers agreed" signal — much
    stronger than either reviewer alone
  - The dialog is bounded (3 rounds) so token / latency budget stays
    predictable

### Failure handling

  - codex-ask.sh exit 100 (auth) → `mode=dialog rescue=<path>`
  - Other Codex error → `mode=dialog` with explicit `blocked-codex-error`
    status; the agent does NOT silently fall back to Claude-solo so the
    analyst knows dialog mode failed

### Activation

Only when BOTH `USE_CODEX=yes` AND the role's `USE_CODEX_*=yes` are set
in `.config`. Either off → falls back to Claude-only checklist /
synthesis (existing behavior).

---

## [7.8.0] — 2026-05-12

### Added

- **`rules/codex-handoff.md`** — canonical rule: when `USE_CODEX=yes`,
  Claude is the orchestrator, NOT the code author. No diffs, no
  snippets, no "starter" function bodies, no `useState(...)`-style
  speculation. Claude carries requirements + verification; Codex
  carries the code. The rule defines the boundary as "executable
  code" (TS / JS / Bash / Python / SQL / Tailwind class strings —
  anything with identifier names + syntax) and lists six explicit
  exceptions where Claude can still write code: USE_CODEX=no, trivial
  one-liners, documentation files, mechanical config edits, direct
  user override, and harness-internal code (since the harness is the
  tool, Codex is for the projects the tool generates).
  - Common rationalizations table flags the typical thoughts that
    precede breaking the rule ("It's just a simple fix" / "Codex
    won't get this nuance" / "I'm just suggesting an approach").
- **Cardinal-rule reference in two skill files** so Claude reads it
  every session it might do code work:
    - `skills/my-harness-init/SKILL.md` (Cardinal rules section)
    - `skills/harness-team-lead/SKILL.md` (new "Codex handoff" section
      between Communication and Honesty)
  Both files point to `rules/codex-handoff.md` as the canonical source
  and do not restate the rule inline (per existing harness convention).

### Why

Pre-empting Codex with Claude's own code suggestion is a process bug:
the engineer / Codex anchors on Claude's guess instead of solving the
problem freshly, two different proposals end up in the user's review
queue, and the chain-of-authorship gets muddled (tests pass / fail for
"Claude's version" or "Codex's version"). Cleaner role separation —
Claude orchestrates, Codex codes — is faster and produces less
review thrash.

The rule is unconditional inside the listed scope but has explicit
exceptions for cases where routing through Codex costs more than it
saves (typo fixes, prose edits, etc.).

---

## [7.7.2] — 2026-05-12

### Changed

- **Phase 1 Setup Q5.b now asks the user `xhigh` vs `high`** instead of
  hardcoding `xhigh`. AskUserQuestion presents the two options with a
  short tradeoff description (xhigh = best output / slower / more
  usage; high = faster / lighter / slightly less thorough on multi-step
  reasoning). The user's choice is passed to `ensure-codex-effort.sh`,
  which still idempotently writes / preserves the value in
  `~/.codex/config.toml`.

Underlying script unchanged (it already validated the level against
the SDK's `ReasoningEffort` literal and accepted any of
`none|minimal|low|medium|high|xhigh`); only the SKILL.md flow that
calls it now ends with a real user choice rather than a baked-in
default. Lower levels (`medium` and below) intentionally aren't
offered via the question — they're available via direct
`ensure-codex-effort.sh <level>` for anyone who wants them.

---

## [7.7.1] — 2026-05-12

### Added

- **`scripts/ensure-codex-effort.sh`** — sets Codex's global
  `model_reasoning_effort` in `~/.codex/config.toml`. Default level is
  `xhigh` (the highest of six steps: `none|minimal|low|medium|high|xhigh`),
  which is the right default for harness workloads (Phase 5 image
  generation + refinements + implementation-phase Codex work all benefit
  from deeper reasoning). Idempotent: if the user already set a value
  it's preserved (no overwrite); otherwise the line is inserted at the
  top level of config.toml above any `[section]` headers. Validates the
  level against the SDK's `ReasoningEffort` literal (rejects typos like
  `ultrahigh`).
- **SKILL.md Phase 1 Setup Q5 split into three steps** (was two):
    - Q5.a — `ensure-codex-project-trust.sh "$ROOT"`
    - Q5.b — `ensure-codex-effort.sh xhigh` (NEW)
    - Q5.c — `ensure-codex-daemon.sh "$ROOT"`
  Both Q5.a and Q5.b touch `~/.codex/config.toml` and must complete
  before Q5.c brings the daemon up, since the daemon reads config.toml
  at start time.

### Why

The SDK exposes reasoning effort via `TurnOverrides.effort` per-turn
and `model_reasoning_effort` at global config.toml level. Setting the
global default once (instead of injecting `TurnOverrides` on every
codex-ask.sh call) is simpler and works for both harness Codex
invocations AND the user's own direct `codex` CLI usage.

Reference: https://developers.openai.com/codex/config-reference

---

## [7.7.0] — 2026-05-12

Phase 5 is now a clean **three-stage** flow at the user's request:

```
Stage 1  PNG + crop, all screens (gen-page-auto.sh per screen)
Stage 2  HTML, all (form-factor, screen) pairs (gen-html-all.sh once)
Stage 3  Claude polish of every HTML
```

### Added

- **`scripts/gen-html-all.sh`** — second-stage batch driver. Reads
  `.config`, scans `dev/docs/design/parts/*/*/manifest.json` to discover
  every settled (form-factor, screen) pair, then calls `gen-page-html.sh`
  on each. Sort order is **PC before Mobile, then by screen-slug** so
  HTMLs open side-by-side in the same order as the PNGs. Auto-opens every
  produced HTML together at the end. Skips silently when `USE_CODEX != yes`.

### Changed

- **`gen-page-auto.sh` no longer generates HTML inline.** Previously each
  per-screen invocation did `page → crop → html` end-to-end; now it does
  `page → crop` only, deferring HTML to the batch stage. This satisfies
  the user's preference for "all PNGs first, all HTMLs second" — the
  entire project's visual identity is reviewed/approved across every
  screen before any markup is committed. Stage-2's Codex HTML session
  also benefits because it sees the FINAL set of mocks + style_guide
  rather than the work-in-progress state.
- **SKILL.md Phase 5 documents the three stages explicitly.** Stage 1
  (PNG + crop per screen), Stage 2 (HTML batch via gen-html-all.sh),
  Stage 3 (Claude polish per HTML).

### Migration

For mid-Phase-5 projects: nothing automatic, but the new flow expects
`gen-page-auto.sh` to be re-runnable without producing HTML, so any old
HTML output stays valid. Run `gen-html-all.sh` once when ready to
batch-generate HTML for the whole project.

---

## [7.6.0] — 2026-05-12

### Added

- **Project-scope default model pinning.** `scripts/bootstrap.sh` now
  writes `dev/.claude/settings.json` with `"model": "claude-opus-4-6"`
  on every run (idempotent — if the file already pins a model, it's left
  alone). Any Claude Code session opened under `dev/` (including
  `/harness-team-lead`) uses Opus 4.6 by default. The team-lead is
  orchestration-heavy but output-light, so 4.6 is the cost/latency
  sweet spot.
  - `model:` cannot be set on a Skill's frontmatter — Skills run on the
    caller's session model. The correct lever is `~/.claude/settings.json`
    or per-project `<root>/.claude/settings.json`. The harness uses the
    latter.
  - Existing logic for `claudeMdExcludes` (USE_GLOBAL_CLAUDE=no) merges
    cleanly on top of the new model field via `jq`.

### Changed

- **`gen-page-html.sh` is now Step 1 of TWO for Phase 5 HTML, not the
  final deliverable.** Codex's `file_write` tool produces a one-shot
  HTML and cannot iterate on layout, so its output routinely ships with
  3-8 layout defects per screen (overflow, wrong column counts, missing
  aria, manifest-vs-markup mismatches). Claude polishes after Codex via
  a MANDATORY second step:
    1. `Read` the page-mock PNG (multimodal vision context)
    2. `open` the HTML in the browser to see the rendered view
    3. Compare PNG vs rendered HTML, list concrete defects
    4. `Edit` the HTML to fix each defect
    5. Loop up to 3 iterations
  SKILL.md Phase 5 documents this as MANDATORY (the polish pass is not
  optional). User-driven refinements after the polish pass may use the
  Codex session OR `Edit` directly.

### Migration

For existing projects that ran `bootstrap.sh` before this version: just
re-run `bootstrap.sh` to add the `model` field to `dev/.claude/settings.json`
(idempotent — won't touch a model field you set manually). The HTML
polish step is a Claude behavior change, no file rewrites needed — the
next time Claude runs `gen-page-auto.sh` it follows the new SKILL.md
flow.

---

## [7.5.0] — 2026-05-12

### Changed

- **Cropped parts now land under `dev/docs/design/parts/<form-factor>/<screen-slug>/`** instead of `dev/public/design/parts/...`. The whole Phase-5 deliverable tree is now homogeneous under `dev/docs/design/` (page PNG, parts grid PNGs, cropped transparent parts, manifest, and the Tailwind HTML written by Claude). This makes the HTML's `<img src>` references a simple `parts/<form-factor>/<screen-slug>/<name>.png` relative path instead of `../../public/design/parts/...`, and treats Phase 5 cleanly as a "documentation / design source-of-truth" output rather than a runtime artifact.
- Updated paths in: `scripts/gen-page-parts.sh` (mkdir, manifest output, prior-style_guide find), `scripts/crop-parts.sh` (ASSET_DIR), `scripts/upscale-part.sh` (ASSET_DIR), `scripts/scaffold-tsx-from-parts.sh` (manifest read).
- Updated SKILL.md Phase 5 — HTML now references parts via the new relative path, output-location docs reflect new location, frontmatter description updated to reflect form-factor + docs/design layout.

### Migration

When the implementation phase wants to serve the parts via a dev server (Next.js / Vite), copy or symlink the parts tree into `dev/public/design/parts/` so requests to `/design/parts/...` resolve. Alternatively, import each PNG directly through the bundler. The `parts.ts` import map (scaffolded by `scaffold-tsx-from-parts.sh`) still writes absolute URLs of the form `/design/parts/...` — those work after the copy/symlink, or you can adjust them per project.

For projects mid-Phase-5: existing parts under `dev/public/design/parts/<...>` stay valid but no longer match the harness's expectations. Move them with `mkdir -p dev/docs/design/parts && mv dev/public/design/parts/* dev/docs/design/parts/`, or rerun `gen-page-auto.sh` + `crop-parts.sh` to produce them in the new location (style_guide inheritance via prior-manifest discovery will pick up only manifests under `dev/docs/design/parts` going forward).

---

## [7.4.0] — 2026-05-12

Phase 5 reorganized around **form factor** (`pc` / `mobile`) instead of
individual platforms, with automatic fan-out based on `.config` and full
session-keep across screens AND form factors so the entire project's
visual identity stays locked from the first artifact onward.

### Changed (BREAKING for in-progress projects only)

- **Mocks are now per form factor, not per platform.** A project that
  selected `web + ios` previously produced `page-web-login.png` AND
  `page-ios-login.png` (two separately-styled artifacts). It now
  produces `page-pc-login.png` AND `page-mobile-login.png` — two
  form-factor variants sharing one locked-in `style_guide`. Form
  factor is derived from platform flags:
    - `pc`     ← `USE_WEB || USE_DESKTOP`
    - `mobile` ← `USE_WEB || USE_IOS || USE_ANDROID`
  This halves the screen-list collection (one list for the whole
  project, not one per platform) and ensures iOS/web-mobile/Android
  share the same mobile mock instead of drifting into 3 visually
  divergent designs.

- **Screen list is collected ONCE per project**, not per platform.
  Phase 5 Q2 now asks "List the 3-5 most-traveled screens for this
  app" instead of "List the 3-5 screens for the <web> build" repeated
  per chosen platform.

### Added

- **`scripts/gen-page-auto.sh`** — single entry point per screen:
  reads `.config`, derives `NEED_PC` / `NEED_MOBILE`, calls
  `gen-page-parts.sh` once per needed form factor in order PC →
  Mobile, then opens every produced PNG together at the end.
  Users no longer have to ask for "make a PC mock" or "make a
  mobile mock" — the harness reads platform flags and produces the
  right set automatically.

- **Project-wide `style_guide` inheritance across invocations.**
  `gen-page-parts.sh` now scans every existing `manifest.json` under
  the project for a `style_guide` field on entry. If found, it's
  injected into the Turn-1 prompt as IMMUTABLE INVARIANTS that
  Codex must honor verbatim (palette hex / illustration style /
  line weight / character design / decorative motifs all locked).
  Combined with the project-wide Codex session (which keeps prior
  generated images visible as edit-mode context), this guarantees
  every later screen and every later form factor inherits the
  first artifact's visual identity. Layout / spacing / type scale /
  CTA placement are the ONLY things Codex is allowed to reinvent
  per form factor.

### Removed

- **`scripts/gen-page-cross-platform.sh`** — its role is fully
  subsumed by `gen-page-auto.sh`. Cross-form-factor side-by-side
  comparison is the new default behavior, not a separate command.

### Prompts

- **`prompts/codex-page-mock.md`** — `<PLATFORM>` placeholder
  renamed to `<FORM_FACTOR>` throughout. New `<PRIOR_STYLE_GUIDE_BLOCK>`
  placeholder that `gen-page-parts.sh` fills with either:
    - (a) the prior-run `style_guide` as IMMUTABLE INVARIANTS, with
          explicit "inherit palette/style/character — reinvent layout
          for the new form factor" guidance, OR
    - (b) a "this is the first artifact, decide every value, choose
          ones that work for BOTH form factors" prompt.
- **`prompts/codex-parts-grid-edit.md`** — `<PLATFORM>` placeholder
  renamed to `<FORM_FACTOR>` throughout.

### File layout

- `dev/docs/design/page-<form-factor>-<screen>.png`
- `dev/docs/design/page-<form-factor>-<screen>.html`
- `dev/docs/design/parts-grid-<form-factor>-<screen>-N.png`
- `dev/public/design/parts/<form-factor>/<screen>/<name>.png`
- `dev/public/design/parts/<form-factor>/<screen>/manifest.json`
- `dev/src/components/design/<form-factor>/<screen>/parts.ts`

### Migration

For projects mid-Phase-5: existing `page-web-login.png` etc. stay
valid (file paths just diverge from the new convention). To migrate
to form-factor naming, delete the in-progress screen's artifacts and
rerun `gen-page-auto.sh "$ROOT" "<screen>" "$PROJECT_NAME"` — it
will produce the new pc/mobile pair and inherit any
already-established style_guide via prior-manifest discovery, so the
new artifacts visually match the old ones.

---

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
