-- THE SUPPLIER IS KNOWN ON EVERY CHANNEL: HIS TRADES, HIS EMIRATES, HIS JOBS AND WHY NOT MORE.
--
-- Seat: customer_support. 16 Nov 2026. Founder ledgers 1711-1713: "in a real company everyone knows what the other is doing
-- because they are colleagues." The independent audit of that day (who knows what, items 5-7, READ from origin/main 55489dde7)
-- found the supplier branch of fn_wa_context, the one reading WhatsApp and the signed-in widget give a supplier, held his
-- licence, approval and counts but no trade, no service, no emirate and nothing of why a request did or did not reach him. A new
-- supplier asking "why am I getting no jobs?" could not be answered by anyone. The e-mail reply (email_triage/account_facts.ts)
-- and the portal quotation chat (supplier_api reviewVoice) kept their own reads and did not see his licence or holds at all.
--
-- WHAT THIS FILE DOES (fn_wa_context, supplier branch only; the founder and customer branches are copied unchanged from
-- a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.sql, MANIFEST line 2237)
--   * profile: licence_expired and licence_days_left beside the expiry it already gave (Asia/Dubai date).
--   * services: what the matcher reads (fn_match_capability): his trades with their labels and whether each is OPEN to
--     customers (trade_customer_opening, fn_ceo_trade_opening_tick), the trades he excluded, his confirmed services, whether
--     they are confirmed (confirmed_at; the matcher skips an unconfirmed supplier), and the emirates he covers
--     (coverage_emirates plus leads.service_emirates, as the matcher's `loc`; none stated = UAE-wide).
--   * matching: jobs sent to him in 30 days, requests posted in 30 days in his trades and emirates, his availability, strikes
--     and the strike limit, the matching block and its reason, his collaboration record (supplier_collaboration), and
--     why_no_jobs: each gate of fn_is_matchable / fn_supplier_available / confirmed_at that holds him back NOW, and, when
--     nothing reached him in 30 days, the demand reasons (no trade open, no request in his trades and emirates, requests
--     that went to suppliers fitting the asked service or emirate better). Every reason is an EXISTING rule, read; none is new.
--   * recent_jobs: the last 15 requests sent to him, by job number, with trade, emirate, the request's status and HIS OWN
--     quote's status. Never another supplier, never a customer's name or contact.
-- The doors that read it: WhatsApp (wa_inbound/identify.ts, compose.ts), the signed-in widget (site_assistant/turn_facts.ts),
-- the supplier e-mail reply (email_triage/account_facts.ts, which now reads this instead of leads/inquiry_matches itself) and
-- the portal quotation chat (supplier_api/actions/quote_review_chat.ts reviewVoice), all through _shared/supplier_known.ts.
-- SECURITY DEFINER, search_path pinned, EXECUTE revoked (CREATE OR REPLACE keeps the ACL; the revoke is restated anyway).
-- Probe: the_supplier_is_known_on_every_channel_probe.sql (LOCAL Postgres 16 only). No model is called.


-- ---------------------------------------------------------------------------------------------------------------------
-- fn_wa_context: the supplier branch reads his trades, emirates, jobs and why not more (founder and customer branches unchanged)
create or replace function public.fn_wa_context(p_audience text, p_phone text)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp'
as $function$
declare v_e164 text; v_email text; v_lead record; v_cust record;
        v_dc uuid[]; v_dl bigint[]; v_di uuid[]; v_refunds jsonb;
        -- the supplier's matching facts (16 Nov 2026)
        v_cap public.supplier_capabilities%rowtype; v_col public.supplier_collaboration%rowtype;
        v_av_state text; v_av_until date; v_today date := (now() at time zone 'Asia/Dubai')::date;
        v_trades text[] := '{}'; v_areas text[] := '{}'; v_limit int; v_jobs30 int := 0; v_demand30 int := 0;
        v_open text[] := '{}'; v_why jsonb := '[]'::jsonb;
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
     where (v_e164 <> '' and l.id = (select o.lead_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'supplier'))
        or (v_email is not null and (lower(coalesce(l.claimed_by,'')) = v_email or lower(coalesce(l.email,'')) = v_email))
     order by coalesce(l.claimed,false) desc, l.id limit 1;
    if not found then return jsonb_build_object('scope','supplier','known', false); end if;

    -- WHAT THE MATCHER READS ABOUT HIM (fn_match_capability's cand/loc, fn_is_matchable, fn_supplier_available), read here
    -- so that every door can answer "why am I getting no jobs?" from the rules that decide it. No rule is added.
    select * into v_cap from supplier_capabilities sc where sc.supplier_id = v_lead.id;
    select * into v_col from supplier_collaboration c where c.lead_id = v_lead.id;
    select av.state, av.busy_until into v_av_state, v_av_until from supplier_availability av where av.supplier_id = v_lead.id;
    v_trades := coalesce(v_cap.trades, '{}'::text[]);
    v_areas  := array(select distinct lower(btrim(e)) from unnest(coalesce(v_cap.coverage_emirates, '{}'::text[])
                                                           || coalesce(v_lead.service_emirates, '{}'::text[])) e
                       where nullif(btrim(e), '') is not null order by 1);
    v_limit  := public.fn_matching_strike_limit();
    v_open   := array(select o.trade from trade_customer_opening o where o.trade = any (v_trades) and o.is_open order by 1);
    v_jobs30 := (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id and m.sent_at > now() - interval '30 days');
    -- requests customers posted in 30 days in his trades (the matcher's routing trades, or the intake category) and, when he
    -- states emirates, in one of them; a demo supplier counts demo requests and a real one real requests (never each other's)
    v_demand30 := (select count(*) from inquiries i
                    where i.created_at > now() - interval '30 days'
                      and cardinality(v_trades) > 0
                      and (lower(coalesce(i.category, '')) = any (v_trades)
                           or exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(i.routing -> 'trades') = 'array'
                                                                               then i.routing -> 'trades' else '[]'::jsonb end) t
                                       where t = any (v_trades)))
                      and (cardinality(v_areas) = 0 or lower(btrim(coalesce(i.emirate, ''))) = any (v_areas))
                      and public.fn_inquiry_is_demo(i.id) = coalesce(v_lead.is_demo, false));

    -- WHY NOT MORE: every gate that holds him back now, in the matcher's own order, then (nothing in 30 days) the demand.
    select coalesce(jsonb_agg(jsonb_build_object('code', r.code, 'says', r.says) order by r.n), '[]'::jsonb) into v_why
      from (values
        (1, 'not_registered', not coalesce(v_lead.claimed, false),
            'He has not registered his company yet, so no request can be sent to him.'),
        (2, 'not_approved', coalesce(v_lead.approval_status, '') <> 'approved',
            'His registration is not approved yet (status: ' || coalesce(v_lead.approval_status, 'not submitted')
            || coalesce('; held for: ' || v_lead.licence_gate_reason, '') || '). Requests go only to approved suppliers; the portal shows what is holding it.'),
        (3, 'licence_not_verified', not coalesce(v_lead.verified, false),
            'His trade licence is not verified yet. Requests go only to suppliers with a verified licence.'),
        (4, 'licence_expired', v_lead.license_expiry is not null and v_lead.license_expiry < v_today,
            'His trade licence expired on ' || to_char(v_lead.license_expiry, 'DD Mon YYYY') || '. He should upload the renewed licence in the Documents tab.'),
        (5, 'account_suspended', coalesce(v_lead.banned, false),
            'His account is suspended from receiving requests.'),
        (6, 'listing_closed', coalesce(v_lead.permanently_closed, false),
            'His listing is marked as a closed business, so no request is sent to it.'),
        (7, 'held_for_unanswered_requests', v_lead.collaboration_hold_at is not null,
            'Matching is paused because ' || coalesce(v_col.consecutive_ignored, 3) || ' quotations in a row were left unanswered at the customer''s decision; it is lifted only on review.'),
        (8, 'matching_paused', coalesce(v_lead.matching_blocked, false) and v_lead.collaboration_hold_at is null,
            case v_lead.matching_block_reason
              when 'licence_expired'   then 'Matching is paused because his trade licence expired. He should upload the renewed licence in the Documents tab; it resumes when the licence is verified again.'
              when 'insurance_expired' then 'Matching is paused because his insurance certificate expired. He should upload the renewed certificate in the Documents tab; it resumes when it is verified again.'
              else 'Matching is paused on his account; our team will explain; he can reply here to reach support.'
            end),
        (9, 'strike_limit', coalesce(v_lead.chat_strikes, 0) >= v_limit,
            'Matching is paused: he has ' || coalesce(v_lead.chat_strikes, 0) || ' unanswered-request strikes (limit ' || v_limit || '). A quotation clears the run.'),
        (10, 'marked_unavailable', not public.fn_supplier_available(v_av_state, v_av_until),
            'He marked himself ' || coalesce(v_av_state, 'unavailable') || coalesce(' until ' || to_char(v_av_until, 'DD Mon YYYY'), '')
            || ', so no request is sent to him until he is available again.'),
        (11, 'services_not_confirmed', v_cap.supplier_id is null or v_cap.confirmed_at is null,
            'He has not confirmed his trades and services in the Services tab of his portal. Requests are matched only on confirmed services.'),
        (12, 'no_trades', v_cap.confirmed_at is not null and cardinality(v_trades) = 0,
            'No trade is confirmed on his profile, so no request can match him. He can add his trades in the Services tab.'),
        (13, 'trades_not_open_to_customers', v_jobs30 = 0 and cardinality(v_trades) > 0 and cardinality(v_open) = 0,
            'None of his trades is open to customers yet: a trade opens for customer requests once enough verified suppliers cover it.'),
        (14, 'no_requests_in_his_trades', v_jobs30 = 0 and cardinality(v_trades) > 0 and v_demand30 = 0,
            'No customer posted a request in his trades' || case when cardinality(v_areas) > 0 then ' and emirates' else '' end || ' in the last 30 days.'),
        (15, 'requests_matched_others', v_jobs30 = 0 and v_demand30 > 0,
            v_demand30 || ' request(s) in his trades were posted in the last 30 days and none was sent to him: a request is sent to every approved supplier whose confirmed trade, services, role, value range and required approvals fit it, so one of these did not fit, or it was posted before he qualified.')
      ) as r(n, code, applies, says)
     where r.applies;

    -- A hard gate (1-12) already explains the silence; the demand reasons (13-15) would sit beside it as a false second cause.
    if exists (select 1 from jsonb_array_elements(v_why) x
                where x ->> 'code' not in ('trades_not_open_to_customers', 'no_requests_in_his_trades', 'requests_matched_others')) then
      v_why := coalesce((select jsonb_agg(x order by o) from jsonb_array_elements(v_why) with ordinality as t(x, o)
                          where x ->> 'code' not in ('trades_not_open_to_customers', 'no_requests_in_his_trades', 'requests_matched_others')), '[]'::jsonb);
    end if;

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
        'licence_expired',  (v_lead.license_expiry is not null and v_lead.license_expiry < v_today),
        'licence_days_left',case when v_lead.license_expiry is not null then v_lead.license_expiry - v_today end,
        'blocked_because',  v_lead.licence_gate_reason),
      -- HIS TRADES, SERVICES AND EMIRATES as the matcher reads them (16 Nov 2026)
      'services', jsonb_build_object(
        'confirmed',          (v_cap.confirmed_at is not null),
        'confirmed_at',       v_cap.confirmed_at,
        'trades',             coalesce((select jsonb_agg(jsonb_build_object('code', t, 'label', public.fn_trade_label(t, 'en'),
                                                   'open_to_customers', t = any (v_open)) order by t)
                                          from unnest(v_trades) t), '[]'::jsonb),
        'trades_excluded',    to_jsonb(coalesce(v_cap.excluded_trades, '{}'::text[])),
        'services',           coalesce((select jsonb_agg(coalesce(ts.label_en, s) order by s)
                                          from unnest(coalesce(v_cap.services, '{}'::text[])) s
                                          left join taxonomy_trade_service ts on ts.trade_code || '.' || ts.code = s), '[]'::jsonb),
        'emirates_covered',   to_jsonb(v_areas),
        'uae_wide',           (cardinality(v_areas) = 0)),
      -- WHETHER REQUESTS REACH HIM, AND WHY NOT MORE (16 Nov 2026)
      'matching', jsonb_build_object(
        'receives_requests_now', not exists (select 1 from jsonb_array_elements(v_why) x
                                              where x ->> 'code' not in ('trades_not_open_to_customers', 'no_requests_in_his_trades', 'requests_matched_others')),
        'jobs_sent_30d',        v_jobs30,
        'requests_in_his_trades_30d', v_demand30,
        'availability',         jsonb_build_object('state', coalesce(v_av_state, 'available'), 'busy_until', v_av_until),
        'strikes',              coalesce(v_lead.chat_strikes, 0),
        'strike_limit',         v_limit,
        'matching_paused',      coalesce(v_lead.matching_blocked, false),
        'paused_reason',        case when v_lead.matching_block_reason in ('licence_expired', 'insurance_expired') then v_lead.matching_block_reason end,
        'collaboration',        jsonb_build_object(
                                  'unanswered_in_a_row', coalesce(v_col.consecutive_ignored, 0),
                                  'unanswered_total',    coalesce(v_col.total_ignored, 0),
                                  'warned_at', v_col.warned_at, 'held_at', v_col.held_at, 'lifted_at', v_col.lifted_at,
                                  'on_hold',   (v_lead.collaboration_hold_at is not null)),
        'why_no_jobs',          v_why),
      -- the last 15 requests sent to him: job number, trade, emirate, the request's status and HIS OWN quote only
      'recent_jobs', coalesce((select jsonb_agg(jsonb_build_object('job', j.rfq_no, 'trade', j.category, 'emirate', j.emirate,
                                                 'sent_at', j.sent_at, 'job_status', j.status, 'my_quote', j.my_quote) order by j.sent_at desc)
                                 from (select i.rfq_no, i.category, i.emirate, m.sent_at, i.status,
                                              (select q.status from quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = v_lead.id
                                                order by q.created_at desc limit 1) as my_quote
                                         from inquiry_matches m join inquiries i on i.id = m.inquiry_id
                                        where m.supplier_id = v_lead.id
                                        order by m.sent_at desc nulls last limit 15) j), '[]'::jsonb),
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
     where (v_e164 <> '' and c.id = (select o.customer_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'customer'))
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
      -- 3 Nov 2026: the ONE reading (fn_customer_inquiry_facts): the request number, live quotes, a reveal unlocking
      -- that quote's supplier only, and the open chase.
      'inquiries', public.fn_customer_inquiry_facts(v_cust.id, 10));
  end if;

  return jsonb_build_object('scope','unknown');
end $function$;

revoke execute on function public.fn_wa_context(text, text) from public, anon, authenticated;

-- verdict (the definition and the grant; the behaviour is proven by the _probe file)
select case when position('why_no_jobs' in pg_get_functiondef('public.fn_wa_context(text,text)'::regprocedure)) > 0
             and not has_function_privilege('anon', 'public.fn_wa_context(text,text)', 'execute')
             and not has_function_privilege('authenticated', 'public.fn_wa_context(text,text)', 'execute')
        then 'PROBE OK' else 'PROBE FAILED: fn_wa_context lacks the supplier reading or is open to anon/authenticated' end as verdict;
