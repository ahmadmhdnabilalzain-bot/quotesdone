# Postmortem: `duty:unsigned_revision` + `duty:unsigned_change` — routines applied outside the reviewed path

Seat: it_engineer. Blameless. Written 28 Sep 2026 from production reads (read-only) and `git log`.

| | |
|---|---|
| Class | `duty:unsigned_revision:rev:<sha>` (13) and `duty:unsigned_change:tx<id>` (2) — one root cause |
| Handoffs covered | **15**, all **critical** |
| First / last | 14 Sep 2026 21:58Z / 23 Sep 2026 18:46Z |
| Answering seat | ceo |

## Impact
Security (the finding's blast). Production routines ran code from a revision that was not on `main` and in no
merged or open pull request (13), or were changed by `mgmt-api as postgres` with no revision at all (2, 18 Sep 07:31Z).
No evidence of an unauthorised actor was found: every sha named is a session's own branch commit.

## Root cause
The estate's own order is **apply, then merge**. A session applies SQL from its branch, then rebases or squashes, so the
applied sha disappears from GitHub (compare 404 / pulls 422 → verdict `not_on_main`). Measured for `rev:14ad86a` on
22 Sep: applied 17:40:13Z from PR #783's branch, which later no longer contained it; PR merged 17:47:21Z; every routine's
deployed sha256 equals its canonical file. The two `unsigned_change` rows were direct management-API applies.

## Detection
`it_engineer.unsigned_revision` / `unsigned_change` duties (`a_routine_change_nobody_signed_is_a_finding_within_minutes.sql`).
Worked; its flaw was that a signed-but-rebased revision could never settle and re-opened every tick.

## Fix (found in git)
- `0b0482b`: the duty itself.
- `c4e73c8` (#824): `a_revision_off_main_is_settled_once_its_routines_are_reapplied_or_accepted.sql`.
- `3b30e6a` (#838): `an_apply_from_an_open_pull_request_waits_for_its_merge.sql`.
- Close note on the two changes: "every routine it touched has since been re-applied from a reviewed revision".

## Action items
1. **it_engineer** — applies should come from the commit that will be merged (no rebase after apply); the coordinator's
   serialised "apply, merge, then next" already covers this.

## Handoff ids covered
`duty:unsigned_revision` (13): 24190, 25407, 27628, 39937, 46474, 49247, 53257, 79002, 80604, 81401, 83462, 85227, 85423.
`duty:unsigned_change` (2): 38450, 38451.
