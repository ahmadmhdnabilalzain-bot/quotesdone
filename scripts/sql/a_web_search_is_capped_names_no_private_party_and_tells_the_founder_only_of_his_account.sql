-- A web search is capped, names no private party, and tells the founder only of his account.
-- Assigned: it_engineer
--
-- Founder ledger 1118 (5 Oct 2026): the edge secret SERPER_API_KEY is set; the seats' web search moves to Serper
-- (supabase/functions/_shared/web_search.ts, called from think.ts webSearch). The keyless scrape before it is
-- removed totally (a bot-check refused every datacenter call).
--
-- WHAT THIS ADDS
--   public.web_search_day          one row per Dubai day: searches used against the hard cap (50).
--   fn_web_search_claim(query)     called before EVERY search. Refuses a query that contains a value the company
--                                  holds for a supplier, customer or lead: an email (exact, case-folded), a
--                                  phone (as its UAE national number: digits only, +971 / 00971 / 971 / 0 removed)
--                                  or a name (leads: company, licence legal, contact, signatory; customers;
--                                  supplier_beneficial_owner) as a whole phrase. Query and names pass through ONE
--                                  normalisation, fn_web_search_norm: fn_ar_norm (alef variants, ta marbuta,
--                                  alef maqsura, diacritics, tatweel, Arabic digits), lower case, dots dropped,
--                                  other punctuation and whitespace to one space. Exact matching against held
--                                  values, never a word list or matching on prose. A refused query is not
--                                  counted; an allowed one is counted atomically; the 51st of a day is refused.
--   fn_web_search_degraded(...)    two finding keys, so an outage can never hide or close a billing finding:
--                                  duty:integration:web_search:billing (401/402/403, notify=true: the Serper
--                                  account is the founder's) and duty:integration:web_search:outage (no key, an
--                                  outage, a failed claim, the cap: notify=false, the IT engineer's;
--                                  fn_customer_support_sends_the_it_digest keeps notify=false internal).
--
-- A lead whose own email domain is a government one (*.gov.ae) is a public authority: its company_name alone is
-- exempt (never its licence legal name); its contact and signatory are people and are never exempt. Measured 5 Oct 2026:
-- a lead "DUBAI MUNICIPALITY" at dm.gov.ae otherwise refused every Dubai Municipality regulatory query.
-- Names shorter than 3 characters are never matched (a 2-letter company would refuse every query containing it).
-- WHAT THIS DOES NOT CHANGE: no search reads or stores the query text beyond the call; the counter keeps counts.
--
-- Prevented by: supabase/functions/_shared/web_search.test.ts and the probe below.
--   node scripts/apply_sql.mjs scripts/sql/a_web_search_is_capped_names_no_private_party_and_tells_the_founder_only_of_his_account.sql --apply --ddl

create table if not exists public.web_search_day (
  day         date primary key,
  used        integer not null default 0 check (used >= 0),
  cap         integer not null default 50 check (cap > 0),
  updated_at  timestamptz not null default now()
);
alter table public.web_search_day enable row level security;
drop policy if exists web_search_day_service_role_only on public.web_search_day;
create policy web_search_day_service_role_only on public.web_search_day
  as permissive for all to public using (false) with check (false);
revoke all on public.web_search_day from anon, authenticated;
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('web_search_day', false, 'measurement', 'a per-day count of web searches against the cap; no query text, rebuilt by the next day', 'it_engineer')
on conflict (table_name) do nothing;


-- One normalisation for the query AND every held name, so both sides are compared in the same form: Arabic
-- folded by fn_ar_norm (alef variants, ta marbuta to ha, alef maqsura to ya, diacritics and tatweel removed,
-- Arabic digits to Latin), lower case, dots dropped (L.L.C. reads llc), and every other run of punctuation or
-- whitespace to one space.
create or replace function public.fn_web_search_norm(p_text text)
 returns text
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select ' ' || btrim(regexp_replace(replace(lower(coalesce(public.fn_ar_norm(p_text), '')), '.', ''), '[^[:alnum:]]+', ' ', 'g')) || ' '
$function$;
revoke execute on function public.fn_web_search_norm(text) from public, anon, authenticated;

-- A phone as its UAE national number: digits only (Arabic digits folded first), then one leading +971, 00971,
-- 971 or trunk 0 removed. "+971 50 123 4567", "00971501234567" and "050-123-4567" all read 501234567.
create or replace function public.fn_web_search_phone(p_text text)
 returns text
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select nullif(regexp_replace(regexp_replace(coalesce(public.fn_ar_norm(p_text), ''), '[^0-9]', '', 'g'), '^(00971|971|0)', ''), '')
$function$;
revoke execute on function public.fn_web_search_phone(text) from public, anon, authenticated;

-- Two finding keys, so an outage can never hide (or close) a billing finding:
--   duty:integration:web_search:billing   Serper refused the key or the account (401/402/403): notify=true,
--                                         the account is the founder's
--   duty:integration:web_search:outage    no key, an outage, a failed claim or the daily cap: notify=false
create or replace function public.fn_web_search_degraded(p_reason text, p_notify boolean, p_detail text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_billing boolean := p_reason = 'key_or_billing';
  v_key text := 'duty:integration:web_search:' || case when v_billing then 'billing' else 'outage' end;
begin
  perform public.fn_it_engineer_finding_upsert(
    v_key,
    'web_search (Serper): ' || coalesce(p_detail, p_reason) || '. The seats reason without the web until it answers again',
    'supabase/functions/_shared/web_search.ts', 'agent_facing', 1,
    jsonb_build_object('integration', 'web_search', 'owner_seat', 'it_engineer', 'reason', p_reason,
                       'notify', coalesce(p_notify, false) and v_billing,
                       'reconnect_url', 'https://serper.dev/'),
    '{}'::text[], '{}'::text[], 'it_engineer.web_search');
  return jsonb_build_object('raised', true, 'reason', p_reason, 'issue_key', v_key);
end $function$;
revoke execute on function public.fn_web_search_degraded(text, boolean, text) from public, anon, authenticated;

create or replace function public.fn_web_search_claim(p_query text, p_now timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_q    text := public.fn_web_search_norm(p_query);
  v_day  date := (p_now at time zone 'Asia/Dubai')::date;
  v_used integer;
begin
  -- 1. emails: any address in the query that the company holds for a party (exact, case-folded)
  if exists (
    select 1 from regexp_matches(lower(coalesce(p_query, '')), '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}', 'g') m(e)
     where exists (select 1 from public.leads l where lower(l.email) = m.e[1])
        or exists (select 1 from public.customers c where lower(c.email) = m.e[1])) then
    return jsonb_build_object('allowed', false, 'reason', 'names_a_private_party');
  end if;
  -- 2. phones: any number in the query, as its national number, equal to one held for a party
  if exists (
    select 1 from regexp_matches(coalesce(public.fn_ar_norm(p_query), ''), '\+?[0-9][0-9 ().-]{5,}[0-9]', 'g') m(t)
     cross join lateral (select public.fn_web_search_phone(m.t[1]) n) q
     where length(q.n) >= 7 and exists (
       select 1 from public.leads l
        cross join lateral (values (l.phone), (l.phone_e164), (l.whatsapp), (l.whatsapp_phone)) x(v)
        where public.fn_web_search_phone(x.v) = q.n
       union all
       select 1 from public.customers c
        cross join lateral (values (c.phone), (c.whatsapp_phone)) x(v)
        where public.fn_web_search_phone(x.v) = q.n)) then
    return jsonb_build_object('allowed', false, 'reason', 'names_a_private_party');
  end if;
  -- 3. names: the exact held name of a party, as a whole phrase of the normalised query. A lead at a *.gov.ae
  --    domain is an authority: only its COMPANY name is exempt; its contact and signatory are people.
  if exists (
    select 1 from (
      select x.n from public.leads l
       cross join lateral (values
         (case when coalesce(l.email_domain, '') ~ '(^|\.)gov\.ae$' then null else l.company_name end),
         (l.licence_legal_name), (l.contact_name), (l.signatory_name)) x(n)
      union all select full_name from public.customers union all select full_name from public.supplier_beneficial_owner
    ) s
     where length(btrim(public.fn_web_search_norm(s.n))) >= 3
       and position(public.fn_web_search_norm(s.n) in v_q) > 0) then
    return jsonb_build_object('allowed', false, 'reason', 'names_a_private_party');
  end if;
  -- 4. the day's cap, counted atomically
  insert into public.web_search_day as d (day, used) values (v_day, 1)
  on conflict (day) do update set used = d.used + 1, updated_at = now() where d.used < d.cap
  returning used into v_used;
  if v_used is null then
    perform public.fn_web_search_degraded('daily_cap', false,
      'the daily cap of ' || (select cap from public.web_search_day where day = v_day) || ' searches is reached for ' || v_day);
    return jsonb_build_object('allowed', false, 'reason', 'daily_cap');
  end if;
  return jsonb_build_object('allowed', true, 'used', v_used);
end $function$;
revoke execute on function public.fn_web_search_claim(text, timestamptz) from public, anon, authenticated;

-- == PROBE =========================================================================================
-- ZZ DEMO subjects only (example.invalid addresses, a 555 test number); 2099 days for the cap; the sub-block
-- rolls back only itself and reports through a verdict row.
create temp table if not exists _qd_probe (verdict text) on commit drop;
do $probe$
declare r jsonb := '{}'::jsonb; v_ok jsonb; v_cap jsonb; v_out text; v_bill jsonb; v_outg jsonb;
  t timestamptz := timestamptz '2099-03-01 10:00+04';
begin
  begin
    insert into public.leads (company_name, contact_name, email, email_domain, phone)
    values ('ZZ DEMO Websearch Probe Trading L.L.C.', 'Zzdemo Probeperson', 'zz.websearch.probe@example.invalid', 'example.invalid', '+971 55 555 0123');
    insert into public.leads (company_name, contact_name, email, email_domain)
    values ('ZZ DEMO Probe Authority', 'Zzdemo Govperson', 'zz.gov.probe@zzdemo.gov.ae', 'zzdemo.gov.ae');
    insert into public.customers (full_name, email) values ('مُحَمَّد زززديمو الأحمدى', 'zz.ar.probe@example.invalid');
    r := jsonb_build_object(
      'name_dots',   public.fn_web_search_claim('permit for zz demo websearch probe trading llc', t),
      'name_case',   public.fn_web_search_claim('ZZ-DEMO WEBSEARCH PROBE TRADING L.L.C. licence', t),
      'email',       public.fn_web_search_claim('who is ZZ.Websearch.Probe@example.invalid', t),
      'phone_00',    public.fn_web_search_claim('call 00971555550123 about pools', t),
      'phone_0',     public.fn_web_search_claim('call 055-555-0123 about pools', t),
      'arabic',      public.fn_web_search_claim('محمد زززديمو الاحمدي رخصة', t),
      'gov_company', public.fn_web_search_claim('zz demo probe authority pool permit', t),
      'gov_person',  public.fn_web_search_claim('zzdemo govperson pool permit', t),
      'partial',     public.fn_web_search_claim('zz demo websearch probe pool permit', t),
      'other_phone', public.fn_web_search_claim('call 050 000 0000 about pools', t));
    insert into public.web_search_day (day, used) values (date '2099-03-02', 49);
    v_ok  := public.fn_web_search_claim('dubai pool permit', timestamptz '2099-03-02 10:00+04');
    v_cap := public.fn_web_search_claim('dubai pool permit', timestamptz '2099-03-02 11:00+04');
    v_bill := public.fn_web_search_degraded('key_or_billing', true, 'probe 402');
    v_outg := public.fn_web_search_degraded('outage', false, 'probe 500');
    v_out := case
      when (select count(*) from jsonb_each(r) e where e.key in ('name_dots','name_case','email','phone_00','phone_0','arabic','gov_person')
              and e.value->>'reason' = 'names_a_private_party') <> 7
        then 'PROBE FAILED: a held name, email, phone or person was not refused: ' || r::text
      when r->'gov_company'->>'allowed' <> 'true' then 'PROBE FAILED: a gov.ae company name was refused: ' || r::text
      when r->'partial'->>'allowed' <> 'true' then 'PROBE FAILED: a partial name (not the held name) was refused: ' || r::text
      when r->'other_phone'->>'allowed' <> 'true' then 'PROBE FAILED: a number nobody holds was refused: ' || r::text
      when (v_ok->>'used')::int is distinct from 50 or v_cap->>'reason' is distinct from 'daily_cap' then 'PROBE FAILED: the cap: ' || v_ok::text || ' ' || v_cap::text
      when v_bill->>'issue_key' = v_outg->>'issue_key' then 'PROBE FAILED: billing and outage share a finding key'
      when (select evidence->>'notify' from public.it_engineer_finding where issue_key = v_bill->>'issue_key') <> 'true'
        or (select closed_at from public.it_engineer_finding where issue_key = v_bill->>'issue_key') is not null
        then 'PROBE FAILED: the billing finding is not open with notify=true after an outage'
      when (select evidence->>'notify' from public.it_engineer_finding where issue_key = v_outg->>'issue_key') <> 'false'
        then 'PROBE FAILED: the outage finding would reach the founder'
      else 'PROBE OK: held name (dots/case/punctuation), email, phone (+971/00971/0) and Arabic-normalised name refused; '
           || 'gov.ae company allowed, its person refused; partial name and unknown number allowed; search 50 allowed, 51 refused; '
           || 'billing (notify=true) and outage (notify=false) on separate keys' end;
    raise exception 'QD_PROBE_ROLLBACK';
  exception when others then
    if sqlerrm <> 'QD_PROBE_ROLLBACK' then v_out := 'PROBE FAILED: ' || left(sqlerrm, 400); end if;
  end;
  insert into _qd_probe values (v_out);
end $probe$;
select verdict from _qd_probe;
