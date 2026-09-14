-- DEMO IDENTITIES ARE MARKED, NEVER PAIR WITH REAL ONES, AND NEVER REACH A REAL PERSON
-- 14 Sep 2026. Assigned: ceo (it_engineer's tooling, carried out for the ceo).
--
-- The founder: "do what is needed cause you need to keep browsing stuff without my credentials".
-- scripts/e2e/ therefore creates its own ZZ DEMO customers and suppliers on the ONE production
-- project and drives both portals as them. That is only safe if the database can tell those accounts
-- apart from real ones and acts on the difference. MEASURED before this file (14 Sep 2026):
--
--   * No `is_demo` marker existed on public.customers or public.leads. Demo rows were recognised by
--     convention only (ZZ DEMO / QD Demo names, @example.invalid / @example.com, tags qd_demo,
--     source demo_factory / qd_demo_fixture), and each reader re-derived the rule its own way.
--   * fn_is_matchable excludes nothing demo, and inquiry_matches carries 0 user triggers (measured),
--     so a demo supplier could be matched to a real customer's inquiry and a real supplier to a demo
--     inquiry. Nothing refused the pairing.
--   * zzz_notifications_demo_guard keys ONLY on to_email and ONLY while decision_policy
--     .demo_rehearsal_active is true. send_whatsapp checked only that a number was well-formed, so a
--     fixture mobile would have gone to Twilio, and a notification to a REAL address ABOUT a demo
--     entity (the founder, a real supplier) passed every guard.
--
-- WHAT THIS CHANGES
--   1. fn_is_demo_email / fn_is_demo_phone: the one SQL answer, identical to
--      supabase/functions/_shared/demo_identity.ts (RFC 2606 reserved domains; the fixture mobile
--      block +971 50 000 00xx). Both are pure and IMMUTABLE so a generated column can use them.
--   2. customers.is_demo and leads.is_demo: GENERATED ALWAYS ... STORED. Derived from the row, so no
--      client, API or fixture can set it or forget to - and a real customer cannot acquire it: they
--      would need to receive an OTP at a reserved domain, which is impossible by definition.
--   3. fn_inquiry_is_demo(uuid): an inquiry is demo when its customer is, or it carries a run tag.
--   4. Demo and real never pair: a match between a demo inquiry and a real supplier (or the reverse)
--      is silently NOT recorded (both writers already ask for the landed rows back and treat a
--      missing one as refused), and such a QUOTE is refused outright.
--   5. zzzz_notifications_demo_capture: a notification addressed to a demo recipient, OR about a
--      demo lead / inquiry / quote, is recorded as status 'suppressed' with a 'captured:' reason on
--      insert and on any later move back to queued/pending. Both dispatchers drain only 'queued', so
--      nothing about a rehearsal reaches Resend or Twilio - including the founder's own inbox.
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE
--   * zzz_notifications_demo_guard stays exactly as it is (name order runs it first; this trigger
--     has the last word for demo rows only).
--   * No real row changes state: measured 0 leads and 0 customers match the demo rule today.
--   * Business-figure exclusions for the dashboards are section 7, just before the self-check.

-- 1. the rule -------------------------------------------------------------------------------------
create or replace function public.fn_is_demo_email(p_email text)
returns boolean language sql immutable
set search_path to 'pg_catalog', 'pg_temp'
as $fn$
  select coalesce(btrim(p_email), '') ~* '@([a-z0-9_-]+[.])*(example[.](com|net|org)|test|example|invalid|localhost)$'
$fn$;

create or replace function public.fn_is_demo_phone(p_phone text)
returns boolean language sql immutable
set search_path to 'pg_catalog', 'pg_temp'
as $fn$
  select regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') ~ '^9715000000[0-9]{2}$'
$fn$;

comment on function public.fn_is_demo_email(text) is
  'True for an RFC 2606 reserved domain nobody can receive mail at. Same rule as _shared/demo_identity.ts.';
comment on function public.fn_is_demo_phone(text) is
  'True for the reserved fixture mobile block +971 50 000 00xx. Same rule as _shared/demo_identity.ts.';

-- 2. the marker -----------------------------------------------------------------------------------
alter table public.customers add column if not exists is_demo boolean
  generated always as (
    public.fn_is_demo_email(email) or public.fn_is_demo_phone(phone)
    or coalesce(full_name, '') ilike 'ZZ DEMO%'
  ) stored;

alter table public.leads add column if not exists is_demo boolean
  generated always as (
    public.fn_is_demo_email(email) or public.fn_is_demo_email(claimed_by) or public.fn_is_demo_phone(phone)
    or 'qd_demo' = any (coalesce(tags, '{}'::text[]))
    or coalesce(company_name, '') ilike 'ZZ DEMO%' or coalesce(company_name, '') like 'QD Demo %'
    or coalesce(source, '') in ('demo_factory', 'qd_demo_fixture')
  ) stored;

comment on column public.customers.is_demo is
  'Derived, never written: a demo (e2e / fixture) customer. Never matched to real suppliers, never messaged, never counted.';
comment on column public.leads.is_demo is
  'Derived, never written: a demo (e2e / fixture) supplier. Never matched to real customers, never messaged, never counted.';

create or replace function public.fn_inquiry_is_demo(p_inquiry uuid)
returns boolean language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((
    select coalesce(c.is_demo, false)
           or coalesce(i.provenance ? 'qd_run', false)
           or coalesce(i.brief_source, '') = 'qd_demo_fixture'
      from public.inquiries i
      left join public.customers c on c.id = i.customer_id
     where i.id = p_inquiry), false)
$fn$;
revoke execute on function public.fn_inquiry_is_demo(uuid) from public, anon, authenticated;

-- 4. demo and real never pair ---------------------------------------------------------------------
create or replace function public.fn_demo_and_real_never_pair()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_inq boolean; v_sup boolean;
begin
  v_inq := public.fn_inquiry_is_demo(NEW.inquiry_id);
  select coalesce(l.is_demo, false) into v_sup from public.leads l where l.id = NEW.supplier_id;
  if v_inq = coalesce(v_sup, false) then return NEW; end if;
  -- A match that must not exist is simply not recorded. customer_api and sales_engineer both read
  -- the landed rows back and report a missing one as refused, so the fanout stays honest.
  if TG_TABLE_NAME = 'inquiry_matches' then return null; end if;
  raise exception 'a % supplier cannot quote a % request (demo and real accounts never meet)',
    case when coalesce(v_sup, false) then 'demo' else 'real' end,
    case when v_inq then 'demo' else 'real' end
    using errcode = '23514';
end $fn$;
revoke execute on function public.fn_demo_and_real_never_pair() from public, anon, authenticated;

drop trigger if exists a01_inquiry_match_demo_and_real_never_pair on public.inquiry_matches;
create trigger a01_inquiry_match_demo_and_real_never_pair
  before insert or update of inquiry_id, supplier_id on public.inquiry_matches
  for each row execute function public.fn_demo_and_real_never_pair();

drop trigger if exists a01_quote_demo_and_real_never_pair on public.quotes;
create trigger a01_quote_demo_and_real_never_pair
  before insert on public.quotes
  for each row execute function public.fn_demo_and_real_never_pair();

-- 5. nothing about a rehearsal is dispatched -------------------------------------------------------
create or replace function public.fn_notifications_demo_capture()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- Only a row that a dispatcher could still pick up is judged; a terminal state is left alone.
  -- 'digest' is on that list: trg_notifications_digest parks admin/founder rows there for the
  -- founder's digest mail, so a row about a demo entity would otherwise reach him in a digest.
  if coalesce(NEW.status, 'pending') not in ('queued', 'pending', 'held', 'digest') then return NEW; end if;
  if TG_OP = 'UPDATE' and coalesce(NEW.status, '') not in ('queued', 'pending', 'digest') then return NEW; end if;
  if public.fn_is_demo_email(NEW.to_email)
     or public.fn_is_demo_phone(NEW.to_phone)
     or (NEW.lead_id is not null and exists (select 1 from public.leads l where l.id = NEW.lead_id and l.is_demo))
     or (NEW.inquiry_id is not null and public.fn_inquiry_is_demo(NEW.inquiry_id))
     or (NEW.quote_id is not null and exists (
           select 1 from public.quotes q
            where q.id = NEW.quote_id
              and (public.fn_inquiry_is_demo(q.inquiry_id)
                   or exists (select 1 from public.leads l where l.id = q.supplier_id and l.is_demo))))
  then
    NEW.status := 'suppressed';
    NEW.last_error := 'captured: a demo recipient or a demo subject (zzzz_notifications_demo_capture). '
                   || 'Recorded for the rehearsal, never handed to Resend or Twilio.';
  end if;
  return NEW;
exception when others then
  -- Fail closed, the same discipline as zzz_notifications_demo_guard: an unreadable row is held.
  NEW.status := 'held';
  NEW.last_error := 'HELD by zzzz_notifications_demo_capture (guard itself errored: ' || sqlerrm || ')';
  return NEW;
end $fn$;
revoke execute on function public.fn_notifications_demo_capture() from public, anon, authenticated;

drop trigger if exists zzzz_notifications_demo_capture on public.notifications;
create trigger zzzz_notifications_demo_capture
  before insert or update of status, to_email, to_phone on public.notifications
  for each row execute function public.fn_notifications_demo_capture();

-- 7. business figures never count a demo row ------------------------------------------------------
-- Measured 14 Sep 2026: fn_health_index, fn_os_dashboard_viz, fn_os_health and fn_company_snapshot
-- (and fn_ops_dashboard / fn_wa_context, see below) counted customers, suppliers, requests,
-- quotes and revenue with no demo filter, so one e2e run would have shown the founder a customer who
-- does not exist. Each body below is the LIVE definition verbatim (matched against its canonical file
-- whitespace-insensitively) with the demo exclusion added to every business count and sum; the
-- comment above each names every line changed. Signatures, security and search_path are unchanged.
-- LEFT OUT ON PURPOSE: fn_ops_dashboard calls fn_founder_refund_approvals_open() and fn_wa_context's
-- founder branch calls fn_founder_queue(12); NEITHER EXISTS, so both throw on every call today, and
-- apply_sql.mjs rightly refuses to redefine a routine around a missing callee. Their demo exclusion
-- goes in with the fix for those callees (a separate change). Also found, not fixed: fn_os_dashboard_viz reads quotes.revealed, which does not exist, and its
-- handler returns an empty pipeline. v_supply_gap (read by fn_company_snapshot) still counts demo leads.
-- figures_exclude_demo.sql - live bodies (pg_get_functiondef, 2026-09-14) with demo exclusion added.
-- Requires customers.is_demo and leads.is_demo to exist first. Line numbers refer to the live pg_get_functiondef output.
-- Inquiry demo = provenance->>'qd_run' set OR brief_source='qd_demo_fixture' OR its customer is_demo.
-- Quote demo = supplier is_demo OR inquiry demo. Transaction demo = customer is_demo OR quote-demo rule on its supplier/inquiry.

-- fn_health_index: changed L15 signups_7d: demo customers; L16 quotes_7d: demo quotes; L23 approved_suppliers: full is_demo rule (old two-marker rule kept); L33 inq_total/inq_done: demo inquiries; L35 avg_qual: demo quotes; L37 avg_resp: demo suppliers
CREATE OR REPLACE FUNCTION public.fn_health_index()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s_acq numeric; s_supp numeric; s_rfq numeric; s_qual numeric;
  s_resp numeric; s_disp numeric; s_up numeric;
  signups_7d int; quotes_7d int; approved_suppliers int;
  inq_total int; inq_done int; avg_qual numeric; avg_resp numeric;
  blocked_30d int; msgs_30d int; up_ok int; up_tot int;
  parts numeric[]; overall numeric; band text; present int;
begin
  select count(*) into signups_7d from customers where created_at > now()-interval '7 days' and not is_demo;
  select count(*) into quotes_7d  from quotes    where created_at > now()-interval '7 days' and not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)));
  -- DEMO FIXTURES EXCLUDED. The marker is in the data, not the schema: the convention seeded on
  -- 7-8 Aug 2026 is 'ZZ DEMO ' in company_name and an @example.invalid address. Both are checked
  -- because either alone would let a half-formed fixture through.
  select count(*) into approved_suppliers from leads
     where (coalesce(approval_status,'')='approved' or claimed=true)
       and coalesce(company_name,'') not like 'ZZ DEMO%'
       and coalesce(email,'') not like '%@example.invalid'
       and not is_demo;
  -- RFQ completion: real RFQs only (exclude split-parent containers and customer-cancelled),
  -- success = completed/won or closed-with-a-hire (a "closed, not hired" is NOT a completion).
  select count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and coalesce(status,'')<>'cancelled'),
         count(*) filter (where created_at > now()-interval '90 days'
                            and coalesce(status,'')<>'split' and coalesce(category,'')<>'combined'
                            and (status in ('completed','won')
                                 or (status='closed' and coalesce(outcome,'') in ('hired','hired_elsewhere'))))
    into inq_total, inq_done from inquiries where not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo));
  select avg(nullif(quality->>'score','')::numeric) into avg_qual
    from quotes where quality is not null and created_at > now()-interval '90 days' and not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)));
  select avg(nullif(rv_response_rate,0)) into avg_resp
    from leads where coalesce(rv_reveals,0) > 0 and not is_demo;
  select count(*) filter (where coalesce(blocked,false)),
         count(*) into blocked_30d, msgs_30d
    from messages where created_at > now()-interval '30 days';
  select count(*) filter (where ok), count(*) into up_ok, up_tot
    from health_checks where created_at > now()-interval '24 hours';

  s_acq  := least(100, signups_7d * 10.0);
  s_supp := case when approved_suppliers=0 and quotes_7d=0 then null
                 else least(100, quotes_7d * 5.0) end;
  s_rfq  := case when inq_total=0 then null else round(inq_done::numeric/inq_total*100,1) end;
  s_qual := avg_qual;
  s_resp := case when avg_resp is null then null
                 when avg_resp <= 1 then round(avg_resp*100,1) else round(avg_resp,1) end;
  s_disp := case when msgs_30d=0 then null
                 else greatest(0, 100 - least(100, blocked_30d*5.0)) end;
  s_up   := case when up_tot=0 then null else round(up_ok::numeric/up_tot*100,1) end;

  parts := array_remove(array[s_acq,s_supp,s_rfq,s_qual,s_resp,s_disp,s_up], null);
  present := coalesce(array_length(parts,1),0);
  overall := case when present=0 then null else round((select avg(x) from unnest(parts) x),1) end;
  band := case when overall is null then 'no data'
               when overall >= 75 then 'healthy'
               when overall >= 50 then 'watch'
               else 'attention' end;

  return jsonb_build_object(
    'index', overall, 'band', band, 'components_present', present,
    -- A PROSE INSIGHT WITH A CAUSE AND A MAGNITUDE, not a blank.
    -- `overall` is the mean of the present components, so the ones furthest below it are
    -- arithmetically what hold the index there. "driven by" is division, not narrative.
    'note', case
      when present < 3 then 'insufficient data - pre-traction; index will firm up with volume'
      else (select 'Company health is '||overall||' of 100 ('||band||'), driven by '
              ||string_agg(w.label||' at '||w.score, ' and ' order by w.score, w.label)
              ||' - the two furthest below the '||overall||'-point average of '||present
              ||' measured components.'
              from (select v.label, v.score from (values
                      ('customer acquisition', s_acq), ('supplier activity', s_supp),
                      ('RFQ completion', s_rfq), ('quote quality', s_qual),
                      ('response time', s_resp), ('dispute health', s_disp), ('uptime', s_up)
                    ) v(label, score)
                     where v.score is not null order by v.score, v.label limit 2) w)
      end,
    'components', jsonb_build_object(
       'customer_acquisition', s_acq, 'supplier_activity', s_supp, 'rfq_completion', s_rfq,
       'quote_quality', s_qual, 'response_time', s_resp, 'dispute_health', s_disp,
       'uptime', s_up, 'revenue', null),
    'raw', jsonb_build_object(
       'signups_7d', signups_7d, 'quotes_7d', quotes_7d, 'approved_suppliers', approved_suppliers,
       'inquiries_eligible_90d', inq_total, 'completed_90d', inq_done,
       'blocked_msgs_30d', blocked_30d, 'uptime_ok', up_ok, 'uptime_checks', up_tot),
    'computed_at', now());
end $function$;

-- fn_os_dashboard_viz: changed L14 v_total; L15 v_contacted; L16 v_invited; L17 v_claimed; L18 v_registered; L19 v_verified; L20 v_approved; L37 j_sector; L42 j_emirate; L48 j_invites; L63 pipeline New; L64 pipeline Matched; L65 pipeline Quoted; L66 pipeline Revealed; L67 pipeline Won
CREATE OR REPLACE FUNCTION public.fn_os_dashboard_viz()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  out jsonb := '{}'::jsonb;
  v_total bigint; v_contacted bigint; v_invited bigint; v_claimed bigint;
  v_registered bigint; v_verified bigint; v_approved bigint;
  v_runs24 bigint; v_agents24 bigint; v_failed24 bigint;
  j_sector jsonb; j_emirate jsonb; j_invites jsonb; j_agents jsonb; j_funnel jsonb; j_pipeline jsonb;
begin
  select count(*) into v_total from leads where not is_demo;
  select count(*) into v_contacted from leads where contacted is true and not is_demo;
  select count(*) into v_invited from leads where invited_at is not null and not is_demo;
  select count(*) into v_claimed from leads where claimed is true and not is_demo;
  select count(*) into v_registered from leads where registration_submitted_at is not null and not is_demo;
  select count(*) into v_verified from leads where verified is true and not is_demo;
  select count(*) into v_approved from leads where approved_at is not null and not is_demo;

  -- agent activity from agent_runs (the same source the header/Smart Engine use)
  begin
    select count(*) filter (where started_at > now() - interval '24 hours'),
           count(distinct agent) filter (where started_at > now() - interval '24 hours'),
           count(*) filter (where started_at > now() - interval '24 hours' and status in ('error','failed'))
      into v_runs24, v_agents24, v_failed24 from agent_runs;
    select coalesce(jsonb_agg(x), '[]'::jsonb) into j_agents from (
      select agent as label, count(*)::int as n
      from agent_runs where started_at > now() - interval '24 hours'
      group by agent order by count(*) desc limit 8
    ) x;
  exception when others then v_runs24 := 0; v_agents24 := 0; v_failed24 := 0; j_agents := '[]'::jsonb; end;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into j_sector from (
    select coalesce(nullif(trim(sector),''),'unspecified') as label, count(*)::int as n
    from leads where not is_demo group by 1 order by count(*) desc limit 12
  ) x;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into j_emirate from (
    select coalesce(nullif(trim(emirate),''),'unknown') as label, count(*)::int as n
    from leads where not is_demo group by 1 order by count(*) desc limit 9
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object('d', to_char(d.day,'Mon DD'), 'n', coalesce(c.n,0)) order by d.day), '[]'::jsonb)
    into j_invites
  from (select generate_series((current_date - interval '13 days')::date, current_date, interval '1 day')::date as day) d
  left join (select invited_at::date as day, count(*)::int as n from leads where invited_at > now() - interval '14 days' and not is_demo group by 1) c
    on c.day = d.day;

  j_funnel := jsonb_build_array(
    jsonb_build_object('stage','Sourced', 'n', v_total),
    jsonb_build_object('stage','Contacted', 'n', v_contacted),
    jsonb_build_object('stage','Invited', 'n', v_invited),
    jsonb_build_object('stage','Claimed', 'n', v_claimed),
    jsonb_build_object('stage','Registered', 'n', v_registered),
    jsonb_build_object('stage','Verified', 'n', v_verified),
    jsonb_build_object('stage','Approved', 'n', v_approved)
  );

  begin
    j_pipeline := jsonb_build_array(
      jsonb_build_object('stage','New', 'n', (select count(*) from inquiries where not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo)))),
      jsonb_build_object('stage','Matched', 'n', (select count(distinct inquiry_id) from quotes where not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo))))),
      jsonb_build_object('stage','Quoted', 'n', (select count(*) from quotes where not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo))))),
      jsonb_build_object('stage','Revealed', 'n', (select count(*) from quotes where coalesce(revealed,false) is true and not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo))))),
      jsonb_build_object('stage','Won', 'n', (select count(*) from inquiries where status = 'won' and not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo))))
    );
  exception when others then j_pipeline := jsonb_build_array(); end;

  out := jsonb_build_object(
    'headline', jsonb_build_object(
      'suppliers_total', v_total, 'invited_total', v_invited, 'verified_total', v_verified,
      'approved_total', v_approved, 'registered_total', v_registered,
      'agents_active_24h', v_agents24, 'runs_24h', v_runs24, 'runs_failed_24h', v_failed24),
    'funnel', j_funnel,
    'pipeline', j_pipeline,
    'by_sector', j_sector,
    'by_emirate', j_emirate,
    'invites_14d', j_invites,
    'agents_24h', j_agents,
    'generated_at', to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF')
  );
  return out;
end $function$;

-- fn_os_health: changed L26 payments_7d_count; L27 payments_7d_revenue_aed; L31 supplier_reach.leads; L32 with_capability; L33 confirmed; L38 matchable_now
-- search_path here is 'public' only (no pg_temp) - kept as live.
CREATE OR REPLACE FUNCTION public.fn_os_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE res jsonb;
BEGIN
  SELECT jsonb_build_object(
    'generated_at', now(),
    'failing_crons', coalesce((
      SELECT jsonb_agg(jsonb_build_object('job', j.jobname, 'status', lr.status, 'when', lr.end_time,
                                          'message', left(coalesce(lr.return_message,''),160))
                       ORDER BY lr.end_time DESC)
      FROM (SELECT DISTINCT ON (jobid) jobid, status, end_time, return_message
              FROM cron.job_run_details
             WHERE start_time > now() - interval '7 days'
             ORDER BY jobid, start_time DESC) lr
      JOIN cron.job j ON j.jobid = lr.jobid
      WHERE lr.status = 'failed' AND lr.end_time > now() - interval '24 hours'
    ), '[]'::jsonb),
    'agent_errors_24h', (SELECT count(*) FROM public.agent_runs WHERE status='error' AND started_at > now() - interval '24 hours'),
    'top_error_agents', coalesce((SELECT jsonb_agg(x) FROM (SELECT jsonb_build_object('agent',agent,'errors',count(*)) x FROM public.agent_runs WHERE status='error' AND started_at > now()-interval '24 hours' GROUP BY agent ORDER BY count(*) DESC LIMIT 6) q),'[]'::jsonb),
    'health_check_fails_24h', (SELECT count(*) FROM public.health_checks WHERE ok=false AND created_at > now()-interval '24 hours'),
    'ai_health_fails', coalesce((SELECT value FROM public.app_secrets WHERE key='ai_health_fails'),'0'),
    'payments_7d_count', (SELECT count(*) FROM public.transactions WHERE revealed_at > now()-interval '7 days' AND not exists (select 1 from public.customers dc where dc.id = transactions.customer_id and dc.is_demo) and not exists (select 1 from public.leads dl where dl.id = transactions.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = transactions.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)))),
    'payments_7d_revenue_aed', coalesce((SELECT round(sum(reveal_fee)::numeric,2) FROM public.transactions WHERE revealed_at > now()-interval '7 days' AND not exists (select 1 from public.customers dc where dc.id = transactions.customer_id and dc.is_demo) and not exists (select 1 from public.leads dl where dl.id = transactions.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = transactions.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)))),0),
    -- CAN A REQUEST REACH ANYONE? Each number is counted at the gate it actually has to pass, so
    -- the drop between them says WHERE the reach is lost rather than only that it is small.
    'supplier_reach', jsonb_build_object(
      'leads', (SELECT count(*) FROM public.leads WHERE NOT is_demo),
      'with_capability', (SELECT count(*) FROM public.supplier_capabilities WHERE coalesce(cardinality(trades),0) > 0 AND NOT EXISTS (SELECT 1 FROM public.leads dl WHERE dl.id = supplier_capabilities.supplier_id AND dl.is_demo)),
      'confirmed', (SELECT count(*) FROM public.supplier_capabilities WHERE confirmed_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.leads dl WHERE dl.id = supplier_capabilities.supplier_id AND dl.is_demo)),
      -- the real ceiling: confirmed AND the lead itself still admissible to matching
      'matchable_now', (
        SELECT count(*) FROM public.supplier_capabilities sc
        JOIN public.leads l ON l.id = sc.supplier_id
        WHERE sc.confirmed_at IS NOT NULL AND NOT l.is_demo
          AND coalesce(cardinality(sc.trades),0) > 0
          AND public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                                     l.approval_status, l.permanently_closed, l.chat_strikes)),
      'meaning', 'matchable_now is the most suppliers the structured matcher can shortlist for any request. fn_match_capability requires a supplier to have CONFIRMED their own scope; that gate is deliberate. When this is far below with_capability the shortage is confirmations, not suppliers.'
    )
  ) INTO res;
  RETURN res;
END
$function$;

-- fn_company_snapshot: changed L14 customers; L15 customers_with_inquiry; L23 approved_suppliers; L26 revenue_30d_aed
-- NOT EDITED: sendable_pool / categories_at_target read public.v_supply_gap, which counts leads without a demo filter; fix the view, not this function.
CREATE OR REPLACE FUNCTION public.fn_company_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s jsonb;
begin
  s := jsonb_build_object(
    'employees',        (select count(*) from org_agents where active),
    -- THE CUSTOMER BASE, which the snapshot has never recorded. Zero is the measurement today —
    -- 0 customers and 0 inquiries carrying one — and writing it down daily is what makes the day
    -- it stops being zero visible in the replay.
    'customers',              (select count(*) from customers where not is_demo),
    'customers_with_inquiry', (select count(distinct customer_id) from inquiries where customer_id is not null and not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo))),
    'departments',      (select count(*) from org_departments where active),
    'operating_systems',(select count(*) from operating_system where active),
    'kpis',             (select count(*) from employee_kpi where active),
    'kpis_measurable',  (select count(*) from employee_kpi where active and measure_sql is not null),
    'kpi_gaps_open',    (select count(*) from org_tasks where title like 'KPI missed:%' and status<>'done'),
    'open_tasks',       (select count(*) from org_tasks where status<>'done'),
    'needs_founder',    (select count(*) from org_tasks where status<>'done' and needs_founder),
    'approved_suppliers',(select count(*) from leads where approval_status='approved' and not is_demo),
    'sendable_pool',    (select coalesce(sum(sendable),0) from v_supply_gap),
    'categories_at_target',(select count(*) from v_supply_gap where approved>=10),
    'revenue_30d_aed',  (select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) from transactions where revealed_at>now()-interval '30 days' and not exists (select 1 from public.customers dc where dc.id = transactions.customer_id and dc.is_demo) and not exists (select 1 from public.leads dl where dl.id = transactions.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = transactions.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo)))),
    'ai_cost_30d_aed',  (select round(coalesce(sum(cost_aed),0),2) from ai_cost_log where occurred_at>now()-interval '30 days'),
    'knowledge_items',  (select count(*) from agent_knowledge),
    'knowledge_quarantined',(select count(*) from agent_knowledge where validation_status='quarantined'),
    'outcomes_pending', (select count(*) from outcome_record where verdict='pending'),
    'outcomes_improved',(select count(*) from outcome_record where verdict='improved'),
    'decisions_7d',     (select count(*) from decision_log where created_at>now()-interval '7 days'),
    'agent_runs_7d',    (select count(*) from agent_runs where started_at>now()-interval '7 days'),
    'error_rate_7d',    (select round(100.0*count(*) filter (where status='error')/nullif(count(*),0),2) from agent_runs where started_at>now()-interval '7 days'),
    'os_health',        (select jsonb_object_agg(os_key,health) from os_review where period=to_char(now(),'IYYY-"W"IW')),
    'indices',          (select jsonb_object_agg(index_name,score) from company_index where measured_on=current_date),
    'autonomy_enabled', (select value from app_secrets where key='agent_autonomy_enabled'),
    'invite_enabled', (select value from app_secrets where key='invite_enabled'),
      -- THE PULSE (3 Sep 2026): the signals the founder's one screen lacked, from the instruments that
      -- already measure them. Liveness (a cron that never fires), what is dead-lettered, what failed in
      -- the last day, what is parked behind the paid-model hold, what paged him, and the ad money.
      'crons_stale',        (select coalesce(jsonb_agg(jobname order by jobname), '[]'::jsonb) from public.v_cron_stale),
      'dead_letters_open',  (select count(*) from public.dead_letter where resolved_at is null),
      'failed_runs_24h',    (select count(*) from public.agent_runs where status = 'error' and started_at > now() - interval '24 hours'),
      'runs_skipped_24h',   (select count(*) from public.agent_runs where status = 'skipped' and started_at > now() - interval '24 hours'),
      'actions_held',       (select count(*) from public.action_execution where status = 'held'),
      'founder_alerts_24h', (select count(*) from public.founder_alerts where channel in ('email','whatsapp') and created_at > now() - interval '24 hours'),
      'ad_spend', jsonb_build_object(
        'active_campaigns', (select count(*) from public.ad_campaign_state where not is_demo and status = 'ACTIVE'),
        'active_daily_aed', (select coalesce(sum(daily_budget_aed), 0) from public.ad_campaign_state where not is_demo and status = 'ACTIVE'),
        'daily_ceiling_aed', public.fn_ad_spend_daily_ceiling(),
        'decisions_pending', (select count(*) from public.ad_decision where executed_at is null),
        'meta_token_present', exists (select 1 from app_secrets where key = 'meta_access_token' and coalesce(value, '') <> '')));

  insert into company_snapshot (snapshot_on, state) values (current_date, s)
  on conflict (snapshot_on) do update set state=excluded.state, created_at=now();

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_snapshot',now(),now(),'ok',jsonb_build_object('keys',(select count(*) from jsonb_object_keys(s))),
    'Company state snapshotted for '||current_date||'. Any past day can now be reconstructed.');
  return s;
end $function$;

-- 6. self-check. This file defines things, so it must end in NOTICE, never EXCEPTION (a raise would
--    roll the DDL back with it). Pure reads only: nothing is written, nothing to clean up.
do $$
declare v_bad int; v_dc int; v_dl int;
begin
  if not public.fn_is_demo_email('qd-probe-cust0@example.invalid') or public.fn_is_demo_email('management@quotesdone.com')
     or public.fn_is_demo_email('x@myexample.com') or not public.fn_is_demo_email('x@sub.example.net') then
    raise exception 'fn_is_demo_email disagrees with _shared/demo_identity.ts';
  end if;
  if not public.fn_is_demo_phone('+971 50 000 0042') or public.fn_is_demo_phone('+971501234567')
     or public.fn_is_demo_phone('+971500000100') then
    raise exception 'fn_is_demo_phone disagrees with _shared/demo_identity.ts';
  end if;
  select count(*) into v_dc from public.customers where is_demo;
  select count(*) into v_dl from public.leads where is_demo;
  select count(*) into v_bad from pg_trigger
   where tgname in ('a01_inquiry_match_demo_and_real_never_pair', 'a01_quote_demo_and_real_never_pair',
                    'zzzz_notifications_demo_capture') and not tgisinternal;
  if v_bad <> 3 then raise exception 'expected 3 demo triggers, found %', v_bad; end if;
  raise notice 'demo identities: % customer(s) and % lead(s) carry the marker; 3 guards installed', v_dc, v_dl;
end $$;
