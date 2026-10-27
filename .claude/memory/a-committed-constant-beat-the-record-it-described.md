---
name: a-committed-constant-beat-the-record-it-described
description: Five times in one session a context key that names a record was answered from a committed fixture instead; ask what the key is ABOUT before accepting any answer for it.
metadata:
  type: project
---

23 Aug 2026, five separate instances inside one Phase D session, all the same sentence:

- `terms_version` / `terms_hash` fell past every resolver branch to the fixture door, so BR-025 was
  handed catalogue constants while the scenario had just written the REAL published pair
  (`legal_documents` customer-terms v3) onto the acceptance record.
- `monetary_state` was committed as `reconciled`, a word from the generic object-record family that
  names no rung of `phase_d_payment_state`; BR-020 would have refused it outright.
- `artifact_sha256` was contributed as the row id of the record that carried it (F41).
- Seven object keys — inquiry_id, supplier_id, quote_id, transaction_id, document_id,
  comparison_id, refund_id — were all answered from the run's OWN row id, so BR-015 was told a
  quote was a supplier and BR-020 that a comparison was a transaction.
- `kind` had one committed fixture, written for `opportunity.kind`, and it was being handed to
  `documents.kind`.

**Why:** a fixture catalogue keyed on a field NAME is unique only until two things share the name,
and a resolver that answers a key without asking what the key is about will always prefer the
answer it can produce over the one that is true.

**How to apply:** for every key a rule reads, ask "does this name a RECORD?" If yes it is answered
from `phase_d_context_key_object` → that object's canonical reference, and the committed catalogue
is the LAST resort, never the first. See [[a-generated-fixture-beat-the-real-reference]] and
[[instruments-report-on-the-wrong-subject]].
