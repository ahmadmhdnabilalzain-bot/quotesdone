-- THE FOUNDER BRIEF COUNTS THE IT ENGINEER'S PROBLEMS, NOT HIS ALERTS.
--
-- Seat: it_engineer. 10 Nov 2026. Item 7 of the daily brief ("the plan for tomorrow") said
-- "The IT engineer works on N open technical problem(s)" with N = one per open alert row, and the founder
-- read N as that many bugs.
--
-- MEASURED (read-only SELECTs on production htdblwldjkcgjvmqkbeh, 10 Nov 2026):
--   N in the brief, from notifications kind founder_brief: 1 Oct 60, 25 Oct 626, 2 Nov 833, 9 Nov 277.
--   N was count(*) of fn_it_open_findings(): every unclosed it_engineer_finding row not classed 'warn'.
--   One fault is many rows: duty:delivery opened 2,773 rows on 2-4 Nov for one queue-and-delete burst (one row
--   per delivery handoff); duty:credential_rotation_age holds 43 rows for one batch of credentials created
--   together on 3 Aug; duty:workflow_audit 67 rows from 3 rules; duty:journey 19 rows from one nightly run.
--   Today: 266 open rows (the old N) = 51 distinct checks (the new N). On 2 Nov 13:00 UTC: about 853 unclosed
--   rows = 39 checks.
--
-- THE GROUPING KEY, and why it is this one. it_engineer_finding has no detector column. Its issue_key is
-- written by every detector as <source>:<check>:<instance> (duty:delivery:request:348639,
-- acct:reveal_reconcile:test_mode_not_demo:pi_..., sales_engineer:cad_read_held:2026-10-27T07), so ONE
-- problem = the first two parts of the key (or the whole key when it has one part: delivery_outcome_unreturned).
-- Measured against the two other candidates on today's open rows:
--   raised_by   merges different checks: 'customer_support' raises 6 unrelated ones (support_reply_sla:*,
--               delivery_outcome_unreturned, reasoned_answer_held_for_review), 'it_engineer' raises
--               knowledge_refresh, deliverability:inbox_placement and the GitHub token check.
--   where_it_is splits one check by place: support_reply_sla per channel, facts:surface_stale per page.
-- The key still splits one cause in two places, and this file says so rather than hide it:
-- knowledge_refresh:<seat> is 6 problems (one per seat) and support_reply_sla:<channel> is 3.
--
-- "NEEDS YOU". The data model marks what only the founder can decide in public.it_founder_decision_class
-- (to_founder + founder_category), read by fn_customer_support_sends_the_it_digest, which emails him at 19:00
-- only "things only you can decide". fn_it_open_problems applies the digest's rule in the digest's order:
--   a credential only he can renew is never his line (ruling 1090, fn_it_credential_founder_required);
--   a failing integration marked notify=false is the IT engineer's (5 Oct 2026);
--   otherwise the most specific matching class decides, a to_founder=false class wins, and a to_founder class
--   counts only with one of his three categories: money, destructive_production_change, fact_only_he_holds
--   (ruling 1254, 19 Oct 2026).
-- Measured today: 0 of 51 problems need him, the same answer the 9 Nov IT digest gave ("nothing needs the
-- founder"). NOT used: the handoff stamp digest='sent'. 31 open findings carry it, all stamped 16 Sep-7 Oct
-- under rules since superseded, and none matches a to_founder class today; it would have told him 17 problems
-- need him.
--
-- WHAT CHANGES
--   fn_it_open_problems()          NEW. One row per open problem: its key, how many alerts, whether it needs the
--                                  founder, the plain title of its oldest founder alert, when it started.
--                                  Reads fn_it_open_findings(), so "open" keeps ONE definition.
--   fn_founder_brief_figures(...)  the IT line of item 7 only, now:
--                                  "The IT engineer is working on 51 technical problems, raised as 266 separate
--                                   alerts. None of them needs you."
--                                  and, on a day one does: "... 2 of them need you: <title>; <title>."
--                                  (at most 3 named, then "and N more"). Every other line is byte-for-byte the
--                                  live definition (pg_get_functiondef, md5 91a4b6b3e832cb3e504840413dd63144,
--                                  equal to the_founder_brief_says_seven_things_in_plain_words.sql).
--
-- NOT CHANGED: fn_it_open_findings (what is open), the IT loop and its digest (fn_it_loop_tick,
-- fn_customer_support_sends_the_it_digest keeps its own copy of the founder rule; the check below pins the
-- two to the same categories and exemptions), the detectors that open one row per instance (duty:delivery,
-- duty:credential_rotation_age: their own fixes, see the 10 Nov triage), the brief's other items.
-- NOT APPLIED before merge (apply at merge, never before): replayed on the local schema copy (npm run db:local),
-- PROBE OK there, and the new IT line rendered on production by a plain read-only SELECT of the same query.
--
-- THE PROBE is read-only and returns its verdict as a row (the file holds DDL, so it must not raise). It writes
-- nothing and sends nothing: it reads the open findings, checks that every open alert sits in exactly one
-- problem, and that the brief's IT line carries the problem count and the alert count.
--
-- Prevented by: scripts/checks/the_founder_brief_counts_it_problems_not_alerts.test.mjs

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. ONE ROW PER PROBLEM.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_it_open_problems()
returns table (problem text, alerts integer, needs_founder boolean, founder_title text, started_at timestamptz)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with o as (
    select f.issue_key, f.title, f.started_at,
           coalesce(substring(f.issue_key from '^[^:]+(?::[^:]+)?'), f.issue_key) as problem,
           -- The IT digest's rule, in its order (fn_customer_support_sends_the_it_digest).
           (    not public.fn_it_credential_founder_required(f.issue_key, f.title, f.evidence)
            and not (f.issue_key like 'duty:integration:%' and f.evidence->>'notify' is distinct from 'true')
            and coalesce((select c.to_founder and c.founder_category in ('money', 'destructive_production_change', 'fact_only_he_holds')
                            from public.it_founder_decision_class c
                           where f.issue_key like c.issue_key_like
                           order by c.to_founder, length(c.issue_key_like) desc limit 1), false)) as his
      from public.fn_it_open_findings() f)
  select o.problem, count(*)::int, bool_or(o.his),
         (array_agg(public.fn_trim_at_word(regexp_replace(o.title, '[.\s]+$', ''), 120) order by o.started_at, o.issue_key)
            filter (where o.his))[1],
         min(o.started_at)
    from o
   group by o.problem
$fn$;
revoke execute on function public.fn_it_open_problems() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 2. THE BRIEF. The live definition, with the IT line of item 7 changed and nothing else.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_founder_brief_figures(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_inv jsonb; v_sup jsonb; v_inq jsonb; v_cus jsonb; v_cmp jsonb; v_rev jsonb; v_plan jsonb;
  v_on boolean; v_cap int;
begin
  -- COUNTS BEGIN
  -- 1. Invitations: an outbox row the provider accepted (provider_message_id) in the window.
  with d as (
    select l.company_name,
           (coalesce(l.is_demo,false) or l.company_name ilike 'ZZ DEMO%' or n.to_email ilike '%@example.invalid'
            or coalesce(l.email,'') ilike '%@example.invalid') as demo
      from public.notifications n left join public.leads l on l.id = n.lead_id
     where n.type = 'supplier_invite' and n.provider_message_id is not null
       and n.sent_at >= p_from and n.sent_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo),
           'names', coalesce(jsonb_agg(coalesce(company_name,'(no company name)') order by company_name) filter (where not demo), '[]'),
           'demo_excluded', count(*) filter (where demo)) into v_inv from d;

  -- 2. Suppliers registered: the registration form was submitted in the window.
  with d as (
    select company_name,
           (coalesce(is_demo,false) or company_name ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid') as demo
      from public.leads where registration_submitted_at >= p_from and registration_submitted_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo),
           'names', coalesce(jsonb_agg(coalesce(company_name,'(no company name)') order by company_name) filter (where not demo), '[]'),
           'demo_excluded', count(*) filter (where demo)) into v_sup from d;

  -- 3. Inquiries received: a customer request created in the window. Split children
  --    (parent_inquiry_id) are one request, not several.
  with d as (
    select (c.id is null or coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid'
            or coalesce(i.provenance->>'source','') in ('demo_factory','e2e')) as demo
      from public.inquiries i left join public.customers c on c.id = i.customer_id
     where i.parent_inquiry_id is null and i.created_at >= p_from and i.created_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo), 'demo_excluded', count(*) filter (where demo))
    into v_inq from d;

  -- 4. Customers registered: the account was created in the window. Names and mobiles go to the PDF.
  with d as (
    select c.full_name, coalesce(nullif(c.phone,''), nullif(c.whatsapp_phone,'')) as mobile, c.created_at,
           (coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid'
            or coalesce(c.phone,'') like '+9715000000%') as demo
      from public.customers c where c.created_at >= p_from and c.created_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo),
           'list', coalesce(jsonb_agg(jsonb_build_object('name', coalesce(nullif(btrim(full_name),''),'(no name given)'),
                                                         'mobile', coalesce(mobile,'(no mobile given)'),
                                                         'at', to_char(created_at at time zone 'Asia/Dubai','FMHH12:MI am'))
                                      order by created_at) filter (where not demo), '[]'),
           'demo_excluded', count(*) filter (where demo)) into v_cus from d;

  -- 5. Comparison reports generated: a quote_comparisons row created in the window.
  with d as (
    select (c.id is null or coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid') as demo
      from public.quote_comparisons q
      left join public.inquiries i on i.id = q.inquiry_id
      left join public.customers c on c.id = coalesce(q.customer_id, i.customer_id)
     where q.created_at >= p_from and q.created_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo), 'demo_excluded', count(*) filter (where demo))
    into v_cmp from d;

  -- 6. Reveal fees paid: a transaction carrying Stripe's own payment id, revealed in the window.
  --    The payment id is written only after Stripe confirms the charge.
  with d as (
    select coalesce(t.reveal_fee, t.app_fee, 0) as fee,
           (c.id is null or coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid') as demo
      from public.transactions t left join public.customers c on c.id = t.customer_id
     where t.payment_ref ~ '^(pi|ch|py)_' and t.revealed_at >= p_from and t.revealed_at < p_to)
  select jsonb_build_object('count', count(*) filter (where not demo),
           'aed', coalesce(sum(fee) filter (where not demo), 0),
           'demo_excluded', count(*) filter (where demo)) into v_rev from d;
  -- COUNTS END

  -- 7. THE PLAN FOR TOMORROW. Read from the seats' configuration and open work; 3-5 lines.
  select coalesce(max(value) filter (where key='invite_enabled'),'') = 'true'
     and coalesce(max(value) filter (where key='supplier_outreach_golive'),'') = 'true',
         coalesce(nullif(max(value) filter (where key='invite_daily_cap'),'')::int, 0)
    into v_on, v_cap from public.app_secrets where key in ('invite_enabled','supplier_outreach_golive','invite_daily_cap');

  -- 22 Sep 2026 (ceo, instructions 636/639): the campaign gate is the founder's reserved decision and he
  -- is never reminded of it. While it is closed the brief says nothing about invitations at all.
  v_plan := case when v_on then jsonb_build_array('The sales engineer sends up to '||v_cap||' supplier invitations.')
                 else '[]'::jsonb end;

  v_plan := v_plan || (
    select jsonb_build_array(case when count(*) = 0 then 'No customer request is waiting for a quote.'
                else 'Customer support follows up '||count(*)||' customer request(s) that have no quote yet.' end)
      from public.inquiries i join public.customers c on c.id = i.customer_id
     where i.parent_inquiry_id is null and i.completed_at is null
       and not (coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%' or coalesce(c.email,'') ilike '%@example.invalid')
       and not exists (select 1 from public.quotes q where q.inquiry_id = i.id));

  v_plan := v_plan || (
    select jsonb_build_array(case when count(*) = 0 then 'No supplier registration is waiting for verification.'
                else 'The CEO reviews '||count(*)||' supplier registration(s) waiting for verification.' end)
      from public.leads
     where registration_submitted_at is not null and approved_at is null and rejection_reason is null
       and not (coalesce(is_demo,false) or company_name ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid'));

  v_plan := v_plan || (
    select case when count(*) = 0 then '[]'::jsonb
                else jsonb_build_array('The CEO decides '||count(*)||' refund request(s).') end
      from public.transactions t join public.customers c on c.id = t.customer_id
     where t.refund_requested_at is not null and t.refund_resolved_at is null
       and not (coalesce(c.is_demo,false) or c.full_name ilike 'ZZ DEMO%'));

  v_plan := v_plan || (
    -- PROBLEMS, NOT ALERTS (10 Nov 2026, it_engineer). This line counted one per open alert row, and the founder read
    -- "works on 833 open technical problem(s)" (2 Nov) as 833 bugs. One fault opens many rows: duty:delivery opened
    -- 2,773 for one burst on 2-4 Nov, duty:credential_rotation_age 43 for one batch of credentials. MEASURED today:
    -- 266 open rows = 51 problems, 0 of which need him. fn_it_open_problems groups fn_it_open_findings() (still the ONE
    -- definition of open) by the first two parts of the issue key, and marks a problem as his by the IT digest's rule.
    with p as (select * from public.fn_it_open_problems()),
         s as (select count(*)::int as n, coalesce(sum(p.alerts), 0)::int as a,
                      count(*) filter (where p.needs_founder)::int as k,
                      array_agg(p.founder_title order by p.started_at, p.problem) filter (where p.needs_founder) as t
                 from p)
    select jsonb_build_array(case
      when s.n = 0 then 'The IT engineer has no open technical problems.'
      else 'The IT engineer is working on ' || s.n
           || case when s.n = 1 then ' technical problem' else ' technical problems' end
           || ', raised as ' || s.a || case when s.a = 1 then ' alert. ' else ' separate alerts. ' end
           || case when s.k = 0 then case when s.n = 1 then 'It does not need you.' else 'None of them needs you.' end
                   else case when s.n = 1 then 'It needs you: '
                             when s.k = 1 then '1 of them needs you: '
                             else s.k || ' of them need you: ' end
                        || array_to_string(s.t[1:3], '; ')
                        || case when s.k > 3 then '; and ' || (s.k - 3) || ' more' else '' end || '.'
              end
      end)
      from s);

  -- 22 Sep 2026 (ceo, instruction 638): the CEO's own plan leads item 7 -- the binding constraint, the
  -- directive each seat is working to, and the one decision only the founder can take, if any. This is
  -- the ONLY way the daily plan reaches him: no separate email. Defined in
  -- the_ceo_plans_every_day_and_directs_the_seats.sql, which must be applied before this file.
  v_plan := public.fn_ceo_plan_brief_lines() || v_plan;

  return jsonb_build_object(
    'window_from', p_from, 'window_to', p_to,
    'local_date', (p_to at time zone 'Asia/Dubai')::date,
    'invitations', v_inv, 'suppliers_registered', v_sup, 'inquiries', v_inq,
    'customers', v_cus, 'comparisons', v_cmp, 'reveal_fees', v_rev, 'plan', v_plan);
end;
$fn$;
revoke execute on function public.fn_founder_brief_figures(timestamptz, timestamptz) from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- 3. PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise). It writes nothing,
--    sends nothing and reads only the open findings and the brief's figures for the last minute (all STABLE).
-- ---------------------------------------------------------------------------------------------
with f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname in ('fn_it_open_problems', 'fn_founder_brief_figures') and p.prosecdef
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')),
     ex as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and p.proname in ('fn_it_open_problems', 'fn_founder_brief_figures')
               and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
     rows_open as (select count(*)::int n from public.fn_it_open_findings()),
     prob as (select count(*)::int n, coalesce(sum(alerts), 0)::int a, count(distinct problem)::int d,
                     count(*) filter (where needs_founder)::int k,
                     count(*) filter (where needs_founder and founder_title is null)::int k_untitled
                from public.fn_it_open_problems()),
     line as (select x as l from jsonb_array_elements_text(
                (public.fn_founder_brief_figures(now() - interval '1 minute', now()))->'plan') x
               where x like 'The IT engineer %')
select case
  when (select n from f) <> 2 then 'PROBE FAILED: fn_it_open_problems / fn_founder_brief_figures missing, not security definer, or no pinned search_path'
  when (select n from ex) <> 0 then 'PROBE FAILED: anon or authenticated can execute fn_it_open_problems or fn_founder_brief_figures'
  when (select a from prob) <> (select n from rows_open)
    then 'PROBE FAILED: the problems hold ' || (select a from prob) || ' alerts but ' || (select n from rows_open) || ' are open'
  when (select d from prob) <> (select n from prob) then 'PROBE FAILED: a problem key appears on two rows'
  when (select n from prob) > (select n from rows_open) then 'PROBE FAILED: more problems than open alerts'
  when (select k_untitled from prob) <> 0 then 'PROBE FAILED: a problem that needs the founder has no title to name it by'
  when (select count(*) from line) <> 1 then 'PROBE FAILED: item 7 has ' || (select count(*) from line) || ' IT engineer lines, not 1'
  when (select n from prob) = 0 and (select l from line) <> 'The IT engineer has no open technical problems.'
    then 'PROBE FAILED: nothing is open but the line reads: ' || (select l from line)
  when (select n from prob) > 0 and position('working on ' || (select n from prob) || ' technical problem' in (select l from line)) = 0
    then 'PROBE FAILED: the line does not carry the problem count ' || (select n from prob) || ': ' || (select l from line)
  when (select n from prob) > 0 and position('raised as ' || (select a from prob) || ' ' in (select l from line)) = 0
    then 'PROBE FAILED: the line does not carry the alert count ' || (select a from prob) || ': ' || (select l from line)
  when (select n from prob) > 0 and ((select k from prob) = 0) <> ((select l from line) ~ '(None of them needs you|It does not need you)\.$')
    then 'PROBE FAILED: the needs-you part disagrees with ' || (select k from prob) || ' founder problem(s): ' || (select l from line)
  else 'PROBE OK: ' || (select n from rows_open) || ' open alerts = ' || (select n from prob) || ' problems, '
       || (select k from prob) || ' need the founder; brief line: ' || (select l from line)
end as verdict;

commit;
