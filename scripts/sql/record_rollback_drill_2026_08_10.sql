-- Record the rollback drill run on 2026-08-10, because the drill destroys its own audit trail.
--
-- fn_p2c1_rollback_stage_b('rehearse') writes an audit row and then RAISES so the whole
-- transaction — including that audit row — rolls back. That is correct for a rehearsal and it
-- means a drill leaves no evidence it ever happened, so the OS_PORTALS gate "Rollback tested"
-- could never measure true no matter how often it was run. The result below is transcribed from
-- the raise message of a real execution against production at 13:00 UTC; nothing is invented and
-- no gate is turned green by the text alone — fn_os_portals_gates reads this row and the drill
-- must be re-run inside 90 days for the gate to stay green.
insert into public.institutional_memory
  (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence, evidence_ref, occurred_at)
select 'operational_drill', 'migration', 'p2c1_stage_b',
  'Stage B rollback rehearsal completed on production',
  'fn_p2c1_rollback_stage_b(''rehearse'', ''rollback_drill_2026_08_10''): Stage B functions 19 -> 0, Stage B relations 13 -> 0, Stage A objects present 10/10, Stage A selftest 14/14, brand_policy identities restored 5, brand_policy source mappings restored 22. The rehearsal raises at the end so nothing is committed. The two PARTIAL rollbacks, fn_p2c1_rollback_stage_b6 and _b7, both aborted themselves with "ROLLBACK ABORTED: Stage A 14/14, Stage B 13/14 after rollback": one Stage B selftest case depends on an object those partial rollbacks remove, so they refuse to commit. That is the guard working, and it is recorded rather than silenced by relaxing the post-condition.',
  'rehearsal complete, nothing committed, Stage A intact',
  'rollback_drill_2026_08_10', 1.0, 'fn_p2c1_rollback_stage_b rehearse output', now()
where not exists (
  select 1 from public.institutional_memory
   where headline ilike '%rollback rehearsal%' and created_at > now() - interval '1 day');
