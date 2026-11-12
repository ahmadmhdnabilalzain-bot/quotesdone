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

/**
 * A VAGUE profile's proposals (paid check of J10, 12 Nov 2026): a profile whose fixture expects a vague card proposes no trade by design
 * and the cards ask. With proposals it is judged exactly as judgeProposals. With none, it passes only when nothing was proposed (no
 * absurd or unexpected trade) AND the trades STORED after Confirm are all expected or acceptable AND an expected one among them is a
 * trade of a service he TAPPED (screen 1 or the cards: cardTrades). Confirm keeps the sign-up trade on its own
 * (supplier_services.ts keepTickedProposed, signupTradeOf), so a stored expected trade alone proves nothing about the cards
 * (final review of PR #1969). stored: his stored trades (null when not read: fails).
 */
export function judgeVagueProposals(exp, proposed, stored, cardTrades = []) {
  const p = judgeProposals(exp, proposed);
  if (p.trades.length) return { ...p, via: 'proposals' };
  const st = [...new Set(stored || [])];
  const right = st.filter((t) => exp.expect_trades.includes(t)), acceptable = st.filter((t) => exp.acceptable_trades.includes(t));
  const absurd = st.filter((t) => !exp.expect_trades.includes(t) && !exp.acceptable_trades.includes(t));
  const fromCards = right.filter((t) => cardTrades.includes(t));
  return { trades: [], stored: st, right, acceptable, absurd, from_cards: fromCards, via: 'stored', ok: stored != null && absurd.length === 0 && fromCards.length > 0 };
}

// ── a licence only the model can read, in a free run ──────────────────────────────────────────────────────────────────────
/**
 * True when a registration is still held ONLY because the model has not read its licence and the run kept the models off. Then "approved and verified" is the paid reader's to prove: NOT RUN,
 * never FAIL. Every part must be true, so any other hold (an unread field our reader DID read, a mismatch, an expired licence)
 * still fails. 11 Nov 2026, second free round: J4 and J5 stayed licence_being_read for 60 s in both runs.
 * The hold itself is right: _shared/licence_read_state.ts ('ours_failed') holds the registration as licence_being_read, tells
 * the supplier it is ours, and the sweep reads it again (#1909); a demo licence is never re-read in real mode.
 */
// EVERY LICENCE IS THE MODEL'S TO READ NOW (12 Nov 2026, founder rulings 1663 and 1664; second review of #1978). Code's reading
// is no longer stored, so in a free run a TEXT licence is held as licence_being_read exactly as a photo is, and the old condition
// "this fixture needs the model" (needsModel) would have marked every text-licence journey that reaches Submit FAIL on "approved
// and verified", where the truth is that the paid reader was never asked. The fixture's flag is therefore not consulted.
export function waitsOnTheModel({ paid, gateReason, readState }) {
  return !paid && gateReason === 'licence_being_read' && readState === 'ours_failed';
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
  // the bar is over the eight original licences (J1-J8); a later journey's licence (J9, J10: clean PDFs) must simply be read whole
  const ORIGINAL = new Set(['J1', 'J2', 'J3', 'J4', 'J5', 'J6', 'J7', 'J8']);
  const laterWrong = js.filter((j) => !ORIGINAL.has(j.id) && j.licence && !j.licence_deferred && !j.licence.ok).map((j) => j.id);
  const perRun = runs.map((r) => {
    const judged = r.journeys.filter((j) => ORIGINAL.has(j.id) && j.licence && !j.licence_deferred), ok = judged.filter((j) => j.licence.ok).length;
    // not run: every one of the eight this run did not judge (the paid reader's two in a free run, and any it never reached)
    return { judged: judged.length, correct: ok, not_run: Math.max(0, 8 - judged.length), wrong: judged.filter((j) => !j.licence.ok).map((j) => j.id) };
  });
  const licVerdict = laterWrong.length || perRun.some((x) => x.correct + x.not_run < 7) ? 'FAIL'
    : perRun.length && perRun.every((x) => x.judged >= 8 && x.correct >= 7) ? 'PASS' : !paid ? 'NOT RUN' : 'FAIL';
  // THE SERVICES SCREENS (finding 1): a failed services step on a journey that expects verification FAILS; a free run cannot read, so
  // NOT RUN; a paid run PASSES only when every such journey judged the reading on screen, the confirm and "nothing was saved…"
  const sj = js.filter((j) => j.expect_verified);
  const svcFailed = sj.flatMap((j) => j.steps.filter((s) => SERVICES_SCREEN_STEPS.includes(s.name) && stepFailed(s)).map((s) => `${j.id} ${j.profile}: ${s.name}`));
  const svcMissing = sj.flatMap((j) => SERVICES_REQUIRED_STEPS.filter((n) => !j.steps.some((s) => s.name === n && !s.deferred)).map((n) => `${j.id} ${j.profile}: ${n} not judged`));
  const svcVerdict = svcFailed.length ? 'FAIL' : !paid ? 'NOT RUN' : sj.length && !svcMissing.length ? 'PASS' : 'FAIL';
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
    licence_fields: { verdict: licVerdict, per_run: perRun, later_wrong: laterWrong, bar: '>= 7 of the 8 original licences per run, all five fields; J9 and J10 each read whole' },
    services_screens: { verdict: svcVerdict, failed: svcFailed, not_judged: paid ? svcMissing : [], steps: SERVICES_SCREEN_STEPS, required: SERVICES_REQUIRED_STEPS },
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

// ── the services screens of slice 4 (it_engineer, 12 Nov 2026): the cards, and what the confirm stored ─────────────────────
/** At most this many cards in one sitting: supplier_profile_reading.ts proposalOf ("at most 5 cards in one sitting"). */
export const CARD_CAP = 5;
/**
 * "The questions are specific and few". cards: [{ kind, prompt, quote, chips: [label], trade_label, trade, stopped }] as the walk
 * recorded them. Few: at most CARD_CAP. Specific, one of: the card quotes his own sentence (the quote shown above the question); its
 * question names the trade it is about (the trade's label); its question names what his documents show (one of its own chips, as the
 * 'shown' cards do: "Your projects show marble & granite, carpet and parquet & vinyl"); the 'licence' card names what his licence
 * lists. The 'umbrella' card ("Companies like yours often also do these") names none of these by design: it is specific within the
 * product's own bound, at most 2 umbrella cards and at most 12 umbrella chips IN ALL (supplier_profile_reading.ts proposalOf).
 * A card fails when: it offers no chip (a 'partner' card's rows are its chips; so the 'nothing' card fails: for a fixture whose
 * profile says what the company does, "your profile does not say" is the reading's failure); the walk STOPPED on it (its chips were
 * not the stored question's); or (any card but the umbrella) its trade is outside the fixture's expected and acceptable trades.
 * No card at all fails when the reading drafted an open question that the question store does not hold (drafts_missing: a broken
 * store looks exactly like "no cards"). Review of PR #1969, findings 2.
 */
export function judgeCards(cards, { cap = CARD_CAP, allowed_trades = null, drafts_missing = 0 } = {}) {
  const list = cards || [];
  const umbrellas = list.filter((c) => c.kind === 'umbrella');
  const umbrellaChips = umbrellas.reduce((n, c) => n + (c.chips || []).length, 0);
  const allowed = allowed_trades ? new Set(allowed_trades) : null;
  const per = list.map((c) => {
    const prompt = String(c.prompt || '').toLowerCase(), chips = c.chips || [];
    const quotes = !!(c.quote && String(c.quote).trim());
    const names = !!(c.trade_label && prompt.includes(String(c.trade_label).toLowerCase()));
    const namesShown = chips.some((ch) => ch && prompt.includes(String(ch).toLowerCase()));
    const umbrellaOk = c.kind === 'umbrella' && umbrellas.length <= 2 && umbrellaChips <= 12;
    const specific = quotes || names || namesShown || (c.kind === 'licence' && /licence lists/i.test(c.prompt || '')) || umbrellaOk;
    const hisTrade = c.kind === 'umbrella' || !c.trade || !allowed || allowed.has(c.trade);
    const why = [!specific && 'neither his sentence, nor its trade, nor what he showed', !chips.length && 'no chip', c.stopped && `the walk stopped: ${c.stopped}`, !hisTrade && `trade ${c.trade} is not his`].filter(Boolean);
    return { kind: c.kind, quotes, names, names_shown: namesShown, specific, chips: chips.length, trade: c.trade || null, ok: why.length === 0, why };
  });
  const few = per.length <= cap;
  const store = !(per.length === 0 && drafts_missing > 0);
  return { count: per.length, cap, few, umbrella_chips: umbrellaChips, drafts_missing, per,
    ok: few && store && per.every((x) => x.ok), why: [...(!few ? [`${per.length} cards > ${cap}`] : []), ...(!store ? [`no card, but the reading drafted ${drafts_missing} open question(s) the store does not hold`] : []), ...per.filter((x) => !x.ok).map((x, i) => `${x.kind}: ${x.why.join(', ')}`)] };
}
/**
 * "Every answer became a key or his words". tapped: { own: [key], partner: [key], words: [phrase], declined: [key] } (what he
 * answered on screen 1 and the cards); stored: { services: [key or phrase], services_partner: [key or phrase] } read back after
 * Confirm. Each own key is stored and not as partner; each partner key is stored as partner; each phrase is stored; a declined key
 * ("Not offered", "None of these") is not stored unless he also tapped it somewhere else.
 */
export function judgeStoredAnswers(tapped, stored) {
  const S = new Set(stored?.services || []), P = new Set(stored?.services_partner || []);
  const low = new Set([...S].map((x) => String(x).toLowerCase()));
  const tappedAny = new Set([...(tapped.own || []), ...(tapped.partner || [])]);
  const missing = [
    ...(tapped.own || []).filter((k) => !S.has(k)).map((k) => `own ${k} not stored`),
    ...(tapped.own || []).filter((k) => P.has(k) && !(tapped.partner || []).includes(k)).map((k) => `own ${k} stored as partner`),
    ...(tapped.partner || []).filter((k) => !S.has(k) || !P.has(k)).map((k) => `partner ${k} not stored as partner`),
    ...(tapped.words || []).filter((w) => !low.has(String(w).toLowerCase())).map((w) => `words "${w}" not stored`),
    ...(tapped.declined || []).filter((k) => !tappedAny.has(k) && S.has(k)).map((k) => `declined ${k} stored`),
  ];
  const n = (tapped.own || []).length + (tapped.partner || []).length + (tapped.words || []).length + (tapped.declined || []).length;
  return { answers: n, missing, ok: n > 0 && missing.length === 0 };
}
/**
 * "Nothing was saved that he did not tap". What a customer's request is matched on is fn_services_effective(services, trades,
 * services_removed): what he stated plus one level of curated service_implication from his stated services and trades, minus what he
 * removed (scripts/sql/a_supplier_describes_its_services_in_its_own_words_and_the_sales_engineer_rewrites_them.sql). So:
 *   - stored services and services_partner minus every key and phrase he tapped must be empty;
 *   - the effective set must be within what he tapped plus the implications OF what he tapped (from a tapped key, or from one of his
 *     stored trades that is his), each implication listed with the source that implies it, so a reader sees why it is there;
 *   - his stored trades must be within the fixture's expected and acceptable trades.
 * eff: { effective: [key], implications: [{ k, from }], trades: [code] } read with the script's own read(); null when not read.
 */
export function judgeNothingUntapped(tappedAll, stored, eff = null, { allowed_trades = null } = {}) {
  const T = new Set((tappedAll || []).map((x) => String(x).toLowerCase()));
  const extra = (stored?.services || []).filter((x) => !T.has(String(x).toLowerCase()));
  const extraPartner = (stored?.services_partner || []).filter((x) => !T.has(String(x).toLowerCase()));
  const allowed = allowed_trades ? new Set(allowed_trades) : null;
  const trades = eff?.trades || [];
  const foreignTrades = allowed ? trades.filter((t) => !allowed.has(t)) : [];
  const sources = new Set([...T, ...trades.filter((t) => !allowed || allowed.has(t))]);
  const why = new Map();
  for (const i of eff?.implications || []) if (sources.has(String(i.from).toLowerCase()) || sources.has(i.from)) { if (!why.has(i.k)) why.set(i.k, i.from); }
  const effective = eff?.effective || [];
  const unexplained = effective.filter((k) => !T.has(String(k).toLowerCase()) && !why.has(k));
  const implied = effective.filter((k) => !T.has(String(k).toLowerCase()) && why.has(k)).map((k) => `${k} (implied by ${why.get(k)})`);
  return { extra, extra_partner: extraPartner, unexplained, implied, foreign_trades: foreignTrades, effective_read: !!eff, services_implied: stored?.services_implied || [],
    ok: extra.length === 0 && extraPartner.length === 0 && unexplained.length === 0 && foreignTrades.length === 0 };
}
/**
 * "The services shown are his" (review of PR #1969, finding 4): a key the profile plainly states (must) is shown on screen 1 or as a
 * chip; a key of his trade the profile plainly does not do (never) is never shown as a CERTAIN row (no partner / projects / brand /
 * please-check badge). shown: { certain: [key], screen1: [key], chips: [key] }. twins: [{ f, t }] the live `same` rows of
 * service_implication (one piece of work under two keys): a must key is shown when its twin is (round 2, D: doors.wooden_doors
 * and joinery.wooden_doors).
 */
export function judgeServicesShown({ must = [], never = [] }, shown, twins = []) {
  const seen = new Set([...(shown.screen1 || []), ...(shown.chips || [])]);
  const twinOf = (k) => twins.filter((r) => r.f === k || r.t === k).map((r) => (r.f === k ? r.t : r.f));
  const missing = must.filter((k) => !seen.has(k) && !twinOf(k).some((x) => seen.has(x)));
  const wrong = never.filter((k) => (shown.certain || []).includes(k));
  return { missing, wrong, ok: missing.length === 0 && wrong.length === 0 };
}
/**
 * "The card his profile calls for is asked": a card of that kind was shown, and (round 2, A) every key the founder named is among its
 * chips, compared by KEY (the card's stored options), so a renamed label cannot fail it. watch: service keys.
 */
export function judgeExpectedCard(kind, cards, watch = []) {
  const of = (cards || []).filter((c) => c.kind === kind);
  const keys = new Set(of.flatMap((c) => c.keys || []).filter(Boolean));
  const offered = Object.fromEntries((watch || []).map((w) => [w, keys.has(w)]));
  const notOffered = (watch || []).filter((w) => !keys.has(w));
  return { kind, asked: of.length > 0, offered, not_offered: notOffered, ok: of.length > 0 && notOffered.length === 0 };
}

// ── what decides "READY TO INVITE" (review of PR #1969, finding 1) ─────────────────────────────────────────────────────────
/** The services screens' judged steps: any of them FAILED on a journey that expects verification fails `services_screens`. */
export const SERVICES_SCREEN_STEPS = ['what we read is on screen', 'the list to tick is on screen', 'proposed services start unticked', 'screen 1: his rows ticked one by one as the fixture says',
  'screen 1 answers the tap', 'a card answers the tap', 'the questions are specific and few', 'the services shown are his', 'the card his profile calls for is asked',
  'every answer became a key or his words', 'nothing was saved that he did not tap', '"Confirm my services" confirms them'];
/** In a paid run each such journey must have judged these, without deferral. */
export const SERVICES_REQUIRED_STEPS = ['what we read is on screen', '"Confirm my services" confirms them', 'nothing was saved that he did not tap'];
/** A step whose FAIL does not stop the verdict, with the reason written here. None: no step is informational. */
export const INFORMATIONAL_STEPS = {};
const stepFailed = (s) => !s.deferred && !(s.ok && (!s.timing || s.timing.ok));
/** Every FAILED step of every journey, unless listed informational: each one makes the run NOT READY, and is named. */
export function failedSteps(runs) {
  return runs.flatMap((r) => r.journeys.flatMap((j) => j.steps.filter((s) => stepFailed(s) && !(s.name in INFORMATIONAL_STEPS)).map((s) => `run${r.run ?? ''} ${j.id} ${j.profile}: ${s.name}${s.timing && !s.timing.ok ? ` (${s.timing.ms} ms > ${s.timing.budget_ms})` : ''}`)));
}
/** READY TO INVITE: a paid run, every criterion PASS, and no failed step anywhere. */
export function readiness(verdicts, runs, { paid }) {
  const failed = failedSteps(runs), notPass = Object.entries(verdicts).filter(([, v]) => v.verdict !== 'PASS').map(([k, v]) => `${k}: ${v.verdict}`);
  return { ready: !!paid && notPass.length === 0 && failed.length === 0, failed_steps: failed, criteria_not_pass: notPass };
}
