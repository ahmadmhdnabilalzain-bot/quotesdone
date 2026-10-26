# Autonomy governance

## Modes

### Observe Mode — default
- Read dashboards, traces, reports, simulations and recommendations.
- Issue high-level objectives.
- No direct record mutation.

### Control Mode — exceptional
- Requires recent MFA.
- Time-limited.
- Every action is previewed with impact and policy.
- High-risk actions require an explicit second confirmation.

## Autonomy tiers

| Tier | Meaning | Examples |
|---|---|---|
| A0 | Observe only | dashboards, search, reports |
| A1 | Recommend | strategy, risk, optimization |
| A2 | Prepare | draft email, quote guidance, legal draft |
| A3 | Execute reversible low-risk | reminders, retries, metadata refresh |
| A4 | Execute supervised | bounded campaigns, clean supplier approval, safe publishing |
| A5 | Founder-gated | money movement, fee/policy change, production deploy, data deletion, mass bans, legal commitments |

Authority must be enforced in code/database, not merely in prompts.
