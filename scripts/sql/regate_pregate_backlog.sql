-- Push the pre-gate backlog through the gate. These 93 rows carry no decision_log at all: they
-- were written straight to needs_review by paths that predate trg_action_gate, so no gate has
-- ever looked at them. Setting them to 'pending' makes the gate decide for the first time.
-- Money kinds are excluded from the sweep entirely and, even if included, would be refused.
select set_config('app.change_reason',
  'Re-gating the pre-gate backlog now that agent autonomy is armed. Every row goes through trg_action_gate, which decides; refund/payout/charge/payment/transfer kinds are excluded outright and remain the founder''s.', true);

with ranked as (
  select id, row_number() over (partition by agent, kind, target_id order by created_at desc) rn
    from agent_actions where status='needs_review' and target_id is not null)
update agent_actions set status='superseded', decided_by='autonomy_arming', decided_at=now()
 where id in (select id from ranked where rn > 1);

update agent_actions set status='pending'
 where status='needs_review' and decision_log_id is null
   and lower(coalesce(kind,'')) !~ '(refund|payout|charge|payment|transfer)';
