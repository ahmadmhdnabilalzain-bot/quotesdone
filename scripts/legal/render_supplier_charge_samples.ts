// Renders the clause 33 recovery pack for the ZZ DEMO case with the brand fonts, signature and stamp.
// deno run --no-lock --allow-net --allow-write scripts/legal/render_supplier_charge_samples.ts <outDir>
// Reads only the public brand bucket; writes PDFs and their input JSON to <outDir>. Touches no row.
import { recoveryPack, signingRecord } from '../../supabase/functions/_shared/supplier_charge_documents.ts';
import { DEMO_CASE } from '../../supabase/functions/_shared/supplier_charge.fixture.ts';
import { renderPdf } from '../../supabase/functions/pdf_native/render.ts';

const BRAND = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/';
const cache = new Map<string, Uint8Array | null>();
async function fetchBytes(p: string) {
  if (!cache.has(p)) { try { const r = await fetch(BRAND + p); cache.set(p, r.ok ? new Uint8Array(await r.arrayBuffer()) : null); } catch { cache.set(p, null); } }
  return cache.get(p)!;
}
const out = Deno.args[0] ?? 'pdf-samples/legal';
await Deno.mkdir(out, { recursive: true });
let bad = 0;
const ledger = [];
for (const p of recoveryPack(DEMO_CASE)) {
  const r = await renderPdf(p.body, { fetchBytes });
  const file = `${out}/${p.name}_${p.lang}`;
  if (!r.ok) { bad++; console.error('REFUSED', file, JSON.stringify(r.body)); continue; }
  await Deno.writeFile(file + '.pdf', r.bytes);
  await Deno.writeTextFile(file + '.json', JSON.stringify(p.body, null, 2));
  const rec = await signingRecord(DEMO_CASE, p, r.bytes, r.meta.pages, { signature: await fetchBytes('qd_signature.png'), stamp: await fetchBytes('qd_stamp.png') });
  if (rec) ledger.push(rec);
  console.log(`${file}.pdf  pages=${r.meta.pages} fonts=${JSON.stringify(r.meta.fonts)} dropped=${r.meta.glyphs_dropped}${rec ? ' signed ' + rec.pdf_sha256.slice(0, 12) : ''}`);
}
// What went out under the founder's signature: one record per signed PDF (supplier_charge_documents signingRecord).
await Deno.writeTextFile(`${out}/signing_records.json`, JSON.stringify(ledger, null, 2));
if (bad) Deno.exit(1);
