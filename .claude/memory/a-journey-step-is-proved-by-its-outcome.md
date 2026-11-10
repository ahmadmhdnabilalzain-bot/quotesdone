---
name: a-journey-step-is-proved-by-its-outcome
description: "A journey test that asserts a step STORED something can pass while the step fails on every real input — 38 of 38 portal licence reads failed while the registration walk was green"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-28T08:05:00.000Z
---

28 Oct 2026 (founder ledger 1401; fixes #1707, #1708, #1709).

Overnight I reported the supplier registration verified through a browser: 112/112 walk checks with the
real sign-up code, the reply probe 6/6, a fresh supplier 28/28. The founder then asked about documents —
"i meant when suppliers upload company profile / trade license and other documents on the portal" — and,
when I had treated them as outside the test, "but thats part of the journey. why you ignored it?"

Measured once the document step was walked with real files:

```
license_extract on portal uploads       38 of 38 failed   — the portal sends each page as {mime, data};
                                                            the reader took only the older shape (#1707;
                                                            quote_extract had the same fault)
insurance "period of cover" expiry      read as the START date, so valid cover showed expired (#1708)
phone-photo licence, Documents tab      HTTP 200 after 18,019 ms; the portal aborts at 20 s; the model alone
                                        p50 7.9 s, p90 15.9 s, max 49.7 s over 30 days — a slower read told
                                        the supplier "could not save" for a file on record (#1709)
```

**Why the walk missed it:** `scripts/e2e/supplier_registration_walk.mjs` DID upload a licence, but it
asserted only that the file was STORED (`leads.license_doc_path` set), not that it was READ. A licence
that is stored and never read passes a storage check every time. The fixture was also a clean generated
PDF; a supplier's phone photo is the slow case. And I had parked license_extract's failures as known
noise instead of asking what fed it — the portal path was first exercised on 27 Oct, so "broken since
19 Oct", which I first said, was wrong too.

**How to apply:** each step of a journey test must
1. receive the exact payload the real client sends (capture it from the portal's own request, not a
   hand-built fixture), including the optional steps a real supplier takes — documents, photos, profile;
2. assert the step's OUTCOME — the licence fields read, the expiry right, the row approved or held with a
   reason — never only the HTTP status or that a path was stored;
3. run on a phone photo as well as a clean PDF, at 390 px and desktop;
4. be timed against the client's own timeout, using the model's measured p90/max, not one fast run.

Same shape as [[a-status-column-is-not-a-delivery-record]] (an intention measured instead of the effect)
and [[a-fixs-own-check-measures-the-case-the-fix-handles]].
