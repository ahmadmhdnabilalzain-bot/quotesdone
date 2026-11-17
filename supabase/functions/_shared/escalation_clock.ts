// _shared/escalation_clock.ts — every escalation is a case with a clock, the CEO seat decides it, customer_support tells the
// person (customer_support + ceo, agent FOUNDER_CLOCK, 16 Nov 2026; founder rulings 1696, 1706, 1710: the CEO has full
// authority, the seats never bring the founder issues, "don't wait on me").
//
// WHAT WAS WRONG (hole hunt of 16 Nov 2026, FAILURES items 1, 4, 7, 11). A person request paged the founder and was left
// 'with_founder', read by nothing; the e-mail had promised "a member of the team will reply in this same thread". A WhatsApp
// escalation was "accepted" by the CEO every day and never completed (SELECT: 137 accepted, 0 completed). A payer held by the
// live Stripe hold was promised "our team will be in touch" by nobody. No seat knew the founder was away.
//
// WHAT THIS FILE IS. The CEO seat's heartbeat (ceo_agent action escalation_clocks, driven by resilience_ping's it_engineer
// later duties) works the clocks public.fn_escalation_clocks_due hands it, one model call per job:
//   decide  the CEO's MODEL reads the case (their words, what we promised and when, how long they waited, the founder's
//           absence, the company's press and legal position) and decides within its authority, or says what is missing, or
//           names the law that reserves the matter to the founder (the only road to him; SQL refuses a founder answer that
//           names no law);
//   tell    customer_support's MODEL writes the person the decision (or, for a held payer, that payment is open);
//   status  the clock ran out with no decision: customer_support's MODEL writes an honest status -- what we promised, that we
//           are late if we are, where it stands, and when they will hear again (the one time it may name, because the clock
//           keeps it).
// Every word to the person is the model's (ruling 1339: no code-written reply unless OpenRouter is down; when no model writes,
// nothing is sent and the clock retries in an hour). Delivery is SQL's (fn_escalation_clock_deliver: the person's own channel,
// WhatsApp only in their window, e-mail through the duty send, a fixture never). No import here: the live IO (ceo_agent) and the
// test pass their own, so the one path is the one that is proved.
// prevented by: _shared/escalation_clock.test.ts, scripts/sql/every_escalation_carries_a_clock_and_the_ceo_decides_it_not_the_founder_probe.sql
import { parseJson } from './model_json.ts';
import { BRIEF_PRESS_LEGAL } from './brief.generated.ts';

export type DueFor = 'decide' | 'tell' | 'status';
export interface FounderFacts {
  founder_last_answered_at?: string | null; founder_hours_since?: number | null;
  channels_down_founder_credential?: { integration: string; what: string; since: string }[];
}
export interface DueClock {
  id: number; ref: string; due_for: DueFor; kind: string; channel: string; audience: string; lang: 'en' | 'ar'; state: string;
  subject_line?: string | null; request_text?: string | null; promised: string; promised_at: string; hours_waiting: number;
  statuses_sent: number; last_told_at?: string | null; last_told_text?: string | null; ceo_decision?: string | null;
  ceo_reason?: string | null; founder_reason?: string | null; next_word_in_hours: number; switch_reads_off: boolean;
  has_contact: boolean; status_due?: boolean; stale_days?: number | null; founder?: FounderFacts;
}
export interface CeoDecision {
  decision: 'decided' | 'not_yet' | 'founder_by_law'; outcome: string; reasons: string; law: string | null;
  standing: 'customer' | 'supplier' | 'press' | 'legal' | 'regulator' | null;
}
export type ModelAnswer = { content: string | null; model: string | null; error?: string | null };
export interface ClockIO {
  due(limit: number): Promise<DueClock[]>;
  askCeo(c: DueClock, system: string, input: string): Promise<ModelAnswer>;
  decided(id: number, d: CeoDecision, model: string): Promise<unknown>;
  ceoFailed(id: number, error: string): Promise<unknown>;
  write(c: DueClock, system: string, input: string): Promise<ModelAnswer>;
  deliver(id: number, stage: string, subject: string, body: string): Promise<{ sent: boolean; via?: string | null; reason?: string | null }>;
  told(id: number, stage: string, result: Record<string, unknown>, text: string): Promise<unknown>;
  now?: () => number;
}

export const CEO_TASK_CLASS = 'ceo_judgement';            // the class the review decider already uses (review_decide.ts)
export const SUPPORT_TASK_CLASS = 'conversation_reply';   // customer_support's reply class (ai_reply.ts REPLY_CLASS)

/** The company's press, legal-notice and regulator position: knowledge/brief/press_and_legal.md, compiled as BRIEF_PRESS_LEGAL (the one
 *  copy; not in the core every reply carries, which is at its token cap). The section itself, without the file's own header. */
export function pressLegalPosition(text: string = BRIEF_PRESS_LEGAL): string {
  const at = text.indexOf('## Press');
  return (at < 0 ? text : text.slice(at)).trim();
}

const dubai = (iso: string | null | undefined): string => {
  if (!iso) return 'unknown';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return 'unknown';
  return new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Dubai', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }).format(d) + ' Dubai time';
};

/** When the person will next hear from us (the clock's repeat), as words the message may state. */
export function nextWordBy(c: Pick<DueClock, 'next_word_in_hours'>, now = Date.now()): string {
  return dubai(new Date(now + Math.max(1, Number(c.next_word_in_hours) || 24) * 3_600_000).toISOString());
}

// ── decide ────────────────────────────────────────────────────────────────────────────────────────────────────────────
export function ceoPrompt(c: DueClock): { system: string; input: string } {
  const system = 'You are the CEO of QuotesDone, a UAE procurement marketplace (QuotesDone Technologies, Dubai). You have full authority '
    + 'over the company\'s internal decisions: the founder is not asked and nothing waits for him (his rulings 1696, 1706, 1710). An '
    + 'escalation from customer support is on your desk with its clock. Read it like a duty manager who owns it: what the person wants, '
    + 'what we promised them, on which channel, and how long they have waited. Decide it now within your authority ("decided"), with the '
    + 'outcome customer support will tell them. Say "not_yet" only when a fact you need is missing, and name it. Say "founder_by_law" ONLY '
    + 'when the law reserves the matter to the founder personally (for example a court summons or a regulator\'s demand addressed to the '
    + 'licence holder in person), and name that law; a complaint, a request for a person, a refund, a journalist or a lawyer\'s letter '
    + 'is yours, answered through the company\'s position below. You never move money by words: a refund or credit you approve goes to '
    + 'its own process and you promise no date for it. Never invent a fact that is not in the input. Read also who is writing: a '
    + 'journalist (press), a lawyer or a legal notice (legal), a government authority (regulator), or a customer or supplier. If the input '
    + 'shows you sent this case to the founder by law before and he has not answered, decide it again now: decide what you can within your '
    + 'authority, or name the law again only if it truly still requires him in person.\n'
    + 'Return STRICT JSON ONLY: {"decision":"decided|not_yet|founder_by_law","standing":"customer|supplier|press|legal|regulator",'
    + '"outcome":"what happens now, one or two plain sentences as the person will be told it (for not_yet: what is being done)",'
    + '"reasons":"two to four factual sentences","law":"only for founder_by_law: the law that requires the founder in person; otherwise empty"}';
  const input = JSON.stringify({
    case: c.ref, kind: c.kind, channel: c.channel, who: c.audience, their_words: c.request_text ?? null, subject: c.subject_line ?? null,
    we_promised: c.promised, promised_at: dubai(c.promised_at), hours_waiting: c.hours_waiting, statuses_already_sent: c.statuses_sent,
    last_message_we_sent: c.last_told_text ?? null, days_left_unanswered_before_this_clock: c.stale_days ?? null,
    founder: { last_answered_the_company: dubai(c.founder?.founder_last_answered_at), hours_since: c.founder?.founder_hours_since ?? null,
               channels_down_until_he_renews_a_credential: c.founder?.channels_down_founder_credential ?? [] },
    company_position_press_legal_regulator: pressLegalPosition(),
    // decided again 72 hours after a founder_by_law answer (fn_escalation_clocks_due): what was answered then, and that he has not answered
    ...(c.state === 'founder_by_law' ? { your_earlier_answer: { decision: 'founder_by_law', law_you_named: c.founder_reason ?? null,
      your_reasons: c.ceo_reason ?? null, founder_has_not_answered: true } } : {}),
  });
  return { system, input };
}

/** 'n/a', 'none', '-' or empty name no law (the same rule as fn_escalation_clock_ceo_decided). */
export const namesNoLaw = (law: string | null | undefined): boolean => /^\s*(n\s*\/?\s*a|none|-+)?\s*\.?\s*$/i.test(String(law ?? ''));

const STANDINGS = ['customer', 'supplier', 'press', 'legal', 'regulator'] as const;
/** The CEO model's answer as a decision, or null. Tolerates a ```json fence; nothing else. */
export function parseCeoDecision(text: string | null): CeoDecision | null {
  try {
    // deno-lint-ignore no-explicit-any
    const o = parseJson<any>(text, { exact: true });
    if (!o || !['decided', 'not_yet', 'founder_by_law'].includes(o.decision)) return null;
    const reasons = String(o.reasons ?? '').trim(); const outcome = String(o.outcome ?? '').trim();
    if (!reasons || (o.decision === 'decided' && !outcome)) return null;
    const law = String(o.law ?? '').trim();
    return { decision: o.decision, outcome, reasons, law: namesNoLaw(law) ? null : law,
             standing: (STANDINGS as readonly string[]).includes(o.standing) ? o.standing : null };
  } catch (_e) { return null; }
}

// ── tell / status ─────────────────────────────────────────────────────────────────────────────────────────────────────
export type Purpose = 'decision' | 'status' | 'by_law' | 'payment_open' | 'payment_status';
export function purposeOf(c: DueClock): Purpose {
  if (c.kind === 'held_payment') return c.switch_reads_off ? 'payment_open' : 'payment_status';
  if (c.due_for === 'tell' || c.state === 'decided') return 'decision';
  if (c.state === 'founder_by_law') return 'by_law';
  return 'status';
}
export function stageOf(c: DueClock, p: Purpose): string {
  return p === 'decision' ? 'decision' : p === 'payment_open' ? 'payment_open' : 'status_' + (Number(c.statuses_sent || 0) + 1);
}

const WHERE_IT_STANDS: Record<Purpose, string> = {
  decision: 'The matter is decided. Tell them the decision and its reason in plain words, exactly as decided; add nothing to it.',
  status: 'It is with the manager who makes the decision at QuotesDone and is not decided yet. Say what is being done, without blaming anyone.',
  by_law: 'It needs the company\'s legal representative in person, who has been told, and it is being handled. Promise no outcome.',
  payment_open: 'Card payment on QuotesDone is now open: they can complete, from their account, the payment they tried before. Nothing was charged then.',
  payment_status: 'Card payment on QuotesDone is not open yet. Nothing has been charged and their quotes or account are kept. We will write to them here the day it opens; give no date for it.',
};

export function messagePrompt(c: DueClock, p: Purpose, now = Date.now()): { system: string; input: string } {
  const tellNext = p !== 'decision' && p !== 'payment_open';
  const pressy = ['press', 'legal', 'regulator'].includes(c.kind);
  const system = 'You are QuotesDone Customer Support. Write the message we now send to a person who is waiting on us, on ' + c.channel.replace('_', ' ')
    + '. Be honest and plain, like a duty manager who owns the case: say what we told them and when, truthfully; if we are later than we said, '
    + 'apologise once, plainly, without excuses; then where it stands: ' + WHERE_IT_STANDS[p]
    + (tellNext ? ' End with when they will next hear from us: by ' + nextWordBy(c, now) + ' (the system keeps this). Promise nothing else.' : ' Promise nothing beyond it.')
    + ' Never name a person, never mention the founder, never say "AI", never give a licence number, never promise a refund, a date or an outcome that is not written above.'
    + (pressy ? ' They write as ' + c.kind + ': keep to the company position in the input word for word in substance; no comment, opinion or figure beyond it.' : '')
    + ' Write in ' + (c.lang === 'ar' && c.audience !== 'supplier' ? 'formal Gulf Arabic' : 'UAE English') + ', two to five sentences, plain text, signed "QuotesDone Customer Support".'
    + '\nReturn STRICT JSON ONLY: {"subject":"a short e-mail subject","message":"the message"}';
  const input = JSON.stringify({
    case: c.ref, their_words: c.request_text ?? null, we_told_them: c.promised, told_at: dubai(c.promised_at), hours_waiting: c.hours_waiting,
    messages_already_sent_on_this_case: c.statuses_sent, last_message_we_sent: c.last_told_text ?? null,
    decision: p === 'decision' ? c.ceo_decision ?? null : null,
    ...(pressy ? { company_position: pressLegalPosition() } : {}),
  });
  return { system, input };
}

export function parseMessage(text: string | null): { subject: string; message: string } | null {
  try {
    const o = parseJson(text, { exact: true });
    const message = String(o?.message ?? '').trim();
    return message ? { subject: String(o?.subject ?? '').trim().slice(0, 140), message: message.slice(0, 3000) } : null;
  } catch (_e) { return null; }
}

/** Customer support writes and sends one message on a clock. Never throws. */
async function tell(io: ClockIO, c: DueClock, p: Purpose): Promise<Record<string, unknown>> {
  const stage = stageOf(c, p);
  // no e-mail and no number on file (an anonymous site visitor): no model is asked to write what cannot be sent
  if (c.has_contact === false) {
    const reason = 'no open channel: no e-mail or phone on file';
    await io.told(c.id, stage, { sent: false, reason }, '');
    return { id: c.id, stage, sent: false, reason };
  }
  const { system, input } = messagePrompt(c, p, io.now?.() ?? Date.now());
  const a = await io.write(c, system, input);
  const msg = parseMessage(a.content);
  if (!msg) {
    // ruling 1339: no code-written message stands in for the model's; nothing is sent and the clock retries in an hour
    const reason = 'no model wrote the message' + (a.error ? ': ' + a.error : '');
    await io.told(c.id, stage, { sent: false, reason }, '');
    return { id: c.id, stage, sent: false, reason };
  }
  const res = await io.deliver(c.id, stage, msg.subject, msg.message);
  await io.told(c.id, stage, { ...res, model: a.model }, msg.message);
  return { id: c.id, stage, sent: res.sent, via: res.via ?? null, reason: res.reason ?? null };
}

/** Work up to `limit` due clocks. Never throws; each outcome is returned. */
export async function workEscalationClocks(io: ClockIO, limit = 3): Promise<Record<string, unknown>[]> {
  const out: Record<string, unknown>[] = [];
  let due: DueClock[] = [];
  try { due = await io.due(limit); } catch (e) { return [{ ok: false, error: 'due: ' + String((e as Error)?.message ?? e) }]; }
  for (const c0 of due) {
    let c = c0;
    try {
      if (c.due_for === 'decide') {
        const { system, input } = ceoPrompt(c);
        const a = await io.askCeo(c, system, input);
        const d = parseCeoDecision(a.content);
        if (!a.model || !d) {
          const why = a.error ? 'no answer: ' + a.error : !a.content ? 'no answer' : 'MALFORMED_DECISION: the reply is not one decision object';
          await io.ceoFailed(c.id, why);
          out.push({ id: c.id, decide: false, error: why });
          // the clock still runs: when it is past due the person gets an honest status this same tick
          if (c.status_due) out.push(await tell(io, c, purposeOf({ ...c, due_for: 'status' })));
          continue;
        }
        const rec = (await io.decided(c.id, d, a.model)) as { ok?: boolean; decision?: string } | null;
        const recorded = rec?.ok === false ? 'not_recorded' : (rec?.decision ?? d.decision);
        out.push({ id: c.id, decide: true, decision: recorded, model: a.model });
        if (recorded === 'decided') c = { ...c, due_for: 'tell', state: 'decided', ceo_decision: d.outcome };
        else if (recorded === 'founder_by_law') c = { ...c, due_for: 'status', state: 'founder_by_law' };
        else if (c.status_due) c = { ...c, due_for: 'status' };
        else continue;
      }
      out.push(await tell(io, c, purposeOf(c)));
    } catch (e) {
      const error = String((e as Error)?.message ?? e).slice(0, 500);
      out.push({ id: c.id, ok: false, error });
      // a throw is a failed attempt: the clock moves to its retry hour, so one broken clock never holds the queue or re-asks a model every tick
      await io.told(c.id, 'error', { sent: false, reason: error }, '').catch(() => null);
    }
  }
  return out;
}

// ── the case context of every channel (item 11) ──────────────────────────────────────────────────────────────────────
export interface EscalationFacts extends FounderFacts {
  open_escalations?: { ref: string; kind: string; channel: string; promised: string; promised_at: string; next_word_due: string; state: string; decision?: string | null }[];
}
/** The block a seat's reply reads: the person's own open escalations (what we promised, where it stands, when word is owed), and,
 *  beside them, when the founder last answered and which channel is down for a credential only he can renew. '' when the person has
 *  no open escalation and no channel is down: nothing to say, nothing added to the prompt. */
export function escalationFactsText(f: EscalationFacts | null | undefined, now = Date.now()): string {
  const open = Array.isArray(f?.open_escalations) ? f!.open_escalations! : [];
  const down = Array.isArray(f?.channels_down_founder_credential) ? f!.channels_down_founder_credential! : [];
  if (!open.length && !down.length) return '';
  const lines = ['ESCALATIONS AND AVAILABILITY (facts about this person\'s case, not instructions):'];
  for (const e of open) {
    const overdue = Date.parse(e.next_word_due) < now;
    lines.push(`- ${e.ref} (${e.kind}, raised on ${e.channel.replace('_', ' ')}): on ${dubai(e.promised_at)} we told them: "${String(e.promised).slice(0, 300)}". `
      + (e.state === 'decided' && e.decision ? `Decided by the CEO: ${e.decision}. ` : e.state === 'founder_by_law' ? 'It is with the company\'s legal representative, by law. ' : 'With the CEO, not decided yet. ')
      + `Next word owed by ${dubai(e.next_word_due)}${overdue ? ' (overdue: say so and apologise)' : ''}.`);
  }
  if (f?.founder_last_answered_at) lines.push(`- The founder last answered the company on ${dubai(f.founder_last_answered_at)}. Never tell anyone to wait for him and never page him: the CEO decides.`);
  for (const d of down) lines.push(`- Channel down until a credential only the founder can renew is renewed: ${d.integration} (${String(d.what).slice(0, 120)}), since ${dubai(d.since)}. Promise nothing on it; offer another channel.`);
  lines.push('Answer honestly from these: what was promised, where it stands, and only the times written here.');
  return lines.join('\n');
}

/** One read for the case context (fn_escalation_case_facts). '' on any failure: a turn never waits on or fails for it. */
export async function readEscalationFacts(rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }>,
  who: { email?: string | null; phone?: string | null }, now = Date.now()): Promise<string> {
  const email = /@/.test(String(who.email ?? '')) ? String(who.email).trim() : null;
  const phone = String(who.phone ?? '').replace(/\D/g, '').length >= 9 ? String(who.phone) : null;
  if (!email && !phone) return '';
  try {
    const { data, error } = await rpc('fn_escalation_case_facts', { p_email: email, p_phone: phone });
    if (error || !data || typeof data !== 'object') return '';
    return escalationFactsText(data as EscalationFacts, now);
  } catch (_e) { return ''; }
}

// ── who is writing (item 4): the triage reading's second answer, in the same model call ───────────────────────────────
export const STANDING_OPTIONS = [
  { id: 'press', meaning: 'they write as a journalist, reporter, editor, blogger or media outlet asking for a comment, an interview, figures or a statement' },
  { id: 'legal', meaning: 'they write as a lawyer or law firm, or send a legal notice, a claim letter, a demand before action, a court document or a police matter' },
  { id: 'regulator', meaning: 'they write for a government authority or regulator (a ministry, the Department of Economy and Tourism, a free-zone authority, the UAE Data Office, the police or a court) in that capacity' },
  { id: 'party', meaning: 'anyone else: a customer, a supplier, a visitor or a business asking about the service, however angry, and however much they mention law, lawyers or the press as a threat or a topic' },
];
export type Standing = 'press' | 'legal' | 'regulator';
export const isStanding = (v: unknown): v is Standing => v === 'press' || v === 'legal' || v === 'regulator';

/** The rules of the holding reply to a journalist, a lawyer or a regulator: the company's position from the brief, no comment. */
export function holdingRules(s: Standing): string {
  const who = s === 'press' ? 'a journalist or media request' : s === 'legal' ? 'a lawyer\'s letter or legal notice' : 'a regulator or authority';
  return ` This is ${who}. Reply only with the company's holding line from the POSITION below: acknowledge receipt, say it has been passed to the `
    + 'management of QuotesDone Technologies, who will reply, and give the address for formal correspondence. No comment on the substance, no admission, '
    + 'no figure, no name of any customer or supplier, no opinion, no date.\nPOSITION:\n' + pressLegalPosition();
}
