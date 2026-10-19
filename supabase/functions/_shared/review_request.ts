// review_request — a request for human review of an automated decision enters the ONE door, fn_review_request_open
// (founder ledger 1152, 19 Oct 2026). Seat: ceo; the intake is customer_support's.
//
// Which decision the person asks us to review is REASONED, never word-matched: think() chooses among the decision
// types read from public.review_route (the routing table is the option list, so a new route needs no code), or
// 'none'. The ROUTE itself is a table lookup in SQL — routine work is code. Called only when the channel's own
// reasoning already said the message needs a person (wa_inbound, email_triage), so it adds no model call to an
// ordinary message. Under the hold the answer is null and nothing is filed on a guess: the message is already in
// customer_support's queue as a person request. The founder is never a route (review_route FK + CHECK).
import { think, type ThinkDeps } from './think.ts';

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
        { id: 'none', meaning: 'they do not ask for a decision the platform made to be reviewed (a question, a new request, or a person for any other reason)' },
      ],
    },
  });
  return result.status === 'answered' ? result.decision?.choice ?? null : null;
}

/** Reason the decision type and, when there is one, file the request with its owning seat. Never throws. */
export async function fileReviewRequest(admin: Admin, deps: ThinkDeps, o: {
  channel: 'whatsapp' | 'email' | 'portal'; requester: string; message: string; surface: string; dedupeKey: string;
  audience?: 'customer' | 'supplier'; subjectTable?: string; subjectId?: string;
}): Promise<{ filed: boolean; decision_type: string | null; owner_seat?: string; id?: number }> {
  try {
    const { data: routes } = await admin.from('review_route').select('decision_type,meaning').order('decision_type');
    if (!Array.isArray(routes) || !routes.length) return { filed: false, decision_type: null };
    const type = await reviewOfDecision(deps, { surface: o.surface, message: o.message.slice(0, 4000), routes, audience: o.audience,
      dedupeKey: 'review:' + o.dedupeKey, subject: { channel: o.channel, requester: o.requester } });
    if (!type || type === 'none') return { filed: false, decision_type: type };
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
