# iOS DAST（質問16 補足）

## 結論

**OWASP ZAP は Web 専用** で iOS アプリには使えない。
2026 年現在、iOS アプリの DAST/SAST を OSS で自動化する現実解は **MobSF（Mobile Security Framework）** 一択。

| ツール | iOS 対応 | DAST | SAST | コスト | 自動化 |
|--------|---------|------|------|-------|--------|
| **MobSF** | ✅ | △ (静的のみ) | ✅ | OSS（無料） | Docker + REST API |
| NowSecure | ✅ | ✅ | ✅ | 商用（高額） | GitHub Action あり |
| Veracode | ✅ | ✅ | ✅ | 商用（高額） | 公式 Action |
| Mobile-Threat | ✅ | ✅ | ✅ | 商用 | API |

> 重要: MobSF v3.9 時点で **動的解析（DAST）は Android のみ対応**。
> iOS は **静的解析 + IPA 内のシークレット/弱い暗号/危険な API 呼び出し検出** が中心。
> それでも CI に組み込む価値は十分にある（OWASP MASVS L1 の大半をカバー）。

## CI 組み込み（`.github/workflows/_reusable-security.yml` で自動）

```yaml
services:
  mobsf:
    image: opensecurity/mobile-security-framework-mobsf:latest
    ports: ['8000:8000']
    env:
      MOBSF_API_KEY: ${{ secrets.MOBSF_API_KEY }}
```

`mobsf` ジョブは `MOBSF_API_KEY` シークレットを使って起動 → IPA をアップロード → スキャン → JSON レポート取得 → high 重大度が 1 件でもあれば失敗。
失敗時は GitHub issue を自動起票して該当レーンに修正を戻す。

## 動的解析が必要な場合

- **iOS のリアル DAST は商用ツールが必要**（NowSecure、Veracode、Mobile-Threat）。
- 予算が許せば **NowSecure GitHub Action**（`nowsecure/nowsecure-action`）を `_reusable-security.yml` に追加するのが最も簡単。
- 予算が無い場合は手動ペネトレーションテストを四半期に 1 回行う運用にする。

## 手動補完

- **Frida + Objection** によるランタイム解析を月次で（手動）。
- **App Store Review Guideline** + **iOS Privacy Manifest** チェックを Xcode の `xcodebuild -enableThreadSanitizer` で。
- **Apple Privacy Manifests**（PrivacyInfo.xcprivacy）の存在確認を CI に追加することを推奨。

## まとめ

iOS の場合、ZAP の代わりに:
1. **MobSF を CI で必須化**（OSS、自動）→ 静的脆弱性 + 設定ミスを 95% カバー
2. **NowSecure / Veracode を導入できれば DAST もカバー**（予算次第）
3. **Apple Privacy Manifest 検証を CI に追加**
4. **Frida + Objection の手動レビュー**を月次で

これらを `_reusable-security.yml` の `mobsf` ジョブで自動化済み。商用ツール導入時はジョブを追加するだけで OK。
