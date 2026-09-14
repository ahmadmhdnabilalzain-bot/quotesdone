# Contract: the customer's intake answers (`inquiries.spec.customer_requirements`)

Owner: **sales_engineer**, the only agent in the customer and supplier portals (founder ruling of
14 Sep 2026). Code: `supabase/functions/_shared/intake_requirements.ts`. Tests:
`_shared/intake_requirements.test.ts`, `inquiry_intake/generators_replay.test.ts`.

## Why it exists

The founder, 14 Sep 2026: *"when we take the inquiry from the customer, we can ask those questions to
make sure the inquiry is fully detailed ... do you require a warranty? do you require installation? do
you have specific material in mind ... maybe he doesnt even care, but our job is to ask."* Later that
day: *"for installation for example, we need to ask, cause maybe the customer will forget. we don't
assume stuff".*

Every quote must state material specs per line, a delivery date, installation and warranty, or it is
held (branch `exact-specs-or-hold`, `docs/contracts/technical_comparison.md`). This object is the
customer's side of those four things. It is the **baseline** the technical comparison judges
"matches your request / differs" against. It is also the **only** source for whether installation and
warranty apply to a request: the hold check (branch `hold-check-follows-the-request`) reads it here,
never from trade defaults.

## The rule: all four, every trade, never assumed

`inquiry_intake` asks these questions after the category's own `category_specs` checklist is
complete, on both the model path and the deterministic path. Every trade gets all four kinds of
question. A trade with no material components of its own gets one open "main material or brand"
question.

| Question | Explicit answers (tap, EN / MSA Arabic) |
|---|---|
| Material per main component (`material.<component>`) | the trade's options, **No preference**, or the customer's own words (stored as `other` with a `note`) |
| Installation | **Yes, install it**, **Supply only, no installation**, **Not needed for this job**, **Not sure**. A bare "no" is asked again, because it could mean either of the middle two. |
| Warranty (minimum period) | **Yes, at least 1 / 2 / 5 years** (or a stated period), **Not needed**, **Not sure**. A "yes" with no period is asked again. |
| Required by | a date (chips or typed), or **Flexible** |

**Suggestions are never answers.** The trade profile may point to a usual answer; for example, for
cleaning, movers and consultancy, installation and warranty point to *Not needed*. Anything the
category checklist already heard (a supply/install scope, a timeline, a material field) is also
offered as the suggestion. The composer highlights the suggested option and labels it *Suggested*,
and the message says "Suggested for this job: X. Tap it to confirm, or pick another." Nothing is
recorded until the customer chooses.

The intake is not `ready`, and `create_inquiry` refuses to post (`428 requirements_incomplete`),
until `validateStored` finds a valid explicit answer to every question. The customer can change any
answer on the summary card before posting (`requirement_edits`), and each edit is parsed again on
the server.

## Stored shape (version 2)

```jsonc
{
  "version": 2,
  "recorded_by": "sales_engineer",
  "category": "custom-furniture",            // the category the questions were asked for
  "recorded_at": "2026-09-14T10:00:00.000Z",
  "installation": { "required": "yes" },     // "yes" | "supply_only" | "not_needed" | "not_sure": always the customer's choice
  "warranty": { "required": "yes", "min_months": 24 },   // "yes" | "not_needed" | "not_sure"; min_months only with "yes"
  "materials": [
    { "component": "legs_base", "label_en": "Legs or base", "label_ar": "الأرجل أو القاعدة",
      "choice": "steel", "choice_en": "Steel", "choice_ar": "حديد (ستيل)", "note": null },
    { "component": "top_body", "choice": "no_preference", ... },
    { "component": "hardware", "choice": "other", "choice_en": "Other: brass", "note": "brass", ... }
  ],
  "required_by": { "flexible": false, "date": "2026-10-14", "text": "Within 1 month" },
  "display": { "en": [{ "key": "installation", "label": "Installation", "value": "Yes, install it" }], "ar": [ ... ] }
}
```

Version 1 (#608) allowed `installation` / `warranty` to be `null` ("not applicable" by trade) and used
`"no"` for supply only. Version 1 answers do not validate. An open intake holding them is asked the
questions again, and `create_inquiry` refuses a version-1 set.

`display` is derived. Every surface (the customer request card, the supplier RFQ, the supplier brief
PDF) renders the same words from it without re-implementing the vocabulary. The machine fields are
the contract; `display` is for reading only.

## Where it goes

- `inquiry_intake` → `brief.requirements` (also `brief.requirement_questions` for the summary card),
  and `next_question.suggested` while asking.
- `customer_api create_inquiry` → `inquiries.spec.customer_requirements`. It is copied to every child
  of a split request. `required_by.date` fills `inquiries.required_by` and `required_by.text` fills
  `inquiries.delivery_window` when the brief had none. The supplier invitation carries one line of
  the chip values (`supplierLine`), never a customer's free-text note.
- Suppliers read it through `inquiries_supplier_safe` / `supplier_api` with the rest of `spec`, after
  the same identity scrubbing (`scrub_inquiry_contacts` → `spec_masked`, and `scrubDeep`). Nothing
  here names the customer.

## Baseline semantics for the technical comparison and the hold check

| Customer answer | Installation / warranty applies? | A quote matches when |
|---|---|---|
| `installation.required = "yes"` | yes | the quote includes installation |
| `installation.required = "supply_only"` | no (supply only) | the quote is supply / delivery only, or prices installation separately |
| `installation.required = "not_needed"` | no | the quote does not charge for installation |
| `warranty.required = "yes"`, `min_months = N` | yes | the stated warranty is ≥ N months |
| `warranty.required = "not_needed"` | no | any, or no warranty stated |
| `"not_sure"` (installation or warranty) | the supplier must state it, shown as information and never as a difference | anything the supplier states |
| material `choice = "no_preference"` | — | any stated material |
| material `choice = <value>` | — | the stated material for that component is that value |
| material `choice = "other"` | — | shown beside the supplier's material for the customer to judge (free text is not auto-matched) |
| `required_by.date = D` | — | the stated delivery / completion date is on or before D |
| `required_by.flexible = true` | — | any stated date |

## Changing it

Add a trade by adding a `PROFILES` row with both languages. Tests fail on any question or option
without Arabic, on any trade that does not ask all four, and on any material question without
**No preference**. A breaking shape change bumps `VERSION`. `validateStored` accepts only the current
version, so open answer sets are asked again rather than trusted.
