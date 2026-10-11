-- A HELD ANSWER SAYS WHEN IT WAS ASKED -- it_engineer, 7 Oct 2026.
--
-- Ledger 1175 lifted the founder's hold; the replay (_shared/think.ts replayHeld) now drains the backlog in about an
-- hour instead of 17. Some of those questions were asked days ago. An answer to a stale question must not reach a
-- real person unreviewed, so the replay needs the question's age: fn_reason_held_due now returns created_at with each
-- claimed row. One change to the RETURNING list; body otherwise byte-copied from production (pg_get_functiondef,
-- 7 Oct 2026). CREATE OR REPLACE keeps the ACL.
-- Prevented by: supabase/functions/_shared/think.test.ts ('a stale held answer is stored, never sent unreviewed').

CREATE OR REPLACE FUNCTION public.fn_reason_held_due(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_gate jsonb; v jsonb;
begin
  perform public.fn_reason_held_sweep();
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with lead as (
    select distinct on (surface, coalesce(qhash, id::text)) id, attempts, last_attempt_at, created_at
      from public.reasoning_held_question
     where status = 'held' and attempts < 3
     order by surface, coalesce(qhash, id::text), attempts desc, id
  ), due as (
    select h.id from public.reasoning_held_question h
     where h.id in (select id from lead where last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     -- 6 Oct: the NEWEST due question first; a retry (last_attempt_at set) still waits its 10 minutes, then goes
     -- behind untried rows exactly as before, so it is never starved past its three tries.
     order by h.last_attempt_at nulls first, h.created_at desc
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    -- 6 Oct: the first claim starts the 14-day clock (a question waits out the hold without ageing)
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now(),
           expires_at = case when h.attempts = 0 and h.surface not like 'site_assistant.%'
                             then now() + interval '14 days' else h.expires_at end
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject, h.created_at
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $function$
;

-- 12 Oct (release review of #1287): a stale answer is held for review, and a hold nobody sees is one-way.
-- Every held_for_review delivery now raises (or refreshes) one finding owned by customer_support, counting
-- every answered-but-unsent row, so the seat reviews and sends or retires them. CREATE OR REPLACE keeps the ACL.
create or replace function public.fn_reason_held_delivered(p_id bigint, p_delivery jsonb)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_n int; v_ids jsonb;
begin
  update public.reasoning_held_question
     set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('delivery', p_delivery),
         status = case when coalesce((p_delivery->>'delivered')::boolean, false) or p_delivery->>'via' = 'none' then 'applied' else status end,
         applied_at = case when coalesce((p_delivery->>'delivered')::boolean, false) or p_delivery->>'via' = 'none' then now() else applied_at end
   where id = p_id;
  if p_delivery->>'via' = 'held_for_review' then
    select count(*), coalesce(jsonb_agg(id order by id desc) filter (where true), '[]'::jsonb)
      into v_n, v_ids
      from public.reasoning_held_question
     where status <> 'applied' and result->'delivery'->>'via' = 'held_for_review';
    perform public.fn_it_engineer_finding_upsert('reasoned_answer_held_for_review',
      v_n || ' stale reasoned answer(s) are held for review before reaching a person',
      'held-question replay (fn_reason_held_delivered)', 'customer_facing', v_n,
      jsonb_build_object('waiting', v_n, 'ids', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_ids) x limit 20) z),
                         'owner_seat', 'customer_support', 'duty', 'reply_time'),
      '{}'::text[], array['whether the person was answered on another channel since'], 'customer_support');
  end if;
end $fn$;
