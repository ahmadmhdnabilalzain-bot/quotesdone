// Renders all 14 supplier-charge recovery documents (EN + AR) with the brand fonts and fails when any
// text overlaps other text, or any page after the first is more than 70% empty (unless it is the last
// page of a document of three pages or more).
//   deno run --no-lock --node-modules-dir=auto --allow-net=htdblwldjkcgjvmqkbeh.supabase.co scripts/legal/check_legal_pdf_layout.ts
// Reads only the public brand bucket. Missing brand fonts FAIL the check (exit 1): without them the
// Arabic pages render empty and a pass would assert nothing.
import { recoveryPack } from '../../supabase/functions/_shared/supplier_charge_documents.ts';
import { DEMO_CASE } from '../../supabase/functions/_shared/supplier_charge.fixture.ts';
import { renderPdf } from '../../supabase/functions/pdf_native/render.ts';
import { overlapsIn, pageFill, sparsePages } from './pdf_layout.ts';

const BRAND = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/';
const cache = new Map<string, Uint8Array | null>();
async function fetchBytes(p: string) {
  if (!cache.has(p)) { try { const r = await fetch(BRAND + p); cache.set(p, r.ok ? new Uint8Array(await r.arrayBuffer()) : null); } catch { cache.set(p, null); } }
  return cache.get(p)!;
}
const bad: string[] = [];
let n = 0;
for (const doc of recoveryPack(DEMO_CASE)) {
  const name = `${doc.name}_${doc.lang}`;
  const r = await renderPdf(doc.body, { fetchBytes });
  if (!r.ok) { bad.push(`${name}: renderer refused ${JSON.stringify(r.body)}`); continue; }
  if (!r.meta.fonts.latin || (doc.lang === 'ar' && !r.meta.fonts.arabic)) { bad.push(`${name}: brand fonts not embedded (${JSON.stringify(r.meta.fonts)})`); continue; }
  const ov = await overlapsIn(r.bytes), fill = await pageFill(r.bytes);
  for (const o of ov) bad.push(`${name} p${o.page}: "${o.a}" × "${o.b}" overlap ${o.w}×${o.h}pt`);
  for (const s of sparsePages(fill)) bad.push(`${name} p${s.page}: ${Math.round(s.empty * 100)}% empty`);
  console.log(`${bad.length ? '' : ''}${name.padEnd(40)} pages=${fill.length} fill=${fill.join(' ')} overlaps=${ov.length}`);
  n++;
}
if (n !== 14 && !bad.length) bad.push(`expected 14 documents, checked ${n}`);
if (bad.length) { console.error('LAYOUT FAULTS:\n' + bad.join('\n')); Deno.exit(1); }
console.log('14/14: no overlapping text, no mostly-empty page');
