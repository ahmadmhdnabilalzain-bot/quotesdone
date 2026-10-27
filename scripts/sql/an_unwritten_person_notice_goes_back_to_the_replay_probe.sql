-- PROBE: a held question whose reasoned message the model could not write (delivery via 'unwritten') goes back to the
-- replay and, at its last try, to the seat. Pure probe: run AFTER its .sql in the SAME query (concatenate the two files
-- and run them through node scripts/qsql.mjs); it always ends in raise exception CHK<<...>>, so nothing survives,
-- including the .sql it ran after. Its rows CANNOT carry the ZZ DEMO / fixture markers: fn_reason_held_sweep (run by
-- fn_reason_held_due) expires fixture rows on sight, which is right, and would hide exactly what U2 measures. So the
-- rows are marked by qhash 'zzprobe:*' and a number no one holds (whatsapp:+000000000000, an invalid E.164), and
-- nothing is sent: these routines write rows only, no channel is called, and every row is rolled back. The one gate it opens
-- for fn_reason_held_due is replaced inside this transaction only, so no model is ever called.
-- PROBE OK only if:
--   U1  a 'reasoned' row (attempts 1) delivered via 'unwritten' is 'held' again, with its delivery recorded;
--   U2  fn_reason_held_due claims it once its 10 minutes have passed (attempts becomes 2);
--   U3  the same at its last try (attempts 3) is 'failed', and fn_reason_held_escalate takes it;
--   U4  unchanged: delivered -> 'applied'; via 'none' -> 'applied'; any other undelivered via keeps 'reasoned'.
do $probe$
declare
  v_fail text := ''; v_u bigint; v_l bigint; v_d bigint; v_n bigint; v_o bigint; v jsonb; v_st text; v_att int;
  v_subj jsonb := '{"phone":"whatsapp:+000000000000","probe":"an_unwritten_person_notice"}'::jsonb;
  v_req jsonb := '{"seat":"customer_support","context":{"audience":"internal"}}'::jsonb;
begin
  execute $g$create or replace function public.fn_kernel_paid_provider_gate(p_model text default null) returns jsonb language sql
             set search_path to 'public', 'pg_temp' as $b$ select '{"allowed":true,"rule":"probe_open"}'::jsonb $b$$g$;
  insert into public.reasoning_held_question (seat, surface, question, request, subject, reason, status, attempts, last_attempt_at, created_at, qhash)
  values ('customer_support', 'wa_inbound.needs_a_person', 'probe of an unwritten person notice U1', v_req, v_subj, 'probe', 'reasoned', 1, now() - interval '11 minutes', now() - interval '1 hour', 'zzprobe:u1'),
         ('customer_support', 'wa_inbound.needs_a_person', 'probe of an unwritten person notice U3', v_req, v_subj, 'probe', 'reasoned', 3, now() - interval '11 minutes', now() - interval '1 hour', 'zzprobe:u3'),
         ('customer_support', 'wa_inbound.needs_a_person', 'probe of an unwritten person notice U4d', v_req, v_subj, 'probe', 'reasoned', 1, now() - interval '11 minutes', now() - interval '1 hour', 'zzprobe:u4d'),
         ('customer_support', 'wa_inbound.needs_a_person', 'probe of an unwritten person notice U4n', v_req, v_subj, 'probe', 'reasoned', 1, now() - interval '11 minutes', now() - interval '1 hour', 'zzprobe:u4n'),
         ('customer_support', 'wa_inbound.needs_a_person', 'probe of an unwritten person notice U4o', v_req, v_subj, 'probe', 'reasoned', 1, now() - interval '11 minutes', now() - interval '1 hour', 'zzprobe:u4o');
  select id into v_u from public.reasoning_held_question where qhash = 'zzprobe:u1';
  select id into v_l from public.reasoning_held_question where qhash = 'zzprobe:u3';
  select id into v_d from public.reasoning_held_question where qhash = 'zzprobe:u4d';
  select id into v_n from public.reasoning_held_question where qhash = 'zzprobe:u4n';
  select id into v_o from public.reasoning_held_question where qhash = 'zzprobe:u4o';

  -- U1
  perform public.fn_reason_held_delivered(v_u, '{"delivered":false,"via":"unwritten","detail":"probe"}'::jsonb);
  select status into v_st from public.reasoning_held_question where id = v_u;
  if v_st <> 'held' then v_fail := v_fail || ' U1 unwritten left the row ' || v_st || ';'; end if;
  if not exists (select 1 from public.reasoning_held_question where id = v_u and result->'delivery'->>'via' = 'unwritten') then
    v_fail := v_fail || ' U1 the delivery was not recorded;'; end if;
  -- U2
  v := public.fn_reason_held_due(10);
  if not exists (select 1 from jsonb_array_elements(v) e where (e->>'id')::bigint = v_u) then
    v_fail := v_fail || ' U2 fn_reason_held_due did not claim the row (claimed ' || jsonb_array_length(v) || ');'; end if;
  select attempts into v_att from public.reasoning_held_question where id = v_u;
  if v_att <> 2 then v_fail := v_fail || ' U2 attempts ' || v_att || ', expected 2;'; end if;
  -- U3
  perform public.fn_reason_held_delivered(v_l, '{"delivered":false,"via":"unwritten"}'::jsonb);
  select status into v_st from public.reasoning_held_question where id = v_l;
  if v_st <> 'failed' then v_fail := v_fail || ' U3 the last try left the row ' || v_st || ';'; end if;
  v := public.fn_reason_held_escalate(100);
  if not exists (select 1 from jsonb_array_elements(v) e where (e->>'id')::bigint = v_l) then
    v_fail := v_fail || ' U3 fn_reason_held_escalate did not take the failed row;'; end if;
  -- U4
  perform public.fn_reason_held_delivered(v_d, '{"delivered":true,"via":"whatsapp_text"}'::jsonb);
  perform public.fn_reason_held_delivered(v_n, '{"delivered":false,"via":"none"}'::jsonb);
  perform public.fn_reason_held_delivered(v_o, '{"delivered":false,"via":"whatsapp_text","detail":"send failed"}'::jsonb);
  if (select status from public.reasoning_held_question where id = v_d) <> 'applied' then v_fail := v_fail || ' U4 delivered is not applied;'; end if;
  if (select status from public.reasoning_held_question where id = v_n) <> 'applied' then v_fail := v_fail || ' U4 none is not applied;'; end if;
  if (select status from public.reasoning_held_question where id = v_o) <> 'reasoned' then v_fail := v_fail || ' U4 another undelivered via changed status;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED:' || v_fail end;
end $probe$;
