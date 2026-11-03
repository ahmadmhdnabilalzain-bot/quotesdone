// scripts/e2e/document_reading_qualification.ts — the supplier DOCUMENT-READING QUALIFICATION, graded by code (Deno).
// Seat: sales_engineer. 3 Nov 2026. Driven by scripts/e2e/document_reading_qualification.mjs (which opens the model window).
//
// Every gold item (document_reading_qualification_corpus.ts) goes through the PRODUCTION modules, imported, never copied,
// in the order supplier_docs_later.readStoredDocsLater runs them after an upload:
//   1. the type gate on the stored bytes      attachment.sanitizeUpload (the gate gateStored applies; the malware scan
//                                             itself is a network service and is not part of this measurement)
//   2. a picture or a scan to the model       supplier_docs_later.readProfileByModel (its size and page caps, its cut)
//   3. the trade read                         supplier_doc_trades.readDocForTrades (the text layer, offerText, the chooser)
//   4. a licence's fields                     document_expiry.readLicenceFields (+ mergeLicenceReads with the model's read)
// N times per item (--repeats, default 5). Graded by code, per document class:
//   REACH       each gold trade's own line is in the text the model is given (supplier_trade_choice.modelText) or on a
//               page readProfileByModel sends. A line that never reaches the model cannot be proposed: this bounds recall,
//               and it is measured without spending anything.
//   TRADES      (model stage) precision and recall of the proposed codes against gold, forbidden codes proposed (must be 0)
//   LICENCE     every field exactly as printed (licence_no, names, authority, emirate, issue, expiry, activities)
//   HONESTY     an unreadable file is refused / unreadable / held with its reason and proposes nothing; a partial read says so
//   CONSISTENCY the same verdict on every repeat
//
//   deno run -A --unsafe-proto --no-lock --node-modules-dir=auto scripts/e2e/document_reading_qualification.ts <corpus dir> <out.json> [--repeats 5] [--model]
// --model needs the rehearsal-window env the driver sets: SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY QD_RUN_TAG QD_SUBJECT QD_E2E_SECRET QD_SECRET_EXTRACT.
import { sanitizeUpload, SAFE_SUPPLIER_PAPERS } from '../../supabase/functions/_shared/attachment.ts';
import { LIMITS } from '../../supabase/functions/_shared/doc_read/types.ts';
import { readDocForTrades, type DocEvidence, type TradeResolveDeps } from '../../supabase/functions/_shared/supplier_doc_trades.ts';
import { modelText, quoteKey } from '../../supabase/functions/_shared/supplier_trade_choice.ts';
import * as DX from '../../supabase/functions/_shared/document_expiry.ts';
import { getDocumentProxy } from 'npm:unpdf@0.11.0';

// malware.ts (imported by supplier_docs_later) builds a client at import; nothing here calls it.
Deno.env.set('SUPABASE_URL', Deno.env.get('SUPABASE_URL') ?? 'http://127.0.0.1:1');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? 'not-used');
const { readProfileByModel, stuckOf } = await import('../../supabase/functions/_shared/supplier_docs_later.ts');

const [dir, outPath] = Deno.args;
const flag = (f: string) => Deno.args.includes(f);
const val = (f: string) => { const i = Deno.args.indexOf(f); return i >= 0 ? Deno.args[i + 1] : null; };
const REPEATS = Number(val('--repeats') || 5);
const MODEL = flag('--model');
const ONLY = val('--only')?.split(',') ?? null;
if (!dir || !outPath) { console.error('usage: <corpus dir> <out.json> [--repeats N] [--model] [--only id,id]'); Deno.exit(2); }
type Gold = { code: string; line: string; page: number };
// deno-lint-ignore no-explicit-any
// allowed: codes the gold accepts but does not require (a real profile's trades_also); strict: every proposed code outside trades and
// allowed counts as a WRONG keyword (the real corpus, whose truth lists what the company does, not each decoy it prints)
type Item = { id: string; file: string; mime: string; kind: 'profile' | 'licence' | 'catalogue'; cls: string; pages: number; text_layer: boolean; registered_name: string; trades: Gold[]; forbidden: string[];
  allowed?: string[]; strict?: boolean; licence?: any; expect?: string };
const PARALLEL = Math.max(1, Number(val('--parallel') || 1));
const truth: { items: Item[] } = JSON.parse(await Deno.readTextFile(`${dir}/truth.json`));

// ── the model, when this run may ask it ───────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
let live: any = null;
if (MODEL) {
  const { createClient } = await import('jsr:@supabase/supabase-js@2');
  const { liveTradeDeps } = await import('../../supabase/functions/_shared/trade_resolve.ts');
  const TAG = Deno.env.get('QD_RUN_TAG')!, SUBJECT = JSON.parse(Deno.env.get('QD_SUBJECT') || 'null');
  if (!/^[a-z0-9]{4,16}$/.test(TAG || '') || !SUBJECT) { console.error('--model needs QD_RUN_TAG and QD_SUBJECT (the driver opens the window)'); Deno.exit(2); }
  const headers = { Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': Deno.env.get('QD_E2E_SECRET') || '' };
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  const deps = await liveTradeDeps(admin, 'document_reading_qualification', { subject: SUBJECT, headers });
  const extract = async (body: Record<string, unknown>) => {
    const r = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/license_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify({ __secret: Deno.env.get('QD_SECRET_EXTRACT'), subject: SUBJECT, ...body }), signal: AbortSignal.timeout(150_000) });
    return { ...(await r.json().catch(() => ({}))), status: r.status };
  };
  live = { deps, extract, subject: SUBJECT };
}

// ── what reached the model ─────────────────────────────────────────────────────────────────────────
async function pagesOf(b64: string): Promise<number | null> {
  try { const bin = atob(b64); const u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return (await getDocumentProxy(u)).numPages; } catch { return null; }
}
const inText = (line: string, text: string) => (' ' + quoteKey(text) + ' ').includes(' ' + quoteKey(line) + ' ');

type Run = {
  status: string; reason: string | null; codes: string[]; reach: Record<string, boolean>; model_chars: number; sent_pages: number | null; sent_kind: string | null;
  pages_read: string | null; ledger: { read: number; of: number } | null; cut_recorded: boolean; first_pass: string | null; passes: number; choice: string | null; rejected: { code: string; why: string }[]; quotes: Record<string, string>; licence?: Record<string, unknown>; licence_needs_model?: boolean; ms: number; error?: string;
};
async function once(it: Item): Promise<Run> {
  const t0 = performance.now();
  const bytes = await Deno.readFile(`${dir}/${it.file}`);
  let given = '';            // every text the trade chooser was handed this run
  let sent: { kind: string; pages: number | null } | null = null;
  const recorder = (inner?: TradeResolveDeps['chooseTrades']): NonNullable<TradeResolveDeps['chooseTrades']> => async (text, kind, company) => {
    given += '\n' + modelText(text);
    return inner ? await inner(text, kind, company) : { ok: false, error: 'model stage not run (code-only measurement)' };
  };
  const never = async () => null;
  const deps: TradeResolveDeps = live
    ? { ...live.deps, chooseTrades: recorder(live.deps.chooseTrades), budget: { left: 40 } }
    // deno-lint-ignore no-explicit-any
    : { services: [], embed: never as any, budget: { left: 0 }, normTrades: never, chooseTrades: recorder() } as unknown as TradeResolveDeps;
  // 1. the type gate on the stored bytes
  const g = sanitizeUpload({ input: bytes, declaredMime: it.mime, filename: it.file, allow: SAFE_SUPPLIER_PAPERS, maxBytes: LIMITS.maxPaperBytes });
  // deno-lint-ignore no-explicit-any
  const d: any = { path: `qualification/${it.file}`, name: it.file, kind: it.kind, names: [it.registered_name] };
  if (!g.ok) d.refused = `${g.error}${g.detail ? ': ' + g.detail : ''}`;
  else { d.bytes = g.bytes; d.mime = g.mime; }
  let lic: Record<string, unknown> | undefined, needs: boolean | undefined;
  if (it.kind === 'licence') {
    const code = d.bytes ? await DX.readLicenceFields(d.bytes, d.mime) : null;
    needs = DX.licenceNeedsModel(code);
    let model = null;
    if (live && needs && d.bytes) {
      const j = await live.extract({ mode: 'license', ...DX.licenceModelPayload({}, { bytes: d.bytes, mime: d.mime }, null) });
      model = j?.ok ? j.doc : null;
      if (model?.activities?.length && !code?.activities?.length) d.photo_text = (await import('../../supabase/functions/_shared/supplier_doc_trades.ts')).modelReadText('licence', model.activities);
    }
    lic = DX.mergeLicenceReads(code, model).merged;
  } else if (!d.refused) {   // readStoredDocsLater runs the model hook for a profile and (3 Nov 2026) a catalogue
    // 2. a picture or a scan: the same function the upload paths call, its request recorded (and sent, in the model stage)
    await readProfileByModel(d, async (body) => {
      sent = { kind: body.file_b64 ? 'pdf' : 'images', pages: body.file_b64 ? await pagesOf(String(body.file_b64)) : (body.images as unknown[])?.length ?? 0 };
      return live ? await live.extract({ mode: 'profile', ...body }) : { ok: false, status: 503, error: 'model stage not run' };
    }, { subject: live?.subject ?? null, attempts: live ? 2 : 1 });
  }
  // 3. the trade read
  let ev: DocEvidence;
  try { ev = await readDocForTrades(d, deps); } catch (e) { ev = { path: d.path, name: d.name, kind: d.kind, status: 'unreadable', reason: 'THREW: ' + String((e as Error)?.message || e), trades: [], read_at: '' }; }
  // a read that stopped at its budget or text cap is continued by the sweep (supplier_docs_later.stuckOf), run after run, as production does
  const firstPass = ev.pages ? `${ev.pages.read}/${ev.pages.of}` : null;
  let passes = 1;
  while (ev.resume && passes < 10) {
    const next = stuckOf([{ supplier_id: 0, source_docs: { docs: [ev] } }])[0]?.docs[0];
    if (!next) break;
    ev = await readDocForTrades({ ...next, bytes: d.bytes, mime: d.mime, names: d.names }, deps);
    passes++;
  }
  if (d.photo_text) given += '\n' + d.photo_text;
  const reach: Record<string, boolean> = {};
  for (const t of it.trades) {
    if (!t.line) continue;   // a real document's gold names the trade, not the line (reach is measured on the gold corpus)
    if (it.kind === 'licence') reach[t.code] = !!(lic?.activities as string[] | null)?.some((a) => quoteKey(a) === quoteKey(t.line));
    else if (sent) reach[t.code] = (sent as { pages: number | null }).pages != null && t.page <= (sent as { pages: number }).pages;
    else reach[t.code] = inText(t.line, given);
  }
  const note = (ev.reason ?? '') + ' ' + (d.read?.notes ?? []).join(' ');
  return { status: ev.status, reason: ev.reason ?? null, codes: [...new Set((ev.trades || []).map((t) => t.code))].sort(), reach,
    model_chars: given.length, sent_pages: sent ? (sent as { pages: number | null }).pages : null, sent_kind: sent ? (sent as { kind: string }).kind : null,
    pages_read: d.read?.pages && d.read.pages.read < d.read.pages.of ? `${d.read.pages.read}/${d.read.pages.of}` : (/Read (\d+) of (\d+) pages/.exec(note)?.slice(1, 3).join('/') ?? null),
    ledger: ev.pages ?? null, cut_recorded: !!d.pages_read, first_pass: firstPass, passes, choice: ev.choice ?? null, quotes: Object.fromEntries((ev.trades || []).map((t) => [t.code, String(t.snippet ?? '').slice(0, 160)])), rejected: (ev.rejected ?? []).slice(0, 12).map((r) => ({ code: r.code, why: String(r.why).slice(0, 160) })), licence: lic, licence_needs_model: needs, ms: Math.round(performance.now() - t0) };
}

const LIC_FIELDS = ['licence_no', 'legal_name_en', 'legal_name_ar', 'authority', 'emirate', 'issue_date', 'expiry_date', 'activities'];
const norm = (v: unknown) => Array.isArray(v) ? v.map((x) => quoteKey(String(x))).join('|') : v == null ? null : quoteKey(String(v));
const results: Record<string, unknown>[] = [];
const { inPool } = await import('../../supabase/functions/_shared/supplier_trade_choice.ts');
await inPool(truth.items.filter((it) => !ONLY || ONLY.includes(it.id)), PARALLEL, async (it) => {
  const runs: Run[] = [];
  for (let r = 0; r < REPEATS; r++) runs.push(await once(it));
  // the VERDICT once every run of the read is done: a first pass's page count varies with the machine's load (the budget is time),
  // the ledger then continues it, and what is proposed and what reached the model must not vary
  const fp = (x: Run) => JSON.stringify([x.status, x.codes, x.reach, x.sent_pages, x.licence]);
  const modal = [...runs.map(fp).reduce((m, k) => m.set(k, (m.get(k) ?? 0) + 1), new Map<string, number>())].sort((a, b) => b[1] - a[1])[0];
  const gold = new Set(it.trades.map((t) => t.code)), forb = new Set(it.forbidden), ok = new Set([...gold, ...(it.allowed ?? [])]);
  const per = runs.map((x) => {
    const reached = it.trades.filter((t) => x.reach[t.code]).length, reachGold = it.trades.filter((t) => t.line).length;
    const tp = x.codes.filter((c) => gold.has(c)).length, right = x.codes.filter((c) => ok.has(c)).length;
    const unavailable = x.status === 'read' && /could not be chosen|model stage not run/.test(x.reason ?? '');
    // ok: exactly as printed; wrong: a value read that is NOT what the licence prints (worse than unread: it is believed)
    const fields = it.licence ? LIC_FIELDS.map((k) => ({ k, ok: norm(x.licence?.[k]) === norm(it.licence[k] ?? null),
      wrong: norm(x.licence?.[k]) != null && norm(x.licence?.[k]) !== norm(it.licence[k] ?? null) })) : [];
    const expired = it.licence?.expired ? !!x.licence?.expiry_date && String(x.licence.expiry_date) < new Date().toISOString().slice(0, 10) : null;
    // HONEST: a file that cannot be read is refused / unreadable / held with its reason, and proposes nothing
    const honest = it.expect === 'refused_or_unreadable' ? ['refused', 'unreadable'].includes(x.status) && !x.codes.length && !!x.reason
      : it.expect === 'held_honestly' ? x.status === 'needs_ocr' && !x.codes.length && /larger than|pages/i.test(x.reason ?? '')
      : it.expect === 'needs_model' && !MODEL ? x.status === 'needs_ocr' && !x.codes.length && (it.kind !== 'licence' || x.licence_needs_model === true)
      : it.expect === 'read' ? x.status === 'read' : true;
    return { reached, reach_gold: reachGold, gold: gold.size, tp, right, proposed: x.codes.length, unavailable,
      forbidden: x.codes.filter((c) => it.strict ? !ok.has(c) : forb.has(c)), fields, expired, honest,
      // a read that stopped short (the text read's budget or text cap, or a scan cut for the model) must say so on the document
      // the FIRST pass's ledger is what must be on the document while the rest is read
      partial_disclosed: x.pages_read ? !!x.first_pass : x.sent_pages != null && x.sent_pages < it.pages ? x.cut_recorded : null, passes: x.passes };
  });
  results.push({ id: it.id, cls: it.cls, kind: it.kind, pages: it.pages, text_layer: it.text_layer, expect: it.expect ?? null, gold: [...gold], forbidden_gold: it.forbidden,
    consistent: modal[1] / runs.length, runs, per });
  const r0 = runs[0], p0 = per[0];
  console.log(`${it.id.padEnd(30)} ${r0.status.padEnd(10)} reach ${p0.reached}/${p0.gold}  model_chars ${String(r0.model_chars).padStart(6)}  sent ${r0.sent_kind ?? '-'}:${r0.sent_pages ?? '-'}  pages_read ${r0.pages_read ?? 'all'}  ${it.kind === 'licence' ? 'fields ' + p0.fields.filter((f) => f.ok).length + '/' + p0.fields.length : ''}  codes [${r0.codes.join(',')}]  consistent ${(modal[1] / runs.length * 100).toFixed(0)}%  ${r0.ms} ms  ${(r0.reason ?? '').slice(0, 70)}`);
});
await Deno.writeTextFile(outPath, JSON.stringify({ at: new Date().toISOString(), model: MODEL, repeats: REPEATS, results }, null, 1));

// ── the table, per document class (every repeat counted) ─────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
const R = (results as any[]).sort((a, b) => String(a.id).localeCompare(String(b.id)));
const classes = [...new Set(R.map((r) => r.cls))];
const pct = (a: number, b: number) => b ? `${(100 * a / b).toFixed(1)}% (${a}/${b})` : 'n/a';
const rows = classes.map((c) => {
  const rs = R.filter((r) => r.cls === c), per = rs.flatMap((r) => r.per);
  const sum = (f: (p: any) => number) => per.reduce((n: number, p: any) => n + f(p), 0);
  const fieldsAll = per.flatMap((p: any) => p.fields);
  return { c, items: rs.map((r) => r.id).join(', '), runs: per.length,
    reach: pct(sum((p) => p.reached), sum((p) => p.reach_gold ?? p.gold)),
    recall: MODEL ? pct(sum((p) => p.tp), sum((p) => p.gold)) : 'model stage not run',
    precision: MODEL ? pct(sum((p) => p.right ?? p.tp), sum((p) => p.proposed)) : 'model stage not run',
    forbidden: MODEL ? `${sum((p) => p.forbidden.length)} of ${sum((p) => p.proposed)} proposed` : 'model stage not run',
    unavailable: MODEL ? String(per.filter((p: any) => p.unavailable).length) : '-',
    fields: fieldsAll.length ? pct(fieldsAll.filter((f: any) => f.ok).length, fieldsAll.length) : '-',
    wrong: fieldsAll.length ? String(fieldsAll.filter((f: any) => f.wrong).length) : '-',
    honest: pct(per.filter((p: any) => p.honest).length, per.length),
    partial: per.some((p: any) => p.partial_disclosed !== null) ? pct(per.filter((p: any) => p.partial_disclosed).length, per.filter((p: any) => p.partial_disclosed !== null).length) : '-',
    consistent: pct(rs.filter((r) => r.consistent === 1).length, rs.length) };
});
const md = [`# Document-reading qualification: ${MODEL ? 'with the model' : 'code stage (no model spend)'}`, '',
  `${new Date().toISOString()} · ${R.length} gold items × ${REPEATS} repeats · corpus ${(truth as { builder?: string }).builder ?? dir}`, '',
  '| class | items | runs | gold lines reaching the model | trade recall | trade precision | forbidden proposed | model unavailable (runs) | licence fields exact | licence fields WRONG | honest outcome | partial read disclosed | same verdict every repeat |',
  '|---|---|---:|---|---|---|---|---|---|---|---|---|---|',
  ...rows.map((r) => `| ${r.c} | ${r.items.length > 120 ? r.items.split(', ').length + ' items' : r.items} | ${r.runs} | ${r.reach} | ${r.recall} | ${r.precision} | ${r.forbidden} | ${r.unavailable} | ${r.fields} | ${r.wrong} | ${r.honest} | ${r.partial} | ${r.consistent} |`),
  '', '## Per item (first repeat)', '',
  '| item | status | reached | proposed | missed | wrong | refused by code or the second look (why) | sent to the model | pages read (first repeat) | fields wrong | reason |', '|---|---|---|---|---|---|---|---|---|---|---|',
  ...R.map((r) => { const x = r.runs[0], p = r.per[0];
    return `| ${r.id} | ${x.status} | ${p.reached}/${p.reach_gold} | ${x.codes.join(' ') || '-'} | ${r.gold.filter((c: string) => !x.codes.includes(c)).join(' ') || '-'} | ${p.forbidden.join(' ') || '-'} | ${(x.rejected ?? []).map((j: any) => j.code + ': ' + j.why.slice(0, 60)).join('; ').replace(/|/g, '/') || '-'} | ${x.sent_kind ? x.sent_kind + ' ' + x.sent_pages + ' pages' : x.model_chars ? x.model_chars + ' characters' : '-'} | ${x.first_pass ? x.first_pass + ' in run 1, all after ' + x.passes + ' runs' : x.pages_read ?? 'all'} | ${p.fields.filter((f: any) => !f.ok).map((f: any) => f.k + (f.wrong ? ' (WRONG)' : '')).join(', ') || '-'} | ${String(x.reason ?? '').replace(/\|/g, '/').slice(0, 110)} |`; }),
].join('\n');
await Deno.writeTextFile(outPath.replace(/\.json$/, '.md'), md + '\n');
console.log(md.split('\n').slice(0, 6 + rows.length).join('\n'));
console.log(`-> ${outPath}`);
