-- THE COMMAND CHANNEL COULD REASON AND COULD NOT SEE.
--
-- Measured on PRODUCTION 13 Aug 2026 by sending four real messages through wa_inbound and reading
-- the replies back out of wa_messages:
--   "how many suppliers do we have and how many are verified"
--        -> "I don't have supplier count or verification-rate figures in my current live data"
--   "send me the financial report for last week"
--        -> "I don't have last week's financial figures in my live data snapshot"
-- Both numbers are one query away. agent_brain's LIVE DATA SNAPSHOT carries handoffs and department
-- state and nothing about the business itself, so the channel refuses to invent - correctly - and
-- then cannot answer. Every capability asked for on this channel is a data question SCOPED TO
-- WHOEVER IS ASKING: is my profile approved, how many inquiries did I miss, what was my last
-- quotation, how many suppliers received my inquiry, what is the average price I was quoted.
--
-- So the scoping is done HERE, in SQL, not in a prompt. The model receives only the facts its
-- sender is entitled to. A supplier's phone number can never produce another supplier's rows,
-- because the phone is the WHERE clause and the model never writes one.
--
-- PRE-REVEAL PRICE PRIVACY IS PRESERVED. A customer who has not paid the reveal fee gets a BAND
-- and a count, never the individual quotes and never a supplier name - the same rule the portal
-- enforces. Bands, not numbers, is the whole business model of a blind marketplace.
create or replace function public.fn_wa_context(p_audience text, p_phone text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_e164 text; v_lead record; v_cust record; v_out jsonb;
begin
  -- Normalise once: wa_from arrives as 'whatsapp:+9715...' and the tables hold several shapes.
  v_e164 := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  if v_e164 = '' then return jsonb_build_object('scope','none'); end if;

  -- ---------------------------------------------------------------- FOUNDER: the company itself
  if p_audience = 'founder' then
    return jsonb_build_object(
      'scope','company',
      'suppliers', jsonb_build_object(
        'leads_total',      (select count(*) from leads),
        'claimed',          (select count(*) from leads where coalesce(claimed,false)),
        'claimed_real',     (select count(*) from leads where coalesce(claimed,false)
                              and not (coalesce(company_name,'') ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid')),
        'approved',         (select count(*) from leads where approval_status = 'approved'),
        'licence_verified', (select count(*) from leads where coalesce(verified,false)),
        'with_email',       (select count(*) from leads where coalesce(btrim(email),'') <> '')),
      'invites', jsonb_build_object(
        'enabled',      (select value from app_secrets where key='invite_enabled'),
        'daily_cap',    (select value from app_secrets where key='invite_daily_cap'),
        'sent_today',   (select count(*) from leads where invited_at >= date_trunc('day', now() at time zone 'utc')),
        'sent_7d',      (select count(*) from leads where invited_at > now() - interval '7 days'),
        'bounced_7d',   (select count(*) from leads where invite_status='bounced' and invited_at > now() - interval '7 days'),
        'uncontacted',  (select count(*) from leads where invited_at is null and coalesce(btrim(email),'') <> '')),
      'demand', jsonb_build_object(
        'customers',        (select count(*) from customers),
        'inquiries_total',  (select count(*) from inquiries),
        'inquiries_7d',     (select count(*) from inquiries where created_at > now() - interval '7 days'),
        'quotes_total',     (select count(*) from quotes),
        'quotes_7d',        (select count(*) from quotes where created_at > now() - interval '7 days')),
      'money', jsonb_build_object(
        'transactions',      (select count(*) from transactions),
        'revealed',          (select count(*) from transactions where revealed_at is not null),
        'ai_spend_today_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= current_date),
        'ai_spend_month_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= date_trunc('month', now()))),
      'health', jsonb_build_object(
        'agent_runs_failed_24h', (select count(*) from agent_runs where status in ('error','failed') and started_at > now() - interval '24 hours'),
        'actions_pending',       (select count(*) from agent_actions where status in ('pending','needs_review')),
        'escalations_open',      (select count(*) from agent_actions where coalesce(escalated,false) and status in ('pending','needs_review'))));
  end if;

  -- ---------------------------------------------------------------- SUPPLIER: only their own row
  if p_audience = 'supplier' then
    select * into v_lead from leads l
     where regexp_replace(coalesce(l.phone_e164, l.phone, ''), '[^0-9]', '', 'g') = v_e164
        or regexp_replace(coalesce(l.whatsapp,''), '[^0-9]', '', 'g') = v_e164
     order by coalesce(l.claimed,false) desc, l.id limit 1;
    if not found then return jsonb_build_object('scope','supplier','known', false); end if;

    return jsonb_build_object(
      'scope','supplier', 'known', true,
      'company', v_lead.company_name,
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
     where regexp_replace(coalesce(c.phone,''), '[^0-9]', '', 'g') = v_e164 limit 1;
    if not found then return jsonb_build_object('scope','customer','known', false); end if;

    return jsonb_build_object(
      'scope','customer', 'known', true,
      'name', v_cust.full_name,
      'profile', jsonb_build_object(
        'phone_verified', coalesce(v_cust.phone_verified,false),
        'email_verified', coalesce(v_cust.email_verified,false),
        'terms_signed',   (v_cust.signed_terms_url is not null)),
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

revoke all on function public.fn_wa_context(text, text) from public;
revoke all on function public.fn_wa_context(text, text) from anon;
