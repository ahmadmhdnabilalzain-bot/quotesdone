// FOUNDER RULE C, 23 Sep 2026: "every change to company knowledge must reach EVERY place at once, with no
// mismatch anywhere." src/content/company_facts.json is the one source; this check fails when any repository
// surface states a figure differently, when a current legal document is missing a clause or a figure in one of
// its two languages, or when a public legal text carries a clause pattern UAE law voids (the researched
// denylist in the same file). Production is read by `node scripts/legal/sync_company_facts.mjs --probe`.
//
// MEASURED 23 Sep 2026 before this file existed: Supplier Agreement v12 clause 10 said AED 10,000 per incident as
// the "sole monetary remedy" while clause 24 said the greater of AED 15,000 or 3x the fee; production knowledge
// (kb_chunks trade mirrors of agent_knowledge) carried both figures; every non-supplier legal page said the
// ENGLISH text governs, including in its Arabic version.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { loadFacts, findings, statements, wrongWordings, denylisted, currentDocs, rewrite } from '../legal/company_facts.mjs';

const ROOT = new URL('../../', import.meta.url);
const root = ROOT.pathname.replace(/^\/([A-Za-z]:)/, '$1');
const F = loadFacts();
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
const legal = JSON.parse(read('src/content/legal.json'));

function walk(dir, out = []) {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (p.endsWith('.ts') && !/\.test\.ts$/.test(p)) out.push(relative(root, p).replace(/\\/g, '/'));
  }
  return out;
}

test('every repository surface states each company figure as company_facts.json does', () => {
  const bad = [];
  for (const k of currentDocs(legal)) for (const g of ['en', 'ar']) {
    for (const f of findings(legal[k][g].html)) bad.push(`legal.json ${k}/${g}: ${f.fact} says ${f.got}, source says ${f.want}: "${f.text}"`);
    for (const w of wrongWordings(legal[k][g].html)) bad.push(`legal.json ${k}/${g}: ${w.rule} worded "${w.text}"`);
  }
  const files = [...F.surfaces.repo.filter((p) => p !== 'src/content/legal.json'), ...walk(join(root, 'supabase/functions'))]
    .filter((p) => !F.surfaces.history.includes(p));
  // 24 SEP 2026 (ceo): SupplierPortal.tsx was excluded WHOLE as "history" for its AGREEMENT_CHANGES list (what each
  // past version changed), and that hid its live non-response rule, which still said AED 250, the card fee and 9%
  // a day after v13. Only the history block is history: the rest of the file is read like any other surface.
  const HISTORY_BLOCK = /const AGREEMENT_CHANGES = \{[\s\S]*?\nexport function agreementChanges/;
  files.push('src/components/portal/SupplierPortal.tsx');
  for (const p of files) {
    let t; try { t = read(p); } catch { continue; }
    if (p === 'src/components/portal/SupplierPortal.tsx') { assert.match(t, HISTORY_BLOCK, 'the history block moved: update HISTORY_BLOCK'); t = t.replace(HISTORY_BLOCK, ''); }
    for (const f of findings(t)) bad.push(`${p}: ${f.fact} says ${f.got}, source says ${f.want}: "${f.text}"`);
    for (const w of wrongWordings(t)) bad.push(`${p}: ${w.rule} worded "${w.text}"; the one wording is: ${w.say}`);
  }
  assert.deepEqual(bad, []);
});

test('each current legal document has the same clauses, and states the same figures, in English and Arabic', () => {
  const bad = [];
  const h2 = (h) => [...h.matchAll(/<h2>(\d+)\./g)].map((m) => m[1]).join(',');
  for (const k of currentDocs(legal)) {
    const en = legal[k].en.html, ar = legal[k].ar.html;
    if (h2(en) !== h2(ar)) bad.push(`${k}: clause numbers differ EN [${h2(en)}] vs AR [${h2(ar)}]`);
    for (const key of Object.keys(F.facts)) {
      const said = (t) => statements(t).some((x) => x.fact === key);
      if (said(en) !== said(ar)) bad.push(`${k}: ${key} is stated in ${said(en) ? 'English' : 'Arabic'} only`);
    }
    const doc = F.documents[k];
    if (doc) {
      if (!en.includes(`Version ${doc.version} ·`) || !ar.includes(`الإصدار ${doc.version} ·`)) bad.push(`${k}: not at version ${doc.version} in both languages`);
    }
    if (!/The Arabic (?:version|text)[^<]{0,40}prevails/.test(en) || !/النسخة العربية[^<]{0,20}هي المعتمدة/.test(ar)) bad.push(`${k}: does not say the Arabic text prevails in both languages`);
  }
  assert.deepEqual(bad, []);
});

test('no public legal text carries a clause pattern UAE law voids, or the word "AI"', () => {
  const bad = [];
  for (const k of currentDocs(legal)) for (const g of ['en', 'ar']) {
    for (const d of denylisted(legal[k][g].html)) bad.push(`${k}/${g}: ${d.id} "${d.text}" — ${d.why}`);
  }
  assert.deepEqual(bad, []);
});

test('the denylist and the drift reader actually fire (they are not vacuous)', () => {
  assert.ok(denylisted('<p>QuotesDone shall not be liable for fraud.</p>').some((d) => d.id === 'exclude_fraud_liability'));
  assert.ok(denylisted('<p>interest is compounded monthly</p>').some((d) => d.id === 'compound_interest'));
  assert.ok(denylisted('<p>The English version of this document is the governing version.</p>').some((d) => d.id === 'english_governs'));
  assert.ok(denylisted('<p>our AI tools</p>').some((d) => d.id === 'word_ai'));
  assert.equal(denylisted('<p>the UAE Federal Authority for Artificial Intelligence and Data</p>').length, 0);
  const stale = 'agreed compensation of AED 15,000 per incident, or three (3) times the fee that would otherwise have been payable';
  assert.deepEqual([...new Set(findings(stale).map((f) => f.fact))].sort(), ['circumvention_fee_multiple', 'circumvention_min_aed']);
  const fixed = rewrite(stale).text;
  assert.equal(findings(fixed).length, 0);
  assert.match(fixed, /AED 20,000 per incident, or five \(5\) times/);
  assert.equal(rewrite('أو ثلاثة (3) أضعاف الرسوم').text, 'أو خمسة (5) أضعاف الرسوم');
  assert.equal(findings('رسمًا إداريًا قدره 250 درهمًا').length, 1);
  assert.equal(findings('subscription fee of <b>AED 900 per year</b>').length, 1, 'a tag inside a statement hides it');
  assert.equal(wrongWordings('the charge is 3% + AED 250 + 9% a year').length, 1);
});

test('no marketing or profile surface carries what the source forbids there (the trade licence number)', () => {
  const bad = [];
  for (const p of F.marketing_surfaces.files) {
    const t = read(p);
    for (const f of F.marketing_surfaces.forbid) for (const m of t.matchAll(new RegExp(f.re, 'gu'))) bad.push(`${p}: "${m[0]}" — ${f.why}`);
  }
  assert.deepEqual(bad, []);
  assert.ok(new RegExp(F.marketing_surfaces.forbid[0].re, 'u').test('Trader License No. 1633275'), 'the licence rule is vacuous');
});

test('no buyer-facing wording adds a card fee (Cabinet Res. 66/2023 Art. 5(3)); the rule is not vacuous', () => {
  assert.equal(wrongWordings('You pay a 3% reveal fee, plus the card processing fee, on the quote').length > 0, true);
  assert.equal(wrongWordings('ادفع 3% من ذلك العرض مضافًا إليها رسوم معالجة البطاقة').length > 0, true);
  assert.equal(wrongWordings('With the Reveal Fee you also pay a card processing fee').length > 0, true);
  assert.equal(wrongWordings('You pay the 3% reveal fee and nothing more: no card fee is added').length, 0);
});

test('the Supplier Agreement module a supplier signs is the current legal.json text and version', () => {
  const mod = read('supabase/functions/_shared/supplier_agreement.ts');
  assert.match(mod, new RegExp(`SUPPLIER_AGREEMENT_VERSION = "${F.documents['supplier-agreement'].version}"`));
  assert.ok(mod.includes(JSON.stringify(legal['supplier-agreement'].en.html)), 'supplier_agreement.ts is stale: run scripts/legal/export_supplier_agreement.mjs');
});

test('every archived agreement version is still readable and linked', () => {
  const portal = read('src/components/portal/SupplierPortal.tsx');
  for (const k of F.surfaces.archived_documents) {
    const v = k.replace('supplier-agreement-', '');
    assert.ok(legal[k], `${k} is missing from legal.json`);
    assert.ok(read(`src/app/[locale]/supplier-agreement/${v}/page.tsx`).includes(`slug="${k}"`), `${k} has no page`);
    assert.match(portal, new RegExp(`ARCHIVED_AGREEMENTS = \\[[^\\]]*'${v}'`), `${v} is not in ARCHIVED_AGREEMENTS`);
  }
  const cur = Number(F.documents['supplier-agreement'].version.slice(1));
  assert.match(portal, new RegExp(`\\n  ${cur}: \\{`), `AGREEMENT_CHANGES has no entry for v${cur}`);
});

// 24 SEP 2026 (ceo, Supplier Agreement v14): the charge ARITHMETIC is a surface too. supplier_charge.ts states the
// rates as decimals (0.12) and the fees as bare numbers, which no prose pattern above reads, so a figure changed in
// company_facts.json could leave the invoice, the demand and the court claim charging the old one. Read them here.
export function chargeArithmeticFindings(src, facts = F.facts) {
  const num = (name) => { const m = src.match(new RegExp(`export const ${name} = ([0-9.]+);`)); return m ? Number(m[1]) : null; };
  const i = facts.late_interest_pct_pa, a = facts.nonresponse_admin_fee_aed, bad = [];
  const want = [['INTEREST_RATE_PA_FROM_V14', i.value / 100], ['INTEREST_RATE_PA', i.legacy.value / 100],
                ['ADMIN_FEE_AED_FROM_V13', a.value], ['ADMIN_FEE_AED', a.legacy.value]];
  for (const [k, v] of want) if (num(k) !== v) bad.push(`supplier_charge.ts ${k} = ${num(k)}, company_facts.json says ${v}`);
  return bad;
}
test('the clause 33 arithmetic charges the rates and fees company_facts.json states, per signed version', () => {
  assert.deepEqual(chargeArithmeticFindings(read('supabase/functions/_shared/supplier_charge.ts')), []);
  // the SQL that seeds the v14 rate agrees too (the generated sync file sets it again from the same source)
  const seed = read('scripts/sql/the_nonresponse_charge_is_the_maximum_uae_law_safely_allows.sql')
    .match(/'supplier_nonresponse_interest_apr_from_v14', to_jsonb\(([\d.]+)::numeric\)/);
  assert.equal(Number(seed?.[1]), F.facts.late_interest_pct_pa.value / 100, 'the v14 rate the SQL seeds is not the source\'s');
  // not vacuous: a stale rate is caught
  assert.equal(chargeArithmeticFindings('export const INTEREST_RATE_PA_FROM_V14 = 0.09;\nexport const INTEREST_RATE_PA = 0.09;\nexport const ADMIN_FEE_AED_FROM_V13 = 500;\nexport const ADMIN_FEE_AED = 250;').length, 1);
});

// 28 Sep 2026 (founder ruling, sales_engineer): a drawing is uploaded as PDF or CAD (DWG/DXF) only. The rule
// drawing_upload_formats is read by the repository test above and by sync_company_facts.mjs --probe (FAQ,
// knowledge rows); these prove it catches a surface that lists another format and spares the ones it must.
test('a surface that tells anyone to upload Revit, IFC or DGN is caught', () => {
  const caught = (s) => wrongWordings(s).some((w) => w.rule === 'drawing_upload_formats');
  for (const s of ['You can upload PDF, DWG, DXF, IFC or RVT files.', 'Please export it from Revit and upload the .ifc file.',
    'We accept MicroStation DGN drawings.', 'Send your Revit model and we read it.', 'يمكنك رفع ملفات PDF أو DWG أو IFC.', 'أرسل ملف ريفيت.'])
    assert.equal(caught(s), true, s);
  for (const s of ['Please upload your drawing as PDF or CAD (DWG/DXF).', 'يُرجى رفع المخطط بصيغة PDF أو CAD (DWG/DXF).',
    'Issued for Construction (IFC) drawings are the approved set the contractor builds from.'])
    assert.equal(caught(s), false, s);
});
