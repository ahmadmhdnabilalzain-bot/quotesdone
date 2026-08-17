-- K26 — the register must say which sources were actually cut over.
--
-- Seventeen rows still read ADAPTER_ASSIGNED_CUTOVER_PENDING, and eight of them are the database
-- triggers increments 1 to 3 already moved onto the kernel. A register that reports work as
-- pending after it has landed is the same defect as one that reports it done before it has: the
-- number stops meaning anything. Five more are frontend routes, which are cut over BY the Edge
-- Function they call — a browser cannot hold a service-role key and must never reach the kernel
-- directly.
--
-- Verified before writing: each of the eight routines below was read out of pg_proc and contains a
-- live call to fn_kernel_source_emit. The status is set from that measurement, not from this
-- session's memory of what it did.
begin;

update public.phase_c_source_cutover c
   set status = 'CUTOVER_COMPLETE',
       cutover_action = 'Cut over. The deployed trigger function calls fn_kernel_source_emit, '
                     || 'verified against pg_proc at the time this row was written.'
 where c.source_type = 'database_trigger'
   and exists (
     select 1 from pg_trigger tg
       join pg_class cl on cl.oid = tg.tgrelid
       join pg_proc p on p.oid = tg.tgfoid
      where tg.tgname = split_part(c.source_component_id, ':', 3)
        and cl.relname = split_part(split_part(c.source_component_id, ':', 2), '.', 2)
        and not tg.tgisinternal
        and regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/',' ','g'),'--[^\n]*',' ','g')
            ~ '\yfn_kernel_source_emit\s*\(');

update public.phase_c_source_cutover
   set status = 'COVERED_BY_THE_EDGE_FUNCTION_IT_CALLS',
       cutover_action = 'No edit. A browser cannot hold a service-role key and must never call the '
                     || 'kernel directly; this route is cut over by the Edge Function behind it.'
 where source_type = 'frontend_path';

commit;
