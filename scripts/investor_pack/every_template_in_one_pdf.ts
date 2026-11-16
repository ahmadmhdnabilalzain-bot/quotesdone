// EVERY TEMPLATE IN ONE PDF — the investor pack of ledger 1547. Seat: accountant (agent: L6_BOOKS, accountant seat
// builder), 16 Nov 2026.
//
// The founder, 4 Nov 2026 (ledger 1547): "For the investor meeting: one PDF showing every template the company generates
// and shares (the BOQ shared with suppliers, how drawings are shared with suppliers, the comparison report, the invoice,
// the email templates, the accountant report, and every other report template), together with the expenses statement,
// to show the investor how the company is automated and organised."
//
// HOW. Every document is drawn by the company's REAL builder and the REAL renderer (pdf_native/render.ts) with ZZ DEMO
// data, offline: no network, no database, no production function, nothing written anywhere but the output file.
//   * the documents the page checks already prove (pdf_native/every_document_we_issue.fixtures.ts, one shared list);
//   * "Download my data" for a supplier and a customer (my_data_pdf, its own ZZ DEMO exports);
//   * the drawing as suppliers receive it: a ZZ DEMO sheet before and after redactPdfVector (the identity cut);
//   * the sign-in and confirmation emails, as their plain-text part (codeEmail; the HTML part is the same words);
//   * the expenses statement already filed in docs/reports/expenses_statement_2026/, appended as it is.
// What only a production routine can fill (its blocks are written by SQL from live rows) is LISTED on the last page,
// with the routine that writes it, never rendered with invented figures.
//
// Run (fonts are the committed copies; the lockup, signature and stamp PNGs are read from QD_BRAND_DIR when given, and
// otherwise the renderer's text letterhead stands):
//   deno run --no-lock --node-modules-dir=none --allow-read=. --allow-write=<out dir> --allow-env=QD_BRAND_DIR \
//     scripts/investor_pack/every_template_in_one_pdf.ts <out.pdf>
// THE PDF IS NOT KEPT IN GIT (docs/reports/README.md: PDFs go to the private `evidence` bucket). It is written outside the
// repository and uploaded to `evidence` under EVIDENCE_KEY; docs/reports/EVIDENCE_INDEX.md carries its size and sha256.
// It carries QuotesDone's OWN letterhead (DET licence, TDRA permit, the company's numbers, the founder as signatory): it is
// the company's own document, and the cover says so; every counterparty in it is ZZ DEMO.
import { PDFDocument } from 'https://esm.sh/pdf-lib@1.17.1';
import { renderPdf } from '../../supabase/functions/pdf_native/render.ts';
import { docs as fixtureDocs, type Doc } from '../../supabase/functions/pdf_native/every_document_we_issue.fixtures.ts';
import { dataCopyBody } from '../../supabase/functions/my_data_pdf/document.ts';
import { CUSTOMER_EXPORT, SUPPLIER_EXPORT } from '../../supabase/functions/my_data_pdf/fixtures.ts';
import { codeEmail } from '../../supabase/functions/_shared/code_email.ts';
import { redactPdfVector } from '../../supabase/functions/_shared/pdf_vector_redact.ts';
import { seedTerms } from '../../supabase/functions/_shared/anonymise.ts';
import { CUSTOMER, FILE_NAME, zzPdfSheet } from '../../supabase/functions/_shared/doc_read/zz_demo_drawings.fixtures.ts';

const REPO = new URL('../../', import.meta.url);
const FONTS = new URL('supabase/functions/pdf_native/fixtures/brand/', REPO);
const EXPENSES = new URL('docs/reports/expenses_statement_2026/QuotesDone_Operating_Expenses_Statement_2026.pdf', REPO);
export const EVIDENCE_KEY = 'docs/reports/investor_pack_2026/QuotesDone_every_template_ZZ_DEMO.pdf';

const brandDir = (() => { try { return Deno.env.get('QD_BRAND_DIR') || null; } catch { return null; } })();
async function fetchBytes(p: string): Promise<Uint8Array | null> {
  if (/\.ttf$/.test(p)) return await Deno.readFile(new URL(p, FONTS));
  if (!brandDir) return null;
  try { return await Deno.readFile(`${brandDir}/${p}`); } catch { return null; }
}

/** One entry of the pack: what it is, who receives it, when, and the PDF (rendered here or read as it is filed). */
export type Entry = { section: string; name: string; to: string; lang: 'en' | 'ar'; body?: unknown; pdf?: Uint8Array };

// Who receives each fixture type and when (the reader's words, not the code's).
const ABOUT: Record<string, [string, string, string]> = {
  request_brief: ['Supplier documents', 'The request brief with its bill of quantities, as matched suppliers receive it', 'Supplier; the customer sees the same'],
  quotation: ['Customer documents', 'A supplier quotation, anonymised', 'Customer, before any reveal'],
  regenerated_quotation: ['Customer documents', 'The quotation regenerated in the standard layout', 'Customer'],
  comparison_report: ['Customer documents', 'The comparison report of every quotation', 'Customer'],
  reveal_invoice: ['Customer documents', 'The reveal fee invoice', 'Customer, on paying to reveal a supplier'],
  reveal_receipt: ['Customer documents', 'The reveal fee receipt', 'Customer, on payment'],
  terms_certificate_customer: ['Customer documents', 'Certificate of acceptance of the Terms of Service', 'Customer, on accepting the terms'],
  supplier_registration_invoice: ['Supplier documents', 'The supplier subscription invoice', 'Supplier'],
  supplier_registration_receipt: ['Supplier documents', 'The supplier subscription receipt', 'Supplier, on payment'],
  supplier_dues_invoice: ['Supplier documents', 'Supplier dues invoice', 'Supplier'],
  supplier_dues_receipt: ['Supplier documents', 'Supplier dues receipt', 'Supplier, on payment'],
  terms_certificate_supplier: ['Supplier documents', 'Certificate of acceptance of the Supplier Agreement', 'Supplier, on signing'],
  conversation_archive: ['Records', 'A conversation archived as a record', 'Kept on file (backup)'],
  email_print: ['Records', 'A vendor bill email printed for the books', 'The accountant (expenses mailbox)'],
  it_incident: ['Reports', 'An IT incident record', 'The IT engineer seat and the auditor'],
  internal_report: ['Reports', 'An internal report (weekly report layout)', 'The CEO seat'],
  dropbox_backup_profile: ['Records', 'A customer profile as backed up to Dropbox', 'Kept on file (backup)'],
};
const RECOVERY = ['Supplier documents', 'Charge recovery pack', 'A supplier who owes a charge'];

export async function packEntries(): Promise<Entry[]> {
  const out: Entry[] = [];
  const order = Object.keys(ABOUT);
  const sorted = [...fixtureDocs].sort((a, b) => rank(a) - rank(b) || (a.lang === b.lang ? 0 : a.lang === 'en' ? -1 : 1));
  function rank(d: Doc) { const i = order.indexOf(d.type); return i < 0 ? order.length : i; }
  for (const d of sorted) {
    const a = ABOUT[d.type];
    const [section, name, to] = a ?? RECOVERY;
    const label = a ? name : `${name}: ${d.type.replace(/^recovery_/, '').replace(/_/g, ' ')}`;
    out.push({ section, name: label, to, lang: d.lang, body: d.body });
  }
  for (const [role, exp] of [['supplier', SUPPLIER_EXPORT], ['customer', CUSTOMER_EXPORT]] as const) {
    for (const lang of ['en', 'ar'] as const) {
      out.push({ section: 'Records', name: `"Download my data" for a ${role}`, to: `The ${role}, from the portal`, lang,
        body: dataCopyBody({ exp, lang, role }) });
    }
  }
  for (const purpose of ['signin', 'confirm'] as const) {
    for (const lang of ['en', 'ar'] as const) {
      const m = codeEmail(purpose, '482913', lang === 'ar');
      out.push({ section: 'Emails', name: `Email: ${purpose === 'signin' ? 'sign-in code' : 'address confirmation'} (its plain-text part)`,
        to: 'Customer or supplier', lang,
        body: { title: m.subject, lang, options: { letterhead: true },
          blocks: [{ t: 'kv', pairs: [[lang === 'ar' ? 'الموضوع' : 'Subject', m.subject]] }, ...m.text.split('\n\n').map((p) => ({ t: 'p', text: p }))] } });
    }
  }
  return out;
}

/** The drawing as suppliers receive it: the ZZ DEMO sheet, and the same sheet after the identity cut. */
export async function drawingPair(): Promise<{ before: Uint8Array; after: Uint8Array; removed: number } | null> {
  const before = zzPdfSheet();
  const r = await redactPdfVector(before, seedTerms({ ...CUSTOMER, extra: [FILE_NAME] }));
  return r.ok ? { before, after: r.bytes, removed: r.removed_runs } : null;
}

// Rendered by a production routine from live rows: listed, not rendered (ledger 1547 asks for them; a demo copy of a
// SQL-written report would be figures nobody measured).
export const LISTED: [string, string][] = [
  ['The accountant\'s monthly close pack and "Spend since day one" report', 'blocks written by the accountant\'s SQL routines (accountant/actions/reports.ts, duties.ts) from the live ledger; the expenses statement at the end of this pack is the filed copy of the same figures'],
  ['The CEO\'s daily brief and weekly company report', 'blocks written by fn_ceo_* routines from live seat activity (resilience_ping/ticks/ceo.ts)'],
  ['The daily supplier list for the founder\'s outreach', 'blocks written from live supplier leads (resilience_ping/ticks/customer_support.ts)'],
  ['The IT incident record as filed', 'blocks written by fn_it_incident_pdf_blocks from a live incident; the layout is shown above with demo text'],
  ['Case summaries in the Dropbox backup', 'a Markdown file per case, written from live case rows (dropbox_backup/row.ts)'],
  ['The marketing month calendar', 'blocks from the approved month\'s scheduled posts (marketing_channels; _shared/marketing_calendar_doc.ts)'],
  ['WhatsApp templates and the reply templates', 'text registered with Meta and held in messaging_template / response_template; they are messages, not documents'],
];

async function render(body: unknown): Promise<Uint8Array> {
  const r = await renderPdf(body as Parameters<typeof renderPdf>[0], { fetchBytes });
  if (!r.ok) throw new Error('the renderer refused: ' + JSON.stringify((r as { body?: unknown }).body).slice(0, 300));
  return r.bytes;
}
const pages = async (b: Uint8Array) => (await PDFDocument.load(b)).getPageCount();

export async function buildPack(): Promise<{ bytes: Uint8Array; rows: string[][] }> {
  const entries = await packEntries();
  for (const e of entries) e.pdf = await render(e.body);
  const drawing = await drawingPair();
  let expenses: Uint8Array | null = null;
  try { expenses = await Deno.readFile(EXPENSES); } catch { expenses = null; }
  const drawingNote = drawing ? await render({ title: 'How a drawing is shared with suppliers', options: { letterhead: true }, blocks: [
    { t: 'p', text: 'A customer uploads a drawing. Before any supplier sees it, the platform cuts every line that identifies the customer, the consultant or the project from the title block, and leaves the drawing itself untouched: the next two pages are a ZZ DEMO sheet before and after.' },
    { t: 'kv', pairs: [['Identity text runs removed', String(drawing.removed)], ['Geometry and symbol counts', 'unchanged (checked on every file)'], ['If anything identifying remains', 'the drawing is held, not shared']] },
  ] }) : null;

  // Section order, then the contents table with page numbers.
  const SECTIONS = ['Customer documents', 'Supplier documents', 'Records', 'Emails', 'Reports'];
  entries.sort((a, b) => SECTIONS.indexOf(a.section) - SECTIONS.indexOf(b.section));
  const parts: { title: string; section: string; to: string; lang: string; pdf: Uint8Array }[] = [];
  for (const e of entries) parts.push({ title: e.name, section: e.section, to: e.to, lang: e.lang === 'ar' ? 'Arabic' : 'English', pdf: e.pdf! });
  if (drawing && drawingNote) {
    const at = parts.findLastIndex((p) => p.section === 'Supplier documents') + 1;
    parts.splice(at, 0,
      { title: 'How a drawing is shared with suppliers', section: 'Supplier documents', to: 'Supplier', lang: 'English', pdf: drawingNote },
      { title: 'The ZZ DEMO drawing as the customer uploaded it', section: 'Supplier documents', to: '(never shared)', lang: 'English', pdf: drawing.before },
      { title: 'The same drawing as suppliers receive it', section: 'Supplier documents', to: 'Supplier', lang: 'English', pdf: drawing.after });
  }
  if (expenses) parts.push({ title: 'Operating expenses statement 2026 (as filed)', section: 'The books', to: 'Founder, investor', lang: 'English', pdf: expenses });
  const listed = await render({ title: 'Templates filled only from live records', options: { letterhead: true }, blocks: [
    { t: 'p', text: 'These documents use the same template, but their content is written by the platform from live records at the moment they are issued. They are listed rather than shown with invented figures.' },
    { t: 'table', head: ['Document', 'Where its content comes from'], rows: LISTED, widths: [0.38, 0.62] },
  ] });
  parts.push({ title: 'Templates filled only from live records', section: 'Index', to: '', lang: 'English', pdf: listed });

  const counts = await Promise.all(parts.map((p) => pages(p.pdf)));
  // The cover + contents is rendered twice: once to learn its own length, then with the final page numbers.
  const coverOf = (start: (i: number) => number) => ({ title: 'QuotesDone — every document we issue', options: { letterhead: true }, blocks: [
    { t: 'p', text: 'Every document QuotesDone generates and sends, drawn by the platform\'s own template and builders with ZZ DEMO data (no real customer, supplier or figure), followed by the operating expenses statement as filed. Arabic copies follow the English where the document is issued in both.' },
    { t: 'p', text: 'Each page carries QuotesDone\'s own letterhead as the company issues it: its trade licence and TDRA permit, its published email and telephone numbers, and its founder as the signatory. Those are the company\'s own details; every customer, supplier, amount and drawing in this pack is ZZ DEMO.' },
    { t: 'table', head: ['#', 'Document', 'Language', 'Who receives it', 'Page'],
      rows: parts.map((p, i) => [String(i + 1), p.title, p.lang, p.to, String(start(i))]), widths: [0.06, 0.48, 0.12, 0.26, 0.08] },
  ] });
  const offset = (front: number) => (i: number) => front + 1 + counts.slice(0, i).reduce((a, b) => a + b, 0);
  let front = await pages(await render(coverOf(offset(1))));
  const cover = await render(coverOf(offset(front)));
  front = await pages(cover);

  const doc = await PDFDocument.create();
  doc.setTitle('QuotesDone — every document we issue (ZZ DEMO)');
  doc.setAuthor('QuotesDone Technologies');
  for (const b of [cover, ...parts.map((p) => p.pdf)]) {
    const src = await PDFDocument.load(b);
    for (const pg of await doc.copyPages(src, src.getPageIndices())) doc.addPage(pg);
  }
  const rows = parts.map((p, i) => [String(i + 1), p.section, p.title, p.lang, String(counts[i]), String(offset(front)(i))]);
  return { bytes: await doc.save(), rows };
}

if (import.meta.main) {
  const out = Deno.args[0];
  if (!out) { console.error('usage: every_template_in_one_pdf.ts <out.pdf>  (outside the repository; upload to evidence as ' + EVIDENCE_KEY + ')'); Deno.exit(2); }
  const { bytes, rows } = await buildPack();
  await Deno.mkdir(out.replace(/\/[^/]+$/, ''), { recursive: true });
  await Deno.writeFile(out, bytes);
  for (const r of rows) console.log(r.join(' | '));
  console.log(`${out}: ${rows.length} documents, ${(await PDFDocument.load(bytes)).getPageCount()} pages, ${bytes.length} bytes`);
}
