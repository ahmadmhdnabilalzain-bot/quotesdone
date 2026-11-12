-- THE AUDIT RUNS OF 11 NOVEMBER LEAVE NO DEMO SUPPORT CASE (it_engineer, 12 Nov 2026). Data only, applied once.
-- Assigned: it_engineer (harness teardown). Founder ledger 1642; final audit H6 / whatsapp F11 (fix O4).
-- Apply AFTER a_demo_support_case_is_removed_with_its_history_and_a_real_one_never_is.sql (it uses that routine).
--
-- MEASURED (production, read-only, 12 Nov 2026 01:20Z): left by audit runs 71366940 and d9a04dbc because the teardown
-- could not pass the append-only summary history:
--   case 2221 (QD-S-QHDQW6, closed) on profile 1034, versions 10 and 11;
--   case 2235 (open) on profile 1036 qd-d9a04dbc-sup4@example.invalid, version 12;
--   case 2236 (open) on profile 1037 qd-d9a04dbc-sup10@example.invalid, version 13; 0 promises.
-- Profile 1034 is the audit's own holder ("ZZ DEMO audit 71366940 leftover: case QD-S-QHDQW6 kept ...", created
-- 11 Nov 23:13Z) and was made with no address, so the demo test cannot see it or its case. It is given the fixture
-- convention's reserved address first (demo-fixture-convention: qd-<tag>-...@example.invalid), which is what it
-- would have carried; nothing else about it changes, and the update is held to that one row by id, null email and name.
--   node scripts/apply_sql.mjs scripts/sql/the_audit_runs_of_11_november_leave_no_demo_support_case.sql --apply

update public.support_customer_profile set email = 'qd-71366940-leftover@example.invalid'
 where id = 1034 and email is null
   and display_name = 'ZZ DEMO audit 71366940 leftover: case QD-S-QHDQW6 kept for its append-only summary versions';

select public.fn_demo_support_case_purge(array[2221, 2235, 2236]::bigint[]);

delete from public.seat_case_memory where source_table = 'support_case' and source_id in ('2221', '2235', '2236');
delete from public.feedback f where f.profile_id in (1034, 1036, 1037)
   and exists (select 1 from public.support_customer_profile p where p.id = f.profile_id and public.fn_is_demo_email(p.email));
delete from public.support_customer_profile p
 where p.id in (1034, 1036, 1037) and public.fn_is_demo_email(p.email)
   and not exists (select 1 from public.support_case c where c.customer_profile_id = p.id);

-- VERDICT (a row; the file writes, so it must not raise)
select case when (select count(*) from public.support_case where case_id in (2221, 2235, 2236)) = 0
             and (select count(*) from public.support_case_summary_version where case_id in (2221, 2235, 2236)) = 0
             and (select count(*) from public.support_customer_profile where id in (1034, 1036, 1037)) = 0
            then 'PROBE OK'
            else 'PROBE FAILED: cases ' || (select count(*) from public.support_case where case_id in (2221, 2235, 2236))
                 || ', versions ' || (select count(*) from public.support_case_summary_version where case_id in (2221, 2235, 2236))
                 || ', profiles ' || (select count(*) from public.support_customer_profile where id in (1034, 1036, 1037)) || ' remain' end as verdict;
