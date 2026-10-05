-- A web search is capped, names no private party, and tells the founder only of his account.
-- Assigned: it_engineer
--
-- Founder ledger 1118 (5 Oct 2026): the edge secret SERPER_API_KEY is set; the seats' web search moves to Serper
-- (supabase/functions/_shared/web_search.ts, called from think.ts webSearch). The keyless scrape before it is
-- removed totally (a bot-check refused every datacenter call).
--
-- WHAT THIS ADDS
--   public.web_search_day          one row per Dubai day: searches used against the hard cap (50).
--   fn_web_search_claim(query)     called before EVERY search. Refuses a query that contains the exact name or
--                                  email of a supplier (leads: company, contact, licence legal and signatory
--                                  names; supplier_beneficial_owner), a customer or a lead. A name matches only
--                                  as a whole phrase (word boundaries on both sides), from the names held in
--                                  the database; there is no word list and no matching on prose. A refused
--                                  query is not counted. An allowed one is counted atomically; the 51st of a
--                                  day is refused and raises the it_engineer finding (notify=false).
--   fn_web_search_degraded(...)    the one finding for every way search degrades, duty:integration:web_search,
--                                  raised once (the upsert is idempotent by key). notify=true ONLY for a key or
--                                  billing refusal (the Serper account is the founder's); no key, the cap and
--                                  outages are notify=false and stay with the IT engineer
--                                  (fn_customer_support_sends_the_it_digest keeps notify=false internal).
--
-- A lead whose own email domain is a government one (*.gov.ae) is a public authority, not a private party:
-- measured 5 Oct 2026, a lead "DUBAI MUNICIPALITY" at dm.gov.ae refused every Dubai Municipality regulatory query.
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

create or replace function public.fn_web_search_degraded(p_reason text, p_notify boolean, p_detail text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  perform public.fn_it_engineer_finding_upsert(
    'duty:integration:web_search',
    'web_search (Serper): ' || coalesce(p_detail, p_reason) || '. The seats reason without the web until it answers again',
    'supabase/functions/_shared/web_search.ts', 'agent_facing', 1,
    jsonb_build_object('integration', 'web_search', 'owner_seat', 'it_engineer', 'reason', p_reason,
                       'notify', coalesce(p_notify, false) and p_reason = 'key_or_billing',
                       'reconnect_url', 'https://serper.dev/'),
    '{}'::text[], '{}'::text[], 'it_engineer.web_search');
  return jsonb_build_object('raised', true, 'reason', p_reason);
end $function$;
revoke execute on function public.fn_web_search_degraded(text, boolean, text) from public, anon, authenticated;

create or replace function public.fn_web_search_claim(p_query text, p_now timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_q    text := ' ' || lower(regexp_replace(coalesce(p_query, ''), '[^[:alnum:]@.]+', ' ', 'g')) || ' ';
  v_day  date := (p_now at time zone 'Asia/Dubai')::date;
  v_used integer;
begin
  -- 1. emails: any address in the query that the company holds for a party
  if exists (
    select 1 from regexp_matches(lower(coalesce(p_query, '')), '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}', 'g') m(e)
     where exists (select 1 from public.leads l where lower(l.email) = m.e[1])
        or exists (select 1 from public.customers c where lower(c.email) = m.e[1])) then
    return jsonb_build_object('allowed', false, 'reason', 'names_a_private_party');
  end if;
  -- 2. names: the exact name of a party, as a whole phrase
  if exists (
    select 1 from (
      select x.n from public.leads l
       cross join lateral (values (l.company_name), (l.contact_name), (l.licence_legal_name), (l.signatory_name)) x(n)
       where coalesce(l.email_domain, '') !~ '(^|\.)gov\.ae$'
      union all select full_name from public.customers union all select full_name from public.supplier_beneficial_owner
    ) s
     where length(btrim(s.n)) >= 3
       and position(' ' || btrim(lower(regexp_replace(s.n, '[^[:alnum:]@.]+', ' ', 'g'))) || ' ' in v_q) > 0) then
    return jsonb_build_object('allowed', false, 'reason', 'names_a_private_party');
  end if;
  -- 3. the day's cap, counted atomically
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
-- ZZ DEMO subjects only (a lead at example.invalid); 2099 days for the cap; the sub-block rolls back only itself.
create temp table if not exists _qd_probe (verdict text) on commit drop;
do $probe$
declare v_name jsonb; v_mail jsonb; v_part jsonb; v_ok jsonb; v_cap jsonb; v_f record; v_out text;
begin
  begin
    insert into public.leads (company_name, email) values ('ZZ DEMO Websearch Probe Trading', 'zz.websearch.probe@example.invalid');
    v_name := public.fn_web_search_claim('pool permit rules ZZ DEMO Websearch Probe Trading dubai', timestamptz '2099-03-01 10:00+04');
    v_mail := public.fn_web_search_claim('who is zz.websearch.probe@example.invalid', timestamptz '2099-03-01 10:00+04');
    v_part := public.fn_web_search_claim('ZZ DEMO Websearch Probe pool permit', timestamptz '2099-03-01 10:00+04');
    insert into public.web_search_day (day, used) values (date '2099-03-02', 49);
    v_ok  := public.fn_web_search_claim('dubai municipality pool permit', timestamptz '2099-03-02 10:00+04');
    v_cap := public.fn_web_search_claim('dubai municipality pool permit', timestamptz '2099-03-02 11:00+04');
    select * into v_f from public.it_engineer_finding where issue_key = 'duty:integration:web_search';
    v_out := case
      when v_name->>'reason' is distinct from 'names_a_private_party' then 'PROBE FAILED: a lead name was not refused: ' || v_name::text
      when v_mail->>'reason' is distinct from 'names_a_private_party' then 'PROBE FAILED: a lead email was not refused: ' || v_mail::text
      when (v_part->>'allowed')::boolean is not true then 'PROBE FAILED: a partial name (not the exact name) was refused: ' || v_part::text
      when (v_ok->>'used')::int is distinct from 50 then 'PROBE FAILED: the 50th search was not allowed: ' || v_ok::text
      when v_cap->>'reason' is distinct from 'daily_cap' then 'PROBE FAILED: the 51st search was allowed: ' || v_cap::text
      when v_f.issue_key is null or v_f.closed_at is not null then 'PROBE FAILED: the cap raised no open finding'
      when v_f.evidence->>'notify' is distinct from 'false' then 'PROBE FAILED: the cap finding would reach the founder'
      else 'PROBE OK: exact name and email refused, a partial name allowed, search 50 allowed, 51 refused with an it_engineer finding (notify=false)' end;
    raise exception 'QD_PROBE_ROLLBACK';
  exception when others then
    if sqlerrm <> 'QD_PROBE_ROLLBACK' then v_out := 'PROBE FAILED: ' || left(sqlerrm, 400); end if;
  end;
  insert into _qd_probe values (v_out);
end $probe$;
select verdict from _qd_probe;
