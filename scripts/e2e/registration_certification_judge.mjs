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

// ── a licence only the model can read, in a free run ──────────────────────────────────────────────────────────────────────
/**
 * True when a registration is still held ONLY because the model has not read a licence that has no text for code (a phone
 * photo, an image-only scan) and the run kept the models off. Then "approved and verified" is the paid reader's to prove: NOT RUN,
 * never FAIL. Every part must be true, so any other hold (an unread field our reader DID read, a mismatch, an expired licence)
 * still fails. 11 Nov 2026, second free round: J4 and J5 stayed licence_being_read for 60 s in both runs.
 * The hold itself is right: _shared/licence_read_state.ts ('ours_failed') holds the registration as licence_being_read, tells
 * the supplier it is ours, and the sweep reads it again (#1909); a demo licence is never re-read in real mode.
 */
export function waitsOnTheModel({ paid, needsModel, gateReason, readState }) {
  return !paid && !!needsModel && gateReason === 'licence_being_read' && readState === 'ours_failed';
}

// ── what the supplier reads ─────────────────────────────────────────────────────────────────────────────────────────────
const ARABIC = /\p{Script=Arabic}+(?:[\s\p{Script=Arabic}]*)/gu;
/** Every run of Arabic in the visible text (suppliers are always written to in English: ruling 1008). */
export const arabicIn = (text) => [...new Set((String(text || '').match(ARABIC) || []).map((s) => s.trim()).filter(Boolean))];

// WHAT "NO ARABIC" MEANS, AND WHAT IT DOES NOT (11 Nov 2026; the main session's decision on finding 8, the founder told).
//   * Ruling 1008 (28 Sep 2026): every MESSAGE to a supplier is English, on every channel: e-mail, WhatsApp, SMS and PDF. Any
//     Arabic in a message the run caused (the sign-in code e-mail, every notification's subject and body) FAILS.
//   * The English supplier pages carry no Arabic either, with two exceptions that are not messages:
//       - the Supplier Agreement's legal text: ruling 342 (14 Sep 2026) makes the agreement's Arabic text the one that prevails,
//         and it names QuotesDone by its Arabic registered name. The agreement page's Arabic is allowed, and reported.
//       - Arabic the supplier chose: the Arabic language switch is his own choice (the harness reports it apart, never presses it), and a
//         page he opened in Arabic (lang 'ar') is his. Neither is a message to him.
// A notification's attachment (a PDF) is listed, not read: the bodies are judged, the files are not opened here.
export const ARABIC_ALLOWED_WHERE = { 'agreement page': 'the Supplier Agreement\'s legal text (ruling 342: its Arabic text prevails)' };
/** screens: [{where, text, lang?}] seen on pages; messages: [{channel, where, text}] the run sent. */
export function judgeArabic({ screens = [], messages = [] }) {
  const allowed = screens.filter((a) => ARABIC_ALLOWED_WHERE[a.where] || a.lang === 'ar');
  const onScreen = screens.filter((a) => !allowed.includes(a));
  const inMessages = messages.flatMap((m) => arabicIn(m.text).map((text) => ({ channel: m.channel, where: m.where, text })));
  return { ok: onScreen.length === 0 && inMessages.length === 0, on_screen: onScreen, in_messages: inMessages,
    allowed: allowed.map((a) => ({ ...a, why: ARABIC_ALLOWED_WHERE[a.where] || 'the supplier chose Arabic' })) };
}
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
// WHO ANSWERED A FAILED PAGE RESOURCE (11 Nov 2026, customer_support; free round 6, run 1 J2 mobile: a portal chunk answered 502
// text/plain and was refused, the second time that day; the first was blamed on the test container's proxy without proof).
// quotesdone.* is served over TLS that ends at Vercel (Let's Encrypt certificate for the host; the container's proxy relays a
// CONNECT tunnel and, once it is up, can only drop it, never answer inside it: /root/.ccr/README.md), and Vercel signs every answer
// it gives with `server: Vercel` and an `x-vercel-id`. So an answer for our host WITH that signature is the site's (its CDN or
// its functions); one WITHOUT it came from something between the browser and the site: an environment fault. Nothing recorded
// (no headers, a run before this) is the site's: a failure is never moved out of the verdict without the evidence.
const SITE_HOST = /^https:\/\/(?:www\.)?quotesdone\.(?:ae|com)\//i;
export function failureOrigin({ url, headers }) {
  if (!SITE_HOST.test(String(url || ''))) return 'other';
  if (!headers || typeof headers !== 'object') return 'site';
  const h = Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), String(v ?? '')]));
  return /vercel/i.test(h.server || '') || h['x-vercel-id'] ? 'site' : 'environment';
}

/** Console errors split by the failure they name: those naming a URL whose failed answer was the environment's, and the rest. */
export function splitEnvironmentFaults(errors, failures) {
  const env = (failures || []).filter((f) => f.origin === 'environment' && f.url).map((f) => String(f.url));
  const environment = [], site = [];
  for (const e of errors || []) (env.some((u) => String(e).includes(u)) ? environment : site).push(e);
  return { site, environment };
}

export function certify(runs, { paid }) {
  const js = runs.flatMap((r) => r.journeys);
  const verdict = (ok, notRun = false) => (notRun ? 'NOT RUN' : ok ? 'PASS' : 'FAIL');
  const timed = js.flatMap((j) => j.steps.filter((s) => s.timing && !s.deferred));
  // THE LICENCE BAR IS PER RUN: >= 7 of the run's 8 licences read whole. In a free run the photo and the scan are not read
  // (deferred), so a run is FAIL only when it can no longer reach 7 even if every licence it did not judge were read right
  // (more than one judged licence wrong); otherwise NOT RUN. A paid run must judge all eight.
  const perRun = runs.map((r) => {
    const judged = r.journeys.filter((j) => j.licence && !j.licence_deferred), ok = judged.filter((j) => j.licence.ok).length;
    // not run: every one of the eight this run did not judge (the paid reader's two in a free run, and any it never reached)
    return { judged: judged.length, correct: ok, not_run: Math.max(0, 8 - judged.length), wrong: judged.filter((j) => !j.licence.ok).map((j) => j.id) };
  });
  const licVerdict = perRun.length && perRun.every((x) => x.judged >= 8 && x.correct >= 7) ? 'PASS'
    : perRun.some((x) => x.correct + x.not_run < 7) ? 'FAIL' : !paid ? 'NOT RUN' : 'FAIL';
  const prop = js.filter((j) => j.proposals && !j.proposals_deferred);
  const exp = js.filter((j) => j.expired?.applies);
  const full = js.filter((j) => j.expect_verified);
  const fullDone = full.filter((j) => j.verified && j.supplier_ms != null);
  const overTime = fullDone.filter((j) => j.supplier_ms > SUPPLIER_MINUTES_MAX * 60000);
  // the supplier's own time: a measured registration over the bar FAILS at once; in a free run the ones the reader could not
  // finish are NOT RUN, never a pass
  const minutesVerdict = overTime.length ? 'FAIL' : fullDone.length && fullDone.length === full.length ? 'PASS' : !paid ? 'NOT RUN' : 'FAIL';
  // THE RIGHT SET, NOT EVERY ACCEPTABLE EXTRA (11 Nov 2026, customer_support; founder rulings 1627 and 1628). The model reads the
  // documents, so an "acceptable" extra may come and go between runs (paid run of #1934: J6 gave staff_transport + vehicle_leasing,
  // then staff_transport alone). What must reproduce is what the judge requires: verified, the licence fields read, the expected
  // trades found (`right`) and nothing absurd. An acceptable extra is shown in `extras`, never part of the signature.
  const sig = (r) => r.journeys.map((j) => `${j.id}:${j.verified ? 'V' : '-'}:${j.licence ? j.licence.ok_count : 'x'}:${[...(j.proposals?.right || [])].sort().join('+')}:${[...(j.proposals?.absurd || [])].sort().join('+')}`).join('|');
  const extras = (r) => r.journeys.map((j) => `${j.id}:${[...(j.proposals?.acceptable || [])].sort().join('+')}`).join('|');
  return {
    speed: { verdict: verdict(timed.length > 0 && timed.every((s) => s.timing.ok)), steps: timed.length, slow: timed.filter((s) => !s.timing.ok).map((s) => `${s.journey} ${s.profile} ${s.name} ${s.timing.ms} ms > ${s.timing.budget_ms}`) },
    licence_fields: { verdict: licVerdict, per_run: perRun, bar: '>= 7 of 8 licences per run, all five fields' },
    expired_flagged: { verdict: verdict(exp.length > 0 && exp.every((j) => j.expired.ok), exp.length === 0) },
    proposals: { verdict: verdict(prop.length >= 6 && prop.every((j) => j.proposals.ok), !paid && prop.length < 6), judged: prop.length, absurd: prop.flatMap((j) => j.proposals.absurd.map((t) => `${j.id}: ${t}`)) },
    no_error_no_dead_end: { verdict: verdict(js.every((j) => !j.dead_end && j.errors.length === 0)), dead_ends: js.filter((j) => j.dead_end).map((j) => `${j.id} ${j.profile}: ${j.dead_end}`), errors: js.flatMap((j) => j.errors.map((e) => `${j.id}: ${e}`)),
      // answers that did not come from the site (failureOrigin), shown and never counted against it
      environment_faults: js.flatMap((j) => (j.environment_faults || []).map((e) => `${j.id}: ${e}`)) },
    no_arabic: (() => {
      // ruling 1008 (messages) and the English pages, the agreement's legal text excepted (ruling 342): judgeArabic above
      const a = judgeArabic({ screens: js.flatMap((j) => j.arabic.map((x) => (typeof x === 'string' ? { where: '', text: x } : x))),
        messages: [...runs.flatMap((r) => r.messages_sent || []), ...js.map((j) => (j.code_mail?.subject ? { channel: 'email', where: 'the sign-in code e-mail', text: j.code_mail.subject } : null)).filter(Boolean)] });
      const fmt = (x) => `${x.where ?? x.channel ?? ''}: ${x.text}`;
      return { verdict: verdict(a.ok), rule: 'ruling 1008: no Arabic in a message to a supplier; no Arabic on an English supplier page except the agreement\'s legal text (ruling 342) or Arabic the supplier chose',
        seen: [...new Set(a.on_screen.map(fmt))], in_messages: [...new Set(a.in_messages.map(fmt))], allowed: [...new Set(a.allowed.map(fmt))],
        messages_read: runs.reduce((n, r) => n + (r.messages_sent || []).length, 0), language_switch_seen: [...new Set(js.flatMap((j) => (j.language_switch || []).map((x) => x.where)))] };
    })(),
    plain_polite: { verdict: verdict(js.every((j) => j.faults.length === 0)), faults: js.flatMap((j) => j.faults.map((f) => `${j.id}: ${f}`)) },
    supplier_minutes: { verdict: minutesVerdict, max_minutes: SUPPLIER_MINUTES_MAX, measured_min: fullDone.map((j) => `${j.id} ${(j.supplier_ms / 60000).toFixed(1)}`), not_finished: full.filter((j) => !j.verified).map((j) => j.id) },
    reproducible: { verdict: verdict(runs.length >= 2 && runs.every((r) => sig(r) === sig(runs[0])), runs.length < 2), signatures: runs.map(sig), extras: runs.map(extras),
      compares: 'verified, licence fields read, the expected trades found and the absurd ones; acceptable extras are listed, not compared' },
  };
}
