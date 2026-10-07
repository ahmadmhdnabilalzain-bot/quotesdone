// scripts/e2e/document_intake_score.mjs — the MEASURING half of the document intake accuracy suite.
// Assigned: sales_engineer; it_engineer (harness). Pure: no network, no database. Imported by
// document_intake_accuracy.mjs and by its own check (scripts/checks/document_intake_accuracy_scores_honestly.test.mjs).
//
// THE RULES OF THE COUNT (the founder's gate, ledger 1162: "not a single mistake")
//   correct  the value read equals the truth (dates as ISO, names and forms case/punctuation-blind, a licence number
//            space/case-blind, an authority through one canonical list, activities as a set)
//   held     the truth is printed and nothing was read: the field is HELD, never guessed. Safe, but not correct.
//   wrong    a value was read and it is not the truth, or a value was read where the document prints none.
//            Every wrong is a failure, whatever the field.
//   n/a      the document prints no such field and nothing was read.
// The gate is correct when its reason is the reason the truth calls for; it is UNSAFE when it approves a licence the
// truth says must be held, or approves on a wrong reading of the name, number or expiry.
// The match is correct when a request in a trade reaches exactly the demo suppliers that truly do that trade: an
// EXTRA supplier is a wrong match (never acceptable: exact trade or none); a MISSING one is a hold when the supplier
// was held at the gate or its document named nothing readable, and a failure otherwise.

export const FIELDS = ['licence_no', 'legal_name_en', 'legal_name_ar', 'trade_name', 'activities', 'authority', 'legal_form', 'issue_date', 'expiry_date', 'emirate'];
export const CRITICAL = ['licence_no', 'legal_name_en', 'expiry_date'];

const AUTH = [
  [/economy and tourism|\bdet\b/i, 'Dubai Department of Economy and Tourism'],
  [/abu dhabi global market|\badgm\b/i, 'Abu Dhabi Global Market Registration Authority'],
  [/abu dhabi.*(economic development|\bded\b)|\badded\b|department of economic development.*abu dhabi|دائرة التنمية الاقتصادية.*أبوظبي/i, 'Abu Dhabi Department of Economic Development'],
  [/ras al khaimah economic zone|\brakez\b/i, 'Ras Al Khaimah Economic Zone Authority'],
  [/ras al khaimah.*(economic development|\bded\b)|\brak ded\b/i, 'Ras Al Khaimah Department of Economic Development'],
  [/sharjah media city|\bshams\b/i, 'Sharjah Media City Authority'],
  [/sharjah.*economic development|\bsedd\b/i, 'Sharjah Economic Development Department'],
  [/ajman.*economic development|عجمان/i, 'Ajman Department of Economic Development'],
  [/umm al quwain.*economic development|\buaq\b/i, 'Umm Al Quwain Department of Economic Development'],
  [/fujairah.*(industry|economy|economic)|الفجيرة/i, 'Fujairah Department of Industry and Economy'],
  [/jebel ali|\bjafza\b/i, 'Jebel Ali Free Zone Authority'],
  [/multi commodities|\bdmcc\b/i, 'Dubai Multi Commodities Centre Authority'],
  [/airport free ?zone|\bdafza\b/i, 'Dubai Airport Free Zone Authority'],
  [/silicon oasis|\bdso\b|\bdsoa\b/i, 'Dubai Silicon Oasis Authority'],
  [/international free zone|\bifza\b/i, 'International Free Zone Authority'],
  [/meydan/i, 'Meydan Free Zone'],
  [/international financial centre|\bdifc\b/i, 'Dubai International Financial Centre Registrar of Companies'],
  [/dubai.*economic development|\bdubai ded\b/i, 'Dubai Department of Economic Development'],
];
export const canonAuthority = (s) => { if (s == null || s === '') return null; for (const [re, c] of AUTH) if (re.test(String(s))) return c; return String(s).trim(); };
const normName = (s) => String(s).toLowerCase().replace(/&/g, ' and ').replace(/[.,،'’`()\-]/g, ' ').replace(/\s+/g, ' ').trim();
const NORM = {
  licence_no: (s) => String(s).toUpperCase().replace(/\s+/g, ''),
  legal_name_en: normName, legal_name_ar: (s) => String(s).replace(/\s+/g, ' ').trim(), trade_name: normName, legal_form: normName,
  authority: canonAuthority, issue_date: String, expiry_date: String, emirate: (s) => String(s).trim().toLowerCase(),
  activities: (a) => JSON.stringify([...new Set((Array.isArray(a) ? a : String(a).split(/[,،;]/)).map(normName).filter(Boolean))].sort()),
};
const empty = (v) => v == null || v === '' || (Array.isArray(v) && v.length === 0);
export function judge(field, truth, read) {
  if (empty(truth)) return empty(read) ? 'n/a' : 'wrong';
  if (empty(read)) return 'held';
  return NORM[field](truth) === NORM[field](read) ? 'correct' : 'wrong';
}

/** The licence fields the pipeline ended with, per document: what document_intake_model.ts merged (code first). */
export function mergedReads(docs, code, model) {
  const byCode = Object.fromEntries(code.docs.map((d) => [d.id, d]));
  const byModel = Object.fromEntries((model.docs || []).map((d) => [d.id, d]));
  const out = {};
  for (const d of docs) {
    const c = byCode[d.id] || {}; const m = byModel[d.id];
    const fields = m?.merged || c.code || {};
    const trades = [...new Set([...(c.trades?.codes || []), ...(m?.model_trades || [])])].sort();
    out[d.id] = { ...Object.fromEntries(FIELDS.map((f) => [f, fields[f] ?? null])), trades, source: m?.source || {} };
  }
  return out;
}

function causeOf(d, field, verdict, merged, c, m) {
  const src = merged.source?.[field] || (c?.code?.[field] != null ? 'code' : (m?.doc ? 'model' : null));
  if (verdict === 'held') {
    if (!d.file) return 'no document';
    if (d.text_layer && c?.code && c.code[field] == null && !m?.asked) return 'code did not read this label/layout, and the model was not asked';
    if (!d.text_layer && !m?.asked) return 'no text layer (scan/photo) and no model read (process_docs model switch off)';
    if (m?.asked && !m.ok) return `model asked, no answer: ${String(m.error || '').slice(0, 90)}`;
    if (m?.asked) return 'model asked, returned nothing for this field';
    return 'not read';
  }
  return `${src || '?'} read ${JSON.stringify(merged[field])}`;
}

export function scoreRun({ docs, code, model, merged, probe, label, spend, gateSql, left, runTag }) {
  const byCode = Object.fromEntries(code.docs.map((d) => [d.id, d]));
  const byModel = Object.fromEntries((model.docs || []).map((d) => [d.id, d]));
  const licences = docs.filter((d) => d.kind === 'licence');
  const failures = [];
  // fields
  const cells = [];   // {id, authority, format, field, verdict}
  for (const d of licences) {
    for (const f of FIELDS) {
      const v = judge(f, d.truth[f], merged[d.id][f]);
      cells.push({ id: d.id, authority: d.authority, format: d.format, text_layer: d.text_layer, field: f, verdict: v });
      if (v === 'wrong' || (v === 'held' && d.text_layer && CRITICAL.includes(f)))
        failures.push({ area: 'field', id: d.id, field: f, verdict: v, truth: d.truth[f], cause: causeOf(d, f, v, merged[d.id], byCode[d.id], byModel[d.id]) });
    }
  }
  const tally = (rows) => { const t = { correct: 0, held: 0, wrong: 0, 'n/a': 0 }; for (const r of rows) t[r.verdict]++; const n = t.correct + t.held + t.wrong; return { ...t, n, acc: n ? Math.round(1000 * t.correct / n) / 10 : null }; };
  const group = (key, rows = cells) => Object.fromEntries([...new Set(rows.map((r) => r[key]))].sort().map((k) => [k, tally(rows.filter((r) => r[key] === k))]));
  const perField = group('field');
  const perFieldReadable = group('field', cells.filter((c) => c.text_layer));
  const perAuthority = Object.fromEntries(Object.entries(group('authority')).map(([k, v]) => [k, { ...v, critical: tally(cells.filter((c) => c.authority === k && CRITICAL.includes(c.field))) }]));
  const perFormat = Object.fromEntries(Object.entries(group('format')).map(([k, v]) => [k, { ...v, critical: tally(cells.filter((c) => c.format === k && CRITICAL.includes(c.field))) }]));

  // gate
  const gateRows = [];
  const unreadFamily = new Set(['licence_unreadable', 'licence_expiry_unread', 'licence_number_unread']);
  for (const g of probe.gate) {
    const d = docs.find((x) => x.id === g.id); if (d.kind !== 'licence') continue;
    const exp = d.expected, reason = g.reason || null, approved = g.status === 'approved';
    const critWrong = CRITICAL.filter((f) => judge(f, d.truth[f], merged[d.id][f]) === 'wrong');
    let verdict;
    if (exp === 'approve') verdict = reason == null ? (critWrong.length ? 'UNSAFE' : 'correct') : unreadFamily.has(reason) ? 'held' : 'wrong';
    // ruling 1176: a read licence name that differs becomes the company name, and the gate approves
    else if (exp === 'name_autofilled') verdict = reason == null && g.status === 'approved' && normName(g.company_name || '') === normName(d.truth.legal_name_en)
      ? (critWrong.length ? 'UNSAFE' : 'correct') : approved ? 'wrong' : unreadFamily.has(reason) ? 'held' : 'wrong';
    else if (exp === 'hold_name') verdict = ['licence_unreadable', 'licence_name_mismatch'].includes(reason) ? 'correct' : approved ? 'UNSAFE' : 'wrong';
    // a licence that must be held and WAS held because a field could not be read is held safely (its own reason was unreadable)
    else verdict = reason === exp ? 'correct' : (approved || reason == null) ? 'UNSAFE' : unreadFamily.has(reason) ? 'held' : 'wrong';
    gateRows.push({ id: d.id, authority: d.authority, format: d.format, expected: exp, status: g.status, reason, verdict, critical_wrong: critWrong, company_name: g.company_name });
    if (verdict !== 'correct') failures.push({ area: 'gate', id: d.id, verdict, expected: exp, got: `${g.status}${reason ? ' (' + reason + ')' : ''}`,
      cause: critWrong.length ? `approved on a wrong reading of ${critWrong.join(', ')}` : verdict === 'held' ? `held: ${reason} (${CRITICAL.filter((f) => judge(f, d.truth[f], merged[d.id][f]) === 'held').join(', ') || 'see fields'} not read)` : `expected ${exp}` });
  }
  const gateTally = { correct: 0, held: 0, wrong: 0, UNSAFE: 0 }; for (const r of gateRows) gateTally[r.verdict]++;

  // match
  const leadDoc = Object.fromEntries(probe.gate.map((g) => [g.lead, g.id]));
  const gateOf = Object.fromEntries(probe.gate.map((g) => [g.id, g]));
  const matchRows = [];
  for (const [trade, leads] of Object.entries(probe.match)) {
    const got = new Set(leads.map((l) => leadDoc[l]));
    const want = new Set(docs.filter((d) => ['licence', 'profile', 'catalogue'].includes(d.kind) && (d.truth.trades || []).includes(trade)
      && (d.kind !== 'licence' || ['approve', 'name_autofilled'].includes(d.expected))).map((d) => d.id));
    const extra = [...got].filter((x) => !want.has(x)), missing = [...want].filter((x) => !got.has(x));
    const missHeld = missing.filter((x) => gateOf[x]?.reason || !merged[x].trades.length);
    const missWrong = missing.filter((x) => !missHeld.includes(x));
    matchRows.push({ trade, expected: want.size, reached: got.size, extra, missing_held: missHeld, missing_wrong: missWrong });
    for (const x of extra) failures.push({ area: 'match', id: x, trade, verdict: 'EXTRA', cause: `reached by a ${trade} request it does not do (proposed ${JSON.stringify(merged[x].trades)}, truth ${JSON.stringify(docs.find((d) => d.id === x).truth.trades)})` });
    for (const x of missWrong) failures.push({ area: 'match', id: x, trade, verdict: 'MISSING', cause: `not reached by a ${trade} request (proposed ${JSON.stringify(merged[x].trades)})` });
  }
  // trade proposals per document (licence activities, profiles, catalogue)
  const tradeRows = docs.filter((d) => ['licence', 'profile', 'catalogue'].includes(d.kind) && d.file).map((d) => {
    const t = new Set(d.truth.trades || []), p = new Set(merged[d.id].trades);
    return { id: d.id, kind: d.kind, format: d.format, truth: [...t], proposed: [...p], wrong: [...p].filter((x) => !t.has(x)), missing: [...t].filter((x) => !p.has(x)), status: byCode[d.id]?.trades?.status };
  });
  for (const r of tradeRows) if (r.wrong.length) failures.push({ area: 'trades', id: r.id, verdict: 'wrong', cause: `proposed ${r.wrong.join(', ')} which the document does not do`,
    evidence: (byCode[r.id]?.trades?.hits || []).filter((h) => r.wrong.includes(h.code)).map((h) => `${h.via} "${h.snippet}" -> ${h.phrases.join('/')}`) });
  // certificates: the expiry only
  const certRows = docs.filter((d) => ['vat_cert', 'iso_cert'].includes(d.kind)).map((d) => ({ id: d.id, truth: d.truth.expiry_date, read: byCode[d.id]?.code?.expiry_date ?? null,
    verdict: judge('expiry_date', d.truth.expiry_date, byCode[d.id]?.code?.expiry_date ?? null) }));
  for (const r of certRows) if (r.verdict === 'wrong' || r.verdict === 'held') failures.push({ area: 'certificate', id: r.id, verdict: r.verdict, cause: `expiry read ${r.read}, truth ${r.truth}` });

  return { label, run_tag: runTag, measured_at: new Date().toISOString(), model_via: model.via || 'none (process_docs model switch off)', spend, gate_sql: gateSql, leftovers: left,
    corpus: { documents: docs.length, licences: licences.length, readable_licences: licences.filter((d) => d.text_layer).length },
    perField, perFieldReadable, perAuthority, perFormat, gate: { tally: gateTally, rows: gateRows }, match: matchRows, trades: tradeRows, certificates: certRows, failures };
}

const pct = (t) => (t.acc == null ? '–' : `${t.acc}%`);
export function renderReport(r) {
  const L = [];
  L.push(`# Supplier document intake accuracy — ${r.label}`, '', `Measured ${r.measured_at} · model: ${r.model_via}${r.spend ? ` · model spend ${r.spend.calls} calls, AED ${r.spend.aed}` : ''}${r.gate_sql?.length ? ` · gate measured with ${r.gate_sql.join(', ')} (inside the rolled-back probe)` : ''}`,
    `Corpus: ${r.corpus.documents} synthetic documents, ${r.corpus.licences} licences (${r.corpus.readable_licences} with a text layer). Leftover rows after the rollback: leads ${r.leftovers?.leads}, storage ${r.leftovers?.objects}.`, '');
  const gt = r.gate.tally;
  const extra = r.match.reduce((s, m) => s + m.extra.length, 0), mwrong = r.match.reduce((s, m) => s + m.missing_wrong.length, 0);
  const fw = Object.values(r.perField).reduce((s, t) => s + t.wrong, 0);
  L.push('## Verdict', '', `| measure | result |`, `|---|---|`,
    `| gate decisions correct | ${gt.correct}/${r.gate.rows.length} · held safely ${gt.held} · wrong reason ${gt.wrong} · **UNSAFE approvals ${gt.UNSAFE}** |`,
    `| licence no. / name / expiry on readable licences | ${CRITICALS(r.perFieldReadable)} |`,
    `| any field read WRONG (guessed) | ${fw} |`,
    `| trade proposals wrong (not exact) | ${r.trades.reduce((s, t) => s + t.wrong.length, 0)} · missed ${r.trades.reduce((s, t) => s + t.missing.length, 0)} |`,
    `| match: wrong supplier reached | ${extra} · right supplier missed (not held) ${mwrong} |`, '');
  L.push('## Per field (all licences / text-layer licences)', '', '| field | correct | held | wrong | accuracy | readable accuracy |', '|---|---|---|---|---|---|');
  for (const [f, t] of Object.entries(r.perField)) { const u = r.perFieldReadable[f] || {}; L.push(`| ${f} | ${t.correct} | ${t.held} | ${t.wrong} | ${pct(t)} | ${pct(u)} |`); }
  L.push('', '## Per authority (all fields · licence no./name/expiry)', '', '| authority | correct | held | wrong | accuracy | critical accuracy |', '|---|---|---|---|---|---|');
  for (const [a, t] of Object.entries(r.perAuthority)) L.push(`| ${a} | ${t.correct} | ${t.held} | ${t.wrong} | ${pct(t)} | ${pct(t.critical)} |`);
  L.push('', '## Per format', '', '| format | correct | held | wrong | accuracy | critical accuracy |', '|---|---|---|---|---|---|');
  for (const [a, t] of Object.entries(r.perFormat)) L.push(`| ${a} | ${t.correct} | ${t.held} | ${t.wrong} | ${pct(t)} | ${pct(t.critical)} |`);
  L.push('', '## Gate decisions (fn_sales_engineer_verifies_supplier)', '', '| document | format | expected | got | verdict |', '|---|---|---|---|---|');
  for (const g of r.gate.rows) L.push(`| ${g.id} | ${g.format} | ${g.expected} | ${g.status}${g.reason ? ' (' + g.reason + ')' : ''}${g.expected === 'name_autofilled' ? ' · name now "' + g.company_name + '"' : ''} | ${g.verdict} |`);
  L.push('', '## Trades proposed from the documents (exact trade or none)', '', '| document | kind | truth | proposed | wrong | missed |', '|---|---|---|---|---|---|');
  for (const t of r.trades) L.push(`| ${t.id} | ${t.kind} | ${t.truth.join(', ')} | ${t.proposed.join(', ') || (t.status === 'needs_ocr' ? '(no text layer)' : '–')} | ${t.wrong.join(', ')} | ${t.missing.join(', ')} |`);
  L.push('', '## Matching probe (fn_match_capability, one request per trade)', '', '| trade | should reach | reached | wrong supplier | missed (held) | missed: named, no exact trade |', '|---|---|---|---|---|---|');
  for (const m of r.match) L.push(`| ${m.trade} | ${m.expected} | ${m.reached} | ${m.extra.join(', ')} | ${m.missing_held.length} | ${m.missing_wrong.join(', ')} |`);
  L.push('', '## Certificates (expiry only)', '', '| document | truth | read | verdict |', '|---|---|---|---|');
  for (const c of r.certificates) L.push(`| ${c.id} | ${c.truth} | ${c.read} | ${c.verdict} |`);
  L.push('', `## Every failure and its cause (${r.failures.length})`, '');
  for (const f of r.failures) L.push(`- **${f.area}** \`${f.id}\`${f.field ? ' ' + f.field : ''}${f.trade ? ' ' + f.trade : ''}: ${f.verdict}${f.expected ? ` (expected ${f.expected}, got ${f.got})` : ''}${f.truth !== undefined ? ` — truth ${JSON.stringify(f.truth)}` : ''} — ${f.cause}${f.evidence?.length ? ' — ' + f.evidence.join('; ') : ''}`);
  return L.join('\n') + '\n';
}
function CRITICALS(per) { return ['licence_no', 'legal_name_en', 'expiry_date'].map((f) => `${f} ${pct(per[f] || {})}`).join(' · '); }
