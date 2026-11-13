// The journey dossier renders on the QuotesDone template, prints every section, a LEAK in plain words, the holes the
// platform leaves ("does not produce this", "nobody in the company was told") and drops no character. Offline.
import { assert } from 'jsr:@std/assert@1';
import { buildDossier } from './dossier.ts';
import { pdfPages, linesFromRuns } from '../../../supabase/functions/_shared/pdf_text_positions.ts';

const T = '2026-11-13T06:00:00.000Z';
const rec = {
  journey: { key: 'A', title: 'ZZ DEMO villa AC', short: 'an inquiry made only by chat', how_made: 'typed only', site: 'https://quotesdone.com', started: T, finished: T, mode: 'stubbed', cap_usd: 1, estimate_usd: 0.5, run_tag: 'zztest01' },
  steps: [{ id: 's2', title: 's2', start: T, end: '2026-11-13T06:10:00.000Z' }],
  sections: {
    s1: { customer: { name: 'ZZ DEMO Buyer', email: 'qd-x@example.invalid' }, verdicts: [{ expected: 'a certificate is stored', happened: 'stored', as_expected: true }], gaps: [] },
    s2: { turns: [{ role: 'customer', text: 'Villa 15, Al Barsha 2', at: T }], verdicts: [], gaps: ['A copy of this chat as a document.'] },
    s3: { anonymity: { rows: [{ label: 'the villa number', value: 'Villa 15', leak: true, hits: [{ where: 'the inquiry PDF (its text)', snippet: '... Villa 15 ...' }] }], checked: ['the inquiry PDF (its text)'], not_checked: [], too_short_to_check: [] }, verdicts: [], gaps: [] },
    s8: { vat: { ex_vat: 'AED 100.00', base: 'AED 105.00', fee: 'AED 3.15', base_is_ex_vat: false, why: 'The fee was calculated on AED 105.00, but the total excluding VAT is AED 100.00.' }, verdicts: [], gaps: [] },
    co: { events: [], after_payment: [{ title: 'Who in the company heard about the sale', nobody: 'Nobody in the company was told about this sale.' }], by_step: { s2: [] }, verdicts: [], gaps: [] },
  },
  findings: [{ severity: 'harness', step: '-', text: 'h' }, { severity: 'leak', step: '3', text: 'the villa number reached the supplier' }],
  cost: { by_step: [{ step: 's2', title: 's2', calls: 2, usd: 0.012, fns: { inquiry_intake: 2 } }], total_usd: 0.012, calls: 2 },
  stand_ins: ['ZZ DEMO stand-in'], exhibits: [],
};

Deno.test('the dossier prints every section, the leak, the holes and the wrong VAT base, on the template', async () => {
  const r = await buildDossier(rec, '/nonexistent');
  assert(r.report_pages >= 3 && r.dropped === 0, JSON.stringify({ pages: r.report_pages, dropped: r.dropped }));
  const raw = new TextDecoder('latin1').decode(r.bytes);
  assert(raw.includes('/EmbeddedFile'), 'the raw record is attached');
  const text = linesFromRuns(await pdfPages(r.bytes)).replace(/\s+/g, ' ');
  for (const want of ['QuotesDone Technologies', '1633275', 'The customer exists', 'The inquiry as it was shared with the suppliers', 'Who was asked, and were they the right suppliers',
    'Inside the company: who knew, and what they did', 'What went wrong, what it cost', 'LEAK: the villa number', 'The platform does not produce this',
    'Nobody in the company was told', 'WRONG BASE', 'Anonymity leak', 'USD 0.0120']) assert(text.includes(want), `missing: ${want}`);
  assert(!/\bpassed\b/i.test(text), 'the dossier never says "passed"');
});
