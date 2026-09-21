-- THE FOUNDER BRIEF SAYS SEVEN THINGS, IN PLAIN WORDS.            seat: ceo · 21 Sep 2026 · instruction 587
--
-- The founder, 21 Sep 2026: "the daily brief i receive daily is completely useless in the format its
-- shared. it should be in plain language with useful information for me as a founder ... 1- how many
-- invitation sent for the day for suppliers and who are they (names) 2- how many supplier registered
-- for the day 3- how many inquiry received for the day 4- how many customer registered for the day
-- with their names and mobile number as pdf 5- how many comparison report generated for the day
-- 6- how many customer paid reveal fee for the day 7- the plan for the next day".
--
-- MEASURED (read-only, 21 Sep 2026 21:47 Dubai, htdblwldjkcgjvmqkbeh):
--   notifications id 35777 (type founder_brief, 21 Sep): 5,502 chars. It opens with the agent roster
--     and ~60 scheduled-job run counts ("fn:ai_gateway 40730 ..."), then all-time and 7-day totals.
--     None of his seven questions is answered for the DAY; several are not answered at all.
--   The 21 Sep production rows ARE a fixture day: 3 supplier registrations, 2 customers, 2 inquiries
--     and 1 Stripe-paid reveal were written today, and every one is ZZ DEMO / example.invalid /
--     is_demo. The real answer for today is zero on all six counts.
--   notifications type='supplier_invite': 0 rows ever. app_secrets invite_enabled=false,
--     supplier_outreach_golive=false, invite_daily_cap=50.
--   No founder language preference is recorded anywhere (founder_habit / founder_instruction /
--     app_secrets carry none; every instruction he has written is English), so the brief is English.
--
-- WHAT WAS WRONG
--   1. fn_founder_brief wrote an operations dump, not a founder brief.
--   2. Its counts mixed all-time, 7-day and status-column figures (outreach.status='sent',
--      leads.approval_status) -- a status column is an intention, not a delivery.
--   3. It did not exclude demo rows, so today it would have reported the fixtures as business.
--   4. The digest fires at 20:00 Dubai, so a calendar-day window silently drops 20:00-24:00.
--
-- WHAT CHANGES
--   fn_founder_brief_figures(from,to)  NEW. The seven answers for a window, each from its event or
--                                      delivery record, demo rows excluded and COUNTED separately.
--   fn_founder_brief_text(figures)     NEW. Seven numbered plain sentences, "none today" on zero.
--   fn_founder_brief_pdf_blocks(fig)   NEW. The customer list (name + mobile) for pdf_native.
--   fn_founder_brief(date)             REPLACES fn_founder_brief(). Window = end of the previous
--                                      brief -> now (first brief: local midnight), so nothing falls
--                                      between two briefs. Writes the Command Center row, returns
--                                      {subject, body, figures}. Sends NOTHING itself.
--   fn_ceo_daily_digest / _submit / _tick  rewired: submission is always _submit; a day with new
--                                      customers waits for the PDF; _tick hands the blocks to
--                                      resilience_ping, which renders and calls _attach_pdf.
--   ceo_daily_digest.pdf_bucket/pdf_path   NEW columns.
--
-- NOT CHANGED: the recipient (app_secrets.admin_emails), the founder-mail gate, the 20:00 time,
-- the once-per-local-day key, the notification type 'founder_brief', send_outbox.
-- Prevented by: scripts/checks/the_founder_brief_says_seven_things.test.mjs

begin;

alter table public.ceo_daily_digest add column if not exists pdf_bucket text;
alter table public.ceo_daily_digest add column if not exists pdf_path   text;

-- ---------------------------------------------------------------------------------------------
-- 1. THE SEVEN ANSWERS. Every count below reads an EVENT or DELIVERY record (a timestamp written
--    when the thing happened, a provider id written when the provider accepted it). No count reads
--    a status column; the recurrence test enforces that on the text between the COUNTS markers.
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
    select jsonb_build_array(case when count(*) = 0 then 'The IT engineer has no open technical problems.'
                                  else 'The IT engineer works on '||count(*)||' open technical problem(s).' end)
      from public.it_engineer_finding where closed_at is null);

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
-- 2. THE WORDS. Seven numbered items, always all seven, always in this order.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_founder_brief_text(p_fig jsonb)
returns text language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare
  n_inv int := coalesce((p_fig->'invitations'->>'count')::int, 0);
  n_sup int := coalesce((p_fig->'suppliers_registered'->>'count')::int, 0);
  n_inq int := coalesce((p_fig->'inquiries'->>'count')::int, 0);
  n_cus int := coalesce((p_fig->'customers'->>'count')::int, 0);
  n_cmp int := coalesce((p_fig->'comparisons'->>'count')::int, 0);
  n_rev int := coalesce((p_fig->'reveal_fees'->>'count')::int, 0);
  v_aed numeric := coalesce((p_fig->'reveal_fees'->>'aed')::numeric, 0);
  v_from timestamptz := (p_fig->>'window_from')::timestamptz;
  v_to   timestamptz := (p_fig->>'window_to')::timestamptz;
  v_demo int;
  v_names text; v_plan text;
  v_period text;
begin
  v_period := case when (v_from at time zone 'Asia/Dubai')::time = time '00:00'
                    and (v_from at time zone 'Asia/Dubai')::date = (v_to at time zone 'Asia/Dubai')::date
                   then 'from midnight to '||to_char(v_to at time zone 'Asia/Dubai','FMHH12:MI am')
                   else 'from '||to_char(v_from at time zone 'Asia/Dubai','FMHH12:MI am Dy FMDD Mon')||
                        ' to '||to_char(v_to at time zone 'Asia/Dubai','FMHH12:MI am')
              end;
  v_demo := coalesce((p_fig->'invitations'->>'demo_excluded')::int,0) + coalesce((p_fig->'suppliers_registered'->>'demo_excluded')::int,0)
          + coalesce((p_fig->'inquiries'->>'demo_excluded')::int,0) + coalesce((p_fig->'customers'->>'demo_excluded')::int,0)
          + coalesce((p_fig->'comparisons'->>'demo_excluded')::int,0) + coalesce((p_fig->'reveal_fees'->>'demo_excluded')::int,0);
  select string_agg('   - '||x, E'\n') into v_plan from jsonb_array_elements_text(coalesce(p_fig->'plan','[]')) x;

  return
    'Your QuotesDone brief for '||to_char(v_to at time zone 'Asia/Dubai','FMDay FMDD FMMonth')||
    ' ('||v_period||', Dubai time).'||E'\n\n'||
    '1. Supplier invitations sent: '||
      case when n_inv = 0 then 'none today.'
           else n_inv||' today, to: '||
                (select string_agg(x, ', ') from jsonb_array_elements_text(p_fig->'invitations'->'names') x)||'.' end||E'\n'||
    '2. Suppliers registered: '||
      case when n_sup = 0 then 'none today.'
           else n_sup||' today: '||
                (select string_agg(x, ', ') from jsonb_array_elements_text(p_fig->'suppliers_registered'->'names') x)||'.' end||E'\n'||
    '3. Customer inquiries received: '||case when n_inq = 0 then 'none today.' else n_inq||' today.' end||E'\n'||
    '4. Customers registered: '||
      case when n_cus = 0 then 'none today.'
           else n_cus||' today. Their names and mobile numbers are in the attached PDF.' end||E'\n'||
    '5. Comparison reports generated: '||case when n_cmp = 0 then 'none today.' else n_cmp||' today.' end||E'\n'||
    '6. Customers who paid a reveal fee: '||
      case when n_rev = 0 then 'none today.'
           else n_rev||' today, AED '||to_char(v_aed,'FM999,999,990.00')||' in total (confirmed by Stripe).' end||E'\n'||
    '7. The plan for tomorrow:'||E'\n'||coalesce(v_plan, '   - Nothing is scheduled.')||E'\n\n'||
    case when v_demo > 0 then 'Test data is left out of every number above ('||v_demo||' test record(s) today).'
         else 'Test data is left out of every number above.' end||E'\n'||
    'Nothing here needs a reply.';
end;
$fn$;
revoke execute on function public.fn_founder_brief_text(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 3. THE PDF. Only when at least one real customer registered. pdf_native renders these blocks
--    on the company letterhead (resilience_ping calls it; Postgres cannot draw a PDF).
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_founder_brief_pdf_blocks(p_fig jsonb)
returns jsonb language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_array(
    jsonb_build_object('t','p','text',
      (p_fig->'customers'->>'count')||' customer(s) registered on QuotesDone on '||
      to_char(((p_fig->>'window_to')::timestamptz) at time zone 'Asia/Dubai','FMDay FMDD FMMonth YYYY')||
      ' (Dubai time). Test accounts are not included.'),
    jsonb_build_object('t','table','head', jsonb_build_array('#','Name','Mobile number','Registered at'),
      'widths', jsonb_build_array(0.08, 0.44, 0.28, 0.20),
      'rows', coalesce((select jsonb_agg(jsonb_build_array(o::text, e->>'name', e->>'mobile', e->>'at') order by o)
                          from jsonb_array_elements(p_fig->'customers'->'list') with ordinality as t(e, o)), '[]'::jsonb)),
    jsonb_build_object('t','note','text','Confidential: personal data of QuotesDone customers, for the founder only.'));
$fn$;
revoke execute on function public.fn_founder_brief_pdf_blocks(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 4. THE BRIEF. Replaces fn_founder_brief(). DROP + CREATE because the signature and return type
--    change; CREATE grants EXECUTE to PUBLIC, so the revoke follows.
-- ---------------------------------------------------------------------------------------------
drop function if exists public.fn_founder_brief();

create or replace function public.fn_founder_brief(p_local_date date default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_tz text := 'Asia/Dubai';
  v_day date := coalesce(p_local_date, (now() at time zone 'Asia/Dubai')::date);
  v_midnight timestamptz := (v_day::timestamp) at time zone 'Asia/Dubai';
  v_from timestamptz; v_to timestamptz; v_prev timestamptz;
  v_fig jsonb; v_body text; v_subj text; v_run bigint; v_alert uuid;
begin
  insert into public.agent_runs(agent, started_at) values ('brief', now()) returning id into v_run;

  -- The window starts where the previous brief ended, so 20:00-24:00 is never lost between days.
  select (figures->>'window_to')::timestamptz into v_prev
    from public.ceo_daily_digest
   where local_date < v_day and figures ? 'window_to'
   order by local_date desc limit 1;
  v_from := case when v_prev is null or v_prev < v_midnight - interval '1 day' then v_midnight else v_prev end;
  v_to   := least(now(), v_midnight + interval '1 day');

  v_fig  := public.fn_founder_brief_figures(v_from, v_to);
  v_body := public.fn_founder_brief_text(v_fig);
  v_subj := 'QuotesDone daily brief - '||to_char(v_day,'Dy DD Mon');

  -- The Command Center row is written whether or not a recipient exists.
  insert into public.founder_alerts(level, event, detail, channel)
    values ('info', 'CEO end-of-day company digest', v_body, 'os') returning id into v_alert;

  -- Unchanged from the previous brief: fold the week's 'digest' notifications.
  update public.notifications set status = 'digested'
   where status = 'digest' and created_at >= now() - interval '7 days' and created_at <= now();

  update public.agent_runs set finished_at = now(), status = 'ok',
         counts = jsonb_build_object(
           'invitations', v_fig->'invitations'->'count', 'suppliers_registered', v_fig->'suppliers_registered'->'count',
           'inquiries', v_fig->'inquiries'->'count', 'customers', v_fig->'customers'->'count',
           'comparisons', v_fig->'comparisons'->'count', 'reveal_fees', v_fig->'reveal_fees'->'count')
   where id = v_run;

  return jsonb_build_object('subject', v_subj, 'body', v_body, 'figures', v_fig, 'command_center_id', v_alert);
end;
$fn$;
revoke execute on function public.fn_founder_brief(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5. SUBMISSION. The only writer of the founder_brief notification. A day with new customers waits
--    for its PDF: the founder asked for the list AS a PDF, so a covering note without it is not sent.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_daily_digest_submit(p_id bigint)
returns public.ceo_daily_digest language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_row public.ceo_daily_digest%rowtype;
  v_owner text;
  v_notif_id bigint;
  v_needs_pdf boolean;
begin
  select * into v_row from public.ceo_daily_digest where id = p_id;
  if not found or v_row.submitted_at is not null then return v_row; end if;

  v_needs_pdf := coalesce((v_row.figures->'customers'->>'count')::int, 0) > 0;
  if v_needs_pdf and v_row.pdf_path is null then
    update public.ceo_daily_digest
       set last_delivery_error = 'waiting for the customer list PDF', updated_at = now()
     where id = p_id returning * into v_row;
    return v_row;
  end if;

  select nullif(btrim(split_part(coalesce(value,''), ',', 1)), '') into v_owner
    from public.app_secrets where key = 'admin_emails';
  if v_owner is null then
    update public.ceo_daily_digest
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'no recipient configured in app_secrets.admin_emails', updated_at = now()
     where id = p_id returning * into v_row;
    return v_row;
  end if;

  begin
    insert into public.notifications(type, to_email, to_role, channel, subject, body, attachments)
      values ('founder_brief', v_owner, 'admin', 'email',
              coalesce(v_row.subject, 'QuotesDone daily brief - '||to_char(v_row.local_date,'Dy DD Mon')),
              coalesce(v_row.body, ''),
              case when v_row.pdf_path is not null then jsonb_build_array(jsonb_build_object(
                'bucket', v_row.pdf_bucket, 'path', v_row.pdf_path,
                'filename', 'QuotesDone customers registered '||to_char(v_row.local_date,'YYYY-MM-DD')||'.pdf')) end)
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
         submitted_at = case when v_notif_id is not null then now() end,
         status = case when v_notif_id is not null then 'submitted' else status end,
         delivery_attempts = delivery_attempts + 1,
         last_delivery_error = case when v_notif_id is null then 'the founder-mail gate did not accept the row' end,
         updated_at = now()
   where id = p_id returning * into v_row;
  return v_row;
end;
$fn$;
revoke execute on function public.fn_ceo_daily_digest_submit(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 6. THE REPORT ROW. One per company per local date; the lookup on report_key stays UNFILTERED.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_daily_digest(p_local_date date default null, p_revise boolean default false,
                                                      p_revision_note text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_tz text := 'Asia/Dubai';
  v_date date; v_key text;
  v_row public.ceo_daily_digest%rowtype;
  v_brief jsonb;
begin
  v_date := coalesce(p_local_date, (now() at time zone v_tz)::date);
  v_key  := 'quotesdone:'||to_char(v_date,'YYYY-MM-DD');

  select * into v_row from public.ceo_daily_digest where report_key = v_key;   -- UNFILTERED

  if found and not p_revise then
    if v_row.submitted_at is null then v_row := public.fn_ceo_daily_digest_submit(v_row.id); end if;
    return jsonb_build_object('report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
      'status', v_row.status, 'generated', false, 'reason', 'already generated for this local date',
      'submitted', v_row.submitted_at is not null, 'delivery_attempts', v_row.delivery_attempts,
      'last_delivery_error', v_row.last_delivery_error);
  end if;

  begin
    v_brief := public.fn_founder_brief(v_date);
  exception when others then
    if v_row.id is not null then
      update public.ceo_daily_digest set last_delivery_error = 'generation failed: '||sqlerrm, updated_at = now()
       where id = v_row.id;
    end if;
    return jsonb_build_object('report_key', v_key, 'generated', false, 'error', sqlerrm);
  end;

  if p_revise and v_row.id is not null then
    -- A correction is a new send of the corrected text: clear the old submission and the old PDF.
    update public.ceo_daily_digest
       set revision = revision + 1, revision_note = p_revision_note,
           subject = v_brief->>'subject', body = v_brief->>'body', figures = v_brief->'figures',
           command_center_id = (v_brief->>'command_center_id')::uuid,
           status = 'generated', generated_at = now(), submitted_at = null, notification_id = null,
           pdf_bucket = null, pdf_path = null, last_delivery_error = null, updated_at = now()
     where id = v_row.id returning * into v_row;
  else
    insert into public.ceo_daily_digest(company_key, local_date, local_timezone, report_key, revision, revision_note,
                                        subject, body, figures, status, command_center_id, delivery_attempts)
    values ('quotesdone', v_date, v_tz, v_key, 1, p_revision_note,
            v_brief->>'subject', v_brief->>'body', v_brief->'figures', 'generated',
            (v_brief->>'command_center_id')::uuid, 0)
    returning * into v_row;
  end if;

  v_row := public.fn_ceo_daily_digest_submit(v_row.id);

  return jsonb_build_object('report_key', v_row.report_key, 'id', v_row.id, 'revision', v_row.revision,
    'status', v_row.status, 'generated', true, 'submitted', v_row.submitted_at is not null,
    'delivery_attempts', v_row.delivery_attempts, 'last_delivery_error', v_row.last_delivery_error);
end;
$fn$;
revoke execute on function public.fn_ceo_daily_digest(date, boolean, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 7. THE TICK. Unchanged timing; when the day's row waits for its PDF, hand the blocks back.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_daily_digest_tick()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_tz text := 'Asia/Dubai';
  v_local timestamp; v_at time; v_date date; v_key text;
  v_row public.ceo_daily_digest%rowtype;
  v_res jsonb;
begin
  v_local := now() at time zone v_tz;
  v_date  := v_local::date;
  v_key   := 'quotesdone:'||to_char(v_date,'YYYY-MM-DD');

  begin
    select coalesce(nullif(btrim(value),''),'20:00')::time into v_at from public.app_secrets where key = 'ceo_digest_local_time';
  exception when others then v_at := time '20:00'; end;
  v_at := coalesce(v_at, time '20:00');

  if v_local::time < v_at then
    return jsonb_build_object('fired', false, 'reason', 'before the configured local time',
      'local_now', to_char(v_local,'YYYY-MM-DD HH24:MI'), 'configured_at', v_at::text, 'report_key', v_key,
      'exists', exists (select 1 from public.ceo_daily_digest where report_key = v_key));
  end if;

  v_res := public.fn_ceo_daily_digest(v_date) || jsonb_build_object('fired', true, 'configured_at', v_at::text);

  select * into v_row from public.ceo_daily_digest where report_key = v_key;
  if found and v_row.submitted_at is null and v_row.pdf_path is null
     and coalesce((v_row.figures->'customers'->>'count')::int, 0) > 0 then
    v_res := v_res || jsonb_build_object('pdf_pending', true, 'id', v_row.id, 'report_key', v_row.report_key,
      'pdf_title', 'Customers registered - '||to_char(v_row.local_date,'Dy DD Mon YYYY'),
      'pdf_blocks', public.fn_founder_brief_pdf_blocks(v_row.figures));
  end if;
  return v_res;
end;
$fn$;
revoke execute on function public.fn_ceo_daily_digest_tick() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 8. THE PDF COMES BACK. A render failure keeps the report for the next tick; it never sends
--    the covering note without the document.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_daily_digest_attach_pdf(p_id bigint, p_bucket text, p_path text, p_error text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_row public.ceo_daily_digest%rowtype;
begin
  if p_path is null or p_error is not null then
    update public.ceo_daily_digest
       set delivery_attempts = delivery_attempts + 1,
           last_delivery_error = 'customer list PDF: '||coalesce(p_error, 'no path returned'), updated_at = now()
     where id = p_id and submitted_at is null returning * into v_row;
    return jsonb_build_object('id', p_id, 'submitted', false, 'error', v_row.last_delivery_error);
  end if;
  update public.ceo_daily_digest set pdf_bucket = p_bucket, pdf_path = p_path, updated_at = now()
   where id = p_id and submitted_at is null;
  v_row := public.fn_ceo_daily_digest_submit(p_id);
  return jsonb_build_object('id', p_id, 'submitted', v_row.submitted_at is not null,
                            'notification_id', v_row.notification_id, 'error', v_row.last_delivery_error);
end;
$fn$;
revoke execute on function public.fn_ceo_daily_digest_attach_pdf(bigint, text, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 9. PROBE: a fixed past window that holds only fixtures must read zero on all six counts, with
--    the fixtures counted as excluded. Verdict row, nothing written.
-- ---------------------------------------------------------------------------------------------
select case
  when f->'invitations'->>'count' = '0' and f->'suppliers_registered'->>'count' = '0'
   and f->'inquiries'->>'count' = '0' and f->'customers'->>'count' = '0'
   and f->'comparisons'->>'count' = '0' and f->'reveal_fees'->>'count' = '0'
   and (f->'suppliers_registered'->>'demo_excluded')::int >= 1
   and public.fn_founder_brief_text(f) ~ '1\. .*\n2\. .*\n3\. .*\n4\. .*\n5\. .*\n6\. .*\n7\. '
  then 'PROBE OK: the 21 Sep fixture day reads zero and all seven items are present'
  else 'PROBE FAILED: '||f::text end as verdict
from (select public.fn_founder_brief_figures(timestamptz '2026-09-21 00:00+04', timestamptz '2026-09-21 21:45+04') f) z;

commit;
