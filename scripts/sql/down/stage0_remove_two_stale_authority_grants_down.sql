-- Down: re-seed the two authority grants removed by stage0_remove_two_stale_authority_grants.sql,
-- exactly as measured on production before deletion (28 Aug 2026).
begin;
set local app.change_reason = 'Down: restore 2 stale employee_authority grants (Stage 0 Defect 3 rollback).';

insert into public.employee_authority (agent_key, action_class, max_tier, threshold_aed, note) values
  ('gov_relations_mgr', 'analysis',      'advisory',   null,
   'seeded 14 Aug 2026 from canonical authority_level advisory; an active role with no authority record is undefined, not restricted'),
  ('marketing_copy',    'content_draft', 'autonomous', 0,
   'Must cite the brand guideline followed.')
on conflict do nothing;

commit;
