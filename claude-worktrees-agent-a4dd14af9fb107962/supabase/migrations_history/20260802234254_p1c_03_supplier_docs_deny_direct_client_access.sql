-- Applied version: 20260802234254
-- Recovered from production, byte-for-byte as applied.

-- Phase 1 emergency containment, step 3 of 4 — SUPPLIER DOCUMENTS.
-- Audit finding 1.3 / 9.1: the only two policies on storage.objects grant SELECT and INSERT on the
-- whole supplier-docs bucket to every authenticated user, with no owner predicate. Any signed-in
-- account can list, download and overwrite every supplier's trade licence, Emirates ID and IBAN letter.
-- Containment: record both policies with a verbatim recreate statement, then drop them.
-- RLS stays enabled with zero policies -> deny-all for anon and authenticated.
-- service_role has rolbypassrls = true, so edge functions are unaffected.
-- No object is deleted. The 15 existing files are untouched.

do $CONTAIN$
declare
  p record;
  v_sql text;
begin
  for p in select * from pg_policies
            where schemaname='storage' and tablename='objects'
              and policyname in ('supplier read docs','supplier upload docs') loop

    v_sql := format('create policy %I on %I.%I as %s for %s to %s',
               p.policyname, p.schemaname, p.tablename,
               case when p.permissive='PERMISSIVE' then 'permissive' else 'restrictive' end,
               lower(p.cmd),
               array_to_string(p.roles, ', '))
          || coalesce(' using ('||p.qual||')','')
          || coalesce(' with check ('||p.with_check||')','')
          || ';';

    insert into containment.policy_removed
      (schemaname, tablename, policyname, cmd, permissive, roles, qual, with_check, rollback_sql)
    values (p.schemaname, p.tablename, p.policyname, p.cmd, p.permissive,
            p.roles::text, p.qual, p.with_check, v_sql);

    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;

  insert into containment.change_log (area, change, before_value, after_value, rollback_sql)
  values ('B_supplier_docs',
          'storage.objects policies on supplier-docs dropped (deny-all for anon/authenticated)',
          '2 permissive policies: bucket-wide SELECT + INSERT to authenticated, no owner predicate',
          '0 policies; RLS enabled; service_role unaffected (rolbypassrls)',
          'select string_agg(rollback_sql, E''\n'') from containment.policy_removed where restored_at is null;');
end
$CONTAIN$;;
