// NO BADGE IS AN EXACT FINGERPRINT BEFORE THE REVEAL (sales_engineer, 19 Nov 2026; founder ruling 1683: anonymity is the most important
// thing on the platform). customer_api my_inquiries sent every unrevealed quote the supplier's exact jobs_won (as jobs_won AND as
// badges.jobs_completed) and its exact match_pct, beside a comment saying no badge may be one. FAILS if a band stops banding, or if
// the my_inquiries quote row sends any of the three exactly before a transaction exists for that quote.
//   deno test --no-lock --node-modules-dir=none -A supabase/functions/customer_api/no_badge_is_an_exact_fingerprint_before_the_reveal.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { jobsBand, matchBand } from '../_shared/pre_reveal_bands.ts';

Deno.test('jobs: 1-5, 6-20, 20+; none is null, never "0"', () => {
  assertEquals([0, null, undefined, -3, 'x'].map(jobsBand), [null, null, null, null, null]);
  assertEquals([1, 5, 6, 14, 20, 21, 400].map(jobsBand), ['1-5', '1-5', '6-20', '6-20', '6-20', '20+', '20+']);
});

Deno.test('match: high from 80, medium from 50, low below; absent is null', () => {
  assertEquals([null, undefined, '', 'x'].map(matchBand), [null, null, null, null]);
  assertEquals([100, 80, 79, 50, 49, 0].map(matchBand), ['high', 'high', 'medium', 'medium', 'low', 'low']);
});

Deno.test('my_inquiries sends jobs and match as bands until the quote is revealed', async () => {
  // Read as text: lib/pricing.ts and the action import context.ts, which builds a Supabase client at load.
  const pricing = await Deno.readTextFile(new URL('./lib/pricing.ts', import.meta.url));
  assert(/export \{[^}]*\bjobsBand\b[^}]*\bmatchBand\b[^}]*\} from '\.\.\/\.\.\/_shared\/pre_reveal_bands\.ts'/.test(pricing), 'pricing.ts no longer re-exports the bands');
  const src = await Deno.readTextFile(new URL('./actions/inquiry_lifecycle.ts', import.meta.url));
  assert(src.includes("import { getCfg, jobsBand, matchBand, ratingBand,"), 'the action no longer imports the bands');
  const row = src.slice(src.indexOf('quotes: quotes.filter((q) => q.inquiry_id === i.id)'), src.indexOf('EACH mapRow AWAITS'));
  assert(row.length > 1000, 'the my_inquiries quote row was not found');
  assert(row.includes('jobs_won: revealed ? (m.jobs_won ?? 0) : jobsBand(m.jobs_won),'), 'jobs_won is exact before the reveal');
  assert(row.includes('jobs_completed: Number(m.jobs_won) > 0 ? (revealed ? Number(m.jobs_won) : jobsBand(m.jobs_won)) : null,'),
    'badges.jobs_completed is exact before the reveal');
  assert(row.includes("match_pct: revealed ? (pctBySup[String(i.id) + ':' + String(q.supplier_id)] ?? null) : undefined,"),
    'match_pct is exact before the reveal');
  assert(row.includes("match_band: matchBand(pctBySup[String(i.id) + ':' + String(q.supplier_id)]),"), 'the match band is missing');
  // Every other exact track-record figure on the row stays gated the same way (the 27 Jul 2026 rule).
  for (const k of ['rating: revealed ?', 'rating_count: revealed ?', 'years_active: revealed ?', 'win_rate: revealed ?', 'emirate: revealed ?']) {
    assert(row.includes(k), `${k} is no longer gated on the reveal`);
  }
  assert(!/jobs_won: m\.jobs_won \?\? 0,/.test(row), 'the exact jobs_won is back');
});
