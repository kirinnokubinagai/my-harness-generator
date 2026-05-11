# On-call Handbook

## Rotation

| Week | Primary | Secondary |
|---|---|---|
| `<week>` | `<name>` | `<name>` |

Rotation managed in PagerDuty / Opsgenie. Handoff every Monday 10:00 JST in
`#oncall`.

## What you commit to as primary

- Acknowledge SEV1 within 15 min, SEV2 within 30 min, 24/7
- Carry a charged phone with paging app foreground
- No new feature work — focus on incidents + tickets in the on-call queue
- File a daily summary at end of day in `#oncall-log`

## Common alerts

| Alert | Likely cause | First action |
|---|---|---|
| `error_rate > 1 %` 5 min | Recent deploy | Check `wrangler deployments list` → consider rollback |
| `p95_latency > 500 ms` 10 min | DB slow query / KV cold | Check D1 + KV dashboards |
| `worker_cpu_time > 50 ms` p95 | Hot loop or large response | Profile via `wrangler tail` |
| `auth_failures > 100/min` | Brute force | Check rate-limit metrics; consider IP block |
| `d1_query_time > 1s` p95 | Missing index / table scan | Run `EXPLAIN` on slow query |

## Dashboards (bookmark these)

- Service health: `<grafana-or-cloudflare-link>`
- Error tracking: `<sentry-link>`
- Logs: `<datadog-or-axiom-link>`
- Cloudflare Analytics: `https://dash.cloudflare.com/.../analytics`
- D1 query insights: `https://dash.cloudflare.com/.../d1`

## Tooling

```bash
# Live tail
nix develop --command pnpm exec wrangler tail --env production --format pretty

# Recent deployments
nix develop --command pnpm exec wrangler deployments list --env production

# Roll back (see runbooks/rollback.md)
nix develop --command pnpm exec wrangler rollback <id> --env production
```

## Escalation

- 30 min stuck → page secondary
- 1 h stuck → page engineering manager
- Customer-impact > 1 h → notify CEO + comms

## At handoff

- [ ] Ack queue empty
- [ ] All open incidents have an owner
- [ ] Daily summary posted in `#oncall-log`
- [ ] Tomorrow's primary aware of any known instability
