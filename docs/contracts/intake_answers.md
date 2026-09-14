# Contract: the customer's intake answers (`inquiries.spec.customer_requirements`)

Owner: **sales_engineer** (the only agent in the customer and supplier portals, founder ruling of
14 Sep 2026). Code: `supabase/functions/_shared/intake_requirements.ts`. Tests:
`_shared/intake_requirements.test.ts`, `inquiry_intake/generators_replay.test.ts`.

## Why it exists

The founder, 14 Sep 2026: *"when we take the inquiry from the customer, we can ask those questions to
make sure the inquiry is fully detailed ... do you require a warranty? do you require installation? do
you have specific material in mind ... maybe he doesnt even care, but our job is to ask."*

Every quote must state material specs per line, a delivery date, and installation and warranty
where they apply, or it is held (branch `exact-specs-or-hold`, `docs/contracts/technical_comparison.md`).
This object is the customer's side of those four things, so it is the **baseline** the technical
comparison judges "matches your request / differs" against.

## When it is asked

`inquiry_intake` asks these questions after the category's own `category_specs` checklist is
complete, on both the model path and the deterministic path. They are asked one at a time, with
tap-able options in the customer's language (English or MSA Arabic). The intake is not `ready` until
every applicable question has an answer. `create_inquiry` refuses to post with
`428 requirements_incomplete` unless the stored object passes `validateStored`. The customer can change
any answer on the summary card before posting (`requirement_edits`), and each edit is parsed again
on the server.

| Question | Asked when | Skipped only by |
|---|---|---|
| Material per main component (`material.<component>`) | The trade's profile lists components. A category with no profile gets one open "main material or brand" question. | Tapping **No preference** (`no_preference`). Typing something else is kept verbatim as `other` + `note`. |
| Installation | `PROFILES[cat].install`. Not asked for pure services: cleaning, pest, movers, consultancy, painting, waterproofing (applying is the job), demolition, scaffold hire and similar. | **Not sure** (`not_sure`) |
| Warranty (with minimum period) | `PROFILES[cat].warranty`. Not asked where no warranty is sold (cleaning, movers, consultancy, demolition, scaffolding, interior design, tank cleaning). | **Not sure** (`not_sure`). A "yes" with no period is asked again. |
| Required by | Always | **Flexible** |

When the category checklist already answered one of these (a `field` named in the profile, a
supply/install scope, a timeline), the answer is carried over and not asked again.

## Stored shape (version 1)

```jsonc
{
  "version": 1,
  "recorded_by": "sales_engineer",
  "category": "custom-furniture",            // the category the questions were asked for
  "recorded_at": "2026-09-14T10:00:00.000Z",
  "installation": { "required": "yes" },     // "yes" | "no" | "not_sure"; null = not applicable
  "warranty": { "required": "yes", "min_months": 24 },   // min_months null unless "yes"; null = not applicable
  "materials": [
    { "component": "legs_base", "label_en": "Legs or base", "label_ar": "الأرجل أو القاعدة",
      "choice": "steel", "choice_en": "Steel", "choice_ar": "حديد (ستيل)", "note": null },
    { "component": "top_body", "choice": "no_preference", ... },
    { "component": "hardware", "choice": "other", "choice_en": "Other: brass", "note": "brass", ... }
  ],
  "required_by": { "flexible": false, "date": "2026-10-14", "text": "Within 1 month" },
  "not_applicable": [],                      // "installation" and/or "warranty" when the trade has none
  "display": { "en": [{ "key": "installation", "label": "Installation", "value": "Yes, install it" }], "ar": [ ... ] }
}
```

`display` is derived and exists so every surface (customer request card, supplier RFQ, supplier
brief PDF) renders the same words without re-implementing the vocabulary. The machine fields are
the contract. `display` is for reading only.

## Where it goes

- `inquiry_intake` → `brief.requirements` (also `brief.requirement_questions` for the summary card)
- `customer_api create_inquiry` → `inquiries.spec.customer_requirements`. It is copied to every
  child of a split request. `required_by.date` fills `inquiries.required_by` and `required_by.text`
  fills `inquiries.delivery_window` when the brief had none. The supplier invitation carries one line
  of the chip values (`supplierLine`), never a customer's free-text note.
- Suppliers read it through `inquiries_supplier_safe` / `supplier_api` with the rest of `spec`, after
  the same identity scrubbing (`scrub_inquiry_contacts` → `spec_masked`, and `scrubDeep`). Nothing
  here names the customer.

## Baseline semantics for the technical comparison

| Customer answer | A quote matches when |
|---|---|
| `installation.required = "yes"` | the quote includes installation |
| `installation.required = "no"` | the quote is supply / delivery only, or prices installation separately |
| `"not_sure"` anywhere | anything the supplier states (shown as information, never as a difference) |
| `warranty.required = "yes"`, `min_months = N` | the stated warranty is ≥ N months |
| material `choice = "no_preference"` | any stated material |
| material `choice = <value>` | the stated material for that component is that value |
| material `choice = "other"` | shown beside the supplier's material for the customer to judge (free text is not auto-matched) |
| `required_by.date = D` | the stated delivery / completion date is on or before D |
| `required_by.flexible = true` | any stated date |

## Changing it

Add a trade by adding a `PROFILES` row with both languages. Tests fail on any question or option
without Arabic, and on any material question without **No preference**. A breaking shape change
bumps `version`, and `validateStored` must accept both versions until every open request has moved.
