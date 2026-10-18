// Renders the clause 33 recovery pack for the ZZ DEMO case with the brand fonts, signature and stamp.
// SUPABASE_SERVICE_ROLE_KEY=... deno run --no-lock --allow-net --allow-write --allow-env scripts/legal/render_supplier_charge_samples.ts <outDir>
// Reads fonts from the public brand bucket and the stamp and signature from the PRIVATE company-seal
// bucket through a 60-second signed URL (moved there 6 Oct 2026; without the key the signed documents
// are refused, which is the point). Writes PDFs and their input JSON to <outDir>. Touches no row.
import { recoveryPack, signingRecord } from '../../supabase/functions/_shared/supplier_charge_documents.ts';
import { DEMO_CASE } from '../../supabase/functions/_shared/supplier_charge.fixture.ts';
import { renderPdf } from '../../supabase/functions/pdf_native/render.ts';

const STORAGE = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1';
const BRAND = STORAGE + '/object/public/brand/';
const SEAL = new Set(['qd_stamp.png', 'qd_signature.png']);
async function sealUrl(p: string): Promise<string | null> {
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'); if (!key) return null;
  const r = await fetch(`${STORAGE}/object/sign/company-seal/${p}`, { method: 'POST', headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ expiresIn: 60 }), signal: AbortSignal.timeout(15_000) });
  const j = r.ok ? await r.json() : null; return j?.signedURL ? STORAGE + j.signedURL : null;
}
const cache = new Map<string, Uint8Array | null>();
async function fetchBytes(p: string) {
  if (!cache.has(p)) { try { const u = SEAL.has(p) ? await sealUrl(p) : BRAND + p; if (!u) { cache.set(p, null); return null; } const r = await fetch(u); cache.set(p, r.ok ? new Uint8Array(await r.arrayBuffer()) : null); } catch { cache.set(p, null); } }
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
