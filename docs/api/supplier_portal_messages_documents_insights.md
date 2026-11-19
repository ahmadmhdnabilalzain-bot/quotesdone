# Supplier portal API: Messages, Documents, Insights

Owner: `sales_engineer`. Written 15 Sep 2026 on the founder's direction: *"later this will be a mobile app
as well. the structure need to be built in already."* Every behaviour below is a server action with a typed
request and response. Gates and calculations run on the server, so a mobile client renders the same data
natively. The web portal is one client.

## Calling convention

- `POST https://<project>.supabase.co/functions/v1/<function>` with a JSON body `{ "action": "...", ... }`.
- `Authorization: Bearer <supplier session access token>`: the Supabase Auth session of the signed-in
  supplier. The supplier is found through `leads.claimed_by = <session e-mail>`. No other identity is accepted.
- Errors come back as `{ ok: false, error: "<code>", ... }` or `{ error: "<code>" }` with a non-2xx status.
  `401 unauthorized` means the session expired. `400 no_company` means the account has no supplier yet.
- Text a supplier reads is **not** in these payloads. Payloads carry codes and numbers, and the words for
  every code live in `src/components/portal/supplier/workspaceCopy.ts` (English and Arabic).
  `scripts/checks/supplier_workspace_copy_is_bilingual.test.mjs` proves that every code has both.

---

## 1. Messages (`messages_api`)

### `mailbox` shows the gate and the revealed jobs' threads

Request `{ action: "mailbox" }`. Only a supplier can call it (`403 not_a_supplier` otherwise).

```ts
type Mailbox = {
  ok: true; role: 'supplier';
  gate: { open: boolean; reason: 'revealed' | 'no_revealed_job'; revealed_jobs: number };
  threads: {
    inquiry_id: string; supplier_id: number; counterpart: 'customer';
    subject: string | null; category: string | null; emirate: string | null;
    revealed_at: string;            // ISO time the customer paid the reveal fee
    respond_by: string | null;      // Supplier Agreement cl. 11/33: 5 working days from the reveal
    acknowledged_at: string | null; // the supplier confirmed contact
    chat_status: 'open' | 'none' | 'banned' | 'closed'; // 'none' = not opened yet (opens on first touch)
    last: string | null; last_at: string | null; unread: number;
  }[];
  unread_total: number;
};
```

When `gate.open` is false, show the locked state (`mb_locked_*` copy). **The payload carries no customer
identity, even after the reveal.** The customer's name, e-mail and phone come from `supplier_api` `projects`,
which is also keyed on the supplier's own revealed transactions.

### `thread` reads one conversation

Request `{ action: "thread", inquiry_id, supplier_id }`. The response is
`{ ok, role, counterpart, chat_status, warning, messages: { id, sender: 'customer'|'supplier', body, created_at }[] }`,
or `{ ok: true, locked: true, messages: [] }` when the job is not revealed. Reading a thread marks the
customer's messages as read by the supplier.

### `send` sends a message

Request `{ action: "send", inquiry_id, supplier_id, body }`, where `body` holds at most 2,000 characters.
The response is `{ ok: true, message }`. Without a reveal the call gets `403`, and an empty body gets `400 empty`.
The customer is told by e-mail.

### Where the reveal gate is enforced (none of these places is a client)

1. `mailbox` builds its list only from the supplier's own `transactions` rows that have `revealed_at` set.
2. `thread` and `send` check `revealed(inquiry_id, supplier_id)` again on every call.
3. `public.messages` and `public.chat_threads` have RLS on with no policy, and anon and authenticated get
   no grant (measured 15 Sep 2026). A session token cannot read or write either table directly.

The unread count also appears in `supplier_portal` `notifications` (`unread_messages`), which drives the bell
and the tab badge.

---

## 2. Documents (`supplier_portal`)

### Required and fixed kinds (unchanged)

- `documents` returns `{ ok, documents: { key, label, hint_code, path, name, expiry, has_expiry, required, status, url }[], summary, expiries }`.
  `status` is one of `missing | on_file | valid | expiring | expired`. `url` is signed for 1 hour.
- `save_documents` takes `{ items: { kind, original_b64, filename, mime, expiry? }[] }` (up to 15) and returns
  `{ ok, saved: string[], failed: { kind, reason }[] }`. Kinds are `license, profile, catalogs, vat, insurance,
  iso, manufacturer, egr, iban`. The licence expiry is read off the licence itself and never typed.
  Licence and profile are the documents in the mandatory six (`fn_supplier_mandatory_six`).
- `eligibility` returns the registration checklist, which sits at the top of the Documents tab.

### Supporting company documents (new)

Any other document, uploaded freely. The supporting documents never write a `leads` column, so they cannot
satisfy or bypass the mandatory six.

| action | request | response |
|---|---|---|
| `supporting_documents` | `{}` | `{ ok, documents: SupportingDocument[], types: string[], limits: { max_documents: 30, max_bytes: 26214400, max_label: 120 } }` |
| `supporting_document_save` (upload) | `{ label, type?, filename, mime, original_b64 }` | `{ ok, document }` |
| `supporting_document_save` (replace / rename) | `{ id, original_b64?, filename?, mime?, label?, type? }` | `{ ok, replaced: boolean, document }` |
| `supporting_document_delete` | `{ id }` | `{ ok, id }` |
| `supporting_document_url` (download) | `{ id }` | `{ ok, id, url, expires_in: 3600, file_name }` |

```ts
type SupportingDocument = { id: number; label: string; type: SupportingType; file_name: string; mime: string | null; uploaded_at: string; url: string | null };
type SupportingType = 'certificate' | 'accreditation' | 'reference_letter' | 'project_reference' | 'financial_statement'
  | 'organisation_chart' | 'hse_policy' | 'quality_policy' | 'brochure' | 'other';
```

Errors: `400 label_required | file_required | bad_type | bad_id | nothing_to_change`, `404 not_found` (an id
that is not this supplier's reads exactly like a missing one), `409 limit_reached`, `413 too_large`,
`422 file_refused` (`reason` from the type and malware scan), `502 upload_failed | save_failed | delete_failed | url_failed`.

**Storage and backup.** Files go to the `supplier-docs` bucket at `supporting/<supplier id>/<epoch>_<name>`.
The same checks as every other upload apply: `sanitizeAndScan` (type decided from the bytes, malware scan),
plus the bucket's own 25 MB and MIME limits. Each file gets a record in `public.documents` with
`ref_table = 'supplier_supporting'`, `ref_id = <supplier id>`, `kind = 'supporting:<type>'`, and
`file_name = <label>`. Its `status` is `received`, which keeps it off `doc_extract`'s OCR queue.
The ref table is not `leads`, so the file stays private: customers who revealed the supplier see nothing.
Backups to Dropbox use the STORAGE SWEEP of `fn_enqueue_doc_backups`, since `supplier-docs` is a swept
bucket in `fn_backup_source_registry`, and the sweep files each object under `supplier:<id>`.
**Remove** sets `status = 'withdrawn'`, which hides the document. The stored file and its backup are kept.

---

## 3. Insights (`supplier_portal`)

### `insights_summary`

Request `{ action: "insights_summary" }`.

```ts
type InsightsSummary = {
  ok: true; version: 1; currency: 'AED'; has_data: boolean;
  totals: { inquiries_received: number; quotations_submitted: number; jobs_won: number; revenue_aed: number };
  rates: { win_pct: number | null; reveal_pct: number | null; response_pct: number | null;
           avg_lead_time_days: number | null; rating: number | null; lost_to_others: number };
  price_position: {
    band: 'below' | 'around' | 'above' | 'no_data';
    // 5-point steps, and null ('no_data') until 5 inquiries each carry submitted quotes from 3+ OTHER suppliers
    // (fn_supplier_stats, 19 Nov 2026, founder ruling 1686: with one rival the exact % gave away his price)
    pct_vs_market_avg: number | null; pct_above_lowest: number | null; lowest_rate_pct: number | null;
    competitive_rfqs: number; times_lowest: number;
    gauge: number | null;                       // -1 (>= 20% below) .. +1 (>= 20% above)
    band_edges: { below_max: -4; above_min: 5 } // % vs market average
  };
  funnel: { key: 'received' | 'quoted' | 'revealed' | 'won'; count: number; conversion_pct: number | null }[];
  series: { month: 'YYYY-MM'; quotes: number; reveals: number }[];   // last 12 months, oldest first
  hints: { code: HintCode; severity: 'high' | 'medium' | 'low'; params: Record<string, number | string>;
           action: 'rfqs' | 'quotes' | 'messages' | 'documents' | 'services' | 'profile' | null }[];
};
```

The fields are measured as follows.

- `inquiries_received` counts `inquiry_matches` rows for the supplier.
- `quotations_submitted`, `jobs_won`, the rates, `price_position` and `series` come from
  `fn_supplier_stats`. Price position compares the supplier's quotes with every other priced quote on the
  same inquiries, and only inquiries with at least 2 priced quotes count. No competitor's price is returned.
- `revenue_aed` is the quote value on each **won** job (`inquiries.hired_supplier_id`), taken from the
  revealed transaction. Refunded transactions are excluded.
- `hints` are deterministic rules, sorted most costly first. The codes are `hint_not_eligible`,
  `hint_doc_expired`, `hint_doc_expiring`, `hint_quote_more`, `hint_price_above`,
  `hint_price_below_no_reveal`, `hint_follow_up`, `hint_response_rate`, `hint_lead_time`,
  `hint_first_request` and `hint_all_good`. The words for each are `<code>_t` and `<code>_b` in
  `workspaceCopy.ts`, and `params` fills their placeholders.
- A new supplier gets zeros, `has_data: false`, `price_position.band = 'no_data'` and one hint. No sample data is returned.

`dashboard` (#702) stays as it was: the supplier card, the bell counts (`notifications`), `eligibility` and
`document_impact`.

### `scorecard` (29 Sep 2026, founder_instruction 1013 item 2)

`{ action: 'scorecard' }` → `{ ok: true, card }`. `card` is `fn_supplier_scorecard(lead)` for the last complete
calendar month in Dubai:

- `metrics.response_hours | win_rate | rating`, each `{ you, trade_average, trade_suppliers, better }`.
  `trade_average` is `null` unless at least `min_suppliers_for_average` (3) suppliers of the same trade have that
  measure in the month.
- `enough_data` and `message`: with no measure at all, `message` is `"not enough data yet"`.
- `activity`: requests sent, quoted, won (revealed or hired), ratings.
- `tip`: `{ code, text }`, one rule-chosen tip (`complete_profile`, `answer_invitations`, `respond_faster`,
  `sharpen_quotes`, `lift_rating`, `keep_going`).

It is English only, whatever the page language. `SupplierScorecard.tsx` renders it at the top of Insights. The same card
goes out by e-mail once a month (`fn_sales_engineer_supplier_scorecard_tick`, recorded in `supplier_scorecard`).

## Tests

- `supabase/functions/supplier_portal/insights_summary.test.ts`
- `supabase/functions/supplier_portal/supporting_documents.test.ts`
- `supabase/functions/messages_api/mailbox.test.ts`
- `scripts/checks/supplier_workspace_copy_is_bilingual.test.mjs`
