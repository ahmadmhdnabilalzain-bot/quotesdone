-- customer_support: a held question whose reasoned message the model could not write goes BACK to the replay.
-- Founder ruling 1339, extended by ledger 1348: a message a person reads as a reply is the model's; code-written text only
-- when OpenRouter is down. PR #1669 made the WhatsApp "needs a person" contact notice (reasoned_delivery.ts,
-- wa_inbound.needs_a_person) model-written; with the model up and no draft passing, the delivery is via 'unwritten'.
--
-- WHY THIS FILE (review of #1669, read from the LIVE pg_get_functiondef on 27 Oct 2026). By the time the delivery runs,
-- fn_reason_held_resolve has already set the row to 'reasoned'. fn_reason_held_delivered kept `status` for anything
-- not delivered and not 'none', so an 'unwritten' row stayed 'reasoned' for good: fn_reason_held_due claims only
-- 'held' rows, and fn_reason_held_escalate takes only 'failed' (or 'held' after 48 h / 15 min). The person was never
-- answered and nobody was told.
--
-- NOW: via 'unwritten' puts the row back to 'held' while it has tries left (attempts < 3, the same bound
-- fn_reason_held_due uses), so the replay reasons and asks the model again after its 10 minutes; at its last try it
-- becomes 'failed', which fn_reason_held_escalate hands to the seat and fn_reason_held_notice_due then owes the person
-- the MODEL-WRITTEN holding notice (reasoned_delivery.holdingNotice; code words only on an outage). Every other path is
-- unchanged: delivered or 'none' -> 'applied'; anything else keeps its status.
-- One overload exists (fn_reason_held_delivered(bigint,jsonb), enumerated live). CREATE OR REPLACE keeps its ACL
-- (postgres, service_role only), so there is no revoke here; search_path stays pinned.
-- prevented by: scripts/sql/an_unwritten_person_notice_goes_back_to_the_replay_probe.sql,
--               scripts/checks/replies_are_written_by_the_model_unless_openrouter_is_down.test.mjs (R6)
CREATE OR REPLACE FUNCTION public.fn_reason_held_delivered(p_id bigint, p_delivery jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_n int; v_ids jsonb;
begin
  update public.reasoning_held_question
     set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('delivery', p_delivery),
         status = case when coalesce((p_delivery->>'delivered')::boolean, false) or p_delivery->>'via' = 'none' then 'applied'
                       -- the model was up and nothing it wrote passed: asked again by the replay, escalated at its last try
                       when p_delivery->>'via' = 'unwritten' then case when attempts >= 3 then 'failed' else 'held' end
                       else status end,
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
end $function$;
