// THE QUOTATION REVIEW STAYS INSIDE THE EDGE CPU CAP (22 Sep 2026). Assigned: sales_engineer.
//
// MEASURED on production, 21-22 Sep 2026: supplier_api answered 546 WORKER_RESOURCE_LIMIT ("CPU Time
// exceeded") three times in one hour of the portal walk, and a ZZ DEMO probe with a 120-line BOQ got 546
// on review_start and review_upload. The cause was _shared/service_rewrite.ts compiling all 1,672 service
// aliases on every servicesFromText call; boqWithArabic calls it twice per BOQ line for every inquiry the
// inbox serves, and every review action reads its job through the inbox. Locally: boqWithArabic 1,447 ms
// for 120 lines (925 ms for 3 lines, cold) before; ~50 ms after.
//
// This file replays that input: the whole seed vocabulary (service_aliases.json, the same 211 services
// production reads) and a 150-line BOQ through everything a review action runs in-process — the inbox's
// BOQ gate and Arabic reading, reading the quotation file, the review, and a typed reply. It fails if the
// index is rebuilt per call again, if every alias's RegExp is built up front again, or if the whole path
// exceeds a budget far below the platform's 2 s CPU cap.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import aliases from '../_shared/service_aliases.json' with { type: 'json' };
import { compileServices, servicesFromText, type ServiceTerm } from '../_shared/service_rewrite.ts';
import { boqWithArabic } from '../_shared/boq_arabic.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { inboxBoq } from './identity_scrub.ts';
import { readQuotationFile } from './quote_review_flow.ts';
import { replyFrom, replyPoints, reviewQuotation, workingFromProposal, type SafeInquiry } from './quote_review.ts';

const vocab = (): ServiceTerm[] => Object.entries(aliases as Record<string, { en: string[]; ar: string[] }>).map(([key, a]) => {
  const [trade_code, code] = key.split('.');
  return { trade_code, code, label_en: code, label_ar: code, aliases: [...a.en, ...a.ar] };
});
const LINES = 150;
const BASE: [string, string, number, string][] = [
  ['Partitions', 'Gypsum board partition, 100mm metal stud, both faces', 320, 'm2'],
  ['Ceilings', 'Suspended false ceiling, 600x600 mineral fibre tiles', 410, 'm2'],
  ['Ceilings', 'Gypsum bulkhead, 300mm drop, painted finish', 64, 'm'],
];
const rows = Array.from({ length: LINES }, (_, k) => { const b = BASE[k % 3]; return { section: b[0], description: `${b[1]}, zone ${k + 1}`, qty: b[2], unit: b[3] }; });
const csv = 'No,Description,Qty,Unit,Rate AED,Amount AED,Specification\n'
  + rows.map((r, k) => `${k + 1},"${r.description}",${r.qty},${r.unit},95.00,${(95 * r.qty).toFixed(2)},"12.5mm Knauf board"`).join('\n')
  + '\n,Validity 30 days. Prices exclude VAT. Installation included 4 weeks. Warranty 2 years parts and labour.,,,,,\n';

/** Budget for the whole in-process path. Measured ~250 ms on a developer machine after the fix; the
 *  per-call rebuild it prevents cost several seconds at this size. The platform cap is 2 s of CPU. */
const BUDGET_MS = 1200;

Deno.test('the alias index is built once per vocabulary, and only the aliases a phrase can match get a RegExp', () => {
  const v = vocab();
  const idx = compileServices(v);
  assert(idx.length > 1000, `the seed should carry the full vocabulary, got ${idx.length} aliases`);
  assert(compileServices(v) === idx, 'a second call with the same vocabulary must reuse the index');
  servicesFromText('Suspended false ceiling, 600x600 mineral fibre tiles', v);
  const built = idx.filter((c) => c.re).length;
  assert(built < idx.length / 10, `${built} of ${idx.length} RegExps were built for one phrase; they must be built only when the phrase holds the alias's first word`);
  assert(servicesFromText('Suspended false ceiling', v).includes('gypsum.false_ceiling'), 'the lazy index still matches');
});

Deno.test(`a ${LINES}-line quotation review runs well inside the edge CPU cap`, async () => {
  const v = vocab();   // a fresh array, as every request reads the vocabulary afresh
  const t0 = performance.now();
  const seeds = seedTerms({ name: 'ZZ DEMO Customer', email: 'c@example.invalid', phone: '+971500000001', project: 'ZZ DEMO Villa' });
  const gated = inboxBoq({ boq: rows }, 'ZZ DEMO Customer', seeds, []);
  const boq = boqWithArabic(gated.boq ?? { boq: rows }, v);
  const inq: SafeInquiry = { id: '00000000-0000-4000-8000-000000000001', job_no: 'ZZ1', category: 'gypsum', emirate: 'Dubai', spec: null,
    boq_rows: (boq as { boq: typeof rows }).boq, boq_withheld: false, concluded: false, revealed: false };
  const read = await readQuotationFile(new TextEncoder().encode(csv), 'ZZDEMO_quotation.csv', 'text/csv', ['ZZ DEMO Supplier']);
  assert(read.proposal, 'the fixture quotation is readable');
  assertEquals(read.proposal.line_items.filter((l) => l.amount != null).length, LINES);
  const rv = reviewQuotation(inq, workingFromProposal(read.proposal, read.text));
  replyPoints(rv.issues); replyFrom({ boq_2_amount: { value: 'AED 27,880', evidence: 'AED 27,880' } }, rv.issues);   // the reply's own work; its meaning is reasoned elsewhere
  const ms = performance.now() - t0;
  assert(ms < BUDGET_MS, `the review path took ${ms.toFixed(0)} ms for ${LINES} lines (budget ${BUDGET_MS} ms; the edge CPU cap is 2 s)`);
});
