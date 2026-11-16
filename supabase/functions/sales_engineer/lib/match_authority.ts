// sales_engineer — may the seat match this request? (ceo, 15 Nov 2026; third review of the CEO pool branch, item 6.)
//
// 'match' is the ONE live caller of the subject-aware authority rule, fn_agent_may_act(seat, action, amount, SUBJECT, ASK)
// (scripts/sql/every_seat_reads_one_pool_and_every_hand_over_comes_back.sql). While the standing grant sales.matching is
// active the answer is the same as before (may_act true). If it is ever refused with route ceo_case_decision, the rule
// itself files the question to the CEO (founder ledger 1696: he decides, nobody waits on the founder) and the caller is
// answered 202 with the hand-over to watch, not a bare 403: the answer lands on that hand-over and in the seat's pool block,
// and a call after an allow_once is honoured once, for this request only.
//
// The other callers stay on the three-argument form on purpose (review item 6): the IT engineer's deploy is a destructive
// production change and keeps its release path; the accountant's refund already asks the CEO through fn_ceo_request_decision
// (asking here too would ask him twice); seat.ts and operator.ts 'grants' only REPORT what a seat may do, and a report must
// not file a question.
//
// DEPLOY ORDER IS NOT A HAZARD (review item 6: "new code before the SQL is not safe: 'match' returns 403 and
// customer_api.matchAndNotify notifies no supplier"): when the five-argument routine does not exist yet, the call falls back
// to the three-argument form, which answers exactly as production does today.
// prevented by: supabase/functions/sales_engineer/lib/match_authority.test.ts
export type RpcResult = { data: unknown; error: { message?: string; code?: string } | null };
export type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<RpcResult>;
export type MatchAuthority =
  | { ok: true; may: Record<string, unknown> }
  | { ok: false; status: 202 | 403; body: Record<string, unknown> };

/** PostgREST's answer when the named-argument overload does not exist (PGRST202), or Postgres' 42883. */
export function routineIsMissing(e: { message?: string; code?: string } | null): boolean {
  if (!e) return false;
  return e.code === 'PGRST202' || e.code === '42883' || /could not find the function|function .* does not exist/i.test(String(e.message ?? ''));
}

export async function matchAuthority(rpc: Rpc, inquiryId: string): Promise<MatchAuthority> {
  const id = String(inquiryId || '').trim();
  let r: RpcResult = await rpc('fn_agent_may_act', {
    p_grantee_role_id: 'sales_engineer', p_action_class: 'matching', p_amount_aed: null,
    p_subject: id ? 'inquiry:' + id : null,
    p_ask: { what: id ? 'match request ' + id + ' to its suppliers' : 'run the matcher with no named request',
             why: 'a customer posted the request and is waiting for quotations', facts: { inquiry_id: id || null } },
  });
  if (routineIsMissing(r.error)) {
    r = await rpc('fn_agent_may_act', { p_grantee_role_id: 'sales_engineer', p_action_class: 'matching', p_amount_aed: null });
  }
  const may = (r.data || {}) as Record<string, unknown>;
  if (!r.error && may.may_act === true) return { ok: true, may };
  if (!r.error && may.asked === true && may.handoff_id != null) {
    return { ok: false, status: 202, body: {
      ok: false, error: 'asked_the_ceo', asked: true, handoff_id: may.handoff_id, status: may.status ?? null, reason: may.reason ?? null,
      message: `asked the CEO (ceo.authority #${may.handoff_id}); the answer lands on that hand-over and in your pool block; call again after allow_once`,
    } };
  }
  return { ok: false, status: 403, body: { ok: false, error: 'not_permitted', ...may, ...(r.error ? { detail: r.error.message ?? String(r.error) } : {}) } };
}
