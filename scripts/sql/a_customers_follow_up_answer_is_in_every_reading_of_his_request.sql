-- A CUSTOMER'S FOLLOW-UP ANSWER IS IN EVERY READING OF HIS REQUEST.
--
-- Assigned: customer_support. Agent: W3_PEOPLE, 16 Nov 2026. Founder ledgers 1711-1713 ("in a real company everyone knows what the
-- other is doing"); the customer hole hunt of 16 Nov (scratchpad holes/CUSTOMER.md #10).
--
-- MEASURED BEFORE WRITING (16 Nov 2026): on day 14 he answers the follow-up "not yet, site visit Tuesday"
-- (fn_customer_followup_answer writes customer_followup.hired/comment/stars). On Wednesday he asks on WhatsApp "any news?" and
-- the agent asks him what happened: the production fn_customer_inquiry_facts (md5 3ee29bfe3829b179bae4f86035c48aeb, read
-- 16 Nov 2026 through a light SELECT) has 0 mentions of customer_followup, and it is the ONE reading WhatsApp (fn_wa_context ->
-- identity.requests), the widget and site chat (site_assistant/turn_facts.ts), the portal chat (sales_engineer/lib/own_quotes.ts),
-- the e-mail reply (email_triage/account_facts.ts) and the intake (inquiry_intake/customer_record.ts) hand the model.
--
-- THE CHANGE: the production body, unchanged, plus one key per request, `his_follow_up_answer`: his LATEST answered follow-up on a
-- reveal of that request (hired yes / no / not decided yet, whether the supplier contacted him, his stars, his own words cut at
-- 300 characters, the day he answered). It is per-request DATA, not prompt text: no rule and no brief line grows. An ask he has
-- not answered is not shown as an answer. Scoped to his own transactions (t.customer_id = p_customer).
--
-- prevented by: a_customers_follow_up_answer_is_in_every_reading_of_his_request_probe.sql (LOCAL Postgres 16; fails on the
-- production body with "1:missing") and _shared/own_request_facts.test.ts (the rule every customer channel gives names it).

set local lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.fn_customer_inquiry_facts(p_customer uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with cfg as (
    select coalesce((select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric
                       from public.app_secrets where key = 'sla_quote_hours'), 24) as sla_h,
           coalesce((select case when c.locale = 'ar' then 'ar' else 'en' end from public.customers c where c.id = p_customer), 'en') as lang,
           -- BEING CHECKED (wave C release, 16 Nov 2026; REVIEW_CASEFACTS item 7): the requests whose quotes his portal holds while a
           -- customer_matches_supplier flag is open on him (fn_customer_quotes_being_checked, every_flag_and_sanctions_hit_...sql,
           -- applied before this file). A held quote is never priced on any channel.
           coalesce(public.fn_customer_quotes_being_checked(p_customer) -> 'inquiry_ids', '[]'::jsonb) as chk),
  inq as (
    select i.*, row_number() over (order by i.created_at desc) as rn from public.inquiries i where i.customer_id = p_customer
     order by i.created_at desc limit greatest(coalesce(p_limit, 10), 1)),
  -- a LIVE quote, as fn_rfq_short_of_quotes_tick and the portal count it; a revealed quote is live
  q as (
    select q.id, q.inquiry_id, q.supplier_id, q.quote_amount, q.price_ex_vat, q.vat_treatment, q.vat_amount, q.amount_as_stated,
           q.gross_amount, q.discount_amount, q.expires_at, q.created_at, q.lead_time, q.warranty, q.validity, q.review_notes,
           q.option_no, q.priced_revision,
           -- REVIEW 16 Nov: the price base exactly as _shared/stated_price.ts feeBaseOf (the portal's figure): none while the
           -- VAT basis is unsettled (not stated, or VAT-inclusive with no ex-VAT figure), else quote_amount, else price_ex_vat
           case when coalesce(q.price_ex_vat, 0) <= 0 and q.vat_treatment in ('not_stated', 'inclusive') then null
                else coalesce(nullif(greatest(q.quote_amount, 0), 0), nullif(greatest(q.price_ex_vat, 0), 0)) end as fee_base,
           (select min(t.revealed_at) from public.transactions t where t.quote_id = q.id and t.revealed_at is not null) as revealed_at,
           -- founder instruction 516: a sanctioned party is never shown to a customer (customer_api refuses it too)
           exists (select 1 from public.sanctions_ban sb where sb.lead_id = q.supplier_id) as sanctioned
      from public.quotes q join inq on inq.id = q.inquiry_id
     where coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled') and q.stale_at is null
       -- 16 Nov: a sanctioned supplier's SEALED quote is not counted, listed or averaged, as the portal leaves it out
       -- (customer_api my_inquiries); one already revealed stays, unnamed
       and (not exists (select 1 from public.sanctions_ban sb where sb.lead_id = q.supplier_id)
            or exists (select 1 from public.transactions t where t.quote_id = q.id and t.revealed_at is not null))
       -- wave C: a quote on a request being checked is left out (counted under quotes_being_checked) unless he has a transaction
       -- on that very quote, as the portal cards hold it (customer_api inquiry_lifecycle.ts, paidQuoteIds)
       and not ((select chk from cfg) ? q.inquiry_id::text
                and not exists (select 1 from public.transactions t where t.quote_id = q.id and t.customer_id = p_customer)))
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
              and not (cfg.chk ? i.id::text)   -- wave C: quotes held while he is checked are not late
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
      'chase', ch.j,
      -- W3_PEOPLE 16 Nov 2026 (CUSTOMER #10): his latest answered follow-up on a reveal of this request, as data
      'his_follow_up_answer', fu.j,
      -- wave C: how many of his quotes on this request are held while he is checked (never their prices)
      'quotes_being_checked', case when cfg.chk ? i.id::text then
          (select count(*) from public.quotes q0
            where q0.inquiry_id = i.id and coalesce(q0.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
              and q0.stale_at is null
              and not exists (select 1 from public.sanctions_ban sb where sb.lead_id = q0.supplier_id)
              and not exists (select 1 from public.transactions t where t.quote_id = q0.id and t.customer_id = p_customer)) else 0 end)
      -- WHAT HE ASKED, AND WHAT HIS PORTAL SHOWS HIM: every open or revealed request (a revealed one is still being worked:
      -- the supplier's contact, the other quotes, the refund window) and the three newest
      || case when not (coalesce(i.status, '') in ('open', 'sent', 'quoted', 'split', 'revealed') or i.rn <= 3) then '{}'::jsonb else jsonb_build_object(
      'asked', jsonb_strip_nulls(jsonb_build_object(
          'summary', left(i.summary, 600),
          -- his own words, exactly as stored; never parsed here
          'budget_as_he_stated_it', nullif(btrim(coalesce(i.budget, '')), ''),
          'required_by', i.required_by,
          -- 16 Nov 2026: the request's revision (1 at posting; each later change he made is one more, inquiry_revision)
          'revision', coalesce(i.revision, 1),
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
      -- EVERY REVISION OF THE REQUEST (16 Nov 2026, inquiry_revision): what changed, old -> new, and who recorded it
      'revisions', coalesce((select jsonb_agg(jsonb_build_object('revision', rv.revision, 'at', rv.created_at, 'changed', rv.changes,
                                                'recorded', case rv.source when 'portal_edit' then 'he edited the request himself'
                                                                 else 'the sales engineer recorded it from his message' end) order by rv.revision)
                               from (select * from public.inquiry_revision r1 where r1.inquiry_id = i.id order by r1.revision desc limit 5) rv), '[]'::jsonb),
      -- EACH LIVE QUOTE AS HIS PORTAL SHOWS IT (customer_api my_inquiries; the anonymity decision in this file's header)
      'quotes', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                    'letter', lt.letter, 'label', case when cfg.lang = 'ar' then lt.label_ar else lt.label_en end,
                    -- said only when it is not the portal's own derivation (stored, or not yet shown in the portal)
                    'letter_source', nullif(lt.letter_source, 'stored'),
                    'price_ex_vat_aed', z.fee_base,
                    'price_as_shown', case when z.fee_base is null then 'price being confirmed with the supplier (its VAT basis is not settled)' else public.fn_aed_words(z.fee_base) || ' before VAT'
                       || case when z.vat_treatment in ('exclusive', 'confirmed_on_portal', 'inclusive') and z.vat_amount is not null
                               then ', ' || public.fn_aed_words(z.vat_amount) || ' VAT, ' || public.fn_aed_words(z.fee_base + z.vat_amount) || ' with VAT'
                               when z.vat_treatment in ('not_registered', 'zero_rated', 'exempt') then ', no VAT: ' || public.fn_aed_words(z.fee_base) || ' in total'
                               else ', VAT not stated' end
                       || case when z.discount_amount > 0 and z.gross_amount is not null
                               then ' (after a discount of ' || public.fn_aed_words(z.discount_amount) || ' from ' || public.fn_aed_words(z.gross_amount) || ')' else '' end end,
                    'vat_as_stated', case z.vat_treatment when 'exclusive' then 'VAT added on top of the price' when 'confirmed_on_portal' then 'VAT added on top of the price'
                                                          when 'inclusive' then 'the supplier''s total includes VAT'
                                                          when 'not_registered' then 'supplier not VAT registered: no VAT'
                                                          when 'zero_rated' then 'zero-rated: no VAT'
                                                          when 'exempt' then 'exempt: no VAT'
                                                          else 'VAT not stated' end,
                    'vat_aed', case when z.vat_treatment in ('exclusive', 'confirmed_on_portal', 'inclusive') then z.vat_amount end,
                    'total_with_vat_aed', case when z.vat_treatment in ('exclusive', 'confirmed_on_portal', 'inclusive') and z.vat_amount is not null
                                                 then z.fee_base + z.vat_amount
                                               when z.vat_treatment in ('not_registered', 'zero_rated', 'exempt')
                                                 then z.fee_base end,
                    'total_as_stated_aed', z.amount_as_stated,
                    'before_discount_aed', case when z.discount_amount > 0 then z.gross_amount end,
                    'discount_aed', case when z.discount_amount > 0 then z.discount_amount end,
                    'valid_until', z.expires_at, 'expired', case when z.expires_at is not null then z.expires_at < now() end,
                    'validity_as_stated', public.fn_quote_words_for_customer(z.validity, z.id, z.revealed_at is not null),
                    'lead_time_as_stated', public.fn_quote_words_for_customer(z.lead_time, z.id, z.revealed_at is not null),
                    'warranty_as_stated', public.fn_quote_words_for_customer(z.warranty, z.id, z.revealed_at is not null),
                    -- the sales engineer's checks of this quote against his request, stored when it went live (ledger 1588);
                    -- brand-free by construction (_shared/quote_review_notes.ts)
                    'notes_against_your_request', (select jsonb_agg(coalesce(case when cfg.lang = 'ar' then rn.n ->> 'ar' end, rn.n ->> 'en'))
                                                     from jsonb_array_elements(case when jsonb_typeof(z.review_notes) = 'array' then z.review_notes else '[]'::jsonb end) rn(n)
                                                    where coalesce(rn.n ->> 'en', rn.n ->> 'ar') is not null),
                    -- the request thread with THIS supplier (rfq_clarification, kind question: the supplier asks, he answers), so
                    -- "did B ask about the tiles, what did I tell them?" is answered by the quote's own letter. The question was
                    -- stripped of contacts and brands when it was asked (messages_api clarify_ask, stripSupplierQuestion) and is
                    -- what his portal thread shows; the code generaliser runs over it again before a model reads it.
                    -- THE THREAD WITH THIS SUPPLIER BEFORE THE REVEAL (16 Nov 2026, fn_customer_quote_thread): the supplier's questions
                    -- and his answers, and his own questions about this quote with the sales engineer's or the supplier's answer and
                    -- the date it is due by. Who asked and who answered are said, so a model never reads his question as the supplier's.
                    'questions_and_answers', public.fn_customer_quote_thread(i.id, z.supplier_id),
                    -- the request revision this price answers (inquiries.revision, quotes.priced_revision; null reads as 1)
                    'priced_revision', coalesce(z.priced_revision, 1),
                    'priced_before_the_request_last_changed', coalesce(z.priced_revision, 1) < coalesce(i.revision, 1),
                    'revealed', z.revealed_at is not null,
                    'supplier', case when z.revealed_at is null then null
                                     when z.sanctioned then 'a supplier no longer on QuotesDone'
                                     else coalesce((select l.company_name from public.leads l where l.id = z.supplier_id), 'the supplier') end))
                    order by z.fee_base, z.created_at)
                  from q z left join public.fn_customer_quote_letters(i.id) lt on lt.quote_id = z.id
                 where z.inquiry_id = i.id and (lt.letter is not null or z.revealed_at is not null)), '[]'::jsonb),
      -- REVIEW 16 Nov: a live quote his portal has not shown (held for missing details by code, or not yet opened) is counted, not priced
      'quotes_not_yet_on_his_portal', (select count(*) from q z left join public.fn_customer_quote_letters(i.id) lt on lt.quote_id = z.id
                                         where z.inquiry_id = i.id and lt.letter is null and z.revealed_at is null),
      -- REVIEW 16 Nov: no 'comparison' here. qd_compare_cache holds quote_compare's RAW model output (index.ts:582 writes `parsed`);
      -- the brand/name gate (generaliseDeep, hideBrandPhrases) and the stored letters are applied only when it is served, and a
      -- cache row is not tied to the current quotes. The portal remains the comparison's one door.
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
                          order by a.id desc limit 1) ch on true
      -- his LATEST answered follow-up on this request (customer_followup_transaction_id_stage_key serves the join); none: no key
      left join lateral (select jsonb_strip_nulls(jsonb_build_object(
                                  'answered_on', f.answered_at, 'asked_on', f.asked_at,
                                  'hired', case f.hired when 'yes' then 'yes, he hired the supplier he revealed'
                                                        when 'no' then 'no, he did not hire the supplier he revealed'
                                                        when 'not_yet' then 'not decided yet' end,
                                  'supplier_contacted_him', f.contacted, 'stars', f.stars,
                                  'his_words', nullif(left(btrim(coalesce(f.comment, '')), 300), ''))) as j
                           from public.customer_followup f join public.transactions t on t.id = f.transaction_id
                          where t.inquiry_id = i.id and t.customer_id = p_customer and f.answered_at is not null
                          order by f.answered_at desc, f.id desc limit 1) fu on true) x
$function$
;

revoke execute on function public.fn_customer_inquiry_facts(uuid, integer) from public, anon, authenticated;
grant execute on function public.fn_customer_inquiry_facts(uuid, integer) to service_role;
