-- K32 — the register records the final disposition of every source, from measurement.
--
-- Each status below is set from what the deployed code does, not from this session's memory of
-- what it did. The three database triggers cut over in K29 are matched by scanning pg_proc for a
-- live fn_kernel_source_emit call; the rest name the chokepoint or the measurement that decides
-- them.
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

-- Cut over by a NEW trigger on the table each one writes, so every writer of that table reaches
-- the kernel and not only the Edge Function that prompted it.
update public.phase_c_source_cutover
   set status = 'CUTOVER_VIA_TABLE_TRIGGER',
       cutover_action = 'Cut over by a trigger on the table it writes: '
         || case source_component_id
              when 'edge:site_assistant' then 'assistant_logs, WHEN escalated -> W18. A question the FAQ answered is not a support signal.'
              when 'edge:wa_inbound'     then 'wa_messages, WHEN escalated -> W18. Same filter, same reason.'
              when 'edge:inbound_email'  then 'inbound_messages, WHEN created_new_lead -> W09. The trigger reads the decision the function already made.'
              when 'edge:sup_dob'        then 'leads, WHEN owner_dob first appears -> document.arrived_for_run on the W10 run. Narrowed twice because leads is 20,470 rows.'
            end
 where source_component_id in ('edge:site_assistant','edge:wa_inbound','edge:inbound_email','edge:sup_dob');

update public.phase_c_source_cutover
   set status = 'COVERED_BY_A_CUT_OVER_TABLE_TRIGGER',
       cutover_action = 'No edit. It writes a DRAFT in inquiry_intake; customer_api promotes a '
                     || 'draft marked ready into public.inquiries and marks it consumed, and that '
                     || 'insert already reaches the kernel through trg_inquiry_received_a. '
                     || 'Emitting here too would open two W05 runs for one customer request.'
 where source_component_id = 'edge:inquiry_intake';

update public.phase_c_source_cutover
   set status = 'READ_ONLY_CONFIRMED_BY_MEASUREMENT',
       cutover_action = 'No adapter. Measured against the deployed source: '
         || case source_component_id
              when 'edge:attach_photos'   then 'it writes NO table at all — it reads app_secrets and customers and returns.'
              when 'edge:supplier_onboard' then 'its only write is one agent_actions row, status logged, risk low, in a try/catch whose own comment reads "telemetry is not the product".'
              when 'edge:resend_inbound'  then 'it books expenses from forwarded receipts and writes none of the eight tables K18 protects. It is not a bypass; it OWES a Phase B workflow, since W27 is a scheduled close and not a receipt arriving.'
            end
 where source_component_id in ('edge:attach_photos','edge:supplier_onboard','edge:resend_inbound');

commit;
