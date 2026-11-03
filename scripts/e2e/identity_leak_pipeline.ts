// identity_leak_pipeline.ts — every artefact one side of the marketplace sees of the other before the reveal,
// produced by the REAL modules from a planted-identity corpus (sales_engineer, 3 Nov 2026; qualification matrix
// gap #3, rows E05 / E07 / F04.04). Driven by scripts/e2e/identity_never_leaks_before_reveal.mjs, which writes the
// corpus and its rasters, runs this, then OCRs and grades what this wrote. Nothing here is graded: it only produces
// what a supplier or a customer would be handed, exactly as the deployed functions compute it.
//
//   deno run -A scripts/e2e/identity_leak_pipeline.ts <run dir>
//
// WHAT EACH SURFACE IS, AND THE PRODUCTION LINE IT MIRRORS (customer_api / supplier_api / messages_api call sites):
//   drawing PDF  -> page previews: pdfPages + titleBlockBoxes + supplierBoxes + serverBoxedPage (customer_api
//                   analyze_drawing 1128-1177, drawing_redact manual path). Any page refused -> the whole drawing is
//                   held (drawing_hold.drawingHandoff). Then the vector PDF: anonymisedDrawingFile (redactFile, 1182).
//                -> the BOQ a supplier reads: boqFromPages, then supplier_api's inbox gate inboxBoq.
//   drawing DXF  -> cadPage (drawing_redact mode 'cad', redactCad) and the anonymised DXF (mode 'file').
//   quotation    -> readDocument + quoteFromExtracted (quote_extract's code-first path), the supplier's submission
//                   scrubbed as submit_quote does (scrubIdentity per field, scrubLine per line), the stored fields the
//                   customer's portal serves, the quotation PDF (quoteDocument + renderPdf), and per request the
//                   comparison PDF (compareDocument) and CSV (compareTable + toCsv).
//   Q&A          -> messages_api stripContact (clarify_ask / clarify_answer), both directions.
//
// The scanned-PDF drawing goes through the same deterministic gate: the server finds no text layer, sends no boxes,
// and in production drawing_redact's MODEL path then decides the page. That path is not run here (it needs the live
// gateway); this file records such a drawing as `model_path` so the driver can send it to the deployed function.
import { pdfPages } from '../../supabase/functions/_shared/pdf_text_positions.ts';
import { seedTerms, titleBlockBoxes } from '../../supabase/functions/_shared/anonymise.ts';
import { supplierBoxes } from '../../supabase/functions/_shared/supplier_copy.ts';
import { cadPage, serverBoxedPage } from '../../supabase/functions/_shared/drawing_redact_page.ts';
import { anonymisedDrawingFile } from '../../supabase/functions/_shared/drawing_file_redact.ts';
import { boqFromPages } from '../../supabase/functions/drawing_boq/boq_from_text.ts';
import { inboxBoq, scrubIdentity, scrubLine } from '../../supabase/functions/supplier_api/identity_scrub.ts';
import { readDocument } from '../../supabase/functions/_shared/doc_read/index.ts';
import { quoteFromExtracted } from '../../supabase/functions/quote_extract/quote_from_document.ts';
import { compareDocument, compareTable, quoteDocument, supplierLabel, toCsv } from '../../supabase/functions/_shared/quote_documents.ts';
import { deterministicCompare, rosterOf } from '../../supabase/functions/quote_compare/deterministic.ts';
import { renderPdf } from '../../supabase/functions/pdf_native/render.ts';
import { stripContact } from '../../supabase/functions/messages_api/strip_contact.ts';

const dir = Deno.args[0];
if (!dir) throw new Error('usage: identity_leak_pipeline.ts <run dir>');
const man = JSON.parse(await Deno.readTextFile(`${dir}/manifest.json`));
const write = async (p: string, d: Uint8Array | string) => { await Deno.mkdir(p.replace(/[\\/][^\\/]*$/, ''), { recursive: true }); typeof d === 'string' ? await Deno.writeTextFile(p, d) : await Deno.writeFile(p, d); };
const read = (p: string) => Deno.readFile(`${dir}/${p}`);
// deno-lint-ignore no-explicit-any
const result: any = { drawings: [], quotes: [], requests: [], qa: [] };
const clip = (v: unknown, n: number) => String(v ?? '').slice(0, n);

// ── drawings ──────────────────────────────────────────────────────────────────────────────────────────
for (const d of man.drawings) {
  const out = `${dir}/out/${d.id}`;
  const seeds = seedTerms({ name: d.customer.name, email: d.customer.email, phone: d.customer.phone, extra: [d.filename] });
  const bytes = await read(d.file);
  // deno-lint-ignore no-explicit-any
  const r: any = { id: d.id, kind: d.kind, surfaces: [], held: [] };
  try {
    if (d.kind === 'dxf') {
      const cp = await cadPage(bytes, seeds);
      if (cp.ok) { await write(`${out}/cad_p0.jpg`, cp.jpg); r.surfaces.push({ kind: 'image', path: `out/${d.id}/cad_p0.jpg` }); } else r.held.push('cad_page:' + cp.skipped);
      const f = await anonymisedDrawingFile(bytes, seeds);
      if (f.ok) { await write(`${out}/file.${f.ext}`, f.bytes); r.surfaces.push({ kind: f.ext === 'pdf' ? 'pdf' : 'text_file', path: `out/${d.id}/file.${f.ext}`, name: `redacted/<uuid>_drawing.${f.ext}` }); } else r.held.push('file:' + f.held);
    } else {
      const pp = await pdfPages(bytes, undefined, { layers: false });
      const words = pp.reduce((n, pg) => n + pg.runs.length, 0);
      const tb = titleBlockBoxes(pp, seeds);
      const sb = supplierBoxes(tb, null, d.rasters.length);
      if (!sb) { r.held.push(words === 0 ? 'model_path:no_text_layer' : 'server_boxes_null:' + (tb.residual[0] || tb.confidence)); r.model_path = words === 0 || undefined; }
      else {
        const pages: Uint8Array[] = [];
        for (let i = 0; i < d.rasters.length; i++) {
          const pg = await serverBoxedPage(await read(d.rasters[i]), pp, i, sb[i]);
          if (!pg.ok) { r.held.push(`page_${i}:${pg.skipped}`); break; }
          pages.push(pg.jpg);
        }
        if (pages.length === d.rasters.length) {
          for (let i = 0; i < pages.length; i++) { await write(`${out}/preview_p${i}.jpg`, pages[i]); r.surfaces.push({ kind: 'image', path: `out/${d.id}/preview_p${i}.jpg`, page: i }); }
          const f = await anonymisedDrawingFile(bytes, seeds);
          if (f.ok) { await write(`${out}/file.${f.ext}`, f.bytes); r.surfaces.push({ kind: 'pdf', path: `out/${d.id}/file.${f.ext}`, name: `redacted/<uuid>_drawing.${f.ext}` }); } else r.held.push('file:' + f.held);
        }
      }
      // The BOQ read off the text layer, as the supplier inbox serves it (whatever happened to the pictures).
      const boq = boqFromPages(pp, '');
      const hits: string[] = [];
      const gate = inboxBoq({ boq: boq.boq ?? boq }, d.customer.name, seedTerms({ name: d.customer.name, email: d.customer.email, phone: d.customer.phone, project: d.customer.project }), hits);
      if (gate.boq) { await write(`${out}/boq.json`, JSON.stringify(gate.boq)); r.surfaces.push({ kind: 'json', path: `out/${d.id}/boq.json` }); } else if (gate.withheld) r.held.push('boq:withheld');
    }
  } catch (e) { r.error = String((e as Error)?.message || e).slice(0, 200); }
  result.drawings.push(r);
}

// ── quotations ────────────────────────────────────────────────────────────────────────────────────────
const nowDate = { date: '3 November 2026' };
// deno-lint-ignore no-explicit-any
const stored: Record<string, any> = {};
for (const q of man.quotes) {
  const out = `${dir}/out/${q.id}`;
  // deno-lint-ignore no-explicit-any
  const r: any = { id: q.id, request: q.request, surfaces: [], held: [] };
  try {
    const rd = await readDocument(await read(q.file), q.filename, q.mime);
    // deno-lint-ignore no-explicit-any
    let p: any = null;
    if (rd.ok) p = quoteFromExtracted(rd as never, [q.supplier.company_name]);
    else r.held.push('unreadable:' + ((rd as { error?: string }).error || 'refused'));
    // The supplier reviews the proposal and submits; what they typed in the form joins it (worst case: they kept
    // every line the file gave and typed the letterhead's details into the terms). submit_quote's scrub, verbatim.
    const hits: string[] = [];
    const s = (v: unknown, n: number) => scrubIdentity(clip(v, n), q.supplier.company_name, hits);
    const form = q.form || {};
    const row = {
      id: q.id, quote_amount: p?.amount ?? form.amount ?? 1000, price_ex_vat: p?.amount ?? form.amount ?? 1000,
      notes: s([p?.notes, form.notes].filter(Boolean).join(' '), 1000), scope: s(form.scope ?? p?.scope, 2000), conditions: s(form.conditions, 2000),
      exclusions: s(form.exclusions, 2000), lead_time: s(form.lead_time, 200), validity: s(form.validity, 200), payment_terms: s(form.payment_terms, 400), warranty: s(form.warranty, 200),
    };
    // deno-lint-ignore no-explicit-any
    const lines = [...(p?.line_items ?? []), ...(form.lines ?? [])].slice(0, 80).map((raw: any) => scrubLine({ ...raw }, q.supplier.company_name, hits));
    // deno-lint-ignore no-explicit-any
    const items = lines.map((l: any) => ({ desc: clip(l.description, 300), qty: String(l.qty ?? ''), unit: String(l.unit ?? ''), amount: typeof l.amount === 'number' ? l.amount : null, brand: l.brand ?? null, model: l.model ?? null, specification: l.specification ?? null }));
    await write(`${out}/stored_quote.json`, JSON.stringify({ ...row, items }));
    r.surfaces.push({ kind: 'json', path: `out/${q.id}/stored_quote.json` });
    stored[q.id] = { q, row, items };
    const maskNames = [q.supplier.company_name, q.supplier.email, q.supplier.phone, q.supplier.whatsapp, q.supplier.website].filter((v) => v && String(v).trim().length >= 3);
    const inq = { id: man.requests[q.request].id, rfq_no: man.requests[q.request].rfq_no, category: 'hvac', summary: 'Supply and install split units', emirate: 'Dubai' };
    const doc = quoteDocument({ quote: row, inquiry: inq, items, letter: 'A', lang: 'en', maskNames, requestUrl: 'https://quotesdone.com/me', revealRate: 0.03, ...nowDate });
    await write(`${out}/quote_doc.json`, JSON.stringify(doc.body));
    r.surfaces.push({ kind: 'json', path: `out/${q.id}/quote_doc.json` });
    const pdf = await renderPdf(doc.body, { fetchBytes: async () => null });
    if (pdf.ok) { await write(`${out}/quotation.pdf`, pdf.bytes); r.surfaces.push({ kind: 'pdf', path: `out/${q.id}/quotation.pdf` }); } else r.held.push('quote_pdf:' + pdf.status);
  } catch (e) { r.error = String((e as Error)?.message || e).slice(0, 200); }
  result.quotes.push(r);
}
// The comparison: every quote of one request, cheapest first, as Supplier A, B, ...
for (const [ri, req] of man.requests.entries()) {
  const out = `${dir}/out/request_${ri}`;
  // deno-lint-ignore no-explicit-any
  const r: any = { id: `request_${ri}`, quotes: [], surfaces: [] };
  try {
    const mine = man.quotes.filter((q: { request: number }) => q.request === ri).map((q: { id: string }) => stored[q.id]).filter(Boolean);
    // deno-lint-ignore no-explicit-any
    mine.sort((a: any, b: any) => a.row.quote_amount - b.row.quote_amount);
    // deno-lint-ignore no-explicit-any
    const lab = mine.map((m: any, i: number) => ({ quote_id: m.q.id, label: 'Supplier ' + supplierLabel(i), price: m.row.quote_amount, lead_time: m.row.lead_time, validity: m.row.validity, warranty: m.row.warranty, payment_terms: m.row.payment_terms, exclusions: m.row.exclusions, itemised: m.items.length > 0, expired: false, source: 'upload', completeness: { score: 80, passed: true, missing_mandatory: 0 } }));
    r.quotes = mine.map((m: { q: { id: string } }) => m.q.id);
    // deno-lint-ignore no-explicit-any
    const a: any = deterministicCompare(lab as never, 'en');
    a.all_quotes = rosterOf(lab as never, a.top3); a.total_quotes = lab.length;
    // deno-lint-ignore no-explicit-any
    const maskNames = mine.flatMap((m: any) => [m.q.supplier.company_name, m.q.supplier.email, m.q.supplier.phone, m.q.supplier.whatsapp, m.q.supplier.website]).filter((v: string) => v && v.length >= 3);
    const doc = compareDocument({ analysis: a, inquiry: { id: req.id, rfq_no: req.rfq_no, category: 'hvac', summary: 'Supply and install split units', emirate: 'Dubai' }, lang: 'en', maskNames, ...nowDate });
    await write(`${out}/compare_doc.json`, JSON.stringify(doc.body)); r.surfaces.push({ kind: 'json', path: `out/request_${ri}/compare_doc.json` });
    const pdf = await renderPdf(doc.body, { fetchBytes: async () => null });
    if (pdf.ok) { await write(`${out}/comparison.pdf`, pdf.bytes); r.surfaces.push({ kind: 'pdf', path: `out/request_${ri}/comparison.pdf` }); }
    const t = compareTable(a, false);
    if (t) { await write(`${out}/comparison.csv`, toCsv(t.head, t.rows)); r.surfaces.push({ kind: 'text_file', path: `out/request_${ri}/comparison.csv` }); }
  } catch (e) { r.error = String((e as Error)?.message || e).slice(0, 200); }
  result.requests.push(r);
}

// ── pre-reveal Q&A ────────────────────────────────────────────────────────────────────────────────────
for (const m of man.qa) {
  const text = stripContact(m.text, m.names);
  await write(`${dir}/out/${m.id}/message.txt`, text);
  result.qa.push({ id: m.id, surfaces: [{ kind: 'text_file', path: `out/${m.id}/message.txt` }], held: [] });
}
await Deno.writeTextFile(`${dir}/pipeline.json`, JSON.stringify(result, null, 1));
console.log(`pipeline: ${result.drawings.length} drawings, ${result.quotes.length} quotations, ${result.requests.length} requests, ${result.qa.length} messages`);
