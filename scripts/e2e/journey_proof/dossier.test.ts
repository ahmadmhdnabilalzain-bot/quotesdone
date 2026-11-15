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

// A persona played the journey (personas/report.mjs builds sections.people): the dossier says on page 1 and in its own
// section whether a real person would have got through, where they left, what was asked twice and each "not sure".
Deno.test('the dossier prints "Would a real person have got through?" with the abandonment, repeats and each "not sure"', async () => {
  const people = {
    title: 'Would a real person have got through?', mode: 'dry run', latency_source: 'replayed',
    persona: { key: 'impatient', label: 'ZZ DEMO impatient customer', short: 'wants a price now', lang: 'en', patience: { slow_s: 20, max_slow: 3, abandon_on_repeat: 1, max_questions: 6 }, knows: ['how many units'], does_not_know: ['the brand'], files: [] },
    headline: 'No. ZZ DEMO impatient customer left at turn 3: asked again what was already answered once (turn 3, first asked at turn 1).', got_through: false,
    abandoned: { at: 3, rule: 'repeat', reason: 'asked again what was already answered once (turn 3, first asked at turn 1)' }, outcome: 'abandoned',
    turns: [{ n: 1, question: 'Cooling capacity per unit', key: 'spec_cooling_capacity', latency_s: 10.8, repeat: false, understood: true, reply: '1.5 ton each' },
      { n: 2, question: 'Any preference for the brand?', key: 'material.brand', latency_s: 21.9, repeat: false, understood: true, reply: 'dont care, cheapest decent one' },
      { n: 3, question: 'Cooling capacity per unit', key: 'spec_cooling_capacity', latency_s: 28.3, repeat: true, understood: null, reply: '(left: asked again)' }],
    repeats: [{ n: 3, question: 'Cooling capacity per unit', first_asked_at: 1, why: 'same key' }], slowest: [{ n: 3, seconds: 28.3, question: 'Cooling capacity per unit' }],
    not_sure: [{ n: 2, topic: 'brand', question: 'Any preference for the brand?', said: 'dont care, cheapest decent one', platform_did: 'accepted it and moved on to: "Cooling capacity per unit"', recorded_as: 'Customer does not know: supplier to advise' }],
    misunderstood: [], files: [], problems: [], suppliers: [{ label: 'ZZ DEMO Quiet Air', behaviour: 'ignores the request', outcome: 'ignored the request', steps: ['never answered'] }],
    verdicts: [{ expected: 'a person like this reaches Send', happened: 'left at turn 3', as_expected: false }], spend: { calls: 2, usd: 0.0004, models: ['zz/stub'] },
  };
  const r = await buildDossier({ ...rec, sections: { ...rec.sections, people } }, '/nonexistent');
  assert(r.dropped === 0, 'dropped glyphs: ' + r.dropped);
  const text = linesFromRuns(await pdfPages(r.bytes)).replace(/\s+/g, ' ');
  for (const want of ['Would a real person have got through?', 'No. ZZ DEMO impatient customer left at turn 3', 'The person left at turn 3', 'Asked again what was already answered',
    'YES, again', 'The slowest replies', '28.3', 'what the platform did with each "not sure"', 'accepted it and moved on to', 'What it recorded',
    'The suppliers, played as people', 'ZZ DEMO Quiet Air', 'NOT as expected']) assert(text.includes(want), `missing: ${want}`);
  assert(!/\bpassed\b/i.test(text), 'the dossier never says "passed"');
});
