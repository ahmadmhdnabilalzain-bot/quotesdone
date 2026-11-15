// scripts/e2e/journey_proof/personas/abandon.mjs — WHEN A REAL PERSON GIVES UP. Pure: the turns so far in, a decision out.
// Seat: customer_support. Founder, 15 Nov 2026: "Are they realistic? ... Dont you think that in real life customers would be
// that smart?" A scripted customer never leaves; a person does. Each persona carries its own patience (customers.mjs):
//
//   slow_s            a reply that takes longer than this many seconds is "slow" for this person
//   max_slow          the person leaves at the max_slow-th slow reply (null: never for slowness)
//   abandon_on_repeat the person leaves the n-th time the platform asks something it already asked (null: never)
//   max_questions     the person leaves when the platform has asked this many questions and is still not ready (null: never)
//   max_stuck         the person leaves after this many platform messages in a row that ask nothing (no question card, no
//                     question mark) while the request is still not ready (default 2): nothing is happening
//
// A REPEAT is the platform asking again what it already asked and the person already answered (or already said "not sure"
// to): the same question key, the same topic, or nearly the same words. A question asked again right after the person said
// they did not understand it, or asked back, is a REPHRASE and is never counted against the platform.

const STOP = new Set('a an the and or of to for in on at is are be do you your it this that what which how many much please any there with would could should can we our i me my have has by as if so just'.split(' '));
/** The content words of a question, lower-case, for "nearly the same words". */
export function words(text) {
  return new Set(String(text || '').toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter((w) => w.length > 2 && !STOP.has(w)));
}
/** Jaccard overlap of two questions' content words, 0..1. */
export function overlap(a, b) {
  const A = words(a), B = words(b); if (!A.size || !B.size) return 0;
  let n = 0; for (const w of A) if (B.has(w)) n++;
  return n / (A.size + B.size - n);
}
export const SAME_WORDS = 0.6;

/**
 * Is `q` ({ key, text, topics }) a repeat of an earlier question the person answered? `earlier` are the person's turns so far
 * ([{ n, question: { key, text, topics }, understood, asked_back }]). Returns { repeat, of, why } where `of` is the turn number
 * of the earlier question and `why` is 'same key' | 'same topic' | 'same words'; or { repeat: false, rephrase } when the last
 * turn was not understood (so asking again is a rephrase, not a repeat).
 */
export function isRepeat(q, earlier) {
  if (!q || (!q.key && !q.text)) return { repeat: false };
  const prev = (earlier || []).filter((t) => t.question && (t.question.key || t.question.text));
  const last = prev.at(-1);
  for (const t of prev) {
    const why = q.key && t.question.key && q.key === t.question.key ? 'same key'
      : (q.topics || []).some((x) => x && !String(x).startsWith('unknown:') && (t.question.topics || []).includes(x)) ? 'same topic'
      : q.text && t.question.text && overlap(q.text, t.question.text) >= SAME_WORDS ? 'same words' : null;
    if (!why) continue;
    // asked again straight after the person did not understand it, or asked back: the platform is explaining, not repeating
    if (t === last && (t.understood === false || t.asked_back)) return { repeat: false, rephrase: true, of: t.n, why };
    return { repeat: true, of: t.n, why };
  }
  return { repeat: false };
}

/** A platform message that asks nothing (no question card, no question mark) while the request is not ready. */
export const isStuck = (t) => !!t && !(t.question && (t.question.key || t.question.text)) && !/[?؟]/.test(String(t.message || '')) && !/ready|sent|consumed/.test(String(t.status || ''));

/**
 * Would this person leave now? `turns` are the person's turns so far, each { n, latency_s (how long the platform took to
 * give the message this turn answers), repeat, question }. Checked after every platform message, before the person answers.
 * Returns { abandon: true, at: n, reason, rule } or { abandon: false }.
 */
export function shouldAbandon(turns, patience) {
  const P = patience || {}; const T = turns || [];
  const at = T.at(-1)?.n ?? 0;
  if (P.max_slow != null && P.slow_s != null) {
    const slow = T.filter((t) => Number(t.latency_s) > P.slow_s);
    if (slow.length >= P.max_slow) return { abandon: true, at, rule: 'slow', reason: `${slow.length} replies slower than ${P.slow_s} s (turns ${slow.map((t) => t.n).join(', ')}; the slowest ${Math.max(...slow.map((t) => Number(t.latency_s)))} s)` };
  }
  if (P.abandon_on_repeat != null) {
    const rep = T.filter((t) => t.repeat);
    if (rep.length >= P.abandon_on_repeat) return { abandon: true, at, rule: 'repeat', reason: `asked again what was already answered ${rep.length === 1 ? 'once' : rep.length + ' times'} (turn${rep.length > 1 ? 's' : ''} ${rep.map((t) => `${t.n}, first asked at turn ${t.repeat_of}`).join('; ')})` };
  }
  const stuckLimit = P.max_stuck === undefined ? 2 : P.max_stuck;
  if (stuckLimit != null) {
    let run = 0; for (let i = T.length - 1; i >= 0 && isStuck(T[i]); i--) run++;
    if (run >= stuckLimit) return { abandon: true, at, rule: 'stuck', reason: `${run} replies in a row asked nothing and the request was still not ready (status ${T.at(-1)?.status || '?'})` };
  }
  if (P.max_questions != null) {
    const asked = T.filter((t) => t.question && (t.question.key || t.question.text)).length;
    if (asked >= P.max_questions) return { abandon: true, at, rule: 'too_many_questions', reason: `${asked} questions and still not ready to send` };
  }
  return { abandon: false };
}
