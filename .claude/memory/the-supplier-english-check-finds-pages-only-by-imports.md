---
name: the-supplier-english-check-finds-pages-only-by-imports
description: "10 Nov 2026: scripts/checks/nothing_a_supplier_reads_can_be_arabic.test.mjs finds supplier files only by following relative imports from its ENTRIES, so a standalone supplier page (supplier_ack) was invisible and printed Arabic for two months. Name every standalone supplier page in ENTRIES; _shared/ is never walked."
metadata:
  type: feedback
  modified: 2026-11-10
---

The founder's rule is that suppliers are always written to in English (ruling 1008, 28 Sep 2026; [[suppliers-always-english]]).
The check that enforces it, `scripts/checks/nothing_a_supplier_reads_can_be_arabic.test.mjs`, does not list files: it starts
from `ENTRIES` (the supplier portal page and the `supplier_portal`, `supplier_api`, `supplier_catalog_ingest` functions) and
follows relative imports. **A page nothing imports is never read.** `supplier_ack` (the "I have contacted the customer" page a
supplier opens from his reveal reminder) is a function of its own that nobody imports, so it printed every answer in English
AND Arabic from 14 Sep until #1901 named it in `ENTRIES` on 10 Nov 2026 (the check then failed 1 of 133 on main's file).

**Why:** a derived file list is better than a hand list until a surface has no import edge into it: an edge function the
supplier reaches by URL (a link in an e-mail, a WhatsApp button, a Stripe return page) is its own entry point.

**How to apply:**
- When you add or find a supplier-facing page or function that is reached by URL rather than by import, add its entry file to
  `ENTRIES` in that check, with a comment saying how the supplier reaches it. Candidates to look at: `supplier_pay`,
  `supplier_onboard`, `claim_lookup`, `unsubscribe` (10 Nov 2026: none of them is in `ENTRIES`).
- `_shared/`, `src/lib/` and `src/components/{ui,me}/` are deliberately not walked (customers share them and keep their
  inquiry language), so a supplier sentence written in `_shared/` is not checked either: keep it English by construction and
  test it where it is written (`_shared/licence_read_state.test.ts` asserts its supplier note has no Arabic letters).
- Changing a line that is on the check's gated list (`nothing_a_supplier_reads_can_be_arabic.gated.json`, sha1 of the trimmed
  line) fails the check even when you did not touch its Arabic. Leave such a line byte-identical and add a wrapper next to it.
