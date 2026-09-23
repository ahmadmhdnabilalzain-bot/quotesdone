// review_reading.fixture.ts — the MOCKED reasoning for the review tests (decision points 29-30, 23 Sep 2026).
//
// In production the review reads a quotation with think() (quote_review.ts readWorking → reasoned_matching.ts
// readQuote), and under the model hold reads nothing. These tests call no model: this fixture stands in for its
// answer. review_reading.fixture.json holds, per "category|line text", what a model is expected to read from
// that line (its stated values, "does not apply", "no material", a customer's component named). The entries were
// generated ONCE from the word readers the gate used before 23 Sep 2026, so every test keeps asserting the
// behaviour it asserted then — now with the reading supplied as data instead of decided by a pattern.
// A line with no entry is read as nothing (the hold): its details are asked, exactly as production would.
// TODO(B4, decision points 31/36): the terms below still use legacy_word_readers.ts as the mock of what a model
// reads from the terms; replace with fixture data when that file is deleted.
import READS from './review_reading.fixture.json' with { type: 'json' };
import { readInstallation, readWarranty } from '../_shared/line_specs/legacy_word_readers.ts';
import type { SafeInquiry, Working } from './quote_review.ts';

const R = READS as Record<string, Record<string, string>>;
/** Line texts the fixture has no reading for, so a test can see what it did not mock. */
export const UNREAD = new Set<string>();
export function readFixture(inq: SafeInquiry, w: Working): Working {
  const lines = w.lines.map((l) => {
    const text = [l.description, l.specification].filter((x) => x != null && String(x).trim() !== '').join(' · ');
    const r = R[`${inq.category}|${text}`];
    if (!r) { UNREAD.add(`${inq.category}|${text}`); return l; }
    const add = Object.fromEntries(Object.entries(r).filter(([k]) => !l.spec?.[k]));
    return { ...l, spec: { ...add, ...(l.spec ?? {}) }, spec_source: { ...Object.fromEntries(Object.keys(add).map((k) => [k, 'reasoned' as const])), ...(l.spec_source ?? {}) } };
  });
  const ts = { ...w.terms_spec };
  if (!ts.installation?.included) {
    const i = readInstallation(lines.map((l, n) => ({ line_no: n + 1, description: l.description, specification: l.specification ?? null })), { scope: w.scope, conditions: w.conditions, notes: w.notes, exclusions: w.exclusions });
    if (i.included) ts.installation = { included: i.included, detail: i.detail, source: 'reasoned' };
  }
  if (!ts.warranty?.period) {
    const wr = readWarranty(w.warranty);
    if (wr.period) ts.warranty = { period: w.warranty, coverage: wr.coverage ?? '', source: 'reasoned' };
  }
  return { ...w, lines, terms_spec: ts };
}
