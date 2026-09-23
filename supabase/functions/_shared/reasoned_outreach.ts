// reasoned_outreach — what a LinkedIn prospect's reply MEANS: reasoned, never word-matched. Seat: marketing.
// 23 Sep 2026, founder_instruction 886-903 (decision point marketing.outreach_reply).
//
// BEFORE: marketing_outreach.ts classifyReply ran three regex lists (decline / later / positive, EN and AR) over the
// reply the founder pasted, and the first list that matched chose the follow-up he was handed AND whether the person
// was closed as declined. "Not interested" contains "interested", so the lists had to be ordered; "no" inside "not
// now", a polite "thank you, not for now", or a question that happens to say "busy" were read by their words.
//
// NOW: replyClass asks think() to choose among the four meanings, over the whole reply and the message it answers.
// UNDER THE HOLD it returns null: the reply is recorded as replied, nobody is closed and no follow-up is drafted on
// a guess; the question waits in the marketing seat's queue (dedupe outreach_reply:<mark token>). When the hold
// lifts, replayHeld reasons it and deliverOutreach (called from reasoned_delivery.ts) records the reasoned class,
// closes a decline, and drafts the follow-up through public.fn_marketing_outreach_reply_reasoned.
import { think, type HeldRow, type ThinkDeps, type ThinkResult } from './think.ts';
import type { Reasoned } from './reasoned_decisions.ts';
import { composeFollowUp, type ReplyClass } from './marketing_outreach.ts';

export const REPLY_CLASSES: { id: ReplyClass; meaning: string }[] = [
  { id: 'decline', meaning: 'they are not interested, or ask not to be contacted again: the seat stops following up' },
  { id: 'later', meaning: 'not now, but not a refusal: busy, a later month or quarter, after a holiday' },
  { id: 'positive', meaning: 'they are interested: they ask for details, a call, a demo, or agree to try it' },
  { id: 'question', meaning: 'they ask something (fees, how it works, who the suppliers are) without saying yes or no' },
];

export async function replyClass(deps: ThinkDeps, o: { reply: string; sent: string; token: string; language: 'en' | 'ar' }): Promise<Reasoned<ReplyClass>> {
  const result = await think(deps, {
    seat: 'marketing', surface: 'marketing.outreach_reply', question: o.reply.slice(0, 4000),
    dedupeKey: 'outreach_reply:' + o.token, subject: { mark_token: o.token },
    context: { audience: 'internal', language: o.language, conversation: [{ role: 'seat', text: o.sent.slice(0, 2000) }, { role: 'visitor', text: o.reply.slice(0, 4000) }] },
    decision: { name: 'outreach_reply', options: REPLY_CLASSES },
  });
  const c = result.status === 'answered' ? result.decision?.choice ?? null : null;
  return { value: REPLY_CLASSES.some((x) => x.id === c) ? c as ReplyClass : null, result };
}

// ── the replay ───────────────────────────────────────────────────────────────────────────────────
export interface OutreachIO {
  /** The one-tap page's row (fn_marketing_outreach_page): who it was and in which language. */
  outreachPage(token: string): Promise<{ full_name: string; language: 'en' | 'ar' } | null>;
  /** public.fn_marketing_outreach_reply_reasoned(token, class, follow_up). */
  outreachReasoned(token: string, cls: ReplyClass, followUp: string | null): Promise<{ ok: boolean; err?: string }>;
}
export type OutreachDelivery = { delivered: boolean; via: 'outreach_follow_up' | 'none'; detail?: string };

export async function deliverOutreach(row: HeldRow, r: ThinkResult, io: OutreachIO): Promise<OutreachDelivery | null> {
  if (row.surface !== 'marketing.outreach_reply') return null;
  const token = String(row.subject?.mark_token ?? '');
  const cls = r.decision?.choice as ReplyClass | undefined;
  if (!token || !REPLY_CLASSES.some((x) => x.id === cls)) return { delivered: false, via: 'none', detail: 'no mark token or no reasoned class' };
  const page = await io.outreachPage(token);
  if (!page) return { delivered: false, via: 'none', detail: 'unknown mark token' };
  const f = composeFollowUp({ full_name: page.full_name, language: page.language }, cls!);
  const x = await io.outreachReasoned(token, cls!, f.lint.length ? null : f.message);
  return { delivered: x.ok, via: 'outreach_follow_up', detail: x.err };
}

// deno-lint-ignore no-explicit-any
type Admin = any;
export function liveOutreachIO(admin: Admin): OutreachIO {
  return {
    outreachPage: async (token) => {
      const { data } = await admin.rpc('fn_marketing_outreach_page', { p_token: token });
      return data?.prospect ? { full_name: String(data.prospect.full_name ?? ''), language: data.language === 'ar' ? 'ar' : 'en' } : null;
    },
    outreachReasoned: async (token, cls, followUp) => {
      const { data, error } = await admin.rpc('fn_marketing_outreach_reply_reasoned', { p_token: token, p_class: cls, p_follow_up: followUp });
      return error ? { ok: false, err: error.message } : data?.ok ? { ok: true } : { ok: false, err: String(data?.error ?? 'not recorded') };
    },
  };
}
