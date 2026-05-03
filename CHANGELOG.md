# Changelog

All notable changes to this plugin documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [SemVer](https://semver.org/spec/v2.0.0.html)

## [1.0.0] - 2026-05-04

### Added (Plugin first release)

- Claude Code plugin としてパッケージ化（`marketplace.json` + `plugin.json`）
- 20 個の skills:
  - 最上位 2: `my-harness-generator`, `my-harness-init`
  - 規約 10: `harness-tdd`, `harness-hono-clean-arch`, `harness-drizzle-rules`, `harness-nix-pure`,
    `harness-design-rules`, `harness-jsdoc`, `harness-git-discipline`, `harness-no-hardcoded-secrets`,
    `harness-mask`, `harness-codex-consult`
  - shell ラッパー 8: `harness-new-feature`, `harness-new-hotfix`, `harness-resolve-conflict`,
    `harness-sync-features`, `harness-check-codex-auth`, `harness-check-secrets`,
    `harness-setup-secrets`, `harness-branch-protection`
- 5 個の agents（4 レーン並列開発用）: `harness-team-lead`, `harness-analyst`, `harness-engineer`,
  `harness-e2e-reviewer`, `harness-reviewer`
- 2 個の hooks（`hooks.json`）:
  - `UserPromptSubmit`: ユーザー入力を mask-secrets.sh で自動マスクして dev/docs/talk/<日付>.md に追記
  - `Stop`: Claude の最終応答を transcript から抽出してマスク後追記
- 22 本の shell スクリプト（bootstrap / codex-ask / mask-secrets / 各種 setup / hooks 等）
- 機密マスキング（9 種パターン: API キー / AWS / メール / 電話 / カード / JWT / PEM / URL認証 / KEY=value 形式）
- bootstrap の `--config <file>` 非対話モード（`/my-harness-init` から呼び出すため）
- Codex CLI session resume による真のマルチターン対話
- USE_GITHUB_ISSUES=no 対応（`docs/task/auto/<id>.md` フォールバック）
- USE_GLOBAL_CLAUDE 切替（個人 global 引き継ぎ / プロジェクト独立配置）
- iOS / Android テンプレート、Cloudflare D1 + Drizzle、Resend、Playwright + Maestro

### Architecture
- skills 中心: 詳細ルールは個別 skill に分割し、Claude が状況に応じて lazy load
- shell は skill 経由で呼ばれる設計（Claude が引数を覚えなくて良い）
- hook で機械的に talk を記録（Claude の書き忘れを保険）
- pre-commit で gitleaks + check-forbidden-patterns が二重防御
