// Every identity number the site prints is one company.json holds AND one whose source document is on file;
// the numbers the licence does not give as a register number are printed nowhere.
//   node --test scripts/checks/identity_numbers_come_from_the_licence.test.mjs
//
// 14 Sep 2026, agent: website. "Commercial Register No. 2883503" was printed on every legal page, the footer
// and the company card. The DET trade licence prints no Commercial Register number: it prints Trader License
// No. 1633275, the trade name, the dates, the activities and a members table in which 2063672 is the owner's
// member number. 2883503 entered company.json on 14 Sep 2026 with no source. The founder: take the number from
// the licence. So the company is identified by its Trader License only, and a number with no source on file
// cannot be printed again unnoticed.
//
// The source notes live in docs/legal/company_identity_sources.json, NOT in company.json: company.json is
// customer copy, and customer_copy_names_no_vendor.test.mjs (rightly) refuses a storage vendor's name there,
// which a file path to the licence would contain. This check is the only reader of the sources file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(ROOT, p), 'utf8');
const C = JSON.parse(read('src/content/company.json'));
const SRC = JSON.parse(read('docs/legal/company_identity_sources.json'));
const walk = (d) => readdirSync(join(ROOT, d)).flatMap((n) => { const p = join(d, n); return statSync(join(ROOT, p)).isDirectory() ? walk(p) : [p]; });

// Everything a visitor, a supplier, a bot answer or an invoice footer can show.
function surfaces() {
  const out = [];
  const legal = JSON.parse(read('src/content/legal.json'));
  for (const [k, d] of Object.entries(legal)) {
    if (k === 'supplier-agreement-v10') continue; // the archived text a supplier accepted: a record, not a claim
    for (const lang of ['en', 'ar']) if (d[lang]) out.push([`legal.json ${k}.${lang}`, d[lang].html]);
  }
  for (const f of ['src/content/company.json', 'src/content/marketing.json', 'messages/en.json', 'messages/ar.json', 'src/lib/seo.ts',
    'supabase/functions/site_assistant/index.ts', 'supabase/functions/wa_inbound/index.ts', 'supabase/functions/supplier_pay/index.ts',
    'supabase/functions/_shared/brand_assets/letterhead.html', 'supabase/functions/_shared/supplier_agreement.ts']) out.push([f, read(f)]);
  for (const f of walk('src/components').filter((p) => /\.tsx?$/.test(p))) out.push([relative(ROOT, join(ROOT, f)).replace(/\\/g, '/'), read(f)]);
  return out;
}

test('every identity number company.json holds has a source entry naming its document; there is no register number', () => {
  assert.equal(C.register_no, undefined, 'a register number the licence does not print');
  assert.equal(C.register, undefined);
  assert.equal(C.sources, undefined, 'source notes belong in docs/legal/company_identity_sources.json, not customer copy');
  assert.match(C.licence_no, /^\d{7}$/);
  for (const k of ['licence_no', 'licence_issued', 'licence_expiry', 'tdra_nol_no']) {
    assert.equal(SRC[k]?.value, C[k], `${k}: company.json and its source entry disagree`);
    assert.ok(String(SRC[k]?.source || '').length > 20, `${k}: no source document named`);
  }
  assert.match(SRC.licence_no.source, /639183403868888392\.pdf/, 'licence_no must cite the licence file');
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

test('every licence or permit number printed next to its label has a source entry', () => {
  const allowed = new Set([SRC.licence_no.value, SRC.tdra_nol_no.value, SRC.tdra_nol_no.value.replace(/^NOL-\d{2}-/, '')]);
  // A phone number is not an identity number: a run preceded by "+" or a digit is skipped, and the
  // licence_phone key (the licence's own contact line) is not a licence label.
  const label = /(?:licen[cs]e(?!_phone)|License|رخصة|ترخيص|register|السجل|\bNOL\b|\bCR\b|permit|identifier)[^<\n]{0,60}?(?<![+\d])\b((?:NOL-\d{2}-)?\d{6,})\b/gi;
  const bad = [];
  for (const [name, s] of surfaces()) for (const m of s.matchAll(label)) if (!allowed.has(m[1])) bad.push(`${name}: ${m[0].slice(0, 90)}`);
  assert.deepEqual(bad, []);
});
