---
name: Child issue (task)
about: A single task split from a parent issue (≤ 300 lines of change)
title: "[task] "
labels: child
---

parent: #<parent issue>
lane: <1–4>

## Summary

<!-- 1–2 sentences -->

## Background

## Files to Change (declared in advance to prevent conflicts)

- `src/...`
- `tests/...`

## Acceptance Criteria

- [ ]
- [ ]

## Impact / Side Effects

## E2E Impact

- [ ] Verification with Playwright required
- [ ] Verification with Maestro required
- [ ] Not required

## Convention Self-Check

- [ ] Lines changed ≤ 300
- [ ] Owned files do not overlap with other child issues
