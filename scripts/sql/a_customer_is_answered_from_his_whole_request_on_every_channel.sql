-- A CUSTOMER IS ANSWERED FROM HIS WHOLE REQUEST, ON EVERY CHANNEL.
--
-- Seat: customer_support. 16 Nov 2026. Agent: customer_support builder (whole request on every channel, ledger 1711).
-- The founder (ledger 1711): "a customer ... mentioned a budget in the inquiry itself when he is in chat with the sales agent.
-- How is that memory recorded properly ...? ... he opens a chat later on WhatsApp and he says, 'What happened with my inquiry?
-- Did you find anyone below 5,000?' ... I don't want the system to be rule-based only, like 1 + 1 = 2. No, it's scenarios".
--
-- WHAT WAS THERE (read on main d26e35235):
--   * What he asked IS stored, on the request itself: create_inquiry writes inquiries.budget (his words, up to 80 characters),
--     required_by, delivery_window, floor, emirate, spec (with spec.customer_requirements: materials and brands asked,
--     installation, warranty, the date; and spec.site_location, his own site), boq and accepted_alternatives
--     (customer_api/actions/inquiry_create.ts:190-209, :361, :448). The request chat (inquiry_intake) is where he says them
--     (inquiry_intake/handle.ts:471, :935). quote_compare sends the budget and the spec to the comparison model
--     (quote_compare/index.ts:69, :364).
--   * The facts every customer channel reads did not carry any of it. fn_customer_inquiry_facts
--     (a_customer_asking_on_whatsapp_reads_their_own_requests_and_every_ask_closes_its_loop.sql:62-133) gave status, quotes
--     received and wanted, the due time, late, revealed quotes and, before a reveal, only a rounded band of the sealed quotes
--     and only from two. No budget, no date, no specs or brands asked, no per-quote price or fit. "Anyone below 5,000?" could
--     not be answered from facts, and with one quote nothing about price could be said. Its readers: fn_wa_context (WhatsApp
--     own record, wa_inbound/identify.ts:28; the website widget and the signed-in site chat, site_assistant/index.ts:323),
--     fn_wa_fact_pack (WhatsApp fact pack, through fn_wa_route) and fn_wa_customer_request_answer (the database's answer).
--     The e-mail reply read fn_customer_stats instead (email_triage/account_facts.ts:105) and the portal chat read its own
--     quotes (sales_engineer/lib/own_quotes.ts), neither with what he asked.
--
-- THE ANONYMITY DECISION: WHATSAPP NOW SHOWS WHAT THE PORTAL SHOWS. Before the reveal the customer's portal already shows each
-- quote's price under its letter, with the supplier's name sealed:
--   * customer_api my_inquiries serves `price: q.quote_amount` for every listed quote, revealed or not, beside
--     `label` (Supplier A ...) and `supplier_name: revealed ? ... : undefined` (customer_api/actions/inquiry_lifecycle.ts:345);
--   * the quote card prints it: `{aed(q.price)}` next to the sealed name (src/components/me/requests/QuoteCard.tsx:121), with
--     the price and VAT as the supplier stated them (:127-128, rulings 1207/1208);
--   * the portal chat gives the model each quote's `amount` under its letter before the reveal
--     (sales_engineer/lib/own_quotes.ts:62-67).
-- Only the spread chart (src/components/me/requests/Progress.tsx:51-60) draws one band instead of one bar per quote. The
-- rulings that bind the reveal are about IDENTITY: the supplier's name, contacts, licence and TRN (the-only-hard-rules
-- memory note), places below the emirate (ruling 1683, _shared/identity_places.ts) and brands and model numbers (ruling
-- 1589, _shared/quote_generalise.ts). None hides a price. So WhatsApp, the widget and e-mail were stricter than the portal
-- for the same person on the same request, and the same question got a number on one door and "a rounded band" on another.
-- They are aligned with the portal here: each live quote's price (ex VAT, and with VAT as stated), its letter, its
-- validity, its lead time and warranty as stated (with the supplier's own name, its own brand and model values and any
-- contact masked, and generalised again in code by _shared/own_request_facts.ts before a model reads it), and the sales
-- engineer's notes against the request. The supplier's name stays out until a reveal; a sanctioned supplier is never named
-- (instruction 516). price_band is kept unchanged for the readers that quote it (fn_wa_customer_request_answer).
--
-- THE LETTER. On main no letter is stored: customer_supplier_letter exists only on the unmerged branch
-- sales_engineer-the-customer-is-asked-in-plain-words-and-sees-one-letter-per-supplier
-- (a_suppliers_letter_is_kept_from_the_first_time_the_customer_sees_it.sql). fn_customer_quote_letters reads that table when
-- it exists (so this file needs no change when that branch lands) and otherwise derives the letter exactly as the portal does:
-- the request's quotes not draft or withdrawn and not from a sanctioned supplier, cheapest first (my_inquiries orders by
-- quote_amount), one letter per supplier in order of first appearance, "Supplier A - Option 2" when one supplier sent two
-- (_shared/quote_labels.ts labelQuotes). Known difference until the stored letter lands: the portal also leaves out a quote
-- that its code-side hold rule holds for missing details (_shared/reveal_guard.ts heldQuoteIds reads the quote lines and
-- cannot run in SQL), so where such a quote is cheaper than another its letters can differ from the portal's. With the
-- stored table a supplier the portal never showed has no letter here either (letter null, said so).
--
-- MEMORY ACROSS CHANNELS. The request row is the durable record of what he told the sales engineer. The case summary
-- (support_case_memory.ts) is written from support exchanges and never saw the request chat; its block now says the request
-- facts are the record of what he asked (support_case_memory.ts caseBlock), and the facts carry the changes he sent after
-- the request went out (rfq_clarification notes: "my budget changed to 7,000"), newest last.
--
-- THE MODEL REASONS, THE DATABASE SUPPLIES FACTS. Nothing here compares a price with a budget, parses a budget or decides an
-- answer: the budget is given as he wrote it, the prices as stated, and the reply rule (_shared/own_request_facts.ts
-- OWN_REQUEST_RULE, read by WhatsApp, the widget, the portal chat and e-mail) tells the model to answer any question about
-- his own request from them and never invent. No intent row and no keyword route is added.
--
-- SIZE. The whole request ("asked"), the quotes and the comparison are given for every open request and the three newest;
-- older closed requests keep the summary keys only, so a long account does not swell every WhatsApp reply.
-- Every new routine: SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated.
-- Probe: a_customer_is_answered_from_his_whole_request_on_every_channel_probe.sql (local Postgres 16, ZZ DEMO only).
-- Deploy order: apply this file, then deploy wa_inbound, site_assistant, email_triage, sales_engineer (each reads keys this
-- file adds and ignores their absence, so either order is safe; applying first lets the deploy be checked at once).

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. THE LETTER THE CUSTOMER KNOWS EACH QUOTE BY (the stored letter when it exists, else the portal's derivation)
create or replace function public.fn_customer_quote_letters(p_inquiry uuid)
returns table(quote_id uuid, letter text, label_en text, label_ar text, option_no integer, letter_source text)
language plpgsql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_stored boolean := to_regclass('public.customer_supplier_letter') is not null;
  v_map jsonb := '{}'::jsonb;
begin
  if v_stored then
    -- the letter recorded the first time his portal showed that supplier, never changed afterwards
    execute 'select coalesce(jsonb_object_agg(l.supplier_id::text, l.letter), ''{}''::jsonb) from public.customer_supplier_letter l where l.inquiry_id = $1'
      into v_map using p_inquiry;
  else
    -- my_inquiries: quotes not draft/withdrawn (_shared/quote_live.ts), sanctioned suppliers out, cheapest first;
    -- labelQuotes: one letter per supplier in order of first appearance; A..Z, AA, AB ... (_shared/quote_labels.ts letter)
    select coalesce(jsonb_object_agg(y.k, case when y.seq < 26 then chr(65 + y.seq)
                                               else chr(65 + (y.seq / 26 - 1) % 26) || chr(65 + y.seq % 26) end), '{}'::jsonb)
      into v_map
      from (select x.k, (row_number() over (order by min(x.rn)) - 1)::int as seq
              from (select coalesce(q.supplier_id::text, 'q:' || q.id::text) as k,
                           row_number() over (order by q.quote_amount, q.created_at, q.id) as rn
                      from public.quotes q
                     where q.inquiry_id = p_inquiry and coalesce(q.status, '') not in ('draft', 'withdrawn')
                       and not exists (select 1 from public.sanctions_ban b where b.lead_id = q.supplier_id)) x
             group by x.k) y;
  end if;
  return query
    with pq as (
      select q.id, coalesce(q.supplier_id::text, 'q:' || q.id::text) as k, coalesce(q.option_no, 1) as opt
        from public.quotes q
       where q.inquiry_id = p_inquiry and coalesce(q.status, '') not in ('draft', 'withdrawn')
         and not exists (select 1 from public.sanctions_ban b where b.lead_id = q.supplier_id)),
    cnt as (select pq.k, count(*) as n from pq group by pq.k)
    select pq.id, v_map ->> pq.k,
           case when v_map ->> pq.k is null then null else 'Supplier ' || (v_map ->> pq.k) || case when c.n > 1 then ' - Option ' || pq.opt else '' end end,
           case when v_map ->> pq.k is null then null else 'المورّد ' || (v_map ->> pq.k) || case when c.n > 1 then ' - الخيار ' || pq.opt else '' end end,
           pq.opt,
           case when v_stored and v_map ->> pq.k is not null then 'stored'
                when v_stored then 'not yet shown in the portal'
                else 'derived as the portal does' end
      from pq join cnt c on c.k = pq.k;
end
$fn$;
revoke execute on function public.fn_customer_quote_letters(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. A QUOTE'S OWN WORDS, AS A CUSTOMER MAY READ THEM BEFORE THE REVEAL (lead time, warranty, validity: short fields).
-- The supplier's own company name becomes "the supplier"; the quote's own brand and model column values become what the
-- portal prints for them; e-mail addresses, web addresses and long digit runs are removed. _shared/own_request_facts.ts runs
-- the code generaliser (_shared/quote_generalise.ts, the known-brand table) over the same fields before any model reads them.
create or replace function public.fn_quote_words_for_customer(p_text text, p_quote uuid, p_revealed boolean)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp'
as $fn$
declare v text := left(btrim(coalesce(p_text, '')), 200); v_name text; r record;
begin
  if v = '' then return null; end if;
  if p_revealed then return v; end if;
  select nullif(btrim(l.company_name), '') into v_name
    from public.quotes q join public.leads l on l.id = q.supplier_id where q.id = p_quote;
  if v_name is not null and length(v_name) >= 3 then
    v := regexp_replace(v, regexp_replace(v_name, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g'), 'the supplier', 'gi');
  end if;
  for r in
    select distinct x.val, x.kind from public.quote_items qi
      cross join lateral (values (btrim(qi.brand), 'brand'), (btrim(qi.model), 'model')) x(val, kind)
     where qi.quote_id = p_quote::text and length(coalesce(x.val, '')) >= 2
  loop
    v := regexp_replace(v, '\m' || regexp_replace(r.val, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '\M',
                        case r.kind when 'brand' then 'a brand (shown after reveal)' else 'model stated (shown after reveal)' end, 'gi');
  end loop;
  v := regexp_replace(v, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[removed]', 'g');
  v := regexp_replace(v, '(https?://|www\.)\S+', '[removed]', 'gi');
  -- nine or more digits with single separators (a phone, a licence or TRN); a date (eight digits) stays
  v := regexp_replace(v, '\+?[0-9](?:[ ()-]?[0-9]){8,}', '[removed]', 'g');
  return left(v, 160);
end
$fn$;
revoke execute on function public.fn_quote_words_for_customer(text, uuid, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. ONE READING OF A CUSTOMER'S REQUESTS, NOW WITH WHAT HE ASKED AND WHAT HIS PORTAL SHOWS HIM.
-- Every key of the 3 Nov reading is kept with the same meaning, with one correction toward the portal: a sanctioned
-- supplier's sealed quote no longer counts in quotes_received, sealed_quotes or price_band (the portal never lists it). The
-- new keys are asked, changes_he_sent_after, quotes, comparison and price_rule (detailed requests only).
create or replace function public.fn_customer_inquiry_facts(p_customer uuid, p_limit integer default 10)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with cfg as (
    select coalesce((select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric
                       from public.app_secrets where key = 'sla_quote_hours'), 24) as sla_h,
           coalesce((select case when c.locale = 'ar' then 'ar' else 'en' end from public.customers c where c.id = p_customer), 'en') as lang),
  inq as (
    select i.*, row_number() over (order by i.created_at desc) as rn from public.inquiries i where i.customer_id = p_customer
     order by i.created_at desc limit greatest(coalesce(p_limit, 10), 1)),
  -- a LIVE quote, as fn_rfq_short_of_quotes_tick and the portal count it; a revealed quote is live
  q as (
    select q.id, q.inquiry_id, q.supplier_id, q.quote_amount, q.price_ex_vat, q.vat_treatment, q.vat_amount, q.amount_as_stated,
           q.gross_amount, q.discount_amount, q.expires_at, q.created_at, q.lead_time, q.warranty, q.validity, q.review_notes,
           q.option_no,
           (select min(t.revealed_at) from public.transactions t where t.quote_id = q.id and t.revealed_at is not null) as revealed_at,
           -- founder instruction 516: a sanctioned party is never shown to a customer (customer_api refuses it too)
           exists (select 1 from public.sanctions_ban sb where sb.lead_id = q.supplier_id) as sanctioned
      from public.quotes q join inq on inq.id = q.inquiry_id
     where coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled') and q.stale_at is null
       -- 16 Nov: a sanctioned supplier's SEALED quote is not counted, listed or averaged, as the portal leaves it out
       -- (customer_api my_inquiries); one already revealed stays, unnamed
       and (not exists (select 1 from public.sanctions_ban sb where sb.lead_id = q.supplier_id)
            or exists (select 1 from public.transactions t where t.quote_id = q.id and t.revealed_at is not null)))
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
      'revealed', coalesce(qq.revealed, '[]'::jsonb) <> '[]'::jsonb,
      'revealed_quotes', coalesce(qq.revealed, '[]'::jsonb),
      'sealed_quotes', coalesce(qq.sealed, 0),
      -- unchanged from 3 Nov: the rounded average of the unrevealed quotes, from two (fn_wa_customer_request_answer reads it)
      'price_band', case when coalesce(qq.sealed, 0) < 2 or qq.sealed_avg is null then null
                         else jsonb_build_object(
                                'average_rounded_to_nearest_1000', case when qq.sealed_avg < 1000 then null else round(qq.sealed_avg / 1000) * 1000 end,
                                'average_label', case when qq.sealed_avg < 1000 then 'under AED 1,000'
                                                      else 'about AED ' || to_char(round(qq.sealed_avg / 1000) * 1000, 'FM999,999,999,990') end,
                                'note', 'rounded average of the quotes not yet revealed; each quote''s own price is under quotes') end,
      'chase', ch.j)
      -- WHAT HE ASKED, AND WHAT HIS PORTAL SHOWS HIM: every open request and the three newest
      || case when not (coalesce(i.status, '') in ('open', 'sent', 'quoted', 'split') or i.rn <= 3) then '{}'::jsonb else jsonb_build_object(
      'asked', jsonb_strip_nulls(jsonb_build_object(
          'summary', left(i.summary, 600),
          -- his own words, exactly as stored; never parsed here
          'budget_as_he_stated_it', nullif(btrim(coalesce(i.budget, '')), ''),
          'required_by', i.required_by,
          'when_as_he_stated_it', nullif(btrim(coalesce(i.delivery_window, '')), ''),
          'emirate', i.emirate,
          -- his own site as he gave it; it is his, and a supplier never receives it before a reveal (_shared/site_location.ts)
          'site_as_he_gave_it', nullif(btrim(coalesce(i.spec ->> 'site_location', '')), ''),
          'floor', nullif(btrim(coalesce(i.floor, '')), ''),
          'urgency', i.urgency,
          'trades', to_jsonb(i.trades),
          -- the sales engineer's record of the materials and brands he asked for, installation, warranty and date
          'what_he_asked', case when jsonb_typeof(i.spec -> 'customer_requirements' -> 'display' -> cfg.lang) = 'array'
                                then i.spec -> 'customer_requirements' -> 'display' -> cfg.lang
                                when jsonb_typeof(i.spec -> 'customer_requirements' -> 'display' -> 'en') = 'array'
                                then i.spec -> 'customer_requirements' -> 'display' -> 'en' end,
          'quantity', i.spec -> 'quantity',
          'items', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('item', left(b ->> 'description', 160), 'qty', b -> 'qty', 'unit', b ->> 'unit')) order by o)
                      from jsonb_array_elements(case when jsonb_typeof(i.boq -> 'boq') = 'array' then i.boq -> 'boq' else '[]'::jsonb end) with ordinality e(b, o)
                     where o <= 15),
          'items_total', case when jsonb_typeof(i.boq -> 'boq') = 'array' then jsonb_array_length(i.boq -> 'boq') end,
          'alternatives_he_accepted', case when jsonb_typeof(i.accepted_alternatives) = 'array' and jsonb_array_length(i.accepted_alternatives) > 0
                                           then i.accepted_alternatives end)),
      -- what he sent after the request went out (portal notes and WhatsApp changes, fn_inquiry_change_from_customer), newest last
      'changes_he_sent_after', coalesce((select jsonb_agg(jsonb_build_object('at', n.at, 'text', n.txt) order by n.at)
                                           from (select coalesce(r.answered_at, r.asked_at) as at, left(coalesce(r.answer_as_written, r.answer), 400) as txt
                                                   from public.rfq_clarification r
                                                  where r.inquiry_id = i.id and r.kind = 'note' and r.supplier_id is null
                                                    and coalesce(r.answer_as_written, r.answer) is not null
                                                  order by r.id desc limit 5) n), '[]'::jsonb),
      -- EACH LIVE QUOTE AS HIS PORTAL SHOWS IT (customer_api my_inquiries; the anonymity decision in this file's header)
      'quotes', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                    'letter', lt.letter, 'label', case when cfg.lang = 'ar' then lt.label_ar else lt.label_en end,
                    'letter_source', lt.letter_source,
                    'price_ex_vat_aed', coalesce(z.price_ex_vat, z.quote_amount),
                    'vat_as_stated', case z.vat_treatment when 'exclusive' then 'VAT added on top of the price'
                                                          when 'inclusive' then 'the supplier''s total includes VAT'
                                                          when 'not_registered' then 'supplier not VAT registered: no VAT'
                                                          when 'zero_rated' then 'zero-rated: no VAT'
                                                          when 'exempt' then 'exempt: no VAT'
                                                          else 'VAT not stated' end,
                    'vat_aed', case when z.vat_treatment in ('exclusive', 'inclusive') then z.vat_amount end,
                    'total_with_vat_aed', case when z.vat_treatment in ('exclusive', 'inclusive') and z.vat_amount is not null
                                                 then coalesce(z.price_ex_vat, z.quote_amount) + z.vat_amount
                                               when z.vat_treatment in ('not_registered', 'zero_rated', 'exempt')
                                                 then coalesce(z.price_ex_vat, z.quote_amount) end,
                    'total_as_stated_aed', z.amount_as_stated,
                    'before_discount_aed', case when z.discount_amount > 0 then z.gross_amount end,
                    'discount_aed', case when z.discount_amount > 0 then z.discount_amount end,
                    'received_at', z.created_at,
                    'valid_until', z.expires_at, 'expired', case when z.expires_at is not null then z.expires_at < now() end,
                    'validity_as_stated', public.fn_quote_words_for_customer(z.validity, z.id, z.revealed_at is not null),
                    'lead_time_as_stated', public.fn_quote_words_for_customer(z.lead_time, z.id, z.revealed_at is not null),
                    'warranty_as_stated', public.fn_quote_words_for_customer(z.warranty, z.id, z.revealed_at is not null),
                    -- the sales engineer's checks of this quote against his request, stored when it went live (ledger 1588);
                    -- brand-free by construction (_shared/quote_review_notes.ts)
                    'notes_against_your_request', (select jsonb_agg(coalesce(case when cfg.lang = 'ar' then rn.n ->> 'ar' end, rn.n ->> 'en'))
                                                     from jsonb_array_elements(case when jsonb_typeof(z.review_notes) = 'array' then z.review_notes else '[]'::jsonb end) rn(n)
                                                    where coalesce(rn.n ->> 'en', rn.n ->> 'ar') is not null),
                    'revealed', z.revealed_at is not null,
                    'supplier', case when z.revealed_at is null then null
                                     when z.sanctioned then 'a supplier no longer on QuotesDone'
                                     else coalesce((select l.company_name from public.leads l where l.id = z.supplier_id), 'the supplier') end))
                    order by coalesce(z.price_ex_vat, z.quote_amount), z.created_at)
                  from q z left join public.fn_customer_quote_letters(i.id) lt on lt.quote_id = z.id
                 where z.inquiry_id = i.id), '[]'::jsonb),
      -- THE COMPARISON HIS PORTAL SHOWS (quote_compare's last good reading for this request; its labels are the portal's)
      'comparison', (select jsonb_strip_nulls(jsonb_build_object(
                        'as_of', cc.created_at, 'quotes_considered', cc.analysis -> 'considered',
                        'not_comparable', cc.analysis -> 'not_comparable', 'not_comparable_reason', cc.analysis ->> 'not_comparable_reason',
                        'bottom_line', cc.analysis ->> 'bottom_line', 'top3', cc.analysis -> 'top3',
                        'cheapest_label', cc.analysis ->> 'cheapest_label', 'best_value_label', cc.analysis ->> 'best_value_label',
                        'per_quote', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('label', e ->> 'label', 'price', e -> 'price',
                                                'missing_from_request', e -> 'missing_from_request', 'spec_deviation', e -> 'spec_deviation',
                                                'flags', e -> 'flags')))
                                        from jsonb_array_elements(case when jsonb_typeof(cc.analysis -> 'quotes') = 'array' then cc.analysis -> 'quotes' else '[]'::jsonb end) e)))
                      from public.qd_compare_cache cc
                     where cc.inquiry_id = i.id::text and not (cc.analysis ? '__failed')
                     order by (cc.lang = cfg.lang) desc, cc.created_at desc limit 1),
      'price_rule', 'Each quote''s price is given under its letter, exactly as his portal shows it. The supplier''s name, contacts and brand unlock only when he reveals that quote.')
      end as j
      from inq i cross join cfg
      left join lateral (select count(*)::int as n, min(x.sent_at) as first_sent
                           from public.inquiry_matches x where x.inquiry_id = i.id) m on true
      left join lateral (select count(*)::int as live, (count(*) filter (where q.revealed_at is null))::int as sealed,
                                avg(q.quote_amount) filter (where q.revealed_at is null) as sealed_avg,
                                jsonb_agg(jsonb_build_object('supplier', case when q.sanctioned then 'a supplier no longer on QuotesDone' else coalesce(l.company_name, 'the supplier') end,
                                          'amount_aed', q.quote_amount, 'revealed_at', q.revealed_at) order by q.revealed_at)
                                  filter (where q.revealed_at is not null) as revealed
                           from q left join public.leads l on l.id = q.supplier_id where q.inquiry_id = i.id) qq on true
      -- the open chase, read by equality on agent_actions_kind_type_from_idx exactly as on 3 Nov
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
