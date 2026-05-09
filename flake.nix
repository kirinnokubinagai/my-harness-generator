{
  # Top-level flake for the my-harness-generator RUNTIME itself.
  # Goal: a freshly-bought Mac (Apple silicon or Intel) or Linux box (x86_64
  # or aarch64) with ONLY Nix installed should give a working harness via
  # `nix develop` or `direnv allow`. No brew, no global npm install -g, no
  # `pip install --user`, no Homebrew Python venv.
  #
  # Windows note: Nix does not run natively on Windows. Use WSL2 (Ubuntu
  # recommended) — inside WSL2 this flake works exactly like Linux.
  #
  # Provides:
  #   - codex   (@openai/codex CLI; from nixpkgs)
  #   - rtk     (Rust Token Killer; from nixpkgs)
  #   - python  (3.13 + codex-app-server-sdk + websockets + pydantic, all pinned)
  #   - jq, curl, gnused, gnugrep, gawk, findutils, coreutils, bash
  #
  # The shellHook exports MY_HARNESS_CODEX_PY so codex-ask.sh / codex-daemon.sh
  # use the Nix python instead of looking for ~/.codex/my-harness-venv. The
  # venv-based fallback (scripts/install-codex-sdk.sh) is preserved for users
  # not running under Nix.
  #
  # Templated projects scaffolded BY this harness have their own separate
  # dev flake at templates/nix/flake.nix; they are unrelated to this one.
  description = "my-harness-generator runtime — pure Nix dev shell (codex + rtk + Python SDK)";

  inputs = {
    # Use nixos-unstable for the harness itself so we get the current
    # `codex` (0.128+) and `rtk` packages — neither is in the 25.05 stable
    # channel yet (codex@25.05 is 0.1.x, rtk is absent). Generated projects
    # under templates/nix/ stay on 25.05 stable for Node/biome/playwright
    # reproducibility; the two channels are intentionally decoupled.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        py = pkgs.python313;

        codex-app-server-sdk = py.pkgs.callPackage ./nix/codex-app-server-sdk.nix { };

        # Python interpreter with every dependency the harness scripts need.
        # Used as MY_HARNESS_CODEX_PY by codex-app-server-call.py.
        pythonWithSdk = py.withPackages (ps: [
          codex-app-server-sdk
          ps.websockets
          ps.pydantic
        ]);

      in {
        packages = {
          inherit codex-app-server-sdk pythonWithSdk;
          default = pythonWithSdk;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Codex CLI itself (network-pure binary, version-locked via flake.lock)
            codex

            # RTK — PreToolUse hook for Claude Code that compresses Bash output
            rtk

            # Python interpreter with codex-app-server-sdk pre-installed
            pythonWithSdk

            # POSIX baseline used by the bash scripts. Pulling these from Nix
            # rather than the host avoids surprises from BSD tools on macOS
            # vs GNU tools on Linux.
            bash
            coreutils
            curl
            jq
            gnused
            gnugrep
            gawk
            findutils
          ];

          shellHook = ''
            # Point codex-ask.sh / codex-daemon.sh at this flake's Python
            # (which already has codex-app-server-sdk in it) instead of the
            # ~/.codex/my-harness-venv fallback.
            export MY_HARNESS_CODEX_PY="${pythonWithSdk}/bin/python"

            echo "[my-harness] Nix dev shell ready"
            echo "  codex  : $(${pkgs.codex}/bin/codex --version 2>/dev/null || echo unavailable)"
            echo "  rtk    : $(${pkgs.rtk}/bin/rtk --version 2>/dev/null | head -1 || echo unavailable)"
            echo "  python : ${pythonWithSdk}/bin/python ($(${pythonWithSdk}/bin/python --version 2>&1))"

            # If we can't see any Codex sessions yet, the user hasn't logged in.
            # We can't automate `codex login` (it needs a browser), so just nudge.
            [ -d "$HOME/.codex/sessions" ] || echo "[my-harness] run \`codex login\` once to authenticate"
          '';
        };
      });
}
