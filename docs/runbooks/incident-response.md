# Incident response

Owner: it_engineer. Written 9 Nov 2026 from the launch-readiness audit (no incident runbook existed).
This page says how to run the first hour. The moves themselves are not repeated here:
undoing a release is [../it/ROLLBACK.md](../it/ROLLBACK.md), losing data is
[restore-and-disaster-recovery.md](restore-and-disaster-recovery.md), keys are [keys.md](keys.md).

## Who decides what

The founder's rules decide, not the severity. Work the incident to the end without asking. Escalate to the
founder only for:

1. **Money**: a refund, a charge, a payout, anything that moves or could move dirhams.
2. **A destructive production change**: dropping or truncating data, disabling a key, deleting a function.
3. **A fact only he holds**: a login, a legal position, a contract term.

Everything else (rolling back a deploy, redeploying a function, re-applying a prior SQL file, pausing a
cron) is done and reported afterwards. Every production write still goes through the release guard.

## Severity

| Level | Meaning | Examples | Target |
|---|---|---|---|
| SEV1 | Customers cannot use the product, or money/data is at risk | site down, sign-in fails for everyone, Stripe webhook failing, data loss | mitigate in 1 h |
| SEV2 | One path broken, a workaround exists | quote emails delayed, one portal page erroring, one provider down | same day |
| SEV3 | Degraded, no customer-visible harm | a duty failing, noisy warning, slow job | next working day |

## First 15 minutes

1. **Confirm and size it.** `curl -s -i https://quotesdone.com/api/health` (public liveness; 200 means the web
   process is up and says nothing about the database). `/api/resilience-ping` is the authenticated deep check
   and is called by the Vercel cron every 15 minutes; do not point a public monitor at it.
2. **Did something just ship?** Vercel deployments and the last merges to `main`. If the timing matches, roll
   back first and diagnose second: [../it/ROLLBACK.md](../it/ROLLBACK.md) section 1 takes under a minute.
3. **Read the logs** (below), find the first error, not the loudest.
4. **Mitigate**, then write down what you did and when.

## Where to look

| What | Where |
|---|---|
| Website runtime errors and logs | Vercel project, Logs (or the Vercel MCP `get_runtime_errors`, then `get_runtime_logs`) |
| Build and deploy failures | Vercel project, Deployments |
| Edge function errors | Supabase dashboard, Edge Functions, Logs (or the Supabase MCP `query_logs`) |
| Postgres errors, slow queries | Supabase dashboard, Logs, Postgres; advisors for security and performance |
| Errors the site reported itself | `public.site_error_events` (written by the `site_error_ingest` function from `src/instrumentation.ts`) |
| What the IT seat already noticed | the IT tick findings: `it_engineer` duty findings and `public.it_finding_closure`; a duty that failed 3 times in a row is itself a finding |
| Scheduler health | `resilience_ping` result in the Vercel cron log; a total pg_cron outage is only visible from outside Supabase |
| Which key a failure points at | [keys.md](keys.md) |

## Mitigation moves

| Surface | Move |
|---|---|
| Website | Vercel Instant Rollback, then Promote after the fix ([../it/ROLLBACK.md](../it/ROLLBACK.md) 1) |
| Edge function | redeploy from `main` ([../it/ROLLBACK.md](../it/ROLLBACK.md) 2) |
| Database routine | revert PR, re-apply the prior canonical file ([../it/ROLLBACK.md](../it/ROLLBACK.md) 3) |
| Lost or corrupted data | [restore-and-disaster-recovery.md](restore-and-disaster-recovery.md) |
| No CI available | [release-without-ci.md](release-without-ci.md) |

## Closing

Record: what broke, when it started and ended, how it was found, the fix, and the check that now prevents it
(a `scripts/checks` test, named in the commit). Put the write-up in `docs/it/postmortems/` for SEV1 and SEV2.
Add what a future session needs to `.claude/memory/`, by PR.

## Known gaps (tracked in [../engineering/tech-debt.md](../engineering/tech-debt.md))

No external uptime monitor watches `/api/health` yet, and there is no circuit breaker for the email, Stripe or
WhatsApp providers, so a provider outage shows up as failures in the logs rather than as a tripped breaker.
