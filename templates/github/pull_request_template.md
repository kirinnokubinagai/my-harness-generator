<!-- This template is loaded automatically. PRs targeting branches other than dev are prohibited except for emergency hotfixes. -->

## Related Issue

closes #<child issue>
parent: #<parent issue>

## Summary of Changes

<!-- 1–3 sentences: why this is needed and what changes. -->

## Changes (Checklist)

- [ ] Feature implementation
- [ ] Tests added / updated
- [ ] Documentation updated
- [ ] Migration (if applicable)

## Impact Scope

- Affected files:
- Affected features:
- Backward compatibility: yes / no (reason)

## E2E Impact

- [ ] Yes → Playwright / Maestro run completed
- [ ] No

## Lane

- lane: N
- analyst: @analyst-N
- engineer: @engineer-N
- e2e-reviewer: @e2e-reviewer-N
- reviewer: @reviewer-N

## Convention Compliance

- [ ] biome format / lint passed
- [ ] vitest passed
- [ ] tsc --noEmit passed
- [ ] gitleaks passed
- [ ] JSDoc / TSDoc complete
- [ ] Hono Clean Architecture 4-layer separation
- [ ] Verified to work under Nix flake only
- [ ] No AI-style design elements; Lucide Icons only

## Review Request

target: dev (harness standard)
