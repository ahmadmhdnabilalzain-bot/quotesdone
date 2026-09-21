// arabic_documents.test.ts — the Arabic quotation and comparison a customer downloads are Arabic.
// deno test --no-lock --node-modules-dir=auto --allow-read supabase/functions/customer_api/arabic_documents.test.ts
//
// MEASURED 21 Sep 2026 (customer-portal journey audit): the customer on the Arabic portal downloaded
// an English document. The document builder was already Arabic (quote_documents.test.ts); the English
// came from the two paths that CHOOSE which document is served:
//   1. compare_pdf / compare_csv / brief_pdf read customers.locale and ignored the lang the portal's
//      button sends, so an English-registered customer pressing the Arabic report got English.
//      (quote_pdf had the same defect and was fixed alone, finding 4.)
//   2. quote_pdf's cache served any stored file younger than the quote. 14 Arabic rows in
//      quote_pdf_cache, the first from 14 Sep, were rendered before the Arabic fixes of #782/#790/#794
//      and kept being served after them.
// Each test below fails if its cause comes back. The render uses the COMMITTED brand fonts
// (pdf_native/fixtures/brand, the same files as storage brand/), so "0 glyphs dropped" is proved with
// the real Arabic font and no network — never skipped because a fetch fell back to Helvetica.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { quoteDocument, compareDocument, supplierLabel, docName, isCurrentDoc, DOC_VERSION } from '../_shared/quote_documents.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { latinLeaks } from '../_shared/trade_glossary_ar.test.ts';
import { deterministicCompare, rosterOf } from '../quote_compare/deterministic.ts';
import * as F from '../_shared/quote_documents.fixture.ts';

const BRAND = new URL('../pdf_native/fixtures/brand/', import.meta.url);
const fetchBytes = async (p: string) => /\.ttf$/.test(p) ? await Deno.readFile(new URL(p, BRAND)) : null;

// A fixed label is what the page itself names (column heads, row labels, keys, section titles).
const cellStr = (c: unknown) => typeof c === 'string' ? c : (c && typeof c === 'object' && 'text' in c) ? String((c as { text: unknown }).text ?? '') : '';
// deno-lint-ignore no-explicit-any
function fixedLabels(body: any): string[] {
  const out: string[] = [String(body.title ?? '')];
  for (const m of body.cover?.meta || []) out.push(cellStr(m[0]));
  for (const f of body.cover?.figures || []) out.push(cellStr(f[0]));
  for (const b of body.blocks || []) {
    if (b.t === 'table') { out.push(...(b.head || []).map(cellStr)); for (const r of b.rows || []) out.push(cellStr(r[0])); }
    else if (b.t === 'kv') for (const p of b.pairs || []) out.push(cellStr(p[0]));
    else if (b.t === 'terms') for (const c of b.cells || []) out.push(cellStr(c[0]));
    else if (b.t === 'checks') for (const c of b.items || []) out.push(cellStr(c[0]));
    else if (b.t === 'section' || b.t === 'h3' || b.t === 'callout') out.push(cellStr(b.title ?? b.text));
    if (b.label) out.push(cellStr(b.label));
  }
  return out.filter(Boolean);
}
// Every string the page draws as PRIMARY text: everything except the supplier's original-wording line.
const SKIP = new Set(['sub', 'link', 't', 'tone', 'flag', 'lang', 'name', 'ref', 'align', 'options', 'widths', 'zebra', 'n', 'muted', 'bold', 'group', 'cols', 'chip_kind']);
function primary(v: unknown, key = ''): string[] {
  if (SKIP.has(key)) return [];
  if (typeof v === 'string') return /^(match|differs|missing|optional|na|short|open|hold)$/.test(v) ? [] : [v];
  if (Array.isArray(v)) return v.flatMap((x) => primary(x));
  if (v && typeof v === 'object') return Object.entries(v).flatMap(([k, x]) => primary(x, k));
  return [];
}
function subs(v: unknown, out: string[] = []): string[] {
  if (Array.isArray(v)) v.forEach((x) => subs(x, out));
  else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) { if (k === 'sub' && typeof x === 'string') out.push(x); else subs(x, out); }
  return out;
}
// deno-lint-ignore no-explicit-any
async function assertArabicDocument(body: any) {
  assertEquals(body.lang, 'ar');
  const labels = fixedLabels(body).flatMap((s) => latinLeaks(s).map((w) => `${w}  ←  ${s}`));
  assertEquals(labels, [], 'an English UI label on the Arabic page');
  const leaks = primary({ cover: body.cover, blocks: body.blocks, control: body.control, title: body.title }).flatMap((s) => latinLeaks(s).map((w) => `${w}  ←  ${s.slice(0, 90)}`));
  assertEquals(leaks, [], 'English left in the Arabic primary text');
  const out = await renderPdf(body, { fetchBytes });
  assert(out.ok, 'renderer refused: ' + JSON.stringify(!out.ok && out.body));
  if (!out.ok) return;
  assert(out.meta.fonts.arabic, 'the Arabic brand font was not embedded');
  assertEquals(out.meta.glyphs_dropped, 0, 'characters dropped: ' + JSON.stringify(out.meta.glyphs_dropped_sample));
}

const dates = { date_ar: '21 سبتمبر 2026' };

Deno.test('the Arabic ZZ DEMO quotation is Arabic, keeps the supplier\'s own words as authored, renders with 0 glyphs dropped', async () => {
  // A note the trade glossary cannot finish: it must reach the page exactly as the supplier wrote it.
  const q = { ...F.liveQuotes()[0], notes: 'Site survey by appointment on Tuesday mornings; parking permit arranged by the tenant.' };
  const body = quoteDocument({ quote: q, inquiry: F.INQUIRY, items: q.items, letter: supplierLabel(0), lang: 'ar', maskNames: F.identities(), ...dates }).body;
  await assertArabicDocument(body);
  // Supplier free text is never machine-translated: what the glossary cannot finish is printed as the
  // supplier wrote it, on the secondary line that says so.
  const s = subs(body.blocks);
  assert(s.length > 0, 'the supplier\'s original wording is not on the page');
  for (const x of s) assert(x.startsWith('النص الأصلي من المورد'), 'an unlabelled secondary line: ' + x);
  assert(s.some((x) => /[A-Za-z]/.test(x)), 'the supplier\'s English wording was not kept as authored');
});

Deno.test('the Arabic ZZ DEMO comparison report is Arabic and renders with 0 glyphs dropped', async () => {
  const lab = F.labelled();
  // deno-lint-ignore no-explicit-any
  const a: any = deterministicCompare(lab, 'ar');
  a.all_quotes = rosterOf(lab, a.top3); a.total_quotes = lab.length; a.technical = F.HVAC_TECHNICAL;
  const body = compareDocument({ analysis: a, inquiry: F.INQUIRY, lang: 'ar', maskNames: F.identities(), ...dates }).body;
  await assertArabicDocument(body);
});

// CAUSE 1: the button's language is the document served. Every document action in customer_api must
// resolve its language through documentLocale(body.lang, …); reading the registered locale alone is
// how the Arabic button produced English.
Deno.test('every customer document action serves the language the portal button asked for', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  for (const action of ['quote_pdf', 'compare_pdf', 'compare_csv', 'brief_pdf']) {
    const at = src.indexOf(`action === '${action}'`);
    assert(at > 0, `customer_api no longer has the ${action} action — update this test with it`);
    const block = src.slice(at, at + 2500);
    const decl = block.match(/const lang\b[^;]*;/)?.[0] ?? '';
    assert(/documentLocale\(body\.lang,/.test(decl), `${action} does not serve the requested language: ${decl || '(no lang)'}`);
  }
});

// CAUSE 2: a cached document from an older layout is never served.
Deno.test('a cached quotation rendered by an older layout is not served; the vault trigger still recognises the name', async () => {
  const name = docName('QD-1234-A', 'quotation', 'ar');
  const path = `2026-09-21/1789983012525_${name}.pdf`;
  assert(isCurrentDoc(path));
  assert(!isCurrentDoc('2026-09-14/1789000000000_QD-1234-A-quotation-ar.pdf'), 'a pre-version file counts as current');
  assert(!isCurrentDoc(path.replace(DOC_VERSION, 'v2.0')), 'a v2.0 file counts as current');
  // trg_quote_pdf_cache_register matches '-quotation-<lang>\.pdf$' to replace a quote's earlier vault entry.
  assert(/-quotation-ar\.pdf$/.test(path), 'the vault trigger no longer matches the stored name');
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const at = src.indexOf(`action === 'quote_pdf'`);
  assert(/if \(cached && isCurrentDoc\(cached\.path\)/.test(src.slice(at, at + 3500)), 'quote_pdf serves a cached file without checking its layout version');
});
