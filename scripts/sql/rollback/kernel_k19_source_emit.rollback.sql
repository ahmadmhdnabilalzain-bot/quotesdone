-- Rollback for K19, the canonical source wrapper.
--
-- REFUSE TO RUN THIS WHILE ANY SOURCE STILL CALLS IT. Dropping fn_kernel_source_emit while a
-- trigger on inquiries, quotes or transactions still names it turns every insert on those tables
-- into an error. Check first:
--
--   select check_name, actual from public.fn_kernel_source_emit_state()
--    where check_name = 'sources_cut_over_to_the_wrapper';
--
-- and roll back each cutover increment before this file, not after it.
--
-- kernel_adapter_failure is NOT dropped. It records every time the kernel raised while a source
-- was handing work to it, and those rows are the evidence that a caught exception was not a
-- silence. They outlive the wrapper that collected them.

begin;

do $check$
declare n bigint;
begin
  select count(*) into n from pg_proc p join pg_namespace nsp on nsp.oid = p.pronamespace
   where nsp.nspname = 'public' and p.proname <> 'fn_kernel_source_emit'
     and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
         ~ '\yfn_kernel_source_emit\s*\(';
  if n > 0 then
    raise exception 'K19 rollback refused: % routine(s) still call fn_kernel_source_emit. Roll '
                    'back the cutover increments first, or every write on their tables becomes an '
                    'error.', n;
  end if;
end
$check$;

drop function if exists public.fn_kernel_source_emit_state();
drop function if exists public.fn_kernel_source_emit(text, jsonb);

commit;
