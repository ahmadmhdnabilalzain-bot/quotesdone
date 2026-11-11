// scripts/e2e/registration_certification_judge.mjs — the PASS CRITERIA of the supplier registration certification, as code.
// Assigned: customer_support (founder ruling 1620, 10 Nov 2026). Pure: no browser, no database, so every rule here is
// tested offline (registration_certification_judge.test.mjs) and the driver (supplier_registration_certification.mjs) only
// measures. docs/release/supplier-registration-certification.md states the same criteria in words; this file is the bar.

// ── speed ───────────────────────────────────────────────────────────────────────────────────────────────────────────────
// "Interactive" = the screen has answered the supplier's action and the next control is on screen and usable. Founder: not
// laggy. Every step must be interactive within 3 s on desktop and 5 s on the phone profile. A step whose server does real
// work (sending the e-mail code, signing the agreement, reading a document) must ACKNOWLEDGE within the same 3 / 5 s and
// FINISH within its own ceiling below; the reader's ceiling applies only to a paid run.
export const INTERACTIVE_MS = { desktop: 3000, mobile: 5000 };
export const CEILING_MS = {
  send_code: { desktop: 10000, mobile: 15000 },       // the sign-up e-mail is sent before the code box opens
  submit: { desktop: 20000, mobile: 30000 },          // profile upload + save + the signed agreement certificate
  licence_read: { desktop: 45000, mobile: 45000 },    // code first; the vision reader when code reads nothing (paid)
  proposals: { desktop: 120000, mobile: 120000 },     // the documents' services, read after the answer
  approval: { desktop: 60000, mobile: 60000 },        // confirm -> approved and verified
};
// The phone profile: an iPhone-13-size screen on a mobile network. Applied with Chrome DevTools Protocol to the page.
export const MOBILE_NETWORK = { latency: 60, downloadThroughput: Math.round(9_000_000 / 8), uploadThroughput: Math.round(1_500_000 / 8), cpuSlowdown: 2,
  said: '9 Mbit/s down, 1.5 Mbit/s up, 60 ms added round trip, CPU slowed 2x (Chrome DevTools Protocol emulation)' };
// The supplier's own time, first click to verified: the scripted run's wall time with the harness-only mobile step replaced by
// the time a real person needs to receive and type an SMS / WhatsApp code.
export const SUPPLIER_MINUTES_MAX = 10;
export const REAL_MOBILE_OTP_MS = 60000;

/** One timed step's verdict. kind: 'interactive' (budget 3/5 s) or a CEILING_MS key (ack 3/5 s + its ceiling). */
export function stepTiming({ profile, kind = 'interactive', ms, ackMs = null }) {
  const budget = INTERACTIVE_MS[profile];
  if (kind === 'interactive') return { ok: ms != null && ms <= budget, budget_ms: budget, ms };
  const ceiling = CEILING_MS[kind]?.[profile];
  if (ceiling == null) throw new Error('no ceiling for ' + kind);
  const ackOk = ackMs == null ? true : ackMs <= budget;
  return { ok: ms != null && ms <= ceiling && ackOk, budget_ms: ceiling, ack_budget_ms: budget, ms, ack_ms: ackMs };
}

// ── the licence ─────────────────────────────────────────────────────────────────────────────────────────────────────────
const norm = (s) => String(s ?? '').toLowerCase().normalize('NFKD').replace(/[^a-z0-9]+/g, '');
const normNo = (s) => String(s ?? '').toUpperCase().replace(/\s+/g, '');
/** The licence's five fields, as read, against what the document prints. read: {licence_no, legal_name, authority, expiry, activities[]} */
export function judgeLicence(exp, read) {
  const r = read || {};
  const acts = (r.activities || []).map(norm);
  const fields = {
    licence_no: { want: exp.licence_no, got: r.licence_no ?? null, ok: !!r.licence_no && normNo(r.licence_no) === normNo(exp.licence_no) },
    legal_name: { want: exp.legal_name, got: r.legal_name ?? null, ok: !!r.legal_name && norm(r.legal_name) === norm(exp.legal_name) },
    authority: { want: exp.authority, got: r.authority ?? null, ok: !!r.authority && (norm(r.authority) === norm(exp.authority) || norm(r.authority).includes(norm(exp.authority))) && !/\p{Script=Arabic}/u.test(r.authority) },
    expiry: { want: exp.expiry_date, got: r.expiry ?? null, ok: String(r.expiry ?? '').slice(0, 10) === exp.expiry_date },
    activities: { want: exp.activities, got: r.activities ?? null, ok: exp.activities.every((a) => acts.includes(norm(a))) },
  };
  const okCount = Object.values(fields).filter((f) => f.ok).length;
  return { fields, ok: okCount === 5, ok_count: okCount };
}
/** An expired licence is flagged honestly: the supplier is told it has expired, and it is never approved. */
export function judgeExpired(exp, { screenText = '', approval = null, gateReason = null }) {
  if (!exp.expired) return { applies: false, ok: true };
  const told = /expired|has expired|no longer valid|renew/i.test(screenText);
  const notApproved = approval !== 'approved';
  return { applies: true, ok: told && notApproved, told_on_screen: told, not_approved: notApproved, gate_reason: gateReason };
}

// ── what the company does ───────────────────────────────────────────────────────────────────────────────────────────────
/** proposed: the trade codes the Services tab proposes (keys "trade.service", or trade codes). */
export function judgeProposals(exp, proposed) {
  const trades = [...new Set((proposed || []).map((k) => String(k).split('.')[0]).filter(Boolean))];
  const right = trades.filter((t) => exp.expect_trades.includes(t));
  const acceptable = trades.filter((t) => exp.acceptable_trades.includes(t));
  const absurd = trades.filter((t) => !exp.expect_trades.includes(t) && !exp.acceptable_trades.includes(t));
  return { trades, right, acceptable, absurd, ok: right.length > 0 && absurd.length === 0 };
}

// ── what the supplier reads ─────────────────────────────────────────────────────────────────────────────────────────────
const ARABIC = /\p{Script=Arabic}+(?:[\s\p{Script=Arabic}]*)/gu;
/** Every run of Arabic in the visible text (suppliers are always written to in English: ruling 1008). */
export const arabicIn = (text) => [...new Set((String(text || '').match(ARABIC) || []).map((s) => s.trim()).filter(Boolean))];
// What a supplier must never read: a code, a status, a stack, a raw platform phrase.
const RAW = [
  [/\b[a-z]{2,}(?:_[a-z0-9]{2,})+\b/, 'a raw code (snake_case)'], [/\bHTTP\s?\d{3}\b|\b(?:500|502|503|504|546)\b/, 'an HTTP status'],
  [/\b(?:undefined|null|NaN)\b|\[object Object\]/, 'a programming value'], [/\b(?:TypeError|ReferenceError|SyntaxError|stack|exception)\b/i, 'an error class'],
  [/failed to fetch|network ?error|ERR_[A-Z_]+|CORS|JWT|token expired/i, 'a raw platform error'], [/\{\s*"|\}\s*$/, 'JSON'],
];
// "correct anything wrong" is polite; a message that OPENS with "Wrong" ("Wrong code.") is curt (11 Nov 2026, the first free run).
const RUDE = [/\binvalid\b/i, /\billegal\b/i, /^wrong\b/i, /\byou must\b/i, /\bnot allowed\b/i, /\bdenied\b/i, /!{2,}/];
/** Why a message the supplier reads is not plain and polite, or [] when it is. */
export function messageFaults(msg) {
  const m = String(msg || '').trim();
  if (!m) return [];
  const out = RAW.filter(([re]) => re.test(m)).map(([, why]) => why);
  if (RUDE.some((re) => re.test(m))) out.push('not polite');
  if (m === m.toUpperCase() && /[A-Z]{6,}/.test(m)) out.push('shouted');
  return out;
}

// ── the whole certification ─────────────────────────────────────────────────────────────────────────────────────────────
/**
 * runs: [{ journeys: [{ id, profile, steps: [{name, timing:{ok}, ok, deferred}], licence: judgeLicence|null, expired: judgeExpired,
 *   proposals: judgeProposals|null, arabic: [], faults: [], errors: [], dead_end, supplier_ms, verified }] }]
 * Returns one verdict per criterion: PASS, FAIL, or NOT RUN (a part that needs the paid reader, in a free run).
 */
export function certify(runs, { paid }) {
  const js = runs.flatMap((r) => r.journeys);
  const verdict = (ok, notRun = false) => (notRun ? 'NOT RUN' : ok ? 'PASS' : 'FAIL');
  const timed = js.flatMap((j) => j.steps.filter((s) => s.timing && !s.deferred));
  const lic = js.filter((j) => j.licence && !j.licence_deferred);
  const licOk = lic.filter((j) => j.licence.ok).length;
  const prop = js.filter((j) => j.proposals && !j.proposals_deferred);
  const exp = js.filter((j) => j.expired?.applies);
  const full = js.filter((j) => j.expect_verified);
  const fullDone = full.filter((j) => j.verified && j.supplier_ms != null);
  const sig = (r) => r.journeys.map((j) => `${j.id}:${j.verified ? 'V' : '-'}:${j.licence ? j.licence.ok_count : 'x'}:${(j.proposals?.trades || []).join('+')}`).join('|');
  return {
    speed: { verdict: verdict(timed.length > 0 && timed.every((s) => s.timing.ok)), steps: timed.length, slow: timed.filter((s) => !s.timing.ok).map((s) => `${s.journey} ${s.profile} ${s.name} ${s.timing.ms} ms > ${s.timing.budget_ms}`) },
    licence_fields: { verdict: verdict(lic.length >= 8 && licOk >= 7, !paid && lic.length < 8), read: lic.length, correct: licOk, bar: '>= 7 of 8 licences, all five fields' },
    expired_flagged: { verdict: verdict(exp.length > 0 && exp.every((j) => j.expired.ok), exp.length === 0) },
    proposals: { verdict: verdict(prop.length >= 6 && prop.every((j) => j.proposals.ok), !paid && prop.length < 6), judged: prop.length, absurd: prop.flatMap((j) => j.proposals.absurd.map((t) => `${j.id}: ${t}`)) },
    no_error_no_dead_end: { verdict: verdict(js.every((j) => !j.dead_end && j.errors.length === 0)), dead_ends: js.filter((j) => j.dead_end).map((j) => `${j.id} ${j.profile}: ${j.dead_end}`), errors: js.flatMap((j) => j.errors.map((e) => `${j.id}: ${e}`)) },
    no_arabic: { verdict: verdict(js.every((j) => j.arabic.length === 0)), seen: js.flatMap((j) => j.arabic.map((a) => `${j.id}: ${a}`)) },
    plain_polite: { verdict: verdict(js.every((j) => j.faults.length === 0)), faults: js.flatMap((j) => j.faults.map((f) => `${j.id}: ${f}`)) },
    supplier_minutes: { verdict: verdict(fullDone.length > 0 && fullDone.length === full.length && fullDone.every((j) => j.supplier_ms <= SUPPLIER_MINUTES_MAX * 60000), !paid && fullDone.length === 0), max_minutes: SUPPLIER_MINUTES_MAX, measured_min: fullDone.map((j) => `${j.id} ${(j.supplier_ms / 60000).toFixed(1)}`) },
    reproducible: { verdict: verdict(runs.length >= 2 && runs.every((r) => sig(r) === sig(runs[0])), runs.length < 2), signatures: runs.map(sig) },
  };
}
