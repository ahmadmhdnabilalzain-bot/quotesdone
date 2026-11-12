#!/usr/bin/env node
// LOW VS HIGH EFFORT, SIDE BY SIDE, ON RECORDED INPUTS (it_engineer, 11 Nov 2026; founder rulings 1630 and 1618).
// Ruling 1630: LOW only for simple sorting, and only where a side-by-side shows it answers as HIGH does. Until 11 Nov six
// call sites asked 'low' by literal with no such test; supabase/functions/_shared/effort_policy.ts now raises every one of
// them (provenLow false). This is the test that may flip a SORTING surface back to low. A surface that decides stays high
// whatever this shows (the intake trade, the spec reader, needs-a-person, the WhatsApp reading that carries needs-a-person).
//
//   node scripts/eval/effort_low_vs_high.mjs plan                    the cases, the expected cost and the pass rules (offline)
//   node scripts/eval/effort_low_vs_high.mjs sql [--days 30]         the READ-ONLY sampling queries (run each with the read-only role)
//   node scripts/eval/effort_low_vs_high.mjs cases --wa <30-day rows.json> --wa-wide <120-day rows.json> --portal <rows.json>
//        [--scrub <terms file>] --out <cases.json>                   the anonymised cases file (it stays OUTSIDE the repository)
//   deno run --no-lock --node-modules-dir=none -A scripts/eval/effort_low_vs_high/replay.ts --cases <cases.json> --paid [--cap 0.45]
//                                                                    the paid round (built 11 Nov 2026 by the final audit)
//
// WHAT IS REPLAYED: real inbound messages, anonymised (emails, phone numbers, names after "my name is", numbers of 6+ digits
// replaced) before they leave the read: WhatsApp inbound text (wa_messages.inbound) for the WhatsApp surfaces, the portal's
// customer messages (assistant_logs, seat sales_engineer) for the intake trade and spec reader. Synthetic traffic (user
// agents node/curl/qd-*), ZZ DEMO rows and e2e-tagged rows are excluded. Each case runs the REAL routine
// (whatsappReadings, menuMeaning, needsAPerson, tradeOf, statedSpecs, the status lane's modelSays) twice through the
// production gateway, the deps' llm forced to effort low and then high, tagged fixture so nothing is written to a person.
// PASS (per surface): the low arm chooses the same option as the high arm on >= 95% of cases (8 of 8 here: one disagreement
// fails), the status lane's low answer carries every must-carry reference and no figure the facts do not state, and the low
// arm is not slower. A surface that fails, or that the cap stopped, keeps provenLow false.
//
// WHY IT WAS NOT RUN ON THE DAY IT WAS WRITTEN (11 Nov 2026, morning): that session held no gateway credential. The final
// audit of the same day built effort_low_vs_high/replay.ts (the credential is read by scripts/eval/model_routing/harness.ts
// connect(), never printed) and ran it; the measured results are in docs/reports/2026-11-11-history-and-effort.md section 6.
//
// WHAT THE AUDIT FOUND IN THIS FILE BEFORE ANY PAID CALL, AND CHANGED (it_engineer, 11 Nov 2026):
//   - anonymise() replaced the two words after ANY "I am": "I am not sure, what do you recommend?" (8 of the 83 recorded
//     portal messages) became "I am ZZ DEMO Person, what do you recommend?", a different message. A name is now taken after
//     "I am / I'm / this is" only when it is capitalised; "my name is" and its Arabic form are unchanged.
//   - anonymise() knew no company name. 5 of the 8 WhatsApp messages of the last 30 days, and our own replies in that
//     thread, name a real supplier's two companies. Company names with a legal form are now replaced, the operator passes
//     the names a rule cannot know as scrub terms, and residualIdentity() refuses a cases file that still carries one.
//   - the 30-day WhatsApp sample is 8 messages from 2 numbers (one supplier's registration thread and a STOP): it cannot
//     exercise the menu reading, the one sorting surface a pass could lower. The menu surface therefore reads every distinct
//     recorded message of 120 days (26 texts from 4 numbers); the two that decide keep the 30-day sample.
//   - the portal sample was text only: the intake decisions read a whole conversation, so the query returns conv_id.

// USD per million tokens (fn_ai_route for customer_communication and status_reply, 11 Nov 2026: GPT-6 Luna Pro 0.10 in, 0.50
// out, 0.01 cache read; the audit's own rows agree: ai_cost_log 102244 is 21,406 in of which 6,541 cached and 423 out for
// USD 0.00176341).
export const PRICE = { in: 0.10, cached: 0.01, out: 0.50 };
// THE SHAPE OF EACH CALL, MEASURED by the paid round of 11 Nov 2026 (runs qd_run:evalefffe3428a49, evalefff2f6e4c90 and
// evaleff0db35eb5c; means per call). The figures written here before that run were estimates, 2-3x low on the prompt of the
// three WhatsApp decisions. outHigh of the two intake decisions is the mean of the high calls that ANSWERED: 4 of 12 for
// the trade, 1 of 10 for the spec reader; the others were cut at the gateway's 47 s wall with nothing written.
// cases: how many recorded inputs the surface replays (the menu surface reads every distinct recorded text, see buildCases).
// liveArm: the surface runs at medium today, so its first CASES_PER_SURFACE cases also run a medium arm.
export const SHAPE = {
  'wa_inbound.intent_table': { inTok: 28_800, cachedTok: 25_000, outLow: 470, outHigh: 1_350 },
  'wa_inbound.greeting_state': { inTok: 21_900, cachedTok: 20_300, outLow: 520, outHigh: 1_550, cases: 26, liveArm: true },
  'wa_inbound.needs_a_person': { inTok: 22_300, cachedTok: 20_300, outLow: 560, outHigh: 1_790 },
  'inquiry_intake.trade': { inTok: 24_600, cachedTok: 20_600, outLow: 1_200, outHigh: 4_500 },
  'inquiry_intake.exact_spec': { inTok: 22_800, cachedTok: 14_600, outLow: 2_000, outHigh: 5_350 },
  'wa_inbound.status_lane': { inTok: 3_800, cachedTok: 1_250, outLow: 220, outHigh: 670, liveArm: true },
};
export const CASES_PER_SURFACE = 8;
export const CAP_USD = 0.5;
export const PASS_RULES = [
  'same choice as the high arm on >= 95% of cases (with 8 cases: all 8)',
  'status lane: every must-carry reference present, no figure the facts do not state',
  'a surface that DECIDES is never lowered, whatever this shows (effort_policy.ts consequence)',
  'a failed or capped surface keeps provenLow false',
];

const cost = (s, out) => ((s.inTok - s.cachedTok) * PRICE.in + s.cachedTok * PRICE.cached + out * PRICE.out) / 1e6;
export function plan() {
  const parts = Object.entries(SHAPE).map(([surface, s]) => {
    const cases = s.cases ?? CASES_PER_SURFACE; const live = s.liveArm ? Math.min(cases, CASES_PER_SURFACE) : 0;
    // the live (medium) arm is priced between the two measured arms
    return { surface, cases, calls: cases * 2 + live,
      usd: +(cases * (cost(s, s.outLow) + cost(s, s.outHigh)) + live * cost(s, (s.outLow + s.outHigh) / 2)).toFixed(4) };
  });
  const total = +parts.reduce((n, p) => n + p.usd, 0).toFixed(4);
  return { parts, total, cap: CAP_USD, calls: parts.reduce((n, p) => n + p.calls, 0) };
}

// Each statement is run on its own (the management API answers with the last statement's rows only). The sender is a hash:
// no number leaves the read. profile_name rides only so buildCases can scrub it, and is not written to the cases file.
export const sampleSql = (days = 30) => ({
  whatsapp: `-- read-only: recorded inbound WhatsApp turns from numbers that are not fixtures, with our reply (the conversation a turn saw)
select w.id, w.created_at, md5(w.wa_from) as sender, coalesce(w.meta->>'audience', '') as audience, w.profile_name, w.inbound as text, w.reply
  from public.wa_messages w
 where w.created_at > now() - interval '${Number(days)} days' and coalesce(w.inbound, '') <> '' and w.inbound not ilike '%ZZ DEMO%'
   and w.wa_from !~ '9715000000'
 order by w.created_at desc limit 200;`,
  portal: `-- read-only: the portal's customer messages by conversation; synthetic user agents, tagged runs and ZZ DEMO rows excluded
select a.conv_id, a.created_at, a.message as text from public.assistant_logs a
 where a.created_at > now() - interval '30 days' and a.seat = 'sales_engineer' and a.e2e_run_tag is null
   and coalesce(a.user_agent, '') !~* '^(node|curl|qd-|deno|python|undici)' and a.message not ilike '%ZZ DEMO%'
 order by a.created_at desc limit 200;`,
});
export const SAMPLE_SQL = Object.values(sampleSql()).join('\n');

const LEGAL_FORM = '(?:FZE LLC|FZ-LLC|FZ LLC|L\\.L\\.C\\.?|LLC|FZE|FZCO|FZC|PJSC|PSC)';
const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** `terms`: [real text, replacement] pairs the operator read out of the sample (a company's short name, an abbreviation). */
export function anonymise(t, terms = []) {
  let s = String(t ?? '');
  // longest first, so a full name is replaced before its short form; a term of 3 letters or fewer matches its exact case only
  for (const [term, to] of [...terms].sort((a, b) => b[0].length - a[0].length)) {
    s = s.replace(new RegExp('(?<![\\p{L}\\p{N}])' + esc(term) + '(?![\\p{L}\\p{N}])', term.length <= 3 ? 'gu' : 'giu'), to);
  }
  return s
    .replace(/[\w.+-]+@(?!quotesdone\.com\b)[\w-]+(\.[\w-]+)+/g, 'person@example.invalid')   // our own published address is not a person
    .replace(/\+?\d[\d\s-]{7,}\d/g, '\u0000PHONE\u0000')
    .replace(/\b(my name is|اسمي)\s+[\p{L}'-]+(\s+[\p{L}'-]+)?/giu, '$1 ZZ DEMO Person')
    // "I am not sure" is not a name: after these, only capitalised words are one (the audit's finding, header)
    .replace(/\b(I am|I'm|I’m|this is|This is)\s+\p{Lu}[\p{L}'-]+(\s+\p{Lu}[\p{L}'-]+)?/gu, '$1 ZZ DEMO Person')
    // a company named with its legal form: "M/s <NAME> FZE LLC", "<NAME> ... TRADING LLC" (capitalised words before the form)
    .replace(new RegExp('\\b(?:\\p{Lu}[\\p{L}&.\'-]*\\s+){1,5}' + LEGAL_FORM + '(?![\\p{L}])', 'gu'), (m) => /ZZ DEMO/.test(m) ? m : 'ZZ DEMO Company LLC')
    .replace(/\b\d{6,}\b/g, '000000')
    .replace(/\u0000PHONE\u0000/g, '+971500000000');
}

/** What still looks like a real identity after anonymise(): an address, a number, a company with a legal form, a scrub term. */
export function residualIdentity(t, terms = []) {
  const s = String(t ?? ''); const out = [];
  for (const m of s.match(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g) ?? []) if (!/@(example\.invalid|quotesdone\.com)$/i.test(m)) out.push('address ' + m);
  for (const m of s.match(/\+?\d[\d\s-]{7,}\d/g) ?? []) if (m.replace(/\D/g, '') !== '971500000000') out.push('number ' + m);
  for (const m of s.match(/\b\d{6,}\b/g) ?? []) if (m !== '000000' && m !== '971500000000') out.push('digits ' + m);
  for (const m of s.match(new RegExp('(?:[\\p{L}&.\'-]+\\s+){1,4}' + LEGAL_FORM + '(?![\\p{L}])', 'gu')) ?? []) if (!/ZZ DEMO/.test(m)) out.push('company ' + m);
  for (const [term] of terms) if (new RegExp('(?<![\\p{L}\\p{N}])' + esc(term) + '(?![\\p{L}\\p{N}])', term.length <= 3 ? 'u' : 'iu').test(s)) out.push('scrub term left in');
  return out;
}

// ── the cases file ─────────────────────────────────────────────────────────────────────────────────────────────────────
// WHICH RECORDED INPUT EACH SURFACE REPLAYS. Nothing here is written by the auditor: every text is a recorded row.
//   wa_inbound.intent_table, wa_inbound.needs_a_person   the 30-day WhatsApp sample (the newest CASES_PER_SURFACE distinct
//       texts), each with the turns its sender had already exchanged, as the readings call sees them in production;
//   wa_inbound.greeting_state                             every distinct recorded text of the wide sample (at most MENU_CASES);
//   inquiry_intake.trade, inquiry_intake.exact_spec       the newest CASES_PER_SURFACE portal conversations with distinct
//       openings; the conversation is the customer's own messages joined as inquiry_intake/handle.ts joins them (allText);
//   wa_inbound.status_lane                                no status ask from a real number is on record (1 fixture row in
//       all of wa_messages), so replay.ts takes eval A's fixed ZZ DEMO status turns (scripts/eval/model_routing/cases_a.ts).
// NOT REPLAYED, and why: wa_inbound.problem_state (no recorded message ever followed "Report a problem": 0 rows),
// support.case_match (0 of 28 cases held a summary on 11 Nov, the day the case model went live), marketing_social.needs_a_person
// (it decides, and shares needs_a_person's options). Each keeps provenLow false.
export const MENU_CASES = 30;
const BUTTON_PAYLOAD = /^qd_[a-z_]+$/;
const MAX_CASE_CHARS = 400;   // a pasted alert (579 characters, 5 Aug) is not a message a menu reads
export function buildCases({ wa = [], waWide = [], portal = [], terms = [] }) {
  const profile = (rows) => [...new Set(rows.flatMap((r) => String(r.profile_name ?? '').split(/\s+/)).filter((w) => w.length >= 3))].map((w) => [w, 'ZZ DEMO']);
  const all = [...terms, ...profile([...wa, ...waWide])];
  const an = (t) => anonymise(t, all);
  const typed = (r) => !BUTTON_PAYLOAD.test(String(r.text).trim()) && String(r.text).length <= MAX_CASE_CHARS;
  const distinct = (rows) => { const seen = new Set(); return rows.filter((r) => { const k = an(r.text).trim().toLowerCase(); if (seen.has(k)) return false; seen.add(k); return true; }); };
  const role = (a) => a === 'supplier' ? 'supplier' : 'customer';
  const before = (r) => wa.filter((x) => x.sender === r.sender && x.id < r.id).sort((a, b) => a.id - b.id).slice(-12)
    .flatMap((x) => [{ role: role(x.audience), text: an(x.text) }, ...(x.reply ? [{ role: 'seat', text: an(x.reply) }] : [])]);
  const recent = distinct(wa.filter(typed)).slice(0, CASES_PER_SURFACE).map((r) => ({
    id: 'wa' + r.id, source: 'recorded WhatsApp, 30 days', audience: ['customer', 'supplier'].includes(r.audience) ? r.audience : 'unknown',
    text: an(r.text), conversation: before(r) }));
  const menu = distinct(waWide.filter(typed)).slice(0, MENU_CASES).map((r) => ({
    id: 'wa' + r.id, source: 'recorded WhatsApp, 120 days', audience: r.audience === 'supplier' ? 'supplier' : 'unknown', text: an(r.text) }));
  const byConv = new Map();
  for (const r of [...portal].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))) {
    if (!r.conv_id) continue;   // a row with no conversation id cannot be put back in its conversation
    if (!byConv.has(r.conv_id)) byConv.set(r.conv_id, []);
    byConv.get(r.conv_id).push(r);
  }
  const convs = [...byConv.values()].sort((a, b) => String(b[0].created_at).localeCompare(String(a[0].created_at)));
  const seenOpening = new Set(); const intake = [];
  for (const [n, c] of convs.entries()) {
    const opening = an(c[0].text).trim().toLowerCase();
    if (seenOpening.has(opening)) continue;
    seenOpening.add(opening);
    intake.push({ id: 'conv' + (convs.length - n), source: 'recorded portal conversation, 30 days', turns: c.length, conversation: c.map((x) => an(x.text)).join(' \n ') });
    if (intake.length >= CASES_PER_SURFACE) break;
  }
  const cases = { 'wa_inbound.intent_table': recent, 'wa_inbound.needs_a_person': recent, 'wa_inbound.greeting_state': menu,
    'inquiry_intake.trade': intake, 'inquiry_intake.exact_spec': intake };
  const left = Object.values(cases).flat().flatMap((k) => [k.text ?? '', k.conversation ?? ''].flat()
    .flatMap((x) => residualIdentity(typeof x === 'string' ? x : x.text, all)).map((why) => k.id + ': ' + why));
  if (left.length) throw new Error('the cases still carry an identity, nothing was written: ' + [...new Set(left)].join('; '));
  return { built_at: new Date().toISOString(), pools: { whatsapp_30_days: wa.length, whatsapp_120_days: waWide.length, senders_120_days: new Set(waWide.map((r) => r.sender)).size,
    portal_messages: portal.length, portal_conversations: byConv.size }, cases };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const cmd = process.argv[2];
  const opt = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] ?? null : null; };
  if (cmd === 'plan') {
    const p = plan();
    for (const x of p.parts) console.log(`${x.surface.padEnd(28)} ${String(x.cases).padStart(2)} cases, ${String(x.calls).padStart(2)} calls  USD ${x.usd.toFixed(4)}`);
    console.log(`total USD ${p.total.toFixed(4)} over ${p.calls} calls (cap ${p.cap})`);
    for (const r of PASS_RULES) console.log('PASS: ' + r);
  } else if (cmd === 'sql') {
    const q = sampleSql(Number(opt('--days') ?? 30));
    console.log(q.whatsapp + '\n\n' + q.portal);
  } else if (cmd === 'cases') {
    const { readFileSync, writeFileSync } = await import('node:fs');
    const rows = (f) => { const j = f ? JSON.parse(readFileSync(f, 'utf8')) : []; if (!Array.isArray(j)) throw new Error(f + ' is not a row array'); return j; };
    const out = opt('--out');
    if (!out || !opt('--wa') || !opt('--portal')) { console.error('usage: cases --wa <rows.json> [--wa-wide <rows.json>] --portal <rows.json> [--scrub <terms>] --out <cases.json>'); process.exit(2); }
    // the scrub file: one "real text => replacement" per line; it names real parties, so it stays outside the repository too
    const terms = opt('--scrub') ? readFileSync(opt('--scrub'), 'utf8').split('\n').map((l) => l.split('=>').map((x) => x.trim())).filter((p) => p.length === 2 && p[0] && p[1]) : [];
    const built = buildCases({ wa: rows(opt('--wa')), waWide: rows(opt('--wa-wide') ?? opt('--wa')), portal: rows(opt('--portal')), terms });
    writeFileSync(out, JSON.stringify(built, null, 1));
    console.log(JSON.stringify({ out, pools: built.pools, cases: Object.fromEntries(Object.entries(built.cases).map(([k, v]) => [k, v.length])) }));
  } else { console.error('usage: plan | sql [--days N] | cases --wa <file> --wa-wide <file> --portal <file> [--scrub <file>] --out <file>'); process.exit(2); }
}
