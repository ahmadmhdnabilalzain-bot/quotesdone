-- The Evolution OS is specified over eight domains and PROMPTING is one of them, but
-- evolution_proposal.change_class refused it: the allowed set was knowledge / process / code /
-- policy / model_routing / org. So the one domain that governs how every employee reasons could not
-- be proposed against even if a routine wanted to. Same for the trigger taxonomy — there was no
-- kind for "this was never measured".
--
-- Widening an allow-list, not weakening a check: nothing that used to be rejected for being wrong
-- is now accepted, and every existing row still satisfies both constraints.
alter table public.evolution_proposal drop constraint if exists evolution_proposal_change_class_check;
alter table public.evolution_proposal add constraint evolution_proposal_change_class_check
  check (change_class = any (array['knowledge','process','code','policy','model_routing','org','prompting']));

alter table public.evolution_proposal drop constraint if exists evolution_proposal_trigger_kind_check;
alter table public.evolution_proposal add constraint evolution_proposal_trigger_kind_check
  check (trigger_kind = any (array['repeated_failure','metric_off_target','cost_anomaly','manual',
                                   'audit_gap','review_rejection','prompt_unmeasured']));
