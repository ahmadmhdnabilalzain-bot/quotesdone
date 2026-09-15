# Supplier portal — Inquiries received and Quotations submitted (API contract)

Owner: `sales_engineer`. Founder, 15 Sep 2026: *"this is the most important part in the whole supplier
portal"* and *"later this will be a mobile app as well. the structure need to be built in already."*

Every behaviour below is a server action. The web portal (`src/components/portal/supplier/InquiriesTab.tsx`,
`QuotationsTab.tsx`, `QuoteReviewChat.tsx`) and any native app call the same actions and hold no rules or
conversation state of their own. The server code is `supabase/functions/supplier_api/`:
`quote_review.ts` (the rules and the engineer's words), `quote_review_flow.ts` (the conversation),
`quote_review_actions.ts` (these actions). The TypeScript shapes the web client uses are
`src/components/portal/supplier/quoteReviewApi.ts`.

## Transport

- `POST {SUPABASE_URL}/functions/v1/supplier_api`
- Headers: `Authorization: Bearer <the supplier's Supabase access token>`, `Content-Type: application/json`
- Body: `{ "action": "<name>", ...fields }`. Optional `lang: "en" | "ar"` (defaults to the supplier's saved locale).
- Answers JSON. Success is `ok: true`. Failure is an HTTP status plus `{ error, code, message }`.
- Files are base64 inside the JSON body (`file.b64`), at most 10 MB before encoding. No multipart, no browser-only API.

The supplier is always the company whose `leads.claimed_by` is the token's email address. No action
accepts a supplier id from the client.

## Privacy guarantees (enforced on the server)

- An inquiry is visible only when the caller is matched to it (`inquiry_matches`). Any other id answers `404 not_found`.
- The inquiry, BOQ and drawings reach the caller only through `supplier_api inbox`, which runs its
  scrubbers and its reveal gate. Before a reveal, nothing identifying the customer is returned, and only
  the **redacted** drawing pages are offered, as signed URLs that expire after 1 hour.
- Every file the supplier attaches passes the byte-type gate and the malware lookup (`sanitizeAndScan`)
  before it is stored in `quote-files/review/<supplier>/<inquiry>/`.
- Text the supplier confirms in the chat that becomes part of the quotation is cleaned of contact details
  and identity numbers before `submit_quote` stores it.

## Job number

`job_no` = the first 8 characters of the inquiry id, upper-case (for example `3F2A9C1E`). It is the same
reference the hold desk's notices print as "RFQ 3F2A9C1E".

## Inquiries received

### `inquiries_list`
Request: `{}`.
Response: `{ ok, approval_status, inquiries: InquiryListItem[] }`

```ts
InquiryListItem = {
  id, job_no, category, emirate, created_at, status, concluded, revealed, you_won,
  summary,                // scrubbed, at most 220 chars
  boq_lines, boq_withheld, drawing_pages,
  quotes: { id, option_no, status, quote_amount, on_hold }[],
  review: { state: ReviewState, updated_at } | null
}
```

### `inquiry_detail`
Request: `{ inquiry_id }`.
Response: `{ ok, inquiry }`. The inquiry holds everything in the list item plus `budget`, `scope_type`,
`spec`, `requested` (the customer's stated requirements in `en`/`ar`, the `spec.customer_requirements.display`
rows), `boq` (`{ boq: [{ section, description, qty, unit, basis, confidence }] }`), `boq_confidence`,
`drawing_pages` (signed URLs), and `quotes`.

### `inquiry_documents`
Request: `{ inquiry_id }`.
Response: `{ ok, job_no, boq_withheld, documents }`

```ts
documents: (
  | { kind: 'drawing_page', name, url, expires_in: 3600 }            // redacted page, signed URL
  | { kind: 'boq_csv', name, mime: 'text/csv', content, lines }       // UTF-8 with BOM; save `content` to a file
)[]
```

## Quotations submitted — the conversation with the sales engineer

Every conversation action returns a `ThreadView`, so a client renders the same thing after every step:

```ts
ThreadView = {
  ok: true, inquiry_id, job_no,
  state: 'none' | 'open' | 'reviewing' | 'changes_requested' | 'awaiting_choice'
       | 'awaiting_upload' | 'ready_to_submit' | 'submitted' | 'closed',
  choice: 'generate' | 'reupload' | null,
  can_write, can_upload, can_choose, can_submit, reviewing,
  file: { name } | null, total_ex_vat, submitted_quote_ids: string[],
  messages: {
    id, role: 'supplier' | 'sales_engineer',
    kind: 'text' | 'file' | 'review' | 'choice_prompt' | 'choice' | 'submitted' | 'notice',
    body_en, body_ar,          // the engineer's words (null on a supplier message)
    text,                      // the supplier's own words (null on an engineer message)
    attachments: { kind: 'quotation_file' | 'standard_quote', name, url, quote_id }[],
    issues: Issue[] | null,    // on a review: the points raised, line by line
    created_at
  }[],
  open_requests: { id, key, code, kind: 'adjustment' | 'clarification' | 'choice',
                   line_no, boq_line, label_en, label_ar, opened_at }[],
  updated_at,
  notice?: { code, message } | null   // the action ran but could not complete, e.g. registration_due
}
Issue = { code, kind: 'adjustment' | 'clarification', line_no, boq_line, attr, en, ar }
```

| action | request | what happens |
|---|---|---|
| `review_thread` | `{ inquiry_id }` | Reads the thread. Poll this every 2 s while `reviewing` is true. |
| `review_start` | `{ inquiry_id }` | Opens the thread if none exists; the engineer greets and says what will be checked. |
| `review_upload` | `{ inquiry_id, file: { b64, filename, mime }, text? }` | Stores and reads the file with no model (PDF with text, Excel, Word, CSV, email, zip), then reviews it. Returns the thread with the review. |
| `review_message` | `{ inquiry_id, text }` | The supplier's reply. Stated details (validity, lead time, VAT basis, price excluding VAT, warranty, installation, "BOQ line N excluded", "line N <spec>: value", "all prices in AED") are applied and the quotation is reviewed again. Questions are answered from the rules. "generate" or "upload" answers the choice. "submit" submits once ready. |
| `review_choose` | `{ inquiry_id, choice: 'generate' \| 'reupload' }` | `generate`: the quotation is submitted through `submit_quote` and the standardised quotation is attached (`attachments[].kind = 'standard_quote'`; open it with `quote_pdf`). `reupload`: waits for the new version, reviews it, then asks for `review_submit`. |
| `review_submit` | `{ inquiry_id }` | Only in `ready_to_submit`. Submits through `submit_quote` and closes the thread. |

Error codes: `not_found` 404, `no_company` 400, `file_required` / `text_required` / `invalid_choice` 400,
`file_too_large` 413, `unsafe_type` / `malware_detected` 415, `upload_failed` 502, `inquiry_closed` /
`review_closed` / `reviewing` / `not_awaiting_choice` / `not_ready` 409.

### The review rules (`quote_review.ts`, deterministic)

1. Every BOQ line is priced, matched by its words. An excluded line must be stated as excluded.
2. Quantity and unit match the BOQ, unless the difference is explained.
3. Every line with a quantity has a price.
4. The line amounts add up to the total.
5. Prices are in AED.
6. The VAT basis is stated: includes, excludes, or not VAT-registered. A TRN is never asked for; below AED 375,000 a business is not registered.
7. The validity is concrete: a number of days or a date.
8. The exact-specs rules of the hold desk (`_shared/line_specs/assess.ts`, unchanged): per-line specification for the trade and for the customer's named components, delivery, installation and warranty when they apply, and the price excluding VAT.

### Submission

The engineer never writes a quote. `review_choose('generate')` and `review_submit` call `supplier_api
submit_quote` in-process as the same supplier, with the reviewed lines, terms, the confirmed
specifications (`items[].spec`) and terms (`terms_spec`), and the original file. The hold gate, the
accept rule, options, VAT, the customer's notice, the comparison and the reveal therefore behave exactly
as for any other quotation. If the hold gate still finds a missing detail, its list comes back into the
conversation as new open points.

### Storage

`public.quote_reviews` (one per inquiry and supplier), `public.quote_review_messages` (a registered
conversation store: kept permanently and archived), and `public.quote_review_request` (every point
raised, open until answered). RLS lets a signed-in supplier read only their own rows. Only the service
role writes. SQL: `scripts/sql/the_supplier_and_the_sales_engineer_review_a_quotation_in_one_conversation.sql`.
