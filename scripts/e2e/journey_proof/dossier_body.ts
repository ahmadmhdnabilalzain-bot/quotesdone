// scripts/e2e/journey_proof/dossier_body.ts — ONE JOURNEY'S DOSSIER as the body pdf_native's renderer takes. Pure: the
// record in, the document body out; dossier.ts renders it through supabase/functions/pdf_native/render.ts (the one
// QuotesDone template, _shared/doc_template.ts) and appends the evidence files after it. Seat: customer_support.
//
// The founder, 13 Nov 2026 (ledger 1684): "you didn't share with me the PDFs actually that are proving the journey, how it
// happened ... Not just you test by code and tell me it's fine." So the dossier is written for him, not for an engineer:
// each of the ten steps he named, in order, with the evidence itself (the screens, the chat, the documents) and a line
// that says what was expected and what happened. Never "passed". Where the platform does not produce something he asked
// to see, the dossier says "The platform does not produce this" and does not fill the hole with something of ours.
//
// Every value comes from the record (record.mjs documents its shape). Images and page numbers are handed in by the caller,
// so this file reads nothing and the same record always gives the same document.
import { scanNote } from './dossier_words.ts';

// deno-lint-ignore no-explicit-any
type Any = any;
export type Img = { bytes: Uint8Array; kind: 'png' | 'jpg' } | null;
export type Ctx = { img: (file: string) => Img; pageOf: (file: string) => number | null; exhibitNo: (file: string) => number | null };

const TITLES: Record<string, string> = {
  s1: 'The customer exists: how he signed up, and his signed terms',
  s2: 'The inquiry as it was made',
  s3: 'The inquiry as it was shared with the suppliers',
  s4: 'Who was asked, and were they the right suppliers',
  s5: 'The quotations',
  s6: 'Every notification the customer received',
  s7: 'The comparison report',
  s8: 'The choice, the reveal fee, the invoice and the confirmations',
  co: 'Inside the company: who knew, and what they did',
  s9: 'Where every document of this journey is filed',
  s10: 'What went wrong, what it cost, and what was not the product',
};
// The order the dossier prints (founder 1685: inside-the-company comes after the reveal); numbers follow it.
export const ORDER = ['s1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 'co', 's9', 's10'];
const NUM = (id: string) => ORDER.indexOf(id) + 1;
const SEV: Record<string, string> = { leak: 'Anonymity leak', product: 'The product did not do it', looked_wrong: 'Looked wrong', harness: 'The test harness, not the product' };
const SEV_ORDER: Record<string, number> = { leak: 0, product: 1, looked_wrong: 2, harness: 3 };

const s = (v: unknown, d = '—') => (v == null || v === '' ? d : String(v));
const dubai = (iso: unknown) => {
  if (!iso) return '—';
  const d = new Date(String(iso)); if (isNaN(d.getTime())) return String(iso);
  const t = new Date(d.getTime() + 4 * 3600 * 1000);
  return `${t.toISOString().slice(0, 10)} ${t.toISOString().slice(11, 19)}`;
};
const hhmmss = (iso: unknown) => (iso ? dubai(iso).slice(11) : '—');
const bytesWords = (n: unknown) => { const b = Number(n); if (!isFinite(b) || b <= 0) return '—'; return b >= 1048576 ? `${(b / 1048576).toFixed(2)} MB (${b.toLocaleString('en-US')} bytes)` : `${(b / 1024).toFixed(1)} KB (${b.toLocaleString('en-US')} bytes)`; };
const usd = (n: unknown) => `USD ${(Number(n) || 0).toFixed(4)}`;

export function dossierBody(rec: Any, ctx: Ctx) {
  const B: Any[] = [];
  const J = rec.journey || {};
  const S = rec.sections || {};
  const stubbed = J.mode === 'stubbed';
  const leaks = countLeaks(rec);

  const p = (text: string, o: Any = {}) => B.push({ t: 'p', text, ...o });
  const note = (text: string) => B.push({ t: 'note', text });
  const h3 = (text: string) => B.push({ t: 'h3', text });
  const kv = (pairs: [string, unknown][]) => B.push({ t: 'kv', pairs: pairs.map(([k, v]) => [k, s(v)]) });
  const table = (head: string[], rows: unknown[][], o: Any = {}) => B.push({ t: 'table', head, rows: rows.map((r) => r.map((c) => (c && typeof c === 'object' ? c : s(c)))), zebra: true, ...o });
  const callout = (title: string, text: string, tone: 'teal' | 'gold' | 'grey') => B.push({ t: 'callout', title, text, tone });
  const image = (file: string, w: number, caption?: string) => {
    const im = file ? ctx.img(file) : null;
    if (im) B.push({ t: 'image', bytes: im.bytes, kind: im.kind, w });
    else if (file) note(`(The picture ${file} is missing from this run's folder.)`);
    if (caption) note(caption);
  };
  const exhibit = (file: string | null | undefined, what: string) => {
    if (!file) return;
    const n = ctx.exhibitNo(file), pg = ctx.pageOf(file);
    B.push({ t: 'link', text: n ? `Exhibit ${n}${pg ? ` (page ${pg})` : ''}: ${what}` : `${what}: ${file} (in the run's folder beside this dossier)` });
  };
  const verdicts = (sec: Any) => {
    for (const v of sec?.verdicts || []) {
      const tone = v.as_expected === true ? 'teal' : v.as_expected === false ? 'gold' : 'grey';
      const head = v.as_expected === true ? 'As expected' : v.as_expected === false ? 'NOT as expected' : 'Not judged by the run';
      callout(head, `Expected: ${s(v.expected).replace(/\.$/, '')}.  What happened: ${s(v.happened).replace(/\.$/, '')}.`, tone);
    }
  };
  const gaps = (sec: Any) => { for (const g of sec?.gaps || []) callout('The platform does not produce this', String(g), 'grey'); };
  // the running column (founder 1685): which seat was told during this step, from the rows the run produced
  const company = (id: string) => {
    const ev = (rec.sections?.co?.by_step || {})[id];
    if (!ev) return;
    if (!ev.length) { note('Inside the company during this step: nobody in the company was told (no event, task or hand-over row was written).'); return; }
    table(['Time', 'Handed over: who -> whom, what', 'Picked up?', 'Sender told outcome?'], ev.slice(0, 12).map((e: Any) => [hhmmss(e.at), `${e.what}: ${s(e.from)} -> ${s(e.to)}`, s(e.picked), s(e.back)]), { widths: [0.1, 0.44, 0.22, 0.24], fs: 7 });
    if (ev.length > 12) note(`... and ${ev.length - 12} more (all in section ${NUM('co')}).`);
  };
  const section = (_n: number, id: string) => B.push({ t: 'section', n: NUM(id), text: TITLES[id] });
  const endSection = (id: string) => company(id);

  // ── page 1: what this is ──
  if (String(J.mode || '').startsWith('dry')) callout('DRY RUN: THE MODELS WERE OFF', 'No model was called and nothing was spent. Everything that needs a model could not happen and is EMPTY for that reason, not because the product failed: the sales engineer\'s replies in the chat (so the chat stops at its first question and the request is never sent by the customer), reading his files, the platform choosing the suppliers, reading the suppliers\' quotations, and the written comparison. To walk the other doors, the test wrote the request itself and invited the suppliers itself; each place this happened says so.', 'gold');
  if (stubbed) callout('FORM ONLY: STUBBED DATA', 'Nothing in this sample happened on the live site. It shows the shape of the dossier the real run will produce, filled with invented ZZ DEMO data and with documents drawn by the product\'s own document builders on invented inputs. No model was called, no money was spent and no person was contacted.', 'gold');
  p(`This is the proof of one journey through QuotesDone, told in the order it happened: ${s(J.how_made)}. Each of the ten steps shows the evidence itself (the screens as the person saw them, the chat as it was said, the documents as they were issued) and one line that says what we expected and what happened. Where the platform does not produce something, the dossier says so and leaves the hole visible.`);
  p('Pictures marked "phone" were taken at iPhone size in a browser with no test tampering: no request was altered or added by the test while the picture was taken. The documents (the signed terms, the inquiry, each quotation, the comparison, the invoice) follow this report as exhibits, exactly as the platform issued them, unaltered.', { muted: true });
  kv([['Journey', J.title], ['Run tag (marks every demo record of this run)', J.run_tag], ['Site', J.site], ['Started (Dubai time)', dubai(J.started)], ['Finished (Dubai time)', dubai(J.finished)], ['Spending cap for this journey', J.cap_usd != null ? `USD ${J.cap_usd}` : '—']]);
  if (leaks.total) callout(`${leaks.total} ANONYMITY LEAK${leaks.total > 1 ? 'S' : ''} FOUND`, `Identifying details reached the other party before the reveal. Each is printed in plain words in step ${leaks.where.join(' and ')}.`, 'gold');

  // ── 1 the customer ──
  const s1 = S.s1 || {}; section(1, 's1');
  kv([['Customer (demo identity)', s1.customer?.name], ['E-mail', s1.customer?.email], ['Mobile', s1.customer?.phone], ['Where the job is (as he told us)', s1.customer?.site]]);
  h3('How he signed up');
  p(s(s1.signup?.door, 'The sign-up door used was not recorded.'));
  if (s1.signup?.steps?.length) table(['Time (Dubai)', 'What he did', 'What the site did'], s1.signup.steps.map((x: Any) => [hhmmss(x.at), x.what, x.result]), { widths: [0.16, 0.38, 0.46] });
  for (const sh of s1.signup?.sheets || []) image(sh.file, 400, sh.caption);
  for (const nr of s1.signup?.not_real || []) callout('Not the product in this step', String(nr), 'grey');
  h3('His signed terms');
  const t = s1.terms || {};
  kv([['Terms accepted', t.version], ['Accepted at (Dubai)', dubai(t.accepted_at)], ['Certificate file', t.certificate?.file], ['Certificate size', bytesWords(t.certificate?.bytes)]]);
  exhibit(t.certificate?.file, 'the signed-terms certificate itself, as the platform stored it');
  table(['Where', 'Path', 'Size', 'Fingerprint (SHA-256 / Dropbox content hash)'], [
    ['Supabase storage', `${s(t.storage?.bucket)} / ${s(t.storage?.path)}`, bytesWords(t.storage?.bytes), s(t.storage?.sha256)],
    ['Dropbox', s(t.dropbox?.path), bytesWords(t.dropbox?.size), `${s(t.dropbox?.content_hash)}${t.dropbox?.local_content_hash ? (t.dropbox.local_content_hash === t.dropbox.content_hash ? '  (equals the hash of the certificate above)' : '  (DIFFERS from the certificate above: ' + t.dropbox.local_content_hash + ')') : ''}`],
  ], { widths: [0.15, 0.4, 0.17, 0.28], fs: 7.4 });
  if (t.dropbox?.where_demo_files_go) note(t.dropbox.where_demo_files_go);
  verdicts(s1); gaps(s1); endSection('s1');

  // ── 2 the inquiry as made ──
  const s2 = S.s2 || {}; section(2, 's2');
  p(s(s2.how, ''));
  if (s2.turns?.length) {
    table(['Time', 'Who', 'What was said', 'Reply took'], s2.turns.map((x: Any) => [hhmmss(x.at), x.role === 'customer' ? 'Customer' : x.role === 'sales engineer' ? 'Sales engineer' : x.role, x.text + (x.options?.length ? `  [answer buttons: ${x.options.join(' | ')}]` : ''), x.reply_s != null ? `${x.reply_s} s` : '']), { widths: [0.11, 0.15, 0.62, 0.12], fs: 7.8 });
  } else p('No chat was recorded.');
  if (s2.questions?.length) {
    h3('Every question the sales engineer asked, and why');
    table(['#', 'The question', 'Why it asked (its own words, where the platform gives them)'], s2.questions.map((q: Any, i: number) => [String(i + 1), q.text, s(q.why, 'The platform does not say why it asked this.')]), { widths: [0.06, 0.5, 0.44], fs: 7.8 });
  }
  for (const v of s2.voice_notes || []) {
    h3(`Voice note: ${s(v.file)} (${s(v.seconds)} s)`);
    kv([['What the customer said (the script the voice was made from)', v.script], ['What the platform heard (its transcription)', v.heard]]);
  }
  for (const a of s2.attachments || []) {
    h3(`The file he gave: ${s(a.file)}`);
    exhibit(a.file, 'the file exactly as the customer gave it');
    kv([['What the sales engineer read from it', a.reading?.summary], ['Did it judge the file sufficient to quote from?', a.sufficient]]);
    if (a.reading?.lines?.length) table(['Line', 'What it read', 'Qty', 'Unit'], a.reading.lines.slice(0, 40).map((l: Any, i: number) => [String(i + 1), s(l.description), s(l.qty), s(l.unit)]), { widths: [0.08, 0.66, 0.12, 0.14], fs: 7.6 });
    if (a.reading?.missing?.length) { p('What it said was missing:', { bold: true }); for (const m of a.reading.missing) B.push({ t: 'li', text: String(m) }); }
    if (a.sales_engineer_after) kv([['What the sales engineer said next in the chat', a.sales_engineer_after]]);
    if (a.prices_passed_on != null) callout(a.prices_passed_on ? 'The old supplier\'s PRICES reach the new suppliers' : 'The old supplier\'s prices do NOT reach the new suppliers', String(a.prices_note || ''), a.prices_passed_on ? 'gold' : 'teal');
  }
  for (const sh of s2.sheets || []) image(sh.file, 400, sh.caption);
  if (s2.stored) note(`Stored by the platform: ${s2.stored}`);
  verdicts(s2); gaps(s2); endSection('s2');

  // ── 3 the inquiry as shared ──
  const s3 = S.s3 || {}; section(3, 's3');
  exhibit(s3.inquiry_pdf, 'the inquiry exactly as a supplier receives it (supplier portal, "Download PDF")');
  if (s3.documents?.length) table(['File the supplier can open', 'What it is'], s3.documents.map((d: Any) => [d.name, d.what]), { widths: [0.45, 0.55] });
  for (const sh of s3.sheets || []) image(sh.file, 400, sh.caption);
  for (const m of s3.messages || []) message(m);
  anonymity(s3.anonymity, 'supplier');
  verdicts(s3); gaps(s3); endSection('s3');

  // ── 4 who was asked ──
  const s4 = S.s4 || {}; section(4, 's4');
  const mv = s4.verdict || {};
  if (s4.fixtures?.length) {
    const asked = new Map((mv.asked || []).map((a: Any) => [String(a.lead_id), a]));
    table(['Demo supplier', 'Trade', 'Serves', 'Should be asked?', 'Asked by the platform?', "The platform's reason"],
      s4.fixtures.map((f: Any) => { const a: Any = asked.get(String(f.lead_id)); return [f.label, f.trade, (f.emirates || []).join(', '), f.should === 'right' ? 'Yes' : `No (${String(f.should).replace('_', ' ')})`, a ? 'ASKED' : 'not asked', a ? s(a.reason) : '']; }),
      { widths: [0.2, 0.12, 0.14, 0.14, 0.12, 0.28], fs: 7.2 });
  }
  const outside = (mv.asked || []).filter((a: Any) => !(s4.fixtures || []).some((f: Any) => String(f.lead_id) === String(a.lead_id)));
  if (outside.length) table(['Also asked (not one of this run\'s suppliers)', 'Kind', "The platform's reason"], outside.map((a: Any) => [s(a.label || a.company), a.should === 'REAL' ? 'A REAL SUPPLIER' : 'a demo supplier of another run', s(a.reason)]), { widths: [0.35, 0.25, 0.4], fs: 7.4 });
  kv([['Right suppliers asked', `${(mv.right_asked || []).length} of ${(s4.fixtures || []).filter((f: Any) => f.should === 'right').length}`], ['Wrong suppliers asked', String((mv.wrong_asked || []).length)], ['Right suppliers missed', (mv.right_missed || []).map((f: Any) => f.label).join(', ') || 'none'], ['Real suppliers asked', String((mv.real_supplier_asked || []).length)]]);
  if ((mv.added_by_test || []).length) callout('Added by the test, NOT chosen by the platform', `${mv.added_by_test.map((a: Any) => a.label).join(', ')}: the test invited ${mv.added_by_test.length > 1 ? 'these suppliers' : 'this supplier'} itself so that quotations could be shown. ${mv.added_by_test.length > 1 ? 'They are' : 'It is'} not evidence that the platform chose well.`, 'gold');
  verdicts(s4); gaps(s4); endSection('s4');

  // ── 5 quotations ──
  const s5 = S.s5 || {}; section(5, 's5');
  if (!s5.quotes?.length) p('No quotation reached this step.');
  for (const q of s5.quotes || []) {
    h3(`${s(q.label)}${q.letter ? ` (shown to the customer as "${q.letter}")` : ''}`);
    exhibit(q.own_file, 'his own quotation, as he sent it, with his identity on it');
    kv([['How it went through the platform', q.path], ['Price the platform read (ex VAT)', q.read?.amount != null ? `AED ${Number(q.read.amount).toLocaleString('en-US', { minimumFractionDigits: 2 })}` : '—'], ['Lines read', q.read?.lines], ['Read by', q.read?.read_by], ['Identity details masked when read', (q.read?.masked || []).join(', ') || 'none named']]);
    exhibit(q.customer_pdf, 'the same quotation as the CUSTOMER sees it, on our template');
    for (const sh of q.sheets || []) image(sh.file, 400, sh.caption);
    anonymity(q.anonymity, 'customer');
  }
  verdicts(s5); gaps(s5); endSection('s5');

  // ── 6 notifications ──
  const s6 = S.s6 || {}; section(6, 's6');
  if (!s6.notifications?.length) p('The platform composed no notification to the customer in this journey.');
  else {
    table(['Time (Dubai)', 'Channel', 'What it was about', 'State'], s6.notifications.map((n: Any) => [dubai(n.at).slice(5), n.channel, s(n.subject || n.type), n.state]), { widths: [0.2, 0.14, 0.46, 0.2], fs: 7.6 });
    for (const n of s6.notifications) message(n);
  }
  verdicts(s6); gaps(s6); endSection('s6');

  // ── 7 comparison ──
  const s7 = S.s7 || {}; section(7, 's7');
  exhibit(s7.pdf, 'the comparison report exactly as the customer downloads it');
  if (s7.top?.length) table(['Rank', 'Quotation', 'Price', 'Why the platform ranked it here'], s7.top.map((x: Any) => [`#${x.rank}`, s(x.label), s(x.price), s(x.why, 'The platform gives no reason.')]), { widths: [0.08, 0.18, 0.16, 0.58], fs: 7.6 });
  for (const sh of s7.sheets || []) image(sh.file, 400, sh.caption);
  verdicts(s7); gaps(s7); endSection('s7');

  // ── 8 reveal ──
  const s8 = S.s8 || {}; section(8, 's8');
  kv([['The customer chose', s8.chosen], ['Reveal fee', s8.fee], ['Paid with', s8.paid_with], ['Paid at (Dubai)', dubai(s8.paid_at)], ['Payment record', s8.payment_state], ['Stripe mode', s8.mode]]);
  exhibit(s8.invoice_pdf, 'the invoice exactly as the customer receives it');
  if (s8.revealed?.length) table(['Who', 'What was revealed to him'], s8.revealed.map((r: Any) => [r.who, r.sees]), { widths: [0.25, 0.75] });
  for (const sh of s8.sheets || []) image(sh.file, 400, sh.caption);
  for (const m of s8.confirmations || []) message(m);
  verdicts(s8); gaps(s8); endSection('s8');
  if (s8.vat) {
    h3('The fee and VAT');
    note('Founder ruling 1687: the reveal fee is calculated on the quotation\'s total EXCLUDING VAT. VAT is the supplier\'s; QuotesDone collects none.');
    const v = s8.vat;
    table(['', 'AED'], [['The chosen quotation, total excluding VAT (as the platform stored it)', s(v.ex_vat)], ['VAT the supplier stated', s(v.vat_stated)], ['Total including VAT, as the supplier stated it', s(v.gross)], ['How the supplier stated his price', s(v.treatment)], ['The base the fee was calculated on', s(v.base)], [`The fee (${s(v.rate_words)})`, s(v.fee)], ['Anything else charged to the customer', s(v.processing)], ['Stripe charged the customer', s(v.charged)], ["Stripe's cost (QuotesDone's own expense)", s(v.stripe_cost)]], { widths: [0.7, 0.3], fs: 8 });
    if (v.overcharged) callout('THE CUSTOMER WAS CHARGED MORE THAN THE FEE', String(v.overcharged), 'gold');
    if (v.base_is_ex_vat === false) callout('WRONG BASE: THE FEE WAS NOT CALCULATED ON THE TOTAL EXCLUDING VAT', String(v.why || ''), 'gold');
    else if (v.base_is_ex_vat === true) note(String(v.why || 'The base is the total excluding VAT.'));
  }

  // ── inside the company (founder 1685-1688) ──
  const co = S.co || {}; section(0, 'co');
  p('From the rows this run actually produced, never from what the code intends: which seat was told, when, what it did, and whether the seat that handed over learned the outcome.', { muted: true });
  if (co.events?.length) table(['Time (Dubai)', 'Step', 'Handed over: who -> whom, what', 'Picked up?', 'Sender told?', 'Model/code'], co.events.map((e: Any) => [dubai(e.at).slice(5), e.step ? String(NUM(e.step) || e.step) : '', `${s(e.from)} -> ${s(e.to)}: ${e.what}`, s(e.picked), s(e.back), s(e.how)]), { widths: [0.13, 0.07, 0.32, 0.17, 0.18, 0.13], fs: 6.8 });
  else callout('Nobody in the company was told', 'No company event, task or hand-over row was written for this journey.', 'gold');
  for (const blk of co.after_payment || []) { h3(blk.title); if (blk.rows?.length) table(blk.head, blk.rows, { widths: blk.widths, fs: 7.4 }); if (blk.text) p(blk.text); if (blk.nobody) callout('Nobody in the company was told', blk.nobody, 'gold'); }
  verdicts(co); gaps(co);

  // ── 9 filing ──
  const s9 = S.s9 || {}; section(9, 's9');
  if (s9.supabase?.length) table(['Document', 'Supabase bucket / path', 'Size'], s9.supabase.map((f: Any) => [f.what, `${f.bucket} / ${f.path}`, bytesWords(f.bytes)]), { widths: [0.3, 0.52, 0.18], fs: 7.2 });
  if (s9.dropbox?.length) table(['Document', 'Dropbox path', 'Read back from Dropbox'], s9.dropbox.map((f: Any) => [f.what, f.path, f.verified ? `${bytesWords(f.size)}, hash ${String(f.hash || '').slice(0, 16)}…` : s(f.state, 'not read back')]), { widths: [0.26, 0.5, 0.24], fs: 7.2 });
  if (s9.listing) note(`Dropbox listing of this run's folder against the platform's own records: ${s9.listing}`);
  verdicts(s9); gaps(s9); endSection('s9');

  // ── 10 the last page ──
  const s10 = S.s10 || {}; section(10, 's10');
  const F = (rec.findings || []).map((f: Any, i: number) => ({ ...f, i })).sort((a: Any, b: Any) => (SEV_ORDER[a.severity] ?? 9) - (SEV_ORDER[b.severity] ?? 9) || a.i - b.i);
  h3('Everything that went wrong or looked wrong, most serious first');
  if (!F.length) p('Nothing was recorded as wrong in this journey.');
  else table(['#', 'How serious', 'Step', 'What happened'], F.map((f: Any, i: number) => [String(i + 1), SEV[f.severity] || f.severity, s(f.step), f.text]), { widths: [0.05, 0.19, 0.08, 0.68], fs: 7.6 });
  h3('What this journey cost (model calls, USD, from the platform\'s own cost log for this run tag)');
  const C = rec.cost || {};
  if (C.by_step?.length) table(['Step', 'Calls', 'USD', 'Which parts of the platform'], C.by_step.map((b: Any) => [b.step === 'other' ? 'other' : `${NUM(b.step) || ''}${NUM(b.step) ? '. ' : ''}${TITLES[b.step] || b.title}`, String(b.calls), usd(b.usd), Object.entries(b.fns || {}).map(([k, v]) => `${k} x${v}`).join(', ')]), { widths: [0.4, 0.08, 0.14, 0.38], fs: 7.4 });
  kv([['Total', `${usd(C.total_usd)} in ${s(C.calls, '0')} calls`], ['Estimate before the run', J.estimate_usd != null ? `USD ${J.estimate_usd}` : '—'], ['Cap for this journey', J.cap_usd != null ? `USD ${J.cap_usd}` : '—']]);
  if (C.note) note(C.note);
  h3('What in this run was NOT the product');
  for (const x of rec.stand_ins || []) B.push({ t: 'li', text: String(x) });
  verdicts(s10); gaps(s10);

  // ── the exhibits ──
  if (rec.exhibits?.length) {
    B.push({ t: 'h2', text: 'The exhibits that follow this report' });
    table(['#', 'Exhibit', 'Page', 'Why it is here'], rec.exhibits.map((e: Any, i: number) => [String(i + 1), e.title, ctx.pageOf(e.file) ? String(ctx.pageOf(e.file)) : (e.attach ? 'attached file' : '—'), s(e.why, '')]), { widths: [0.06, 0.44, 0.1, 0.4], fs: 7.6 });
    note('A PDF exhibit is bound after this report unaltered. A file that is not a PDF (a voice note, a spreadsheet, the run\'s raw record) is attached inside this PDF; on an iPhone, open the PDF in Files and tap the paperclip.');
  }

  return {
    title: `Journey ${s(J.key)} proof`,
    lang: 'en',
    cover: {
      kicker: stubbed ? 'JOURNEY PROOF - FORM ONLY (STUBBED DATA)' : 'JOURNEY PROOF',
      title: `Journey ${s(J.key)}`,
      subtitle: `${s(J.short, J.title)}: ${s(J.how_made, '')}`,
      meta: [['Run', s(J.run_tag)], ['Date (Dubai)', dubai(J.started).slice(0, 10)], ['Site', (String(J.site || '').match(/[a-z0-9.-]+\.(?:com|ae)/i) || ['—'])[0]], ['Prepared by', 'customer_support']],
      figures: [['Anonymity leaks', String(leaks.total)], ['Suppliers asked', String((S.s4?.verdict?.asked || []).length)], ['Quotations', String((S.s5?.quotes || []).length)], ['Model cost', usd(rec.cost?.total_usd)]],
    },
    blocks: B,
    options: { letterhead: true },
  };

  function message(m: Any) {
    B.push({ t: 'p', label: `${s(m.channel).toUpperCase()} to ${s(m.to)}${m.at ? ' at ' + dubai(m.at) : ''}: ${s(m.state)}`, text: `${m.subject ? m.subject + '\n\n' : ''}${s(m.text, '(no text)')}`, lines: true, size: 8.4 });
    if (m.shot) image(m.shot, 200, 'The e-mail as it was composed, drawn at phone width.');
  }
  function anonymity(a: Any, receiver: string) {
    if (!a) { callout('No anonymity check was made at this step', 'The run did not reach the point where the other party received something.', 'grey'); return; }
    h3(`Anonymity check: what the ${receiver} received`);
    note(scanNote(a, receiver));
    table(['Identifying detail that went in', 'Found in what the ' + receiver + ' received?'], (a.rows || []).map((r: Any) => [`${r.label}: ${r.value}`, r.leak ? { text: 'LEAK: ' + r.hits.map((h: Any) => h.where).join('; '), sub: r.hits[0]?.snippet, bold: true } : 'not found']), { widths: [0.42, 0.58], fs: 7.6 });
    for (const r of (a.rows || []).filter((x: Any) => x.leak)) callout(`LEAK: ${r.label}`, `"${r.value}" reached the ${receiver} before the reveal, in ${r.hits.map((h: Any) => h.where).join('; ')}. It reads: ${r.hits[0]?.snippet}`, 'gold');
  }
}

export function countLeaks(rec: Any) {
  const S = rec.sections || {};
  const where: string[] = [];
  let total = 0;
  const n3 = (S.s3?.anonymity?.rows || []).filter((r: Any) => r.leak).length; if (n3) { total += n3; where.push('3'); }
  const n5 = (S.s5?.quotes || []).reduce((a: number, q: Any) => a + (q.anonymity?.rows || []).filter((r: Any) => r.leak).length, 0); if (n5) { total += n5; where.push('5'); }
  return { total, where };
}
