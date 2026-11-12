-- PROBE (pure, no DDL, aborted transaction) for the_consultant_role_is_called_consultant_not_designer.sql.
-- Seat: sales_engineer. 12 Nov 2026, founder ruling 1670.
-- Run AFTER the file, or with it, rolled back:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/the_consultant_role_is_called_consultant_not_designer.sql scripts/sql/the_consultant_role_is_called_consultant_not_designer_probe.sql
-- It writes nothing and always ends in raise exception 'CHK<<json>>'. It cannot reach a person: it reads one taxonomy table.
-- WHAT IT ASKS: consultant is labelled 'Consultant'; no active role's label says designer; the other seven labels and every role's
-- code, aliases, flags and sort are as read live on 12 Nov 2026 (consultant: consultant, consultancy, engineering design, architect).
do $probe$
declare f text := ''; v_label text; v_n int; v_others text;
begin
  select label into v_label from public.taxonomy_role where code = 'consultant';
  if v_label is distinct from 'Consultant' then f := f || 'consultant is labelled ' || coalesce(v_label, 'nothing') || '; '; end if;
  if exists (select 1 from public.taxonomy_role where active and label ~* 'design') then f := f || 'a role label still says designer; '; end if;
  select count(*) into v_n from public.taxonomy_role where active;
  if v_n <> 8 then f := f || v_n || ' active roles, not 8; '; end if;
  select string_agg(code || '=' || label, ', ' order by sort) into v_others from public.taxonomy_role where code <> 'consultant';
  if v_others is distinct from 'manufacturer=Manufacturer, distributor=Authorised distributor, supplier=Supplier / trading, installer=Installer / applicator, contractor=Contractor, turnkey_fitout=Turnkey / fit-out contractor, maintenance=Maintenance / AMC'
    then f := f || 'another role label moved: ' || coalesce(v_others, '') || '; '; end if;
  if not exists (select 1 from public.taxonomy_role where code = 'consultant' and aliases = array['consultant','consultancy','engineering design','architect'] and not supplies and not executes and not whole_scope and sort = 80)
    then f := f || 'consultant lost an alias, a flag or its place; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when f = '' then 'PROBE OK' else 'PROBE FAILED: ' || f end, 'consultant', v_label, 'active_roles', v_n);
end $probe$;
