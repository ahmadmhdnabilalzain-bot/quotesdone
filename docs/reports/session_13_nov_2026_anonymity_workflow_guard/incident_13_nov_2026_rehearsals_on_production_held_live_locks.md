# Incident, 13 Nov 2026: rehearsals on production held the locks of a real change

Seat: it_engineer. Written by the session that caused it. Every figure below was read from the production
Postgres log, `pg_stat_activity` snapshots or the tables named; none is estimated.

## What happened

Between 05:30 and 09:29 UTC on 13 Nov 2026 the session and the agents it had launched rehearsed pending SQL
files against the live database (`scripts/ci/rehearse_sql.mjs`, and `safe_replay` inside checks). A rehearsal
sends the whole file plus its probe inside one transaction and rolls it back. Rolled back or not, the
transaction takes the locks the real change takes, and holds them until it ends:

- a file with `ALTER TABLE`, `CREATE TRIGGER` or a policy change takes ACCESS EXCLUSIVE on the table;
- the probes behind those files ran for 12 to 15 seconds;
- one agent re-ran its file about every 20 seconds while it worked.

During that window the log holds 218 "still waiting for lock" lines, 217 of them behind management-API
sessions (ours). 103 live PostgREST requests and 11 pg_cron jobs queued behind 28 lock holders. The API role
`authenticator` has a statement timeout of 8 seconds, so queued requests were cancelled.

## Who was affected

Every affected identity was a ZZ DEMO identity of a test running at the same time. No real customer or
supplier made a request in the window (0 real people).

| effect | what the person saw | what the database held | repaired |
|---|---|---|---|
| a supplier's agreement certificate write was cancelled | "Signing your Supplier Agreement…" stayed on screen | acceptance recorded, no certificate | yes, 5 minutes later, by the sweep `fn_sales_engineer_resigns_unsigned_agreements` |
| a `spec_fill` approval was cancelled | a generic error (HTTP 500) | nothing written | no; the press had to be repeated |
| a customer's acceptance of the terms was lost | the page let him in as if it had been saved | nothing written | no; `kyc accept_terms` discarded the write error |

The third row is the serious one. It is a product defect that the incident exposed, not one the incident
created: a failed write that the page reports as a success.

## Cause

1. The process: "rehearse on production, it is rolled back" was written into the release runbook and the
   agents' briefs as safe. It is safe for data and unsafe for locks.
2. The tool: the rehearsal set no `lock_timeout` and no ceiling on the transaction's length, and production
   was its default target.
3. The product: three write paths answered the person before knowing the write had landed.

## What was done the same day

- 08:55 UTC: every rehearsal against production stopped; all agents moved to a local Postgres 16 built from
  the schema mirror (`scripts/db/local_from_mirror.mjs`).
- Standing rule for sessions: nothing is rehearsed or executed against production. The one real apply is done
  by the releasing session, in a quiet minute, with a short `lock_timeout`, after reading `pg_stat_activity`.
- Branch `it_engineer-a-suppliers-certificate-is-written-in-time-and-never-silently-lost`: the replay tool is
  local by default; a production replay must be asked for, is refused if the file takes a lock stronger than
  ROW EXCLUSIVE on an existing relation, and is cut at 5 seconds; `apply_sql.mjs` sets a lock timeout; no retry
  after a 5xx; `kyc`, `compliance_archive` and `supplier_api` report a failed write to the person and to a
  seat; a pending SQL file guarantees that a recorded acceptance always gets its certificate.
- Memory: `.claude/memory/a-rehearsal-on-production-holds-the-locks-of-a-real-change.md`.

## What an auditor should check

- `scripts/lib/replay_guard.mjs` and its tests: the refusal list and the 5-second cut.
- `docs/runbooks/release-without-ci.md`: no step tells a session to rehearse on production.
- The three write paths above: each has a test in which the write fails and the person is told.
