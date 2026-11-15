// scripts/e2e/journey_proof/personas/player.mjs — THE PERSONA PLAYER: a person, not a script, answers the platform. Seat:
// customer_support. Founder, 15 Nov 2026 (journey A): the engineer asked room sizes and the script answered "Inverter units,
// please." Here a model plays the person: it receives the persona's HIDDEN truth sheet (customers.mjs) and the platform's
// latest message, and answers ONLY what was asked, in character, or says it is not sure. Code only checks what the model
// returns (memory: the-llm-understands-code-only-checks.md): the ids it names exist, a file it sends is one the person has,
// a fact it claims to know is one the person knows, and it volunteered nothing the person was not asked.
//
// THE MODEL CALL (live): the platform's own gateway, ai_gateway, under the journey's run tag (x-qd-e2e-run), so every call is
// in ai_cost_log under that tag and the run's cap (fn_kernel_paid_provider_gate) stops it; fn journey_persona_player, task
// class json_extraction (model_policy 15 Nov 2026: openai/gpt-6-luna-pro, measured USD 0.00021 a call at 2.5k tokens in and
// 215 out over 418 calls in 14 days). The player also keeps its own cap: at most `maxCalls` calls and `capUsd` USD a journey.
// In the dry run and in the unit tests the model is stubComplete: deterministic, from the truth sheet, no network.
//
// EACH TURN IS RECORDED: { n, message, question: { key, text, topics }, latency_s, repeat, repeat_of, repeat_why, rephrase,
// understood, asked_back, reply, tap, answered, not_sure, file, problems, model, cost_usd } and, when the person leaves,
// player.abandoned = { at, rule, reason } (abandon.mjs). Nothing in this file touches the network except gatewayComplete.
import { isRepeat, shouldAbandon } from './abandon.mjs';

export const PERSONA_FN = 'journey_persona_player';
export const PERSONA_TASK_CLASS = 'json_extraction';
const LANG_WORDS = { en: 'English', ar: 'Gulf Arabic in Arabic script, mixed with the English words this person uses' };
const qText = (x) => (typeof x === 'string' ? x : (x?.text || x?.question || x?.label || ''));

/** The persona's system prompt: byte-stable for one persona (so the gateway may cache it); the truth sheet stays hidden. */
export function personaPrompt(p) {
  const facts = p.facts.map((f) => `- [${f.id}] ${f.about}: ${f.knows ? `you KNOW this. In your words, roughly: "${f.says}"` : `you do NOT know this. If asked, say so in your own words, roughly: "${f.says}"`}${f.file ? ` (you can send the file [${f.file}] instead)` : ''}`).join('\n');
  const files = (p.files || []).map((x) => `- [${x.id}] ${x.caption}`).join('\n') || '- none';
  const jargon = (p.jargon || []).map((r) => r.source.replace(/\\b|\\|\(|\)|\?|\.\*|\|/g, ' ').replace(/\s+/g, ' ').trim()).filter(Boolean).join(', ');
  return [
    'You are playing a CUSTOMER in a test of a procurement chat (QuotesDone, UAE). Stay in character. You are not an assistant and you are not helpful beyond what this person would be.',
    `WHO YOU ARE: ${p.label}, ${p.short}. How you write: ${p.voice}. Write in ${LANG_WORDS[p.lang] || 'English'}.`,
    'WHAT YOU KNOW AND DO NOT KNOW (hidden: never list it, never volunteer it):', facts,
    'FILES ON YOUR PHONE:', files,
    'RULES:',
    '1. Answer ONLY what the platform\'s latest message asks. Never add a fact it did not ask for, even one you know.',
    '2. If you do not know, say you are not sure, in your own words. Never invent a number, size, brand, model or date that is not above.',
    `3. If the question uses a word this person would not understand${jargon ? ` (for you: ${jargon})` : ''}, do not guess: ask what it means.`,
    '4. If the platform asks again something you already answered, say so the way this person would.',
    '5. Write as short as this person writes. No lists, no formatting, no sign-off.',
    '6. If answer buttons are offered and one is exactly what you would say, you may tap it (put its exact text in "tap").',
    '7. If a question asks for something one of your files shows, you may send the file (its id in "send_file") with a short line.',
    'Return STRICT JSON only, one line, no code fence: {"reply":"what you type","tap":null,"understood":true,"asked_back":false,"asked_topics":["ids of the facts the question asks about"],"answered":["ids you answered"],"not_sure":["ids you said you do not know"],"send_file":null,"already_answered":false}',
  ].join('\n');
}

/** The turn's input: the chat so far (short), the platform's latest message and its question card. */
export function turnInput({ history = [], message = '', question = null }) {
  const h = history.slice(-12).map((t) => `${t.role === 'customer' ? 'You' : 'Platform'}: ${String(t.text || '').slice(0, 600)}`).join('\n');
  const card = question && (question.text || question.key) ? `\nITS QUESTION CARD: "${qText(question)}"${question.options?.length ? ` [buttons: ${question.options.map(qText).join(' | ')}]` : ''}` : '\n(no question card)';
  return `THE CHAT SO FAR (latest last):\n${h || '(nothing yet)'}\n\nTHE PLATFORM'S LATEST MESSAGE: ${String(message || '').slice(0, 2000)}${card}`;
}

/** Which facts a question asks about, without a model: its key first, then its words (at most two facts). */
export function topicsFor(p, question) {
  const key = question?.key ? String(question.key) : '';
  const text = [qText(question), question?.message || ''].join(' ');
  const byKey = key ? p.facts.filter((f) => (f.keys || []).includes(key)) : [];
  if (byKey.length) return byKey.slice(0, 2).map((f) => f.id);
  const byWords = p.facts.filter((f) => f.re && f.re.test(qText(question) || text));
  return byWords.slice(0, 2).map((f) => f.id);
}

const LINES = {
  en: { unknown: 'Not sure, sorry.', again: 'I already told you: ', what: (w) => `What do you mean by "${w}"?`, nothing: 'OK. Is that everything? Can you send it to the suppliers?', file: '(sent a photo)' },
  ar: { unknown: 'والله ما أعرف', again: 'قلت لك: ', what: (w) => `شو يعني "${w}"؟`, nothing: 'تمام. خلاص؟ ترسلونه للموردين؟', file: '(أرسل صورة)' },
};
const lines = (p) => ({ ...LINES.en, ...(LINES[p.lang] || {}), ...(p.lines || {}) });

/**
 * THE DETERMINISTIC STUB MODEL (dry run, unit tests): what a faithful player of the truth sheet would return, as the same
 * JSON a model returns. It reads the structured turn handed to it (ctx), never the prompt text.
 */
export function stubComplete(p) {
  return async ({ ctx }) => {
    const L = lines(p); const q = ctx.question || null; const text = qText(q);
    const out = { reply: '', tap: null, understood: true, asked_back: false, asked_topics: [], answered: [], not_sure: [], send_file: null, already_answered: false };
    if (!q || (!q.key && !text)) { out.reply = L.nothing; return { ok: true, content: JSON.stringify(out), model: 'stub/persona', cost_usd: 0 }; }
    const jar = (p.jargon || []).map((r) => (text.match(r) || [])[0]).find(Boolean);
    out.asked_topics = topicsFor(p, q);
    const facts = out.asked_topics.map((id) => p.facts.find((f) => f.id === id)).filter(Boolean);
    if (jar) {   // they do not understand the word; if a file on their phone would show it, they offer that instead
      out.understood = false; out.asked_back = true; out.reply = L.what(jar);
      const withFile = facts.find((f) => f.file && !(ctx.files_sent || []).includes(f.file));
      if (withFile) { out.send_file = withFile.file; out.not_sure = [withFile.id]; out.reply += ' ' + withFile.says; }
      return { ok: true, content: JSON.stringify(out), model: 'stub/persona', cost_usd: 0 };
    }
    if (!facts.length) { out.not_sure = [`unknown:${q.key || 'question'}`]; out.reply = L.unknown; return { ok: true, content: JSON.stringify(out), model: 'stub/persona', cost_usd: 0 }; }
    const said = new Set(ctx.answered_before || []);
    const parts = [];
    for (const f of facts) {
      if (said.has(f.id)) { out.already_answered = true; parts.push(L.again + f.says); continue; }
      if (f.file && !(ctx.files_sent || []).includes(f.file)) out.send_file = f.file;
      (f.knows ? out.answered : out.not_sure).push(f.id); parts.push(f.says);
    }
    out.reply = parts.join(' ');
    return { ok: true, content: JSON.stringify(out), model: 'stub/persona', cost_usd: 0 };
  };
}

/**
 * THE LIVE MODEL: one call to the platform's ai_gateway under the run tag. Every argument is what the harness already holds
 * (fixtures.mjs openRun, demo_factory keys/internalCred); nothing here is a new secret. Returns the same shape as the stub.
 */
export function gatewayComplete({ base, service, fnSecret, e2eSecret, runTag, subject = null, timeoutMs = 60000, fetchImpl = fetch }) {
  if (!base || !service || !runTag) throw new Error('gatewayComplete needs base, service and the run tag (a persona call is never untagged)');
  return async ({ sys, input }) => {
    const r = await fetchImpl(`${base}/functions/v1/ai_gateway`, { method: 'POST',
      headers: { 'content-type': 'application/json', Authorization: `Bearer ${service}`, 'x-qd-e2e-run': runTag, ...(e2eSecret ? { 'x-qd-e2e-secret': e2eSecret } : {}) },
      body: JSON.stringify({ __secret: fnSecret, fn: PERSONA_FN, task_class: PERSONA_TASK_CLASS, sys, input, max: 400, temperature: 0.8,
        response_format: { type: 'json_object' }, client_timeout_ms: timeoutMs - 5000, ...(subject ? { subject } : {}) }),
      signal: AbortSignal.timeout(timeoutMs) });
    const j = await r.json().catch(() => ({}));
    return { ok: r.ok && !!j.content, content: j.content ?? null, model: j.model ?? j.model_used ?? null, cost_usd: Number(j.cost_usd) || 0, error: j.error ?? (r.ok ? null : `HTTP ${r.status}`) };
  };
}

const parseJson = (s) => { try { return JSON.parse(String(s ?? '').replace(/^[^{]*/, '').replace(/[^}]*$/, '')); } catch { return null; } };
/** The numbers a person says (not the 2 of "m2", not the 2 of "2.5" on its own). */
const numbersOf = (s) => String(s).match(/(?<![\p{L}\d.,])\d+(?:[.,]\d+)?/gu) || [];
const hasNumber = (text, n) => new RegExp(`(?<![\\p{L}\\d.,])${n.replace(/[.,]/g, '[.,]')}(?![\\d]|[.,]\\d)`, 'u').test(text);

/**
 * Code checks what the model returned (never rewrites the reply): unknown ids dropped, a "known" fact the person does not
 * know moved to not_sure, a file the person does not have (or already sent) dropped, and any number from a fact the person
 * was not asked about found in the reply is named as volunteered. Returns the checked turn and the problems found.
 */
export function checkReply(p, raw, { filesSent = [], openerText = '' } = {}) {
  const problems = [];
  const j = parseJson(raw);
  if (!j || typeof j !== 'object') return { ok: false, problems: ['the player did not return JSON'] };
  const ids = new Set(p.facts.map((f) => f.id));
  const keep = (arr, what) => (Array.isArray(arr) ? arr : []).map(String).filter((x) => { if (ids.has(x) || x.startsWith('unknown:')) return true; problems.push(`${what}: "${x}" is not a fact of this person`); return false; });
  const out = { reply: String(j.reply ?? '').trim(), tap: j.tap ? String(j.tap) : null, understood: j.understood !== false, asked_back: j.asked_back === true,
    asked_topics: keep(j.asked_topics, 'asked_topics'), answered: keep(j.answered, 'answered'), not_sure: keep(j.not_sure, 'not_sure'), send_file: j.send_file ? String(j.send_file) : null, already_answered: j.already_answered === true };
  for (const id of [...out.answered]) { const f = p.facts.find((x) => x.id === id); if (f && !f.knows) { problems.push(`claimed to know "${id}", which this person does not know`); out.answered = out.answered.filter((x) => x !== id); if (!out.not_sure.includes(id)) out.not_sure.push(id); } }
  if (out.send_file && (!(p.files || []).some((x) => x.id === out.send_file) || filesSent.includes(out.send_file))) { problems.push(`send_file "${out.send_file}" is not a file this person still has to send`); out.send_file = null; }
  if (!out.reply && !out.tap && !out.send_file) { problems.push('an empty reply'); return { ok: false, problems, ...out }; }
  const asked = new Set([...out.asked_topics, ...out.answered, ...out.not_sure]);
  // a number in the reply is explained by the opener or by a fact the turn is about; any other fact's number is volunteered
  const explained = new Set([...numbersOf(openerText), ...p.facts.filter((f) => asked.has(f.id)).flatMap((f) => numbersOf(f.says))]);
  const volunteered = p.facts.filter((f) => f.knows && !asked.has(f.id) && numbersOf(f.says).some((n) => !explained.has(n) && hasNumber(out.reply, n))).map((f) => f.id);
  if (volunteered.length) problems.push(`volunteered what was not asked: ${volunteered.join(', ')}`);
  return { ok: true, problems, volunteered, ...out };
}

/**
 * One person in one chat. `complete` is stubComplete(persona) or gatewayComplete(...). Call opener() once, then turn() with
 * every platform message until it returns { abandoned } or the platform is ready.
 */
export function createPlayer({ persona, complete, maxCalls = 40, capUsd = 0.05 }) {
  const p = persona; const history = []; const turns = []; const filesSent = [];
  const spend = { calls: 0, usd: 0, models: new Set() };
  let abandoned = null; let openerText = '';
  const answeredBefore = () => turns.flatMap((t) => [...(t.answered || []), ...(t.not_sure || [])]).concat(p.opener_topics || []);
  return {
    persona: p, turns, history, spend, filesSent,
    get abandoned() { return abandoned; },
    opener() { openerText = p.opener; history.push({ role: 'customer', text: p.opener }); return { text: p.opener, topics: [...(p.opener_topics || [])] }; },
    /**
     * The platform said `message` (its question card `question`, `latency_s` after the person's last message). Returns the
     * turn record; `turn.abandoned` is set when the person leaves instead of answering (then `reply` is null).
     */
    async turn({ message = '', question = null, latency_s = null, status = null }) {
      const n = turns.length + 1;
      const prose = String(message || '').split(/(?<=[.!?؟])\s+/).filter((x) => /[?؟]\s*$/.test(x)).pop();
      const q = question && (question.key || qText(question)) ? { key: question.key ?? null, text: qText(question), options: (question.options || []).map(qText), suggested: question.suggested ?? null }
        : prose ? { key: null, text: prose.trim(), options: [], suggested: null } : null;   // no card: a question asked in words is the question
      history.push({ role: 'platform', text: message || (q ? q.text : '') });
      const t = { n, at: new Date().toISOString(), status, message: String(message || ''), question: q ? { key: q.key, text: q.text, topics: [] } : null, latency_s,
        repeat: false, repeat_of: null, repeat_why: null, rephrase: false, understood: null, asked_back: false, reply: null, tap: null, answered: [], not_sure: [], file: null, problems: [], model: null, cost_usd: 0 };
      // before paying for a call: slow, or asked again by key or by words, is enough for this person to leave
      const pre = q ? isRepeat({ key: q.key, text: q.text }, turns) : { repeat: false };
      if (pre.repeat) Object.assign(t, { repeat: true, repeat_of: pre.of, repeat_why: pre.why }); else if (pre.rephrase) t.rephrase = true;
      turns.push(t);
      let gone = shouldAbandon(turns, p.patience);
      if (gone.abandon) { abandoned = { at: n, rule: gone.rule, reason: gone.reason }; t.abandoned = abandoned; return t; }
      if (spend.calls >= maxCalls || spend.usd >= capUsd) { t.problems.push(`the player's own cap was reached (${spend.calls} calls, USD ${spend.usd.toFixed(4)})`); abandoned = { at: n, rule: 'player_cap', reason: 'the test stopped the person: its own spending cap' }; t.abandoned = abandoned; return t; }
      const ctx = { question: q, message, answered_before: answeredBefore(), files_sent: [...filesSent] };
      let res = null; let checked = null;
      for (let attempt = 0; attempt < 2 && !checked?.ok; attempt++) {
        res = await complete({ sys: personaPrompt(p), input: turnInput({ history: history.slice(0, -1), message, question: q }), ctx });
        spend.calls++; spend.usd += Number(res?.cost_usd) || 0; if (res?.model) spend.models.add(res.model);
        if (!res?.ok) { t.problems.push(`the player's model call failed: ${res?.error || 'no content'}`); continue; }
        checked = checkReply(p, res.content, { filesSent, openerText });
        if (!checked.ok) t.problems.push(...checked.problems);
      }
      t.model = res?.model ?? null; t.cost_usd = Number(res?.cost_usd) || 0;
      if (!checked?.ok) { t.problems.push('the person could not answer (the player failed twice); counted as the person leaving'); abandoned = { at: n, rule: 'player_failed', reason: 'the test could not produce the person\'s reply' }; t.abandoned = abandoned; return t; }
      t.problems.push(...checked.problems);
      if (t.question) t.question.topics = checked.asked_topics;
      // with the topics the person heard, a question about something already answered is a repeat too
      if (!t.repeat && !t.rephrase && t.question) {
        const r = isRepeat(t.question, turns.slice(0, -1));
        if (r.repeat) Object.assign(t, { repeat: true, repeat_of: r.of, repeat_why: r.why }); else if (r.rephrase) t.rephrase = true;
      }
      if (!t.repeat && checked.already_answered && !t.rephrase && t.question) Object.assign(t, { repeat: true, repeat_of: null, repeat_why: 'the person said it was already answered' });
      gone = shouldAbandon(turns, p.patience);
      if (gone.abandon) { abandoned = { at: n, rule: gone.rule, reason: gone.reason }; t.abandoned = abandoned; return t; }
      Object.assign(t, { understood: checked.understood, asked_back: checked.asked_back, reply: checked.reply || null, tap: checked.tap, answered: checked.answered, not_sure: checked.not_sure, file: checked.send_file });
      if (t.tap && !(q?.options || []).includes(t.tap)) { t.problems.push(`tapped "${t.tap}", which is not one of the buttons`); t.tap = null; }
      if (t.file) filesSent.push(t.file);
      history.push({ role: 'customer', text: t.tap ? `(tapped "${t.tap}")` : `${t.reply || ''}${t.file ? ` ${lines(p).file}` : ''}` });
      return t;
    },
  };
}
