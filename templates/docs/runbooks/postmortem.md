# Postmortem: `<incident-id>` — `<short-title>`

## Header

- **Date / time**: `<UTC>`
- **Duration**: `<hh:mm>` (start → resolved)
- **Severity**: SEV1 / SEV2 / SEV3
- **Author**: `<name>`
- **IC**: `<name>`
- **Affected services**: `<list>`
- **Customer impact**: `<users affected, requests dropped, revenue lost>`

## Summary

One paragraph that a non-engineer can understand. What happened, what
customers saw, what we did about it.

## Timeline (UTC)

| Time | Event |
|---|---|
| `HH:MM` | Deploy of vX.Y.Z merged to main |
| `HH:MM` | First alert fired (`error_rate > 1 %`) |
| `HH:MM` | On-call acked |
| `HH:MM` | IC declared SEV1 |
| `HH:MM` | Rolled back to v(X.Y.Z-1) |
| `HH:MM` | Metrics recovered |
| `HH:MM` | Status page → resolved |

## Root cause

Five whys, no shortcuts.

```
1. Why did the API return 500s for 47 % of requests?
   → A null deref in `OrderHandler.confirm()` when the cart was empty.

2. Why was the cart empty?
   → The "abandoned cart cleanup" cron ran ahead of schedule.

3. Why did it run ahead of schedule?
   → The cron expression was `*/15` (every 15 min) but Cloudflare interprets
     this differently on its scheduler than locally.

4. Why didn't the test catch it?
   → Tests mocked the cron, never exercised the real Cloudflare timing.

5. Why was that mock acceptable?
   → No-one had thought about cron drift across edge environments.
```

## What went well

- Alert fired within 90 sec of the issue.
- IC + Tech Lead split worked — IC kept comms tight while Tech Lead diagnosed.
- Rollback was scripted (`runbooks/rollback.md`) so we hit it in 4 min.

## What went poorly

- Deploy went out at 17:30 JST — the on-call had already started winding down.
- No canary on this service (it was deemed "low risk").
- Status page update was 12 min late.

## Action items

| # | Item | Owner | Due | Issue |
|---|---|---|---|---|
| 1 | Add canary deploy to OrderService | `<name>` | `<date>` | `#1234` |
| 2 | Add cron-drift integration test | `<name>` | `<date>` | `#1235` |
| 3 | Move deploy window to before 16:00 JST | `<name>` | `<date>` | `#1236` |
| 4 | Status page update bot in `#incident-*` | `<name>` | `<date>` | `#1237` |

Action items track in the GitHub `incident-<id>` label.

## What we are not changing

- Keeping the cron (the schedule is correct now).
- Keeping the deploy frequency (problem was timing, not frequency).

## Blameless statement

This document focuses on systems and processes, not individuals. Anyone in
the same situation, with the same information, would have made the same
calls. The action items target the conditions that allowed the failure.
