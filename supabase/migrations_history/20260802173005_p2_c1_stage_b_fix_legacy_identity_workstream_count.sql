-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802173005   name: p2_c1_stage_b_fix_legacy_identity_workstream_count
-- SHA-256 of the applied SQL: ac6fd7ab70ea95f04d1f9a784c9f71d328a82ba4f9fefe1ad9e34f20b9d0cdb7
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- Found by Stage B test 13.
--
-- v_inquiry_workstream_identity computed the legacy (no-group) case as
--   coalesce((select count(*) from inquiry_workstream where group_id = g.id and g.id is null), 1)
-- and count(*) over zero rows returns 0, not NULL. So coalesce never fired and every existing
-- single-route inquiry reported effective_workstreams = 0 - "this inquiry has no workstreams" -
-- when the whole point of the compatibility identity is that it has exactly one.
--
-- The shape column was right, so nothing downstream misbehaved yet. It would have, the moment
-- anything counted workstreams to decide whether an inquiry was ready.

create or replace view public.v_inquiry_workstream_identity as
select i.id as inquiry_id, g.id as group_id,
       (g.id is not null) as has_group,
       case when g.id is null then 1
            else (select count(*) from public.inquiry_workstream w
                   where w.group_id = g.id and w.active) end as effective_workstreams,
       case when g.id is null then 'implicit_single_workstream' else 'multi_workstream' end as shape
  from public.inquiry_intake i
  left join public.inquiry_workstream_group g on g.inquiry_id = i.id;

comment on view public.v_inquiry_workstream_identity is
  'Reading this view writes nothing. An inquiry with no group reports exactly one implicit workstream, which is how the system behaves today.';
;