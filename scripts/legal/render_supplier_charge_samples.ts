// Renders the clause 33 recovery pack for the ZZ DEMO case with the brand fonts, signature and stamp.
// deno run --no-lock --allow-net --allow-write scripts/legal/render_supplier_charge_samples.ts <outDir>
// Reads only the public brand bucket; writes PDFs and their input JSON to <outDir>. Touches no row.
import { recoveryPack } from '../../supabase/functions/_shared/supplier_charge_documents.ts';
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
for (const p of recoveryPack(DEMO_CASE)) {
  const r = await renderPdf(p.body, { fetchBytes });
  const file = `${out}/${p.name}_${p.lang}`;
  if (!r.ok) { bad++; console.error('REFUSED', file, JSON.stringify(r.body)); continue; }
  await Deno.writeFile(file + '.pdf', r.bytes);
  await Deno.writeTextFile(file + '.json', JSON.stringify(p.body, null, 2));
  console.log(`${file}.pdf  pages=${r.meta.pages} fonts=${JSON.stringify(r.meta.fonts)} dropped=${r.meta.glyphs_dropped}`);
}
if (bad) Deno.exit(1);
