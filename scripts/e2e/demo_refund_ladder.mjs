// scripts/e2e/demo_refund_ladder.mjs - the refund ladder, driven on a ZZ DEMO reveal (accountant, 3 Nov 2026).
//
// WHY THIS EXISTS. Founder instruction 1199 (12 Oct 2026): "delete all test/demo data ... so no agent ever works on it
// as if real". fn_seat_handoff therefore files NO handoff raised from a demo row (it returns NULL) unless the
// transaction set qd.probe_files_demo_handoff = 'on'. Journey e read handoffs that can never exist for its demo
// customer, so on main (nightly run 41598217377, 3 Nov 07:56Z) "the confirmation goes to support", "the case is
// handed to the accountant", the day-3 chase, the day-5 final call (reqId 0: fn_sales_engineer_ladder_step returned
// NULL) and so the CEO's decision all FAILED. The refund ladder itself is not broken: for a real customer every
// handoff is filed. Measured the same day on refund 78197 (run acpay01): the same ladder, run inside one transaction
// that sets the flag, delivered both steps, confirmed no response and the CEO approved on the checklist.
//
// The two doors here are the only ones the harness uses for demo handoffs:
//   handoffProbeSql  a ROLLED-BACK probe: opens the case with the flag on, reads the two handoffs, always raises.
//   ladderSql        ONE committed transaction with the flag on: chase and final call, each delivered to the demo
//                    address (sent_at only), watched to a no-response confirmation. Every handoff it files is
//                    closed inside the same transaction, so no seat is left with demo work (instruction 1199).
const q = (v) => `'${String(v).replace(/'/g, "''")}'`;

export function handoffProbeSql(txId) {
  return `do $p$ declare r jsonb; begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  r := public.fn_refund_open_from_customer(${q(txId)}::uuid, 'customer');
  raise exception 'CHK<<%>>', jsonb_build_object('open', r - 'message_ar' - 'message_en',
    'confirm_locale', (select detail->>'locale' from public.agent_actions where kind = 'handoff' and agent = 'customer_support'
                         and detail->>'msg_type' = 'refund_request_received' and detail->>'transaction_id' = ${q(txId)} order by id desc limit 1),
    'to_accountant', (select agent from public.agent_actions where kind = 'handoff' and detail->>'type' = 'refund.requested'
                         and detail->>'subject_id' = (r->>'refund_id') order by id desc limit 1));
end $p$`;
}

export function ladderSql(txId, refundId) {
  return `do $l$ declare st text; req bigint; nid bigint; begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  if not exists (select 1 from public.transactions t join public.customers c on c.id = t.customer_id
                  where t.id = ${q(txId)}::uuid and c.is_demo and c.email like '%@example.invalid') then
    raise exception 'demo refund ladder: % is not a ZZ DEMO reveal', ${q(txId)};
  end if;
  foreach st in array array['chase', 'final_call'] loop
    req := public.fn_sales_engineer_ladder_step(${q(txId)}::uuid, st, case when st = 'final_call' then ${Number(refundId)}::bigint end, null);
    select (evidence->>'notification_id')::bigint into nid from public.agent_actions where id = req;
    update public.notifications set sent_at = now() where id = nid and to_email like '%@example.invalid';
    update public.agent_actions set detail = detail || jsonb_build_object('watch_until', now() - interval '1 minute')
     where id = req and detail->>'to_email' like '%@example.invalid';
    perform public.fn_customer_support_delivery_watch(req);
  end loop;
end $l$`;
}

/** The JSON a CHK<<...>> probe raised, from the management API error (its body carries the message), or null. */
export function parseChk(err) {
  let text = String(err?.body ?? err?.message ?? err ?? '');
  try { text = JSON.parse(text).message ?? text; } catch { /* the body was already the message */ }
  const m = text.match(/CHK<<([\s\S]*)>>/);
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch { return { raw: m[1] }; }
}
