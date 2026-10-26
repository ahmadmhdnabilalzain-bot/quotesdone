-- QA FIXTURE PURGE — EXECUTED ON PRODUCTION 2026-08-10 ON THE FOUNDER'S EXPLICIT DECISION.
--
-- This file is the record of a destructive production change. It is NOT re-runnable tooling and it
-- is NOT applied to staging: staging's demo fixtures are legitimate test data that demo_factory.mjs
-- depends on. Production is the only place they were wrong.
--
-- WHAT WAS THERE. Test data seeded into the live database before real traffic existed:
--   * 7 inquiries, every one carrying brief_source='qd_demo_fixture' and a summary beginning
--     "ZZ DEMO — ..." (six hvac, one aluminium, 7-8 Aug, all with customer_id null). They were the
--     ONLY inquiries the platform had ever had.
--   * 8 documents at status='orphaned', each pointing at a storage object that was never uploaded.
--     The row carries its own error: "Storage object never existed. QA fixture or seed row with no
--     object."
--
-- WHY IT MATTERED, MEASURED RATHER THAN ASSERTED.
--   * At 03:25 today fn_opportunity_scan was 25 minutes from telling the founder "the hvac industry
--     drew 6 inquir(y/ies) in 90 days — demand is running ahead of the supply able to answer it".
--     All six were fixtures. Every brief before the last one made the same mistake with these rows.
--   * The platform's single "revealed quote" — AED 185,000, refund window open to 11 Aug — was a
--     fixture, so the marketing dashboard's quote_to_reveal_pct of 14.3% was fixture-derived too.
--   * s26-verify-documentation asks whether every document received has been read and verified. It
--     read 7 of 16 and could never read more: the 8 orphans have no file to read, and marking them
--     verified would be fabrication. The check was unpassable while they sat there.
--
-- BLAST RADIUS, MAPPED FROM pg_constraint BEFORE ANYTHING WAS DELETED — the set is closed:
--   documents(8)   <- nothing references them (messages.document_id: 0 rows)
--   inquiries(7)   <- quotes 25, messages 1, transactions 1; all other 12 FK children: 0 rows
--   quotes(25)     <- transactions 1 (the same row), po_orders 0, comparison_candidate_v2 0
--   42 rows total. The one transaction carries reveal_fee NULL, payment_ref NULL and no Stripe id,
--   so NO REAL MONEY was involved.
--
-- REVERSIBLE. Every row was copied whole into public.qa_fixture_purge_archive as jsonb BEFORE the
-- delete, with its source table and id. 42 archived, 42 deleted. To inspect or restore:
--     select source_table, count(*) from public.qa_fixture_purge_archive group by 1;
--     select payload from public.qa_fixture_purge_archive where source_table='inquiries';
--
-- NO SCORER CHECK REGRESSES. Only four lines in the whole blueprint mention inquiries, and the twin
-- check states the reason in its own comment: "Row count is deliberately NOT required — QuotesDone
-- is pre-traction and customers, inquiries and transactions are all at zero today, so a population
-- clause would make this unsatisfiable." fn_os_search's corpus test asks whether the table is READ,
-- not whether it has rows.
--
-- RESULT: inquiries 7 -> 0, documents 16 -> 8 (7 done + 1 genuine extraction failure), quotes 25 -> 0,
-- transactions 1 -> 0. s26-verify-documentation goes from unpassable to 7 of 8 — one real
-- doc_extract truncation bug away from passing.

create table if not exists public.qa_fixture_purge_archive (
  id bigserial primary key,
  purged_at timestamptz not null default now(),
  reason text not null,
  source_table text not null,
  row_id text,
  payload jsonb not null
);

-- archive first, in child-to-parent order
insert into public.qa_fixture_purge_archive (reason, source_table, row_id, payload)
select 'founder decision 2026-08-10: purge QA fixtures from production', 'transactions', t.id::text, to_jsonb(t)
  from public.transactions t
 where t.inquiry_id in (select i.id from public.inquiries i where i.brief_source='qd_demo_fixture');

insert into public.qa_fixture_purge_archive (reason, source_table, row_id, payload)
select 'founder decision 2026-08-10: purge QA fixtures from production', 'messages', m.id::text, to_jsonb(m)
  from public.messages m
 where m.inquiry_id in (select i.id from public.inquiries i where i.brief_source='qd_demo_fixture');

insert into public.qa_fixture_purge_archive (reason, source_table, row_id, payload)
select 'founder decision 2026-08-10: purge QA fixtures from production', 'quotes', q.id::text, to_jsonb(q)
  from public.quotes q
 where q.inquiry_id in (select i.id from public.inquiries i where i.brief_source='qd_demo_fixture');

insert into public.qa_fixture_purge_archive (reason, source_table, row_id, payload)
select 'founder decision 2026-08-10: purge QA fixtures from production', 'inquiries', i.id::text, to_jsonb(i)
  from public.inquiries i where i.brief_source='qd_demo_fixture';

insert into public.qa_fixture_purge_archive (reason, source_table, row_id, payload)
select 'founder decision 2026-08-10: purge QA fixtures from production', 'documents', d.id::text, to_jsonb(d)
  from public.documents d where d.status='orphaned';

-- then delete, same order
begin;
delete from public.transactions t
 where t.inquiry_id in (select i.id from public.inquiries i where i.brief_source='qd_demo_fixture');
delete from public.messages m
 where m.inquiry_id in (select i.id from public.inquiries i where i.brief_source='qd_demo_fixture');
delete from public.quotes q
 where q.inquiry_id in (select i.id from public.inquiries i where i.brief_source='qd_demo_fixture');
delete from public.inquiries i where i.brief_source='qd_demo_fixture';
delete from public.documents d where d.status='orphaned';
commit;
