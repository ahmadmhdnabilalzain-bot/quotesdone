-- THE ASSISTANT COULD NOT SEE WHO WAS ASKING
--
-- Measured on production, 13 Aug 2026 01:04–01:05 UTC. The founder, signed in as a customer, on
-- /me, asked the site widget four questions. `public.assistant_logs` holds all four:
--
--   "what is my email registered"  -> "I don't have access to your account details or email
--                                      address... log in to your account at /me"
--   "do i have any inquiries"      -> "I can't see your account or your inquiries — only you can
--                                      view those when you log in."
--
-- He WAS logged in. He WAS on /me. The assistant told him to go and do the thing he had just done,
-- twice, because `site_assistant` takes `{message, path, history}` and nothing else: no JWT, no
-- identity, no scope. Its only grounding is a keyword search over `company_faq` plus two hardcoded
-- FACTS blobs. It is structurally incapable of answering a question about the person asking it.
--
-- `wa_inbound` does not have this problem, because on 13 Aug it was given `fn_wa_context`, which
-- derives the audience's own rows IN SQL from their phone number — so a prompt can never reach
-- another person's data, however it is worded.
--
-- THE ONLY REASON THAT FUNCTION COULD NOT SERVE THE WEB PORTAL IS THE IDENTIFIER. WhatsApp knows a
-- phone number. A browser session knows an email address. Everything else — the scoping, the
-- pre-reveal band, the supplier's own row and nobody else's — is already correct and already
-- enforced here rather than in a prompt.
--
-- So this widens the identifier and changes nothing else about who can see what: `p_phone` now
-- accepts a phone number OR an email address, and the caller's audience still decides which table
-- is consulted. A customer identified by email reaches exactly the rows they reached by phone.
--
-- WHY NOT A SECOND FUNCTION. A parallel `fn_portal_context` would be a second copy of the
-- pre-reveal band rule — the one rule in this product that must never drift. Two copies of a
-- privacy rule is one copy waiting to be forgotten. One function, one rule, two identifiers.
--
-- CREATE OR REPLACE preserves the ACL ({postgres,service_role}); no GRANT/REVOKE belongs here.

create or replace function public.fn_wa_context(p_audience text, p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_e164 text; v_email text; v_lead record; v_cust record;
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
        'escalations_open',      (select count(*) from agent_actions where coalesce(escalated,false) and status in ('pending','needs_review'))),
      -- THE PART THAT IS HIS. Named so the model cannot read it as more company telemetry: these
      -- are items no agent is allowed to settle, and they are waiting for him specifically.
      'your_decision_queue', public.fn_founder_queue(12));
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

comment on function public.fn_wa_context(text, text) is
  'Scoped, audience-correct context for a conversational surface. p_phone accepts a phone number OR an email address so the same SQL-enforced scoping serves WhatsApp (phone) and the signed-in web portal (email). The pre-reveal rule lives here and nowhere else: before a reveal a customer gets a count and a band rounded to the nearest 1,000, never an individual quote and never a supplier name.';
