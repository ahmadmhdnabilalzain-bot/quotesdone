---
name: a-default-inside-a-document-that-asserts-a-fact
description: "`value || new Date()` inside a routine that ISSUES evidence fabricates the very fact the document exists to attest — check every fallback on an artefact-producing path."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d59a0e58-a4df-44cd-a572-d0275ee07862
  modified: 2026-08-12T17:03:53.503Z
---

`compliance_archive` read `(rec.tos_accepted_at) || new Date().toISOString()`. When a party had not
accepted the Terms it stamped the certificate with the render time — and the certificate states
"Acceptance was given by ticking the 'I accept' box during registration" and asserts binding
acceptance under the UAE Electronic Transactions and Trust Services Law. Found 12 Aug 2026 because
repairing `email_verified` fired `trg_sign_customer`, which keys on email verification and NOT on
`tos_accepted_at`.

**Why:** a defensive default is harmless in a calculation and forgery in an artefact. The same
`|| fallback` idiom that stops a null crashing a report will, on a document-producing path, invent
the fact the document certifies — and it looks like ordinary defensive coding in review.

**How to apply:** on any routine that renders a certificate, invoice, report or receipt, treat every
`||`, `coalesce` and `?? ` on a fact the artefact ASSERTS as a defect. Refuse and log instead —
absence of the fact is the finding. Also check what the artefact's trigger keys on: here it fired on
a different column from the one the document is about. Related:
[[least-ignores-nulls-in-postgres]], [[instruments-report-on-the-wrong-subject]],
[[never-state-what-you-have-not-measured]].
