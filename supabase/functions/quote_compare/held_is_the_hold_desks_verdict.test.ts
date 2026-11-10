// One definition of "held": the comparison's roster says held only when the hold desk's own evaluator does.
// sales_engineer, 10 Nov 2026 - evidence run ea40c830, journey 2 (docs/reports/2026-11-10-journey-evidence.md, still-seen 3).
//
// THE CASE, from the run's comparison answer (comparison_analysis.json): four live quotes, on_hold 0 and quality_check.held 0
// (reveal_guard.heldQuoteIds - line_specs assessQuote, what spec_approve released Q2 on - held none of them), and the roster
// listed Supplier B, quote 72b94ebd (AED 71,966 ex VAT, "1 year on the complete installation", missing_mandatory 0) as
// "held" with no rank. rosterOf read quotes.quality.pass (trg_quote_quality, scored on the quote as first submitted) instead.
//   deno test --no-lock --allow-read supabase/functions/quote_compare/held_is_the_hold_desks_verdict.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { rosterOf, type Labelled } from './deterministic.ts';

type Row = Labelled & { quote_id: string };
const row = (quote_id: string, label: string, price: number | null, warranty: string, passed: boolean): Row => ({
  quote_id, label, price, lead_time: '3 weeks from LPO', warranty, vat_treatment: 'exclusive',
  completeness: { score: passed ? 90 : 60, passed, missing_mandatory: 0 },
});
// The four live quotes of the run, as the comparison saw them (ZZ DEMO suppliers; ids are the run's own).
const LIVE: Row[] = [
  row('b21fca55-a1e8-459c-bfe1-463353f8da1a', 'Supplier A', 69188, '2 years on the complete installation', true),
  row('72b94ebd-efcd-4b16-b713-6e4ced7d7ca8', 'Supplier B', 71966, '1 year on the complete installation', false),
  row('aa641de4-d85e-4e80-8f23-0a35994267e7', 'Supplier C', 94820, '5 years on compressors, 2 years on the complete installation', true),
  row('68248d81-dd95-4ea1-9d30-ed862f8d634f', 'Supplier D', 107099, '5 years on compressors, 2 years on the complete installation', true),
];
const TOP3 = [{ label: 'Supplier D', rank: 1 }, { label: 'Supplier C', rank: 2 }, { label: 'Supplier A', rank: 3 }];
const statusOf = (r: ReturnType<typeof rosterOf>, id: string) => r.find((x) => x.quote_id === id)?.status;

Deno.test('a quote the hold desk released is listed received, not held, whatever quotes.quality.pass says', () => {
  const r = rosterOf(LIVE, TOP3, new Set());
  assertEquals(statusOf(r, '72b94ebd-efcd-4b16-b713-6e4ced7d7ca8'), 'received');
  assertEquals(r.filter((x) => x.status === 'shortlisted').map((x) => x.label).sort(), ['Supplier A', 'Supplier C', 'Supplier D']);
  assertEquals(r.filter((x) => x.status === 'held').length, 0, 'on_hold was 0: the roster cannot hold what the desk does not');
});

Deno.test('the roster holds exactly what the evaluator holds, and a quote with no stated price', () => {
  const r = rosterOf(LIVE, TOP3.slice(0, 2), new Set(['b21fca55-a1e8-459c-bfe1-463353f8da1a']));
  assertEquals(statusOf(r, 'b21fca55-a1e8-459c-bfe1-463353f8da1a'), 'held');
  assertEquals(statusOf(r, '72b94ebd-efcd-4b16-b713-6e4ced7d7ca8'), 'received');
  const unpriced = rosterOf([{ ...LIVE[1], price: null }], [], new Set());
  assertEquals(unpriced[0].status, 'held', 'assessQuote never ranks a quote with no ex-VAT price either');
});

Deno.test('quote_compare hands the roster the same set it filtered the ranking with', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(/heldIds = held; heldAtRanking = held\.size;/.test(src), 'the held set is the one heldQuoteIds returned');
  assert(/rosterOf\([^\n]*, heldIds\);/.test(src), 'rosterOf is given heldIds');
  const det = await Deno.readTextFile(new URL('./deterministic.ts', import.meta.url));
  const fn = det.slice(det.indexOf('export function rosterOf'), det.indexOf('export function deterministicCompare'));
  assert(!/completeness\?\.passed/.test(fn), "rosterOf's status no longer reads quotes.quality.pass");
});
