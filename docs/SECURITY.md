# Security Policy

## Defense by Layer

### 1. Secret Management

- Never commit a plain-text `.env` to Git (prevented by `.gitignore`).
- Development: inject local environment variables purely via **direnv + Nix flake**.
- Sharing: include only **SOPS + age**-encrypted files in the repository.
  - Keys are managed personally in 1Password / iCloud Keychain; CI uses an `AGE_KEY` secret.
- Production: **AWS Secrets Manager** or **GCP Secret Manager**. Applications retrieve secrets via IAM Role.

### 2. Authentication and Authorization

- Passwords: bcrypt cost ≥ 12 (see `~/.claude/rules/security.md`).
- Sessions: HttpOnly + Secure + SameSite=Strict Cookie; JWT is short-lived (15m) + refresh (7d).
- Authorization: resource owner check is mandatory; RBAC is centralized in Hono middleware.

### 3. Input Validation

- Validate all input with a Zod schema (reject with 422 + error message in `$LANG`).
- Use Drizzle ORM; when writing raw SQL, always parameterize with the `sql` template literal.

### 4. SAST / DAST / Dependencies

| Type | Tool | Timing |
|------|------|--------|
| SAST | Semgrep (OWASP / typescript ruleset) | PR → dev |
| Secrets scan | gitleaks | pre-commit + CI |
| Dependency | Trivy + Renovate | CI daily + PR |
| Container | Trivy image scan | after docker build |
| DAST | OWASP ZAP baseline + full | dev → stage merge |
| License | license-checker | before release |

### 5. Network / Infrastructure

- HTTPS enforced + HSTS preload.
- CSP starts from `default-src 'self'`; only add necessary origins.
- CORS: allowed origins are explicitly set in `.env`; `*` is prohibited.
- WAF: Cloudflare or AWS WAF (OWASP Core Rule Set).
- Rate limiting: login 5 attempts / 15 min; API overall 100 req / 15 min.

### 6. Observability

- Structured logging (pino) → CloudWatch / Datadog.
- Sensitive data masked (email in `te***@example.com` format).
- Metrics: alerts configured for p95 latency, error rate, and authentication failure count.
- Audit log: authentication, permission changes, and data deletion stored separately for 1 year.

## Why This Configuration

- **Nix pure + SOPS**: satisfies the "clean machine" requirement and enables safe secret sharing via Git.
- **Semgrep + Trivy + ZAP**: comprehensive SAST/DAST/SCA coverage using only OSS tools.
- **ZAP/E2E at stage**: detects side effects in a production-like environment; main is always kept green.
