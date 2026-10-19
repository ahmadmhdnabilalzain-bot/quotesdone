-- PURGE THE TASKS AND HANDOFFS FIXTURE SUPPLIER REGISTRATIONS FILED (13 Oct 2026, seat: customer_support).
-- NOT APPLIED. Deleting production rows waits for the founder's go: ruling 1199 ("delete all test and demo data once
-- and for all after the tests") covers it, and it runs only after the final clean sandbox pass, in the same purge run
-- as #1348. See scripts/sql/pending/fixture_supplier_registration_tasks_and_handoffs_are_purged.txt.
--
-- SCOPE, by fixture markers only — nothing else is read as a reason to delete:
--   org_tasks    : detail starts '[founder_mail:supplier_registered]' (filed by fn_founder_mail_route) AND the named
--                  supplier is 'ZZ DEMO ...', or the text carries an @example.invalid address or a qd_run: tag.
--   agent_actions: kind 'handoff' on target_table 'notifications' whose facts.msg_type is 'supplier_registered' AND
--                  whose facts.supplier_id is a lead public.fn_seat_clock_lead_is_fixture() says is a fixture (or
--                  that carries a qd_run:<tag> on leads.tags), or whose own text names a 'ZZ DEMO' new supplier.
-- Idempotent: a second run deletes 0 and still returns its verdict row. Counts first with
-- fixture_supplier_registration_tasks_and_handoffs_are_purged_probe.sql (rolled back).
with fixture_lead as (
  select l.id from public.leads l
   where public.fn_seat_clock_lead_is_fixture(l)
      or exists (select 1 from unnest(coalesce(l.tags, '{}'::text[])) t where t like 'qd\_run:%')
), del_tasks as (
  delete from public.org_tasks t
   where t.detail like '[founder_mail:supplier\_registered]%'
     and (t.detail ~* 'New supplier "\s*zz\s*demo' or t.detail ~* '@example[.]invalid' or t.detail like '%qd\_run:%')
  returning t.id
), del_handoffs as (
  delete from public.agent_actions a
   where a.kind = 'handoff' and a.target_table = 'notifications'
     and a.detail #>> '{summary,known,facts,msg_type}' = 'supplier_registered'
     and ((a.detail #>> '{summary,known,facts,supplier_id}') in (select id::text from fixture_lead)
          -- the walk's lead already purged: the handoff's own words name a ZZ DEMO supplier (28 rows, 13 Oct)
          or a.detail::text ~* 'New supplier \\"\s*zz\s*demo')
  returning a.id
)
select 'PURGE OK' as verdict,
       (select count(*) from del_tasks)    as org_tasks_deleted,
       (select count(*) from del_handoffs) as handoffs_deleted;
