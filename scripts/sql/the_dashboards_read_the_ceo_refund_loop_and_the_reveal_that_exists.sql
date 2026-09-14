-- THE DASHBOARDS READ THE CEO'S REFUND LOOP, THE REVEAL THAT EXISTS, AND NO DEMO ROW
-- 14 Sep 2026. Assigned: ceo.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production htdblwldjkcgjvmqkbeh, pg_proc and information_schema):
--   1. fn_ops_dashboard() called the founder's refund-approval counter (DROPPED.txt line 481) outside
--      any handler. That routine is absent from pg_proc (removed 9 Sep with the founder-approval
--      machinery), so EVERY call to fn_ops_dashboard threw.
--   2. fn_wa_context(text,text), founder branch, called the founder's decision-queue reader
--      (DROPPED.txt line 480). Also absent since 9 Sep, so the founder's WhatsApp context threw.
--   3. fn_os_dashboard_viz() counted quotes.revealed. public.quotes has no such column. The first body
--      measured wrapped the pipeline in `exception when others` and returned an empty array; the body
--      live at apply time (the e2e-harness demo rewrite, applied mid-session) dropped that handler, so
--      every call threw.
--   4. v_supply_gap (read by fn_company_snapshot) counted demo leads in its supplier pool.
--
-- WHAT REPLACED THE MISSING CALLEES
--   Refunds are the CEO's (founder, 8 and 14 Sep 2026; payments_are_the_accountant_and_the_seats_
--   close_every_refund_together.sql). A refund waiting for a decision is a public.refunds row in
--   status 'requested'; the CEO's loop on it is public.refund_ceo_review (one row per cycle). The
--   founder decides nothing in that flow: the only thing that reaches him is refund_ceo_summary, sent
--   when a loop escalates (outcome 'escalated': three cycles or a missed deadline). So:
--     * fn_ops_dashboard.operations.escalations = open refunds whose latest CEO review escalated
--       + severe founder alerts in 24h (the old meaning, "what reaches him", kept). New key
--       operations.refunds_with_ceo = open refunds the CEO holds.
--     * fn_wa_context founder: your_decision_queue is replaced by refunds_with_the_ceo, which says in
--       its own text that nothing in it waits on him.
--   Pipeline "Revealed": a public.transactions row is the reveal (it is written when the customer pays
--   the reveal fee), so the stage counts transactions.
--
-- DEMO EXCLUSION
--   Every business count in fn_ops_dashboard and the founder branch of fn_wa_context excludes demo
--   customers, suppliers and inquiries, and every quote, transaction, refund and due hanging off them.
--   It reads the derived markers customers.is_demo, leads.is_demo and fn_inquiry_is_demo(uuid)
--   (demo_identities_are_marked_and_never_reach_a_real_person.sql). Each routine builds the three id
--   sets once and every count says `(x = any (set)) is not true`, which keeps a NULL foreign key
--   counted rather than silently dropping it.
--
-- NOT TOUCHED: fn_contact_timeline and fn_ceo_weekly_figures (another branch owns them).
-- CREATE OR REPLACE keeps each routine's ACL (service_role only, measured), so there is no revoke here.

-- 1. fn_ops_dashboard --------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ops_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  active_rfqs int; rfqs_today int; done_today int; ttfq numeric; qpr numeric;
  accept_rate numeric; conv numeric;
  rev_today numeric; rev_month numeric; pending_fees numeric; outstanding_inv int; cash_recv numeric;
  ai_conf numeric; waiting int; onboard_q int; disputes int; escalations int; held int; with_ceo int;
  uptime numeric; queue_size int; failed int; last_backup timestamptz; api_lat numeric;
  health jsonb;
  v_dc uuid[]; v_dl bigint[]; v_di uuid[];
begin
  -- DEMO: the three id sets every business count below leaves out.
  select coalesce(array_agg(id), '{}') into v_dc from customers where is_demo;
  select coalesce(array_agg(id), '{}') into v_dl from leads where is_demo;
  select coalesce(array_agg(id), '{}') into v_di from inquiries where public.fn_inquiry_is_demo(id);

  -- MARKETPLACE
  select count(*) into active_rfqs from inquiries where status not in ('completed','accepted','closed','cancelled') and (id = any (v_di)) is not true;
  select count(*) into rfqs_today from inquiries where created_at::date=current_date and (id = any (v_di)) is not true;
  select count(*) into done_today from inquiries where ((completed_at::date=current_date) or (status in ('completed','accepted') and stage_changed_at::date=current_date)) and (id = any (v_di)) is not true;
  select round(avg(extract(epoch from (fq - ic))/3600.0),1) into ttfq from (
    select i.created_at ic, min(q.created_at) fq from inquiries i join quotes q on q.inquiry_id=i.id
    where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true and (q.supplier_id = any (v_dl)) is not true
    group by i.id) z where fq is not null;
  select round(avg(qc),1) into qpr from (select count(*) qc from quotes q join inquiries i on i.id=q.inquiry_id
    where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true and (q.supplier_id = any (v_dl)) is not true
    group by q.inquiry_id) z;
  select round(avg(nullif(rv_response_rate,0)) ,1) into accept_rate from leads where coalesce(rv_reveals,0)>0 and (id = any (v_dl)) is not true;
  select round(100.0*count(distinct t.inquiry_id)/nullif(count(distinct i.id),0),1) into conv
    from inquiries i left join transactions t on t.inquiry_id=i.id and (t.supplier_id = any (v_dl)) is not true
   where i.created_at>=now()-interval '30 days' and (i.id = any (v_di)) is not true;

  -- REVENUE
  select coalesce(sum(reveal_fee),0) into rev_today from transactions where revealed_at::date=current_date and coalesce(refund_status,'')<>'approved'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  select coalesce(sum(reveal_fee),0) into rev_month from transactions where date_trunc('month',revealed_at)=date_trunc('month',now()) and coalesce(refund_status,'')<>'approved'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  begin select coalesce(sum(amount_due),0) into pending_fees from supplier_dues where coalesce(status,'')<>'paid' and (supplier_id = any (v_dl)) is not true; exception when others then pending_fees:=0; end;
  begin select count(*) into outstanding_inv from reveal_invoices ri left join transactions t on t.id=ri.transaction_id where coalesce(t.fee_status,'')<>'paid'
     and (t.customer_id = any (v_dc)) is not true and (t.supplier_id = any (v_dl)) is not true and (t.inquiry_id = any (v_di)) is not true; exception when others then outstanding_inv:=0; end;
  select coalesce(sum(reveal_fee),0) into cash_recv from transactions where coalesce(fee_status,'')='paid'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;

  -- OPERATIONS
  begin select public.fn_health_index() into health; exception when others then health:=null; end;
  select round(100.0*count(*) filter (where nullif(quality->>'score','')::numeric>=60)/nullif(count(*) filter (where quality is not null),0),1) into ai_conf
    from quotes where created_at>=now()-interval '7 days' and (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true;
  select count(*) into waiting from inquiries where status in ('clarify','clarifying','awaiting_customer','needs_info') and (id = any (v_di)) is not true;
  select count(*) into onboard_q from leads where approval_status='pending' and (id = any (v_dl)) is not true;
  select count(*) into disputes from transactions where refund_status='requested'
     and (customer_id = any (v_dc)) is not true and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true;
  -- REFUNDS ARE THE CEO'S. Open = a refunds row still 'requested'. What reaches the founder is only the
  -- CEO's summary when that refund's latest review cycle escalated, plus severe alerts.
  select count(*), count(*) filter (where rv.outcome = 'escalated') into with_ceo, escalations
    from refunds r
    left join lateral (select x.outcome from refund_ceo_review x where x.refund_id = r.id order by x.cycle desc limit 1) rv on true
   where r.status = 'requested'
     and (r.customer_id = any (v_dc)) is not true and (r.supplier_lead_id = any (v_dl)) is not true and (r.inquiry_id = any (v_di)) is not true;
  escalations := escalations
        + (select count(*) from founder_alerts where public.fn_alert_severe(level) and created_at>=now()-interval '24 hours');
  select count(*) into held from agent_actions a left join agent_action_kind_policy p on p.kind=a.kind
   where a.status in ('pending','needs_review') and coalesce(p.policy,'')<>'founder';

  -- INFRASTRUCTURE
  select round(100.0*count(*) filter (where ok)/nullif(count(*),0),1) into uptime from health_checks where created_at>=now()-interval '24 hours';
  select count(*) into queue_size from notifications where coalesce(status,'')in('queued','pending','');
  begin select count(*) into failed from agent_runs where status='error' and coalesce(finished_at,started_at)>=now()-interval '24 hours'; exception when others then failed:=0; end;
  select max(updated_at) into last_backup from storage.objects where bucket_id='backups' and name like '%/_manifest.json';
  select round(avg(latency_ms),0) into api_lat from health_checks where created_at>=now()-interval '1 hour' and latency_ms is not null;

  return jsonb_build_object(
    'as_of', now(),
    'marketplace', jsonb_build_object('active_rfqs',active_rfqs,'rfqs_today',rfqs_today,'completed_today',done_today,
        'avg_hours_to_first_quote',ttfq,'avg_quotes_per_rfq',qpr,'supplier_acceptance_pct',accept_rate,'conversion_pct',conv),
    'revenue', jsonb_build_object('today_aed',rev_today,'month_aed',rev_month,'pending_fees_aed',pending_fees,
        'outstanding_invoices',outstanding_inv,'cash_received_aed',cash_recv),
    'operations', jsonb_build_object('ai_confidence_pct',ai_conf,'rfqs_waiting_clarification',waiting,
        'onboarding_queue',onboard_q,'disputes',disputes,'escalations',escalations,'refunds_with_ceo',with_ceo,'held_with_roles',held),
    'infrastructure', jsonb_build_object('uptime_pct',uptime,'queue_size',queue_size,'failed_jobs_24h',failed,
        'backup_age_hours', case when last_backup is null then null else round(extract(epoch from (now()-last_backup))/3600.0,1) end,
        'api_latency_ms',api_lat),
    'health_index', coalesce(health->>'index',null));
end $function$;

-- 2. fn_wa_context -----------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wa_context(p_audience text, p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_e164 text; v_email text; v_lead record; v_cust record;
        v_dc uuid[]; v_dl bigint[]; v_di uuid[]; v_refunds jsonb;
begin
  -- ONE IDENTIFIER, TWO SHAPES. wa_from arrives as 'whatsapp:+9715...'; a browser session arrives
  -- as an email address. An '@' is the discriminator: nothing that is a phone number contains one,
  -- and an address stripped of non-digits is meaningless, which is how a mis-shaped identifier used
  -- to fall through to "known: false" instead of an answer.
  v_email := nullif(lower(btrim(coalesce(p_phone, ''))), '');
  if v_email is not null and position('@' in v_email) = 0 then v_email := null; end if;
  v_e164 := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if v_e164 = '' and v_email is null then return jsonb_build_object('scope','none'); end if;

  -- ---------------------------------------------------------------- FOUNDER: the company itself
  if p_audience = 'founder' then
    -- DEMO: left out of every business figure below.
    select coalesce(array_agg(id), '{}') into v_dc from customers where is_demo;
    select coalesce(array_agg(id), '{}') into v_dl from leads where is_demo;
    select coalesce(array_agg(id), '{}') into v_di from inquiries where public.fn_inquiry_is_demo(id);

    -- REFUNDS ARE THE CEO'S, NOT HIS. The old decision-queue reader (dropped 9 Sep) listed refunds as
    -- waiting on him; since 14 Sep the CEO decides every refund and the founder only receives the CEO's summary
    -- when a review loop escalates. This is what the CEO holds, stated as information.
    with open_r as (
      select r.id, r.requested_at, r.amount_fils, r.reason_code, rv.cycle, rv.outcome
        from refunds r
        left join lateral (select x.cycle, x.outcome from refund_ceo_review x where x.refund_id = r.id order by x.cycle desc limit 1) rv on true
       where r.status = 'requested'
         and (r.customer_id = any (v_dc)) is not true and (r.supplier_lead_id = any (v_dl)) is not true and (r.inquiry_id = any (v_di)) is not true)
    select jsonb_build_object(
      'who_decides', 'ceo',
      'note', 'Every refund is decided by the CEO. You receive his short summary only when a review loop escalates (three cycles or a missed deadline). Nothing here waits on you.',
      'open', (select count(*) from open_r),
      'escalated', (select count(*) from open_r where outcome = 'escalated'),
      'items', coalesce((select jsonb_agg(jsonb_build_object('refund_id', z.id, 'requested_at', z.requested_at,
                          'amount_aed', round(z.amount_fils / 100.0, 2), 'reason', z.reason_code,
                          'review_cycle', z.cycle, 'review_outcome', z.outcome) order by z.requested_at)
                           from (select * from open_r order by requested_at limit 12) z), '[]'::jsonb))
      into v_refunds;

    return jsonb_build_object(
      'scope','company',
      'suppliers', jsonb_build_object(
        'leads_total',      (select count(*) from leads where (id = any (v_dl)) is not true),
        'claimed',          (select count(*) from leads where coalesce(claimed,false) and (id = any (v_dl)) is not true),
        'claimed_real',     (select count(*) from leads where coalesce(claimed,false) and (id = any (v_dl)) is not true
                              and not (coalesce(company_name,'') ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid')),
        'approved',         (select count(*) from leads where approval_status = 'approved' and (id = any (v_dl)) is not true),
        'licence_verified', (select count(*) from leads where coalesce(verified,false) and (id = any (v_dl)) is not true),
        'with_email',       (select count(*) from leads where coalesce(btrim(email),'') <> '' and (id = any (v_dl)) is not true)),
      'invites', jsonb_build_object(
        'enabled',      (select value from app_secrets where key='invite_enabled'),
        'daily_cap',    (select value from app_secrets where key='invite_daily_cap'),
        'sent_today',   (select count(*) from leads where invited_at >= date_trunc('day', now() at time zone 'utc') and (id = any (v_dl)) is not true),
        'sent_7d',      (select count(*) from leads where invited_at > now() - interval '7 days' and (id = any (v_dl)) is not true),
        'bounced_7d',   (select count(*) from leads where invite_status='bounced' and invited_at > now() - interval '7 days' and (id = any (v_dl)) is not true),
        'uncontacted',  (select count(*) from leads where invited_at is null and coalesce(btrim(email),'') <> '' and (id = any (v_dl)) is not true)),
      'demand', jsonb_build_object(
        'customers',        (select count(*) from customers where (id = any (v_dc)) is not true),
        'inquiries_total',  (select count(*) from inquiries where (id = any (v_di)) is not true),
        'inquiries_7d',     (select count(*) from inquiries where created_at > now() - interval '7 days' and (id = any (v_di)) is not true),
        'quotes_total',     (select count(*) from quotes where (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true),
        'quotes_7d',        (select count(*) from quotes where created_at > now() - interval '7 days'
                               and (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true)),
      'money', jsonb_build_object(
        'transactions',      (select count(*) from transactions where (customer_id = any (v_dc)) is not true
                                and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true),
        'revealed',          (select count(*) from transactions where revealed_at is not null and (customer_id = any (v_dc)) is not true
                                and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true),
        'ai_spend_today_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= current_date),
        'ai_spend_month_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= date_trunc('month', now()))),
      'health', jsonb_build_object(
        'agent_runs_failed_24h', (select count(*) from agent_runs where status in ('error','failed') and started_at > now() - interval '24 hours'),
        'actions_pending',       (select count(*) from agent_actions where status in ('pending','needs_review')),
        'escalations_open',      (select count(*) from agent_actions where coalesce(escalated,false) and status in ('pending','needs_review'))),
      'refunds_with_the_ceo', v_refunds);
  end if;

  -- ---------------------------------------------------------------- SUPPLIER: only their own row
  if p_audience = 'supplier' then
    select * into v_lead from leads l
     where (v_e164 <> '' and (regexp_replace(coalesce(l.phone_e164, l.phone, ''), '[^0-9]', '', 'g') = v_e164
                           or regexp_replace(coalesce(l.whatsapp,''), '[^0-9]', '', 'g') = v_e164))
        or (v_email is not null and (lower(coalesce(l.claimed_by,'')) = v_email or lower(coalesce(l.email,'')) = v_email))
     order by coalesce(l.claimed,false) desc, l.id limit 1;
    if not found then return jsonb_build_object('scope','supplier','known', false); end if;

    return jsonb_build_object(
      'scope','supplier', 'known', true,
      'company', v_lead.company_name,
      'account', jsonb_build_object('email', v_lead.claimed_by, 'phone', coalesce(v_lead.phone_e164, v_lead.phone)),
      'profile', jsonb_build_object(
        'claimed',          coalesce(v_lead.claimed,false),
        'approval_status',  coalesce(v_lead.approval_status,'not submitted'),
        'verified',         coalesce(v_lead.verified,false),
        'email_verified',   coalesce(v_lead.owner_email_verified,false),
        'phone_verified',   coalesce(v_lead.owner_phone_verified,false),
        'trade_licence_no', v_lead.trade_license_no,
        'licence_authority',v_lead.license_authority,
        'licence_expiry',   v_lead.license_expiry,
        'licence_on_file',  (v_lead.license_doc_path is not null),
        'blocked_because',  v_lead.licence_gate_reason),
      'work', jsonb_build_object(
        'inquiries_received',  (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id),
        'inquiries_quoted',    (select count(distinct q.inquiry_id) from quotes q where q.supplier_id = v_lead.id),
        'inquiries_missed',    (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id
                                  and not exists (select 1 from quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = v_lead.id)),
        'quotes_submitted',    (select count(*) from quotes q where q.supplier_id = v_lead.id),
        'last_quote',          (select jsonb_build_object('amount_aed', q.quote_amount, 'status', q.status, 'when', q.created_at)
                                  from quotes q where q.supplier_id = v_lead.id order by q.created_at desc limit 1),
        'jobs_won',            (select count(*) from quotes q where q.supplier_id = v_lead.id and q.status = 'accepted')));
  end if;

  -- ---------------------------------------------------------------- CUSTOMER: only their own rows
  if p_audience = 'customer' then
    select * into v_cust from customers c
     where (v_e164 <> '' and regexp_replace(coalesce(c.phone,''), '[^0-9]', '', 'g') = v_e164)
        or (v_email is not null and lower(coalesce(c.email,'')) = v_email)
     limit 1;
    if not found then return jsonb_build_object('scope','customer','known', false); end if;

    return jsonb_build_object(
      'scope','customer', 'known', true,
      'name', v_cust.full_name,
      -- WHAT WE HOLD FOR THEM. "what is my email registered" was one of the four questions the
      -- assistant could not answer, and the answer was one column away the whole time.
      'account', jsonb_build_object(
        'email', v_cust.email, 'phone', v_cust.phone,
        'language', v_cust.locale, 'industry', v_cust.industry,
        'customer_since', v_cust.created_at),
      'profile', jsonb_build_object(
        'phone_verified', coalesce(v_cust.phone_verified,false),
        'email_verified', coalesce(v_cust.email_verified,false),
        'terms_signed',   (v_cust.signed_terms_url is not null),
        -- create_inquiry's own gate, stated as the fact it is, so the assistant answers "can I post
        -- a request" with the truth rather than an encouragement.
        'can_post_request', (coalesce(v_cust.phone_verified,false) and coalesce(v_cust.email_verified,false)
                             and v_cust.signed_terms_url is not null)),
      'inquiries', coalesce((
        select jsonb_agg(x order by x->>'created_at' desc) from (
          select jsonb_build_object(
            'id', i.id, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
            'created_at', i.created_at,
            'suppliers_received', (select count(*) from inquiry_matches m where m.inquiry_id = i.id),
            'quotes_received',    (select count(*) from quotes q where q.inquiry_id = i.id and q.status='submitted'),
            -- PRE-REVEAL: a band and a count, never the individual quotes and never a supplier name.
            'revealed', exists (select 1 from transactions t where t.inquiry_id = i.id and t.revealed_at is not null),
            'price_band', case
              when exists (select 1 from transactions t where t.inquiry_id = i.id and t.revealed_at is not null)
                then (select jsonb_build_object('low', min(q.quote_amount), 'high', max(q.quote_amount), 'average', round(avg(q.quote_amount)::numeric,0))
                        from quotes q where q.inquiry_id = i.id and q.status='submitted')
              else (select case when count(*) = 0 then null
                                else jsonb_build_object('average_rounded_to_nearest_1000',
                                        round(avg(q.quote_amount)::numeric / 1000) * 1000, 'note',
                                        'rounded band only - the exact quotes and the supplier names unlock when you reveal')
                           end from quotes q where q.inquiry_id = i.id and q.status='submitted') end) as x
          from inquiries i where i.customer_id = v_cust.id order by i.created_at desc limit 10) z), '[]'::jsonb));
  end if;

  return jsonb_build_object('scope','unknown');
end $function$;

-- 3. fn_os_dashboard_viz: the pipeline's Revealed stage -----------------------------------------------
-- Started from the body live at apply time (the e2e-harness demo rewrite). Only the "Revealed" stage
-- changes: it counts transactions (a transactions row IS the reveal; quotes has no revealed column),
-- with the same demo rule that body applies to every other stage.
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

  j_pipeline := jsonb_build_array(
    jsonb_build_object('stage','New', 'n', (select count(*) from inquiries where not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo)))),
    jsonb_build_object('stage','Matched', 'n', (select count(distinct inquiry_id) from quotes where not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo))))),
    jsonb_build_object('stage','Quoted', 'n', (select count(*) from quotes where not exists (select 1 from public.leads dl where dl.id = quotes.supplier_id and dl.is_demo) and not exists (select 1 from public.inquiries di where di.id = quotes.inquiry_id and (di.provenance->>'qd_run' is not null or di.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = di.customer_id and dc.is_demo))))),
    jsonb_build_object('stage','Revealed', 'n', (select count(*) from transactions t where not exists (select 1 from public.customers dc where dc.id = t.customer_id and dc.is_demo) and not exists (select 1 from public.leads dl where dl.id = t.supplier_id and dl.is_demo) and not public.fn_inquiry_is_demo(t.inquiry_id))),
    jsonb_build_object('stage','Won', 'n', (select count(*) from inquiries where status = 'won' and not (inquiries.provenance->>'qd_run' is not null or inquiries.brief_source = 'qd_demo_fixture' or exists (select 1 from public.customers dc where dc.id = inquiries.customer_id and dc.is_demo))))
  );

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

-- 4. v_supply_gap: a demo lead is not part of any category's supplier pool --------------------------
-- The demo marker sits on the join, so every one of the four FILTERs (all read l.*) drops the row.
CREATE OR REPLACE VIEW public.v_supply_gap AS
 WITH pool AS (
         SELECT c.slug,
            c.name,
            c.num,
            count(DISTINCT lc.lead_id) FILTER (WHERE ((l.email IS NOT NULL) AND (l.email <> ''::text) AND (COALESCE(l.banned, false) = false))) AS sendable,
            count(DISTINCT lc.lead_id) FILTER (WHERE (l.invite_status IS NOT NULL)) AS invited,
            count(DISTINCT lc.lead_id) FILTER (WHERE l.claimed) AS claimed,
            count(DISTINCT lc.lead_id) FILTER (WHERE (l.approval_status = 'approved'::text)) AS approved
           FROM ((catalog_supplier_categories c
             LEFT JOIN lead_category lc ON ((lc.slug = c.slug)))
             LEFT JOIN leads l ON (((l.id = lc.lead_id) AND (NOT l.is_demo))))
          GROUP BY c.slug, c.name, c.num
        )
 SELECT slug,
    name,
    num,
    sendable,
    invited,
    claimed,
    approved,
    GREATEST((0)::bigint, (10 - approved)) AS gap_to_target,
    (ceil(((GREATEST((0)::bigint, (10 - approved)))::numeric / 0.05)))::integer AS sendable_needed_at_5pct,
    GREATEST((0)::bigint, ((ceil(((GREATEST((0)::bigint, (10 - approved)))::numeric / 0.05)))::integer - sendable)) AS sendable_shortfall,
        CASE
            WHEN (approved >= 10) THEN 'TARGET MET'::text
            WHEN (sendable = 0) THEN 'NO POOL - must source from scratch'::text
            WHEN (sendable < (ceil(((GREATEST((0)::bigint, (10 - approved)))::numeric / 0.05)))::integer) THEN 'POOL TOO THIN - scrape more'::text
            WHEN (invited = 0) THEN 'READY - not yet invited'::text
            ELSE 'IN PROGRESS'::text
        END AS status
   FROM pool;
