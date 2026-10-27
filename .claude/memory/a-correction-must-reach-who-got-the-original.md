---
name: a-correction-must-reach-who-got-the-original
description: A revise path that bumps a version but leaves the delivery lanes closed silently reaches nobody
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T04:24:46.020Z
---

9 Sep 2026, `fn_accountant_weekly_report`. `p_revise` bumped `revision`, rewrote the figures and
discarded the stale PDF — but left `founder_submitted_at` and `ceo_submitted_at` set.
`fn_accountant_weekly_report_deliver` opens each lane with `if v_row.<x>_submitted_at is null`.

So from the moment the first report was delivered, **every correction of that week was
undeliverable**: it would regenerate, re-render a fresh PDF, return `ok`, mark itself `delivered`,
and reach nobody. The failure is silent and biased in the flattering direction — the row says
delivered while the recipient holds only the version that was wrong.

**The general shape:** whenever a record can be superseded, check that the succession path clears
whatever the delivery/consumption path uses as its "already done" flag. A version counter that
advances while the gate stays shut is a replacement nobody can reach — the same trap as
[[a-succession-record-unreachable-behind-the-row-it-replaces]].

**How to test it:** positive control first — prove the ORIGINAL delivers, then revise and assert
the lanes re-opened. Asserting only that the revision number advanced would have passed on the
broken code. Run it in a plpgsql `begin/exception` subtransaction with a sentinel exception so the
probe rolls back but a real assertion failure still propagates and fails the apply.

Related: [[guarded-by-a-condition-that-cannot-occur]], [[a-status-column-is-not-a-delivery-record]],
[[the-estate-could-not-email-a-file]].
