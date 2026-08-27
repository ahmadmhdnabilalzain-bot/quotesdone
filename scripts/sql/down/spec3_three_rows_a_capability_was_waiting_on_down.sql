-- Reverse of scripts/sql/spec3_three_rows_a_capability_was_waiting_on.sql.
--
-- Each delete is keyed on the same identity the insert guarded on, and on the provenance this
-- session stamped, so a row someone else wrote for the same subject afterwards is not removed by
-- rolling this file back.

begin;

delete from public.agent_knowledge
 where agent_key = 'product_ux_designer'
   and source_ref = 'spec3:2026-08-27:employee-knowledge';

delete from public.cron_registry
 where jobname = 'phase_c_outbox_deliver_1min'
   and human_name = 'Phase C Outbox Delivery';

delete from public.supplier_negotiation_policy
 where scope = 'default'
   and approved_by = 'spec3:2026-08-27';

commit;
