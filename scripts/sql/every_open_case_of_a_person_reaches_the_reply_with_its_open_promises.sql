-- EVERY OPEN CASE OF A PERSON REACHES THE REPLY WITH ITS OPEN PROMISES (it_engineer, 16 Nov 2026).
-- Assigned: it_engineer (the case read every customer-facing door makes). Founder ledgers 1711-1713: colleagues know what each
-- other know; ruling 1635: every conversation is a case and the reply works from what it recorded.
--
-- MEASURED (production, read-only SELECTs, 16 Nov 2026; audit WHO_KNOWS_WHAT item 2):
--   * support_case: 30 rows, 0 with a summary; support_case_promise: 0 rows. Of the 30, 16 pass fn_support_case_is_demo
--     (15 reserved fixture numbers, 1 reserved address). Of the 14 real cases, 5 ever had a reply, the newest on 10 Nov 23:25 UTC,
--     before the summary writer shipped (11 Nov). Since 11 Nov: 0 wa_turn rows, 0 mails replied (all 10 classified
--     no_auto_reply), 1,971 widget turns all anonymous (no identity, no case by design), 0 portal or quotation-chat turns.
--   * Every case_summary model call ever (29, 11-12 Nov) carries an e2e run tag; the summary-version and promise sequences
--     stand at 91 and 23: those rows were audit-run demo cases, removed with their history by fn_demo_support_case_purge
--     (ledger 1642). The one support_case:summary_not_written finding was such a run (12 Nov 05:42, reason 'not json') and is
--     closed (12 Nov 06:06).
--   So the record is empty because no identified person has been answered on any case door since the writer shipped, not
--   because the writer fails. What this file fixes is what the record could not carry once it fills.
--
-- CHANGE: fn_support_open_cases returns, on each open case, its OPEN promise-ledger rows (what, due_text, due_at, owner_seat;
-- at most 5 a case, soonest due first). support_case_memory.ts readCase then hands EVERY open case's line and open promises to
-- the reply (allOpen), also when the person has several recorded matters and names none (before: no case at all, so the
-- promise was lost to every reply). Before this file is applied the code reads the promises from each summary's WE PROMISED
-- lines instead, so either order of deploy and apply is safe.
-- Same signature, CREATE OR REPLACE (keeps the ACL); revoked and granted again anyway. search_path pinned.
-- Prevented by: every_open_case_of_a_person_reaches_the_reply_with_its_open_promises_probe.sql (rolled back, local first) and
-- supabase/functions/_shared/support_case_memory.test.ts.
--   node scripts/apply_sql.mjs scripts/sql/every_open_case_of_a_person_reaches_the_reply_with_its_open_promises.sql --apply --ddl

create or replace function public.fn_support_open_cases(p_party_kind text, p_party_id text, p_email text, p_phone text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_prof bigint;
begin
  v_prof := public.fn_support_profile_resolve(case when p_party_kind in ('customer', 'supplier') then p_party_kind else 'unknown' end,
                                              p_party_id, p_email, p_phone);
  if v_prof is null then return jsonb_build_object('profile', null, 'cases', '[]'::jsonb); end if;
  return jsonb_build_object('profile', v_prof, 'cases', coalesce((
    select jsonb_agg(jsonb_build_object('case_ref', x.case_ref, 'title', coalesce(x.title, left(x.subject, 160)),
                                        'summary_text', x.summary_text, 'summary_version', x.summary_version,
                                        'status', x.status_plain, 'channels', x.channels, 'last_activity_at', x.last_activity_at,
                                        'prior_activity_at', x.prior_activity_at,
                                        -- the promises still open on this case (16 Nov 2026): every reply keeps them, whichever case it works from
                                        'promises', coalesce((
                                          select jsonb_agg(jsonb_build_object('what', pr.what, 'due_text', pr.due_text, 'due_at', pr.due_at,
                                                                              'owner_seat', pr.owner_seat) order by pr.due_at nulls last, pr.id)
                                            from (select * from public.support_case_promise
                                                   where case_id = x.case_id and status = 'open'
                                                   order by due_at nulls last, id limit 5) pr), '[]'::jsonb))
                     order by x.last_activity_at desc)
      from (select * from public.support_case where customer_profile_id = v_prof and state <> 'closed'
             order by last_activity_at desc limit 5) x), '[]'::jsonb));
end $function$;

revoke execute on function public.fn_support_open_cases(text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_support_open_cases(text, text, text, text) to service_role;
