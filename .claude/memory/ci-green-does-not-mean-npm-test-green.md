---
name: ci-green-does-not-mean-npm-test-green
description: "The CI checks job carries no Supabase credential, so every production-reading check skips there — locally they run and ~61 are red"
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T22:57:16.260Z
---

**26 Oct 2026:** GitHub Actions is off ([[ci-runs-locally-ubicloud-stopped]]). The local run, with
the token present, is now the only check run, which is the stronger of the two anyway.

`.github/workflows/checks.yml`'s **`checks` job has no secrets at all**. Every check that reads
production prints `NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL` and skips. Only two jobs carry the
token: "the database is running what this repository says" and "the kernel and handler gate,
against production" — those are the ones whose green actually means something about production.

On this machine the token is present, so `npm test` runs several hundred database checks that CI
never runs. **Measured 8 Sep 2026: 61 failing assertions on a green-in-CI tree.**

**CLEARED 9 Sep 2026 — the local suite is now 97 tests, 97 pass, 0 fail.** Every one of those reds
was a check that outlived its subject in the 7 Sep deletion wave. They were resolved one at a time
on the measurement, not in bulk: most RETIRED with their subject, several REPAIRED where the
property survived the routine that used to express it, and one turned out to be reporting a real
live defect — see [[an-fk-to-an-emptied-table-fails-every-writer]]. A local red is still not
automatically your fault, but the baseline is now ZERO, so a new red means something. Every missing
routine they name was absent from production BEFORE that day's work — `fn_phase_b_invariants`,
`fn_phase_c_reporting_map_drift`, `fn_agent_binding_rule`, `fn_certification_exam_summary`,
`fn_autonomy_class`, `fn_phase_d_fixture_catalogue_state`, `fn_terms_integrity`.

Practical consequences:

- **Never read a local red as "I just broke this".** Attribute it: compare each missing routine
  against a pre-change inventory of `pg_proc`. Taking the lump number at face value nearly caused a
  wrong rollback.
- **Never read CI green as "the suite passes".** It means the skipping ones skipped.
- The 61 are a real backlog: checks whose subjects were removed in earlier sessions without the
  checks being retired alongside. Retiring them (`.RETIRED.mjs`, never softened) is honest work
  when there is time for it — see [[checks-retired-with-their-subject]].

Also: `npm test 2>&1 | tail -40` reports the exit code of `tail`, not of `npm`. Redirect to a file
and echo `$?`, or a failing suite reads as a passing one.
