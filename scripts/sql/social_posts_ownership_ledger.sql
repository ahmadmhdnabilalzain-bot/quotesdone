-- OWNERSHIP LEDGER FOLLOWS THE MANIFEST — fn_marketing_studio and fn_review_pending are owned by
-- scripts/sql/social_posts_are_clickable.sql (6 Sep 2026).
--
-- Both were defined only in migrations_history files (20260726130146_fn_marketing_studio.sql,
-- 20260724060712_founder_review_gates.sql), so the ledger recorded them HISTORICAL_APPLICATION. The
-- manifest now names the new file; this reconciles the ledger to the manifest. Bookkeeping only.
--
--   node scripts/apply_sql.mjs scripts/sql/social_posts_ownership_ledger.sql --apply --ddl

begin;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/social_posts_are_clickable.sql',
       evidence = 'recorded HISTORICAL_APPLICATION (migrations_history), repository derives QUOTESDONE_APPLICATION from the manifest — reconciled 6 Sep 2026 when the Marketing lists were given their permalinks, media and preview URLs.',
       recorded_at = now()
 where schema_name = 'public' and routine_name in ('fn_marketing_studio', 'fn_review_pending')
   and coalesce(identity_args,'') = '';

do $proof$
declare v int;
begin
  select count(*) into v from public.kernel_routine_ownership
   where schema_name = 'public' and routine_name in ('fn_marketing_studio', 'fn_review_pending')
     and source_file = 'scripts/sql/social_posts_are_clickable.sql';
  if v <> 2 then raise exception 'ledger rows for the two marketing routines not re-pointed (% rows)', v; end if;
  raise notice 'proof: fn_marketing_studio and fn_review_pending owned by the manifest file';
end $proof$;

commit;
