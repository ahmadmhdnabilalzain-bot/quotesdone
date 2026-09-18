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
//   pdf with text layer  priced lines read here by code (rows_from_text.ts, 15 Sep 2026)
//   pdf / png / jpg      otherwise read by ai_gateway's vision path; while every model route is on
//                        hold that answer is 'unread_llm_hold' — never 'no_products_found', which
//                        would tell the supplier a file nobody read lists nothing
//   dwg / dxf / ifc / rvt  converted to PDF by cad_convert (CloudConvert) first, then read
//
// A drawing is geometry. Converting it and reading the title block and schedule tables is honest;
// claiming to derive a product catalogue from a 3D model is not, so the CAD route extracts what a
// human would read off the sheet and says that is what it did.
//
// Anything else is stored and marked `unsupported_format` with the reason. It is never silently
// treated as empty, because "we extracted 0 products" and "we cannot read this file" look identical
// to a supplier and mean completely different things.
//
// ── 9 SEP 2026: THIS WAS THE ONE UPLOAD SITE OF FOURTEEN WITH NO VALIDATION ─────────────────────
// Measured, not asserted. Before this change the function:
//   * atob()'d the request body straight into .upload() — no shape check of any kind;
//   * chose the extraction route from the FILENAME EXTENSION, so `bomb.zip` renamed `prices.xlsx`
//     took the sheet route and `payload.svg` renamed `sheet.png` was announced to the model as an
//     image, because readableMime was literally `image/${ext}`;
//   * applied NO size limit anywhere;
//   * handed the ZIP container to XLSX.read() with no entry-count, decompressed-size or ratio cap
//     — a zip bomb, reachable by any registered supplier with one POST;
//   * discarded the upload result (`.catch(() => null)`, and `up.error` never read). .upload()
//     RESOLVES with `{ error }` rather than rejecting, so that .catch() could never fire. The
//     supplier-docs bucket allows only PDF/JPEG/PNG/WebP, so every CSV and XLSX upload was rejected
//     by storage and supplier_catalog.source_document_path was written pointing at an object that
//     does not exist — silently, every time.
// The format now comes from the BYTES via _shared/attachment.ts, the same module the other thirteen
// sites use; the archive is costed before it is expanded; and a refused upload fails loudly.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeUpload, zipExpansionWithinLimits, SAFE_SHEET, SAFE_DOCUMENT, SAFE_IMAGE, SAFE_CAD } from '../_shared/attachment.ts';
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { readDocument, type DocumentRead } from '../_shared/doc_read/index.ts';
import { proposeTradesFromDocs } from '../_shared/supplier_doc_trades.ts';
import { productsFromText } from './rows_from_text.ts';
import { SANCTIONED_REFUSAL, sanctionedEmail } from '../_shared/sanctioned.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;

// THE ROUTE IS CHOSEN BY THE SNIFFED MIME, NEVER BY THE FILENAME. Everything this function accepts
// is a type _shared/attachment.ts can identify from magic bytes, which is what makes the choice
// trustworthy. 25 MB matches the supplier-docs bucket; a catalogue larger than that is a
// conversation, not an upload.
const ACCEPT = [...SAFE_SHEET, ...SAFE_DOCUMENT, ...SAFE_IMAGE, ...SAFE_CAD] as const;
const MAX_UPLOAD_BYTES = 25 * 1024 * 1024;
const TEXTUAL = ['text/csv'];
const SHEET = ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/vnd.ms-excel'];
const VISUAL = ['application/pdf', 'image/png', 'image/jpeg', 'image/webp'];
const CAD = ['image/vnd.dwg', 'image/vnd.dxf'];
// IFC and RVT are gone from the accepted set, and that is a NARROWING, not an oversight. Neither can
// be identified by shape here — an .rvt is an OLE2 compound document, byte-identical in its header
// to a legacy .xls, so accepting it on trust would mean handing an unidentified binary to SheetJS on
// the strength of its filename, which is the exact defect this change removes. supplier_catalog and
// supplier_product are both 0 rows, so no catalogue loses a route it ever used. Restore them by
// giving sniff() a real signature for each, never by trusting the extension again.

// The zip caps, and why these numbers. A genuine supplier price list is a few hundred KB of XML plus
// a logo: SheetJS's own test corpus tops out around 40 entries, and a workbook with images still
// sits far under 200. 512 entries and 64 MB leave a wide margin over anything legitimate while
// putting a hard ceiling on the work XLSX.read() can be made to do; 120:1 is roughly four times the
// ratio ordinary XML-plus-images compresses at, and far below the ~1000:1 a bomb needs to be worth
// building. A file that trips any of the three is refused with its own reason, so a big honest
// catalogue and a hostile one do not look alike in the log.
const ZIP_CAPS = { maxEntries: 512, maxTotalBytes: 64 * 1024 * 1024, maxRatio: 120 };

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

Deno.serve(observe('supplier_catalog_ingest', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    // A SANCTIONED PARTY CANNOT ACT (founder instruction 516, 18 Sep 2026; security review the
    // same day found this function authenticated a supplier by leads.claimed_by and asked
    // nothing about the ban). Above everything this function does, so it covers what is written
    // here next year too.
    if (await sanctionedEmail(admin, user.email.toLowerCase())) return J(SANCTIONED_REFUSAL, 403);
    const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', user.email.toLowerCase()).maybeSingle();
    if (!sup) return J({ error: 'no_company', hint: 'claim your company first' }, 400);
    const supId = sup.id as number;

    const b = await req.json().catch(() => ({} as Record<string, unknown>));
    const fileName = String(b.file_name || '').slice(0, 200);
    const dataB64 = String(b.data || '');
    if (!fileName || !dataB64) return J({ error: 'file_name and data required' }, 400);

    // THE GATE. Shape, size and safety are decided here, before a byte is stored or parsed, by the
    // same module the other thirteen upload sites use. It refuses executables, HTML, SVG and script
    // by CONTENT whatever the file was named, and it strips EXIF/GPS from photographed price lists.
    // MALWARE WATCH, 9 Sep 2026. This is the ONE path that accepts a spreadsheet, which is the file
    // type a macro actually travels in — looksMacroEnabled() in attachment.ts now refuses a workbook
    // carrying a VBA project, and the hash lookup here refuses a file VirusTotal already knows.
    const sc = await sanitizeAndScan({ input: dataB64, declaredMime: String(b.content_type || ''), filename: fileName, allow: ACCEPT, maxBytes: MAX_UPLOAD_BYTES,
                                       scan: { source: 'supplier_catalog_ingest', subject: String(supId), filename: fileName, bucket: 'supplier-docs' } });
    if (!sc.ok) return J({ ok: false, ...sc.body, file_name: fileName }, sc.status);
    const san = sc.result;
    const kind = san.mime;
    const bytes = san.bytes;

    // The catalogue row exists BEFORE extraction, so an upload that later fails to parse is still a
    // file the supplier can see we hold, with a status explaining what happened to it. It must NOT
    // exist before the upload, though: a row whose source_document_path names an object storage
    // refused is a lie the supplier cannot see and nothing downstream can detect.
    const path = `catalog/${supId}/${Date.now()}-${fileName.replace(/[^\w.\-]/g, '_')}`;
    const up = await admin.storage.from('supplier-docs').upload(path, bytes, { contentType: san.mime, upsert: true });
    if (up.error) {
      return J({ ok: false, error: 'storage_refused', detail: String(up.error.message || up.error).slice(0, 200),
                 hint: 'the file was accepted but could not be stored; no catalogue row was created', file_name: fileName }, 502);
    }
    const { data: cat } = await admin.from('supplier_catalog')
      .insert({ supplier_id: supId, source_document_path: path, version: 1, status: 'ingesting' })
      .select('id').maybeSingle();
    const catalogId = cat?.id ?? null;

    // The same file is also read for the TRADES it names, into the supplier's proposal on "What your
    // company can quote for" (_shared/supplier_doc_trades.ts). A PDF already read below is reused.
    let docRead: DocumentRead | undefined;
    const readTrades = () => proposeTradesFromDocs(admin, supId, [{ path, name: fileName, kind: 'catalogue', bytes, mime: san.mime, read: docRead }]);

    const fail = async (status: string, why: string) => {
      if (catalogId) await admin.from('supplier_catalog').update({ status }).eq('id', catalogId);
      return J({ ok: true, catalog_id: catalogId, products_created: 0, status, why, documents_read: await readTrades() });
    };

    let products: Record<string, unknown>[] = [];
    let note = '';

    if (TEXTUAL.includes(kind)) {
      products = rowsToProducts(parseDelimited(new TextDecoder().decode(bytes)));
      note = `parsed ${kind} directly — a price list is a table and needs no model`;
    } else if (SHEET.includes(kind)) {
      // COST THE ARCHIVE BEFORE EXPANDING IT. XLSX.read() is synchronous and CPU-bound: nothing in
      // JavaScript can abort it once it starts, so the only place a limit can work is here, reading
      // the declared uncompressed sizes out of the zip's central directory without inflating a byte.
      if (kind === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
        const z = zipExpansionWithinLimits(bytes, ZIP_CAPS);
        if (!z.ok) return await fail('refused_archive', `${z.error}: ${z.detail}`);
      }
      const XLSX = await import('https://esm.sh/xlsx@0.18.5');
      const wb = XLSX.read(bytes, { type: 'array' });
      const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { defval: '' }) as Record<string, unknown>[];
      products = rowsToProducts(rows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [String(k).toLowerCase(), v]))));
      note = `parsed sheet "${wb.SheetNames[0]}"`;
    } else if (VISUAL.includes(kind) || CAD.includes(kind)) {
      // readableMime was `image/${ext}` — the FILENAME decided what was announced to the model, so
      // `x.svg` renamed `x.png` was presented as a PNG. It is now the sniffed type, which is the
      // only one that reflects the bytes actually being sent.
      let readable = bytes; let readableMime = kind;
      if (CAD.includes(kind)) {
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
      // CODE FIRST. A PDF with a text layer is read here; a line that prints a price is a product.
      if (readableMime === 'application/pdf') {
        docRead = await readDocument(readable, fileName, 'application/pdf', 0, { textOnly: true });
        if (docRead.ok && docRead.text.trim()) {
          products = productsFromText(docRead.text);
          if (products.length) note = [note, `read the PDF text layer by code: ${products.length} priced line(s), no model`].filter(Boolean).join('; ');
        }
      }
      if (!products.length) {
        const textRead = !!(docRead?.ok && docRead.text.trim());
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
        // A REFUSAL IS NOT AN EMPTY CATALOGUE (15 Sep 2026). Under the hold ai_gateway answers
        // {ok:false, outcome:'circuit_open'} or {used_llm:false}; `r.content` is then absent, the parse
        // below saw '{}', and the catalogue was recorded 'no_products_found' — "we read it and it lists
        // nothing" about a file nobody read.
        if (!r || r.ok === false || r.used_llm === false || typeof r.content !== 'string' || !r.content.trim()) {
          return await fail('unread_llm_hold', `${textRead ? 'the text layer was read by code and prints no priced product lines; ' : ''}reading this file needs the model, which did not answer (${String(r?.outcome || r?.error || 'no response').slice(0, 80)}). The file is stored and has not been read.`);
        }
        try {
          const parsed = JSON.parse(String(r.content).match(/\{[\s\S]*\}/)?.[0] || '{}');
          products = Array.isArray(parsed.products) ? parsed.products : [];
          note = [note, parsed.note].filter(Boolean).join('; ');
        } catch { return await fail('extraction_failed', 'the extractor did not return readable structure'); }
      }
    } else {
      // Defensive, and no longer the way an unreadable file is rejected: sanitizeUpload refuses an
      // unaccepted type above, before anything is stored. This fires only if ACCEPT and the four
      // route lists ever drift apart, and says so rather than reporting an empty catalogue.
      return await fail('unsupported_format', `${kind} is accepted by the upload gate but no extraction route claims it — ACCEPT and the route lists have drifted.`);
    }

    // WRITE THE STRUCTURED STORE. external_key makes a re-upload of the same catalogue update rather
    // than duplicate — (supplier_id, external_key) is unique, which is the constraint that makes
    // this idempotent instead of merely repeatable.
    let created = 0;
    for (const p of products.slice(0, 500)) {
      const name = String(p.name || '').trim();
      if (!name) continue;
      // san.ext, not san.mime: external_key keeps the short `xlsx:`/`csv:` prefix it always had, so
      // a re-upload of the same catalogue still collides with its own earlier rows and updates them.
      const key = `${san.ext}:${(String(p.model || p.name)).slice(0, 80)}`.toLowerCase();
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
      documents_read: await readTrades(),
    });
  } catch (e) {
    return J({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
}));
