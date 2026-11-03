-- A CUSTOMER ASKING ON WHATSAPP READS THEIR OWN REQUESTS, AND EVERY ASK CLOSES ITS LOOP.
--
-- Seat: customer_support. 3 Nov 2026. The founder asked "when a customer asks on WhatsApp about his inquiry, how is the
-- workflow — confirm that things are linked properly", then "not a single thing in our app is one-way communication".
-- Measured on production with rolled-back ZZ DEMO probes (a confirmed customer, a request sent to 3 suppliers, 2 quotes):
--
--   LOOKUPS
--   1. fn_wa_fact_pack told the model "There are no live requests, quotes or comparison reports in the system yet, so no
--      job status can be given for any id" for EVERY sender, and wa_inbound calls the pack "the ONLY source for any fact
--      about this person, their own jobs and quotes". A customer with two quotes was handed a pack forbidding the answer.
--   2. fn_wa_fact_pack found the customer by customers.phone (every digit equal), not by the confirmed WhatsApp number
--      fn_whatsapp_owner reads: an UNCONFIRMED number equal to customers.phone came back as kind 'customer' with the
--      name (while fn_identify_contact said unknown), and a customer who confirmed a different WhatsApp number, or whose
--      phone was stored as 05..., was 'unknown'.
--   3. fn_wa_answer identified only suppliers. Every intent with requires_identity answered a CONFIRMED customer "I do not
--      recognise this number yet", and no intent row is a buyer asking about their own request.
--   4. fn_wa_context gave the request's uuid, not its number (rfq_no, the reference the customer reads), counted only
--      status 'submitted' (a revealed quote dropped out of quotes_received), and after ONE reveal it gave the exact
--      low / high / average of ALL quotes, the unrevealed ones included, and never the revealed supplier's name.
--   LOOPS (nothing is one-way, ledger "nothing-is-one-way")
--   L1 a status question on a request late on quotes reached nobody: no handoff, no chase, no follow-up.
--   L2 a change or an added detail sent on WhatsApp reached no routine; only the portal's note path told suppliers.
--   L4 a cancel on WhatsApp reached no routine, and fn_cancel_inquiry (the portal's too) told neither the matched
--      suppliers nor the customer.
--
-- WHAT THIS FILE DOES
--   * fn_customer_inquiry_facts(customer): ONE reading of a customer's requests (ref, status and its meaning, suppliers
--     reached, live quotes, due time, late, revealed quotes with their supplier, the sealed rest as a rounded band, the
--     open chase). fn_wa_context, fn_wa_fact_pack and fn_wa_answer all read it, so the three cannot disagree.
--   * fn_wa_fact_pack: the customer is the one fn_whatsapp_owner confirms; the false "no live requests" line is gone and
--     the customer's own requests are in the pack.
--   * three intent rows (my_requests, change_request, cancel_request) and fn_wa_answer answering a confirmed customer
--     through fn_wa_customer_request_answer, which ACTS:
--       L1 a late request opens handoff inquiry.status_chase (customer_support -> sales_engineer). The sales engineer's
--          handler reminds every matched supplier who has not quoted (never one reminded in 24 h, ruling 1209), and the
--          customer is told what was done and when the next update is due. customer_support closes it, as originator,
--          only after telling the customer: a quote arrived (WhatsApp, the customer_new_quote template) or the dated
--          update (email). Duty customer_support.status_chase_close runs the closer every 30 minutes.
--       L2 fn_inquiry_change_from_customer: the portal's own note path in SQL (rfq_clarification note, contact details
--          and the customer's name removed, Arabic held for its English exactly as fn_inquiry_add_missing_specs does),
--          every matched supplier told, those who already quoted asked to confirm or revise; the reply confirms it.
--       L4 a cancel names its request number and is then CONFIRMED by a later reply naming it ("yes 1043") within 30
--          minutes; only then fn_cancel_inquiry, which now tells every matched supplier and confirms to the customer by
--          email, for the portal as much as for WhatsApp.
--   L3 "talk to a person": when the 23-hour follow-up cannot go on WhatsApp (the 24-hour window closed) it now goes by
--      email (fn_wa_human_request_email_followup, duty customer_support.person_followup_email). The CEO report at 24 hours
--      and the close (followed up AND the report completed) are unchanged. NOT built here: the first reply on a
--      support.case_open ("report a problem") is still a person's; its handler only waits (see the PR).
--   REVIEW OF #1844 (independent, 3 Nov 2026), every finding fixed in this file and proven by the _probe file: the
--   supplier copy of a change is scrubbed by fn_scrub_customer_identity (portal parity: names, domains, landlines); a
--   buyer is never given a supplier template; one open chase per request, its follow-up delivery read before it closes;
--   a resent change is sent once; a cancel is asked, then confirmed; digit runs bounded and Arabic-Indic digits read; no
--   band from one sealed quote and none reading "about AED 0"; a sanctioned supplier never named; the chase read by
--   index; reminders respect the 2-hour invite guard; the founder's 23-hour alert no longer tells him to email them.
-- wa_inbound is unchanged: fn_wa_route already calls fn_wa_answer with the reasoned intent and hands the reply, the
-- context and the pack to the model as facts. No model is called by anything in this file.
-- Every new routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated.
-- Probe: a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop_probe.sql.

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. ONE READING OF A CUSTOMER'S REQUESTS
create or replace function public.fn_customer_inquiry_facts(p_customer uuid, p_limit integer default 10)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with cfg as (
    select coalesce((select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric
                       from public.app_secrets where key = 'sla_quote_hours'), 24) as sla_h),
  inq as (
    select i.* from public.inquiries i where i.customer_id = p_customer
     order by i.created_at desc limit greatest(coalesce(p_limit, 10), 1)),
  -- a LIVE quote, as fn_rfq_short_of_quotes_tick and the portal count it; a revealed quote is live
  q as (
    select q.inquiry_id, q.supplier_id, q.quote_amount,
           (select min(t.revealed_at) from public.transactions t where t.quote_id = q.id and t.revealed_at is not null) as revealed_at,
           -- founder instruction 516: a sanctioned party is never shown to a customer (customer_api refuses it too)
           exists (select 1 from public.sanctions_ban sb where sb.lead_id = q.supplier_id) as sanctioned
      from public.quotes q join inq on inq.id = q.inquiry_id
     where coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled') and q.stale_at is null)
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) from (
    select i.created_at, jsonb_build_object(
      'id', i.id, 'ref', i.rfq_no, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
      'status_meaning', case i.status
          when 'open' then 'being prepared, not yet sent to suppliers'
          when 'sent' then 'sent to suppliers, waiting for quotes'
          when 'quoted' then 'quotes are coming in'
          when 'split' then 'split into one request per trade (each is listed on its own)'
          when 'revealed' then 'you revealed a supplier'
          when 'completed' then 'completed'
          when 'cancelled' then 'cancelled'
          else 'closed' end,
      'open', coalesce(i.status, '') in ('open', 'sent', 'quoted', 'split'),
      'created_at', i.created_at,
      'suppliers_received', m.n, 'first_sent_at', m.first_sent,
      'quotes_due_by', m.first_sent + make_interval(secs => (cfg.sla_h * 3600)::double precision),
      'quotes_received', coalesce(qq.live, 0), 'quotes_wanted', 3,
      'late', coalesce(i.status, '') in ('sent', 'quoted') and m.first_sent is not null and coalesce(qq.live, 0) < 3
              and now() >= m.first_sent + make_interval(secs => (cfg.sla_h * 3600)::double precision),
      -- PRE-REVEAL a band and a count, never an individual quote and never a supplier. A reveal unlocks THAT quote only:
      -- its supplier and its amount. The rest stay a rounded band of the unrevealed quotes alone.
      'revealed', coalesce(qq.revealed, '[]'::jsonb) <> '[]'::jsonb,
      'revealed_quotes', coalesce(qq.revealed, '[]'::jsonb),
      'sealed_quotes', coalesce(qq.sealed, 0),
      -- review of #1844: with ONE sealed quote the band IS that quote, so a band is given only from two; and an average
      -- under AED 1,000 rounded to the nearest 1,000 read "about AED 0", so below the floor it says "under AED 1,000".
      'price_band', case when coalesce(qq.sealed, 0) < 2 or qq.sealed_avg is null then null
                         else jsonb_build_object(
                                'average_rounded_to_nearest_1000', case when qq.sealed_avg < 1000 then null else round(qq.sealed_avg / 1000) * 1000 end,
                                'average_label', case when qq.sealed_avg < 1000 then 'under AED 1,000'
                                                      else 'about AED ' || to_char(round(qq.sealed_avg / 1000) * 1000, 'FM999,999,999,990') end,
                                'note', 'rounded band of the quotes not yet revealed - the exact quotes and the supplier names unlock when you reveal') end,
      'chase', ch.j) as j
      from inq i cross join cfg
      left join lateral (select count(*)::int as n, min(x.sent_at) as first_sent
                           from public.inquiry_matches x where x.inquiry_id = i.id) m on true
      left join lateral (select count(*)::int as live, (count(*) filter (where q.revealed_at is null))::int as sealed,
                                avg(q.quote_amount) filter (where q.revealed_at is null) as sealed_avg,
                                jsonb_agg(jsonb_build_object('supplier', case when q.sanctioned then 'a supplier no longer on QuotesDone' else coalesce(l.company_name, 'the supplier') end,
                                          'amount_aed', q.quote_amount, 'revealed_at', q.revealed_at) order by q.revealed_at)
                                  filter (where q.revealed_at is not null) as revealed
                           from q left join public.leads l on l.id = q.supplier_id where q.inquiry_id = i.id) qq on true
      -- The chase is read by EQUALITY on agent_actions_kind_type_from_idx (kind, detail type, detail from), then the
      -- inquiry id. Measured on production 3 Nov 2026: the earlier target_id LIKE 'inquiry.status_chase:<id>:%' could not
      -- use the btree (default collation) and planned a bitmap heap scan of every sales_engineer handoff, cost 6,122 per
      -- inquiry, ~30 times per WhatsApp message; this plans an index scan, cost 2.53. Only a request that was sent is read.
      -- ponytail: filters every status_chase row on detail inquiry_id; add an expression index on it if chases reach 10^4.
      left join lateral (select jsonb_build_object('asked_at', a.created_at, 'state', a.status,
                                  'suppliers_reminded', a.evidence -> 'chased', 'next_update_by', a.detail ->> 'next_update_by',
                                  'outcome', a.evidence ->> 'verdict') as j
                           from public.agent_actions a
                          where m.first_sent is not null
                            and a.kind = 'handoff' and a.detail ->> 'type' = 'inquiry.status_chase' and a.detail ->> 'from' = 'customer_support'
                            and a.detail ->> 'inquiry_id' = i.id::text
                          order by a.id desc limit 1) ch on true) x
$fn$;
revoke execute on function public.fn_customer_inquiry_facts(uuid, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. fn_wa_context: the customer's requests come from the one reading (founder and supplier branches unchanged)
create or replace function public.fn_wa_context(p_audience text, p_phone text)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp'
as $function$
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
     where (v_e164 <> '' and l.id = (select o.lead_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'supplier'))
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

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. fn_wa_fact_pack: the confirmed customer, their requests, and no false "nothing exists" line
create or replace function public.fn_wa_fact_pack(p_phone text)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_lead_id bigint;
  l         record;
  c         record;
  v_cfg     record;
  v_conv    record;
  v_hist    jsonb := '[]'::jsonb;
  v_mand    jsonb;
  v_digits  text;
  -- Built before the return, NOT inside a CASE. Postgres evaluates a record field reference even in
  -- an unreached CASE branch, so with an unknown sender 'record l is not assigned yet' aborts the
  -- whole function. An unknown caller is the most common case, so that bug would have fired first.
  v_ident   jsonb;
  v_found_c boolean := false;
  v_conv_j  jsonb;
begin
  v_digits := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  select standard_reveal_rate, supplier_free_count, supplier_reg_fee, category_open_min_suppliers,
         refund_window_working_days, chase_after_working_days
    into v_cfg from public.pricing_config order by id limit 1;

  v_lead_id := public.fn_wa_lead_id(p_phone);
  if v_lead_id is not null then
    select * into l from public.leads where id = v_lead_id;
    v_mand  := public.fn_supplier_mandatory_check(v_lead_id);
    v_ident := jsonb_build_object(
      'kind','supplier','id',v_lead_id,'company',l.company_name,
      'approval_status', coalesce(l.approval_status,'not reviewed'),
      'registration_status', coalesce(l.registration_status,'not started'),
      'mandatory', v_mand);
  else
    -- 3 Nov 2026: the customer the CONFIRMED WhatsApp number names (fn_whatsapp_owner), as fn_identify_contact and
    -- fn_wa_context read it. customers.phone alone named an unconfirmed number and missed a confirmed other one.
    select * into c from public.customers
      where id = (select o.customer_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'customer');
    v_found_c := found;
    if v_found_c then
      v_mand  := public.fn_customer_mandatory_check(c.id);
      v_ident := jsonb_build_object(
        'kind','customer','id',c.id::text,'name',c.full_name,
        'email_verified', c.email_verified, 'phone_verified', c.phone_verified,
        'mandatory', v_mand,
        'requests', public.fn_customer_inquiry_facts(c.id, 10));
    else
      v_ident := jsonb_build_object('kind','unknown',
        'note','This number matches no confirmed lead and no confirmed customer. Do not discuss anyone''s records.');
    end if;
  end if;

  v_conv_j := jsonb_build_object('state','new');
  select * into v_conv from public.wa_conversation where phone_e164 = v_digits;
  if found then
    v_conv_j := jsonb_build_object(
      'state', v_conv.thread_state, 'topic', v_conv.topic, 'language', v_conv.language,
      'messages_so_far', v_conv.message_count,
      'window_open', (v_conv.window_expires_at is not null and v_conv.window_expires_at > now()));
    select coalesce(jsonb_agg(jsonb_build_object('at', t.at, 'dir', t.direction,
             'text', coalesce(t.transcript, t.body)) order by t.at), '[]'::jsonb)
      into v_hist
      from (select * from public.wa_turn where conversation_id = v_conv.id order by at desc limit 12) t;
  end if;

  return jsonb_build_object(
    -- WHO. Identity is a fact, never an inference. An unknown sender stays unknown.
    'identity', v_ident,

    -- WHAT IS TRUE ABOUT THE COMPANY. Read live, never remembered.
    'company', jsonb_build_object(
      'reveal_rate_pct', round(coalesce(v_cfg.standard_reveal_rate,0.03) * 100, 1),
      'supplier_free_count', v_cfg.supplier_free_count,
      'supplier_reg_fee_aed', v_cfg.supplier_reg_fee,
      'category_opens_at_suppliers', v_cfg.category_open_min_suppliers,
      'refund_window_working_days', v_cfg.refund_window_working_days,
      'supplier_chase_after_working_days', v_cfg.chase_after_working_days,
      'founder_contact', (coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')),
      'supplier_mandatory', jsonb_build_array('company name','UAE mobile','email','trade licence','company profile','signed terms'),
      'customer_mandatory', jsonb_build_array('name','mobile','email','signed terms')),

    -- THE THREAD.
    'conversation', v_conv_j,
    'history', v_hist,

    -- WHAT IS NOT KNOWN. Stating this is what stops a model filling the gap with something plausible.
    -- 3 Nov 2026: "there are no live requests ... no job status can be given for any id" and "no category is open yet"
    -- were removed: both were false, and the first forbade the answer a customer's own requests (above) carry.
    'unknown', jsonb_build_array(
      'Anything about another customer, another supplier or another supplier''s quote is not in this pack and is never given.',
      'Pricing beyond the reveal rate and registration fee is not set and must not be invented.'),

    -- WHAT MAY NOT BE SAID OR DONE. A boundary, not a suggestion.
    'must_not', jsonb_build_array(
      'Never state a fact that is not in this pack. If it is not here, say plainly that you do not have it.',
      'Never quote a price, discount, delivery date or timescale that is not in this pack.',
      'Never reveal any other party''s identity, contact details or quote. Anonymity is the product.',
      'Never promise approval, a job, or a refund. Refunds are decided by the CEO under the refund policy.',
      'Never ask for a password, a card number or an OTP code.'),

    'generated_at', now()
  );
end;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. THE THREE INTENTS A BUYER ASKS (the classifier reads intent_key and label; the words decide nothing)
insert into public.wa_reply_intent (intent_key, label, sort, match_patterns, requires_identity, scope, answer_template, resolver_note, active, requires_number) values
 ('my_requests', 'A buyer asking about their own request: its status, how many suppliers received it, how many quotes came in, or when quotes will arrive',
  85, '{}', true, 'own_records',
  'Your requests are answered from a buyer''s own record. As a supplier, ask me about your registration, your documents or your quotes.',
  'fn_wa_customer_request_answer (fn_customer_inquiry_facts). A late request opens inquiry.status_chase to the sales engineer.', true, false),
 ('change_request', 'A buyer changing or adding a detail to a request they already posted (a quantity, a size, a specification, a date, a location)',
  86, '{}', true, 'own_records',
  'Changes to a request are made by the buyer who posted it. As a supplier, ask me about your registration, your documents or your quotes.',
  'fn_wa_customer_request_answer -> fn_inquiry_change_from_customer: the note reaches every matched supplier.', true, false),
 ('cancel_request', 'A buyer asking to cancel or withdraw a request they posted',
  87, '{}', true, 'own_records',
  'A request is cancelled by the buyer who posted it. As a supplier, ask me about your registration, your documents or your quotes.',
  'fn_wa_customer_request_answer -> fn_cancel_inquiry, only after a later reply confirms it by naming the request (yes 1043) within 30 minutes.', true, false)
on conflict (intent_key) do update set label = excluded.label, sort = excluded.sort, requires_identity = excluded.requires_identity,
  scope = excluded.scope, answer_template = excluded.answer_template, resolver_note = excluded.resolver_note, active = excluded.active;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. L2: A CHANGE FROM THE CUSTOMER REACHES EVERY MATCHED SUPPLIER (the portal's rfq_note path, in SQL)
--
-- 5a. ONE SCRUB of the customer's identity from text a supplier reads. Review of #1844 (HIGH): the change path ran
--     mask_contacts() and a case-sensitive replace of the full name. Measured: mask_contacts removes emails, URLs, +971
--     numbers and 05x mobiles, and leaves a bare domain (alnoor-trading.ae), a landline (04 345 6789), a first name alone
--     and an UPPERCASE name - all of which reached every matched supplier before any reveal. This is the SQL twin of
--     customer_api scrubIdentity (ID_PATTERNS + the name): bare domains, landlines (0, a digit, then 7 or 8 more), and every token
--     of the customer's name, case-insensitive, on word boundaries. Tokens shorter than 3 letters and the name particles
--     (bin, abu, umm ...) are left: they are words in a specification as often as in a name.
create or replace function public.fn_scrub_customer_identity(p_text text, p_customer uuid)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v text; w text;
begin
  if p_text is null or btrim(p_text) = '' then return p_text; end if;
  -- every pattern below is ASCII-digit: a number typed in Arabic-Indic or Persian digits is read as Western first
  -- (re-review of #1844), or it would pass the scrub and reach suppliers through the English copy
  v := public.mask_contacts(translate(p_text, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'));
  v := regexp_replace(v, '\y[A-Za-z0-9-]{2,}\.(ae|com|net|org|co|io|me|biz|info)(\.[A-Za-z]{2})?\y', '[removed]', 'gi');
  v := regexp_replace(v, '\y0[0-9]([ .-]?[0-9]){7,8}\y', '[removed]', 'g');
  -- a token is letters and digits only (the split guarantees it), so it carries no regex metacharacter
  for w in select distinct t from regexp_split_to_table(coalesce((select full_name from public.customers where id = p_customer), ''), '[^[:alnum:]]+') t
            where length(t) >= 3 and lower(t) not in ('bin', 'bint', 'abu', 'umm', 'the', 'and', 'mrs') loop
    v := regexp_replace(v, '\y' || w || '\y', '[removed]', 'gi');
  end loop;
  return v;
end $fn$;
revoke execute on function public.fn_scrub_customer_identity(text, uuid) from public, anon, authenticated;

-- 5b. The change itself. Review of #1844, also fixed here:
--   * a resent identical change (same scrubbed text, same request, within 6 hours) returns the earlier note and sends
--     nothing again (the delivery dedupe key carries the note id, so a resend used to mail every supplier twice);
--   * the Arabic path now does what the English path does for suppliers who ALREADY quoted: they are told at once, in
--     English, that a change is on its way and asked to confirm or revise once they read it; the English copy itself
--     still goes to every matched supplier through the supplier_english replay, as fn_inquiry_add_missing_specs files it.
create or replace function public.fn_inquiry_change_from_customer(p_inquiry uuid, p_customer uuid, p_text text, p_source text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare i public.inquiries; v_text text; v_full text; v_note bigint; v_q text; l record; v_prev public.rfq_clarification;
        v_told int := 0; v_quoted int := 0; v_failed int := 0; v_matched int; v_head text; v_body text; v_ar boolean; v_d jsonb; v_dup boolean;
begin
  if p_source not in ('whatsapp') then raise exception 'a customer change comes from whatsapp here, not %', p_source; end if;
  select * into i from public.inquiries where id = p_inquiry for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'inquiry_not_found'); end if;
  if i.customer_id is distinct from p_customer then return jsonb_build_object('ok', false, 'error', 'not_your_inquiry'); end if;
  if coalesce(i.status, '') in ('cancelled', 'closed', 'completed', 'expired', 'lost') then
    return jsonb_build_object('ok', false, 'error', 'inquiry_closed', 'status', i.status); end if;
  if coalesce(i.status, '') = 'revealed' or exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.revealed_at is not null) then
    return jsonb_build_object('ok', false, 'error', 'already_revealed'); end if;
  -- Every matched supplier reads this: the customer's contact details and name are removed first (5a).
  v_text := public.fn_scrub_customer_identity(left(btrim(coalesce(p_text, '')), 1500), p_customer);
  if length(btrim(regexp_replace(coalesce(v_text, ''), '\[(removed|hidden)\]', '', 'g'))) < 2 then
    return jsonb_build_object('ok', false, 'error', 'text_required'); end if;
  v_head := 'The customer sent this change to the request on WhatsApp:';
  v_full := v_head || chr(10) || v_text;
  v_ar := v_text ~ '[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻾]';
  select count(*) into v_matched from public.inquiry_matches x where x.inquiry_id = i.id;

  -- THE SAME CHANGE TWICE IS ONE CHANGE: the earlier note is reused and no second note is filed. Its deliveries are
  -- asked for again under the SAME keys, so a supplier already told is not mailed twice (the delivery door dedupes a
  -- delivered key) and one whose first delivery failed is retried (a failed key is not deduped).
  select * into v_prev from public.rfq_clarification r
   where r.inquiry_id = i.id and r.kind = 'note' and r.source = 'rfq_note'
     and coalesce(r.answered_at, r.asked_at) > now() - interval '6 hours'
     and md5(coalesce(r.answer_as_written, r.answer, '')) = md5(v_full)
   order by r.id desc limit 1;
  v_dup := v_prev.id is not null;
  if v_dup then v_note := v_prev.id; end if;
  -- the portal's own limit on notes (customer_api rfq_note)
  if not v_dup and (select count(*) from public.rfq_clarification r where r.inquiry_id = i.id and r.kind = 'note' and r.asked_at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('ok', false, 'error', 'too_many_notes'); end if;

  if v_dup then
    null;
  elsif v_ar then
    -- Suppliers read English only: the Arabic is kept as written and its supplier copy waits for its English, exactly as
    -- fn_inquiry_add_missing_specs files it (the supplier_english replay mails every matched supplier when it lands).
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answer_as_written, english_held_at, answered_at, source)
    values (i.id, null, 'note', null, v_full, now(), now(), 'rfq_note') returning id into v_note;
    v_q := 'Translate this message from a customer into clear, professional English for the suppliers quoting the job, '
        || 'as a UAE sales engineer would write it. Keep every measurement, quantity, brand, model and grade code exactly as written. '
        || 'Add nothing and leave nothing out. Put ONLY the English text in "answer".' || chr(10) || chr(10) || v_full;
    perform public.fn_reason_hold('sales_engineer', 'sales_engineer.supplier_english', left(v_q, 8000),
      jsonb_build_object('seat', 'sales_engineer', 'surface', 'sales_engineer.supplier_english', 'question', v_q,
        'context', jsonb_build_object('audience', 'internal', 'language', 'en'), 'research', false,
        'subject', jsonb_build_object('clarification_id', v_note), 'dedupeKey', 'supplier_english:' || v_note),
      '{}'::jsonb, jsonb_build_object('clarification_id', v_note), 'filed_from_a_request_path', 'supplier_english:' || v_note);
  else
    insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source)
    values (i.id, null, 'note', v_full, now(), 'rfq_note') returning id into v_note;
  end if;

  for l in select le.id, coalesce(nullif(btrim(le.claimed_by), ''), le.email) as to_email,
                  exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = le.id
                           and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'cancelled')) as quoted
             from public.inquiry_matches x join public.leads le on le.id = x.supplier_id
            where x.inquiry_id = i.id and not coalesce(le.banned, false)
              and coalesce(nullif(btrim(le.claimed_by), ''), le.email, '') like '%@%' loop
    -- held Arabic: only the suppliers who already quoted are written to now; everyone gets the English copy from the replay
    continue when v_ar and not l.quoted;
    v_body := case when v_ar
      then 'The customer changed the ' || coalesce(i.category, '') || coalesce(' job in ' || nullif(i.emirate, ''), ' job')
           || ' (request ' || coalesce(i.rfq_no::text, '') || ') you already quoted. The change was written in Arabic, and its English copy '
           || 'reaches you by email shortly. Once you have read it, please confirm your quote still stands, or revise it, in your QuotesDone supplier portal.'
      else 'The customer changed the ' || coalesce(i.category, '') || coalesce(' job in ' || nullif(i.emirate, ''), ' job')
           || ' (request ' || coalesce(i.rfq_no::text, '') || ') you were invited to quote:' || chr(10) || chr(10) || v_text || chr(10) || chr(10)
           || case when l.quoted then 'You have already quoted on this request: please confirm your quote still stands, or revise it, in your QuotesDone supplier portal.'
                   else 'It is now part of the request. Log in to your QuotesDone supplier portal to see the full request and quote.' end end;
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'rfq_addendum', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', l.to_email,
      'to_role', 'supplier', 'lead_id', l.id, 'inquiry_id', i.id, 'lang', 'en',
      'subject', 'The customer changed a request you were invited to quote', 'body', v_body,
      'dedupe_key', 'customer_change:' || v_note || ':' || l.id)));
    -- a supplier is counted as told only when the delivery took it (re-review of #1844: the reply claimed every send)
    if coalesce(v_d->0->>'status', '') not in ('done', 'demo_captured') then v_failed := v_failed + 1; continue; end if;
    if not v_ar then v_told := v_told + 1; end if;
    if l.quoted then v_quoted := v_quoted + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'duplicate', v_dup, 'note_id', v_note, 'held_for_english', v_ar, 'suppliers_told', v_told, 'quoted_told', v_quoted,
    'delivery_failed', v_failed, 'suppliers_matched', v_matched);
end $fn$;
revoke execute on function public.fn_inquiry_change_from_customer(uuid, uuid, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. L4: A CANCEL TELLS EVERY MATCHED SUPPLIER AND CONFIRMS TO THE CUSTOMER (portal and WhatsApp alike)
create or replace function public.fn_cancel_inquiry(p_inquiry uuid, p_customer uuid, p_reason text DEFAULT NULL::text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v inquiries%rowtype; v_paid boolean; v_cnt int; v_warned boolean:=false; v_email text; v_locale text;
        l record; v_told int := 0; v_failed int := 0; v_cust_told boolean := false; v_ar boolean; v_d jsonb;
begin
  -- review of #1844: locked, so a concurrent reveal or a second cancel cannot interleave with the checks below
  select * into v from inquiries where id=p_inquiry for update;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  if v.status='cancelled' or v.pipeline_stage='cancelled' then
    return jsonb_build_object('ok',true,'already_cancelled',true); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  if v_paid or v.status in ('revealed','completed') or v.pipeline_stage in ('revealed','won') then
    return jsonb_build_object('error','already_revealed',
      'message','This request already has an active revealed deal and cannot be cancelled. You can close it instead.'); end if;

  update inquiries set status='cancelled', pipeline_stage='cancelled', outcome='cancelled',
      lost_reason=coalesce(p_reason,'customer_cancelled'), completed_at=now(), stage_changed_at=now()
    where id=p_inquiry;
  insert into inquiry_cancellations(inquiry_id,customer_id,reason) values (p_inquiry, v.customer_id, p_reason);

  -- 3 Nov 2026: NOTHING IS ONE-WAY. Every supplier invited to quote is told the job is off (suppliers are written in
  -- English), through customer_support's door, once per request and supplier.
  for l in select le.id, coalesce(nullif(btrim(le.claimed_by), ''), le.email) as to_email
             from inquiry_matches x join leads le on le.id = x.supplier_id
            where x.inquiry_id = p_inquiry and not coalesce(le.banned, false)
              and coalesce(nullif(btrim(le.claimed_by), ''), le.email, '') like '%@%' loop
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'rfq_cancelled', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', l.to_email,
      'to_role', 'supplier', 'lead_id', l.id, 'inquiry_id', p_inquiry, 'lang', 'en',
      'subject', 'A request you were invited to quote was cancelled',
      'body', 'The customer cancelled the ' || coalesce(v.category, '') || coalesce(' job in ' || nullif(v.emirate, ''), ' job')
              || ' (request ' || coalesce(v.rfq_no::text, '') || ') you were invited to quote. No quote is needed for it any more, '
              || 'and a quote you already sent will not be used. Thank you for your time.',
      'dedupe_key', 'rfq_cancelled:' || p_inquiry || ':' || l.id)));
    -- counted as told only when the delivery took it (re-review of #1844)
    if coalesce(v_d->0->>'status', '') in ('done', 'demo_captured') then v_told := v_told + 1; else v_failed := v_failed + 1; end if;
  end loop;

  select email, locale into v_email, v_locale from customers where id=v.customer_id;
  -- ...and the customer gets the confirmation in the request's own language (founder, 28 Sep 2026).
  if v_email is not null and position('@' in v_email)>1 then
    v_ar := coalesce(v.lang, v_locale) = 'ar';
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'inquiry_cancelled', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', v_email,
      'to_role', 'customer', 'inquiry_id', p_inquiry, 'lang', case when v_ar then 'ar' else 'en' end,
      'subject', case when v_ar then 'أُلغي طلبكم رقم ' || coalesce(v.rfq_no::text, '')
                      else 'Your request ' || coalesce(v.rfq_no::text, '') || ' is cancelled' end,
      'body', case when v_ar
        then 'أُلغي طلبكم رقم ' || coalesce(v.rfq_no::text, '') || ' بناءً على رغبتكم، وأبلغنا بذلك المورّدين الذين دعوناهم إلى تقديم عروضهم. '
             || 'وإن كان الإلغاء عن طريق الخطأ، فبإمكانكم نشر الطلب من جديد على https://quotesdone.com'
        else 'Your request ' || coalesce(v.rfq_no::text, '') || ' is cancelled, as you asked, and the suppliers invited to quote have been told. '
             || 'If this was a mistake, you can post the request again at https://quotesdone.com' end,
      'dedupe_key', 'inquiry_cancelled:' || p_inquiry)));
    v_cust_told := coalesce(v_d->0->>'status', '') in ('done', 'demo_captured');
  end if;

  select count(*) into v_cnt from inquiry_cancellations where customer_id=v.customer_id and created_at > now()-interval '30 days';
  if v.customer_id is not null and v_cnt >= 3 then
    if v_email is not null and position('@' in v_email)>1
       and not exists (select 1 from notifications where type='cancel_warning' and to_email=v_email and created_at > now()-interval '30 days') then
      insert into notifications(type,to_email,to_role,inquiry_id,subject,body,channel,status)
      values('cancel_warning', v_email, 'customer', p_inquiry,
        'A quick note about cancelled requests',
        'We noticed a few of your recent requests were cancelled. That is completely fine — but every request you post is prepared and quoted by suppliers who set aside real time for it. To keep things fair for them, we kindly ask that you post requests you intend to proceed with. If you would like help scoping a job before posting, our team is glad to assist.',
        'email','queued');
      v_warned:=true;
    end if;
  end if;
  return jsonb_build_object('ok',true,'cancelled',true,'cancellations_30d',v_cnt,'warned',v_warned,
                            'suppliers_told',v_told,'suppliers_not_reached',v_failed,'customer_told',v_cust_told);
end $function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. L1: THE STATUS CHASE — registered conversation, the sales engineer's handler, customer_support's closer
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
 ('inquiry.status_chase', 'customer_support', 'sales_engineer',
  'A customer asked on WhatsApp about a request that is past the time quotes were due with fewer than 3 quotes: the sales engineer reminds every matched supplier who has not quoted (never one reminded in the last 24 hours). customer_support closes it after telling the customer: a quote arrived, or the dated update at next_update_by.',
  'fn_sales_engineer_chases_for_status', interval '26 hours', true,
  'scripts/sql/a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

create or replace function public.fn_sales_engineer_chases_for_status(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; i public.inquiries; l record; v jsonb; v_fix boolean; v_due timestamptz;
        n_matched int := 0; n_quoted int := 0; n_chased int := 0; n_recent int := 0; n_unreached int := 0; n_new int := 0;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff' and detail->>'type' = 'inquiry.status_chase';
  if not found then raise exception 'fn_sales_engineer_chases_for_status: % is not a status-chase handoff', p_id; end if;
  select * into i from public.inquiries where id = (a.detail->>'inquiry_id')::uuid;
  if not found then return jsonb_build_object('ok', false, 'error', 'inquiry_not_found'); end if;
  v_fix := public.fn_inquiry_is_demo(i.id);
  v_due := coalesce((a.detail->>'next_update_by')::timestamptz, now() + interval '24 hours');
  for l in select ld.*, m.sent_at as invited_at_, exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = ld.id) as has_quote
             from public.inquiry_matches m join public.leads ld on ld.id = m.supplier_id
            where m.inquiry_id = i.id and not coalesce(ld.banned, false) loop
    n_matched := n_matched + 1;
    if l.has_quote then n_quoted := n_quoted + 1; continue; end if;
    -- the sweep's own guard (review of #1844): a supplier invited less than 2 hours ago (or not yet sent) is not reminded
    if not coalesce(l.invited_at_ < now() - interval '2 hours', false) then n_new := n_new + 1; continue; end if;
    -- NO SUPPLIER IS NUDGED TWICE IN 24 HOURS (ruling 1209): one already reminded is counted, not reminded again.
    if exists (select 1 from public.notifications n where n.lead_id = l.id and n.type = 'rfq_quote_reminder'
                 and n.created_at > now() - interval '24 hours' and coalesce(n.status, '') <> 'failed') then
      n_recent := n_recent + 1; continue;
    end if;
    v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_quote_reminder', 'supplier',
           lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), v_fix, 'en', 'rfq_quote_reminder',
           jsonb_build_object('name', l.company_name, 'category', i.category, 'emirate', i.emirate, 'deadline', v_due),
           'rfq_status_chase:' || p_id || ':' || l.id, i.id, null, l.id);
    if coalesce((v->>'ok')::boolean, false) then n_chased := n_chased + 1; else n_unreached := n_unreached + 1; end if;
  end loop;
  return jsonb_build_object('ok', true,
    'waiting', 'customer_support closes this after telling the customer: a new quote arrived, or the dated update at ' || v_due,
    'inquiry_id', i.id, 'suppliers_matched', n_matched, 'suppliers_quoted', n_quoted, 'chased', n_chased,
    'already_reminded_today', n_recent, 'invited_under_2_hours_ago', n_new, 'not_reachable', n_unreached, 'next_update_by', v_due);
end $fn$;
revoke execute on function public.fn_sales_engineer_chases_for_status(bigint) from public, anon, authenticated;

-- The closer. Review of #1844, fixed here:
--   * the follow-up's DELIVERY is read (fn_customer_support_takes_delivery element 0): only 'done' closes the loop. A
--     failed delivery, or a customer with no confirmed WhatsApp and no email, leaves the chase pending; the third failure
--     files an it_engineer finding and stops retrying. The closing evidence carries delivery_status.
--   * a quote follow-up is keyed on the request and the new quotes' ids, and when the platform's own new-quote notice
--     already told the customer after the chase began, the chase closes without a second message.
--   * the language is the WhatsApp conversation's first (as fn_wa_human_request_email_followup reads it), then the
--     request's, then the account's.
create or replace function public.fn_customer_support_closes_status_chases()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h public.agent_actions; i public.inquiries; c public.customers; v_new int; v_live int; v_due timestamptz; v_ar boolean;
        v_dest text; v_res jsonb; v_st text; v_lang text; v_qkey text; v_tries int; v_verdict text; v_outcome text;
        v_first_new timestamptz; v_ptold boolean; v_pwait boolean;
        n_closed int := 0; n_wait int := 0; n_failed int := 0; n_stuck int := 0; v_err jsonb := '[]'::jsonb;
begin
  for h in select * from public.agent_actions a
            where a.kind = 'handoff' and a.agent = 'sales_engineer' and a.status = 'pending'
              and a.detail->>'type' = 'inquiry.status_chase' and a.detail->>'from' = 'customer_support'
            order by a.id limit 100 loop
    begin
      v_verdict := null; v_outcome := null; v_res := null; v_st := null; v_dest := null; v_lang := null;
      v_tries := coalesce((h.detail->>'followup_attempts')::int, 0);
      v_ptold := null; v_pwait := null;
      select * into i from public.inquiries where id = (h.detail->>'inquiry_id')::uuid;
      select * into c from public.customers where id = i.customer_id;
      v_due := coalesce((h.evidence->>'next_update_by')::timestamptz, (h.detail->>'next_update_by')::timestamptz, h.created_at + interval '24 hours');
      select w.language into v_lang from public.wa_conversation w where w.phone_e164 = h.detail->>'phone_digits';
      v_ar := case when v_lang in ('ar', 'en') then v_lang = 'ar' else coalesce(i.lang, c.locale) = 'ar' end;
      select count(*) filter (where q.created_at > h.created_at), count(*),
             md5(string_agg(q.id::text, ',' order by q.id) filter (where q.created_at > h.created_at)),
             min(q.created_at) filter (where q.created_at > h.created_at)
        into v_new, v_live, v_qkey, v_first_new from public.quotes q
       where q.inquiry_id = i.id and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
         and q.stale_at is null;
      -- The platform's own new-quote notice for THESE quotes (measured 3 Nov 2026: its rows carry inquiry_id, not quote_id,
      -- so it is tied by time: written at or after the first new quote). Every such row counts (it may write one per
      -- channel): any delivered one means told; else any still queued under an hour means wait; else we send.
      if v_new > 0 then
        select bool_or(coalesce(n.status, 'queued') not in ('failed', 'skipped', 'queued', 'pending')),
               bool_or(coalesce(n.status, 'queued') in ('queued', 'pending') and n.created_at > now() - interval '1 hour')
          into v_ptold, v_pwait from public.notifications n
         where n.inquiry_id = i.id and n.type = 'new_quote' and n.to_role = 'customer' and n.created_at >= v_first_new;
      end if;
      if i.id is null or coalesce(i.status, '') not in ('sent', 'quoted', 'open', 'split') then
        -- read before the retry cap, so a stuck chase still closes when its request moves on
        v_outcome := 'request_moved_on'; v_st := 'nothing_to_send';
        v_verdict := 'the request is ' || coalesce(i.status, 'gone') || ': nothing is left to chase';
      elsif v_tries >= 3 then
        -- three failed follow-ups wait on it_engineer's finding, never a fourth identical try
        n_stuck := n_stuck + 1; continue;
      elsif v_new > 0 and coalesce(v_ptold, false) then
        -- sent, delivered, or (demo only, measured 3 Nov 2026) suppressed, as ours would be: the customer was told
        v_outcome := 'quote_arrived'; v_st := 'platform_new_quote_notice';
        v_verdict := v_new || ' new quote(s) arrived and the platform''s new-quote notice told the customer; nothing more was sent';
      elsif v_new > 0 and coalesce(v_pwait, false) then
        -- the platform's notice is still on its way: wait for it rather than send a second message
        n_wait := n_wait + 1; continue;
      elsif v_new > 0 then
        -- A quote arrived: the customer hears it on the WhatsApp they asked on (the approved customer_new_quote template);
        -- after a failed try, by the email on file instead, so a WhatsApp that keeps failing is not retried alone.
        v_dest := public.fn_whatsapp_destination('customer', c.id);
        if v_tries >= 1 and coalesce(c.email, '') like '%@%' then v_dest := null; end if;
        v_outcome := 'quote_arrived';
        if v_dest is null and coalesce(c.email, '') not like '%@%' then v_st := 'no_channel';
        else
          v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
            'type', 'quote_received', 'requested_by', 'customer_support', 'channel', case when v_dest is null then 'email' else 'whatsapp' end,
            'to_phone', v_dest, 'to_email', c.email, 'to_role', 'customer', 'inquiry_id', i.id, 'lang', case when v_ar then 'ar' else 'en' end,
            'subject', case when v_ar then 'مستجدات العروض على طلبكم رقم ' || coalesce(i.rfq_no::text, '') else 'A new quote arrived on your request ' || coalesce(i.rfq_no::text, '') end,
            'body', case when v_ar
              then 'كما وعدناكم، وصل إلى طلبكم رقم ' || coalesce(i.rfq_no::text, '') || ' ما عدده ' || v_new || ' من العروض الجديدة، ليصبح مجموع العروض لديكم ' || v_live
                   || '. وبإمكانكم مقارنتها في حسابكم على https://quotesdone.com'
              else 'As promised: ' || v_new || ' new quote(s) arrived on your request ' || coalesce(i.rfq_no::text, '') || ', so you now have ' || v_live
                   || '. You can compare them in your account at https://quotesdone.com' end,
            'dedupe_key', 'status_chase_quote:' || i.id || ':' || v_qkey || case when v_dest is null then ':email' else '' end)));
          v_st := v_res->0->>'status';
        end if;
        v_verdict := v_new || ' new quote(s) arrived; the customer was told (' || case when v_dest is null then 'email' else 'WhatsApp' end || ')';
      elsif now() >= v_due then
        v_outcome := 'dated_update_sent';
        if coalesce(c.email, '') not like '%@%' then v_st := 'no_channel';
        else
          v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
            'type', 'inquiry_status_update', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', c.email,
            'to_role', 'customer', 'inquiry_id', i.id, 'lang', case when v_ar then 'ar' else 'en' end,
            'subject', case when v_ar then 'مستجدات طلبكم رقم ' || coalesce(i.rfq_no::text, '') else 'An update on your request ' || coalesce(i.rfq_no::text, '') end,
            'body', case when v_ar
              then 'كما وعدناكم، إليكم مستجدات طلبكم رقم ' || coalesce(i.rfq_no::text, '') || ': وصلكم حتى الآن ' || v_live || ' من أصل 3 عروض نسعى إلى توفيرها. '
                   || 'وقد ذكّر مهندس المبيعات لدينا المورّدين المدعوين الذين لم يقدّموا عروضهم بعد، ويبقى طلبكم متاحًا لمورّدين آخرين في المجال نفسه، وسنوافيكم فور وصول أي عرض جديد.'
              else 'As promised, an update on your request ' || coalesce(i.rfq_no::text, '') || ': you have ' || v_live || ' of the 3 quotes we aim for. '
                   || 'Our sales engineer reminded the invited suppliers who had not quoted, and the request stays open to more suppliers in its trade. '
                   || 'We will tell you as soon as a new quote arrives.' end,
            'dedupe_key', 'status_chase_update:' || h.id)));
          v_st := v_res->0->>'status';
        end if;
        v_verdict := 'no new quote by ' || v_due || '; the dated update was sent to the customer by email';
      end if;

      if v_verdict is null then n_wait := n_wait + 1; continue; end if;
      -- NOT TOLD IS NOT CLOSED. The chase stays pending and is tried again on the next tick.
      if coalesce(v_st, '') not in ('done', 'platform_new_quote_notice', 'nothing_to_send') then
        v_tries := v_tries + 1;
        update public.agent_actions set detail = detail || jsonb_build_object('followup_attempts', v_tries,
                 'followup_last_status', coalesce(v_st, 'unknown'), 'followup_last_error', v_res->0->>'error', 'followup_last_at', now())
         where id = h.id;
        if v_tries >= 3 then
          perform public.fn_it_engineer_finding_upsert('customer_support:status_chase_followup_undelivered:' || h.id,
            'A status-chase follow-up could not reach the customer after 3 tries (handoff ' || h.id || ')',
            'public.fn_customer_support_closes_status_chases', 'customer_facing', 1,
            jsonb_build_object('handoff_id', h.id, 'inquiry_id', i.id, 'outcome', v_outcome, 'delivery_status', v_st,
                               'error', v_res->0->>'error', 'owner_seat', 'customer_support'),
            '{}'::text[], array['why the follow-up could not be delivered: no confirmed WhatsApp and no email on file, or the delivery handoff failed'],
            'customer_support');
        end if;
        n_failed := n_failed + 1;
        continue;
      end if;
      perform set_config('qd.handoff_closer', 'customer_support', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) - 'waiting' || jsonb_build_object(
        'verified_by', 'customer_support', 'verified_at', now(), 'outcome', v_outcome, 'verdict', v_verdict,
        'delivery_status', v_st, 'followup', v_res -> 0));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('handoff', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'closed', n_closed, 'waiting', n_wait,
                            'not_delivered', n_failed, 'stuck_after_3_tries', n_stuck, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_customer_support_closes_status_chases() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled, own_job) values
 ('customer_support.status_chase_close', 'customer_support', interval '30 minutes', 'fn_customer_support_closes_status_chases',
  'Every inquiry.status_chase handoff (a customer asked on WhatsApp about a late request) is closed by customer_support, its '
  || 'originator, only after the customer was told: a new quote arrived (WhatsApp) or the dated update (email).',
  'scripts/sql/a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.sql', true, false)
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file, enabled = excluded.enabled;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7b. L3: "TALK TO A PERSON" NEVER ENDS IN SILENCE. Measured (rolled back): fn_wa_human_request_tick at 23 hours sends the
--     apology on WhatsApp only while the 24-hour window is open; with it closed it recorded followup_skipped 'the 24-hour
--     WhatsApp window had closed' and told the founder to "call them or email them". The contact heard nothing. This duty
--     sends the same follow-up by email to the confirmed party, through customer_support's door, once per request.
create or replace function public.fn_wa_human_request_email_followup()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.agent_actions; o record; v_email text; v_ar boolean; v_res jsonb; n_sent int := 0; n_none int := 0;
begin
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'support.human_requested'
              and a.detail->>'followup_skipped' = 'the 24-hour WhatsApp window had closed' and not (a.detail ? 'email_followup_at')
            order by a.id limit 50 loop
    v_email := null;
    select * into o from public.fn_whatsapp_owner('+' || (r.detail->>'phone_digits')) limit 1;
    if o.party_kind = 'customer' then select email into v_email from public.customers where id = o.customer_id;
    elsif o.party_kind = 'supplier' then select coalesce(nullif(btrim(claimed_by), ''), email) into v_email from public.leads where id = o.lead_id;
    end if;
    -- suppliers are written in English (founder, 28 Sep 2026); a customer in the conversation's language
    v_ar := o.party_kind = 'customer' and exists (select 1 from public.wa_conversation w where w.phone_e164 = r.detail->>'phone_digits' and w.language = 'ar');
    if coalesce(v_email, '') like '%@%' then
      v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'support_person_followup', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', v_email,
        'to_role', o.party_kind, 'lead_id', o.lead_id, 'lang', case when v_ar then 'ar' else 'en' end,
        'subject', case when v_ar then 'بخصوص طلبكم التحدث إلى أحد أعضاء الفريق' else 'About your request to speak to a person' end,
        'body', case when v_ar
          then 'نعتذر عن تأخر ردنا عليكم بعد طلبكم على واتساب التحدث إلى أحد أعضاء الفريق، وقد ذكّرنا الفريق بطلبكم مجددًا. '
               || 'ويمكنكم الرد على هذه الرسالة أو مراسلتنا على واتساب في أي وقت، وستصلكم الإجابات الفورية مباشرة.' || E'\n\nفريق خدمة العملاء في QuotesDone'
          else 'We are sorry you have not heard from us since you asked on WhatsApp to speak to a person. We have reminded the team of your request. '
               || 'You can reply to this email, or message us on WhatsApp at any time and instant answers are back on there.' || E'\n\nQuotesDone Customer Support' end,
        'dedupe_key', 'wa_human_email_followup:' || r.id)));
      update public.agent_actions set detail = detail || jsonb_build_object('email_followup_at', now(), 'email_followup', v_res->0) where id = r.id;
      n_sent := n_sent + 1;
    else
      update public.agent_actions set detail = detail || jsonb_build_object('email_followup_at', now(), 'email_followup', 'no email on file for this number') where id = r.id;
      n_none := n_none + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'emailed', n_sent, 'no_email', n_none);
end $fn$;
revoke execute on function public.fn_wa_human_request_email_followup() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled, own_job) values
 ('customer_support.person_followup_email', 'customer_support', interval '30 minutes', 'fn_wa_human_request_email_followup',
  'A WhatsApp contact who asked for a person and was not answered within 23 hours, whose WhatsApp window had closed, is sent '
  || 'the follow-up by email (once), so the request never ends in silence.',
  'scripts/sql/a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.sql', true, false)
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file, enabled = excluded.enabled;

-- 7c. The founder's 23-hour alert said "call them or email them" when the WhatsApp window had closed, although 7b now sends
--     that email itself. Only that sentence changes; the body is a_whatsapp_request_for_a_person_is_escalated_never_left_waiting.sql's.
create or replace function public.fn_wa_human_request_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_conv public.wa_conversation; v_ref text; v_secret text; v_req bigint; v_body text; v_lang text; n int := 0; v_sent int := 0;
  v_held boolean; v_window interval; v_rep jsonb; rep public.support_ceo_report; n_esc int := 0; n_closed int := 0;
begin
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_resilience_ping';
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.created_at < now() - interval '23 hours' and not (a.detail ? 'followed_up_at')
            order by a.id limit 20 loop
    n := n + 1; v_req := null;
    v_held := coalesce(r.detail ->> 'held', 'true') = 'true';
    update public.wa_conversation set thread_state = 'open', handed_to = null
     where phone_e164 = r.detail ->> 'phone_digits' and thread_state = 'handed_to_human'
    returning * into v_conv;
    if v_conv.id is null then select * into v_conv from public.wa_conversation where phone_e164 = r.detail ->> 'phone_digits'; end if;
    v_lang := case when coalesce(v_conv.language, '') = 'ar' then 'ar' else 'en' end;
    v_body := case when v_lang = 'ar'
      then 'نعتذر عن تأخر ردنا عليكم. لم يتمكن أحد أعضاء الفريق من التواصل معكم بعد، وقد أبلغناه مجددًا بطلبكم. وإلى حين ذلك عادت إليكم خدمة الردود الفورية في هذه المحادثة، فتفضلوا بإرسال كلمة «قائمة» لعرض الخيارات أو كتابة استفساركم.' || E'\n\nفريق خدمة العملاء في QuotesDone'
      else 'We are sorry you have not heard from us yet. A member of the team has not been able to reach you, and we have reminded them of your request. Meanwhile, instant answers are back on in this chat: reply MENU for the options or type your question.' || E'\n\nQuotesDone Customer Support' end;
    if v_held and v_conv.window_expires_at > now() and v_ref is not null and v_secret is not null then
      select net.http_post(
        url := 'https://' || v_ref || '.supabase.co/functions/v1/send_whatsapp',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object('__secret', v_secret, 'to', '+' || (r.detail ->> 'phone_digits'), 'body', v_body),
        timeout_milliseconds := 15000) into v_req;
      v_sent := v_sent + 1;
    end if;
    begin
      perform public.fn_notify_founder(p_event => 'WhatsApp: +' || (r.detail ->> 'phone_digits') || ' has waited 23 hours for a person',
        p_detail => 'Nobody closed the request from +' || (r.detail ->> 'phone_digits') || ' (' || coalesce(r.detail ->> 'event', 'Talk to a person') || ').'
        || case when v_req is not null then ' They were sent a polite follow-up and automatic replies are back on.'
                when v_held then ' Their WhatsApp window has closed, so customer_support emails them the follow-up instead (within 30 minutes, when an email is on file).'
                else ' Automatic replies were never paused for this contact, so no follow-up was sent; customer_support reports it to the CEO at 24 hours to decide who answers them.' end
        || E'\nReply now: https://wa.me/' || (r.detail ->> 'phone_digits')
        || E'\nWhen handled, send DONE +' || (r.detail ->> 'phone_digits') || ' to the QuotesDone WhatsApp number.',
        p_level => 'high', p_kind => 'whatsapp_human_request', p_dedupe_key => 'wa_human_followup:' || r.id,
        p_owner_agent => 'customer_support');
    exception when others then null;   -- the follow-up is recorded below either way
    end;
    update public.agent_actions
       set detail = detail || jsonb_build_object('followed_up_at', now(), 'followup_request_id', v_req,
                                                 'followup_skipped', case when v_req is not null then null
                                                                           when not v_held then 'not held: the automatic replies were never paused'
                                                                           else 'the 24-hour WhatsApp window had closed' end)
     where id = r.id;
  end loop;
  -- B. 24 h, the reply clock (seat_handoff_kind.reply_within): customer_support reports it to the CEO, once.
  select reply_within into v_window from public.seat_handoff_kind
   where type = 'support.human_requested' and from_seat = 'customer_support' and to_seat = 'customer_support';
  v_window := coalesce(v_window, interval '24 hours');
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.created_at < now() - v_window and not (a.detail ? 'escalated_report_id')
            order by a.id limit 20 loop
    v_rep := public.fn_support_report_to_ceo('wa_human:' || r.id, 'serious',
      'A WhatsApp contact asked for a person and nobody answered within ' || v_window || ' (handoff ' || r.id || ')',
      jsonb_build_object('handoff_id', r.id, 'phone_digits', r.detail ->> 'phone_digits', 'asked_at', r.created_at,
                         'event', r.detail ->> 'event', 'followed_up_at', r.detail ->> 'followed_up_at',
                         'followup_request_id', r.detail ->> 'followup_request_id', 'followup_skipped', r.detail ->> 'followup_skipped'),
      jsonb_build_array('customer_support alerted the founder at ' || to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
                        coalesce('customer_support followed up with the contact at ' || (r.detail ->> 'followed_up_at'),
                                 'customer_support has not yet followed up with the contact')),
      'Decide who answers this contact today (call, email or WhatsApp from the company number) and record it. The request stays open until the contact was followed up and this report is completed.',
      p_review_in => interval '4 hours', p_source_agent => 'customer_support');
    if coalesce((v_rep ->> 'ok')::boolean, false) then
      update public.agent_actions
         set detail = detail || jsonb_build_object('escalated_report_id', (v_rep ->> 'report_id')::bigint, 'escalated_at', now())
       where id = r.id;
      n_esc := n_esc + 1;
    end if;
  end loop;

  -- The loop closes when the contact was followed up AND the CEO's report is completed; the verdict names both.
  for r in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail ->> 'type' = 'support.human_requested'
              and a.detail ? 'followed_up_at' and a.detail ? 'escalated_report_id'
            order by a.id limit 20 loop
    select * into rep from public.support_ceo_report where id = (r.detail ->> 'escalated_report_id')::bigint;
    continue when rep.id is null or rep.status <> 'completed';
    perform set_config('qd.handoff_closer', 'customer_support', true);
    perform public.fn_seat_handoff_complete(r.id, coalesce(r.evidence, '{}'::jsonb) || jsonb_build_object(
      'verified_by', 'customer_support', 'verified_at', now(),
      'verdict', 'followed up ' || (r.detail ->> 'followed_up_at')
                 || coalesce(' (' || (r.detail ->> 'followup_skipped') || ')', '')
                 || '; the CEO decided (report ' || rep.id || '): ' || left(coalesce(rep.completion_note, rep.acceptance_receipt, 'completed'), 400)));
    perform set_config('qd.handoff_closer', '', true);
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('ok', true, 'due', n, 'followups_queued', v_sent, 'escalated', n_esc, 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_wa_human_request_tick() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. THE ANSWER TO A CONFIRMED CUSTOMER, AND WHAT IT DOES
--
-- 8a. A CANCEL IS CONFIRMED BEFORE IT IS DONE (review of #1844: a cancel is irreversible and was carried out on a
--     model-classified intent plus the first digit run in the message). The first ask is answered with "reply yes <ref>
--     within 30 minutes"; the ask is recorded on its wa_answer_log row (refusal_reason 'awaiting cancel confirmation:<id>',
--     the reason nothing was done yet). Only a later reply that confirms AND names that request cancels it.
create or replace function public.fn_wa_is_cancel_confirmation(p_body text)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  -- A confirm word, English or Arabic, AND nothing else: every WORD of the message (digits and punctuation are not
  -- words) is a confirm word or one of the few that go with one. Re-review of #1844: "yes, change the quantity on 1043
  -- to 40", "yes, edit 1043" and "yes add 1043" each said yes and named the request, and none is a cancel.
  select coalesce(p_body, '') ~* ('(^|[^[:alpha:]])(' || x.w || ')([^[:alpha:]]|$)')
     and not exists (select 1 from regexp_split_to_table(lower(coalesce(p_body, '')), '[^[:alpha:]]+') t
                      where t <> '' and t !~ ('^(' || x.w || '|' || x.c || ')$'))
    from (select 'yes|yep|confirm|confirmed|'
                 || 'نعم|أؤكد|اؤكد|تأكيد|أكد|موافق' as w,
                 'cancel|please|pls|request|the|it|ok|okay|sure|thanks|thank|you|'
                 || 'إلغاء|الغاء|ألغوا|الغوا|الطلب|طلب|رقم|من|فضلكم|لو|سمحتم|شكرا' as c) x
$fn$;
revoke execute on function public.fn_wa_is_cancel_confirmation(text) from public, anon, authenticated;

-- wa_answer_log had only its key and a partial index on unmatched rows, so the lookup below walked the whole log on every
-- confirmation-shaped message (re-review of #1844). 835 rows on 3 Nov 2026: built in the apply's transaction, not
-- concurrently.
create index if not exists wa_answer_log_pending_cancel on public.wa_answer_log (identity_id, id desc) where intent_key = 'cancel_request';

create or replace function public.fn_wa_pending_cancel(p_customer uuid)
returns uuid language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select nullif(split_part(l.refusal_reason, ':', 2), '')::uuid
    from public.wa_answer_log l
   where l.identity_kind = 'customer' and l.identity_id = p_customer::text and l.intent_key = 'cancel_request'
     and l.refusal_reason like 'awaiting cancel confirmation:%' and l.received_at > now() - interval '30 minutes'
   order by l.id desc limit 1
$fn$;
revoke execute on function public.fn_wa_pending_cancel(uuid) from public, anon, authenticated;

create or replace function public.fn_wa_customer_request_answer(p_customer uuid, p_phone text, p_intent text, p_body text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.customers; v_facts jsonb; v_open jsonb; v_pick jsonb; v_set jsonb; e jsonb; v_first bigint; v_refs text; v_body text;
        v_lines text := ''; v_line text; v_h bigint; a public.agent_actions; v_res jsonb; v_reply text; v_ref text;
        v_when text; v_actions jsonb := '[]'::jsonb; v_mand jsonb; v_n int; v_payload jsonb;
begin
  select * into c from public.customers where id = p_customer;
  v_facts := public.fn_customer_inquiry_facts(p_customer, 10);
  -- FORMAT, not meaning. Arabic-Indic and Persian digits read as Western first (as fn_inquiry_add_missing_specs reads
  -- them), then EVERY standalone run of 2 to 9 digits is tested against the customer's own request numbers. A longer run
  -- (an IBAN, a phone number) is no request number: the old first-run ::bigint overflowed on 19 digits and lost the answer.
  v_body := translate(coalesce(p_body, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
  select x into v_pick
    from regexp_matches(v_body, '(?<![0-9])([0-9]{2,9})(?![0-9])', 'g') with ordinality r(m, ord)
    join jsonb_array_elements(v_facts) x on (x->>'ref')::bigint = r.m[1]::bigint
   order by r.ord limit 1;
  select r.m[1]::bigint into v_first from regexp_matches(v_body, '(?<![0-9])([0-9]{2,9})(?![0-9])', 'g') with ordinality r(m, ord)
   order by r.ord limit 1;
  select coalesce(jsonb_agg(x), '[]'::jsonb), string_agg(x->>'ref', ', ') into v_open, v_refs
    from jsonb_array_elements(v_facts) x where (x->>'open')::boolean;

  if p_intent = 'my_status' then
    v_reply := 'Your buyer account: email ' || case when coalesce(c.email_verified, false) then 'verified' else 'not verified yet' end
      || ', mobile ' || case when coalesce(c.phone_verified, false) then 'verified' else 'not verified yet' end
      || ', terms ' || case when c.signed_terms_url is not null then 'signed' else 'not signed yet' end
      || case when coalesce(c.email_verified, false) and coalesce(c.phone_verified, false) and c.signed_terms_url is not null
              then ', so you can post requests.' else ', so you cannot post a request until that is complete.' end
      || ' You have ' || jsonb_array_length(v_facts) || ' request(s) with us, ' || jsonb_array_length(v_open) || ' open.';
    return jsonb_build_object('reply', v_reply, 'actions', v_actions);
  end if;

  -- A BUYER'S OWN FILE (review of #1844: my_documents gave a buyer the supplier template with its {{company_name}} and
  -- {{missing_list}} slots unfilled). The buyer's mandatory four are read from fn_customer_mandatory_check.
  if p_intent = 'my_documents' then
    v_mand := public.fn_customer_mandatory_check(p_customer);
    v_reply := 'Your buyer account file'
      || case when coalesce((v_mand->>'complete')::boolean, false)
              then ' is complete: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_mand->'have') x) || '.'
              else ' still needs: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_mand->'missing') x) || '.'
                   || coalesce(' On file: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_mand->'have') x) || '.', '') end
      || ' You can complete it in your account at https://quotesdone.com';
    return jsonb_build_object('reply', v_reply, 'actions', v_actions);
  end if;

  if jsonb_array_length(v_facts) = 0 then
    return jsonb_build_object('reply', 'You have no requests with us yet. You can post one at https://quotesdone.com', 'actions', v_actions);
  end if;

  -- ------------------------------------------------------------------ L4: CANCEL, ASKED THEN CONFIRMED (8a)
  if p_intent = 'cancel_request' then
    if v_pick is null then
      -- a bare "yes" while a cancel waits: name the request it would cancel, rather than restart the loop
      v_ref := (select x->>'ref' from jsonb_array_elements(v_facts) x where (x->>'id')::uuid = public.fn_wa_pending_cancel(p_customer));
      if v_ref is not null then
        return jsonb_build_object('reply', 'To cancel request ' || v_ref || ', reply yes ' || v_ref || '. Nothing is cancelled until you do.', 'actions', v_actions);
      end if;
      v_reply := case when jsonb_array_length(v_open) = 0 then 'You have no open request to cancel.'
        else 'To cancel, reply with the word cancel and the request number, for example: cancel ' || (v_open->0->>'ref')
             || '. Your open requests: ' || v_refs || '.' end;
      return jsonb_build_object('reply', v_reply, 'actions', v_actions);
    end if;
    v_ref := v_pick->>'ref';
    if v_pick->>'status' = 'cancelled' then
      return jsonb_build_object('reply', 'Request ' || v_ref || ' was already cancelled.', 'actions', v_actions);
    end if;
    if not (v_pick->>'open')::boolean then
      return jsonb_build_object('reply', 'Request ' || v_ref || ' cannot be cancelled now: ' || (v_pick->>'status_meaning') || '.', 'actions', v_actions);
    end if;
    if not (public.fn_wa_is_cancel_confirmation(v_body) and public.fn_wa_pending_cancel(p_customer) = (v_pick->>'id')::uuid) then
      return jsonb_build_object('reply', 'Please confirm: to cancel request ' || v_ref || ' (' || coalesce(v_pick->>'category', 'request')
          || coalesce(', ' || (v_pick->>'emirate'), '') || '), reply yes ' || v_ref || ' within 30 minutes. Nothing is cancelled until you confirm, '
          || 'and a cancelled request cannot be reopened.',
        'actions', v_actions, 'pending_cancel', v_pick->>'id');
    end if;
    v_res := public.fn_cancel_inquiry((v_pick->>'id')::uuid, p_customer, 'the customer asked on WhatsApp and confirmed');
    v_actions := v_actions || jsonb_build_array(jsonb_build_object('cancel', v_res, 'ref', v_pick->'ref'));
    v_reply := case
      when v_res->>'already_cancelled' = 'true' then 'Request ' || v_ref || ' was already cancelled.'
      when v_res ? 'error' then coalesce(v_res->>'message', 'Request ' || v_ref || ' could not be cancelled (' || (v_res->>'error') || ').')
      else 'Request ' || v_ref || ' is cancelled. The ' || coalesce(v_res->>'suppliers_told', '0')
           || ' supplier(s) invited to quote were told'
           || case when coalesce((v_res->>'suppliers_not_reached')::int, 0) > 0 then ' (' || (v_res->>'suppliers_not_reached') || ' more could not be reached by email)' else '' end
           || case when v_res->>'customer_told' = 'true' then ', and a confirmation is on its way to your email' else '' end || '.' end;
    return jsonb_build_object('reply', v_reply, 'actions', v_actions);
  end if;

  -- ------------------------------------------------------------------ L2: A CHANGE OR AN ADDED DETAIL
  if p_intent = 'change_request' then
    v_pick := coalesce(v_pick, case when jsonb_array_length(v_open) = 1 then v_open->0 end);
    if v_pick is null then
      v_reply := case when jsonb_array_length(v_open) = 0 then 'You have no open request to change. You can post a new one at https://quotesdone.com'
        else 'Which request is this for? Your open requests: ' || v_refs || '. Reply with the request number and the change, for example: request '
             || (v_open->0->>'ref') || ': the quantity is now 40.' end;
      return jsonb_build_object('reply', v_reply, 'actions', v_actions);
    end if;
    v_res := public.fn_inquiry_change_from_customer((v_pick->>'id')::uuid, p_customer, p_body, 'whatsapp');
    v_actions := v_actions || jsonb_build_array(jsonb_build_object('change', v_res, 'ref', v_pick->'ref'));
    v_ref := v_pick->>'ref';
    -- the reply claims only what was done: a held Arabic change has been sent to nobody yet, and with no supplier
    -- matched it waits for the match (review of #1844)
    v_reply := case
      when v_res->>'error' = 'inquiry_closed' then 'Request ' || v_ref || ' is ' || coalesce(v_res->>'status', 'closed') || ', so it can no longer be changed. You can post a new request at https://quotesdone.com'
      when v_res->>'error' = 'already_revealed' then 'Request ' || v_ref || ' already has a revealed supplier, so please agree the change with them directly.'
      when v_res->>'error' = 'too_many_notes' then 'Request ' || v_ref || ' has had many changes in the last hour. Please send the rest in an hour, or add it on the request in your account.'
      when v_res ? 'error' then 'The change could not be added to request ' || v_ref || ' (' || (v_res->>'error') || '). Please add it on the request in your account.'
      when v_res->>'duplicate' = 'true' then 'I already added this change to request ' || v_ref || ' a little earlier, so it was not sent again.'
      when coalesce((v_res->>'suppliers_matched')::int, 0) = 0 then 'I have added your change to request ' || v_ref
           || '. The request is not with any supplier yet, so the change goes to suppliers with the request once they are matched.'
      when v_res->>'held_for_english' = 'true' then 'I have added your change to request ' || v_ref
           || '. It goes to the suppliers invited to quote as soon as its English copy is ready'
           || case when coalesce((v_res->>'quoted_told')::int, 0) > 0
                   then '; the ' || (v_res->>'quoted_told') || ' who already quoted were told a change is on its way and asked to confirm or revise their price' else '' end || '.'
      when coalesce((v_res->>'suppliers_told')::int, 0) = 0 then 'I have added your change to request ' || v_ref
           || '. The invited suppliers see it on the request when they open it.'
      else 'I have added your change to request ' || v_ref || ' and sent it to the ' || (v_res->>'suppliers_told')
           || ' supplier(s) invited to quote' || case when coalesce((v_res->>'quoted_told')::int, 0) > 0
             then '; the ' || (v_res->>'quoted_told') || ' who already quoted were asked to confirm or revise their price' else '' end
           || '. You can see it on the request in your account.' end
      -- whichever branch answered, a supplier the delivery could not reach is said, never counted as told
      || case when coalesce((v_res->>'delivery_failed')::int, 0) > 0
              then ' ' || (v_res->>'delivery_failed') || ' invited supplier(s) could not be reached by email; sending the same change again retries them.' else '' end;
    return jsonb_build_object('reply', v_reply, 'actions', v_actions);
  end if;

  -- ------------------------------------------------------------------ L1: STATUS (my_requests, my_quotes, my_jobs, by_id, and any
  -- other own-record intent a buyer asks: a buyer is never handed a supplier template)
  if p_intent = 'by_id' and v_first is not null and v_pick is null then
    return jsonb_build_object('reply', 'I could not find request ' || v_first || ' on your account. Your requests: '
      || (select string_agg(x->>'ref', ', ') from jsonb_array_elements(v_facts) x) || '.', 'actions', v_actions);
  end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_set from (
    select x from jsonb_array_elements(case when v_pick is not null then jsonb_build_array(v_pick) else v_facts end) x limit 5) z;
  for e in select x from jsonb_array_elements(v_set) x loop
    v_line := 'Request ' || coalesce(e->>'ref', '?') || ' (' || coalesce(e->>'category', 'request') || coalesce(', ' || (e->>'emirate'), '') || '): '
      || (e->>'status_meaning') || '. Sent to ' || (e->>'suppliers_received') || ' supplier(s); ' || (e->>'quotes_received') || ' quote(s) so far'
      || case when e->>'revealed' = 'true' then coalesce('; you revealed ' || (select string_agg(coalesce(r->>'supplier', 'the supplier')
                                                                          || coalesce(' (AED ' || (r->>'amount_aed') || ')', ''), ', ')
                                                                          from jsonb_array_elements(e->'revealed_quotes') r), '') else '' end
      || case when e->'price_band' is not null and e->'price_band' <> 'null'::jsonb
              then '; the ' || (e->>'sealed_quotes') || ' not yet revealed average ' || (e->'price_band'->>'average_label') || ' (rounded)' else '' end
      || case when (e->>'open')::boolean and not (e->>'late')::boolean and (e->>'quotes_received')::int < 3 and e->>'quotes_due_by' is not null
              then '; quotes are due by ' || to_char((e->>'quotes_due_by')::timestamptz at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (UAE time)' else '' end
      || '.';
    if (e->>'late')::boolean then
      -- ONE OPEN CHASE PER REQUEST (review of #1844: the key held the Dubai date, so a second ask after midnight opened a
      -- second chase and the closer told the customer twice). A pending chase is reused; a new one is round n+1 of that
      -- request; and a concurrent first ask that loses the race on agent_actions_dedupe reads the winner's row.
      v_h := null;
      select x.id into v_h from public.agent_actions x
       where x.kind = 'handoff' and x.detail->>'type' = 'inquiry.status_chase' and x.detail->>'from' = 'customer_support'
         and x.detail->>'inquiry_id' = e->>'id' and x.status = 'pending'
       order by x.id desc limit 1;
      if v_h is null then
        select count(*) into v_n from public.agent_actions x
         where x.kind = 'handoff' and x.detail->>'type' = 'inquiry.status_chase' and x.detail->>'from' = 'customer_support'
           and x.detail->>'inquiry_id' = e->>'id';
        v_payload := jsonb_build_object('inquiry_id', e->>'id', 'rfq_no', e->'ref', 'customer_id', p_customer,
                 'phone_digits', regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 'asked', left(coalesce(p_body, ''), 300),
                 'next_update_by', now() + interval '24 hours', 'channel', 'whatsapp');
        begin
          v_h := public.fn_seat_handoff('customer_support', 'sales_engineer', 'inquiry.status_chase', 'inquiries',
                   (e->>'id') || ':' || (v_n + 1), v_payload);
        exception when unique_violation then
          select x.id into v_h from public.agent_actions x
           where x.kind = 'handoff' and x.detail->>'type' = 'inquiry.status_chase' and x.detail->>'from' = 'customer_support'
             and x.detail->>'inquiry_id' = e->>'id' and x.status = 'pending'
           order by x.id desc limit 1;
        end;
      end if;
      if v_h is not null then
        select * into a from public.agent_actions where id = v_h;
        -- a chase whose handler failed is reported, so the reply's "it has been reported" is true (re-review of #1844)
        if a.status = 'failed' then
          perform public.fn_it_engineer_finding_upsert('customer_support:status_chase_failed:' || v_h,
            'A status chase could not start (handoff ' || v_h || ')', 'public.fn_sales_engineer_chases_for_status', 'customer_facing', 1,
            jsonb_build_object('handoff_id', v_h, 'inquiry_id', e->>'id', 'error', a.detail->>'error', 'owner_seat', 'sales_engineer'),
            '{}'::text[], array['why fn_sales_engineer_chases_for_status failed for this request'], 'customer_support');
        end if;
        v_when := to_char(coalesce((a.evidence->>'next_update_by')::timestamptz, (a.detail->>'next_update_by')::timestamptz) at time zone 'Asia/Dubai', 'DD Mon HH24:MI');
        v_line := v_line || case
          when a.status = 'failed' then ' It is past the time quotes were due, but the chase could not be started automatically; it has been reported so it is started by hand.'
          -- a chase whose follow-up failed three times promises nothing it cannot send (re-review of #1844)
          when coalesce((a.detail->>'followup_attempts')::int, 0) >= 3 then ' Our sales engineer has been chasing it since '
               || to_char(a.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' (UAE time), but our updates to you about it could not be delivered; '
               || 'this has been reported, and you can ask me here for the latest at any time.'
          when a.created_at = now() then ' It is past the time quotes were due (' || to_char((e->>'quotes_due_by')::timestamptz at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
               || ' UAE time) with ' || (e->>'quotes_received') || ' of the 3 quotes we aim for, so I have asked our sales engineer to chase it: '
               || 'the ' || (coalesce((a.evidence->>'chased')::int, 0) + coalesce((a.evidence->>'already_reminded_today')::int, 0))
               || ' invited supplier(s) who have not quoted were reminded today'
               || '. You will get a message here as soon as a new quote arrives, and an update by ' || v_when || ' (UAE time) either way.'
          else ' Our sales engineer has been chasing it since ' || to_char(a.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')
               || ' (UAE time); you will get a message as soon as a new quote arrives, and an update by ' || v_when || ' (UAE time) either way.' end;
        v_actions := v_actions || jsonb_build_array(jsonb_build_object('status_chase_handoff', v_h, 'ref', e->'ref'));
      end if;
    end if;
    v_lines := v_lines || case when v_lines = '' then '' else chr(10) end || v_line;
  end loop;
  if v_pick is null and jsonb_array_length(v_facts) > 5 then
    v_lines := v_lines || chr(10) || 'Your other requests are in your account at https://quotesdone.com';
  end if;
  return jsonb_build_object('reply', v_lines, 'actions', v_actions);
end $fn$;
revoke execute on function public.fn_wa_customer_request_answer(uuid, text, text, text) from public, anon, authenticated;
-- The four routines this file replaces. CREATE OR REPLACE keeps their ACL (service_role only, measured on production
-- 3 Nov 2026; every caller is an edge function's service-role client), so these change nothing live: they state the
-- rule in the file that now owns them.
revoke execute on function public.fn_cancel_inquiry(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.fn_wa_answer(text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_wa_context(text, text) from public, anon, authenticated;
revoke execute on function public.fn_wa_fact_pack(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 9. fn_wa_answer: a CONFIRMED customer is a known party (unchanged for suppliers and unknown numbers)
create or replace function public.fn_wa_answer(p_from text, p_body text, p_intent text DEFAULT NULL::text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_body     text := lower(btrim(coalesce(p_body, '')));
  v_intent   public.wa_reply_intent;
  v_reply    text;
  v_lead     record;
  v_lead_id  bigint;
  v_cust     uuid;
  v_ident_k  text := 'unknown';
  v_ident_id text := null;
  v_id       bigint;
  v_missing  text;
  v_cfg      record;
  v_log      bigint;
  v_ans      jsonb;
begin
  if v_body = '' then
    return jsonb_build_object('ok', false, 'reason', 'Empty message.');
  end if;

  select standard_reveal_rate, supplier_free_count, supplier_reg_fee into v_cfg
    from public.pricing_config order by id limit 1;

  -- WHO IS ASKING. Identity gates every 'own_records' answer, so one supplier can never be told
  -- another supplier's business by sending a lucky message.
  v_lead_id := public.fn_wa_lead_id(p_from);
  if v_lead_id is not null then
    select * into v_lead from public.leads where id = v_lead_id;
    v_ident_k := 'lead'; v_ident_id := v_lead_id::text;
  else
    -- 3 Nov 2026: a CONFIRMED customer is known too (fn_whatsapp_owner: one party or nobody).
    select o.customer_id into v_cust from public.fn_whatsapp_owner(p_from) o where o.party_kind = 'customer';
    if v_cust is not null then v_ident_k := 'customer'; v_ident_id := v_cust::text; end if;
  end if;

  -- A CONFIRMATION OF A PENDING CANCEL is the cancel conversation, whatever the classifier made of "yes 1043" (8a):
  -- the request is still named and checked against the pending one inside fn_wa_customer_request_answer.
  -- Whatever the classifier made of a bare "yes 1043" (a status or by-id reading is plausible), except a message it read
  -- as a change (re-review of #1844); fn_wa_is_cancel_confirmation admits nothing but a bare confirmation.
  if v_cust is not null and p_intent is distinct from 'change_request'
     and public.fn_wa_is_cancel_confirmation(v_body) and public.fn_wa_pending_cancel(v_cust) is not null then
    p_intent := 'cancel_request';
  end if;

  -- THE INTENT, AS REASONED. Read by key from the active rows; the body is not read for meaning.
  select * into v_intent from public.wa_reply_intent where active and intent_key = p_intent;

  -- NOTHING TO ANSWER FROM. An honest refusal that names what it would need. Never a guess.
  if not found then
    v_reply := public.fn_wa_unmatched_reply();
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, false, v_reply,
            case when p_intent is null
                 then 'Not reasoned yet (the model hold). The meaning waits in customer_support''s queue and is answered on WhatsApp when it is reasoned.'
                 when p_intent = 'none' then 'Reasoned: no intent row fits. This row is the backlog: a real question with no resolver.'
                 else 'Reasoned as ' || p_intent || ': answered outside the intent table (size statement, trade list), not backlog.' end)
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', false, 'reply', v_reply, 'log_id', v_log,
                              'intent_decided_by', case when p_intent is null then 'held: not yet reasoned' else 'reasoning' end);
  end if;

  -- IDENTITY REQUIRED BUT UNKNOWN.
  if v_intent.requires_identity and v_lead_id is null and v_cust is null then
    v_reply := 'I do not recognise this number yet, so I cannot look up your records. Reply with the '
            || 'email address you registered with, or REGISTER to start a new registration.';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            'Intent reasoned but the sender is not a known party.')
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key, 'reply', v_reply, 'log_id', v_log);
  end if;

  -- A CONFIRMED CUSTOMER'S OWN REQUESTS (3 Nov 2026): answered from their rows, and the ask is acted on
  -- (a late request is chased, a change reaches the suppliers, a cancel is asked and then carried out). Review of
  -- #1844: EVERY own-record intent a buyer asks is answered here, so a buyer never falls through to a supplier template
  -- (my_documents gave its {{company_name}} / {{missing_list}} text as a fact).
  if v_cust is not null and (v_intent.requires_identity or v_intent.scope in ('own_records', 'by_id')
                             or v_intent.intent_key in ('my_requests', 'my_status', 'my_quotes', 'my_jobs', 'my_documents', 'by_id', 'change_request', 'cancel_request')) then
    v_ans := public.fn_wa_customer_request_answer(v_cust, p_from, v_intent.intent_key, p_body);
    v_reply := v_ans->>'reply';
    insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply, refusal_reason)
    values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply,
            case when v_ans ? 'pending_cancel' then 'awaiting cancel confirmation:' || (v_ans->>'pending_cancel') end)
    returning id into v_log;
    return jsonb_build_object('ok', true, 'matched', true, 'intent', v_intent.intent_key,
      'identity_kind', v_ident_k, 'identity_id', v_ident_id, 'reply', v_reply, 'actions', v_ans->'actions',
      'log_id', v_log, 'answered_by', 'deterministic', 'intent_decided_by', 'reasoning');
  end if;

  v_reply := v_intent.answer_template;

  -- COMPANY SLOTS, the same for everyone.
  v_reply := replace(v_reply, '{{reveal_rate}}', coalesce(round(v_cfg.standard_reveal_rate * 100, 1)::text || '%', '3%'));
  v_reply := replace(v_reply, '{{free_count}}',  coalesce(v_cfg.supplier_free_count::text, '1000'));
  v_reply := replace(v_reply, '{{reg_fee}}',     coalesce(round(v_cfg.supplier_reg_fee)::text, '1000'));

  -- THE APPROVED PUBLIC CONTACT, read from the settings that say publication in their names -- never from
  -- founder_mobile. Absent, the slot ADMITS it rather than rendering an empty string.
  v_reply := replace(v_reply, '{{founder_public_phone}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
             '(no approved public contact is configured yet)'));
  v_reply := replace(v_reply, '{{founder_public_name}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_name'),
             'the owner'));

  -- OWN-RECORD SLOTS, read from this sender's row only.
  if v_lead_id is not null then
    v_reply := replace(v_reply, '{{company_name}}', coalesce(v_lead.company_name, 'your company'));
    v_reply := replace(v_reply, '{{reg_status}}',   coalesce(v_lead.registration_status, 'not started'));
    v_reply := replace(v_reply, '{{approval_status}}', coalesce(v_lead.approval_status, 'not yet reviewed'));

    -- The founder's mandatory six, not the ten the scoring view happens to list.
    select string_agg(m, ', ') into v_missing from (
      select 'a UAE mobile number' as m where coalesce(btrim(v_lead.phone_e164), '') = ''
      union all select 'an email address' where coalesce(btrim(v_lead.email), '') = ''
      union all select 'your trade licence' where coalesce(btrim(v_lead.license_doc_path), '') = ''
      union all select 'your company profile' where coalesce(btrim(v_lead.company_profile_doc_path), '') = ''
      union all select 'a signed copy of our terms' where coalesce(btrim(v_lead.signed_terms_path), '') = ''
    ) x;
    v_reply := replace(v_reply, '{{missing_list}}', coalesce(v_missing, 'nothing, your file is complete'));
    v_reply := replace(v_reply, '{{missing_line}}',
      case when v_missing is null then 'Your file is complete.'
           else 'We still need: ' || v_missing || '.' end);

    v_reply := replace(v_reply, '{{quote_count}}', '0');
    v_reply := replace(v_reply, '{{quote_detail}}',
      'No quotes yet. Once a buyer posts a request in your category you will be invited to quote.');
    v_reply := replace(v_reply, '{{awarded_count}}', '0');
    v_reply := replace(v_reply, '{{awarded_detail}}',
      'No jobs awarded yet. You will get a message here the moment one is.');
  end if;

  -- BY-ID LOOKUP. A number in the body is resolved against the real records, and returned ONLY to a
  -- party who appears on that record. The digits are FORMAT: the first standalone run of 2 to 9, Arabic-Indic and Persian
  -- digits read as Western (review of #1844: an unbounded run overflowed bigint on an IBAN and lost the answer).
  if v_intent.scope = 'by_id' then
    v_id := (regexp_match(translate(v_body, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'), '(?<![0-9])([0-9]{2,9})(?![0-9])'))[1]::bigint;
    if v_id is null then
      v_reply := 'Send me the number and I will look it up. For example: quote 1234, or job 5678.';
    else
      v_reply := replace(v_reply, '{{id_answer}}',
        'I could not find a record numbered ' || v_id || ' that you are a party to. Check the number, '
        || 'or reply HUMAN and the team will look into it.');
    end if;
  end if;

  insert into public.wa_answer_log (from_phone, body, identity_kind, identity_id, intent_key, matched, reply)
  values (p_from, p_body, v_ident_k, v_ident_id, v_intent.intent_key, true, v_reply)
  returning id into v_log;

  return jsonb_build_object(
    'ok', true, 'matched', true, 'intent', v_intent.intent_key,
    'identity_kind', v_ident_k, 'identity_id', v_ident_id,
    'reply', v_reply, 'log_id', v_log, 'answered_by', 'deterministic', 'intent_decided_by', 'reasoning'
  );
end;
$function$;

-- verdict (the routines, the conversation, the duty and the grants; the behaviour is proven by the _probe file)
select case when to_regprocedure('public.fn_customer_inquiry_facts(uuid,integer)') is not null
             and to_regprocedure('public.fn_wa_customer_request_answer(uuid,text,text,text)') is not null
             and to_regprocedure('public.fn_inquiry_change_from_customer(uuid,uuid,text,text)') is not null
             and to_regprocedure('public.fn_sales_engineer_chases_for_status(bigint)') is not null
             and to_regprocedure('public.fn_customer_support_closes_status_chases()') is not null
             and to_regprocedure('public.fn_wa_human_request_email_followup()') is not null
             and to_regprocedure('public.fn_scrub_customer_identity(text,uuid)') is not null
             and to_regprocedure('public.fn_wa_is_cancel_confirmation(text)') is not null
             and to_regprocedure('public.fn_wa_pending_cancel(uuid)') is not null
             and to_regclass('public.wa_answer_log_pending_cancel') is not null
             and exists (select 1 from public.seat_duty where duty = 'customer_support.person_followup_email' and enabled)
             and exists (select 1 from public.seat_handoff_kind where type = 'inquiry.status_chase' and originator_closes)
             and exists (select 1 from public.seat_duty where duty = 'customer_support.status_chase_close' and enabled)
             and (select count(*) from public.wa_reply_intent where intent_key in ('my_requests', 'change_request', 'cancel_request') and active) = 3
             and not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                              and p.proname in ('fn_customer_inquiry_facts', 'fn_wa_customer_request_answer', 'fn_inquiry_change_from_customer',
                                                'fn_sales_engineer_chases_for_status', 'fn_customer_support_closes_status_chases',
                                                'fn_wa_human_request_email_followup', 'fn_scrub_customer_identity',
                                                'fn_wa_is_cancel_confirmation', 'fn_wa_pending_cancel', 'fn_wa_human_request_tick')
                              and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')))
        then 'PROBE OK' else 'PROBE FAILED: a routine, the status_chase conversation, its duty, the three intents or the grants' end as verdict;
