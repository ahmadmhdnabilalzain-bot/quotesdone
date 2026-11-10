// scripts/e2e/refund_ladder_probe.mjs — the refund ladder walked on the production path in a transaction that
// always rolls back. Seat: customer_support (for the journey's refund steps, owned by sales_engineer, accountant, ceo).
//
// WHY (2 Nov 2026). fn_seat_handoff files no handoff for demo work (ruling 1199), and every rung of the ladder
// is a handoff: the confirmation (sales engineer -> customer support), the case (-> accountant), the day-3 chase
// and day-5 final call (delivery.request -> customer support -> delivery.result), the CEO's review. So journey e
// read {} for all five since 20 Oct. fn_seat_handoff keeps one door for a probe, qd.probe_files_demo_handoff,
// set for the probe's own transaction only.
//
// THE KNOWN-BAD CONTROL. The same walk runs twice inside the transaction: first with the door shut (the path a
// demo row really takes, i.e. no handoff filed — a broken ladder), then open. A step passes only when the open
// walk proves it AND the shut walk does not, so a step that would pass with the ladder broken is caught.
// Each walk is its own sub-block that rolls back, and the whole probe ends in `raise exception`: nothing commits.
// Mail and WhatsApp to @example.invalid are captured by the database and never sent; Stripe is never called here.
const q = (v) => `'${String(v).replace(/'/g, "''")}'`;

export function refundLadderProbeSql(txId, { prelude = '' } = {}) {
  return `do $probe$
declare
  v_tx uuid := ${q(txId)};
  f boolean; v_out jsonb := '{}'; r jsonb; t public.transactions; v_email text; v_loc text; v_sup text;
  v_open jsonb; v_rid bigint; v_req bigint; v_nid bigint; st text; v_ev jsonb; ck jsonb; v_dec jsonb;
begin
  foreach f in array array[false, true] loop
    begin
      perform set_config('qd.probe_files_demo_handoff', case when f then 'on' else 'off' end, true);
      ${prelude}
      select * into t from public.transactions where id = v_tx;
      select email into v_email from public.customers where id = t.customer_id;
      select email into v_sup from public.leads where id = t.supplier_id;
      v_loc := coalesce(public.fn_registered_locale('customer', t.customer_id, null, v_email), 'en');
      r := jsonb_build_object('customer_locale', v_loc);
      -- 1. the customer asks; the case opens
      v_open := public.fn_refund_open_from_customer(v_tx, 'customer');
      v_rid := (v_open->>'refund_id')::bigint;
      r := r || jsonb_build_object('open', v_open - 'message_en' - 'message_ar');
      -- 2. the confirmation is handed to customer support, in the customer's language
      r := r || jsonb_build_object('confirmation', (select jsonb_build_object('seat', a.agent, 'locale', a.detail->>'locale', 'to', a.detail->>'to_email', 'status', a.status)
        from public.agent_actions a where a.kind = 'handoff' and a.detail->>'msg_type' = 'refund_request_received'
         and a.detail->>'transaction_id' = v_tx::text order by a.id desc limit 1));
      -- 3. the case is handed to the accountant
      r := r || jsonb_build_object('case', (select jsonb_build_object('seat', a.agent, 'from', a.detail->>'from', 'status', a.status)
        from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'refund.requested'
         and a.detail->>'subject_id' = v_rid::text order by a.id desc limit 1));
      -- the CEO may not decide before the ladder has run
      ck := public.fn_ceo_refund_checklist(v_tx, 'approve', false);
      r := r || jsonb_build_object('checklist_before', jsonb_build_object('ok', ck->'ok', 'failed', (select coalesce(jsonb_agg(x->>'item'), '[]') from jsonb_array_elements(coalesce(ck->'failed', '[]')) x)));
      -- the supplier's five working days have passed (inside this transaction only)
      update public.transactions set revealed_at = now() - interval '10 days',
             refund_deadline = public.fn_add_working_days(now() - interval '10 days', 5) where id = v_tx;
      -- 4 and 5. day-3 chase, then day-5 final call, each delivered and watched to a no-response confirmation
      foreach st in array array['chase', 'final_call'] loop
        v_req := public.fn_sales_engineer_ladder_step(v_tx, st, case when st = 'final_call' then v_rid end, null);
        v_nid := (select (a.evidence->>'notification_id')::bigint from public.agent_actions a where a.id = v_req);
        update public.notifications set sent_at = now() where id = v_nid and to_email like '%@example.invalid';
        update public.agent_actions set detail = detail || jsonb_build_object('watch_until', now() - interval '1 minute')
         where id = v_req and detail->>'to_email' like '%@example.invalid';
        if v_req is not null then perform public.fn_customer_support_delivery_watch(v_req); end if;
        v_ev := (select jsonb_build_object('id', e.id, 'result', e.result, 'delivered', e.delivered)
                   from public.refund_ladder_evidence e where e.transaction_id = v_tx and e.step = st order by e.id desc limit 1);
        r := r || jsonb_build_object(st, jsonb_build_object('request', v_req, 'evidence', v_ev,
          'told', (select jsonb_build_object('to', n.to_email, 'cc', n.cc_emails, 'status', n.status) from public.notifications n where n.id = v_nid)));
      end loop;
      -- 6. the CEO decides on the checklist; the money has not moved (no Stripe call inside the database)
      v_dec := (select jsonb_build_object('decision', a.decision, 'decided_by', a.decided_by, 'refund_status', rf.status)
                  from public.refunds rf left join public.ceo_approval a on a.decision_id = rf.refund_decision_id where rf.id = v_rid);
      r := r || jsonb_build_object('ceo', v_dec, 'ceo_failed', (select coalesce(jsonb_agg(c.item), '[]') from public.refund_ceo_check c where c.refund_id = v_rid and not c.passed));
      r := r || jsonb_build_object('supplier_email', v_sup, 'customer_email', v_email);
      raise exception 'ITER<<%>>', r::text;
    exception when others then
      v_out := v_out || jsonb_build_object(case when f then 'open' else 'shut' end,
        case when sqlerrm like 'ITER<<%' then substring(sqlerrm from 'ITER<<(.*)>>$')::jsonb
             else jsonb_build_object('error', left(sqlerrm, 300), 'partial', r) end);
    end;
  end loop;
  raise exception 'CHK<<%>>', v_out::text;
end $probe$;`;
}

/** The five steps from one walk. Each returns [ok, detail]. */
export function ladderSteps(w) {
  const ev = (s) => w?.[s]?.evidence || {};
  const told = (s) => w?.[s]?.told || {};
  // the supplier is told and the customer is copied ("we chase them on the third working day and copy you")
  const delivered = (s) => ev(s).result === 'no_response_confirmation' && ev(s).delivered === true && told(s).to === w?.supplier_email
    && (told(s).cc || []).includes(w?.customer_email);
  return {
    confirmation: [w?.confirmation?.seat === 'customer_support' && w?.confirmation?.locale === w?.customer_locale && w?.confirmation?.to === w?.customer_email,
      w?.confirmation],
    case: [w?.case?.seat === 'accountant' && w?.case?.from === 'sales_engineer', w?.case],
    chase: [delivered('chase'), { evidence: ev('chase'), told: told('chase') }],
    final_call: [delivered('final_call') && Number(ev('final_call').id) > Number(ev('chase').id), { evidence: ev('final_call'), told: told('final_call'), after_chase_evidence: ev('chase').id }],
    ceo: [w?.checklist_before?.ok === false && w?.ceo?.decision === 'approved' && /ceo/i.test(String(w?.ceo?.decided_by || ''))
      && !['succeeded', 'processing'].includes(String(w?.ceo?.refund_status)),
      { before_ladder: w?.checklist_before, ceo: w?.ceo, failed: w?.ceo_failed }],
  };
}

export function parseProbe(e) {
  let msg = String(e?.message || e); try { msg = JSON.parse(e.body).message; } catch { /* not JSON */ }
  const m = /CHK<<([\s\S]*)>>/.exec(msg);
  return m ? JSON.parse(m[1]) : { error: msg.slice(0, 300) };
}
