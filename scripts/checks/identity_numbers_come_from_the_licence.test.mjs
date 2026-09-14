// Every identity number the site prints is one company.json holds, with a source note naming the document
// it was read from; and the two numbers the licence does NOT give as a register number are printed nowhere.
//   node --test scripts/checks/identity_numbers_come_from_the_licence.test.mjs
//
// 14 Sep 2026, agent: website. "Commercial Register No. 2883503" was printed on every legal page, the footer
// and the company card. The DET trade licence (Dropbox/QuotesDone Backup/Assets/639183403868888392.pdf) prints
// no Commercial Register number: it prints Trader License No. 1633275, the trade name, the dates, the
// activities and a members table in which 2063672 is the owner's member number. 2883503 entered company.json
// on 14 Sep 2026 with no source. The founder: take the number from the licence. So the company is identified
// by its Trader License only, and a number with no source on file cannot be printed again unnoticed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const C = JSON.parse(read('src/content/company.json'));
const walk = (d) => readdirSync(join(ROOT, d)).flatMap((n) => { const p = join(d, n); return statSync(join(ROOT, p)).isDirectory() ? walk(p) : [p]; });

// Everything a visitor, a supplier, a bot answer or an invoice footer can show.
function surfaces() {
  const out = [];
  const legal = JSON.parse(read('src/content/legal.json'));
  for (const [k, d] of Object.entries(legal)) {
    if (k === 'supplier-agreement-v10') continue; // the archived text a supplier accepted: a record, not a claim
    for (const lang of ['en', 'ar']) if (d[lang]) out.push([`legal.json ${k}.${lang}`, d[lang].html]);
  }
  // company.json's sources notes name documents (a file path, the member number the licence does NOT give as a
  // register number); they are never printed, so the printed values are scanned without them.
  out.push(['src/content/company.json (printed values)', JSON.stringify({ ...C, sources: undefined })]);
  for (const f of ['src/content/marketing.json', 'messages/en.json', 'messages/ar.json', 'src/lib/seo.ts',
    'supabase/functions/site_assistant/index.ts', 'supabase/functions/wa_inbound/index.ts', 'supabase/functions/supplier_pay/index.ts',
    'supabase/functions/_shared/brand_assets/letterhead.html', 'supabase/functions/_shared/supplier_agreement.ts']) out.push([f, read(f)]);
  for (const f of walk('src/components').filter((p) => /\.tsx?$/.test(p))) out.push([relative(ROOT, join(ROOT, f)).replace(/\\/g, '/'), read(f)]);
  return out;
}
// supplier_agreement.ts is generated from legal.json and carries only the live version.

test('company.json names a source for every identity number it holds, and holds no register number', () => {
  assert.equal(C.register_no, undefined, 'a register number the licence does not print');
  assert.equal(C.register, undefined);
  assert.match(C.licence_no, /^\d{7}$/);
  assert.match(C.sources?.licence_no || '', /639183403868888392\.pdf/, 'licence_no must cite the licence file');
  assert.ok(C.sources?.tdra_nol_no, 'tdra_nol_no must cite its document');
  assert.match(C.licence.en, /Trader License/); assert.match(C.licence.ar, /رخصة تاجر/);
});

test('no page prints the register number, the member number, or the old licence title', () => {
  const bad = [];
  for (const [name, s] of surfaces()) {
    for (const re of [/2883503/, /2063672/, /E-Trader/, /تاجر إلكتروني/, /التاجر الإلكتروني/, /Commercial Register No\./, /السجل التجاري رقم \d/]) {
      const m = s.match(new RegExp('.{0,50}' + re.source + '.{0,30}'));
      if (m) bad.push(`${name}: ${m[0]}`);
    }
  }
  assert.deepEqual(bad, []);
});

test('every licence or permit number printed next to its label is one company.json holds', () => {
  const allowed = new Set([C.licence_no, C.tdra_nol_no, C.tdra_nol_no.replace(/^NOL-\d{2}-/, '')]);
  // A phone number is not an identity number: a run preceded by "+" or a digit is skipped, and the
  // licence_phone key (the licence's own contact line) is not a licence label.
  const label = /(?:licen[cs]e(?!_phone)|License|رخصة|ترخيص|register|السجل|\bNOL\b|\bCR\b|permit|identifier)[^<\n]{0,60}?(?<![+\d])\b((?:NOL-\d{2}-)?\d{6,})\b/gi;
  const bad = [];
  for (const [name, s] of surfaces()) for (const m of s.matchAll(label)) if (!allowed.has(m[1])) bad.push(`${name}: ${m[0].slice(0, 90)}`);
  assert.deepEqual(bad, []);
});
