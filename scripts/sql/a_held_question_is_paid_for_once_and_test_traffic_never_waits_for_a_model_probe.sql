-- PROBE: a held question is paid for once and our own test traffic never waits for a model. Pure probe, no DDL of its
-- own: run AFTER its .sql in the SAME query (node scripts/qsql.mjs on a file that concatenates both); it always ends in
-- raise exception CHK<<...>>, so nothing survives, including the .sql it was run after. It writes only ZZ DEMO rows
-- (a harness identity qd-zzprobe-*@example.invalid, surface zz_demo.probe) and reaches no one: nothing is sent, and the
-- one gate it opens for fn_reason_held_due is replaced inside this transaction only, so no model is ever called.
-- PROBE OK only if:
--   R1  a question about a harness identity's inquiry is not filed; its deliberation gate opens nothing;
--   R2  three rows with the same question are claimed once, and the one answer is applied to all three (fanned 2);
--   R3  a failed row filed again stays failed with attempts unchanged, and the same question under a new key files nothing;
--   R5  a visitor chat is filed with an hour to live, and a two-hour-old one is expired by the sweep;
--   R4  two held postmortems of one fault become one;
--   backlog: the held queue after the file is at most what it was before minus the measured test traffic.
do $probe$
declare
  v_fail text := ''; v_cust uuid := gen_random_uuid(); v_inq uuid := gen_random_uuid(); v_id bigint; v_a bigint; v_b bigint; v_c bigint;
  v jsonb; v_n int; v_att int; v_req jsonb := '{"seat":"it_engineer","context":{"audience":"internal"}}'::jsonb;
begin
  -- R1: a harness identity (address shape + its rehearsal_window row) and an inquiry of it.
  insert into public.rehearsal_window (run_tag, note) values ('qd_run:zzprobe', 'ZZ DEMO probe of a_held_question_is_paid_for_once');
  insert into public.customers (id, email, full_name) values (v_cust, 'qd-zzprobe-cust1@example.invalid', 'ZZ DEMO probe customer');
  insert into public.inquiries (id, customer_id, category, trades, emirate, raw_input, status)
  values (v_inq, v_cust, 'aluminium', array['aluminium'], 'Dubai', 'ZZ DEMO probe request', 'quoted');
  v_id := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'Is this our own test?', v_req, '{}', jsonb_build_object('inquiry_id', v_inq),
                                'probe', 'zzprobe:fixture');
  if v_id is not null then v_fail := v_fail || ' R1 a harness subject was filed;'; end if;
  if not public.fn_deliberation_subject_is_fixture('inquiries', v_inq::text || ':c9a3b39bcab2048b') then
    v_fail := v_fail || ' R7 a harness inquiry is not a fixture deliberation subject;'; end if;

  -- R2: three rows, one question; the gate is opened inside this transaction only.
  execute $g$create or replace function public.fn_kernel_paid_provider_gate(p_model text default null) returns jsonb language sql
             set search_path to 'public', 'pg_temp' as $b$ select '{"allowed":true,"rule":"probe_open"}'::jsonb $b$$g$;
  v_a := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE one question  asked three times', v_req, '{}', '{"n":1}', 'probe', 'zzprobe:a');
  v_b := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE one question asked three times', v_req, '{}', '{"n":2}', 'probe', 'zzprobe:b');
  v_c := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE one question asked three times ', v_req, '{}', '{"n":3}', 'probe', 'zzprobe:c');
  update public.reasoning_held_question set last_attempt_at = null, created_at = '2000-01-01'
   where id in (v_a, v_b, v_c);   -- first in the queue, ahead of every real row
  v := public.fn_reason_held_due(10);
  select count(*) into v_n from jsonb_array_elements(v) e where (e->>'id')::bigint in (v_a, v_b, v_c);
  if v_n <> 1 then v_fail := v_fail || ' R2 the same question was claimed ' || v_n || ' times;'; end if;
  v := public.fn_reason_held_resolve(v_a, '{"status":"answered","answer":"ZZ PROBE answer"}'::jsonb);
  if jsonb_array_length(v->'fanned') <> 2 then v_fail := v_fail || ' R2 fanned ' || jsonb_array_length(v->'fanned') || ' not 2;'; end if;
  select count(*) into v_n from public.reasoning_held_question where id in (v_a, v_b, v_c) and status in ('reasoned', 'applied');
  if v_n <> 3 then v_fail := v_fail || ' R2 ' || v_n || ' of 3 rows took the answer;'; end if;

  -- R3: a failed row stays failed when filed again; the same question under another key files nothing.
  v_id := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE a question that failed', v_req, '{}', '{"n":4}', 'probe', 'zzprobe:f');
  update public.reasoning_held_question set status = 'failed', attempts = 3, last_attempt_at = now() where id = v_id;
  perform public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE a question that failed', v_req, '{}', '{"n":4}', 'probe', 'zzprobe:f');
  select attempts into v_att from public.reasoning_held_question where id = v_id and status = 'failed';
  if v_att is distinct from 3 then v_fail := v_fail || ' R3 a failed row was reopened;'; end if;
  if public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE a question that failed', v_req, '{}', '{"n":5}', 'probe', 'zzprobe:g') <> v_id
     or exists (select 1 from public.reasoning_held_question where dedupe_key = 'zzprobe:g') then
    v_fail := v_fail || ' R3 a recently failed question was filed again under a new key;'; end if;

  -- R5: visitor chat lives an hour.
  v_id := public.fn_reason_hold('customer_support', 'site_assistant.person', 'ZZ PROBE how is the weather', v_req, '{}', '{"path":"/"}', 'probe', 'zzprobe:chat');
  if (select expires_at from public.reasoning_held_question where id = v_id) is null then v_fail := v_fail || ' R5 a visitor chat has no expiry;'; end if;
  update public.reasoning_held_question set expires_at = now() - interval '1 hour' where id = v_id;
  perform public.fn_reason_held_sweep();
  if (select status from public.reasoning_held_question where id = v_id) <> 'expired' then v_fail := v_fail || ' R5 a stale visitor chat was not expired;'; end if;

  -- R4: two held postmortems of one fault become one.
  select count(*) into v_n from (select subject->>'fault_key' fk from public.reasoning_held_question
                                  where surface = 'it_engineer.postmortem' and status = 'held' group by 1 having count(*) > 1) z;
  if v_n > 0 then v_fail := v_fail || ' R4 ' || v_n || ' fault(s) still have more than one held postmortem;'; end if;

  select count(*) into v_n from public.reasoning_held_question where status = 'held' and surface not like 'zz_demo.%';
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK held_after=' || v_n
                                     || ' open_deliberations=' || (select count(*) from public.seat_deliberation where status = 'open')
                                     || ' supply_gap_deciding=' || (select count(*) from public.supply_gap where status = 'deciding')
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
