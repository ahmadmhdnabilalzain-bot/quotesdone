-- Two things this project has repeatedly needed and never had.

-- 1. A way to get migrations applied through the management API back into the repository. Every
-- drift incident on this project has the same root: SQL that exists only in production because it
-- was applied from a tool rather than a checkout. This makes recovering it a single call.
create or replace function public.kb_dump_migrations(p_since text default '20260101000000')
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('version', version, 'name', name,
                                               'sql', array_to_string(statements, E'\n\n'))
                            order by version), '[]'::jsonb)
  from supabase_migrations.schema_migrations
  where version >= p_since;
$$;
revoke all on function public.kb_dump_migrations(text) from public, anon, authenticated;
grant execute on function public.kb_dump_migrations(text) to service_role;

-- 2. The two schema changes applied ad hoc during the import, recorded here so the repository is a
-- complete description of the database rather than a nearly-complete one.
alter table kb_stage.decision_rules add column if not exists source_rule_id text;
alter table kb_stage.decision_rules add column if not exists record_id text;
create index if not exists kb_stage_rules_srcid_idx
  on kb_stage.decision_rules (category_slug, subcategory_slug, source_rule_id);
comment on column kb_stage.decision_rules.source_rule_id is
  'rule_id as written inside the package. 39 of the 67 packages wrap their rules in the standard record envelope (rule body in structured_data) while 28 emit them flat; both land here keyed on a globally unique id, with the package-local id kept for cross-references from then_json.';
