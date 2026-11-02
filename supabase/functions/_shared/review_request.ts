// review_request — a request to review an automated decision enters the ONE door, fn_review_request_open
// (founder ledger 1152, 19 Oct 2026). Seat: ceo; the intake is customer_support's.
//
// Which decision the person asks us to review is REASONED, never word-matched: think() chooses among the decision
// types read from public.review_route (the routing table is the option list, so a new route needs no code), or
// 'none'. The ROUTE itself is a table lookup in SQL — routine work is code. Called only when the channel's own
// reasoning already said the message needs a person (wa_inbound, email_triage), so it adds no model call to an
// ordinary message. Under the hold the answer is null and nothing is filed on a guess: the message is already in
// customer_support's queue. Ruling 1264: the 'person' route (an EXPLICIT ask for a person, chat or e-mail) is the one
// thing that reaches the founder, through founder_mail_policy in SQL; no review of a decision ever does.
import { think, type ThinkDeps } from './think.ts';
import { isDemoEmail, isDemoPhone } from './demo_identity.ts';
import { type DueReview, REVIEW_TASK_CLASS, type ReviewIO } from './review_decide.ts';

type Rpc = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: unknown }> };
type Admin = Rpc & { from: (t: string) => any };
export type Route = { decision_type: string; meaning: string };

/** Which automated decision does this message ask a person to review? null = held/unreasoned, 'none' = not a review request. */
export async function reviewOfDecision(deps: ThinkDeps, o: {
  surface: string; message: string; routes: Route[]; audience?: 'customer' | 'supplier'; dedupeKey?: string; subject?: Record<string, unknown>;
}): Promise<string | null> {
  const result = await think(deps, {
    seat: 'customer_support', surface: o.surface, question: o.message, dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: o.audience ?? 'customer' },
    decision: {
      name: 'decision_under_review',
      options: [
        ...o.routes.map((r) => ({ id: r.decision_type, meaning: `they ask for a person to review or reverse an automated decision about ${r.meaning}` })),
        { id: 'none', meaning: 'neither: they do not contest a decision the platform made and do not explicitly ask to speak to a person (a question, a complaint, a new request)' },
      ],
    },
  });
  return result.status === 'answered' ? result.decision?.choice ?? null : null;
}

/** The live IO for review_decide.ts: the SQL door and ai_gateway with counterpart_model (another family answers). */
export function liveReviewIO(admin: Admin, fn = 'ceo_agent'): ReviewIO {
  return {
    due: async (limit, id) => {
      const { data, error } = await admin.rpc('fn_review_request_due', { p_limit: limit, p_id: id ?? null });
      if (error) throw new Error('fn_review_request_due: ' + (error as { message?: string }).message);
      return (data ?? []) as DueReview[];
    },
    ask: async (r, system, input) => {
      const { makeLlmRich } = await import('./llm.ts');
      const call = makeLlmRich(r.reviewer_model_hint ? [r.reviewer_model_hint] : [], {
        fn, taskClass: REVIEW_TASK_CLASS, agent: r.owner_seat, max: 700, timeoutMs: 45_000, cacheTtlMin: 0, json: true, temperature: 0 });
      const res = await call(system, input, 700, '', { counterpartModel: r.counterpart_model,
        subject: r.requester.includes('@') ? { email: r.requester } : { phone: r.requester } });
      return { content: res.content ?? null, model: res.model ?? null, error: res.error ?? null };
    },
    conclude: async (id, v, model) => {
      const { data, error } = await admin.rpc('fn_review_request_conclude', {
        p_id: id, p_verdict: v.verdict, p_reason: v.reasons, p_reviewer_model: model, p_reply: v.reply });
      if (error) throw new Error('fn_review_request_conclude: ' + (error as { message?: string }).message);
      return data as Record<string, unknown>;
    },
    failed: async (id, err) => (await admin.rpc('fn_review_request_attempt_failed', { p_id: id, p_error: err })).data,
  };
}

/** Reason the decision type and, when there is one, file the request with its owning seat. Never throws. */
export async function fileReviewRequest(admin: Admin, deps: ThinkDeps, o: {
  channel: 'whatsapp' | 'site_chat' | 'email'; requester: string; message: string; surface: string; dedupeKey: string;
  audience?: 'customer' | 'supplier'; subjectTable?: string; subjectId?: string;
}): Promise<{ filed: boolean; decision_type: string | null; owner_seat?: string; id?: number }> {
  try {
    const { data: routes } = await admin.from('review_route').select('decision_type,meaning').order('decision_type');
    if (!Array.isArray(routes) || !routes.length) return { filed: false, decision_type: null };
    const type = await reviewOfDecision(deps, { surface: o.surface, message: o.message.slice(0, 4000), routes, audience: o.audience,
      dedupeKey: 'review:' + o.dedupeKey, subject: { channel: o.channel, requester: o.requester } });
    if (!type || type === 'none') return { filed: false, decision_type: type };
    // A FIXTURE'S ASK FOR A PERSON NEVER PAGES THE FOUNDER (2 Nov 2026). The 'person' route is the one that reaches him
    // (fn_review_request_open -> fn_notify_founder) and it had no demo check: the real-exchange runs of 2 Nov sent him four
    // e-mails for +971500000094/95. A demo requester (reserved mobile, or a demo/.invalid/sink e-mail) is recorded as
    // suppressed instead; every real requester still pages. Prevented by: review_request.test.ts.
    if (type === 'person' && (isDemoPhone(o.requester) || isDemoEmail(o.requester))) {
      try {
        await admin.from('agent_runs').insert({ agent: 'review_request', status: 'skipped', counts: { suppressed: 1, channel: o.channel },
          note: 'suppressed: a demo/fixture requester asked for a person; the founder is not paged (review_request.ts)', finished_at: new Date().toISOString() });
      } catch (_e) { /* the record never blocks the reply */ }
      return { filed: false, decision_type: type };
    }
    const { data, error } = await admin.rpc('fn_review_request_open', {
      p_decision_type: type, p_channel: o.channel, p_requester: o.requester, p_request_text: o.message.slice(0, 4000),
      p_subject_table: o.subjectTable ?? null, p_subject_id: o.subjectId ?? null, p_dedupe_key: o.channel + ':' + o.dedupeKey,
    });
    const r = (data ?? {}) as { ok?: boolean; id?: number; owner_seat?: string };
    return { filed: !error && r.ok === true, decision_type: type, owner_seat: r.owner_seat, id: r.id };
  } catch (_e) {
    return { filed: false, decision_type: null }; // the person request already stands; a review row is never worth a lost reply
  }
}
