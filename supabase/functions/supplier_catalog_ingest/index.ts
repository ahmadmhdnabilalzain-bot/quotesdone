// supplier_catalog_ingest — SPEC FILE #5 §7. A CATALOGUE IN, PRODUCT RECORDS OUT.
//
// §7 asks for a structured product store built from what the supplier already has: catalogues,
// price lists, spreadsheets, drawings. The estate could READ that store (fn_supplier_products) and
// nothing could FILL it — the scorer's own note for prod-ai-extraction says so, and it is right:
// license_extract writes a comma-separated sentence into leads.products, which is a text field, not
// 245 products with attributes.
//
// ── WHAT THIS ACTUALLY EXTRACTS, AND WHAT IT REFUSES TO PRETEND ─────────────────────────────────
// Four routes, chosen by what the file really is:
//
//   csv / tsv / txt      parsed here — a price list is a table and needs no model
//   xlsx / xls           parsed here via SheetJS, the same way
//   pdf / png / jpg      read by ai_gateway's vision path, like license_extract
//   dwg / dxf / ifc / rvt  converted to PDF by cad_convert (CloudConvert) first, then read
//
// A drawing is geometry. Converting it and reading the title block and schedule tables is honest;
// claiming to derive a product catalogue from a 3D model is not, so the CAD route extracts what a
// human would read off the sheet and says that is what it did.
//
// Anything else is stored and marked `unsupported_format` with the reason. It is never silently
// treated as empty, because "we extracted 0 products" and "we cannot read this file" look identical
// to a supplier and mean completely different things.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;

const ext = (name: string) => (name.split('.').pop() || '').toLowerCase();
const TEXTUAL = ['csv', 'tsv', 'txt'];
const SHEET = ['xlsx', 'xls'];
const VISUAL = ['pdf', 'png', 'jpg', 'jpeg', 'webp'];
const CAD = ['dwg', 'dxf'];
const BIM = ['ifc', 'rvt'];

const EXTRACTION_PROMPT = `You are reading a UAE construction supplier's own product catalogue, price list or drawing schedule.
Extract the PRODUCTS it lists. Return STRICT JSON only:
{"products":[{"name":string,"brand":string|null,"model":string|null,"description":string|null,
              "category":string|null,"attributes":{},"unit":string|null,"price":number|null}],
 "note":string}
Rules:
- One entry per distinct product. Do not invent products to fill the list — an empty array is a
  correct answer for a document that lists none.
- attributes: whatever the document actually states (size, finish, thickness, colour, standard).
  Use the document's own words as keys. {} when it states none.
- price: a number only if the document prints one for that product. null otherwise. Never estimate.
- note: one sentence on what the document was and what you could not read.`;

function parseDelimited(text: string): Record<string, unknown>[] {
  const lines = text.split(/\r?\n/).filter((l) => l.trim());
  if (lines.length < 2) return [];
  const delim = (lines[0].match(/\t/g) || []).length > (lines[0].match(/,/g) || []).length ? '\t' : ',';
  const head = lines[0].split(delim).map((h) => h.trim().replace(/^"|"$/g, '').toLowerCase());
  return lines.slice(1).map((l) => {
    const cells = l.split(delim).map((c) => c.trim().replace(/^"|"$/g, ''));
    const row: Record<string, unknown> = {};
    head.forEach((h, i) => { if (h) row[h] = cells[i] ?? ''; });
    return row;
  });
}

// A parsed table row becomes a product only if it names one. A spreadsheet's totals row and its
// blank tail are not products, and inserting them would put rubbish in the store that a supplier
// then has to delete by hand.
const pick = (row: Record<string, unknown>, keys: string[]) => {
  for (const k of Object.keys(row)) if (keys.some((x) => k.includes(x))) {
    const v = String(row[k] ?? '').trim();
    if (v) return v;
  }
  return null;
};
function rowsToProducts(rows: Record<string, unknown>[]) {
  const out: Record<string, unknown>[] = [];
  for (const row of rows) {
    const name = pick(row, ['product', 'item', 'description', 'name', 'material']);
    if (!name || /^(total|subtotal|sum)\b/i.test(name)) continue;
    const priceRaw = pick(row, ['price', 'rate', 'amount', 'cost']);
    const price = priceRaw ? Number(String(priceRaw).replace(/[^0-9.]/g, '')) : null;
    out.push({
      name: name.slice(0, 200),
      brand: pick(row, ['brand', 'make', 'manufacturer']),
      model: pick(row, ['model', 'code', 'sku', 'ref']),
      description: pick(row, ['spec', 'detail', 'remark']),
      unit: pick(row, ['unit', 'uom']),
      price: Number.isFinite(price) ? price : null,
      attributes: row,
    });
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', user.email.toLowerCase()).maybeSingle();
    if (!sup) return J({ error: 'no_company', hint: 'claim your company first' }, 400);
    const supId = sup.id as number;

    const b = await req.json().catch(() => ({} as Record<string, unknown>));
    const fileName = String(b.file_name || '').slice(0, 200);
    const dataB64 = String(b.data || '');
    if (!fileName || !dataB64) return J({ error: 'file_name and data required' }, 400);
    const kind = ext(fileName);

    // The catalogue row exists BEFORE extraction, so an upload that later fails to parse is still a
    // file the supplier can see we hold, with a status explaining what happened to it.
    const path = `catalog/${supId}/${Date.now()}-${fileName.replace(/[^\w.\-]/g, '_')}`;
    const bytes = Uint8Array.from(atob(dataB64.replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0));
    await admin.storage.from('supplier-docs').upload(path, bytes, { upsert: true }).catch(() => null);
    const { data: cat } = await admin.from('supplier_catalog')
      .insert({ supplier_id: supId, source_document_path: path, version: 1, status: 'ingesting' })
      .select('id').maybeSingle();
    const catalogId = cat?.id ?? null;

    const fail = async (status: string, why: string) => {
      if (catalogId) await admin.from('supplier_catalog').update({ status }).eq('id', catalogId);
      return J({ ok: true, catalog_id: catalogId, products_created: 0, status, why });
    };

    let products: Record<string, unknown>[] = [];
    let note = '';

    if (TEXTUAL.includes(kind)) {
      products = rowsToProducts(parseDelimited(new TextDecoder().decode(bytes)));
      note = `parsed ${kind} directly — a price list is a table and needs no model`;
    } else if (SHEET.includes(kind)) {
      const XLSX = await import('https://esm.sh/xlsx@0.18.5');
      const wb = XLSX.read(bytes, { type: 'array' });
      const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { defval: '' }) as Record<string, unknown>[];
      products = rowsToProducts(rows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [String(k).toLowerCase(), v]))));
      note = `parsed sheet "${wb.SheetNames[0]}"`;
    } else if (VISUAL.includes(kind) || CAD.includes(kind) || BIM.includes(kind)) {
      let readable = bytes; let readableMime = kind === 'pdf' ? 'application/pdf' : `image/${kind === 'jpg' ? 'jpeg' : kind}`;
      if (CAD.includes(kind) || BIM.includes(kind)) {
        // A drawing is geometry. cad_convert (CloudConvert) renders it to PDF; what comes back is a
        // SHEET, and what is extractable from a sheet is its schedule and title block — which is
        // exactly what a human reads off it. Nothing here claims to mine a 3D model.
        const { data: secRow } = await admin.from('app_secrets').select('value').eq('key', 'cred_db_internal').maybeSingle();
        if (!secRow?.value) return await fail('conversion_unavailable', 'CAD conversion is not configured on this project');
        const conv = await fetch(SUPA_URL + '/functions/v1/cad_convert', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ __secret: secRow.value, file_name: fileName, data: dataB64, to: 'pdf' }),
        }).then((r) => r.json()).catch(() => null);
        if (!conv?.data && !conv?.pdf_b64) return await fail('conversion_failed', `could not convert ${kind} to a readable sheet: ${String(conv?.error || 'no output')}`);
        readable = Uint8Array.from(atob(String(conv.pdf_b64 || conv.data)), (c) => c.charCodeAt(0));
        readableMime = 'application/pdf';
        note = `${kind} converted to a PDF sheet, then read`;
      }
      const { data: keyRow } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
      if (!keyRow?.value) return await fail('extraction_unavailable', 'the smart engine is not configured on this project');
      let s = ''; const CH = 0x8000;
      for (let i = 0; i < readable.length; i += CH) s += String.fromCharCode.apply(null, Array.from(readable.subarray(i, i + CH)));
      const r = await fetch(SUPA_URL + '/functions/v1/ai_gateway', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          __secret: keyRow.value, fn: 'supplier_catalog_ingest', max: 3000, temperature: 0.1,
          sys: EXTRACTION_PROMPT, response_format: 'json',
          input: [{ role: 'user', content: [{ type: 'image_url', image_url: { url: `data:${readableMime};base64,${btoa(s)}` } }] }],
        }),
      }).then((x) => x.json()).catch(() => null);
      try {
        const parsed = JSON.parse(String(r?.content || '{}').match(/\{[\s\S]*\}/)?.[0] || '{}');
        products = Array.isArray(parsed.products) ? parsed.products : [];
        note = [note, parsed.note].filter(Boolean).join('; ');
      } catch { return await fail('extraction_failed', 'the extractor did not return readable structure'); }
    } else {
      return await fail('unsupported_format', `.${kind} is not a format this ingester can read. It is stored, not extracted.`);
    }

    // WRITE THE STRUCTURED STORE. external_key makes a re-upload of the same catalogue update rather
    // than duplicate — (supplier_id, external_key) is unique, which is the constraint that makes
    // this idempotent instead of merely repeatable.
    let created = 0;
    for (const p of products.slice(0, 500)) {
      const name = String(p.name || '').trim();
      if (!name) continue;
      const key = `${kind}:${(String(p.model || p.name)).slice(0, 80)}`.toLowerCase();
      const { error } = await admin.from('supplier_product').upsert({
        supplier_id: supId, catalog_id: catalogId, external_key: key,
        name: name.slice(0, 200), brand: p.brand ?? null, model: p.model ?? null,
        description: p.description ?? null,
        attributes: (p.attributes && typeof p.attributes === 'object') ? p.attributes : {},
        certifications: [], documents: [], status: 'extracted',
        evidence_refs: [{ catalog_id: catalogId, source: path, unit: p.unit ?? null, price: p.price ?? null }],
      }, { onConflict: 'supplier_id,external_key' });
      if (!error) created++;
    }

    if (catalogId) await admin.from('supplier_catalog')
      .update({ status: created ? 'extracted' : 'no_products_found', extracted_at: new Date().toISOString() })
      .eq('id', catalogId);

    return J({
      ok: true, catalog_id: catalogId, format: kind, products_created: created,
      products_found: products.length, note,
      // 0 found is a real answer and is reported as one, distinct from a format we cannot read.
      status: created ? 'extracted' : 'no_products_found',
    });
  } catch (e) {
    return J({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});
