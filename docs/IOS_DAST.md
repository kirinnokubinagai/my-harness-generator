# iOS DAST

## Conclusion

**OWASP ZAP is web-only** and cannot be used for iOS apps.
As of 2026, the only practical OSS solution for automating iOS DAST/SAST is **MobSF (Mobile Security Framework)**.

| Tool | iOS support | DAST | SAST | Cost | Automation |
|------|------------|------|------|------|-----------|
| **MobSF** | ✅ | △ (static only) | ✅ | OSS (free) | Docker + REST API |
| NowSecure | ✅ | ✅ | ✅ | Commercial (expensive) | GitHub Action available |
| Veracode | ✅ | ✅ | ✅ | Commercial (expensive) | Official Action |
| Mobile-Threat | ✅ | ✅ | ✅ | Commercial | API |

> Important: As of MobSF v3.9, **dynamic analysis (DAST) supports Android only**.
> For iOS, the focus is **static analysis + detection of secrets / weak cryptography / dangerous API calls inside the IPA**.
> Even so, there is clear value in integrating it into CI (covers most of OWASP MASVS L1).

## CI Integration (automated via `.github/workflows/_reusable-security.yml`)

```yaml
services:
  mobsf:
    image: opensecurity/mobile-security-framework-mobsf:latest
    ports: ['8000:8000']
    env:
      MOBSF_API_KEY: ${{ secrets.MOBSF_API_KEY }}
```

The `mobsf` job starts using the `MOBSF_API_KEY` secret → uploads the IPA → runs the scan → retrieves a JSON report → fails if even one high-severity finding exists.
On failure, a GitHub issue is automatically created and the fix is routed back to the relevant lane.

## When Dynamic Analysis Is Required

- **Real iOS DAST requires commercial tools** (NowSecure, Veracode, Mobile-Threat).
- If budget allows, adding the **NowSecure GitHub Action** (`nowsecure/nowsecure-action`) to `_reusable-security.yml` is the simplest approach.
- Without budget, perform manual penetration testing quarterly.

## Manual Supplementation

- **Runtime analysis with Frida + Objection** monthly (manual).
- **App Store Review Guideline** + **iOS Privacy Manifest** checks via Xcode's `xcodebuild -enableThreadSanitizer`.
- It is recommended to add **Apple Privacy Manifests** (`PrivacyInfo.xcprivacy`) existence checks to CI.

## Summary

For iOS, instead of ZAP:
1. **Make MobSF mandatory in CI** (OSS, automated) → covers ~95% of static vulnerabilities + misconfigurations
2. **Introduce NowSecure / Veracode if possible to also cover DAST** (budget permitting)
3. **Add Apple Privacy Manifest validation to CI**
4. **Manual review with Frida + Objection** monthly

These are automated via the `mobsf` job in `_reusable-security.yml`. When introducing commercial tools, simply add a job.
