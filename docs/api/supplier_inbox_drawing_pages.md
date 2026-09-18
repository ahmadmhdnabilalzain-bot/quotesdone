# Supplier inbox API: the redacted drawing pages

Owner: `sales_engineer`. Written 18 Sep 2026. Subject: the drawing pages `supplier_api` action `inbox`
serves a supplier for each matched inquiry, and what the client must say when one of them cannot be
opened. API-first, so a mobile client renders the same counts natively.

## The defect this documents

`inbox` signed each path in `inquiries.drawing_redacted_paths` with a helper that returned `null` on any
error and swallowed it, and pushed the URL only if it was truthy. A page that failed to sign was
**dropped**: the supplier saw an inquiry with fewer drawings — or none — and nothing recorded that a page
was meant to be there. Measured on production by driving `scripts/e2e/supplier_quote_review.mjs` four
times: one whole run served **zero** pages for all four inquiries while the rows were correct and the
objects had uploaded successfully; the next run served them normally. A supplier in that window would
have priced a villa painting job from the bill of quantities alone.

## The fields

Each element of `inquiries[]` carries:

```ts
type InquiryDrawings = {
  /** Signed URLs (1 h) for the pages that SIGNED. Every page that can be served still is. */
  drawing_pages: string[];
  /** How many pages the inquiry has on inquiries.drawing_redacted_paths. 0 = this inquiry has no drawings. */
  drawing_pages_expected: number;
  /** How many of them were signed and are in drawing_pages. */
  drawing_pages_served: number;
  /** How many could NOT be signed. Always expected − served. > 0 means pages are missing from this card. */
  drawing_pages_failed: number;
};
```

The three counts exist so a zero is readable: `expected: 0` is an inquiry with no drawings;
`expected: 3, served: 3, failed: 0` is three drawings that all arrived. A client that shows only
`drawing_pages.length` cannot tell those apart — which is exactly how the defect stayed invisible.

## What the client renders

`drawing_pages_failed > 0` → show the count. The words are in
`src/components/portal/supplier/workspaceCopy.ts` (English and Arabic, proved by
`scripts/checks/supplier_workspace_copy_is_bilingual.test.mjs`):

| condition | key |
| --- | --- |
| some pages served, some failed | `rfq_pages_unavailable` — params `{n}` = failed, `{total}` = expected |
| every page failed (`drawing_pages.length === 0`) | `rfq_pages_none` |

The web client renders both in `DrawingGallery` (`src/components/portal/supplier/RfqParts.tsx`), which for
this reason no longer returns `null` when there are no URLs but pages were expected.

## What the server records

`supabase/functions/_shared/drawing_pages.ts` logs each failure (**the object path and the storage
client's message only** — never a signed URL, a token or a key) and raises **one** IT engineer finding per
request through `fn_it_engineer_finding_upsert`:

- `issue_key`: `supplier_inbox:drawing_page_sign_failed` (one key, so a recurrence dedupes and reopens)
- `blast`: `customer_facing`, `affected`: the number of failed pages, `raised_by`: `sales_engineer`
- `evidence`: `pages_expected`, `pages_served`, `pages_failed`, `inquiries_affected`, `per_inquiry[]` and
  up to five `sample_errors` of `{ path, message }`

It fires only when a page that was meant to be served was not — never on an inquiry with no drawings, so
the guard can tell a broken system from an idle one. Proved by
`supabase/functions/_shared/drawing_pages.test.ts`.

Two failure modes of the mechanism itself are covered, because a guard that fails quietly is the defect
it was built to remove:

- a signing call that never answers is ended after 8 s and counted as an ordinary failure, so one stalled
  page cannot hold the whole `inbox` response open;
- if `fn_it_engineer_finding_upsert` itself cannot be reached, a second queryable trail is written to
  `agent_runs` (`agent: 'sales_engineer'`, `counts.signal: 'drawing_page_sign_failed'`,
  `counts.finding_unavailable: 1`) rather than only a log line.
