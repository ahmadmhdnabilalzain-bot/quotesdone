-- Rollback for K22, fn_kernel_run_for.
--
-- Refuse while any routine still calls it: trg_quote_items_roll and qd_on_refund_resolved both do,
-- and dropping it turns every quote-item and transaction write into an error. Roll back
-- kernel_k22b_cutover_03_existing_run first.
begin;
do $c$
declare n bigint;
begin
  select count(*) into n from pg_proc p join pg_namespace nsp on nsp.oid = p.pronamespace
   where nsp.nspname = 'public' and p.proname <> 'fn_kernel_run_for'
     and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
         ~ '\yfn_kernel_run_for\s*\(';
  if n > 0 then
    raise exception 'K22 rollback refused: % routine(s) still call fn_kernel_run_for. Roll back '
                    'the cutover increment first.', n;
  end if;
end
$c$;
drop function if exists public.fn_kernel_run_for(text);
commit;
