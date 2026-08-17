-- Rollback for PBCR-001. Restores W14-S05 to the overlay owner, the overlay's accountability and
-- the two deleted handoff edges, exactly as they stood before 2026-08-17.
--
-- This puts the REGISTRY DEFECT back: W14 returns to "closure topologically reachable but NOT
-- executable" and the estate returns to 1 of 30 workflows with no executable closure path. Run it
-- only to restore the pre-change baseline, never as a fix.
--
-- The PBCR-001 row in phase_b_change_request is NOT deleted. It is append-only by trigger, and a
-- change request that vanishes when its change is rolled back is not a record of anything. The
-- rollback is itself the next fact, and phase_b_change_request.applied_at stays as it was.

begin;

set local app.phase_b_change_reason =
  'PBCR-001-ROLLBACK: restoring the pre-2026-08-17 W14-S05 ownership, the overlay accountability '
  'flag and handoffs H-W14-04-05 / H-W14-05-06. This deliberately reinstates the known registry '
  'defect that PBCR-001 fixed.';

update public.phase_b_workflow_step
   set accountable_role_id       = 'relevant_category_overlay',
       package_accountable_token = 'relevant_category_overlay',
       actor_kind                = 'category_overlay',
       contributors              = array['quote_evaluation','relevant_domain_specialist'],
       notes                     = null
 where step_id = 'W14-S05';

update public.phase_b_dynamic_actor
   set may_be_accountable = true,
       resolution_rule = 'Resolve from the approved canonical route set; overlays cannot receive '
                         'prohibited authority.'
 where actor_token = 'relevant_category_overlay';

-- The two rows exactly as they stood on production before PBCR-001 deleted them, captured
-- from phase_b_handoff in the same session. Nothing here is reconstructed or inferred.
insert into public.phase_b_handoff
  (handoff_id, workflow_id, from_step_id, to_step_id, sending_role_id, receiving_role_id, sending_department_id, receiving_department_id, handoff_type, trigger, required_packet, receiving_acceptance_criteria, rejection_condition, return_owner_role_id, closure_condition, sla_policy_id)
values
  ('H-W14-04-05',
   'W14',
   'W14-S04',
   'W14-S05',
   'quote_evaluation',
   'relevant_category_overlay',
   'marketplace_supplier_network',
   'category_overlay',
   'cross_department',
   'Accepted output of W14-S04: Commercial completeness findings.',
   'Commercial completeness findings.; source business object/version; acceptance evidence; unresolved blockers; requested next action.',
   'Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy.',
   'Required packet incomplete, source version invalid, owner unauthorized, or prerequisite gate not satisfied.',
   'quote_evaluation',
   'W14-S05 accepts the packet or rejects it with a specific reason and return owner.',
   'SLA-HANDOFF-CRITICAL'),
  ('H-W14-05-06',
   'W14',
   'W14-S05',
   'W14-S06',
   'relevant_category_overlay',
   'quote_evaluation',
   'category_overlay',
   'marketplace_supplier_network',
   'cross_department',
   'Accepted output of W14-S05: Technical completeness findings.',
   'Technical completeness findings.; source business object/version; acceptance evidence; unresolved blockers; requested next action.',
   'Prior required step accepted or workflow start event. Workflow record; prior accepted outputs; applicable policy.',
   'Required packet incomplete, source version invalid, owner unauthorized, or prerequisite gate not satisfied.',
   'relevant_category_overlay',
   'W14-S06 accepts the packet or rejects it with a specific reason and return owner.',
   'SLA-HANDOFF-CRITICAL')
on conflict (handoff_id) do nothing;

commit;
