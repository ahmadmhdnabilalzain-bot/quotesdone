-- THE CEO WRITES AN END-OF-DAY DIGEST, AND NOBODY ELSE MAILS THE FOUNDER.
--
-- The founder, 9 Sep 2026: "I now explicitly request an informational end-of-day company digest
-- from the CEO. Implement it in the existing CEO scheduler and reporting channel; propose 20:00
-- Asia/Dubai as a configurable initial time if no approved schedule exists. Resolve my actual
-- reporting recipient from authorized configuration; do not guess an email. CEO summarizes all
-- currently real agents and writes to the Command Center; it sends email when configured. Sales
-- must not independently email me. No acknowledgment, approval or action by me is required. Use a
-- unique report key per company/local date, revisions for corrections and idempotent sending.
-- Unavailable email delivery must not block business operations; retain the report and retry
-- through the permitted service."
--
-- And, narrowing the older "no unsolicited founder notifications" guidance: "Do not reinstate
-- serious-incident approval/escalation." This file therefore adds ONE informational lane and no
-- alert lane, no approval, no escalation.
--
-- WHAT WAS MEASURED FIRST, 9 Sep 2026 on htdblwldjkcgjvmqkbeh:
--   cron.job                 1 row (wa_flush, active=false). 234 jobs were deleted on the founder's
--                            7 Sep instruction. Registering a pg_cron row would re-open machinery he
--                            removed, and a pg_cron job would not fire anyway.
--   agent_runs               send_outbox 52, login_otp 56, sales_engineer 15 -- send_outbox has run
--                            52 times since the crons died, all of it down the Vercel cron ->
--                            /api/resilience-ping -> resilience_ping path. THAT is the live
--                            scheduler, and that is where this digest hangs.
--   app_secrets              admin_emails present and populated. founder_email also present and read
--                            by NOTHING in the database -- using it would bypass the gate's own
--                            recognition test, so it is not read here either.
--   founder_mail_policy      kind='founder_brief' allowed_to_email=true, owner_role='chief_of_staff'
--                            -- a role that no longer exists. Corrected to 'ceo' below.
--   org_agents               3 active rows: ceo, customer_support, sales_engineer.
--   leads                    22,264 rows, approval_status NULL on ALL 22,264.
--   inquiries/quotes/transactions/inquiry_matches   0 rows each (never held one).
--   customers                1 row.
--   ai_cost_log              8 rows, every one model_used='none', cost_aed=0.
--
-- WHY THE RECIPIENT IS admin_emails AND NOT founder_email. Three live routines --
-- fn_notifications_founder_mail_policy, fn_notify_founder and fn_founder_brief -- all resolve the
-- founder as split_part(admin_emails, ',', 1), and the BEFORE INSERT trigger on notifications
-- recognises a row as founder mail by matching that same value. A digest addressed from any other
-- key would not be recognised as founder mail by the gate that is supposed to govern it.
--
-- WHY A WRAPPER AND NOT A NEW REPORT BODY. fn_founder_brief already computes the figures and
-- already writes the Command Center row. What it lacks is a report key, a revision, idempotency
-- (every call inserted a fresh notification + founder_alerts pair) and three honest lines. It keeps
-- its body; fn_ceo_daily_digest supplies the key, the revision, the once-per-local-day guarantee
-- and the delivery state machine.
--
-- WHY THREE TIMESTAMPS AND NOT ONE status. notifications carries a single conflated status, which
-- cannot distinguish "the report was never written" from "it was written and never sent". The
-- founder asked for exactly that distinction, so generation, submission and delivery are three
-- separate columns. public.support_ceo_report is the pattern being copied, including its
-- UNFILTERED lookup on the unique key -- fn_support_report_to_ceo returns the original row as
-- success on a duplicate.
--
-- THE TRAP THIS FILE DOES NOT FALL INTO. fn_agent_action_work_sweep guards its UNIQUE
-- idempotency_key with `not exists (... and status in ('queued','running','succeeded'))`. A
-- previously FAILED row occupies the key without satisfying the guard, so the routine retries and
-- hits the unique violation; the '#2' suffix in that table is the scar. Here the lookup on
-- report_key is unconditional -- it never filters by status -- and a correction bumps an explicit
-- revision column instead of minting a second key.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE TABLE. One row per company per LOCAL date, forever.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.ceo_daily_digest (
  id                bigserial primary key,
  company_key       text        not null default 'quotesdone',
  local_date        date        not null,
  local_timezone    text        not null default 'Asia/Dubai',
  -- company_key || ':' || local_date. UNIQUE, and looked up unfiltered.
  report_key        text        not null,
  -- Corrections bump this. They never mint a second key.
  revision          int         not null default 1,
  revision_note     text,
  subject           text,
  body              text,
  figures           jsonb       not null default '{}'::jsonb,
  -- generation / submission / delivery are THREE states, not one.
  status            text        not null default 'generated',
  generated_at      timestamptz not null default now(),
  submitted_at      timestamptz,
  delivered_at      timestamptz,
  notification_id   bigint,
  command_center_id uuid,
  delivery_attempts int         not null default 0,
  last_delivery_error text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint ceo_daily_digest_report_key_uniq unique (report_key),
  constraint ceo_daily_digest_status_ck check (status in ('generated','submitted','delivered','delivery_failed'))
);

comment on table public.ceo_daily_digest is
  'The CEO end-of-day informational digest the founder requested on 9 Sep 2026. One row per company per local date (report_key is UNIQUE); corrections bump revision. status/generated_at/submitted_at/delivered_at keep generation, submission and delivery apart so a retained-but-undelivered report is visible as such. Nothing here asks the founder for an approval.';

create index if not exists ceo_daily_digest_local_date_idx on public.ceo_daily_digest (local_date desc);
create index if not exists ceo_daily_digest_undelivered_idx on public.ceo_daily_digest (local_date desc) where delivered_at is null;

alter table public.ceo_daily_digest enable row level security;
-- No policy: the digest is written by SECURITY DEFINER routines and read by the service role only.
-- RLS on with zero policies denies every anon/authenticated read, which is the intent.

-- ---------------------------------------------------------------------------------------------
-- 2. THE STALE POLICY OWNER. founder_mail_policy row for 'founder_brief' names chief_of_staff, a
--    role deleted on 7 Sep. It degrades to ceo through fn_founder_mail_route's fallback, so it was
--    not breaking -- but the row was lying about who owns the lane.
-- ---------------------------------------------------------------------------------------------
update public.founder_mail_policy set owner_role = 'ceo'
 where kind = 'founder_brief' and owner_role = 'chief_of_staff';

-- ---------------------------------------------------------------------------------------------
-- 3. THE CONFIGURABLE TIME. 20:00 Asia/Dubai, proposed because no approved schedule existed.
--    Stored as a local wall-clock time; the UAE has no DST, but the conversion is done by Postgres
--    against the named zone rather than being frozen into a UTC cron string.
-- ---------------------------------------------------------------------------------------------
insert into public.app_secrets(key, value)
values ('ceo_digest_local_time', '20:00')
on conflict (key) do nothing;

commit;

-- ---------------------------------------------------------------------------------------------
-- 4. THE REPORT BODY. fn_founder_brief keeps its figures; five things change.
--
--    (a) THE RECIPIENT IS NO LONGER GUESSED. The old body did
--        coalesce(value,'management@quotesdone.com') -- a hard-coded address that would be used if
--        admin_emails were ever unset or blank. It now resolves to NULL, the notifications insert is
--        skipped, and the Command Center row is still written. An unavailable recipient cannot stop
--        the company reporting to itself.
--
--    (b) SUPPLIER VERIFICATION IS REPORTED AS UNKNOWN, NOT AS ZERO. approval_status is NULL on all
--        22,264 lead rows. The old lines printed "0 pending" and "0 rejected", which reads as a
--        clean verification queue when the truth is that no verification decision has ever been
--        recorded. Zero cannot tell a clean queue from an unused column.
--
--    (c) MATCHING ACCURACY NO LONGER DIVIDES BY greatest(count(*),1). With 0 inquiries that printed
--        "0% of RFQs matched" -- a percentage with no base, which reads as a failing matcher rather
--        than an empty window. It now states the denominator or refuses to state a percentage.
--
--    (d) THE DEAD LINK IS GONE. "Open your dashboard: https://quotesdone.com/os" -- the OS was
--        deleted on 7 Sep 2026.
--
--    (e) THE AGENT ROSTER. The founder asked the CEO to summarise all currently real agents. It
--        reads org_agents (3 active seats) and labels agent_runs for what it is: a log of scheduled
--        JOBS, not of employees, so a seat with no rows under its own key is reported as
--        "no run recorded under its own key" and not as an idle employee.
--
--    create or replace preserves the ACL, so this file does NOT revoke on it.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_founder_brief()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fb$
declare
  v_owner text; v_run bigint;
  v_auto_q int := 0; v_stalled int := 0;
  v_reg int; v_cust int; v_inq7 int; v_q7 int; v_deals int; v_rev numeric;
  v_pend int; v_kyc int; v_refunds int; v_reviews int;
  v_hot int; v_gap int; v_newsup int; v_newcust int;
  v_bd_q int; v_bd_sent int; v_chat_open int; v_viol int;
  v_officer text; v_health jsonb;
  v_topcats text; v_qpr numeric; v_conv numeric;
  v_expired int; v_crit int; v_crit_noise int := 0;
  v_body text; v_subj text; v_org text; v_routed_n int := 0; v_routed_kinds text;
  v_auto_cleared int; v_auto_appr int; v_handled text;
  v_obj_open int := 0; v_obj_await int := 0; v_obj_done24 int := 0; v_task_done24 int := 0; v_obj_line text;
  v_fraud int := 0; v_match_now numeric; v_match_prev numeric;
  v_ai_cost numeric := 0; v_ai_cost_prev numeric := 0; v_ai_delta numeric := 0;
  v_opp text; v_goal numeric; v_goal_j jsonb;
  v_scope_confirmed int; v_scope_total int;
  v_pdf_lines text := '';
  -- 9 Sep 2026 additions.
  v_lead_total int := 0; v_lead_undecided int := 0;   -- unknown vs zero, supplier verification
  v_inq30 int := 0; v_inq30_prev int := 0;            -- the denominator matching accuracy needs
  v_agents int := 0; v_agent_lines text;              -- the roster the founder asked for
  v_jobs text;                                        -- what agent_runs actually logs
begin
  -- THE RECIPIENT IS RESOLVED FROM AUTHORISED CONFIGURATION, OR NOT AT ALL.
  select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
    from app_secrets where key = 'admin_emails';

  insert into agent_runs(agent, started_at) values ('brief', now()) returning id into v_run;

  begin select coalesce(registered_supplier_count(),0) into v_reg; exception when others then v_reg := 0; end;
  select count(*) into v_cust from customers;
  select count(*) into v_inq7 from inquiries where created_at >= now()-interval '7 days';
  select count(*) into v_q7 from quotes where created_at >= now()-interval '7 days';
  select count(*) into v_deals from transactions;
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where coalesce(fee_status,'')<>'refunded' and coalesce(refund_status,'')<>'approved';
  select count(*) into v_pend from agent_actions where status in ('pending','held_for_review','proposed','open','needs_review');
  select count(*) into v_kyc from leads where approval_status='pending';
  select count(*), count(*) filter (where approval_status is null) into v_lead_total, v_lead_undecided from leads;
  select count(*) into v_refunds from transactions where refund_status='requested';
  select count(*) into v_reviews from inbound_messages where needs_review=true;
  select count(distinct i.id) into v_hot from inquiries i join quotes q on q.inquiry_id=i.id left join transactions t on t.inquiry_id=i.id where t.id is null and i.status not in ('completed','accepted','closed','cancelled');
  select count(*) into v_gap from inquiries i where i.status not in ('completed','accepted','closed','cancelled') and not exists (select 1 from inquiry_matches m where m.inquiry_id=i.id);
  select count(*) into v_newsup from leads where registration_submitted_at >= now()-interval '7 days';
  select count(*) into v_newcust from customers where created_at >= now()-interval '7 days';
  select count(*) into v_bd_q from outreach where status='queued';
  select count(*) into v_bd_sent from outreach where status='sent';
  select count(*) into v_chat_open from chat_threads where status='open';
  select count(*) into v_viol from chat_violations where created_at >= now()-interval '7 days';

  begin select public.fn_health_index() into v_health; exception when others then v_health := null; end;

  begin
    select string_agg(cat,', ') into v_topcats from (
      select coalesce(nullif(category,''),'(uncategorized)') cat, count(*) n
      from inquiries where created_at>=now()-interval '7 days'
      group by 1 order by n desc limit 3) z;
  exception when others then v_topcats := null; end;

  begin
    select round(avg(qc),1) into v_qpr from (
      select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id
      where i.created_at>=now()-interval '30 days' group by q.inquiry_id) z;
  exception when others then v_qpr := null; end;
  begin
    select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into v_conv
    from inquiries i left join transactions t on t.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days';
  exception when others then v_conv := null; end;

  begin select count(*) into v_expired from leads where license_expiry is not null and license_expiry < current_date and coalesce(approval_status,'')='approved'; exception when others then v_expired:=0; end;

  -- SEVERITY HAS SEVEN SPELLINGS AND THIS COUNTED ONE (fixed 11 Aug 2026).
  select count(*) into v_crit from founder_alerts
   where public.fn_alert_severe(level)
     and event not ilike 'AI credit low%'
     and created_at >= now() - interval '24 hours';
  select count(*) into v_crit_noise from founder_alerts
   where event ilike 'AI credit low%' and created_at >= now() - interval '24 hours';

  -- OFFICER PRIORITIES ARE GONE. exec_reports holds 325 rows written by a department layer the
  -- founder deleted on 7 Sep 2026 — strategy, operations, procurement_quality, data_science,
  -- product_ux, competitive. Printing them addressed the digest to an organisation that no longer
  -- exists. The org is three agents and no departments; the roster section above is the truth.
  v_officer := null;

  select count(*) into v_auto_cleared from agent_actions
    where decided_by='chief_of_staff (auto)' and decided_at >= now()-interval '24 hours';
  begin
    select count(*) into v_auto_appr from leads
      where approval_decided_by='chief_of_staff (auto)' and approved_at >= now()-interval '24 hours';
  exception when others then v_auto_appr := 0; end;
  begin
    select string_agg('- ['||to_char(created_at,'DD Mon HH24:MI')||'] '||type||': '||
                      coalesce(nullif(subject,''),'(no subject)'), E'\n' order by created_at desc)
      into v_handled
    from (select type, subject, created_at from notifications
          where status='digest' and created_at >= now()-interval '7 days'
          order by created_at desc limit 25) z;
  exception when others then v_handled := null; end;

  begin
    select count(*) into v_obj_open from department_objective where active and status='active';
    select count(*) into v_obj_done24 from department_objective
      where status <> 'active' and updated_at >= now()-interval '24 hours';
    select count(*) into v_task_done24 from org_tasks where status='done' and updated_at >= now()-interval '24 hours';
    select count(*) into v_obj_await from org_tasks t
      where t.status in ('proposed','escalated')
        and exists (select 1 from department_objective o where o.id=t.objective_id and o.active);
    select string_agg(
        '- "'||left(o.objective,80)||'" ('||o.dept_key||') — '||
        (select count(*) from org_tasks t where t.objective_id=o.id and t.status='done')||'/'||
        (select count(*) from org_tasks t where t.objective_id=o.id)||' tasks done'||
        case when (select count(*) from org_tasks t where t.objective_id=o.id and t.status in ('proposed','escalated'))>0
             then ', '||(select count(*) from org_tasks t where t.objective_id=o.id and t.status in ('proposed','escalated'))||' awaiting you'
             else '' end,
        E'\n' order by o.id desc)
      into v_obj_line from department_objective o
      where o.active and exists (select 1 from org_tasks t where t.objective_id=o.id);
  exception when others then v_obj_open:=0; v_obj_await:=0; v_obj_done24:=0; v_task_done24:=0; v_obj_line:=null; end;

  -- THE FOUNDER-QUEUE BLOCK IS GONE, AND NOT BECAUSE IT WAS TIDIED AWAY.
  -- Measured 9 Sep 2026: public.fn_founder_queue does NOT exist in this database, and neither does
  -- public.founder_approval_request. The fn_founder_queue call sat inside an exception block, so it
  -- degraded silently to "0 waiting on you" — a number that reads as an empty queue when the truth
  -- was that nothing was being counted. The founder_approval_request count did NOT sit inside one,
  -- so fn_founder_brief RAISED on every call and could not complete at all.
  -- Both are removed rather than re-guarded: on 8 Sep the founder ruled that every approval is the
  -- CEO's, refunds included, and on 9 Sep that this digest needs no acknowledgment, approval or
  -- action from him. A queue of his decisions is a thing that no longer exists.
  select count(*) into v_auto_q from public.agent_actions a
    join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
   where a.status = 'pending';
  select count(*) into v_stalled from public.agent_actions a
   where a.status in ('held_for_review','proposed','open','needs_review')
     and not exists (select 1 from public.agent_action_kind_policy q
                      where q.kind = a.kind and q.policy = 'founder');

  v_org := '';
  if v_kyc > 0 then v_org := v_org||'- '||v_kyc||' supplier KYC application(s) — supplier_verification (the sweep auto-approves licence-clean ones)'||E'\n'; end if;
  if v_obj_await > 0 then v_org := v_org||'- '||v_obj_await||' objective step(s) in proposed/escalated — their department leads'||E'\n'; end if;
  if v_stalled > 0 then v_org := v_org||'- '||v_stalled||' agent action(s) in needs_review / proposed / open — held with their roles'||E'\n'; end if;
  if v_expired > 0 then v_org := v_org||'- '||v_expired||' supplier(s) with EXPIRED trade licence — supplier_verification / compliance_and_privacy_officer'||E'\n'; end if;
  if v_crit > 0 then v_org := v_org||'- '||v_crit||' severe alert(s) in the last 24h (critical/error/high'||case when v_crit_noise>0 then '; '||v_crit_noise||' AI-credit notice(s) excluded' else '' end||') — each alert''s owning department acts on it'||E'\n'; end if;
  begin
    select count(*), string_agg(distinct coalesce(t.result->'founder_mail'->>'kind','?'), ', ')
      into v_routed_n, v_routed_kinds
      from org_tasks t
     where t.result ? 'founder_mail'
       and (t.status in ('proposed','assigned','in_progress','blocked','escalated')
            or t.updated_at >= now()-interval '24 hours');
  exception when others then v_routed_n := 0; v_routed_kinds := null; end;
  if v_routed_n > 0 then v_org := v_org||'- '||v_routed_n||' engine signal(s) routed to their owning roles instead of your inbox ('||coalesce(v_routed_kinds,'')||') — founder_mail_policy'||E'\n'; end if;
  if v_org = '' then v_org := 'Nothing held.'||E'\n'; end if;

  v_subj := 'QuotesDone company digest — '||to_char(now() at time zone 'Asia/Dubai','Dy DD Mon');

  begin select count(*) into v_fraud from public.leads
     where coalesce(approval_status,'') in ('rejected','banned') or coalesce(banned,false);
  exception when others then v_fraud := 0; end;

  -- MATCHING ACCURACY, WITH ITS DENOMINATOR IN HAND.
  begin
    select count(*) into v_inq30 from public.inquiries where created_at > now() - interval '30 days';
    select count(*) into v_inq30_prev from public.inquiries
     where created_at between now() - interval '60 days' and now() - interval '30 days';
    select round(100.0 * count(*) filter (where exists (select 1 from public.inquiry_matches m where m.inquiry_id = i.id))
                 / nullif(count(*),0))
      into v_match_now from public.inquiries i where i.created_at > now() - interval '30 days';
    select round(100.0 * count(*) filter (where exists (select 1 from public.inquiry_matches m where m.inquiry_id = i.id))
                 / nullif(count(*),0))
      into v_match_prev from public.inquiries i
     where i.created_at between now() - interval '60 days' and now() - interval '30 days';
  exception when others then v_inq30 := 0; v_inq30_prev := 0; v_match_now := null; v_match_prev := null; end;

  begin
    select count(*) filter (where sc.confirmed_at is not null), count(*)
      into v_scope_confirmed, v_scope_total
      from public.supplier_capabilities sc;
  exception when others then v_scope_confirmed := null; v_scope_total := null; end;

  begin
    select round(coalesce(sum(cost_aed),0),2) into v_ai_cost from public.ai_cost_log
      where occurred_at > now() - interval '30 days';
    select round(coalesce(sum(cost_aed),0),2) into v_ai_cost_prev from public.ai_cost_log
      where occurred_at between now() - interval '60 days' and now() - interval '30 days';
    v_ai_delta := v_ai_cost - v_ai_cost_prev;
  exception when others then v_ai_cost := 0; v_ai_cost_prev := 0; v_ai_delta := 0; end;

  begin select o.title into v_opp from public.opportunity o where o.status = 'open'
     order by o.value_score desc nulls last, o.created_at desc limit 1;
  exception when others then v_opp := null; end;

  begin
    v_goal_j := public.fn_goal_attainment('monthly');
    v_goal := (v_goal_j->>'pct')::numeric;
  exception when others then v_goal := null; v_goal_j := null; end;

  -- THE AGENT ROSTER. Every currently real agent, and what is actually logged against it.
  begin
    select count(*) into v_agents from public.org_agents where active;
    select string_agg(
      '- '||a.agent_key||coalesce(' ('||a.title||')','')||
      ' — seated '||to_char(a.hired_at at time zone 'Asia/Dubai','DD Mon')||
      case when a.available then ', available' else ', unavailable' end||
      '; '||coalesce(r.n::text||' run(s) logged under its own key, last '||
                     to_char(r.last_at at time zone 'Asia/Dubai','DD Mon HH24:MI'),
                     'no run logged under its own key'),
      E'\n' order by a.agent_key)
      into v_agent_lines
      from public.org_agents a
      left join (select agent, count(*) n, max(started_at) last_at from public.agent_runs group by agent) r
             on r.agent = a.agent_key
     where a.active;
    select string_agg(agent||' '||n||' (last '||to_char(last_at at time zone 'Asia/Dubai','DD Mon HH24:MI')||')', ', ' order by n desc)
      into v_jobs
      from (select agent, count(*) n, max(started_at) last_at from public.agent_runs
             where started_at >= now() - interval '7 days' group by agent) j;
  exception when others then v_agents := 0; v_agent_lines := null; v_jobs := null; end;

  v_body :=
    'End-of-day company digest. Informational — nothing here needs your acknowledgment, approval or action.'||E'\n\n'||
    'THE AGENTS THAT EXIST TODAY: '||v_agents||E'\n'||
    coalesce(v_agent_lines||E'\n','(no active agent on record)'||E'\n')||
    'agent_runs is a log of scheduled JOBS, not of employees, so a seat with no rows under its own key '||
    'has not been invoked by name — it is not a measure of whether that seat did work.'||E'\n'||
    '- Scheduled job runs (7d): '||coalesce(v_jobs,'none')||E'\n\n'||
    'HANDLED FOR YOU (last 24h): auto-cleared '||v_auto_cleared||' routine item(s)'||
      case when v_auto_appr>0 then ', auto-approved '||v_auto_appr||' licence-clean supplier(s)' else '' end||'.'||
      case when v_handled is not null then E'\n'||v_handled else '' end||E'\n\n'||
    'MARKETPLACE HEALTH: '||coalesce(v_health->>'index','—')||'/100 ('||coalesce(v_health->>'band','no data')||')'||
      case when coalesce(v_health->>'note','')<>'' then '  — '||(v_health->>'note') else '' end||E'\n\n'||
    'OBJECTIVES (what the organization is driving for you)'||E'\n'||
    '- Active objectives: '||v_obj_open||'  ·  tasks completed (24h): '||v_task_done24||'  ·  objectives closed (24h): '||v_obj_done24||E'\n'||
      case when v_obj_line is not null and v_obj_line<>'' then v_obj_line||E'\n' else '' end||E'\n'||
    'OPEN WORK (informational — none of it is yours to action)'||E'\n'||
    '- The machine is working on: '||v_auto_q||' item(s) it will settle itself within the hour'||E'\n'||
    case when v_stalled > 0 then
      '- NOT MOVING: '||v_stalled||' item(s) sit in needs_review / proposed / open. The worker only '||
      'selects status=pending, so nothing is draining these. They are not yours to decide and they '||
      'are not being done either.'||E'\n'
    else '' end||
    '- Refund requests: '||v_refunds||' — the CEO decides these; nothing routes to you'||E'\n'||
    '- Inbound emails to review: '||v_reviews||E'\n'||
    '- Hot leads (quotes in, not revealed): '||v_hot||E'\n'||
    '- Supply gaps (demand, no supplier matched): '||v_gap||E'\n'||
    '- Chat: '||v_chat_open||' open, '||v_viol||' policy flag(s) this week'||E'\n\n'||
    'THIS WEEK'||E'\n'||
    '- New inquiries: '||v_inq7||'  ·  quotes: '||v_q7||E'\n'||
    '- Avg quotes/RFQ (30d): '||coalesce(v_qpr::text,'no RFQ in window')||'  ·  Conversion (30d): '||coalesce(v_conv::text||'%','no RFQ in window')||E'\n'||
    '- New customers: '||v_newcust||'  ·  new supplier registrations: '||v_newsup||E'\n'||
    '- Customers on record (all time): '||v_cust||E'\n'||
    '- Deals (reveals) all-time: '||v_deals||'  ·  revenue recognized: AED '||round(v_rev)||E'\n'||
    '- Top categories (7d): '||coalesce(v_topcats,'none — no RFQ was created')||E'\n\n'||
    'GROWTH'||E'\n'||
    '- Suppliers registered: '||v_reg||'  ·  BD invites queued: '||v_bd_q||'  ·  sent: '||v_bd_sent||E'\n'||
    case when v_officer is not null and v_officer <> '' then E'\n'||'OFFICER PRIORITIES (from weekly analysis)'||E'\n'||v_officer||E'\n' else '' end ||
    E'\n'||'WITH THE ORGANISATION (held by a named role; not yours to approve)'||E'\n'||v_org||
    E'\n'||'QUALITY, COST AND OPPORTUNITY'||E'\n'||
    -- UNKNOWN IS NOT ZERO.
    '- Supplier verification: '||
      case when v_lead_total > 0 and v_lead_undecided = v_lead_total
           then 'UNKNOWN. approval_status is null on all '||v_lead_total||' supplier lead(s), so NO verification '||
                'decision has ever been recorded. This is not "0 pending, 0 rejected" — it is no decision at all.'
           else v_kyc||' pending, '||v_fraud||' rejected or banned, of '||v_lead_total||' lead(s)'||
                case when v_lead_undecided > 0 then ' ('||v_lead_undecided||' carry no decision at all)' else '' end
      end||E'\n'||
    -- A PERCENTAGE WITH ITS BASE, OR NO PERCENTAGE.
    '- Matching accuracy: '||
      case when v_inq30 = 0
           then 'not measurable — 0 RFQ(s) were created in the last 30 days, so there is no denominator'
           else coalesce(v_match_now::text,'—')||'% of '||v_inq30||' RFQ(s) reached at least one supplier (30d); previous 30d '||
                case when v_inq30_prev = 0 then 'no RFQ in window' else coalesce(v_match_prev::text,'—')||'% of '||v_inq30_prev end
      end||E'\n'||
    '- Suppliers an RFQ can reach: '||coalesce(v_scope_confirmed::text,'?')||' of '||coalesce(v_scope_total::text,'?')||' holding capability data have confirmed their own scope'||
      case when coalesce(v_scope_confirmed,0) < 2
           then ' — fn_match_capability gates on that confirmation, so a shortlist cannot exceed '||coalesce(v_scope_confirmed::text,'0')||' whatever a customer asks for'
           else '' end||E'\n'||
    '- AI cost: AED '||coalesce(v_ai_cost::text,'0')||' over 30d, previous 30d AED '||coalesce(v_ai_cost_prev::text,'0')||' ('||case when v_ai_delta >= 0 then '+' else '' end||coalesce(v_ai_delta::text,'0')||')'||E'\n'||
    '- Monthly goal attainment: '||coalesce(v_goal::text,'not measurable')||
      case when v_goal is not null then '% across '||coalesce(v_goal_j->>'goals_measured','?')||' of '||
             coalesce(v_goal_j->>'goals_total','?')||' goals that carry a measured actual for '||
             coalesce(v_goal_j->>'period','this period')||
             ' (the rest have no measure and are NOT counted as met)'
           else ' — no goal has a measured actual for this period' end||E'\n'||
    '- Emerging opportunity: '||coalesce(v_opp,'none detected');
  -- The dashboard link that used to close this body pointed at /os, deleted 7 Sep 2026.

  -- THE PDF LINKS ARE GONE FOR THE SAME REASON AS THE DASHBOARD LINK: every one of them was
  -- https://quotesdone.com/os?report_pdf=board:<id>, and the OS was deleted on 7 Sep 2026. A link
  -- that 404s is worse than no link — it makes the digest look like it is pointing somewhere.
  v_pdf_lines := '';

  -- THE COMMAND CENTER ROW IS WRITTEN WHETHER OR NOT A RECIPIENT EXISTS.
  insert into public.founder_alerts(level, event, detail, channel)
    values ('info', 'CEO end-of-day company digest', v_body, 'os');

  -- THE EMAIL LANE. kind='founder_brief' is registered allowed_to_email=true and is excluded from
  -- the digest-folding regex, so this row passes the founder-mail gate as informational traffic.
  -- With no configured recipient there is simply no row -- and the report above still exists.
  if v_owner is not null then
    insert into notifications(type,to_email,to_role,channel,subject,body)
      values ('founder_brief',v_owner,'admin','email',v_subj,v_body);
  end if;

  update notifications set status='digested'
   where status='digest' and created_at >= now()-interval '7 days' and created_at <= now();

  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('approvals',v_pend,'hot',v_hot,'gaps',v_gap,'bd_queued',v_bd_q,'kyc',v_kyc,'health',(v_health->>'index'),'auto_cleared_24h',v_auto_cleared,'objectives_open',v_obj_open,'agents_active',v_agents,'leads_undecided',v_lead_undecided) where id=v_run;
end;$fb$;

-- ---------------------------------------------------------------------------------------------
-- 5. THE WRAPPER. Report key, revision, idempotency, and the three delivery states.
--
--    Called twice for the same local date it generates ONCE and returns the existing row the second
--    time -- the lookup on report_key is UNFILTERED, so a row in ANY state (including a failed
--    delivery) is found and returned rather than provoking a unique violation.
--
--    p_revise bumps revision and regenerates in place. Corrections never mint a second key.
--
--    A row whose submission did not happen (no recipient, or the gate declined) is left with
--    submitted_at NULL and is RE-ATTEMPTED on the next call. delivery_attempts counts the tries and
--    last_delivery_error carries the reason. Nothing in this routine can stop business operations:
--    every delivery step is inside its own exception block.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_daily_digest(
  p_local_date date default null,
  p_revise boolean default false,
  p_revision_note text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $ceo$
declare
  v_tz         text := 'Asia/Dubai';
  v_company    text := 'quotesdone';
  v_date       date;
  v_key        text;
  v_row        public.ceo_daily_digest%rowtype;
  v_owner_set  boolean;
  v_alert_id   uuid;
  v_notif_id   bigint;
  v_subject    text;
  v_body       text;
  v_figures    jsonb;
begin
  v_date := coalesce(p_local_date, (now() at time zone v_tz)::date);
  v_key  := v_company||':'||to_char(v_date,'YYYY-MM-DD');

  -- UNFILTERED. Never `and status in (...)`.
  select * into v_row from public.ceo_daily_digest where report_key = v_key;

  if found and not p_revise then
    -- Already generated. Retry submission only if it never happened; otherwise return as success.
    if v_row.submitted_at is null then
      v_row := public.fn_ceo_daily_digest_submit(v_row.id);
    end if;
    return jsonb_build_object(
      'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
      'status', v_row.status, 'generated', false, 'reason', 'already generated for this local date',
      'submitted', v_row.submitted_at is not null, 'delivery_attempts', v_row.delivery_attempts);
  end if;

  -- GENERATE. fn_founder_brief writes the Command Center row and, when a recipient is configured,
  -- the notifications row. Both are captured by id here.
  begin
    perform public.fn_founder_brief();
  exception when others then
    -- Generation itself failed. Record the attempt; do not raise into the caller's transaction.
    if v_row.id is not null then
      update public.ceo_daily_digest
         set last_delivery_error = 'generation failed: '||sqlerrm, updated_at = now()
       where id = v_row.id;
    end if;
    return jsonb_build_object('report_key', v_key, 'generated', false, 'error', sqlerrm);
  end;

  select id, detail into v_alert_id, v_body from public.founder_alerts
   where event = 'CEO end-of-day company digest' order by created_at desc limit 1;
  select id, subject into v_notif_id, v_subject from public.notifications
   where type = 'founder_brief' order by created_at desc, id desc limit 1;
  -- A notification older than this call is not ours.
  if v_notif_id is not null and not exists (
       select 1 from public.notifications where id = v_notif_id and created_at >= now() - interval '2 minutes')
  then v_notif_id := null; v_subject := null; end if;

  select coalesce(nullif(btrim(split_part(coalesce(value,''), ',', 1)), ''), '') <> ''
    into v_owner_set from public.app_secrets where key = 'admin_emails';
  v_owner_set := coalesce(v_owner_set, false);

  v_figures := jsonb_build_object(
    'agents_active',      (select count(*) from public.org_agents where active),
    'customers',          (select count(*) from public.customers),
    'inquiries',          (select count(*) from public.inquiries),
    'quotes',             (select count(*) from public.quotes),
    'transactions',       (select count(*) from public.transactions),
    'inquiry_matches',    (select count(*) from public.inquiry_matches),
    'leads_total',        (select count(*) from public.leads),
    'leads_undecided',    (select count(*) from public.leads where approval_status is null),
    'ai_cost_rows',       (select count(*) from public.ai_cost_log),
    'ai_cost_aed',        (select coalesce(sum(cost_aed),0) from public.ai_cost_log),
    'recipient_configured', v_owner_set);

  if p_revise and v_row.id is not null then
    update public.ceo_daily_digest
       set revision = revision + 1, revision_note = p_revision_note,
           subject = coalesce(v_subject, subject), body = coalesce(v_body, body),
           figures = v_figures, command_center_id = v_alert_id,
           notification_id = coalesce(v_notif_id, notification_id),
           status = case when v_notif_id is not null then 'submitted' else 'generated' end,
           generated_at = now(),
           submitted_at = case when v_notif_id is not null then now() else submitted_at end,
           delivery_attempts = delivery_attempts + 1,
           last_delivery_error = case when v_notif_id is not null then null
                                      when v_owner_set then 'the founder-mail gate did not accept the row'
                                      else 'no recipient configured in app_secrets.admin_emails' end,
           updated_at = now()
     where id = v_row.id
    returning * into v_row;
  else
    insert into public.ceo_daily_digest(
      company_key, local_date, local_timezone, report_key, revision, revision_note,
      subject, body, figures, status, command_center_id, notification_id,
      submitted_at, delivery_attempts, last_delivery_error)
    values (
      v_company, v_date, v_tz, v_key, 1, p_revision_note,
      v_subject, v_body, v_figures,
      case when v_notif_id is not null then 'submitted' else 'generated' end,
      v_alert_id, v_notif_id,
      case when v_notif_id is not null then now() else null end,
      1,
      case when v_notif_id is not null then null
           when v_owner_set then 'the founder-mail gate did not accept the row'
           else 'no recipient configured in app_secrets.admin_emails' end)
    returning * into v_row;
  end if;

  return jsonb_build_object(
    'report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status, 'generated', true,
    'submitted', v_row.submitted_at is not null,
    'delivery_attempts', v_row.delivery_attempts,
    'recipient_configured', v_owner_set);
end;$ceo$;

revoke execute on function public.fn_ceo_daily_digest(date, boolean, text) from public;

comment on function public.fn_ceo_daily_digest(date, boolean, text) is
  'Generates the CEO end-of-day digest for one LOCAL date, once. Idempotent: the lookup on the unique report_key is unfiltered, so a second call returns the existing row rather than inserting a duplicate. p_revise bumps revision in place for a correction. Delivery is best effort and never raises into the caller.';

-- ---------------------------------------------------------------------------------------------
-- 6. THE RETRY. Re-attempts submission for a retained report whose email never went out.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_daily_digest_submit(p_id bigint)
returns public.ceo_daily_digest
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $sub$
declare
  v_row public.ceo_daily_digest%rowtype;
  v_owner text;
  v_notif_id bigint;
begin
  select * into v_row from public.ceo_daily_digest where id = p_id;
  if not found or v_row.submitted_at is not null then return v_row; end if;

  select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
    from public.app_secrets where key = 'admin_emails';

  if v_owner is null then
    update public.ceo_daily_digest
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'no recipient configured in app_secrets.admin_emails',
           updated_at = now()
     where id = p_id returning * into v_row;
    return v_row;
  end if;

  begin
    insert into public.notifications(type,to_email,to_role,channel,subject,body)
      values ('founder_brief', v_owner, 'admin', 'email',
              coalesce(v_row.subject,'QuotesDone company digest — '||to_char(v_row.local_date,'Dy DD Mon')),
              coalesce(v_row.body,''))
    returning id into v_notif_id;
  exception when others then
    update public.ceo_daily_digest
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'submission raised: '||sqlerrm, updated_at = now()
     where id = p_id returning * into v_row;
    return v_row;
  end;

  update public.ceo_daily_digest
     set notification_id = v_notif_id,
         submitted_at = case when v_notif_id is not null then now() else null end,
         status = case when v_notif_id is not null then 'submitted' else status end,
         delivery_attempts = delivery_attempts + 1,
         last_delivery_error = case when v_notif_id is not null then null
                                    else 'the founder-mail gate did not accept the row' end,
         updated_at = now()
   where id = p_id returning * into v_row;
  return v_row;
end;$sub$;

revoke execute on function public.fn_ceo_daily_digest_submit(bigint) from public;

-- ---------------------------------------------------------------------------------------------
-- 7. THE TICK. What the LIVE scheduler calls every 15 minutes.
--
--    NOT pg_cron. cron.job holds one inactive row; 234 jobs were deleted on the founder's 7 Sep
--    instruction and 110 cron.schedule statements were stripped from the repository so re-applying
--    a file cannot resurrect one. A pg_cron job registered here would not fire, and reactivating
--    pg_cron to make it fire would restart machinery he deleted.
--
--    The timezone arithmetic lives HERE and not in the edge function, because Postgres knows what
--    Asia/Dubai means and a cron string does not. The configured time is a local wall clock.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_daily_digest_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $tick$
declare
  v_tz    text := 'Asia/Dubai';
  v_local timestamp;
  v_at    time;
  v_date  date;
  v_key   text;
  v_row   public.ceo_daily_digest%rowtype;
begin
  v_local := now() at time zone v_tz;
  v_date  := v_local::date;
  v_key   := 'quotesdone:'||to_char(v_date,'YYYY-MM-DD');

  begin
    select coalesce(nullif(btrim(value),''),'20:00')::time into v_at
      from public.app_secrets where key = 'ceo_digest_local_time';
  exception when others then v_at := time '20:00'; end;
  v_at := coalesce(v_at, time '20:00');

  select * into v_row from public.ceo_daily_digest where report_key = v_key;

  if v_local::time < v_at then
    return jsonb_build_object('fired', false, 'reason', 'before the configured local time',
                              'local_now', to_char(v_local,'YYYY-MM-DD HH24:MI'), 'configured_at', v_at::text,
                              'report_key', v_key, 'exists', found);
  end if;

  -- Past the configured time. Generate if it does not exist; retry submission if it does and the
  -- email never went out. Both paths are idempotent.
  return public.fn_ceo_daily_digest(v_date) || jsonb_build_object('fired', true, 'configured_at', v_at::text);
end;$tick$;

revoke execute on function public.fn_ceo_daily_digest_tick() from public;

comment on function public.fn_ceo_daily_digest_tick() is
  'The once-per-local-day trigger for the CEO end-of-day digest, called by resilience_ping on the LIVE (Vercel cron) scheduler every 15 minutes. Fires at or after app_secrets.ceo_digest_local_time in Asia/Dubai and is idempotent within the local day. Not a pg_cron job: cron.job was emptied on the founder''s 7 Sep 2026 instruction and would not fire.';
