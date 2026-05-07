# iOS Template

> Because Apple's toolchain (Xcode / Swift / iOS Simulator) **cannot be fully purified with Nix**,
> this directory provides only scaffolding. Actual project creation is expected to be done with Xcode.
> What can be done in the Nix environment is limited to **E2E with Maestro** and **static analysis with MobSF**.

## Setup Steps

1. **Install Xcode from the official Apple source** (Nix exception).
2. Create a project from the template:
   ```
   xcodebuild -create-project -name harness-ios -bundleId com.example.harness
   ```
   Or use Xcode → File → New → Project → App (SwiftUI / Swift).
3. Using `com.example.harness` as the **App Bundle ID** aligns naming with Maestro / Android.
4. Build:
   ```
   xcodebuild -scheme harness-ios -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```
5. Run Maestro (the yaml files in the harness `tests/e2e/mobile/` can be reused directly):
   ```
   xcrun simctl boot "iPhone 16"
   maestro --device booted test tests/e2e/mobile
   ```

## What Is Automated (CI)

- Build & unit tests: `xcodebuild test` on a macOS runner
- Maestro E2E: covered by the maestro job in `_reusable-e2e.yml`
- MobSF static analysis: `.ipa` scanned by the mobsf job in `_reusable-security.yml`
- TestFlight distribution: via fastlane pilot from the testflight-stage job in `scheduled-db-backup.yml`
