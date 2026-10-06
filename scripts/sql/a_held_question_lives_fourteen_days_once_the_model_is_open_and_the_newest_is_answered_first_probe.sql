-- PROBE: a held question's 14-day clock starts at its first attempt, a person-facing question never expires silently,
-- the newest is answered first, and the stale backlog of 23-28 Sep is expired. Pure probe, no DDL of its own except a
-- gate replaced INSIDE this transaction (the idiom of a_held_question_is_paid_for_once_..._probe.sql): run AFTER its
-- .sql in the SAME query; it always ends in raise exception CHK<<...>>, so nothing survives, including the .sql and the
-- replaced gate. Its rows are surface zz_demo.expiry_probe with a null subject; nothing is sent and no model is called.
-- PROBE OK only if:
--   E1  no held row is left in the four stale groups; 113-ish expired with the file's reason; every customer-facing one
--       (sales_engineer.document_arabic) has a held_question_expired handoff to its seat, and no internal one has;
--   E2  the column default and fn_reason_hold give a new question 14 days; a visitor chat still gets its hour;
--   E3  under the founder's hold, a tried row past expiry is NOT expired;
--   L   A LATE LIFT, simulated (review of #1235): the gate opens with a row filed 30 days ago whose filing-time
--       expiry is long past and that was never tried. The sweep does NOT expire it; the first claim gives it
--       now() + 14 days; a second sweep still keeps it held;
--   P   with the model open, a tried PERSON-FACING row past its 14 days expires AND opens a handoff to its seat; a tried
--       INTERNAL row expires with its reason and no handoff.
do $probe$
declare
  v_fail text := ''; v_id bigint; v_late bigint; v_cust bigint; v_int bigint; v_exp timestamptz; v_claim jsonb;
  n_left int; n_exp int; n_ho int; n_ho_int int; v_rule text;
  v_int_req constant jsonb := '{"context":{"audience":"internal"}}'::jsonb;
begin
  -- E1
  select count(*) into n_left from public.reasoning_held_question h
   where h.status = 'held' and (
         (h.surface = 'marketing.competitor_change' and h.created_at >= '2026-09-24 00:00+00' and h.created_at < '2026-09-25 00:00+00')
      or (h.surface = 'it_engineer.postmortem' and h.created_at < now() - interval '7 days')
      or (h.surface in ('sales_engineer.document_arabic', 'documents.boq_arabic')
          and h.created_at >= '2026-09-23 00:00+00' and h.created_at < '2026-09-29 00:00+00')
      or (h.surface like '%.knowledge_refresh' and exists (select 1 from public.reasoning_held_question n
            where n.status = 'held' and n.surface = h.surface and n.subject ->> 'item_key' = h.subject ->> 'item_key'
              and n.subject ->> 'quarter' > h.subject ->> 'quarter')));
  if n_left > 0 then v_fail := v_fail || ' E1 ' || n_left || ' stale rows still held;'; end if;
  select count(*),
         count(*) filter (where coalesce(h.request -> 'context' ->> 'audience', '') <> 'internal'
                            and exists (select 1 from public.agent_actions a where a.kind = 'held_question_expired'
                                          and a.target_table = 'reasoning_held_question' and a.target_id = h.id::text
                                          and a.agent = h.seat and a.status = 'pending')),
         count(*) filter (where coalesce(h.request -> 'context' ->> 'audience', '') = 'internal'
                            and exists (select 1 from public.agent_actions a where a.kind = 'held_question_expired'
                                          and a.target_id = h.id::text))
    into n_exp, n_ho, n_ho_int
    from public.reasoning_held_question h
   where h.status = 'expired' and h.result ->> 'expired_by' = '6 Oct final check';
  if n_ho <> (select count(*) from public.reasoning_held_question h where h.status = 'expired'
                and h.result ->> 'expired_by' = '6 Oct final check'
                and coalesce(h.request -> 'context' ->> 'audience', '') <> 'internal') then
    v_fail := v_fail || ' E1 a person-facing expired row has no handoff;';
  end if;
  if n_ho_int > 0 then v_fail := v_fail || ' E1 an internal row opened a handoff;'; end if;

  -- E2
  if pg_get_expr((select adbin from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
                   where d.adrelid = 'public.reasoning_held_question'::regclass and a.attname = 'expires_at'),
                 'public.reasoning_held_question'::regclass) !~ '14 days' then
    v_fail := v_fail || ' E2 expires_at has no 14-day default;';
  end if;
  v_id := public.fn_reason_hold('it_engineer', 'zz_demo.expiry_probe', 'Probe: how long does a held question live?',
                                v_int_req, '{}', null, 'probe', 'zzprobe:expiry:1');
  select expires_at into v_exp from public.reasoning_held_question where id = v_id;
  if v_exp is null or v_exp < now() + interval '13 days 23 hours' or v_exp > now() + interval '14 days 1 hour' then
    v_fail := v_fail || ' E2 fn_reason_hold gave ' || coalesce(v_exp::text, 'no expiry') || ';';
  end if;
  v_id := public.fn_reason_hold('customer_support', 'site_assistant.person', 'Probe: visitor chat expiry?',
                                '{"context":{"audience":"visitor"}}'::jsonb, '{}', null, 'probe', 'zzprobe:expiry:2');
  select expires_at into v_exp from public.reasoning_held_question where id = v_id;
  if v_exp is null or v_exp > now() + interval '61 minutes' then
    v_fail := v_fail || ' E2 a visitor chat got ' || coalesce(v_exp::text, 'no expiry') || ';';
  end if;

  -- E3: under the hold a tried row past expiry stays held
  v_rule := coalesce(public.fn_kernel_paid_provider_gate('hold-probe/not-a-model') ->> 'rule', '');
  v_id := public.fn_reason_hold('it_engineer', 'zz_demo.expiry_probe', 'Probe: past expiry under the hold?',
                                v_int_req, '{}', null, 'probe', 'zzprobe:expiry:3');
  update public.reasoning_held_question set expires_at = now() - interval '1 day', attempts = 1,
         last_attempt_at = now() - interval '1 day' where id = v_id;
  perform public.fn_reason_held_sweep();
  if v_rule <> 'founder_hold' then v_fail := v_fail || ' E3 production is not under the founder hold (' || v_rule || ');';
  elsif (select status from public.reasoning_held_question where id = v_id) <> 'held' then
    v_fail := v_fail || ' E3 a row past expiry was expired under the founder hold;';
  end if;
  delete from public.reasoning_held_question where id = v_id;

  -- L: the late lift. A question filed 30 days ago under the hold, never tried, its filing-time expiry 16 days past.
  v_late := public.fn_reason_hold('it_engineer', 'zz_demo.expiry_probe', 'Probe: filed long ago, never tried',
                                  v_int_req, '{}', null, 'probe', 'zzprobe:expiry:late');
  update public.reasoning_held_question
     set expires_at = now() - interval '16 days', last_attempt_at = null, attempts = 0,
         created_at = now() + interval '1 minute'   -- newest, so the newest-first claim takes it; age lives in expires_at
   where id = v_late;
  execute $g$create or replace function public.fn_kernel_paid_provider_gate(p_model text default null) returns jsonb language sql
             set search_path to 'public', 'pg_temp' as $b$ select '{"allowed":true,"rule":"probe_open"}'::jsonb $b$$g$;
  perform public.fn_reason_held_sweep();
  if (select status from public.reasoning_held_question where id = v_late) <> 'held' then
    v_fail := v_fail || ' L an untried row was expired on the first sweep after a late lift;';
  end if;
  v_claim := public.fn_reason_held_due(1);
  if not exists (select 1 from jsonb_array_elements(v_claim) e where (e ->> 'id')::bigint = v_late) then
    v_fail := v_fail || ' L the newest-first claim did not take the newest row: ' || left(v_claim::text, 120) || ';';
  end if;
  select expires_at into v_exp from public.reasoning_held_question where id = v_late;
  if v_exp is null or v_exp < now() + interval '13 days 23 hours' then
    v_fail := v_fail || ' L the first claim did not start a 14-day clock (' || coalesce(v_exp::text, 'null') || ');';
  end if;
  perform public.fn_reason_held_sweep();
  if (select status from public.reasoning_held_question where id = v_late) <> 'held' then
    v_fail := v_fail || ' L the row expired after its first claim;';
  end if;

  -- P: model open; tried rows past their 14 days
  v_cust := public.fn_reason_hold('sales_engineer', 'zz_demo.expiry_probe', 'Probe: a customer is waiting',
                                  '{"context":{"audience":"customer"}}'::jsonb, '{}', null, 'probe', 'zzprobe:expiry:cust');
  v_int := public.fn_reason_hold('it_engineer', 'zz_demo.expiry_probe', 'Probe: internal only',
                                 v_int_req, '{}', null, 'probe', 'zzprobe:expiry:int');
  update public.reasoning_held_question set attempts = 1, last_attempt_at = now() - interval '15 days',
         expires_at = now() - interval '1 day' where id in (v_cust, v_int);
  perform public.fn_reason_held_sweep();
  if (select status from public.reasoning_held_question where id = v_cust) <> 'expired'
     or not exists (select 1 from public.agent_actions where kind = 'held_question_expired' and agent = 'sales_engineer'
                      and target_table = 'reasoning_held_question' and target_id = v_cust::text and status = 'pending') then
    v_fail := v_fail || ' P a customer-facing row expired without a handoff to its seat (or did not expire);';
  end if;
  if (select status from public.reasoning_held_question where id = v_int) <> 'expired'
     or (select result ->> 'why' from public.reasoning_held_question where id = v_int) is null
     or exists (select 1 from public.agent_actions where kind = 'held_question_expired' and target_id = v_int::text) then
    v_fail := v_fail || ' P an internal row did not expire with its reason alone;';
  end if;

  if v_fail = '' then
    raise exception 'CHK<<PROBE OK expired_by_file=% handoffs=% stale_left=0 late_lift=kept_then_14d person_facing=handoff gate=%>>',
      n_exp, n_ho, v_rule;
  end if;
  raise exception 'CHK<<PROBE FAILED%>>', v_fail;
end $probe$;
