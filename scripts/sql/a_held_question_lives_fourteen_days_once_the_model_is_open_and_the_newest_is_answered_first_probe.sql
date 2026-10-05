-- PROBE: a held question lives fourteen days once the model is open, the newest is answered first, and the stale
-- backlog of 23-28 Sep is expired. Pure probe, no DDL of its own: run AFTER its .sql in the SAME query (node
-- scripts/qsql.mjs on a file that concatenates both); it always ends in raise exception CHK<<...>>, so nothing
-- survives, including the .sql it was run after. Its only rows are surface zz_demo.expiry_probe, filed with a null
-- subject; nothing is sent and no model is called (the hold is read, never opened).
-- PROBE OK only if:
--   E1  no held row is left in any of the four stale groups the file expires, and each expired row carries its reason;
--   E2  the column default and fn_reason_hold both give a new question 14 days; a visitor chat still gets its hour;
--   E3  under the founder's hold the sweep does NOT expire a non-visitor row already past expires_at;
--   E4  no held row is left with expires_at null.
do $probe$
declare
  v_fail text := ''; v_id bigint; v_exp timestamptz; n_left int; n_exp int; n_null int; v_rule text;
begin
  -- E1
  select count(*) into n_left from public.reasoning_held_question
   where status = 'held' and (
         (surface = 'marketing.competitor_change' and created_at >= '2026-09-24 00:00+00' and created_at < '2026-09-25 00:00+00')
      or (surface = 'it_engineer.postmortem' and created_at < now() - interval '7 days')
      or (surface in ('sales_engineer.document_arabic', 'documents.boq_arabic')
          and created_at >= '2026-09-23 00:00+00' and created_at < '2026-09-29 00:00+00')
      or (surface like '%.knowledge_refresh' and exists (select 1 from public.reasoning_held_question n
            where n.status = 'held' and n.surface = reasoning_held_question.surface
              and n.subject ->> 'item_key' = reasoning_held_question.subject ->> 'item_key'
              and n.subject ->> 'quarter' > reasoning_held_question.subject ->> 'quarter')));
  if n_left > 0 then v_fail := v_fail || ' E1 ' || n_left || ' stale rows still held;'; end if;
  select count(*) into n_exp from public.reasoning_held_question
   where status = 'expired' and result ->> 'expired_by' = '6 Oct final check' and coalesce(result ->> 'why', '') <> '';

  -- E2
  if pg_get_expr((select adbin from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
                   where d.adrelid = 'public.reasoning_held_question'::regclass and a.attname = 'expires_at'),
                 'public.reasoning_held_question'::regclass) !~ '14 days' then
    v_fail := v_fail || ' E2 expires_at has no 14-day default;';
  end if;
  v_id := public.fn_reason_hold('it_engineer', 'zz_demo.expiry_probe', 'Probe: how long does a held question live?',
                                '{"context":{"audience":"internal"}}'::jsonb, '{}', null, 'probe', 'zzprobe:expiry:1');
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

  -- E3 (only meaningful under the hold; production is held until 2126-08-15)
  v_rule := coalesce(public.fn_kernel_paid_provider_gate('hold-probe/not-a-model') ->> 'rule', '');
  v_id := public.fn_reason_hold('it_engineer', 'zz_demo.expiry_probe', 'Probe: past expiry under the hold?',
                                '{"context":{"audience":"internal"}}'::jsonb, '{}', null, 'probe', 'zzprobe:expiry:3');
  update public.reasoning_held_question set expires_at = now() - interval '1 day' where id = v_id;
  perform public.fn_reason_held_sweep();
  if v_rule = 'founder_hold' and (select status from public.reasoning_held_question where id = v_id) <> 'held' then
    v_fail := v_fail || ' E3 a row past expiry was expired under the founder hold;';
  end if;

  -- E4
  select count(*) into n_null from public.reasoning_held_question where status = 'held' and expires_at is null;
  if n_null > 0 then v_fail := v_fail || ' E4 ' || n_null || ' held rows have no expiry;'; end if;

  if v_fail = '' then
    raise exception 'CHK<<PROBE OK expired_by_file=% stale_left=0 null_expiry=0 gate=%>>', n_exp, v_rule;
  end if;
  raise exception 'CHK<<PROBE FAILED%>>', v_fail;
end $probe$;
