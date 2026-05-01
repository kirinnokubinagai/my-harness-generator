# iOS テンプレート

> Apple のツールチェーン（Xcode / Swift / iOS Simulator）は **Nix で完全 pure 化できない** ため、
> このディレクトリでは雛形のみ提供し、実際のプロジェクト作成は Xcode で行うことを前提とする。
> Nix 環境で実施できるのは **Maestro による E2E** と **MobSF による静的解析** まで。

## セットアップ手順

1. **Xcode を Apple 公式から導入**（Nix 例外）。
2. プロジェクトテンプレを作成:
   ```
   xcodebuild -create-project -name harness-ios -bundleId com.example.harness
   ```
   または Xcode → File → New → Project → App（SwiftUI / Swift）。
3. **App Bundle ID** は `com.example.harness` に揃えると Maestro / Android と命名統一できる。
4. ビルド:
   ```
   xcodebuild -scheme harness-ios -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```
5. Maestro 実行（ハーネスの `tests/e2e/mobile/` 内 yaml をそのまま流用可能）:
   ```
   xcrun simctl boot "iPhone 16"
   maestro --device booted test tests/e2e/mobile
   ```

## 自動化対象（CI）

- ビルド & 単体テスト: macOS ランナーで `xcodebuild test`
- Maestro E2E: `_reusable-e2e.yml` の maestro ジョブで網羅
- MobSF 静的解析: `_reusable-security.yml` の mobsf ジョブで `.ipa` をスキャン
- TestFlight 配布: `scheduled-db-backup.yml` の testflight-stage ジョブから fastlane pilot で
