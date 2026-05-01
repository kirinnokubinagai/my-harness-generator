{
  # 概要: ハーネス用の純粋な開発環境定義。
  #       何も入っていない PC でも `nix develop` 一発で同一の環境が再現される。
  #       direnv（.envrc に `use flake`）と組み合わせて、cd するだけで自動で適用される運用とする。
  description = "Generic harness dev shell (pure Nix, reproducible)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nodejs = pkgs.nodejs_22;
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Node.js ランタイムとパッケージマネージャ
            nodejs
            nodePackages.pnpm
            corepack_22

            # 静的解析・整形・型検査・テスト
            biome
            semgrep
            gitleaks
            trivy

            # E2E テスト
            playwright-driver.browsers
            maestro

            # Android（Kotlin / Jetpack Compose）開発用
            # NOTE: Android SDK Manager（platform-tools / build-tools）は Apple toolchain と同様、
            #       Nix 完全 pure 化が難しいので、Android 利用時のみ別途 ANDROID_HOME を設定する。
            jdk21
            android-tools

            # 機密管理
            sops
            age

            # Git / GitHub 連携
            git
            gh

            # IaC / クラウド連携
            terraform
            awscli2
            wrangler
            flyctl

            # ユーティリティ
            jq
            yq-go
            direnv
            postgresql_16
            sqlite

            # iOS DAST 用（MobSF は docker で起動するため docker / colima を許可）
            colima
            docker-client
          ];

          shellHook = ''
            export PNPM_HOME="$PWD/.pnpm-store"
            export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
            export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
            export MAESTRO_DRIVER_STARTUP_TIMEOUT=60000
            echo "[nix] harness dev shell ready (pure)"
            echo "[nix] node=$(${nodejs}/bin/node --version)  pnpm=$(${pkgs.nodePackages.pnpm}/bin/pnpm --version)"
            echo "[nix] biome=$(${pkgs.biome}/bin/biome --version)  maestro=$(${pkgs.maestro}/bin/maestro --version 2>/dev/null || echo n/a)"
          '';
        };
      });
}
