// scripts/e2e/live_seat_conversations.mjs — ledger 1200 (12 Oct 2026): customer-facing seats hold adaptive, expert
// conversations (the custom wardrobe from a studio photo: dimensions, shelves vs hanging, door type ...), never robotic
// yes/no, never "I don't know". Seats: customer_support (suite owner), sales_engineer (knowledge). Harness: it_engineer.
//
// THE REAL SEAT, LIVE, ON THE SURFACE THE CUSTOMER USES. Every agent turn is the DEPLOYED portal chat: the call
//   PortalShell.askAssistant makes (sales_engineer {action:'assist'}), as a signed-in ZZ DEMO customer, one fresh
//   account per conversation (ruling 1255 keeps one conversation per account). Measured 27 Oct 2026: until then this
//   harness called site_assistant with path '/me', which no portal page calls — the portal panel has called
//   sales_engineer since 9 Sep — so the suite graded a prompt the customer never meets (instrument measuring the wrong
//   subject). Ruling 1249: the homepage widget holds no job conversation, so every scenario runs in the portal.
// The reply is written by the model there (ruling 1196: no canned reply exists to be measured). Calls carry this run's
// tag and are let through only inside its capped rehearsal window; demo accounts are torn down in the finally.
//
// THE BANK is scripts/e2e/adaptive_conversation_bank.mjs (what a senior UAE estimator asks per trade, EN + Gulf Arabic,
// with the failure modes). THE CUSTOMER IS SCRIPTED, NOT A MODEL: each hidden fact is released only when the agent's
// turn asks about it. Nothing is volunteered, so the conversation measures whether the agent asks for what the trade
// needs. A summary with nothing new asked is confirmed. No spend on a simulated customer.
//
// THE GRADE, in two parts:
//   code    (every turn)  answered; no "I don't know" / "not sure" / "I'll check"; no yes/no-only reply; the reply's
//                         script is the customer's language; the first reply asks at least one question; no question
//                         about what the opening already said (told); every must-have asked (must); a wrong spec the
//                         customer stated is corrected (trap). Re-asking a fact already given is FLAGGED (reask) for
//                         the judge, not failed by code: the release patterns are too broad to fail on alone.
//   claude  (judgement)   a Claude session on the subscription reads each transcript against the scenario's `expert`
//                         list and `keeps`, and scores adaptiveness, correctness, completeness and overall 0-10
//                         (--judged <file>, never a paid judge).
//   scenario score = overall x 10 when every code gate passed, else 0. Target (ledger 1200): every one of >= 30
//   scenarios >= 95, with 0 "I don't know" and 0 yes/no-only replies.
// Every scenario below its target is a gap for the weekly audit (scripts/e2e/knowledge_gap_audit.mjs).
//
//   node scripts/e2e/live_seat_conversations.mjs run [--only a,b | --slice today | --slice 3/7] [--cap-usd 5] [--max-turns 8] [--out <dir>]
//     --slice i/n   every n-th scenario from the i-th (0-based), so n daily runs cover the whole bank; 'today' is the
//                   day of the year mod 7, the daily job's slice (the whole bank once a week inside one 2 h window a day).
//   PORTAL_ASSIST_URL=http://localhost:8000 ... run   proves a branch before deploy: sales_engineer served locally
//                                                     (deno run) against production.
//   node scripts/e2e/live_seat_conversations.mjs score --results <run.json> --judged <judged.json>
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import sharp from 'sharp';
import { internalCred, keys, BASE, q } from '../lib/demo_factory.mjs';
import { openRun, closeRun, makeDemoCustomer, read } from './fixtures.mjs';
import { S, R, PHOTOS } from './adaptive_conversation_bank.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const OUT = val('--out') || join(process.env.TEMP || '.', 'qd_live_seat_conversations');
process.env.QD_FIXTURES = '1';
// Measured 27 Oct 2026 (run a91b68b7): one portal turn is three model calls, 60-100 s and about USD 0.06; a turn with a
// photo about USD 0.58. --max-turns and --only keep a run inside its cap; the cap itself is the window's (rehearsal_cap).
const MAX_AGENT_TURNS = Number(val('--max-turns') || 8);
// The platform's request idle limit: an edge function that has not answered by then is a 504 to the browser. Measured
// 27 Oct 2026 (runs 1b6b12b6, 5ac11cb6, 5acff4ec): 5 of 6 first turns were written (assistant_logs) after 150 s.
export const TURN_LIMIT_MS = 150_000;

/** The scenarios a run takes: --only ids, else --slice i/n ('today' = day of the year mod 7, of 7), else the whole bank. */
export function pick(bank, only, slice, now = new Date()) {
  if (only.length) return bank.filter((s) => only.includes(s.id));
  if (!slice) return bank;
  const day = Math.floor((now - Date.UTC(now.getUTCFullYear(), 0, 0)) / 86400000);
  const [i, n] = slice === 'today' ? [day % 7, 7] : slice.split('/').map(Number);
  if (!(n > 0 && i >= 0 && i < n)) throw new Error('--slice i/n with 0 <= i < n, or today');
  return bank.filter((_s, k) => k % n === i);
}

const IDK = /\b(i don'?t know|i do not know|(i'?m|i am) (not sure|unsure)|i'?ll (check|find out|get back)|i will (check|find out|get back)|can'?t help|cannot help|unable to help)\b|لا أعرف|ما أعرف|لست متأكد|مو متأكد|غير متأكد|سأتحقق|راح أتأكد|لا أستطيع المساعدة/i;
const YESNO_ONLY = /^\s*(yes|no|yeah|nope|sure|ok(ay)?|نعم|لا|أكيد|تمام|ايوه)[\s.!،,]*([^\s]+\s*){0,3}$/i;
// A READ-BACK ASKED TO BE CONFIRMED, not any sentence with 'confirm' in it (run a8ad5ed7: 'to confirm at the site visit' and
// 'للتأكيد' ended 11 conversations early as if the customer had confirmed a summary that was never given).
const CONFIRM_ASK = /(here is|here's|summary|summar|request as i have it|ملخص)[\s\S]*(correct|right|confirm)[^.?!؟]*[?؟]|(صحيح|تؤكد|أكد)[^.?!؟]*[؟?]/i;
const arabicShare = (t) => { const a = (t.match(/[؀-ۿ]/g) || []).length, l = (t.match(/[A-Za-z]/g) || []).length; return a / Math.max(1, a + l); };

const reOf = (k) => (typeof k === 'string' ? R[k] : k);
export function customerTurn(s, agentText, given) {
  const out = [];
  s.facts.forEach(([k, say], i) => {
    if (given.has(i)) return;
    if (reOf(k).test(agentText)) { given.add(i); out.push(say); }
  });
  if (out.length) return out.join(' ');
  if (CONFIRM_ASK.test(agentText)) return s.lang === 'ar' ? 'نعم، صحيح.' : 'Yes, that is correct.';
  return null;
}
// The questions in a turn: each sentence that ends in a question mark (a told or re-asked fact fails only as a question).
export const questionsOf = (t) => String(t).split(/(?<=[.!?؟\n])\s+/).filter((x) => /[?؟]\s*$/.test(x.trim()));
/**
 * The code gates over the agent's turns. `released` (optional, Map fact index -> agent turn it was released after) lets a
 * later question matching that fact be FLAGGED as a re-ask for the judge; it never fails the gate on its own.
 */
export function codeGates(s, agentTurns, released = null, ms = null) {
  const qs = agentTurns.flatMap(questionsOf);
  const mustIdx = s.facts.map((x, i) => (x[2]?.must ? i : -1)).filter((i) => i >= 0);
  const g = {
    answered: agentTurns.length > 0 && agentTurns.every((t) => t.trim() && !/^\(NO ANSWER/.test(t)),
    // a reply after the platform's 150 s request limit never reaches the customer: the gateway has already sent a 504
    in_time: !ms || ms.every((x) => x <= TURN_LIMIT_MS),
    no_idk: !agentTurns.some((t) => IDK.test(t)),
    no_yesno_only: !agentTurns.some((t) => YESNO_ONLY.test(t)),
    language: agentTurns.every((t) => (s.lang === 'ar' ? arabicShare(t) >= 0.6 : arabicShare(t) <= 0.05)),
    asks_first: /[?؟]/.test(agentTurns[0] || ''),
    // asked what the opening already said
    no_reask_told: !(s.told || []).some((re) => qs.some((x) => re.test(x))),
    // a senior estimator cannot price without these: each must have been asked by some turn
    must_asked: mustIdx.every((i) => agentTurns.some((t) => reOf(s.facts[i][0]).test(t))),
    // the customer's wrong spec was corrected
    trap_corrected: !s.trap || agentTurns.some((t) => s.trap.expect.test(t)),
  };
  const reask = [];
  if (released) {
    agentTurns.forEach((t, ti) => {
      for (const [fi, at] of released) if (ti > at && questionsOf(t).some((x) => reOf(s.facts[fi][0]).test(x))) reask.push({ turn: ti, fact: s.facts[fi][1] });
    });
  }
  return { ...g, pass: Object.values(g).every(Boolean), reask_flagged: reask };
}

async function photo(kind) {
  return 'data:image/png;base64,' + (await sharp(Buffer.from(PHOTOS[kind])).png().toBuffer()).toString('base64');
}

async function runSuite() {
  mkdirSync(OUT, { recursive: true });
  const ONLY = (val('--only') || '').split(',').filter(Boolean);
  const list = pick(S, ONLY, val('--slice'));
  const cap = Number(val('--cap-usd') || 5);
  const { ANON } = await keys();
  const run = await openRun({ capUsd: cap, minutes: 120 });
  const url = process.env.PORTAL_ASSIST_URL || `${BASE}/functions/v1/sales_engineer`;
  try {
    const secret = await internalCred();
    const results = [];
    for (const s of list) {
      const path = s.lang === 'ar' ? '/ar/me' : '/me';
      // one fresh account per conversation: no earlier request bleeds in (ruling 1255: one conversation per account)
      const tok = (await makeDemoCustomer(run, { locale: s.lang })).jwt;
      const image = s.image ? await photo(s.image) : null;
      const history = [], turns = [{ role: 'customer', text: s.open, image: !!s.image }], given = new Set(), released = new Map();
      let stalls = 0;
      for (let t = 0; t < MAX_AGENT_TURNS; t++) {
        const message = turns.at(-1).text;
        // exactly PortalShell.askAssistant's body
        const body = { action: 'assist', message, history, path, lang: s.lang, ...(t === 0 && image ? { images: [image] } : {}) };
        const t0 = Date.now();
        // waits past the 150 s limit on purpose: a late reply is graded for content and failed on time (in_time)
        const r = await fetch(url, { method: 'POST', signal: AbortSignal.timeout(400000),
          headers: { apikey: ANON, Authorization: 'Bearer ' + tok, 'Content-Type': 'application/json', 'x-qd-e2e-run': run.tag, 'x-qd-e2e-secret': secret },
          body: JSON.stringify(body) })
          .then(async (x) => ({ status: x.status, json: await x.json().catch(() => null) })).catch((e) => ({ status: 0, json: { error: e.message } }));
        const reply = String(r.json?.reply || '').trim();
        const ms = Date.now() - t0;
        if (!reply) { turns.push({ role: 'agent', text: `(NO ANSWER: ${r.status} ${r.json?.error ?? ''})`, ms }); break; }
        turns.push({ role: 'agent', text: reply, ms });
        history.push({ role: 'user', content: message }, { role: 'assistant', content: reply });
        const before = new Set(given);
        let c = customerTurn(s, reply, given);
        for (const i of given) if (!before.has(i)) released.set(i, t);
        if (!c) { if (++stalls > 1) break; c = s.lang === 'ar' ? 'مو متأكد، شو تنصحني؟' : 'I am not sure, what do you recommend?'; }
        turns.push({ role: 'customer', text: c });
        if (/^(Yes, that is correct\.|نعم، صحيح\.)$/.test(c)) break;
      }
      const agentTurns = turns.filter((x) => x.role === 'agent').map((x) => x.text);
      const gates = codeGates(s, agentTurns, released, turns.filter((x) => x.role === 'agent').map((x) => x.ms));
      const facts_released = given.size, facts_total = s.facts.length;
      results.push({ id: s.id, lang: s.lang, trade: s.trade, path, gates, facts_released, facts_total, released: [...released], hidden_facts: s.facts.map(([, say]) => say),
        expert: s.expert, trap: s.trap ? s.trap.why : null, keeps: s.keeps ?? null, transcript: turns });
      const fails = Object.entries(gates).filter(([k, v]) => v === false && k !== 'pass').map(([k]) => k);
      console.log(`${s.id} [${s.lang}] code ${gates.pass ? 'PASS' : 'FAIL ' + fails.join(',')} facts asked ${facts_released}/${facts_total} turns ${agentTurns.length}${gates.reask_flagged.length ? ' reask? ' + gates.reask_flagged.length : ''}`);
    }
    const spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed),0)::numeric(12,4) aed, string_agg(distinct model_used, ',') models from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
    const file = join(OUT, `live_seat_conversations_${run.tag}.json`);
    writeFileSync(file, JSON.stringify({ ledger: 1200, surface: 'portal: sales_engineer assist', url, run_tag: run.tag, measured_at: new Date().toISOString(), spend, results }, null, 1));
    console.log(`spend ${JSON.stringify(spend)}\ntranscripts: ${file}\nnext: a Claude session scores each transcript -> score --results ${file} --judged <judged.json>`);
  } finally { await closeRun(run).catch((e) => console.error('teardown: ' + e.message)); }
}

function score() {
  const R0 = JSON.parse(readFileSync(val('--results'), 'utf8'));
  const J = JSON.parse(readFileSync(val('--judged'), 'utf8'));
  // The gates are recomputed from the transcript, so a corrected gate re-grades a stored run.
  for (const r of R0.results) {
    const sc = S.find((s) => s.id === r.id);
    const ag = r.transcript.filter((x) => x.role === 'agent');
    if (sc) r.gates = codeGates(sc, ag.map((x) => x.text), r.released ? new Map(r.released) : null, ag.every((x) => Number.isFinite(x.ms)) ? ag.map((x) => x.ms) : null);
  }
  const rows = R0.results.map((r) => {
    const j = J[r.id];
    const pct = j && r.gates.pass ? Math.round(Number(j.overall) * 10) : 0;
    const failed = Object.entries(r.gates).filter(([k, v]) => v === false && k !== 'pass').map(([k]) => 'code: ' + k);
    return { id: r.id, lang: r.lang, code: r.gates.pass, overall: j?.overall ?? null, pct, met: pct >= 95, issues: [...failed, ...(j?.issues ?? [])] };
  });
  const idk = R0.results.filter((r) => !r.gates.no_idk).length, yn = R0.results.filter((r) => !r.gates.no_yesno_only).length;
  for (const r of rows) console.log(`${r.met ? 'MET ' : 'GAP '} ${r.id} [${r.lang}] ${r.pct}%${r.issues.length ? ' - ' + r.issues.join('; ') : ''}`);
  const met = rows.filter((r) => r.met).length;
  const summary = { run_tag: R0.run_tag, scenarios: rows.length, met, mean_pct: Math.round(rows.reduce((a, r) => a + r.pct, 0) / rows.length), idk_conversations: idk, yesno_only_conversations: yn,
    acceptance: rows.length >= 30 && met === rows.length && idk === 0 && yn === 0 ? 'MET' : 'NOT MET',
    gaps: rows.filter((r) => !r.met).map((r) => ({ id: r.id, seat: 'sales_engineer', lang: r.lang, pct: r.pct, issues: r.issues })) };
  writeFileSync(val('--results').replace(/\.json$/, '.scored.json'), JSON.stringify(summary, null, 1));
  console.log(JSON.stringify({ ...summary, gaps: summary.gaps.length }));
}

if (process.argv[1]?.endsWith('live_seat_conversations.mjs')) {
  if (argv[0] === 'run') await runSuite();
  else if (argv[0] === 'score') score();
  else { console.error('usage: live_seat_conversations.mjs run|score (see the header)'); process.exit(2); }
}
export { S };
