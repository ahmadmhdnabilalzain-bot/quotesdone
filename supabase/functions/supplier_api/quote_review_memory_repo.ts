// supplier_api/quote_review_memory_repo.ts — the quotation conversation's repository, in memory.
//
// The test double for quote_review_flow.ts: quote_review.test.ts runs the whole conversation on it,
// and scripts/e2e/supplier_quote_review.mjs's pre-deploy mode serves the new actions from it, so the
// portal can be driven through the real rules before the tables exist in production. It holds no
// credential and reaches nothing: a supplier addressed from here cannot be a real one.
import type { MessageRow, NewRequest, RequestRow, ReviewRepo, ReviewRow } from './quote_review_flow.ts';

export function memoryReviewRepo(now: () => Date = () => new Date()) {
  const reviews: ReviewRow[] = []; const messages: MessageRow[] = []; const requests: RequestRow[] = [];
  const files = new Map<string, { bytes: Uint8Array; mime: string }>(); const logs: { counts: Record<string, unknown>; note: string }[] = [];
  let seq = 0;
  const id = () => `00000000-0000-4000-8000-${String(++seq).padStart(12, '0')}`;
  const iso = () => new Date(now().getTime() + seq).toISOString();   // strictly increasing, so order is stable
  const repo: ReviewRepo = {
    review: (i, s) => Promise.resolve(structuredClone(reviews.find((r) => r.inquiry_id === i && r.supplier_id === s) ?? null)),
    reviewsOf: (s) => Promise.resolve(reviews.filter((r) => r.supplier_id === s).map((r) => ({ inquiry_id: r.inquiry_id, status: r.status, updated_at: r.updated_at }))),
    createReview(r) {
      const row: ReviewRow = { id: id(), ...r, status: 'open', choice: null, original_file_path: null, original_file_name: null, extracted: null, working: null, last_review: null,
        reviewing_since: null, total_amount: null, currency: 'AED', submitted_quote_ids: null, completed_at: null, created_at: iso(), updated_at: iso() };
      reviews.push(row); return Promise.resolve(structuredClone(row));
    },
    claim(i, from, to) {
      const r = reviews.find((x) => x.id === i);
      if (!r || !from.includes(r.status)) return Promise.resolve(false);
      Object.assign(r, { status: to, reviewing_since: iso(), updated_at: iso() }); return Promise.resolve(true);
    },
    updateReview(i, p) { const r = reviews.find((x) => x.id === i); if (r) Object.assign(r, structuredClone(p), { updated_at: iso() }); return Promise.resolve(); },
    addMessage(m) { const row: MessageRow = { ...structuredClone(m), id: id(), created_at: iso() }; messages.push(row); return Promise.resolve(structuredClone(row)); },
    messages: (rid) => Promise.resolve(structuredClone(messages.filter((m) => m.review_id === rid))),
    requests: (rid, onlyOpen) => Promise.resolve(structuredClone(requests.filter((q) => q.review_id === rid && (!onlyOpen || q.state === 'open')))),
    addRequests(rows: NewRequest[]) { for (const r of rows) requests.push({ ...structuredClone(r), id: requests.length + 1, state: 'open', answered_message_id: null, opened_at: iso(), answered_at: null }); return Promise.resolve(); },
    closeRequests(ids, state, mid) { for (const q of requests) if (ids.includes(q.id) && q.state === 'open') Object.assign(q, { state, answered_message_id: mid, answered_at: iso() }); return Promise.resolve(); },
    storeFile(p, bytes, mime) { files.set(p, { bytes, mime }); return Promise.resolve(true); },
    signFile: (b, p) => Promise.resolve(files.has(p) ? `memory://${b}/${p}` : null),
    log(counts, note) { logs.push({ counts, note }); return Promise.resolve(); },
  };
  return { repo, reviews, messages, requests, files, logs };
}
