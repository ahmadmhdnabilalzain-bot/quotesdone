# Contract: `technical_comparison` v1 (and `standardised_quotation` v1)

Owner: the **sales_engineer** seat (data and workflow). Reader: the comparison-report PDF, drawn by
another branch's code. This file is the handshake. If the shape changes, the `version` changes and
this file changes in the same commit.

Founder, 14 Sep 2026: *"the comparison report need to be more detailed technically. its not a matter
of delivery time only or installation … we need to make sure that exact specs of the material used,
what type of wood, what thickness, etc."*

## Where it is served

`quote_compare` returns it on every successful answer, degraded (rules-only) or not, cached or not:

```
POST /functions/v1/quote_compare  { inquiry_id, lang }
→ { ok: true, analysis: { …existing fields…, technical: TechnicalComparison, on_hold: number } }
```

It is rebuilt on every call from the live rows (it is never part of the cached model output), so it
always reflects the quotes as they are now. Code: `supabase/functions/_shared/line_specs/compare.ts`.

## Shape

```ts
type Flag = 'match' | 'differs' | 'missing' | 'stated' | 'not_applicable';
// marker to print:  match "✓"   differs "≠"   missing "—"   stated ""   not_applicable "n/a"

type TechnicalComparison = {
  contract: 'technical_comparison';
  version: 1;
  generated_at: string;              // ISO-8601
  trade: string;                     // the request's trade (the fn_quote_spec_group vocabulary)
  on_hold: number;                   // quotes held for missing details — a COUNT only, never who or why
  quotes: {                          // column order; one entry per quote the customer may see
    quote_id: string;                // quotes.id — an option is its own quote with its own id
    label_en: string;                // "Supplier A" or "Supplier A – Option 1"
    label_ar: string;                // "المورّد A" or "المورّد A – الخيار 1"
    supplier_letter: string;         // "A" — the same letter on every option of one supplier
    option_no: number;               // 1 for a single-option quote
  }[];
  lines: {                           // one row group per line of the customer's request
    row: number;                     // 1-based
    request_line: { line_no: number; description: string; qty?: number | string | null; unit?: string | null } | null;
                                     // null = a line some quote added that the request did not have,
                                     //        or there was no BOQ and rows follow the most itemised quote
    trade: string | null; trade_en: string | null; trade_ar: string | null;
    attributes: {
      code: string;                  // e.g. 'material', 'thickness_mm', 'finish', 'capacity_tr'
      label_en: string; label_ar: string;
      unit: string | null; unit_ar: string | null;   // 'mm' / 'ملم', 'TR' / 'طن' …
      mandatory: boolean;            // part of the trade's mandatory core
      requested: string | null;      // the customer's baseline value, when there is one
      requested_source: 'boq' | 'intake' | 'no_preference' | null;
      cells: {                       // same order as `quotes`
        quote_id: string;
        value: string | null;        // as the supplier stated it (canonical where a lexicon exists)
        source: 'extracted' | 'supplier_portal' | null;
        quote_line_no: number | null;// the supplier's own line it came from
        flag: Flag; marker: string;
      }[];
    }[];                             // attributes nobody stated, not mandatory, not requested are omitted
  }[];
  terms: {                           // always exactly these three, in this order
    code: 'delivery' | 'installation' | 'warranty';
    label_en: string; label_ar: string;
    requested: string | null;        // '2026-10-14' | 'required' | 'not_required' | '24 months minimum' …
    requested_source: 'intake' | 'no_preference' | null;
    cells: { quote_id: string; applies: boolean; value: string | null; flag: Flag; marker: string }[];
  }[];
  legend: Record<Flag, string>;
};
```

### How a flag is decided (deterministic, `compare.ts`)

| situation | flag |
|---|---|
| the attribute does not apply to that quote's line (e.g. refrigerant on an AHU, warranty on cleaning) | `not_applicable` |
| the quote does not state it | `missing` (—) |
| the customer answered *no preference* | `match` (✓) — any stated value counts, but it must be stated |
| no baseline at all | `stated` (value shown, no marker) |
| numbers equal within 1% / text equal or one contains the other | `match` (✓) |
| otherwise | `differs` (≠) |

Delivery: a lead time is converted to a date from `generated_at`; on or before the requested date is
`match`. Warranty: `months >= min_months` is `match`. Installation: `yes` vs `required`, `no` vs
`not_required`.

Held quotes never appear in `quotes` or in any cell. They are drafts until released; the report may
say "N quote(s) on hold for missing details" using `on_hold` and nothing else.

## The baseline: the customer's intake answers

The branch `intake-asks-the-right-questions` stores the customer's answers on the request. This
contract reads them from **`inquiries.spec.requirements`** with this shape (all optional):

```ts
type Requirements = {
  installation?: 'required' | 'not_required' | 'no_preference';
  warranty?: { required?: boolean | 'no_preference'; min_months?: number };
  delivery_by?: string;                              // 'YYYY-MM-DD'
  materials?: { component: string;                   // 'wardrobes', 'kitchen worktop', 'false ceiling'
                attr?: string;                       // an attribute code from line_specs/model.ts, optional
                value: string | 'no_preference' }[]; // '18mm MR MDF, HPL' or one attribute value
};
```

A `materials` entry applies to the request line whose description names the component. Without
`attr`, its value is read with the same readers as a quotation line, so "18mm MR MDF, HPL" yields
material, thickness and finish at once. The same requirements also drive the hold:
`installation: 'not_required'` makes installation not applicable; `warranty.required: true` makes a
warranty required even where the trade would not.

## The hold gate (for context; the report does not render it)

A quote is held — status stays `draft`, never shown to the customer — while any of these is missing:
(1) a mandatory spec attribute on any line, per its trade; (2) a concrete delivery date or lead time;
(3) installation included yes/no, and its scope or timeline if yes, where installation applies;
(4) the warranty period and what it covers, where a warranty applies. Applicability lives in
`line_specs/model.ts` (`installApplies`, `warrantyApplies`, `attrsForLine`).

## `standardised_quotation` v1 — the regenerated quotation

When a supplier completes the missing details on the portal, the sales engineer regenerates the
quotation and the supplier approves it. The record is `public.quote_spec_hold.regenerated`:

```ts
type Standardised = {
  contract: 'standardised_quotation'; version: 1;
  quote_id: string; option_no: number; category: string | null; trade: string; currency: 'AED'; total: number;
  lines: { line_no: number; description: string; qty: unknown; unit: unknown; unit_price: unknown; amount: unknown; trade: string | null;
           spec: { code: string; label_en: string; label_ar: string; value: string; unit: string | null; unit_ar: string | null;
                   source: 'extracted' | 'supplier_portal' }[] }[];
  terms: { delivery: string | null; installation: string | null; warranty: string | null;
           validity: string | null; payment_terms: string | null; exclusions: string | null };
  prepared_by: 'sales_engineer'; prepared_at: string;
};
```

Its PDF is drawn by `pdf_native` (the existing quote renderer, `lang: 'bi'`) from
`workflow.ts#pdfBody` and stored at `quote_spec_hold.pdf_bucket / pdf_path`. The spec values ride in
each item's description today; the PDF branch may render `lines[].spec` as its own columns.
