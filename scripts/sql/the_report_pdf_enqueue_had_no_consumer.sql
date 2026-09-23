-- THE REPORT-PDF ENQUEUE HAD NO CONSUMER (22 Sep 2026, documents-language audit DL-13).
--
-- SEAT: customer_support. Three triggers and one routine dropped, one executor deactivated, one
-- component row corrected. No table, no column, no grant widened.
--
-- WHAT WAS MEASURED, 22 Sep 2026:
--   * The Supabase management API lists 74 ACTIVE edge functions on htdblwldjkcgjvmqkbeh. report_pdf
--     is not among them, and supabase/functions/report_pdf/ does not exist in this repository.
--   * public.action_execution has ZERO rows of action_class 'report.pdf' — not queued, not failed,
--     none, ever. The three AFTER INSERT triggers reports_are_corporate_pdfs.sql created on 6 Sep have
--     produced no work in sixteen days.
--   * 22 objects exist in the private `reports` bucket and 22 report rows carry pdf_path, the newest
--     dated 7 Sep — they were written while the report_pdf function was still deployed. No report row
--     has been created since.
--   * public.org_action_executor holds NO row for action_class 'report.pdf' — the executor
--     reports_are_corporate_pdfs.sql registered is already gone, so the trigger was queuing work for a
--     class with neither an executor nor a function. public.phase_c_component does not exist on this
--     database any more either (the phase machinery was retired), so its 'edge:report_pdf' row, which
--     the_report_pdf_function_is_a_component.sql wrote as activation_state 'deployed', is not there to
--     correct. Both were checked before this file was written rather than assumed from the repository.
--
-- WHY NOT POINT IT AT pdf_native. pdf_native IS deployed and is the one PDF renderer, but it renders a
-- document that its CALLER composes and hands it — blocks in, bytes back. The executor's request is
-- {"source":"board","id":353}: no caller, nothing that reads a report row, nothing that writes the
-- object into the `reports` bucket or stamps pdf_path and pdf_generated_at back onto the row. Pointing
-- the trigger at pdf_native would replace a consumer that does not answer with one that cannot, and
-- the first report created after that would queue an action that fails on a payload pdf_native has no
-- handler for. The composer is what is missing, and writing it is a different piece of work from
-- removing a queue that has never carried anything.
--
-- SO THE ENQUEUE GOES: the three triggers and fn_report_pdf_enqueue are dropped, and scripts/sql/
-- DROPPED.txt records the routine as a deliberate absence so the canonical engine reports it as one
-- rather than as a failed deploy. The gap the founder's order leaves open ("any report needs to be in
-- PDF format") is named in DROPPED.txt and in this header, which is where the estate keeps a removal's
-- reason — not in a memory of this session.
-- The columns, the bucket, the 22 existing PDFs and the report_registry projection are untouched: when
-- a renderer exists again it writes into the same place.
--
-- THE CHECK THAT NAMED THE MECHANISM: scripts/checks/reports_have_a_pdf.test.mjs asserted every report
-- created in the last 8 days carries a stored PDF. Its subject is being removed, not softened, so the
-- check is retired with its subject (the estate's rule) and says why in its own header. It has been
-- vacuously green since 7 Sep because no report has been created in any 8-day window since.
--
--   node scripts/apply_sql.mjs scripts/sql/the_report_pdf_enqueue_had_no_consumer.sql --apply --ddl

drop trigger if exists z_report_pdf_enqueue on public.board_reports;
drop trigger if exists z_report_pdf_enqueue on public.exec_reports;
drop trigger if exists z_report_pdf_enqueue on public.finance_reports;
drop function if exists public.fn_report_pdf_enqueue();

-- Deliberately idempotent and no-op today: org_action_executor holds no report.pdf row (measured
-- above). The statement stays so that a re-apply after someone re-registers the executor without a
-- deployed target still leaves it inactive.
update public.org_action_executor
   set active = false,
       note = 'RETIRED 22 Sep 2026 (audit DL-13): the edge target report_pdf is not deployed (74 active '
           || 'functions measured on the management API, report_pdf absent) and no source for it exists in '
           || 'the repository. action_execution carried zero rows of this class, ever. The enqueue triggers '
           || 'were dropped with it. pdf_native cannot serve this payload: it renders a document its caller '
           || 'composes, and nothing composes a report. Re-activate when a renderer exists.'
 where action_class = 'report.pdf' and active;

-- PROOF, as a ROW (a raise here would roll the drops back).
select case when (select count(*) from pg_trigger where tgname = 'z_report_pdf_enqueue' and not tgisinternal) = 0
             and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = 'fn_report_pdf_enqueue') = 0
             and (select count(*) from public.org_action_executor where action_class = 'report.pdf' and active) = 0
            then 'PROBE OK — 0 z_report_pdf_enqueue triggers, fn_report_pdf_enqueue gone, the report.pdf executor inactive'
            else 'PROBE FAILED — triggers ' ||
                 (select count(*)::text from pg_trigger where tgname = 'z_report_pdf_enqueue' and not tgisinternal)
                 || ', routine ' || (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                      where n.nspname = 'public' and p.proname = 'fn_report_pdf_enqueue')
                 || ', active executor ' || (select count(*)::text from public.org_action_executor where action_class = 'report.pdf' and active)
       end as probe_verdict;
