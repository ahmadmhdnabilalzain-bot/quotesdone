# Journey test fixtures

Two synthetic documents used by `journey_test.mjs` to exercise the file-and-drawing upload path
against deployed staging. Both are generated, not scanned: nothing here is a real customer,
supplier, project or person.

| file | stands in for | used by |
|---|---|---|
| `drawing_windows.png` | a customer's architectural drawing (window/door schedule + elevation) | `customer_api/analyze_drawing` → `drawing_boq`, `drawing_redact` |
| `quotation_supplier.png` | a supplier's own quotation on their letterhead | `supplier_api/extract_quote` → `quote_extract` |

## Why they carry fake identifying detail

Both fixtures deliberately contain names, phone numbers, emails, websites, a TRN and reference
numbers. That is the point of the assertions:

- The drawing's **title block** (`AL NAHDA CONSULTANTS`, `MR OMAR BIN FAISAL`, `VILLA 42`, plot
  `345-8871`, `+971 4 555 1234`, `info@alnahda-consult.ae`, `AN-2026-114`) must never appear in the
  BOQ, because the BOQ is shown to **competing suppliers**. The journey asserts none of it leaks,
  and that `drawing_redact` blacked the block out and recorded a verified run.
- The quotation's **letterhead** (`EMIRATES ALUMINIUM WORKS LLC`, two phone numbers,
  `sales@emiratesalum.ae`, TRN `100234567800003`, salesperson `Rashid`) must be masked before the
  customer sees anything, because QuotesDone is a marketplace where the customer **pays to reveal
  the supplier**. An unanonymised upload hands the identity over for free.

None of these values resolve to a real UAE business; they exist so a leak fails a test loudly.

## Regenerating

Both were produced once on Windows with `System.Drawing`, so there is no image dependency in the
repo or in CI. They are committed because generating them needs a graphics stack the test itself
should not require. To change one, edit and re-run the generator recorded in the session notes, or
draw a replacement by hand — the only contract the test depends on is:

- `drawing_windows.png`: a legible window/door schedule with marks W1 (40 off, 1200x1500),
  W2 (8 off), D1 (2 off), D2 (3 off), a stated scale, and a title block full of identifying detail.
- `quotation_supplier.png`: a legible priced quotation totalling **AED 163,800**, at least four line
  items, plus validity, lead time, warranty, payment terms and exclusions, on an identifying
  letterhead.
