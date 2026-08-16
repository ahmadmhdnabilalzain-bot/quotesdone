# Phase C correction 8 — the components that were "unclassified" and counted as clean

**Migrations:** `phase_c_35_component_classification.sql`, `phase_c_38_repair_historical_evidence.sql`
**Generator:** the evidence sweep in `scripts/phase_c/` tooling (cron, pg_proc, pg_trigger, repo trees)

## The invariant was measuring a different subject

`unclassified_components` reported **0**. Its test was `classification = ''` — the empty string,
which no row has ever held — while **286** rows carried the literal `NO_CALLER_UNCLASSIFIED` and
**99** of those were state-changing and not inactive: exactly the population gate 4 names.

Corrected to `classification in ('', 'NO_CALLER_UNCLASSIFIED')` restricted to
`mutates_state and activation_state not in ('inactive','disabled')`. `unclassified_edge_functions`
had the same shape and was corrected the same way — which immediately found 32 more.

## Every classification is derived from evidence

| Evidence source | Used for |
|---|---|
| `pg_trigger` | `ACTIVE_DATABASE_TRIGGER` |
| `cron.job`, distinguishing **active** from **deactivated** | `ACTIVE_CRON` vs `INTENTIONALLY_INACTIVE` |
| `pg_proc.prosrc` across every deployed routine | `ACTIVE_INTERNAL_CALLER` |
| `supabase/functions/**` — `functions/v1/<slug>` and rpc names | `ACTIVE_INTERNAL_CALLER` |
| `src/**` | `ACTIVE_FRONTEND_ENTRY` |
| webhook/inbound/callback naming with no internal caller by design | `ACTIVE_WEBHOOK_ENTRY` |
| none of the above | `DEFERRED_RUNTIME_IMPLEMENTATION` |

For each component the register records: component type, active status, caller or external entry
point, workflow or justified technical scope, accountable canonical role, system actor, authority
class, trace policy and final classification.

## Result

**286 components reviewed** — the 99 active state-changing ones gate 4 names, and the 187 the
corrected `unclassified_edge_functions` check then surfaced.

| Classification | Count |
|---|---|
| `ACTIVE_INTERNAL_CALLER` | **62** |
| `ACTIVE_FRONTEND_ENTRY` | **3** |
| `DEFERRED_RUNTIME_IMPLEMENTATION` | **221** |

The 221 have no caller and no entry point anywhere — not a trigger, not an active cron job, not
another deployed routine, not an edge function, not `src/`. **An active state-changing component
with no caller evidence may not remain active**, so their `activation_state` is now `inactive` and
their `repair_or_keep_action` reads *"Phase D: give it a caller and an entry point, or retire it. It
is deployed and unreachable."*

This changes the **registry's claim** about them, not their deployment. The functions remain
deployed and callable; what stops is the estate asserting they are live and accounted for.

## Required results

| Measure | Result |
|---|---|
| active `NO_CALLER_UNCLASSIFIED` | **0** |
| active components without an accountable role | **0** |
| active components without a system actor | **0** |
| active components without workflow / justified scope | **0** |
| active components without an authority class | **0** (new invariant) |
| active components without a trace policy | **0** (new invariant) |

Active component classes now: `CANONICAL_KEEP` 782, `WIRE_TO_CANONICAL` 705,
`ACTIVE_INTERNAL_CALLER` 62, `CANONICAL_BETTER_KEEP` 7, `ACTIVE_FRONTEND_ENTRY` 3.
