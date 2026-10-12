-- THE MARKETING SEAT FINDS NEW, COMPLETE SUPPLIER LEADS EVERY DAY.   seat: marketing · 12 Oct 2026
--
-- Founder rulings 1184 and 1186 (12 Oct 2026): the marketing seat must CONTINUOUSLY find NEW UAE supplier leads
-- beyond the ~19,900 in public.leads, each one complete — company, trade, contact name, position, business email,
-- mobile/phone, website, emirate — so the next list is ready when the current one runs out. 1186 supersedes the
-- 10 Aug "no new leads" pause. Apify stays cancelled; nothing is bought without a cost quote.
--
-- MEASURED BEFORE THIS FILE (12 Oct 2026):
--   * public.leads 19,901 rows; sources uaecsd 9,873, uaecsd_xlsx 4,282, web_scrape 4,067, … — nothing adds to it now.
--   * lead_trade_class is EMPTY; the per-trade supplier pool is leads.invite_trades (16,407 rows carry one).
--     Ordered by that count, the fewest-supplier active trades have 0 leads (e.g. abrasives_surface_finishing).
--   * SERPER_API_KEY is an EDGE secret (not in app_secrets), so sourcing runs in the marketing edge function.
--   * email_suppressions 37 rows (36 hard bounces); pdpl_lead_erase_vault keeps the snapshot of an erased lead.
--
-- WHAT THIS FILE BUILDS
--   1. lead_sourcing_run   one row per run: queries, Serper credits, cost, crawl counts, outcome per trade.
--   2. lead_prospect       every company found, each field with its SOURCE URL and collected_at (UAE PDPL).
--   3. fn_lead_sourcing_priority(emirate, n)  active trades with the FEWEST suppliers first; among equals, the one
--      sourced longest ago (so an empty trade is not re-queried every day).
--   4. fn_lead_sourcing_record(run, prospects)  records the run, then per prospect, in this order:
--        suppressed — its email is in email_suppressions, its email/phone/domain matches an erased (PDPL) lead,
--                     or a lead at that email bounced. NEVER re-added.
--        duplicate  — a lead already has that domain (site or email), that phone, or that name.
--        complete   — all eight fields, email MX-checked: PROMOTED into public.leads (source 'marketing_sourcing').
--        incomplete — kept in lead_prospect for a later enrichment pass, never sent anything.
--      and files the per-trade count to the CEO (handoff marketing.lead_sourcing; the CEO reads it, nothing to approve).
--   5. fn_ceo_reads_lead_sourcing_report — the handler: the CEO's read receipt.
-- WHAT IT DOES NOT DO: it sends nothing to anyone (the invitation belongs to sales_engineer and customer_support,
-- instr 625), it never touches an existing lead, and it does not measure catch-all (needs SMTP on port 25; see
-- supabase/functions/marketing/lead_sourcing.ts). The daily runner is the 'lead_sourcing' duty in duties.ts.

-- ── 1–2. THE TABLES ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.lead_sourcing_run (
  id              bigserial primary key,
  kind            text not null check (kind in ('daily', 'pilot', 'probe')),
  run_day         date not null default (now() at time zone 'Asia/Dubai')::date,
  emirate         text not null,
  trades          text[] not null,
  queries         integer not null default 0,
  serper_credits  numeric not null default 0,
  usd_per_credit  numeric not null default 0.001,   -- Serper Starter list price, $50 / 50k credits (serper.dev, 12 Oct 2026)
  places          integer not null default 0,
  sites_crawled   integer not null default 0,
  pages_fetched   integer not null default 0,
  robots_refused  integer not null default 0,
  prospects       integer not null default 0,
  complete        integer not null default 0,
  duplicates      integer not null default 0,
  suppressed      integer not null default 0,
  promoted        integer not null default 0,
  by_trade        jsonb not null default '{}'::jsonb,
  errors          jsonb not null default '[]'::jsonb,
  handoff_id      bigint,
  read_by_ceo_at  timestamptz,
  created_at      timestamptz not null default now()
);
create table if not exists public.lead_prospect (
  id               bigserial primary key,
  run_id           bigint not null references public.lead_sourcing_run(id) on delete cascade,
  company_name     text not null,
  trade_code       text,
  emirate          text,
  website          text,
  domain           text,
  phone_e164       text,
  phone_kind       text,
  email            text,
  email_status     text,
  contact_name     text,
  contact_title    text,
  place_id         text,
  query            text,
  field_sources    jsonb not null default '{}'::jsonb check (jsonb_typeof(field_sources) = 'object'),
  collected_at     timestamptz not null default now(),
  status           text not null check (status in ('complete', 'incomplete', 'duplicate', 'suppressed', 'promoted')),
  status_reason    text,
  promoted_lead_id bigint references public.leads(id) on delete set null
);
create index if not exists lead_prospect_run_idx on public.lead_prospect (run_id);
create index if not exists lead_prospect_domain_idx on public.lead_prospect (domain);
do $rls$ begin
  alter table public.lead_sourcing_run enable row level security;
  alter table public.lead_prospect enable row level security;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'lead_sourcing_run') then
    create policy lead_sourcing_run_service_role_only on public.lead_sourcing_run as permissive for all to public using (false) with check (false);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'lead_prospect') then
    create policy lead_prospect_service_role_only on public.lead_prospect as permissive for all to public using (false) with check (false);
  end if;
end $rls$;
revoke all on public.lead_sourcing_run, public.lead_prospect from anon, authenticated;

-- ── 3. PRIORITY: the fewest suppliers first ───────────────────────────────────────────────────────
create or replace function public.fn_lead_sourcing_priority(p_emirate text default 'Dubai', p_limit integer default 3)
returns table (code text, label text, aliases text[], suppliers integer, last_sourced date)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select t.code, t.label, t.aliases,
         (select count(*) from public.leads l
           where t.code = any(l.invite_trades) and not coalesce(l.is_demo, false) and l.emirate = p_emirate)::int,
         (select max(r.run_day) from public.lead_sourcing_run r where r.kind <> 'probe' and t.code = any(r.trades) and r.emirate = p_emirate)
    from public.taxonomy_trade t
   where t.active
   order by 4, 5 nulls first, 1
   limit greatest(1, least(p_limit, 20));
$fn$;
revoke execute on function public.fn_lead_sourcing_priority(text, integer) from public, anon, authenticated;

-- ── 4. RECORD, DEDUPE, SUPPRESS, PROMOTE, REPORT ──────────────────────────────────────────────────
create or replace function public.fn_lead_sourcing_record(p_run jsonb, p_prospects jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_run public.lead_sourcing_run; p jsonb; v_status text; v_reason text; v_lead bigint; v_demo boolean;
  v_email text; v_dom text; v_phone text; v_name text;
begin
  insert into public.lead_sourcing_run (kind, emirate, trades, queries, serper_credits, usd_per_credit, places, sites_crawled,
                                        pages_fetched, robots_refused, errors)
  values (coalesce(p_run->>'kind', 'daily'), p_run->>'emirate',
          array(select jsonb_array_elements_text(coalesce(p_run->'trades', '[]'::jsonb))),
          coalesce((p_run->>'queries')::int, 0), coalesce((p_run->>'serper_credits')::numeric, 0),
          coalesce((p_run->>'usd_per_credit')::numeric, 0.001), coalesce((p_run->>'places')::int, 0),
          coalesce((p_run->>'sites_crawled')::int, 0), coalesce((p_run->>'pages_fetched')::int, 0),
          coalesce((p_run->>'robots_refused')::int, 0), coalesce(p_run->'errors', '[]'::jsonb))
  returning * into v_run;
  v_demo := v_run.kind = 'probe';

  for p in select * from jsonb_array_elements(coalesce(p_prospects, '[]'::jsonb)) loop
    v_email := nullif(lower(btrim(p->>'email')), '');
    v_dom   := nullif(lower(btrim(p->>'domain')), '');
    v_phone := nullif(btrim(p->>'phone_e164'), '');
    v_name  := nullif(btrim(p->>'company_name'), '');
    v_status := null; v_reason := null; v_lead := null;
    if v_name is null then continue; end if;
    -- A probe can never write a real company into leads: is_demo is derived from the 'ZZ DEMO' name (generated column).
    if v_demo and v_name not ilike 'ZZ DEMO%' then raise exception 'a probe run may only record ZZ DEMO companies'; end if;

    if v_email is not null and exists (select 1 from public.email_suppressions s where lower(s.email) = v_email) then
      v_status := 'suppressed'; v_reason := 'email is on the suppression list';
    elsif exists (select 1 from public.pdpl_lead_erase_vault e
                   where (v_email is not null and lower(e.snapshot->>'email') = v_email)
                      or (v_phone is not null and e.snapshot->>'phone_e164' = v_phone)
                      or (v_dom is not null and lower(e.snapshot->>'domain') = v_dom)) then
      v_status := 'suppressed'; v_reason := 'matches a lead erased on a privacy request';
    elsif v_email is not null and exists (select 1 from public.leads l where lower(l.email) = v_email and l.invite_status = 'bounced') then
      v_status := 'suppressed'; v_reason := 'a lead at this email bounced';
    elsif exists (select 1 from public.leads l
                   where (v_dom is not null and (lower(l.domain) = v_dom or lower(l.email_domain) = v_dom))
                      or (v_phone is not null and l.phone_e164 = v_phone)
                      or lower(btrim(l.company_name)) = lower(v_name)) then
      v_status := 'duplicate'; v_reason := 'a lead already has this domain, phone or name';
    elsif v_dom is null or v_email is null or p->>'email_status' is distinct from 'mx_ok' or v_phone is null
       or nullif(p->>'trade_code', '') is null or nullif(p->>'contact_name', '') is null
       or nullif(p->>'contact_title', '') is null or nullif(p->>'website', '') is null or nullif(p->>'emirate', '') is null then
      v_status := 'incomplete';
      v_reason := 'missing: ' || concat_ws(', ',
        case when nullif(p->>'trade_code', '') is null then 'trade' end,
        case when nullif(p->>'contact_name', '') is null then 'contact name' end,
        case when nullif(p->>'contact_title', '') is null then 'position' end,
        case when v_email is null then 'email' when p->>'email_status' is distinct from 'mx_ok' then 'deliverable email' end,
        case when v_phone is null then 'phone' end,
        case when nullif(p->>'website', '') is null then 'website' end,
        case when nullif(p->>'emirate', '') is null then 'emirate' end);
    else
      insert into public.leads (company_name, website, domain, phone_e164, phone, emirate, city, email, email_domain,
                                email_verified, contact_name, invite_trades, place_id, source, enrich_source, scraped_at,
                                notes)
      values (v_name, p->>'website', v_dom, v_phone, v_phone, p->>'emirate', p->>'emirate', v_email, split_part(v_email, '@', 2),
              'mx_ok', p->>'contact_name', array[p->>'trade_code'], nullif(p->>'place_id', ''), 'marketing_sourcing',
              'serper_places+company_site', current_date,
              'Sourced by the marketing seat (lead_sourcing_run ' || v_run.id || '). Contact position: ' || (p->>'contact_title')
              || '. Field sources in public.lead_prospect.')
      returning id into v_lead;
      v_status := 'promoted';
    end if;

    insert into public.lead_prospect (run_id, company_name, trade_code, emirate, website, domain, phone_e164, phone_kind, email,
                                      email_status, contact_name, contact_title, place_id, query, field_sources, status,
                                      status_reason, promoted_lead_id)
    values (v_run.id, v_name, nullif(p->>'trade_code', ''), nullif(p->>'emirate', ''), nullif(p->>'website', ''), v_dom, v_phone,
            nullif(p->>'phone_kind', ''), v_email, nullif(p->>'email_status', ''), nullif(p->>'contact_name', ''),
            nullif(p->>'contact_title', ''), nullif(p->>'place_id', ''), p->>'query', coalesce(p->'field_sources', '{}'::jsonb),
            v_status, v_reason, v_lead);
  end loop;

  update public.lead_sourcing_run r set
    prospects  = s.n, complete = s.promoted, duplicates = s.dup, suppressed = s.sup, promoted = s.promoted,
    by_trade   = s.by_trade
  from (select count(*)::int n,
               (count(*) filter (where status = 'promoted'))::int promoted,
               (count(*) filter (where status = 'duplicate'))::int dup,
               (count(*) filter (where status = 'suppressed'))::int sup,
               coalesce((select jsonb_object_agg(t, jsonb_build_object('found', f, 'new_complete', c))
                           from (select coalesce(trade_code, '(no exact trade)') t, count(*) f,
                                        count(*) filter (where status = 'promoted') c
                                   from public.lead_prospect where run_id = v_run.id group by 1) x), '{}'::jsonb) by_trade
          from public.lead_prospect where run_id = v_run.id) s
  where r.id = v_run.id
  returning * into v_run;

  if v_run.kind <> 'probe' then
    update public.lead_sourcing_run set handoff_id = public.fn_seat_handoff('marketing', 'ceo', 'marketing.lead_sourcing',
      'lead_sourcing_run', v_run.id::text,
      jsonb_build_object('emirate', v_run.emirate, 'by_trade', v_run.by_trade, 'promoted', v_run.promoted,
                         'cost_usd', round(v_run.serper_credits * v_run.usd_per_credit, 4)))
     where id = v_run.id returning * into v_run;
  end if;
  return jsonb_build_object('run_id', v_run.id, 'prospects', v_run.prospects, 'promoted', v_run.promoted,
    'duplicates', v_run.duplicates, 'suppressed', v_run.suppressed, 'by_trade', v_run.by_trade,
    'cost_usd', round(v_run.serper_credits * v_run.usd_per_credit, 4), 'handoff_id', v_run.handoff_id);
end $fn$;
revoke execute on function public.fn_lead_sourcing_record(jsonb, jsonb) from public, anon, authenticated;

-- ── 5. THE CEO READS IT ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_reads_lead_sourcing_report(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; r public.lead_sourcing_run;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'marketing.lead_sourcing' then
    raise exception 'fn_ceo_reads_lead_sourcing_report: % is not a marketing.lead_sourcing handoff', p_id;
  end if;
  update public.lead_sourcing_run set read_by_ceo_at = coalesce(read_by_ceo_at, now())
   where id = (a.detail->>'subject_id')::bigint returning * into r;
  if r.id is null then raise exception 'marketing.lead_sourcing % names run %, which does not exist', p_id, a.detail->>'subject_id'; end if;
  return jsonb_build_object('read', true, 'read_at', r.read_by_ceo_at, 'promoted', r.promoted, 'by_trade', r.by_trade,
                            'note', 'Read by the CEO. New complete supplier leads per trade; nothing to approve.');
end $fn$;
revoke execute on function public.fn_ceo_reads_lead_sourcing_report(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('marketing.lead_sourcing', 'marketing', 'ceo',
   'The marketing seat''s supplier lead sourcing run: new complete leads per trade (fewest-supplier trades first), duplicates, suppressed, and the API cost. Informational: the CEO reads it; nothing is approved.',
   'fn_ceo_reads_lead_sourcing_report', interval '1 day', false,
   'scripts/sql/the_marketing_seat_finds_new_complete_supplier_leads_every_day.sql')
on conflict do nothing;

-- ── 6. PROBE: a verdict ROW, ZZ DEMO subjects only, nothing left behind ────────────────────────────
create temp table if not exists _lead_sourcing_probe (verdict text) on commit drop;
do $probe$
declare v jsonb; v_run bigint; v_bad text := null; v_supp text; v_leads_before bigint; v_lead bigint;
begin
  select email into v_supp from public.email_suppressions limit 1;
  select count(*) into v_leads_before from public.leads where not coalesce(is_demo, false);
  v := public.fn_lead_sourcing_record(
    jsonb_build_object('kind', 'probe', 'emirate', 'Dubai', 'trades', jsonb_build_array('aluminium'), 'queries', 2, 'serper_credits', 2),
    jsonb_build_array(
      jsonb_build_object('company_name', 'ZZ DEMO Probe Aluminium LLC', 'trade_code', 'aluminium', 'emirate', 'Dubai',
        'website', 'https://zz-demo-probe.example.invalid', 'domain', 'zz-demo-probe.example.invalid', 'phone_e164', '+971500000001',
        'phone_kind', 'mobile', 'email', 'sales@zz-demo-probe.example.invalid', 'email_status', 'mx_ok',
        'contact_name', 'ZZ DEMO Person', 'contact_title', 'Sales Manager', 'query', 'probe', 'field_sources', '{"email":"probe"}'::jsonb),
      jsonb_build_object('company_name', 'ZZ DEMO Probe Aluminium LLC', 'trade_code', 'aluminium', 'emirate', 'Dubai',
        'domain', 'zz-demo-probe.example.invalid', 'query', 'probe'),
      jsonb_build_object('company_name', 'ZZ DEMO Suppressed Co', 'email', v_supp, 'domain', 'zz-demo-supp.example.invalid', 'query', 'probe'),
      jsonb_build_object('company_name', 'ZZ DEMO Half Found Co', 'trade_code', 'aluminium', 'query', 'probe')));
  v_run := (v->>'run_id')::bigint;
  select promoted_lead_id into v_lead from public.lead_prospect where run_id = v_run and status = 'promoted';
  if (v->>'promoted')::int <> 1 then v_bad := 'expected 1 promoted, got ' || (v->>'promoted'); end if;
  if v_bad is null and (v->>'duplicates')::int <> 1 then v_bad := 'expected 1 duplicate, got ' || (v->>'duplicates'); end if;
  if v_bad is null and v_supp is not null and (v->>'suppressed')::int <> 1 then v_bad := 'expected 1 suppressed, got ' || (v->>'suppressed'); end if;
  if v_bad is null and not exists (select 1 from public.leads where id = v_lead and is_demo and source = 'marketing_sourcing') then
    v_bad := 'the promoted lead is not a demo marketing_sourcing row'; end if;
  if v_bad is null and (v->>'handoff_id') is not null then v_bad := 'a probe run filed a handoff'; end if;
  delete from public.leads where id = v_lead;
  delete from public.lead_sourcing_run where id = v_run;   -- cascades to its prospects
  if v_bad is null and (select count(*) from public.leads where not coalesce(is_demo, false)) <> v_leads_before then
    v_bad := 'real leads changed'; end if;
  if v_bad is null and exists (select 1 from public.leads where company_name like 'ZZ DEMO Probe Aluminium%') then v_bad := 'probe lead left behind'; end if;
  insert into _lead_sourcing_probe values (coalesce('PROBE FAILED: ' || v_bad, 'PROBE OK'));
exception when others then
  insert into _lead_sourcing_probe values ('PROBE FAILED: ' || sqlerrm);
end $probe$;
select verdict from _lead_sourcing_probe;
