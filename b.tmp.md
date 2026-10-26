Assigned: **sales_engineer** (customer + supplier portals), with **it_engineer** (QA selectors).

**Gap:** #1237 built `pdpl_request_me` / `pdpl_confirm_me` / `pdpl_cancel_me`; privacy policy 1.6 promises self-service; nothing in either portal called them.

**Built** — `src/components/portal/PrivacyControls.tsx` (copy + answer-reading in `privacy.ts`), mounted at the end of the customer Account page (EN + native Arabic, RTL) and the supplier Settings page (English only):
- **Download my data** → `pdpl_request_me('export')` → JSON file downloads, status shown. The contract asks no code for export (session + verified email), so none is asked.
- **Delete my account and data** → warning (tax/invoice records 5 years, open disputes/refunds/unpaid kept until settled, 7-day window) → tick → `pdpl_request_me('delete')` emails a code → `pdpl_confirm_me` → "Deletion scheduled for <date>, cancel any time before" + **Cancel** (`pdpl_cancel_me`) + per-record kept reason / legal hold in plain words.
- Refusals (unverified email, wrong code with tries left, spent code, rate limit, window closed) are our own sentences in the reader's language, never server text.
- Labels, focus management, `role=alert/status`, 44px targets; no "AI" wording.
- `data-testid`: `privacy-export`, `privacy-erase`, `privacy-erase-ack`, `privacy-code`, `privacy-erase-confirm`, `privacy-erase-cancel`.

**Backend:** one new read routine, `pdpl_status_me()` (own open requests: kind, state, scheduled date, holds; SECURITY DEFINER, pinned search_path, revoked PUBLIC/anon, granted authenticated, named in the kernel gate allow-list like #1262). **Pending, apply at merge** (`scripts/sql/pending/a_person_sees_their_own_open_privacy_requests_on_any_device.txt`). The page reads it on load, so Cancel shows on any device; the browser copy is only a fallback until it is live.

**Tests:** `node --test src/components/portal/privacy.test.mjs` — 10/10 (contract vs SQL grants and argument names, both mounts, supplier English, wording, holds, Arabic has no Latin). No database writes; no real erase. `tsc --noEmit` clean.

prevented by: `src/components/portal/privacy.test.mjs`

🤖 Generated with [Claude Code](https://claude.com/claude-code)

