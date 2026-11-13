// identity_scrubbers_finish_on_adversarial_input.test.ts — every exported scrubber finishes, on input built to make a
// regex backtrack, within a HARD limit enforced from outside (13 Nov 2026, independent reviews of the anonymity fix round).
// Measured before the fixes: PHONE_WORDS_RE never finished on 104 digits; 1,000 spaces took 6.5-7.3 s in
// scrubIdentityText and 2,000 spaces more than 60 s (NOT_A_CODE's \s* look-behind); 50 KB of "Al-Al-…" 3.2 s to scrub
// and 19.3 s through the inbox gate (unbounded tokens). Each scrubber runs in a Worker that is terminated at the limit,
// so a hang fails the test in seconds instead of hanging the suite.
// deno test --no-lock --allow-read=. supabase/functions/_shared/identity_scrubbers_finish_on_adversarial_input.test.ts
import { assert } from 'jsr:@std/assert@1';

const digits = (n: number) => '0123456789'.repeat(Math.ceil(n / 10)).slice(0, n);
const line = 'Item 3: Supply and install emulsion, 2 coats on walls, 450 m2 @ AED 12.50 = 5,625.00. Warranty 2 years. Delivery to site in Dubai. ';
const INPUTS: [string, string][] = [
  ['200 digits', `Serial numbers: ${digits(200)} end`], ['5,000 digits', `Serial numbers: ${digits(5000)} end`], ['digit groups', '12 '.repeat(5000)],
  ['1,000 spaces', 'Al' + ' '.repeat(1000) + 'x'], ['5,000 spaces', 'a' + ' '.repeat(5000) + 'x 050'], ['tabs', 'Tel\t' + '\t'.repeat(3000) + '04'],
  ['no-break spaces', 'Villa' + ' '.repeat(3000) + '15'], ['leading indent', 'line one\n' + ' '.repeat(5000) + 'Tel 050 123 4567'], ['blank-only line', 'a\n' + ' '.repeat(5000) + '\n'],
  ['two-space columns', '  x'.repeat(3000)], ['mixed blanks', ('Office' + ' \t '.repeat(800) + '12, ').repeat(3)],
  ['50 KB Al Al', 'Al '.repeat(17000)], ['50 KB Al-Al-', 'Al-'.repeat(17000) + 'x'], ['50 KB Al Barsha', 'Al Barsha '.repeat(5000)], ['near Xyz, repeated', 'near Xyz, '.repeat(5000)],
  ['thousands of commas', '1,'.repeat(25000)], ['Villa 1, repeated', 'Villa 1, '.repeat(5500)], ['zero five repeated', 'zero five '.repeat(5000)],
  ['Title Case words', 'Main Distribution Board Tower '.repeat(1700)], ['a @ b.', 'a @ b.'.repeat(8000)],
  ['long Arabic', 'تركيب بلاط السيراميك في الحمام والمطبخ مع الضمان قرب '.repeat(1000)], ['Arabic place run', 'فيلا رقم ١ البرشاء '.repeat(2500)],
  ['200 KB BOQ', line.repeat(Math.ceil(200000 / line.length))],
];
const WHO = ['scrubIdentityText', 'identityShapesIn', 'reducePlaces', 'placeSpans', 'scrubAddresses', 'knownNameRe', 'redactText', 'residualScan', 'maskContacts', 'generaliseText',
  'scrubIdentity', 'scrubDeep', 'stripContact', 'stripSupplierQuestion', 'boqScrub', 'scrubModelText', 'inboxField'];
// 2 s for a text scrubber (the edge CPU cap is 2 s for a whole request; these inputs are far beyond a real field); 5 s
// for the inbox gate, the redactor and the residual scan, which paint seeds and residual-scan (drawing_boq's own e-mail pattern is the
// slowest step on "Al-Al-…", 2.3 s: its one-line bound belongs to the drawings branch). The 200 KB BOQ is not asked of them.
const limitOf = (who: string) => (['inboxField', 'redactText', 'residualScan', 'boqScrub'].includes(who) ? 5000 : 2000);
const url = new URL('./identity_scrubbers_adversarial.worker.ts', import.meta.url).href;
const start = () => new Promise<Worker>((res, rej) => {
  const w = new Worker(url, { type: 'module' });
  const t = setTimeout(() => { w.terminate(); rej(new Error('worker did not start in 60 s')); }, 60000);
  w.onmessage = (e) => { if (e.data?.ready) { clearTimeout(t); res(w); } };
});
const run = (w: Worker, who: string, input: string, limit: number) => new Promise<number | null>((res) => {
  const t = setTimeout(() => { w.terminate(); res(null); }, limit);
  w.onmessage = (e) => { clearTimeout(t); res(e.data.ms as number); };
  w.postMessage({ who, input });
});
Deno.test({ name: 'every exported scrubber finishes on every adversarial input within its limit (a hang is terminated)', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const slow: string[] = [];
  for (const who of WHO) {
    let w = await start();
    for (const [what, input] of INPUTS) {
      if (what === '200 KB BOQ' && limitOf(who) > 2000) continue;
      const ms = await run(w, who, input, limitOf(who));
      if (ms == null) { slow.push(`${who} on ${what}: terminated at ${limitOf(who)} ms`); w = await start(); }
    }
    w.terminate();
  }
  assert(!slow.length, slow.join('\n'));
} });
