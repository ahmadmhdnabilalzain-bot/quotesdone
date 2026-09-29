// What a website-widget reply files BESIDE itself, whichever road wrote it. Seat: customer_support.
//
// Review of #1043 (29 Sep 2026): the composed reply (support_reply.ts) returned before the two side effects
// at the end of site_assistant, so while a model could answer, a visitor asking for a person was never
// reported to the CEO and a question company knowledge could not source was never recorded as a gap.
// Both roads now call this one function, so neither can skip them.
//
//   1. THE KNOWLEDGE GAP (fn_support_knowledge_gap) — only for a visitor who is not signed in, and only when
//      the reply is not grounded in company knowledge: the canned road found nothing, or the composed reply
//      had no topic knowledge and cited no source. The gap's own reply text is returned for the canned road,
//      which has nothing else to say; the composed reply keeps its own text.
//   2. THE PERSON REPORT (fn_support_report_to_ceo) — when the visitor asked for a person (reasoned by the
//      caller, site_assistant.person). Visibility only; it runs beside the reply and never blocks it.
//
// Tested with stubs in widget_reply_effects.test.ts, which also asserts site_assistant's reasoned exit calls it.

/** assistant_logs.audience for a widget reply. A signed-in person is logged as their PARTY — customer:<uuid> or
 *  supplier:<lead id>, the format fn_conversation_party reads to attach the reply to their support case (#1036) —
 *  on every exit, the composed reply included. A stranger has no party: the side and how it was known, and
 *  ':reasoned' when the reply was composed. */
export function logParty(who: { audience: 'customer' | 'supplier'; id: string } | null, audience: string, source: string, reasoned = false): string {
  if (who) return who.audience + ':' + who.id;
  return audience + (source === 'none' ? '' : ':' + source) + (reasoned ? ':reasoned' : '');
}

type Rpc =(fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error?: unknown }>;

export interface WidgetReplyEffectsInput {
  message: string;
  live: boolean;                 // signed in: a gap is never filed for a signed-in person here
  grounded: boolean;             // the reply rests on company knowledge
  answered: boolean;
  refusal: string;               // why it is not grounded, for the gap row
  ip: string;
  path: string;
  askedForAPerson: () => Promise<boolean | null>;
}
export interface WidgetReplyEffects {
  gapTaskId: number | null;
  gapReply: { en: string; ar: string } | null;
  person: Promise<boolean>;      // resolves true when the CEO report was filed; hand it to EdgeRuntime.waitUntil
}

export async function widgetReplyEffects(rpc: Rpc, o: WidgetReplyEffectsInput): Promise<WidgetReplyEffects> {
  let gapTaskId: number | null = null;
  let gapReply: WidgetReplyEffects['gapReply'] = null;
  if (!o.live && !o.grounded) {
    try {
      const { data } = await rpc('fn_support_knowledge_gap', { p_question: o.message, p_refusal: o.refusal || 'no_grounded_answer', p_surface: 'website_widget' });
      const g = data as Record<string, unknown> | null;
      if (g && g.ok === true) {
        gapTaskId = (g.task_id as number) ?? null;
        gapReply = { en: String(g.reply_en || ''), ar: String(g.reply_ar || '') };
      }
    } catch (_e) { /* the visitor still gets a reply; a log write must not eat the turn */ }
  }
  const hour = new Date().toISOString().slice(0, 13);
  const person = (async () => {
    if ((await o.askedForAPerson()) !== true) return false;
    await rpc('fn_support_report_to_ceo', {
      p_idempotency_key: 'widget:person:' + o.ip + ':' + hour,
      p_severity: 'routine',
      p_subject: 'A website visitor asked to speak to a person and was given the public contact',
      p_evidence: { surface: 'website_widget', path: o.path, message: o.message.slice(0, 300), answered: o.answered, number_given: true },
      p_attempted: ['answered from company knowledge', 'shared the approved public contact'],
      p_requested: 'Visibility only. There is no escalation to a human and nothing is waiting on this.',
      p_source_agent: 'customer_support',
    });
    return true;
  })().catch(() => false);   // the visitor already has their answer; visibility must not block it
  return { gapTaskId, gapReply, person };
}
