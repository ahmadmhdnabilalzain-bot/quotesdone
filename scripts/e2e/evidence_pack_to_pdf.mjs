// scripts/e2e/evidence_pack_to_pdf.mjs — turns one evidence_pack.mjs output folder into ONE PDF per journey and
// uploads it to the private `evidence` bucket, so the founder opens the documents themselves (ledger 1684, 19 Nov 2026:
// "every customer/supplier journey must be proven by the documents themselves"; none had been produced since 27 Oct).
// Assigned: it_engineer. Measured before this file: evidence_pack.mjs wrote loose PDFs/PNGs/xlsx per journey and
// delivered a zip by hand; no merged PDF, no upload.
//
//   node scripts/e2e/evidence_pack_to_pdf.mjs --out <evidence dir> [--upload] [--dry-list]
//
// Per journey folder (1_text_only, 2_*, 3_*) the pack is, in this order, every document that exists:
//   customer request (chat_transcript.txt) · customer BOQ (customer_BOQ_*.xlsx) · customer drawing PDF ·
//   supplier inquiry (42_inquiry_as_sent_to_suppliers.pdf) · every supplier quotation (Q*_supplier_quotation.pdf) ·
//   comparison (52_comparison_report.pdf) · reveal invoice (63_invoice.pdf).
// A document that is missing is LISTED on the cover as missing, never silently skipped, and never invented.
// The supplier registration journey (4_*) packs its signed agreement certificate, licence, profile, catalogue and its
// step list from manifest.json. Upload: private bucket `evidence`, path evidence_packs/<run tag>/<name>.pdf, service role
// from keys(); nothing is sent to anyone. Dropbox is reached by the coordinating session's connector, not from here.
import { readdirSync, readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { join, resolve, basename } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const esc = (s) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

/** The documents of a journey folder, in reading order: [{ label, file, kind }] where file is absolute or null (missing). */
export function packPlan(dir, files = readdirSync(dir), subfiles = (d) => (existsSync(join(dir, d)) ? readdirSync(join(dir, d)) : [])) {
  const has = (re) => files.filter((f) => re.test(f)).sort();
  const one = (label, re, kind) => { const f = has(re)[0]; return [{ label, file: f ? join(dir, f) : null, kind }]; };
  const quotes = subfiles('quotations').filter((f) => /^Q\d+_.*supplier_quotation\.pdf$/.test(f)).sort((a, b) => parseInt(a.slice(1), 10) - parseInt(b.slice(1), 10));
  return [
    ...one('Customer request (the chat, as typed)', /^chat_transcript\.txt$/, 'text'),
    ...one('Customer BOQ', /^customer_BOQ_.*\.xlsx$/, 'xlsx'),
    ...one('Customer drawing', /^customer_drawing_.*\.pdf$/, 'pdf'),
    ...one('Supplier inquiry (as sent to suppliers, identity removed)', /^42_inquiry_as_sent_to_suppliers\.pdf$/, 'pdf'),
    ...(quotes.length ? quotes.map((f, i) => ({ label: `Supplier quotation ${i + 1}`, file: join(dir, 'quotations', f), kind: 'pdf' })) : [{ label: 'Supplier quotations', file: null, kind: 'pdf' }]),
    ...one('Customer comparison report', /^52_comparison_report\.pdf$/, 'pdf'),
    ...one('Reveal invoice', /^63_invoice\.pdf$/, 'pdf'),
  ];
}

/** The registration journey's documents. */
export function registrationPlan(dir, files = readdirSync(dir)) {
  const pick = (label, re) => { const f = files.filter((x) => re.test(x)).sort()[0]; return { label, file: f ? join(dir, f) : null, kind: 'pdf' }; };
  return [pick('Trade licence', /^trade_licence\.pdf$/), pick('Company profile', /^company_profile\.pdf$/), pick('Product catalogue', /^product_catalogue\.pdf$/),
    pick('Signed Supplier Agreement certificate', /^signed_supplier_agreement_certificate\.pdf$/)];
}

export function coverHtml(title, plan, meta = {}) {
  const rows = plan.map((p, i) => `<tr><td>${i + 1}</td><td>${esc(p.label)}</td><td>${p.file ? esc(basename(p.file)) : '<b style="color:#b00">MISSING - not produced by this run</b>'}</td></tr>`).join('');
  return `<html><body style="font-family:Arial;margin:30px"><h1>${esc(title)}</h1><p>QuotesDone journey evidence. ZZ DEMO identities only; Stripe TEST mode; no real person was contacted.</p>
<p>Run tag ${esc(meta.tag || '-')} - ${esc(meta.dry ? 'DRY run (models off)' : 'real run (models on, capped)')} - captured ${esc(meta.started || '-')}${meta.spend ? ` - model spend USD ${esc(meta.spend)}` : ''}</p>
<table border="1" cellpadding="6" style="border-collapse:collapse"><tr><th>#</th><th>Document</th><th>File</th></tr>${rows}</table></body></html>`;
}

function xlsxHtml(path) {
  const py = 'import openpyxl,sys,json\nws=openpyxl.load_workbook(sys.argv[1]).active\nprint(json.dumps([[("" if c is None else str(c)) for c in r] for r in ws.iter_rows(values_only=True)]))';
  const r = spawnSync('python3', ['-c', py, path], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('xlsx read: ' + r.stderr);
  const rows = JSON.parse(r.stdout).map((c) => `<tr>${c.map((x) => `<td>${esc(x)}</td>`).join('')}</tr>`).join('');
  return `<html><body style="font-family:Arial"><h2>Customer BOQ (${esc(basename(path))})</h2><table border="1" cellpadding="4" style="border-collapse:collapse">${rows}</table></body></html>`;
}
const textHtml = (path) => `<html><body style="font-family:Arial"><h2>Customer request</h2><pre style="white-space:pre-wrap;font-size:11px">${esc(readFileSync(path, 'utf8'))}</pre></body></html>`;

async function build(browser, name, title, plan, meta, outDir) {
  const tmp = join(outDir, '.pack_tmp'); mkdirSync(tmp, { recursive: true });
  const html = async (h, f) => { const c = await browser.newContext(); const p = await c.newPage(); await p.setContent(h, { waitUntil: 'load' });
    writeFileSync(f, await p.pdf({ format: 'A4', printBackground: true })); await c.close(); return f; };
  const parts = [await html(coverHtml(title, plan, meta), join(tmp, '00_cover.pdf'))];
  for (const [i, p] of plan.entries()) {
    if (!p.file) continue;
    if (p.kind === 'pdf') parts.push(p.file);
    else parts.push(await html(p.kind === 'xlsx' ? xlsxHtml(p.file) : textHtml(p.file), join(tmp, `${String(i + 1).padStart(2, '0')}.pdf`)));
  }
  const out = join(outDir, `${name}.pdf`);
  const r = spawnSync('pdfunite', [...parts, out], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('pdfunite: ' + r.stderr);
  return { out, documents: plan.filter((p) => p.file).length, missing: plan.filter((p) => !p.file).map((p) => p.label) };
}

// A run tag becomes one path segment and nothing else: no '..', no '/', so an upload never leaves evidence_packs/ (review of #2082).
export const safeTag = (t) => (String(t ?? '').replace(/[^A-Za-z0-9_-]/g, '_').replace(/^_+$/, '') || 'untagged').slice(0, 80);

async function upload(file, objectPath) {
  const { keys, BASE } = await import('../lib/demo_factory.mjs');
  const { SERVICE } = await keys();
  const r = await fetch(`${BASE}/storage/v1/object/evidence/${objectPath.split('/').map(encodeURIComponent).join('/')}`, {
    method: 'POST', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE, 'Content-Type': 'application/pdf', 'x-upsert': 'true' }, body: readFileSync(file), signal: AbortSignal.timeout(60_000) });
  if (!r.ok) throw new Error(`upload ${objectPath}: HTTP ${r.status} ${(await r.text()).slice(0, 200)}`);
  return `evidence/${objectPath}`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const argv = process.argv.slice(2); const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
  const out = resolve(val('--out') || ''); if (!val('--out') || !existsSync(out)) { console.error('usage: --out <evidence dir> [--upload] [--dry-list]'); process.exit(2); }
  const M = existsSync(join(out, 'manifest.json')) ? JSON.parse(readFileSync(join(out, 'manifest.json'), 'utf8')) : {};
  const meta = { tag: M.tag, dry: M.dry, started: M.started, spend: M.spend?.usd_reported };
  const dirs = readdirSync(out).filter((d) => statSync(join(out, d)).isDirectory() && /^\d_/.test(d)).sort();
  let browser = null; const done = [];
  try {
    if (!argv.includes('--dry-list')) { const { launch } = await import('./browser.mjs'); browser = await launch(); }
    for (const d of dirs) {
      const dir = join(out, d); const plan = d.startsWith('4_') ? registrationPlan(dir) : packPlan(dir);
      if (!browser) { console.log(d, plan.map((p) => `${p.label}: ${p.file ? 'present' : 'MISSING'}`).join(' | ')); continue; }
      const r = await build(browser, `evidence_pack_${d}`, `Evidence pack - ${d.replace(/^\d_/, '').replace(/_/g, ' ')}`, plan, meta, out);
      if (argv.includes('--upload')) r.uploaded = await upload(r.out, `evidence_packs/${safeTag(M.tag)}/${basename(r.out)}`);
      done.push(r); console.log(JSON.stringify(r));
    }
  } finally { if (browser) await browser.close().catch(() => {}); }
}
