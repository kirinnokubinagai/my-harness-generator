# Incident Response

## Severity matrix

| Severity | Definition | Response time | Pages |
|---|---|---|---|
| SEV1 | Total outage / data loss / security breach | 15 min | All on-call + leadership |
| SEV2 | Partial outage / major degradation | 30 min | Primary on-call |
| SEV3 | Minor degradation / non-critical bug | 2 h business | Issue queue |
| SEV4 | Cosmetic / planned maintenance | Next business day | None |

## First 15 minutes

1. **Acknowledge** the page in PagerDuty / Opsgenie.
2. **Open** the incident channel `#incident-<short-id>` in Slack.
3. **Status page**: post initial "investigating" within 5 minutes.
4. **Identify** the affected service from dashboards (`runbooks/oncall.md`).
5. **Stop the bleed**: rollback (`runbooks/rollback.md`) > feature flag > scale > restart, in that order of preference.

## Roles during an incident

- **Incident Commander (IC)** — drives the response, the only person making decisions
- **Comms Lead** — owns status page + customer communication
- **Tech Lead** — owns the actual fix
- **Scribe** — captures the timeline in the channel

For SEV1/SEV2, the IC is **not** the same person as the Tech Lead.

## Communication cadence

- SEV1: status page every 15 min until resolved.
- SEV2: status page every 30 min.
- Internal updates in `#incident-*` every 10 min.

## Resolution

1. Confirm metrics / synthetic checks are green for 30 min.
2. Update status page to "resolved".
3. Schedule the postmortem within 24 h (use `runbooks/postmortem.md`).
4. Open follow-up issues with `incident-<id>` label.

## Escalation

- 30 min without progress → page secondary on-call
- 1 h without progress → page engineering manager
- 2 h without progress → page CTO

## Do NOT

- Speculate publicly about cause before evidence.
- Push a fix to production without rollback plan.
- Close the incident before 30 min of clean metrics.
- Start the postmortem with "who broke it".
