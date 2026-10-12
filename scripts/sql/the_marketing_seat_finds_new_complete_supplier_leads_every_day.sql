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
--   1. lead_sourcing_run   one row per batch: queries, Serper credits, model calls and cost, crawl counts, per trade.
--   2. lead_prospect       every company found, each field with its SOURCE URL and collected_at (UAE PDPL).
--   3. fn_lead_sourcing_next_cells(n)  (trade, emirate) cells with the FEWEST suppliers first, every trade but F&B;
--      among equals the one sourced longest ago. lead_sourcing_daily_quota (app_secrets, 300) and fn_lead_sourcing_today.
--   4. fn_lead_sourcing_record(run, prospects)  records the batch, then per prospect, in this order:
--        suppressed — its email is in email_suppressions, its email/phone/domain matches an erased (PDPL) lead,
--                     or a lead at that email bounced. NEVER re-added.
--        duplicate  — a lead already has that domain (site or email), that phone, or that name.
--        complete   — all eight fields, email MX-checked: PROMOTED into public.leads (source 'marketing_sourcing').
--        incomplete — kept in lead_prospect for a later enrichment pass, never sent anything.
--   5. fn_lead_sourcing_daily_report — ONE report per Dubai day to the CEO (handoff marketing.lead_sourcing; read,
--      nothing to approve) and fn_ceo_reads_lead_sourcing_report, its handler.
--   6. pg_cron lead_sourcing_batch, every 5 minutes -> fn_lead_sourcing_kick -> the marketing function's
--      'lead_sourcing' action (its own schedule, never the resilience tick), until the day's quota.
-- WHAT IT DOES NOT DO: it sends nothing to anyone (the invitation belongs to sales_engineer and customer_support,
-- instr 625), it never touches an existing lead, and it does not measure catch-all (needs SMTP on port 25; see
-- supabase/functions/marketing/lead_sourcing.ts).

-- ── 1–2. THE TABLES ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.lead_sourcing_run (
  id              bigserial primary key,
  kind            text not null check (kind in ('batch', 'pilot', 'probe')),
  started_at      timestamptz not null default now(),   -- the batch's start: its model cost is read from ai_cost_log after it
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
  model_calls     integer not null default 0,
  linkedin_queries integer not null default 0,
  llm_cost_usd    numeric not null default 0,       -- ai_cost_log, fn 'marketing', class routine_employee_reasoning, during the batch
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

-- ── 3. PRIORITY: the (trade, emirate) cells with the fewest suppliers first ───────────────────────────
-- Every active trade is in scope except food and beverage (founder, via the release coordinator, 12 Oct 2026; on
-- 12 Oct no active code matched the exclusion). Among equals, the cell sourced longest ago, so a cell that found
-- nothing is not re-queried until every other equal cell has had its turn.
create or replace function public.fn_lead_sourcing_next_cells(p_limit integer default 1)
returns table (code text, label text, aliases text[], emirate text, suppliers integer, last_sourced timestamptz)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with em(emirate) as (values ('Dubai'), ('Abu Dhabi'), ('Sharjah'), ('Ajman'), ('Ras Al Khaimah'), ('Fujairah'), ('Umm Al Quwain')),
  pool as (
    select e.emirate, c.code, count(*)::int n
      from public.leads l cross join lateral unnest(l.invite_trades) c(code) join em e on e.emirate = l.emirate
     where not coalesce(l.is_demo, false)
     group by 1, 2)
  select t.code, t.label, t.aliases, em.emirate, coalesce(p.n, 0),
         (select max(r.started_at) from public.lead_sourcing_run r
           where r.kind <> 'probe' and t.code = any(r.trades) and r.emirate = em.emirate)
    from public.taxonomy_trade t cross join em
    left join pool p on p.code = t.code and p.emirate = em.emirate
   where t.active and t.code !~* '(^|_)(food|beverage|catering|restaurant|bakery)' and coalesce(t.group_code, '') !~* 'food'
   order by 5, 6 nulls first, 1, 4
   limit greatest(1, least(p_limit, 20));
$fn$;
revoke execute on function public.fn_lead_sourcing_next_cells(integer) from public, anon, authenticated;

-- The day's quota of NEW COMPLETE leads, a setting (0 stops the batches). The batches stop for the Dubai day once
-- it is reached.
insert into public.app_secrets (key, value) values ('lead_sourcing_daily_quota', '300') on conflict (key) do nothing;

create or replace function public.fn_lead_sourcing_today()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'day', (now() at time zone 'Asia/Dubai')::date,
    'quota', coalesce((select nullif(btrim(value), '')::int from public.app_secrets where key = 'lead_sourcing_daily_quota'), 0),
    'promoted', coalesce((select sum(promoted) from public.lead_sourcing_run
                           where kind = 'batch' and run_day = (now() at time zone 'Asia/Dubai')::date), 0));
$fn$;
revoke execute on function public.fn_lead_sourcing_today() from public, anon, authenticated;

-- ── 4. RECORD, DEDUPE, SUPPRESS, PROMOTE, REPORT ──────────────────────────────────────────────────
create or replace function public.fn_lead_sourcing_record(p_run jsonb, p_prospects jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_run public.lead_sourcing_run; p jsonb; v_status text; v_reason text; v_lead bigint; v_demo boolean;
  v_email text; v_dom text; v_phone text; v_name text;
begin
  insert into public.lead_sourcing_run (kind, emirate, trades, queries, serper_credits, usd_per_credit, places, sites_crawled,
                                        pages_fetched, robots_refused, errors, started_at, model_calls, linkedin_queries)
  values (coalesce(p_run->>'kind', 'batch'), p_run->>'emirate',
          array(select jsonb_array_elements_text(coalesce(p_run->'trades', '[]'::jsonb))),
          coalesce((p_run->>'queries')::int, 0), coalesce((p_run->>'serper_credits')::numeric, 0),
          coalesce((p_run->>'usd_per_credit')::numeric, 0.001), coalesce((p_run->>'places')::int, 0),
          coalesce((p_run->>'sites_crawled')::int, 0), coalesce((p_run->>'pages_fetched')::int, 0),
          coalesce((p_run->>'robots_refused')::int, 0), coalesce(p_run->'errors', '[]'::jsonb),
          coalesce((p_run->>'started_at')::timestamptz, now()), coalesce((p_run->>'model_calls')::int, 0),
          coalesce((p_run->>'linkedin_queries')::int, 0))
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

  -- The model's cost for this batch: what ai_gateway logged for fn 'marketing' on the routine class since the batch
  -- began (the seat's other model work runs on its own classes; a credential per fn is cred_fn_<fn>, so the batch
  -- calls as 'marketing')
  -- (cost_usd_reported is OpenRouter's own charge; cost_aed at the pegged 3.6725 where it is missing).
  update public.lead_sourcing_run r set llm_cost_usd = coalesce((
      select sum(coalesce(c.cost_usd_reported, c.cost_aed / 3.6725)) from public.ai_cost_log c
       where c.fn = 'marketing' and c.task_class = 'routine_employee_reasoning' and c.occurred_at >= r.started_at and c.occurred_at <= now()), 0)
   where r.id = v_run.id returning * into v_run;

  return jsonb_build_object('run_id', v_run.id, 'prospects', v_run.prospects, 'promoted', v_run.promoted,
    'duplicates', v_run.duplicates, 'suppressed', v_run.suppressed, 'by_trade', v_run.by_trade,
    'serper_usd', round(v_run.serper_credits * v_run.usd_per_credit, 4), 'llm_usd', round(v_run.llm_cost_usd, 4));
end $fn$;
revoke execute on function public.fn_lead_sourcing_record(jsonb, jsonb) from public, anon, authenticated;

-- ── 5. ONE REPORT A DAY TO THE CEO, AND HIS READ RECEIPT ────────────────────────────────────────────
-- The batches run every 5 minutes; the CEO gets ONE report per Dubai day (the day before), per trade: new complete
-- leads, found, and the cost. fn_seat_handoff is idempotent on (type, subject), so every batch may call this.
create or replace function public.fn_lead_sourcing_daily_report(p_day date default ((now() at time zone 'Asia/Dubai')::date - 1))
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_sum jsonb; v_id bigint;
begin
  select jsonb_build_object('day', p_day, 'batches', count(distinct r.id), 'promoted', coalesce(sum(r.promoted), 0),
           'serper_usd', round(coalesce(sum(r.serper_credits * r.usd_per_credit), 0), 4), 'llm_usd', round(coalesce(sum(r.llm_cost_usd), 0), 4),
           'by_trade', coalesce((select jsonb_object_agg(t, jsonb_build_object('found', f, 'new_complete', c))
              from (select coalesce(p.trade_code, '(no exact trade)') t, count(*) f, count(*) filter (where p.status = 'promoted') c
                      from public.lead_prospect p join public.lead_sourcing_run x on x.id = p.run_id
                     where x.kind = 'batch' and x.run_day = p_day group by 1) q), '{}'::jsonb))
    into v_sum from public.lead_sourcing_run r where r.kind = 'batch' and r.run_day = p_day;
  if coalesce((v_sum->>'batches')::int, 0) = 0 then return jsonb_build_object('filed', false, 'reason', 'no batch ran on ' || p_day); end if;
  v_id := public.fn_seat_handoff('marketing', 'ceo', 'marketing.lead_sourcing', 'lead_sourcing_day', p_day::text, v_sum);
  update public.lead_sourcing_run set handoff_id = v_id where kind = 'batch' and run_day = p_day and handoff_id is null;
  return jsonb_build_object('filed', true, 'handoff_id', v_id) || v_sum;
end $fn$;
revoke execute on function public.fn_lead_sourcing_daily_report(date) from public, anon, authenticated;

create or replace function public.fn_ceo_reads_lead_sourcing_report(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; n int;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'marketing.lead_sourcing' then
    raise exception 'fn_ceo_reads_lead_sourcing_report: % is not a marketing.lead_sourcing handoff', p_id;
  end if;
  update public.lead_sourcing_run set read_by_ceo_at = coalesce(read_by_ceo_at, now())
   where kind = 'batch' and run_day = (a.detail->>'subject_id')::date;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'marketing.lead_sourcing % names day %, which has no batch', p_id, a.detail->>'subject_id'; end if;
  return jsonb_build_object('read', true, 'day', a.detail->>'subject_id', 'promoted', a.detail->'promoted', 'by_trade', a.detail->'by_trade',
                            'note', 'Read by the CEO. New complete supplier leads per trade; nothing to approve.');
end $fn$;
revoke execute on function public.fn_ceo_reads_lead_sourcing_report(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('marketing.lead_sourcing', 'marketing', 'ceo',
   'The marketing seat''s supplier lead sourcing for one Dubai day: new complete leads per trade (fewest-supplier trades first), found, and the Serper and model cost. Informational: the CEO reads it; nothing is approved.',
   'fn_ceo_reads_lead_sourcing_report', interval '1 day', false,
   'scripts/sql/the_marketing_seat_finds_new_complete_supplier_leads_every_day.sql')
on conflict do nothing;



-- ── 6. ITS OWN SCHEDULE ─────────────────────────────────────────────────────────────────────────────
-- NOT the resilience tick (release coordinator, 12 Oct 2026: the marketing step there already runs ~55 s and starves
-- the seat duties). pg_cron calls this every 5 minutes; it posts ONE request to the marketing function, which
-- answers 202 at once and runs the batch in the background under its 150 s cap. The credentials are read here at
-- run time, so no key is ever written into cron.job (the schema mirror exports cron commands verbatim).
create or replace function public.fn_lead_sourcing_kick()
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ref text; v_anon text; v_cred text; t jsonb;
begin
  t := public.fn_lead_sourcing_today();
  if (t->>'quota')::int <= 0 or (t->>'promoted')::int >= (t->>'quota')::int then return null; end if;   -- quota reached or off
  select value into v_ref  from public.app_secrets where key = 'project_ref';
  select value into v_anon from public.app_secrets where key = 'anon_key';
  select value into v_cred from public.app_secrets where key = 'cred_fn_marketing';
  if v_ref is null or v_anon is null or v_cred is null then
    raise exception 'fn_lead_sourcing_kick: project_ref, anon_key or cred_fn_marketing missing from app_secrets';
  end if;
  return net.http_post(url := 'https://' || v_ref || '.supabase.co/functions/v1/marketing',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_anon, 'apikey', v_anon),
    body := jsonb_build_object('__secret', v_cred, 'action', 'lead_sourcing'), timeout_milliseconds := 10000);
end $fn$;
revoke execute on function public.fn_lead_sourcing_kick() from public, anon, authenticated;

do $cron$ begin
  if exists (select 1 from cron.job where jobname = 'lead_sourcing_batch') then perform cron.unschedule('lead_sourcing_batch'); end if;
  perform cron.schedule('lead_sourcing_batch', '*/5 * * * *', 'select public.fn_lead_sourcing_kick();');
end $cron$;

-- ── 7. PROBE: a verdict ROW, ZZ DEMO subjects only, nothing left behind ────────────────────────────
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
