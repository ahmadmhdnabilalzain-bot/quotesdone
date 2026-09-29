-- A QUOTE IS CHECKED FOR ITS SPECS, ITS PRICE AND ITS TERMS BEFORE THE CUSTOMER SEES IT.
-- Seat: sales_engineer (the quote hold desk). Founder ledger 1018, round 3, item 2 (29 Sep 2026):
--   "Quote quality check before the customer sees a quote. Flag missing required specs (the trade spec checklists), prices
--    outside the UAE price ranges (fn_price_benchmark_*; skip where there is no benchmark), and unclear terms (no validity,
--    no delivery time, no VAT treatment). A flagged quote is sent back to the supplier, in English, with the exact fixes,
--    and held from the customer until it's corrected or has waited 24 hours. Show the reason in the comparison. Plain code."
--
-- MEASURED BEFORE THIS FILE (production htdblwldjkcgjvmqkbeh, 29 Sep 2026, read-only):
--   * 3 quotes (2 'submitted', 1 'revealed'), all on the founder-demo requests; 7 quote_items; vat_treatment is set on all 3.
--   * A quote reaches the customer the moment its status leaves 'draft': customer_api (my_inquiries, the quote detail),
--     quote_compare and the reveal guard all exclude 'draft' and nothing else. supplier_api's acceptLive sets 'submitted'
--     and e-mails the customer "You have a new quote".
--   * What already holds a quote (status 'draft', quote_spec_hold): the exact-specs gate at submission (line readers, and the
--     pack checklist for a trade with no reader) and the review's rules 1-7. Nothing compares a quote's PRICE with the UAE
--     ranges before the customer sees it (fn_price_benchmark_flags_for_inquiry is read by quote_compare only), nothing holds
--     a quote for a missing validity or VAT basis once it passed those, and nothing lets a held quote through after a time.
--   * trade_spec_checklist: 63 checklists over 20 trades. fn_price_benchmarks: a range exists only for an item priced in
--     5+ quotes by 3+ suppliers on other requests (demo excluded) - today none, so no price is flagged until real data exists.
--
-- WHAT THIS ADDS (plain code; no model is asked anything):
--   1. decision_policy 'quote_quality_hold_hours' = 24 (the CEO can change it; inserted once).
--   2. fn_quote_quality_flags(quote) - the three checks, as data (codes and numbers, no sentences):
--        missing_spec   the trade's pack checklist (trade_spec_checklist, through fn_taxonomy_trades_for like
--                       fn_trade_spec_checklist) against the spec codes the quote's lines carry (quote_items.spec). A quote
--                       whose lines carry a line reader's attributes (any spec key not in the spec_* family) is read by that
--                       reader at submission and is not asked the pack's list again. One checklist: that one. Several: the
--                       one the lines already answer most of; none answered: every list, each spec once (the hold desk's
--                       rule, reasoned_specs.ts unionOf - asking more is safe, guessing which list applies is not). A value
--                       such as "not applicable" is a statement and counts.
--        price_above / price_below   each priced line against fn_price_benchmarks (other requests only; ZZ DEMO quotes are
--                       judged against demo ranges and real quotes against real ones) through fn_price_benchmark_judge's own
--                       bounds (outside p25 - 1.5 IQR .. p75 + 1.5 IQR). A line with no benchmark is skipped.
--        no_validity, no_delivery_time, no_vat_treatment   quotes.validity blank; quotes.lead_time blank and no delivery on
--                       the portal (terms_spec.delivery); quotes.vat_treatment null or 'not_stated'.
--   3. public.quote_quality_hold: one row per quote: the flags, the English fixes sent, when it was held, when it is due
--      out (held + 24 h, never reset by a resubmission), when and why it was released ('corrected' | 'waited_24h'), whether a
--      later edit corrected it, and what the customer was told.
--   4. The gate, trigger z40_quote_quality_gate (BEFORE INSERT OR UPDATE OF status on quotes, after every other BEFORE
--      trigger): a quote about to leave 'draft' (or a withdrawn / rejected / expired state) is checked. Flagged and never
--      held before -> it stays 'draft' (hidden from every customer surface, exactly as a held quote already is) and the hold
--      opens. Clean -> it goes out, and an open hold is closed 'corrected'. A quote that already waited its 24 h is not held
--      again; its flags are kept current. A quote already in front of the customer is never pulled back.
--   5. fn_sales_engineer_quote_quality_tick (seat_duty 'sales_engineer.quote_quality_hold', every 15 minutes):
--        a. sends the supplier the exact fixes, in English (to_role supplier; a04/z05 refuse anything else), once per
--           distinct set of fixes, through customer_support's delivery door and the same-kind gate (fn_seat_clock_refusal);
--        b. re-checks every open hold: corrected -> released 'corrected'; past its 24 h -> released 'waited_24h' with its
--           flags. Released = 'submitted', the request marked 'quoted' as acceptLive does, and the customer told once, in the
--           request's language, that a quotation arrived - and, after a wait, that the check's points are shown beside it
--           in the comparison. A quote with a live exact-specs hold (quote_spec_hold) is left to that desk.
--   6. quote_quality_hold joins the daily table export (fn_table_export_list, from marketing_plans_recruitment_for_every_
--      trade_below_ten_suppliers.sql, MANIFEST 1834, with only that row added). No *_path column: no backup registry row.
--
-- WITH THIS FILE, IN THE SAME PR: supplier_api (acceptLive reads the status back: a quote the gate held is answered as
-- held, with the fixes, and the customer is NOT told of a quote they cannot see); quote_compare (the open holds are
-- counted as on hold, and a quote released after its wait carries its flags as quality_check); CustomerPortal's
-- comparison shows both, in English and Arabic.
--
-- Prevented by: scripts/checks/a_quote_is_checked_before_the_customer_sees_it.test.mjs (static + this file and its
-- _probe.sql in one aborted transaction on ZZ DEMO data).

-- ── 1. the setting ─────────────────────────────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('quote_quality_hold_hours', '24'::jsonb,
   'z40_quote_quality_gate / fn_sales_engineer_quote_quality_tick: hours a quote flagged by the quality check (missing checklist specs, a price outside the UAE range, no validity / delivery time / VAT basis) is held from the customer while the supplier corrects it. After this it is shown with its flags. Founder ledger 1018, 29 Sep 2026.')
on conflict (key) do nothing;

-- ── 2. the checks ──────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_quote_quality_flags(p_quote public.quotes)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_cat text; v_demo boolean; v_reader boolean; v_spec jsonb; v_price jsonb; v_terms jsonb := '[]'::jsonb;
begin
  select i.category into v_cat from public.inquiries i where i.id = p_quote.inquiry_id;
  v_demo := public.fn_inquiry_is_demo(p_quote.inquiry_id);

  -- (1) the pack checklist, unless a line reader already read these lines
  select exists (select 1 from public.quote_items qi, jsonb_object_keys(coalesce(qi.spec, '{}'::jsonb)) k
                  where qi.quote_id = p_quote.id::text and k !~ '^spec_') into v_reader;
  if not v_reader then
    with lists as (
      select c.topic_id, c.topic, c.specs from public.trade_spec_checklist c
       where c.trade_code = v_cat or c.trade_code = any(coalesce(public.fn_taxonomy_trades_for(array[v_cat]), '{}'::text[]))
    ), specs as (
      select l.topic_id, l.topic, s.x->>'code' as code, s.x->>'label_en' as label, s.ord
        from lists l, jsonb_array_elements(l.specs) with ordinality s(x, ord)
    ), judged as (
      select sp.*, exists (select 1 from public.quote_items qi
                            where qi.quote_id = p_quote.id::text and nullif(btrim(qi.spec->>sp.code), '') is not null) as stated
        from specs sp
    ), per_list as (
      select j.topic_id, j.topic, count(*) filter (where j.stated) as n_stated, count(*) filter (where not j.stated) as n_missing,
             jsonb_agg(jsonb_build_object('code', j.code, 'label', j.label) order by j.ord) filter (where not j.stated) as missing
        from judged j group by j.topic_id, j.topic
    ), chosen as (
      select * from per_list order by (n_missing = 0) desc, n_stated desc, n_missing, topic_id limit 1
    )
    select case
             when not exists (select 1 from per_list) then null                        -- no checklist for this trade
             when (select n_missing from chosen) = 0 then null                         -- one list fully stated
             when (select n_stated from chosen) > 0 or (select count(*) from per_list) = 1
               then jsonb_build_object('code', 'missing_spec', 'topic', (select topic from chosen), 'specs', (select missing from chosen))
             else jsonb_build_object('code', 'missing_spec', 'topic', null, 'specs',
                    (select jsonb_agg(jsonb_build_object('code', u.code, 'label', u.label) order by u.first_topic, u.ord)
                       from (select distinct on (j.code) j.code, j.label, j.topic_id as first_topic, j.ord
                               from judged j order by j.code, j.topic_id, j.ord) u))
           end
      into v_spec;
  end if;

  -- (2) each priced line against the UAE range for the same item; no benchmark, no flag
  with b as (select * from public.fn_price_benchmarks(v_demo, p_quote.inquiry_id)),
  lines as (
    select qi.line_no, qi.description,
           public.fn_price_benchmark_key(qi.description, qi.specification) as item_key,
           public.fn_price_benchmark_unit(qi.unit) as unit,
           round(coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0)), 2) as price
      from public.quote_items qi where qi.quote_id = p_quote.id::text
  ), judged as (
    select l.*, b.median, b.p25, b.p75, b.quote_count, b.supplier_count,
           public.fn_price_benchmark_judge(l.price, b.median, b.p25, b.p75, b.quote_count, b.supplier_count, l.unit) as j
      from lines l join b on b.trade = lower(v_cat) and b.item_key = l.item_key and b.unit = l.unit
     where l.price > 0
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', case when j->>'status' = 'well_above' then 'price_above' else 'price_below' end,
           'line_no', line_no, 'description', description, 'unit', unit, 'price', price,
           'pct_vs_median', (j->>'pct_vs_median')::numeric, 'median', median, 'p25', p25, 'p75', p75,
           'quotes', quote_count, 'suppliers', supplier_count) order by line_no), '[]'::jsonb)
    into v_price
    from judged where j->>'status' in ('well_above', 'well_below');

  -- (3) the terms a customer cannot compare without
  if nullif(btrim(coalesce(p_quote.validity, '')), '') is null then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_validity')); end if;
  if nullif(btrim(coalesce(p_quote.lead_time, '')), '') is null
     and nullif(btrim(coalesce(p_quote.terms_spec #>> '{delivery,value}', '')), '') is null then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_delivery_time')); end if;
  if coalesce(p_quote.vat_treatment, 'not_stated') = 'not_stated' then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_vat_treatment')); end if;

  return (case when v_spec is null then '[]'::jsonb else jsonb_build_array(v_spec) end) || coalesce(v_price, '[]'::jsonb) || v_terms;
end
$fn$;
revoke execute on function public.fn_quote_quality_flags(public.quotes) from public, anon, authenticated;

-- ── 3. the exact fixes, in English (a supplier is always written in English) ────────────────────────────────────
create or replace function public.fn_quote_quality_fixes_en(p_flags jsonb)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select string_agg(n || '. ' || line, E'\n' order by n)
    from (select row_number() over (order by o) as n,
                 case f->>'code'
                   when 'missing_spec' then
                     'State these specifications on the lines you quote'
                     || coalesce(' (' || nullif(regexp_replace(f->>'topic', '^[Ss]pec checklist:\s*', ''), '') || ')', '') || ': '
                     || (select string_agg(s->>'label', '; ' order by k) from jsonb_array_elements(f->'specs') with ordinality e(s, k))
                     || '. If one does not apply to what you quote, write "not applicable" and why.'
                   when 'price_above' then
                     'Line ' || (f->>'line_no') || ' "' || left(coalesce(f->>'description', ''), 80) || '": AED '
                     || to_char((f->>'price')::numeric, 'FM999,999,990.00') || ' per ' || (f->>'unit') || ' is '
                     || (f->>'pct_vs_median') || '% above the usual UAE price for this item (AED '
                     || to_char((f->>'p25')::numeric, 'FM999,999,990.00') || ' to ' || to_char((f->>'p75')::numeric, 'FM999,999,990.00')
                     || ' per ' || (f->>'unit') || ', from ' || (f->>'quotes') || ' quotations by ' || (f->>'suppliers')
                     || ' suppliers). Correct the price, or state on the line what justifies it (brand, grade, scope or delivery).'
                   when 'price_below' then
                     'Line ' || (f->>'line_no') || ' "' || left(coalesce(f->>'description', ''), 80) || '": AED '
                     || to_char((f->>'price')::numeric, 'FM999,999,990.00') || ' per ' || (f->>'unit') || ' is '
                     || abs((f->>'pct_vs_median')::numeric) || '% below the usual UAE price for this item (AED '
                     || to_char((f->>'p25')::numeric, 'FM999,999,990.00') || ' to ' || to_char((f->>'p75')::numeric, 'FM999,999,990.00')
                     || ' per ' || (f->>'unit') || ', from ' || (f->>'quotes') || ' quotations by ' || (f->>'suppliers')
                     || ' suppliers). Check the quantity, the specification and what is excluded, then correct the line or state what it covers.'
                   when 'no_validity' then 'State how long the quotation is valid (for example, 30 days).'
                   when 'no_delivery_time' then 'State the delivery or lead time (a date, or a number of days from the order).'
                   when 'no_vat_treatment' then 'State whether your price includes or excludes VAT, or that you are not registered for VAT.'
                 end as line
            from jsonb_array_elements(coalesce(p_flags, '[]'::jsonb)) with ordinality a(f, o)) x
   where line is not null
$fn$;
revoke execute on function public.fn_quote_quality_fixes_en(jsonb) from public, anon, authenticated;

-- ── 4. the record ──────────────────────────────────────────────────────────────────────────────────────────────
-- DEFERRABLE: the gate opens the row from inside the quote's own BEFORE INSERT, before the quote row exists.
create table if not exists public.quote_quality_hold (
  quote_id       uuid primary key references public.quotes(id) on delete cascade deferrable initially deferred,
  inquiry_id     uuid,
  supplier_id    bigint,
  fixture        boolean not null default false,
  flags          jsonb not null default '[]'::jsonb check (jsonb_typeof(flags) = 'array'),
  fixes_en       text,
  fixes_sent_md5 text,
  fixes_sent_at  timestamptz,
  fixes_delivery jsonb,
  held_at        timestamptz not null default now(),
  release_due    timestamptz not null,
  released_at    timestamptz,
  release_reason text check (release_reason is null or release_reason in ('corrected', 'waited_24h')),
  corrected_at   timestamptz,
  customer_notice jsonb,
  updated_at     timestamptz not null default now(),
  check ((released_at is null) = (release_reason is null))
);
create index if not exists quote_quality_hold_by_inquiry on public.quote_quality_hold (inquiry_id);
create index if not exists quote_quality_hold_open on public.quote_quality_hold (release_due) where released_at is null;
alter table public.quote_quality_hold enable row level security;
drop policy if exists quote_quality_hold_service_role_only on public.quote_quality_hold;
create policy quote_quality_hold_service_role_only on public.quote_quality_hold
  as permissive for all to public using (false) with check (false);
revoke all on public.quote_quality_hold from anon, authenticated;
comment on table public.quote_quality_hold is
  'A quote the quality check flagged (missing checklist specs, a price outside the UAE range, no validity / delivery time / VAT basis): held from the customer until corrected or for 24 h, the supplier sent the exact fixes in English; after the wait it is shown with its flags. Owner: sales_engineer. Founder ledger 1018, 29 Sep 2026.';

-- ── 5. the gate ────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_quote_quality_gate()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_flags jsonb; h public.quote_quality_hold; v_live boolean;
  v_hours numeric := public.fn_seat_clock_policy('quote_quality_hold_hours', 24);
begin
  -- a quote that is not (or not yet) in front of the customer is not checked here
  if coalesce(new.status, 'submitted') in ('draft', 'withdrawn', 'rejected', 'expired', 'cancelled', 'held') then return new; end if;
  -- going out now: a new row, or one leaving a state no customer surface shows
  v_live := tg_op = 'INSERT' or coalesce(old.status, 'draft') in ('draft', 'withdrawn', 'rejected', 'expired', 'cancelled', 'held');
  v_flags := public.fn_quote_quality_flags(new);
  select * into h from public.quote_quality_hold where quote_id = new.id;

  if not v_live or h.released_at is not null then
    -- already out, or already waited its hours once: never pulled back; the flags beside it are kept current
    if found and h.flags is distinct from v_flags then
      update public.quote_quality_hold
         set flags = v_flags, fixes_en = public.fn_quote_quality_fixes_en(v_flags),
             corrected_at = case when jsonb_array_length(v_flags) = 0 then coalesce(corrected_at, now()) else null end,
             updated_at = now()
       where quote_id = new.id;
    end if;
    return new;
  end if;

  if jsonb_array_length(v_flags) = 0 then
    if found then
      update public.quote_quality_hold
         set flags = v_flags, released_at = now(), release_reason = 'corrected', corrected_at = now(), updated_at = now()
       where quote_id = new.id;
    end if;
    return new;
  end if;

  -- flagged: it stays a draft, which every customer surface already hides, and the hold opens (its clock is never reset)
  new.status := 'draft';
  insert into public.quote_quality_hold (quote_id, inquiry_id, supplier_id, fixture, flags, fixes_en, held_at, release_due)
  values (new.id, new.inquiry_id, new.supplier_id, public.fn_inquiry_is_demo(new.inquiry_id), v_flags,
          public.fn_quote_quality_fixes_en(v_flags), now(), now() + make_interval(secs => (v_hours * 3600)::double precision))
  on conflict (quote_id) do update
    set flags = excluded.flags, fixes_en = excluded.fixes_en, updated_at = now();
  return new;
end
$fn$;
revoke execute on function public.fn_quote_quality_gate() from public, anon, authenticated;
drop trigger if exists z40_quote_quality_gate on public.quotes;
create trigger z40_quote_quality_gate before insert or update of status on public.quotes
  for each row execute function public.fn_quote_quality_gate();

-- ── 6. the words ───────────────────────────────────────────────────────────────────────────────────────────────
-- The supplier: English only, the exact fixes, and when the quotation goes out as it stands. The customer: in the
-- request's language, in the register of fn_seat_clock_compose, told only what is true.
create or replace function public.fn_quote_quality_compose(p_kind text, p_lang text, p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ar boolean := p_kind = 'customer' and coalesce(p_lang, '') like 'ar%';
  v_lang text := case when p_kind = 'customer' and coalesce(p_lang, '') like 'ar%' then 'ar' else 'en' end;
  v_name text := nullif(btrim(coalesce(p->>'name', '')), '');
  v_site text; v_link text; v_trade text; v_trade_ar text; v_em text; v_em_ar text; v_where text; v_where_ar text;
  v_ref text := coalesce('QD-' || nullif(p->>'job_no', ''), 'your request');
  v_hours int := coalesce((p->>'hours')::numeric, 24)::int;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select t.label, coalesce(t.label_ar, t.label) into v_trade, v_trade_ar
    from public.taxonomy_trade t
   where t.code = (public.fn_taxonomy_trades_for(array[coalesce(p->>'category', '')]))[1];
  v_trade := coalesce(v_trade, nullif(p->>'category', ''), 'your trade');
  v_trade_ar := coalesce(v_trade_ar, nullif(p->>'category', ''), 'تخصصكم');
  v_em := nullif(btrim(coalesce(p->>'emirate', '')), '');
  v_em_ar := case lower(coalesce(v_em, '')) when 'dubai' then 'دبي' when 'abu dhabi' then 'أبوظبي' when 'sharjah' then 'الشارقة'
               when 'ajman' then 'عجمان' when 'umm al quwain' then 'أم القيوين' when 'ras al khaimah' then 'رأس الخيمة'
               when 'fujairah' then 'الفجيرة' else v_em end;
  v_where := v_trade || coalesce(' in ' || v_em, '');
  v_where_ar := v_trade_ar || coalesce(' في ' || v_em_ar, '');

  if p_kind = 'supplier' then
    -- an Arabic-script company name is not written into an English letter (#1070's guard)
    if v_name ~ '[؀-ۿ]' then v_name := null; end if;
    v_subj := 'Action needed: your quotation for ' || v_ref || ' is on hold — ' || v_where;
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
      || 'Your quotation for request ' || v_ref || ' (' || v_where || ') has not been shown to the customer yet. '
      || 'Our quality check found the points below. Please correct them in your supplier portal:'
      || E'\n\n' || coalesce(p->>'fixes', '') || E'\n\n'
      || 'If the quotation is not corrected by ' || coalesce(p->>'due', 'the end of the hold') || ' (Dubai time), '
      || 'it will be shown to the customer as it stands, with these points noted beside it.'
      || E'\n\n' || v_link;
  elsif v_ar then
    v_subj := 'عرض سعر جديد لطلبكم — ' || v_where_ar;
    v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
      || 'نفيدكم بأن أحد الموردين قدّم عرض سعر لطلبكم في مجال ' || v_where_ar || '. '
      || case when coalesce((p->>'waited')::boolean, false)
           then 'وقد وجد فحص الجودة لدينا ملاحظات لم يصحّحها المورّد خلال ' || v_hours || ' ساعة، وهي معروضة بجانب هذا العرض في المقارنة. '
           else '' end
      || 'ويمكنكم الاطلاع عليه ومقارنته بالعروض الأخرى عبر بوابتكم:'
      || E'\n\n' || v_link
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_subj := 'A new quotation for your request — ' || v_where;
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
      || 'A supplier has submitted a quotation for your request for ' || v_where || '. '
      || case when coalesce((p->>'waited')::boolean, false)
           then 'Our quality check found points the supplier did not correct within ' || v_hours || ' hours; they are shown beside this quotation in your comparison. '
           else '' end
      || 'You can view it and compare it with the others in your portal:'
      || E'\n\n' || v_link;
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$fn$;
revoke execute on function public.fn_quote_quality_compose(text, text, jsonb) from public, anon, authenticated;

-- ── 7. the duty: send the fixes, release on correction or after the wait ─────────────────────────────────────────
create or replace function public.fn_sales_engineer_quote_quality_tick(p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_hours numeric := public.fn_seat_clock_policy('quote_quality_hold_hours', 24);
  h record; q public.quotes; v_flags jsonb; m jsonb; v jsonb; v_to text; v_why text; v_key text; v_md5 text; v_notice jsonb;
  v_sent int := 0; v_corrected int := 0; v_waited int := 0; v_left_to_spec int := 0; v_told int := 0;
  v_not_sent jsonb := '[]'::jsonb;
begin
  for h in
    select x.*, i.category, i.emirate, i.lang as inq_lang, i.status as inq_status, public.fn_job_no(x.inquiry_id) as job_no,
           c.email as cemail, c.full_name as cname, l.company_name, lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))) as semail
      from public.quote_quality_hold x
      join public.inquiries i on i.id = x.inquiry_id
      left join public.customers c on c.id = i.customer_id
      left join public.leads l on l.id = x.supplier_id
     where x.released_at is null and (p_include_fixtures or not x.fixture)
     order by x.held_at
  loop
    select * into q from public.quotes where id = h.quote_id;
    v_flags := public.fn_quote_quality_flags(q);

    -- (a) the fixes, once per distinct set, while the quote is still flagged
    if jsonb_array_length(v_flags) > 0 then
      if v_flags is distinct from h.flags then
        update public.quote_quality_hold set flags = v_flags, fixes_en = public.fn_quote_quality_fixes_en(v_flags), updated_at = now()
         where quote_id = h.quote_id;
      end if;
      v_md5 := md5(public.fn_quote_quality_fixes_en(v_flags));
      if v_md5 is distinct from h.fixes_sent_md5 and now() < h.release_due then
        m := public.fn_quote_quality_compose('supplier', 'en', jsonb_build_object('name', h.company_name, 'category', h.category,
               'emirate', h.emirate, 'job_no', h.job_no, 'fixes', public.fn_quote_quality_fixes_en(v_flags),
               'due', to_char(h.release_due at time zone 'Asia/Dubai', 'DD Mon YYYY, HH24:MI')));
        v_key := 'quote_quality_fixes:' || h.quote_id || ':' || left(v_md5, 12);
        v_why := public.fn_seat_clock_refusal(h.fixture, h.semail, 'quote_quality_fixes');
        if v_why is null and public.fn_seat_clock_asked(v_key) then v_why := 'already sent'; end if;
        if v_why is null then
          v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
            'type', 'quote_quality_fixes', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', h.semail,
            'to_role', 'supplier', 'lead_id', h.supplier_id, 'inquiry_id', h.inquiry_id, 'quote_id', h.quote_id,
            'lang', 'en', 'subject', m->>'subject', 'body', m->>'body', 'dedupe_key', v_key)));
          update public.quote_quality_hold set fixes_sent_md5 = v_md5, fixes_sent_at = now(), fixes_delivery = v->0, updated_at = now()
           where quote_id = h.quote_id;
          v_sent := v_sent + 1;
        else
          update public.quote_quality_hold set fixes_delivery = jsonb_build_object('sent', false, 'reason', v_why), updated_at = now()
           where quote_id = h.quote_id;
          v_not_sent := v_not_sent || jsonb_build_array(jsonb_build_object('quote_id', h.quote_id, 'reason', v_why));
        end if;
      end if;
    end if;

    -- (b) corrected, or waited its hours: released (the hold is marked first, so the gate lets it through)
    if jsonb_array_length(v_flags) = 0 or now() >= h.release_due then
      update public.quote_quality_hold
         set flags = v_flags, released_at = now(),
             release_reason = case when jsonb_array_length(v_flags) = 0 then 'corrected' else 'waited_24h' end,
             corrected_at = case when jsonb_array_length(v_flags) = 0 then now() end, updated_at = now()
       where quote_id = h.quote_id;
      if jsonb_array_length(v_flags) = 0 then v_corrected := v_corrected + 1; else v_waited := v_waited + 1; end if;
      -- a quote the exact-specs desk holds (quote_spec_hold) is that desk's to release
      if coalesce(q.status, '') = 'draft' and not exists (select 1 from public.quote_spec_hold s
                                                          where s.quote_id = h.quote_id and s.state in ('open', 'awaiting_approval')) then
        update public.quotes set status = 'submitted' where id = h.quote_id and status = 'draft';
        update public.inquiries set status = 'quoted' where id = h.inquiry_id and status in ('sent', 'quoted');
        m := public.fn_quote_quality_compose('customer', h.inq_lang, jsonb_build_object('name', h.cname, 'category', h.category,
               'emirate', h.emirate, 'hours', v_hours, 'waited', jsonb_array_length(v_flags) > 0));
        v_key := 'quote_quality_release:' || h.quote_id;
        v_to := lower(btrim(coalesce(h.cemail, '')));
        v_why := public.fn_seat_clock_refusal(h.fixture, v_to, 'new_quote');
        if v_why is null and public.fn_seat_clock_asked(v_key) then v_why := 'already told'; end if;
        if v_why is null then
          v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
            'type', 'new_quote', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', v_to, 'to_role', 'customer',
            'inquiry_id', h.inquiry_id, 'quote_id', h.quote_id, 'lang', m->>'lang', 'subject', m->>'subject', 'body', m->>'body',
            'dedupe_key', v_key)));
          v_notice := jsonb_build_object('sent', coalesce(v->0->>'status', '') <> 'failed', 'lang', m->>'lang', 'delivery', v->0);
          if (v_notice->>'sent')::boolean then v_told := v_told + 1; end if;
        else
          v_notice := jsonb_build_object('sent', false, 'lang', m->>'lang', 'reason', v_why);
        end if;
        update public.quote_quality_hold set customer_notice = v_notice where quote_id = h.quote_id;
      else
        v_left_to_spec := v_left_to_spec + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'hold_hours', v_hours, 'fixes_sent', v_sent, 'fixes_not_sent', v_not_sent,
    'released_corrected', v_corrected, 'released_after_wait', v_waited, 'left_to_the_spec_desk', v_left_to_spec,
    'customers_told', v_told,
    'open', (select count(*) from public.quote_quality_hold where released_at is null and (p_include_fixtures or not fixture)));
end
$fn$;
revoke execute on function public.fn_sales_engineer_quote_quality_tick(boolean) from public, anon, authenticated;

insert into public.seat_duty (duty, what, every, enabled, routine, owner_file, owner_seat) values
  ('sales_engineer.quote_quality_hold',
   'a quote the quality check flagged is sent back to the supplier with the exact fixes in English, and released to the customer when corrected or after 24 h, with its flags shown in the comparison',
   '15 minutes', true, 'fn_sales_engineer_quote_quality_tick',
   'scripts/sql/a_quote_is_checked_for_specs_prices_and_terms_before_the_customer_sees_it.sql', 'sales_engineer')
on conflict (duty) do nothing;

-- ── 8. the daily export ────────────────────────────────────────────────────────────────────────────────────────
-- Redefined from its canonical body (marketing_plans_recruitment_for_every_trade_below_ten_suppliers.sql, the last
-- definer in MANIFEST.txt on 29 Sep 2026) with only ('quote_quality_hold','quote') added. If another definition is
-- applied first (the stalled-request PR of the same round adds inquiry_rescue), rebase this one onto it.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'), ('quote_quality_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_calendar_resend_decision','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('marketing_recruitment_source','marketing'), ('marketing_gap_recruitment_plan','marketing'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

revoke execute on function public.fn_table_export_list() from public, anon, authenticated;
