// duty_voice — customer_support's duty updates are WRITTEN BY THE MODEL (27 Oct 2026). Seat: customer_support.
// Founder ruling, ledger 1339, verbatim: "the engineer and customer support never replies without llm unless the server
// of open router is down". Scope (ledger 1348): what a person reads as a reply or update from the seat is covered;
// legal/system notices (opt-out confirmation, sign-in codes, receipts) stay code-written.
//
// A SQL duty cannot call the model, so the duty records what it owes (fn_customer_support_voice_owe:
// scripts/sql/customer_support_writes_its_duty_updates_through_the_model.sql) — the situation, customer-safe facts,
// the text the message must carry, and a code-written DRAFT — and this writes it:
//   * one aiReply per voice_key (seat customer_support, e-mail); rows sharing a voice_key (an incident notice for every
//     person of one side and language) get the same words, one model call;
//   * modelOrOutage(reply, draft): the model's words, or the draft ONLY when no call reached a model (5xx, network,
//     timeout, open circuit; never a 4xx). fn_customer_support_voice_send refuses an outage body that is not the draft;
//   * model up and nothing passed the guard: nothing is sent, the attempt is counted (fn_customer_support_voice_failed)
//     and the row is asked again on the next run (the CEO is told at six).
// Run by resilience_ping's detached step supportVoice, every 15 minutes, with its own 120 s.
// prevented by: _shared/duty_voice.test.ts
import { aiReply, type AiReply } from './ai_reply.ts';
import { modelOrOutage } from './openrouter_down.ts';
import type { ThinkDeps } from './think.ts';

export interface OwedRow {
  stage: string; subject_key: string; voice_key: string; to_role: 'customer' | 'supplier'; to_email: string; lang: 'en' | 'ar';
  subject: string; draft: string; situation: string; facts: string; must: string[] | null;
}
export type Written = Pick<AiReply, 'reply' | 'outage' | 'attempts'>;
export interface VoiceIO {
  due(limit: number): Promise<OwedRow[]>;
  write(row: OwedRow): Promise<Written>;
  send(stage: string, key: string, body: string, by: 'model' | 'outage_fallback'): Promise<{ ok: boolean; err?: string }>;
  failed(stage: string, key: string, error: string): Promise<void>;
}

/** The e-mail format the model writes in. The words are its own; nothing internal is given to it (ledger 1338). */
export const VOICE_RULES = 'This is an e-mail we send them, not an answer to a question they asked: a short greeting line, two or three short ' +
  'paragraphs, and the sign-off "The QuotesDone team" (in Arabic: "فريق QuotesDone"). Plain text, no markdown. Use only the facts given; ' +
  'never mention a cause, a system, a provider, a model, a queue or any internal detail, and never promise a refund or a time the facts do not give.';

/** At most `groups` voice_keys a run (each one model reply), every row of a group sent with the same words. */
export async function writeOwedDutyMessages(io: VoiceIO, groups = 3): Promise<{ ok: true; written: number; by_model: number; by_outage: number; unwritten: number }> {
  const rows = await io.due(groups * 40);
  const byVoice = new Map<string, OwedRow[]>();
  for (const r of rows) {
    if (!byVoice.has(r.voice_key) && byVoice.size >= groups) continue;
    byVoice.set(r.voice_key, [...(byVoice.get(r.voice_key) ?? []), r]);
  }
  let written = 0, byModel = 0, byOutage = 0, unwritten = 0;
  for (const group of byVoice.values()) {
    const a: Written = await io.write(group[0]).catch((e) => ({ reply: '', outage: false, attempts: ['threw: ' + String((e as Error)?.message || e).slice(0, 120)] }));
    const said = String(a.reply ?? '').trim();
    for (const r of group) {
      // each row's own draft on an outage (a group's drafts are the same text; this keeps the send's draft check exact)
      const body = modelOrOutage(a, r.draft);
      if (!body) { unwritten++; await io.failed(r.stage, r.subject_key, 'the model is up and no draft passed the guard: ' + (a.attempts ?? []).join(' | ')); continue; }
      const by = said ? 'model' : 'outage_fallback';
      const s = await io.send(r.stage, r.subject_key, body, by);
      if (!s.ok) { unwritten++; await io.failed(r.stage, r.subject_key, 'send: ' + (s.err ?? 'refused')); continue; }
      written++; if (by === 'model') byModel++; else byOutage++;
    }
  }
  return { ok: true, written, by_model: byModel, by_outage: byOutage, unwritten };
}

/** The model call for one owed message: aiReply as customer_support on e-mail, bounded to 30 s. */
export function voiceWriter(deps: ThinkDeps, write: typeof aiReply = aiReply) {
  return (r: OwedRow): Promise<Written> => write(deps, {
    seat: 'customer_support', channel: 'e-mail', audience: r.to_role === 'supplier' ? 'supplier' : 'customer', lang: r.lang,
    message: r.situation, rules: VOICE_RULES, facts: r.facts, must: r.must ?? [], deadline: Date.now() + 30_000,
    ...(/@example\.invalid$/i.test(r.to_email) ? { subject: { fixture: true } } : {}),   // our own fixtures are never billed or counted
  });
}

// deno-lint-ignore no-explicit-any
type Admin = any;
export function liveVoiceIO(admin: Admin, deps: ThinkDeps): VoiceIO {
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(fn, args);
    if (error) throw new Error(fn + ': ' + error.message);
    return data;
  };
  return {
    due: async (limit) => ((await rpc('fn_customer_support_voice_due', { p_limit: limit })) ?? []) as OwedRow[],
    write: voiceWriter(deps),
    send: async (stage, key, body, by) => {
      // handled once the send ran: a refusal by the sending path (an address that does not accept mail, an opt-out) is
      // recorded on the row's result and in customer_support_duty_message, and is not asked of the model again
      try {
        await rpc('fn_customer_support_voice_send', { p_stage: stage, p_key: key, p_body: body, p_by: by });
        return { ok: true };
      } catch (e) { return { ok: false, err: String((e as Error)?.message || e).slice(0, 200) }; }
    },
    failed: async (stage, key, error) => { await rpc('fn_customer_support_voice_failed', { p_stage: stage, p_key: key, p_error: error }).catch(() => null); },
  };
}
