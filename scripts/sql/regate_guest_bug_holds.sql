-- Re-evaluate everything the guest bug held. Not a mass-close: each row goes back to 'pending',
-- which re-fires trg_action_gate, and the GATE decides again under the corrected role lookup.
-- Anything it still refuses stays in needs_review. Refunds and money-carrying actions are still
-- refused -- probed before this ran: ordinary=pending, refund=needs_review, money=needs_review.
select set_config('app.change_reason',
  'Re-gating actions held only by the guest-role defect, now that agent autonomy is armed. The gate re-decides each one; nothing is force-approved.', true);

with ranked as (
  select id, row_number() over (partition by agent, kind, target_id order by created_at desc) rn
    from agent_actions where status='needs_review' and target_id is not null)
update agent_actions set status='superseded', decided_by='autonomy_arming', decided_at=now(),
       detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object('reason','exact duplicate on (agent, kind, target_id), kept the newest')
 where id in (select id from ranked where rn > 1);

with target as (
  select a.id from agent_actions a join decision_log d on d.id = a.decision_log_id
   where a.status='needs_review' and d.reasons::text ilike '%guest%lacks permission%'
     and jsonb_array_length(d.reasons) = 1)
update agent_actions set status='pending' where id in (select id from target);
