-- THE INVITATION GATE READS THE GLOCKAPPS VERDICT, PER MAILBOX PROVIDER (it_engineer, 27 Oct 2026).
-- Assigned: it_engineer (for marketing: the supplier invitation campaign, ledger 1374 "the only priority").
--
-- WHY. no_test_mail_goes_to_the_founders_own_inboxes.sql (#1696) retired the morning seed to the founder's own
-- inboxes and left fn_invite_placement_gate answering 'fail:seed_retired' on every day. enqueue_supplier_invites, the
-- outreach tick and the day-3/7/14 nudges all require 'pass', so once #1696 is applied no invitation could ever go
-- again. The plan was #1649 (unmerged): an edge function calling the GlockApps API with a GLOCKAPPS_API_KEY secret
-- that does not exist. The key lives only in the session's GlockApps connector (ledger 1344), and the founder is not
-- asked for it. So the verdict is RECORDED by the session (scripts/record_inbox_placement_verdict.mjs, from the
-- connector's get_results) and the gate READS it. Ledger 1312: invitations resume only at >= 80% Outlook inbox in a
-- GlockApps test of supplier@. Founder ledger 1377 (27 Oct, "Outlook inbox bar is the session's job; resume is delegated once the bar is met"),
-- relayed with a scope addition: the gate is PER
-- RECIPIENT PROVIDER, so a provider that passes is invited while one that fails is skipped.
--
-- MEASURED before writing (production, read-only, 27 Oct 2026 23:2xZ):
--   * public.deliverability_test and deliverability_test_provider do not exist; #1649 defines them and is not merged.
--     THIS FILE NOW OWNS THEM, with #1649's column names kept so its edge function could write here unchanged. Its one
--     literal bar (CHECK outlook_inbox_pct >= 80 for a pass) is not carried: the bar lives in public.invite_placement_bar.
--     If #1649 is revived it must drop its section 1 and read these tables (one owner per subject).
--   * GlockApps test 2026-10-27-09:33:53:634t, read through the connector (get_results, detail 'providers'), 111
--     tracked seeds: Microsoft groups Outlook 8 + Hotmail 6 + Outlook.fr 1 + Outlook.de 1 + Exchange (Office365) 2 =
--     18 seeds, 0 inbox, 18 spam; Gmail 17 + 3 = 20 seeds, all in the Promotions tab; Google Workspace 3 + 2 = 5, all
--     inbox; Yahoo 9 + AOL 8 = 17, all spam. scripts/checks/glockapps_27_oct_providers.fixture.json keeps it.
--   * public.email_domain_mx already caches the MX hosts of 8,763 lead domains (mx_sweep.mjs), and every invitable lead
--     needs a kind 'mx' row there (fn_supplier_invite_eligible_ids). So a recipient's mailbox provider is classified
--     in SQL from the cached hosts; no second DNS path is built (Deno.resolveDns would be a second owner of MX).
--   * the effective sender is 'QuotesDone <supplier@quotesdone.com>' (fn_invite_placement_sender); invite_enabled is
--     'false'; supplier_outreach_golive is 'true'; one overload of fn_invite_placement_gate (date, timestamptz).
--
-- WHAT THIS ADDS / CHANGES
--   1. public.invite_placement_bar: ONE row, the founder's bar as data. Microsoft inbox >= 80% (ledger 1312);
--      Google: inbox + Promotions is delivered, spam <= 20%, delivered >= 80% (100 - 20: a provider that LOST mail is
--      not cleared by a low spam figure); Yahoo/AOL inbox >= 80% (no bar of his; the Microsoft one, the conservative
--      reading); the verdict is good for 7 days; the sender is supplier@quotesdone.com.
--   2. public.deliverability_test (+ tested_at, recorded_by, recorded_at, source, class_rates, overall_*) and
--      public.deliverability_test_provider (+ provider_class): one GlockApps result, per provider and per class.
--   3. fn_record_inbox_placement_verdict(result jsonb, from text, recorded_by text): service_role only. Stores one
--      get_results answer as given: counts, never typed percentages, so every rate is computed from what was measured.
--   4. fn_mail_provider_class / fn_mail_provider_of_email: a recipient domain -> microsoft | google | yahoo_aol | other,
--      by its first (highest-priority) cached MX host, then by its domain. fn_glockapps_provider_class does the same
--      for a GlockApps provider group name.
--   5. fn_invite_placement_class_verdicts(now): side-effect free. Per class 'pass' | 'fail:no_verdict' |
--      'fail:stale_verdict' | 'fail:below_bar:<class>'; 'other' answers with the Microsoft verdict (an unidentified
--      corporate host follows the strictest bar); 'strict' is the first failing class, or 'pass' when all pass.
--   6. fn_invite_placement_gate(provider text, day, now): that class's answer. fn_invite_placement_gate(day, now), the
--      form every existing caller uses: the STRICT answer, so a caller that cannot filter per provider stays safe.
--      fn_invite_placement_open_providers(day, now): the classes that pass. All three file, on an OPEN day only
--      (fn_invite_placement_day_closed answers null), ONE it_engineer finding per day and verdict through the existing
--      relay fn_invite_placement_finding (deliverability:inbox_placement), exactly as #1696 does; on an open day that
--      passes they close it. A closed day or a paused campaign files and closes nothing.
--   7. enqueue_supplier_invites, fn_sales_engineer_supplier_outreach_tick and fn_sales_engineer_nudges_invited_suppliers
--      hold only when NO class passes; otherwise they invite / nudge only recipients of a passing class and SKIP the
--      others (counted, not failed). fn_supplier_invite_candidates(limit, providers) filters by class;
--      fn_supplier_invite_candidates(limit), used by the daily supplier list and the campaign list tick, is unchanged
--      in behaviour (it reads the two-argument form with no filter).
--
-- WHAT IT DOES NOT CHANGE
--   * invite_enabled, supplier_outreach_golive, wa_supplier_invite_golive: never written here. A passing verdict turns
--     nothing on; invite_enabled stays the founder's own switch. The only app_secrets write in this file is the bounce
--     brake's existing auto-PAUSE inside enqueue_supplier_invites, re-emitted byte for byte from production.
--   * #1696's trigger, fn_invite_placement_due (retired), founder_mail_policy, invite_placement_check: untouched.
--   * No mail is sent and no GlockApps credit is spent: recording reads a test that already ran.
--
-- APPLY ORDER: after no_test_mail_goes_to_the_founders_own_inboxes.sql (it defines fn_mailbox_fold, read here).
-- Prevented by: scripts/checks/the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.test.mjs, which
-- replays both pending files and ..._probe.sql in ONE aborted transaction.

-- ── 1. THE BAR, AS DATA ────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.invite_placement_bar (
  id                        boolean primary key default true check (id),
  sender                    text not null default 'supplier@quotesdone.com' check (sender like '%@%'),
  max_age                   interval not null default interval '7 days' check (max_age > interval '0'),
  microsoft_min_inbox_pct   numeric not null default 80 check (microsoft_min_inbox_pct between 0 and 100),
  google_max_spam_pct       numeric not null default 20 check (google_max_spam_pct between 0 and 100),
  google_min_delivered_pct  numeric not null default 80 check (google_min_delivered_pct between 0 and 100),
  yahoo_aol_min_inbox_pct   numeric not null default 80 check (yahoo_aol_min_inbox_pct between 0 and 100),
  note                      text not null,
  updated_at                timestamptz not null default now(),
  updated_by                text not null default 'it_engineer'
);
comment on table public.invite_placement_bar is
  'it_engineer: the ONE row holding the inbox-placement bar a GlockApps verdict must meet before supplier invitations go to a mailbox provider (ledger 1312; the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql).';
alter table public.invite_placement_bar enable row level security;
drop policy if exists invite_placement_bar_service_role_only on public.invite_placement_bar;
create policy invite_placement_bar_service_role_only on public.invite_placement_bar
  as permissive for all to public using (false) with check (false);
revoke all on public.invite_placement_bar from anon, authenticated;

insert into public.invite_placement_bar (id, note) values (true,
  'Microsoft >= 80% inbox: the founder, ledger 1312 (27 Oct 2026). Google: inbox + Promotions counts as delivered, spam '
  || '<= 20%, delivered >= 80% (100 - 20, so lost mail cannot pass). Yahoo/AOL: no bar of his; the Microsoft bar. '
  || 'Unidentified providers (other) follow the Microsoft verdict. A verdict is good for 7 days.')
on conflict (id) do nothing;

-- ── 2. THE VERDICT RECORD (shape of #1649, now owned here) ─────────────────────────────────────────────────────────
create table if not exists public.deliverability_test (
  test_id            text primary key check (test_id ~ '^[0-9A-Za-z:_-]{6,64}$'),
  project_id         text,
  provider           text not null default 'glockapps' check (provider = 'glockapps'),
  lane               text not null default 'm365' check (lane = 'm365'),
  from_address       text,
  reason             text not null,
  requested_by       text not null,
  created_at         timestamptz not null default now(),
  marker             text not null check (marker = 'id:' || test_id),
  seeds              jsonb not null default '[]'::jsonb,
  seeds_refused      jsonb not null default '[]'::jsonb,
  notification_ids   bigint[] not null default '{}',
  status             text not null default 'seeds_queued'
                     check (status in ('seeds_queued', 'collecting', 'complete', 'incomplete', 'failed')),
  polls              integer not null default 0,
  last_polled_at     timestamptz,
  last_error         text,
  stats              jsonb,
  filters            jsonb not null default '{}'::jsonb,
  outlook            jsonb,
  outlook_inbox_pct  numeric,
  verdict            text not null default 'pending' check (verdict in ('pending', 'pass', 'fail', 'incomplete')),
  decided_at         timestamptz,
  summary            text,
  reported_at        timestamptz,
  report_result      jsonb,
  check (verdict = 'pending' or decided_at is not null)
);
alter table public.deliverability_test add column if not exists tested_at timestamptz;
alter table public.deliverability_test add column if not exists recorded_by text;
alter table public.deliverability_test add column if not exists recorded_at timestamptz;
alter table public.deliverability_test add column if not exists source text;
alter table public.deliverability_test add column if not exists class_rates jsonb;
alter table public.deliverability_test add column if not exists overall_inbox_pct numeric;
alter table public.deliverability_test add column if not exists overall_tabs_pct numeric;
alter table public.deliverability_test add column if not exists overall_spam_pct numeric;
alter table public.deliverability_test add column if not exists overall_missing_pct numeric;
alter table public.deliverability_test drop constraint if exists deliverability_test_recorded_is_complete;
alter table public.deliverability_test add constraint deliverability_test_recorded_is_complete check (
  recorded_at is null
  or (tested_at is not null and recorded_by is not null and from_address like '%@%'
      and source in ('glockapps_connector', 'glockapps_api')
      and class_rates ?& array['microsoft', 'google', 'yahoo_aol', 'other', 'overall']));
create index if not exists deliverability_test_recorded_idx on public.deliverability_test (tested_at desc)
  where class_rates is not null;
comment on table public.deliverability_test is
  'it_engineer: one GlockApps inbox-placement test of the supplier invitation (supplier@ over the Microsoft 365 lane): who recorded it, when it was tested, per-class counts and rates (class_rates: microsoft, google, yahoo_aol, other, overall). fn_invite_placement_gate reads the latest. Owned by the_invitation_gate_reads_the_glockapps_verdict_per_mailbox_provider.sql (shape from #1649).';
alter table public.deliverability_test enable row level security;
drop policy if exists deliverability_test_service_role_only on public.deliverability_test;
create policy deliverability_test_service_role_only on public.deliverability_test
  as permissive for all to public using (false) with check (false);
revoke all on public.deliverability_test from anon, authenticated;

create table if not exists public.deliverability_test_provider (
  test_id            text not null references public.deliverability_test(test_id) on delete cascade,
  provider           text not null,
  provider_group_id  text,
  is_outlook         boolean not null default false,
  seeds              integer not null check (seeds >= 0),
  inbox              integer not null check (inbox >= 0),
  spam               integer not null check (spam >= 0),
  tabs               integer not null check (tabs >= 0),
  missing            integer not null check (missing >= 0),
  inbox_pct          numeric,
  raw_itypes         jsonb not null default '{}'::jsonb,
  updated_at         timestamptz not null default now(),
  primary key (test_id, provider),
  check (seeds = inbox + spam + tabs + missing)
);
alter table public.deliverability_test_provider add column if not exists provider_class text;
alter table public.deliverability_test_provider drop constraint if exists deliverability_test_provider_class_known;
alter table public.deliverability_test_provider add constraint deliverability_test_provider_class_known
  check (provider_class is null or provider_class in ('microsoft', 'google', 'yahoo_aol', 'other'));
comment on table public.deliverability_test_provider is
  'it_engineer: per GlockApps provider group of one test: seeds, inbox, spam, tabs (Promotions and other tabs), missing (not delivered), and the mailbox class it counts toward.';
alter table public.deliverability_test_provider enable row level security;
drop policy if exists deliverability_test_provider_service_role_only on public.deliverability_test_provider;
create policy deliverability_test_provider_service_role_only on public.deliverability_test_provider
  as permissive for all to public using (false) with check (false);
revoke all on public.deliverability_test_provider from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('deliverability_test', true, 'deliverability', 'Each GlockApps inbox-placement test of the supplier invitation, who recorded it, and its per-class rates (ledger 1312).', 'it_engineer'),
  ('deliverability_test_provider', true, 'deliverability', 'Per GlockApps provider group: inbox, spam, tabs and missing counts, and the mailbox class.', 'it_engineer'),
  ('invite_placement_bar', true, 'deliverability', 'The one-row bar a GlockApps verdict must meet per mailbox class before supplier invitations go (ledger 1312).', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── 3. WHICH MAILBOX PROVIDER ──────────────────────────────────────────────────────────────────────────────────────
-- A recipient: by its first cached MX host (mx_sweep stores them priority-sorted), else by its domain. A domain whose
-- first host is a filtering gateway (Trend Micro in front of Exchange Online, measured on adcustoms-gov-ae) is
-- 'other', and 'other' follows the Microsoft verdict: the conservative answer for a host we cannot name.
create or replace function public.fn_mail_provider_class(p_domain text, p_mx_hosts text[])
returns text language plpgsql immutable
set search_path to 'public', 'pg_temp'
as $fn$
declare d text := lower(btrim(coalesce(p_domain, ''))); h text := lower(rtrim(btrim(coalesce(p_mx_hosts[1], '')), '.'));
begin
  if h <> '' then
    if h ~ '(^|\.)(protection\.)?outlook\.com$' or h ~ '(^|\.)hotmail\.com$' then return 'microsoft'; end if;
    if h ~ '(^|\.)(google|googlemail)\.com$' then return 'google'; end if;
    if h ~ '(^|\.)yahoodns\.net$' or h ~ '(^|\.)(yahoo|aol)\.com$' then return 'yahoo_aol'; end if;
    return 'other';
  end if;
  if d ~ '^(outlook|hotmail|live|msn)\.[a-z.]+$' then return 'microsoft'; end if;
  if d in ('gmail.com', 'googlemail.com') then return 'google'; end if;
  if d ~ '^(yahoo|ymail|rocketmail|aol)\.[a-z.]+$' then return 'yahoo_aol'; end if;
  return 'other';
end $fn$;
revoke execute on function public.fn_mail_provider_class(text, text[]) from public, anon, authenticated;

create or replace function public.fn_mail_provider_of_email(p_email text)
returns text language sql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.fn_mail_provider_class(x.dom, (select m.hosts from public.email_domain_mx m where m.domain = x.dom and m.kind = 'mx'))
    from (select split_part(lower(btrim(coalesce(p_email, ''))), '@', 2) as dom) x;
$fn$;
revoke execute on function public.fn_mail_provider_of_email(text) from public, anon, authenticated;

-- A GlockApps provider group name, as get_results' providerRollup names it ("Outlook", "Hotmail", "Outlook.fr",
-- "Exchange (Office365)", "Gmail (6 months+)", "Google Workspace (4 years+)", "Yahoo", "AOL", ...).
create or replace function public.fn_glockapps_provider_class(p_name text)
returns text language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when lower(btrim(coalesce(p_name, ''))) ~ '^(outlook|hotmail|live|msn|exchange|office ?365|microsoft)' then 'microsoft'
    when lower(btrim(coalesce(p_name, ''))) ~ '^(gmail|google|g ?suite)' then 'google'
    when lower(btrim(coalesce(p_name, ''))) ~ '^(yahoo|aol)' then 'yahoo_aol'
    else 'other' end;
$fn$;
revoke execute on function public.fn_glockapps_provider_class(text) from public, anon, authenticated;

-- ── 4. ONE CLASS AGAINST THE BAR ───────────────────────────────────────────────────────────────────────────────────
-- Decided on COUNTS (inbox * 100 >= bar * seeds), never on a rounded rate, so 79.95% cannot round into a pass. A class
-- with no seed is not measured and does not pass.
create or replace function public.fn_invite_placement_rates_verdict(p_rates jsonb)
returns jsonb language plpgsql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare b public.invite_placement_bar; v jsonb := '{}'; c text; r jsonb; n numeric; ok boolean; first_fail text;
begin
  select * into b from public.invite_placement_bar where id;
  foreach c in array array['microsoft', 'google', 'yahoo_aol'] loop
    r := coalesce(p_rates -> c, '{}'::jsonb);
    n := coalesce((r ->> 'seeds')::numeric, 0);
    ok := b.id is not null and n > 0 and case c
      when 'microsoft' then (r ->> 'inbox')::numeric * 100 >= b.microsoft_min_inbox_pct * n
      when 'google'    then (r ->> 'spam')::numeric * 100 <= b.google_max_spam_pct * n
                        and ((r ->> 'inbox')::numeric + (r ->> 'tabs')::numeric) * 100 >= b.google_min_delivered_pct * n
      when 'yahoo_aol' then (r ->> 'inbox')::numeric * 100 >= b.yahoo_aol_min_inbox_pct * n end;
    v := v || jsonb_build_object(c, case when ok then 'pass' else 'fail:below_bar:' || c end);
    if not ok and first_fail is null then first_fail := 'fail:below_bar:' || c; end if;
  end loop;
  return v || jsonb_build_object('other', v ->> 'microsoft', 'strict', coalesce(first_fail, 'pass'));
end $fn$;
revoke execute on function public.fn_invite_placement_rates_verdict(jsonb) from public, anon, authenticated;

-- ── 5. RECORDING ONE GLOCKAPPS RESULT ──────────────────────────────────────────────────────────────────────────────
-- p_result is the connector's get_results answer with detail 'providers', as given (testId, created, finished, stats,
-- sender, providerRollup[{providerGroupId, providerGroupName, total, inbox, spam, other, notDelivered}]). p_from is
-- the mailbox that sent the seeds: GlockApps reports only the domain, so the domain must match it. Re-recording the same
-- test (later, when more providers reported) replaces its numbers. Writes only the two verdict tables.
create or replace function public.fn_record_inbox_placement_verdict(p_result jsonb, p_from text, p_recorded_by text)
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_test text := btrim(coalesce(p_result ->> 'testId', p_result ->> 'test_id', ''));
  v_tested timestamptz; v_from text := public.fn_mailbox_fold(p_from); v_dom text; v_rates jsonb := '{}'; v_verdict jsonb;
  e jsonb; c text; t record; v_sum jsonb; v_seed_rows int;
begin
  if v_test !~ '^[0-9A-Za-z:_-]{6,64}$' then
    raise exception 'fn_record_inbox_placement_verdict: testId % is not a GlockApps test id', v_test using errcode = 'check_violation'; end if;
  begin v_tested := (p_result ->> 'created')::timestamptz;
  exception when others then v_tested := null; end;
  if v_tested is null then
    raise exception 'fn_record_inbox_placement_verdict: created (when the test ran) is missing or unreadable' using errcode = 'check_violation'; end if;
  if v_from !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then
    raise exception 'fn_record_inbox_placement_verdict: from % is not a mailbox', p_from using errcode = 'check_violation'; end if;
  v_dom := lower(btrim(coalesce(p_result #>> '{sender,senderDomain}', '')));
  if v_dom <> '' and v_dom <> split_part(v_from, '@', 2) then
    raise exception 'fn_record_inbox_placement_verdict: GlockApps saw sender domain %, not the domain of %', v_dom, v_from
      using errcode = 'check_violation'; end if;
  if not exists (select 1 from public.org_role r where r.role_id = p_recorded_by and r.status = 'active') then
    raise exception 'fn_record_inbox_placement_verdict: % is not a live seat', p_recorded_by using errcode = 'check_violation'; end if;
  if jsonb_typeof(p_result -> 'providerRollup') is distinct from 'array' or jsonb_array_length(p_result -> 'providerRollup') = 0 then
    raise exception 'fn_record_inbox_placement_verdict: providerRollup is missing; call get_results with detail ''providers'''
      using errcode = 'check_violation'; end if;
  for e in select x from jsonb_array_elements(p_result -> 'providerRollup') x loop
    if coalesce(btrim(e ->> 'providerGroupName'), '') = ''
       or (e ->> 'total')::int is distinct from coalesce((e ->> 'inbox')::int, -1) + coalesce((e ->> 'spam')::int, -1)
                                               + coalesce((e ->> 'other')::int, -1) + coalesce((e ->> 'notDelivered')::int, -1) then
      raise exception 'fn_record_inbox_placement_verdict: provider % does not add up (total = inbox + spam + other + notDelivered)', e
        using errcode = 'check_violation'; end if;
  end loop;

  select count(*) into v_seed_rows from public.notifications n
   where n.kind = 'invite_m365_seed' and rtrim(n.body) like '%id:' || v_test;

  insert into public.deliverability_test as d (test_id, project_id, from_address, reason, requested_by, marker, status,
         stats, tested_at, recorded_by, recorded_at, source, verdict, decided_at)
  values (v_test, p_result ->> 'projectId', v_from, 'recorded from the GlockApps connector (get_results, detail providers)',
          p_recorded_by, 'id:' || v_test,
          case when coalesce((p_result ->> 'finished')::boolean, false) then 'complete' else 'incomplete' end,
          coalesce(p_result -> 'stats', '{}'::jsonb) || jsonb_build_object('finished', p_result -> 'finished',
            'trackedSeeds', p_result -> 'trackedSeeds', 'authSummary', p_result -> 'authSummary', 'sender', p_result -> 'sender',
            'seed_notifications', v_seed_rows),
          v_tested, p_recorded_by, null, 'glockapps_connector', 'pending', null)
  on conflict (test_id) do update set project_id = excluded.project_id, from_address = excluded.from_address,
         status = excluded.status, stats = excluded.stats, tested_at = excluded.tested_at, recorded_by = excluded.recorded_by,
         recorded_at = null, source = excluded.source;

  delete from public.deliverability_test_provider where test_id = v_test;
  insert into public.deliverability_test_provider (test_id, provider, provider_group_id, is_outlook, seeds, inbox, spam,
         tabs, missing, inbox_pct, raw_itypes, provider_class)
  select v_test, g.name, min(g.gid), public.fn_glockapps_provider_class(g.name) = 'microsoft',
         sum(g.total), sum(g.inbox), sum(g.spam), sum(g.tabs), sum(g.missing),
         round(100.0 * sum(g.inbox) / nullif(sum(g.total), 0), 1),
         jsonb_build_object('tabs', jsonb_agg(g.tablist) filter (where g.tablist is not null)),
         public.fn_glockapps_provider_class(g.name)
    from (select btrim(x ->> 'providerGroupName') name, x ->> 'providerGroupId' gid, (x ->> 'total')::int total,
                 (x ->> 'inbox')::int inbox, (x ->> 'spam')::int spam, (x ->> 'other')::int tabs,
                 (x ->> 'notDelivered')::int missing, x -> 'tabs' tablist
            from jsonb_array_elements(p_result -> 'providerRollup') x) g
   group by g.name;

  -- THE OVERALL FIGURE IS GLOCKAPPS' OWN (stats), when it gives one. Measured on test 2026-10-27-09:33:53:634t: stats
  -- covers 111 tracked seeds (44 inbox, 21 tabs, 41 spam, 5 missing) while the providerRollup rows add up to 106 (41, 21,
  -- 39, 5): GlockApps leaves 5 seeds out of its provider breakdown. Those 5 cannot be put in a class, so the classes are
  -- judged on the rollup and 'overall' carries 'unclassified' = stats total - rollup total, said rather than hidden.
  for c in select unnest(array['microsoft', 'google', 'yahoo_aol', 'other', 'overall']) loop
    if c = 'overall' and (p_result #>> '{stats,inbox}') ~ '^\d+$' and (p_result #>> '{stats,other}') ~ '^\d+$'
       and (p_result #>> '{stats,spam}') ~ '^\d+$' and (p_result #>> '{stats,notDelivered}') ~ '^\d+$' then
      select (p_result #>> '{stats,inbox}')::bigint + (p_result #>> '{stats,other}')::bigint + (p_result #>> '{stats,spam}')::bigint
               + (p_result #>> '{stats,notDelivered}')::bigint s,
             (p_result #>> '{stats,inbox}')::bigint i, (p_result #>> '{stats,other}')::bigint tb,
             (p_result #>> '{stats,spam}')::bigint sp, (p_result #>> '{stats,notDelivered}')::bigint m into t;
    else
      select coalesce(sum(p.seeds), 0) s, coalesce(sum(p.inbox), 0) i, coalesce(sum(p.tabs), 0) tb,
             coalesce(sum(p.spam), 0) sp, coalesce(sum(p.missing), 0) m into t
        from public.deliverability_test_provider p
       where p.test_id = v_test and (c = 'overall' or p.provider_class = c);
    end if;
    v_rates := v_rates || jsonb_build_object(c, jsonb_build_object('seeds', t.s, 'inbox', t.i, 'tabs', t.tb, 'spam', t.sp,
      'missing', t.m,
      'inbox_pct', round(100.0 * t.i / nullif(t.s, 0), 1), 'tabs_pct', round(100.0 * t.tb / nullif(t.s, 0), 1),
      'spam_pct', round(100.0 * t.sp / nullif(t.s, 0), 1), 'missing_pct', round(100.0 * t.m / nullif(t.s, 0), 1),
      'delivered_pct', round(100.0 * (t.i + t.tb) / nullif(t.s, 0), 1)));
  end loop;
  v_rates := jsonb_set(v_rates, '{overall,unclassified}', to_jsonb((v_rates #>> '{overall,seeds}')::int
               - (select coalesce(sum(p.seeds), 0)::int from public.deliverability_test_provider p where p.test_id = v_test)));
  v_verdict := public.fn_invite_placement_rates_verdict(v_rates);
  v_sum := v_rates -> 'overall';

  update public.deliverability_test set
         class_rates = v_rates, outlook = v_rates -> 'microsoft',
         outlook_inbox_pct = (v_rates #>> '{microsoft,inbox_pct}')::numeric,
         overall_inbox_pct = (v_sum ->> 'inbox_pct')::numeric, overall_tabs_pct = (v_sum ->> 'tabs_pct')::numeric,
         overall_spam_pct = (v_sum ->> 'spam_pct')::numeric, overall_missing_pct = (v_sum ->> 'missing_pct')::numeric,
         verdict = case when v_verdict ->> 'strict' = 'pass' then 'pass' else 'fail' end, decided_at = now(),
         recorded_at = now(),
         summary = format('GlockApps %s from %s, tested %s: Microsoft %s/%s inbox (%s%%), Google %s inbox + %s tabs of %s (spam %s%%), '
                          || 'Yahoo/AOL %s/%s inbox (spam %s%%), overall %s/%s inbox (%s%%). Against the bar: %s.',
                          v_test, v_from, to_char(v_tested at time zone 'UTC', 'YYYY-MM-DD HH24:MI"Z"'),
                          v_rates #>> '{microsoft,inbox}', v_rates #>> '{microsoft,seeds}', coalesce(v_rates #>> '{microsoft,inbox_pct}', '-'),
                          v_rates #>> '{google,inbox}', v_rates #>> '{google,tabs}', v_rates #>> '{google,seeds}',
                          coalesce(v_rates #>> '{google,spam_pct}', '-'),
                          v_rates #>> '{yahoo_aol,inbox}', v_rates #>> '{yahoo_aol,seeds}', coalesce(v_rates #>> '{yahoo_aol,spam_pct}', '-'),
                          v_sum ->> 'inbox', v_sum ->> 'seeds', coalesce(v_sum ->> 'inbox_pct', '-'), v_verdict::text)
   where test_id = v_test;

  return jsonb_build_object('recorded', true, 'test_id', v_test, 'from', v_from, 'tested_at', v_tested,
    'recorded_by', p_recorded_by, 'seed_notifications', v_seed_rows, 'class_rates', v_rates,
    'against_the_bar', v_verdict, 'gate_now', public.fn_invite_placement_class_verdicts(now()));
end $fn$;

-- ── 6. THE VERDICT, PER CLASS, AT A MOMENT (no side effects) ───────────────────────────────────────────────────────
-- The latest recorded verdict for the bar's sender, tested at or before p_now. If the sender that would send today is
-- not that sender, there is no verdict for it.
create or replace function public.fn_invite_placement_class_verdicts(p_now timestamp with time zone default now())
returns jsonb language plpgsql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare b public.invite_placement_bar; t public.deliverability_test; v text; v_sender text;
begin
  select * into b from public.invite_placement_bar where id;
  v_sender := public.fn_mailbox_fold(public.fn_invite_placement_sender());
  if b.id is not null then
    select * into t from public.deliverability_test d
     where d.class_rates is not null and d.recorded_at is not null and d.tested_at <= p_now
       and public.fn_mailbox_fold(d.from_address) = public.fn_mailbox_fold(b.sender)
     order by d.tested_at desc, d.recorded_at desc limit 1;
  end if;
  if b.id is null or t.test_id is null or v_sender is distinct from public.fn_mailbox_fold(b.sender) then
    v := 'fail:no_verdict';
  elsif t.tested_at < p_now - b.max_age then
    v := 'fail:stale_verdict';
  end if;
  return case when v is not null
    then jsonb_build_object('microsoft', v, 'google', v, 'yahoo_aol', v, 'other', v, 'strict', v)
    else public.fn_invite_placement_rates_verdict(t.class_rates) end
    || jsonb_build_object('test_id', t.test_id, 'tested_at', t.tested_at, 'bar_sender', b.sender, 'effective_sender', v_sender,
                          'max_age', b.max_age, 'checked_at', p_now);
end $fn$;
revoke execute on function public.fn_invite_placement_class_verdicts(timestamp with time zone) from public, anon, authenticated;
revoke execute on function public.fn_record_inbox_placement_verdict(jsonb, text, text) from public, anon, authenticated;
grant execute on function public.fn_record_inbox_placement_verdict(jsonb, text, text) to service_role;

-- ── 7. THE GATE ────────────────────────────────────────────────────────────────────────────────────────────────────
-- The judge: the verdicts, and on an OPEN day the one finding (or its close). Every gate form goes through it, so the
-- finding carries the same strict verdict whichever form asked, and the relay's per-day-and-verdict dedupe keeps it
-- to one per day.
create or replace function public.fn_invite_placement_judge(p_day date default null::date, p_now timestamp with time zone default now())
returns jsonb language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := coalesce(p_day, (p_now at time zone 'Asia/Dubai')::date);
  v jsonb := public.fn_invite_placement_class_verdicts(p_now);
  v_open text[];
begin
  select coalesce(array_agg(c order by c), '{}') into v_open
    from unnest(array['google', 'microsoft', 'other', 'yahoo_aol']) c where v ->> c = 'pass';
  if public.fn_invite_placement_day_closed(p_now) is null then
    if v ->> 'strict' <> 'pass' then
      perform public.fn_invite_placement_finding(v_day, substr(v ->> 'strict', 6),
        'the GlockApps verdict answered ' || (v ->> 'strict') || ' on ' || v_day
        || case when cardinality(v_open) = 0 then '; no mailbox provider is invited'
                else '; invited only: ' || array_to_string(v_open, ', ') end,
        jsonb_build_object('checked_at', p_now, 'verdicts', v, 'open_providers', to_jsonb(v_open),
          'remedy', 'record a fresh GlockApps result with scripts/record_inbox_placement_verdict.mjs once a test of supplier@ meets public.invite_placement_bar'));
    elsif exists (select 1 from public.it_engineer_finding where issue_key = 'deliverability:inbox_placement' and closed_at is null) then
      perform public.fn_it_engineer_finding_close('deliverability:inbox_placement',
        'closed by fn_invite_placement_judge: GlockApps test ' || coalesce(v ->> 'test_id', '?') || ' meets the bar for every mailbox class');
    end if;
  end if;
  return v || jsonb_build_object('open_providers', to_jsonb(v_open), 'dubai_day', v_day);
end $fn$;
revoke execute on function public.fn_invite_placement_judge(date, timestamp with time zone) from public, anon, authenticated;

-- The form every existing caller uses: the STRICT answer (pass only when every class passes). CREATE OR REPLACE keeps
-- its ACL (service_role only, measured).
create or replace function public.fn_invite_placement_gate(p_day date default null::date, p_now timestamp with time zone default now())
returns text language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return public.fn_invite_placement_judge(p_day, p_now) ->> 'strict';
end $fn$;

-- One recipient class: 'microsoft' | 'google' | 'yahoo_aol' | 'other'. Anything else, or null, is 'other'.
create or replace function public.fn_invite_placement_gate(p_provider text, p_day date default null::date, p_now timestamp with time zone default now())
returns text language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_c text := case when lower(btrim(coalesce(p_provider, ''))) in ('microsoft', 'google', 'yahoo_aol')
                         then lower(btrim(p_provider)) else 'other' end;
begin
  return public.fn_invite_placement_judge(p_day, p_now) ->> v_c;
end $fn$;
revoke execute on function public.fn_invite_placement_gate(text, date, timestamp with time zone) from public, anon, authenticated;

create or replace function public.fn_invite_placement_open_providers(p_day date default null::date, p_now timestamp with time zone default now())
returns text[] language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return array(select jsonb_array_elements_text(public.fn_invite_placement_judge(p_day, p_now) -> 'open_providers'));
end $fn$;
revoke execute on function public.fn_invite_placement_open_providers(date, timestamp with time zone) from public, anon, authenticated;

-- ── 8. THE CALLERS SKIP A FAILING PROVIDER INSTEAD OF HOLDING EVERY ONE ────────────────────────────────────────────
-- Each body below is production's (pg_get_functiondef, read 27 Oct 2026 23:3xZ) with only the placement-gate lines
-- changed; everything else is byte for byte, the bounce brake's auto-pause included.
CREATE OR REPLACE FUNCTION public.fn_supplier_invite_candidates(p_limit integer, p_providers text[])
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text; v_target int;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  -- 27 Oct 2026: the founder's invitation carries no link ("safer to not send links"); a supplier registers at
  -- quotesdone.com or replies. Only an EMPTY template is refused now. A template that still has {{link}} is filled.
  if btrim(coalesce(v_body, '')) = '' then
    raise exception 'app_secrets.invite_body is empty: no invitation is built from nothing';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  -- ONE COMPANY, ONE INVITATION (24 Sep 2026, marketing). A company is its email domain, unless the domain is
  -- a shared mailbox provider (gmail, emirates.net.ae ...: measured as a domain carrying 3+ different company
  -- names), where it is the address itself; and, independently, its normalised company name.
  shared as materialized (
    select split_part(lower(btrim(l.email)), '@', 2) as dom from leads l where coalesce(btrim(l.email), '') <> ''
    group by 1 having count(distinct lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g'))) >= 3
  ),
  keyed as materialized (
    select l.id,
           case when s.dom is null then split_part(lower(btrim(l.email)), '@', 2) else lower(btrim(l.email)) end as dkey,
           nullif(lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g')), '') as nkey,
           (l.invite_status is not null or l.invited_at is not null or coalesce(l.claimed, false)) as touched
    from leads l left join shared s on s.dom = split_part(lower(btrim(l.email)), '@', 2)
    where coalesce(btrim(l.email), '') <> ''
  ),
  touched_d as materialized (select distinct dkey from keyed where touched),
  touched_n as materialized (select distinct nkey from keyed where touched and nkey is not null),
  -- instr 1013: marketing's ranking of the trades below ten suppliers (the ranking orders the queue; since 27 Oct 2026
  -- every row stores the one approved text, not a per-trade variant)
  plans as materialized (select p.trade, p.emirate, p.rank from public.marketing_gap_recruitment_plan p),
  -- 29 Sep 2026 (ledger 1018): the trades and areas of the open, real stalled-request rescues (public.stalled_inquiry_rescue).
  -- A fixture rescue never moves the real queue.
  rescue as materialized (select x.trades, x.emirate from public.stalled_inquiry_rescue x where x.cleared_at is null and not x.fixture and cardinality(x.trades) > 0),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey,
           -- ALWAYS ENGLISH (24 Sep 2026, ledger 993 item 4; #1065): suppliers are always written in English.
           'en'::text as lang
    from leads l join keyed k on k.id = l.id
    where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))   -- the set, read once (see header)
      -- 27 Oct 2026 (it_engineer): only recipients whose mailbox class passed the GlockApps verdict; null = every class
      and (p_providers is null or public.fn_mail_provider_of_email(l.email) = any(p_providers))
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 29 Sep 2026 (ledger 1018): ahead of every tier below, a lead in the trade and area of a stalled request a customer waits on.
      -- 23 Sep 2026: a lead in a trade the sales engineer marked for recruitment (supply_gap 'recruit') goes first;
      -- 29 Sep 2026 (instr 1013): then a lead in any trade marketing planned, by the plan's rank.
      case when exists (select 1 from rescue x where x.trades && coalesce(c.invite_trades, '{}'::text[])
                          and (x.emirate is null or x.emirate = 'UAE' or x.emirate = c.emirate)) then -1
           when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0
           when pl.rank is not null then 1 else 2 end as target_rank,
      coalesce(pl.rank, 2147483647) as plan_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
    left join lateral (select p.rank from plans p
                        where p.trade = any(coalesce(c.invite_trades, '{}'::text[])) and (p.emirate = 'UAE' or p.emirate = c.emirate)
                        order by p.rank limit 1) pl on true
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.unverified_rank, p.role_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.unverified_rank, p.role_rank, p.id) as domain_rk,
        -- the best contact per company: a verified, named mailbox before info@/sales@ (a role address goes only
        -- when it is the company's only one). ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.unverified_rank, p.role_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.unverified_rank, p.role_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.plan_rank, r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang, v_subj,
         -- an Arabic-script company name is not written into an English letter (the 29 Sep probe found 11 of 200);
         -- with no usable name the greeting is the neutral "Hello," the Microsoft 365 lane also sends
         -- (a template that still carries {{link}} is filled as before; the approved one has none)
         replace(replace(case when n.nm = '' then replace(v_body, 'Hi {{company}} team,', 'Hello,') else v_body end,
                         '{{company}}', case when n.nm = '' then 'there' else n.nm end),
                 '{{link}}', public.fn_supplier_invite_link(v_site, e.claim_token, e.id))
  from elig e
  cross join lateral (select coalesce(nullif(btrim(case when e.company_name ~ '[؀-ۿ]' then '' else e.company_name end), ''), '') as nm) n;
end
$function$;

revoke execute on function public.fn_supplier_invite_candidates(integer, text[]) from public, anon, authenticated;

-- The one-argument form keeps its callers (fn_supplier_campaign_next_list, fn_customer_support_campaign_list_tick):
-- the same rows as before, every class. CREATE OR REPLACE keeps its ACL.
create or replace function public.fn_supplier_invite_candidates(p_limit integer)
 returns table(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 language plpgsql stable security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  return query select * from public.fn_supplier_invite_candidates(p_limit, null::text[]);
end $fn$;

CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
  v_cfg jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_win_start timestamptz; v_win_end timestamptz;
  v_gate text; v_open text[];
begin
  select c.event_name, c.action, c.ends_on into v_hol_name, v_hol_action, v_hol_end
    from public.company_calendar c
   where c.kind = 'public_holiday'
     and v_today between c.starts_on and coalesce(c.ends_on, c.starts_on)
   order by c.starts_on limit 1;
  if v_hol_name is not null then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'calendar_paused', true, 'resumes_on', coalesce(v_hol_end, v_today) + 1),
            'Invites held: company_calendar has "' || v_hol_name || '" covering today. Its recorded action: '
            || coalesce(v_hol_action, '(none recorded)'), now(), now());
    return 0;
  end if;

  -- THE UAE WEEKEND IS SATURDAY AND SUNDAY. A cold invitation queued then waits under Monday's pile.
  -- Self-clearing like the holiday hold: nothing is switched off, Monday simply runs.
  if extract(isodow from (now() at time zone 'Asia/Dubai')) in (6, 7) then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'weekend_hold', true),
            'Invites held: it is the UAE weekend in Dubai; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_go  := (coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true')
           and public.fn_supplier_outreach_golive();
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  -- founder ruling 1231: never more than the dated founder cap, whatever invite_daily_cap holds.
  v_cap := least(v_cap, public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
  select count(*) into v_pool from leads l where public.fn_supplier_invite_eligible(l);
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' eligible never-invited lead(s), cap ' || v_cap
          || case when v_go then '; sending open'
                  when not public.fn_supplier_outreach_golive() then '; HELD — real invitations wait for the founder''s go (app_secrets.supplier_outreach_golive is false)'
                  else '; HELD — real invitations wait for the founder''s go (app_secrets.invite_enabled)' end)
    on conflict (day) do update
      set planned = excluded.planned, status = excluded.status, note = excluded.note;

  if not v_go then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'planned', greatest(v_planned, 0), 'pool', v_pool, 'cap', v_cap, 'held', true),
            'Invites planned and HELD: ' || greatest(v_planned, 0) || ' of a pool of ' || v_pool
            || ' would be queued at cap ' || v_cap || '; '
            || case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive' else 'invite_enabled' end
            || ' is false, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_planned <= 0 then return 0; end if;

  -- PLACEMENT GATE, PER MAILBOX CLASS (27 Oct 2026, it_engineer; was the morning seed, retired by #1696). Recipients
  -- go only in a class whose latest GlockApps verdict meets public.invite_placement_bar (fn_invite_placement_open_providers);
  -- the others are skipped, not failed. No class open, no verdict, or a stale one: the whole batch is held.
  v_open := public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date);
  v_gate := public.fn_invite_placement_class_verdicts(now()) ->> 'strict';
  if cardinality(v_open) = 0 then
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; held: inbox placement ' || v_gate where day = v_today;
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'placement_gate', v_gate, 'held', true),
            'Invites held: the GlockApps inbox placement verdict answered ' || v_gate || ' for every mailbox class, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_gate <> 'pass' then
    update invite_schedule set note = coalesce(note,'') || '; placement ' || v_gate || ': invited only ' || array_to_string(v_open, ', ') where day = v_today;
  end if;

  -- THE SENDING WINDOW (22 Sep 2026). Invitations leave between the later of now and the window's start
  -- and the end of the Dubai working day, evenly spaced. Past the window nothing is queued: a cold
  -- invitation at night lands under the morning's pile, and tomorrow's batch runs as normal.
  v_win_start := greatest(now(), ((now() at time zone 'Asia/Dubai')::date
                   + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9))) at time zone 'Asia/Dubai');
  v_win_end := ((now() at time zone 'Asia/Dubai')::date + make_interval(hours => coalesce((v_cfg->>'window_end_hour')::int, 17)))
               at time zone 'Asia/Dubai';
  if v_win_end < v_win_start + interval '30 minutes' then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'outside_window', true),
            'Invites held: the Dubai sending window closes at ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI')
            || '; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  if not v_pause and v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days against '||v_inv_recent||' sent. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  -- test-path rows (fixture addresses) are not invitations and must not spend the day's cap:
  -- measured in the rolled-back rehearsal, two test sends plus one real row cut a batch of 5 to 2.
  -- ONE daily cap for invitations and their nudges (review of #1007, 29 Sep 2026): a nudge queued today spends it too,
  -- as fn_sales_engineer_nudges_invited_suppliers already counts the invitations queued today against the same cap.
  select count(*) into v_used from notifications where type in ('supplier_invite', 'supplier_invite_nudge') and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  with c as (
    select c.*, row_number() over () as rn, count(*) over () as n
      from public.fn_supplier_invite_candidates(v_remaining, v_open) c
  ), ins as (
    insert into notifications(type, to_email, to_role, lead_id, subject, body, lang, status, created_at, not_before)
    select 'supplier_invite', c.to_email, 'supplier', c.lead_id, c.subject, c.body, c.lang, 'queued', now(),
           v_win_start + (c.rn - 1) * ((v_win_end - v_win_start) / greatest(c.n, 1))
      from c
    on conflict (lower(btrim(to_email))) where type = 'supplier_invite' do nothing
    returning lead_id
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and id in (select lead_id from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false,
                             'window_ends', v_win_end, 'placement_gate', v_gate, 'open_providers', to_jsonb(v_open)),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap
          || '), spread until ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI') || ' Dubai.', now(), now());
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_nudges_invited_suppliers(p_now timestamp with time zone DEFAULT now(), p_cap integer DEFAULT NULL::integer, p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_dxb timestamp := p_now at time zone 'Asia/Dubai';
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_hol text; v_cap int; v_used int; v_left int; v_queued int := 0; v_due int := 0; r record; v_link text;
  v_res jsonb; v_not_before timestamptz;
  v_gate text; v_open text[]; v_skipped int := 0; v_inv_recent int; v_bounced_recent int; v_max_rate numeric;
begin
  select c.event_name into v_hol from public.company_calendar c
   where c.kind = 'public_holiday' and v_dxb::date between c.starts_on and coalesce(c.ends_on, c.starts_on) limit 1;
  if v_hol is not null then return jsonb_build_object('held', 'holiday: ' || v_hol, 'queued', 0); end if;
  if extract(isodow from v_dxb) in (6, 7) then return jsonb_build_object('held', 'UAE weekend', 'queued', 0); end if;
  -- THE SENDING WINDOW (review of #1007, 29 Sep 2026). The duty that calls this runs at 00:01 UTC (04:01 Dubai),
  -- before the window opens, so a start-hour HOLD would block every nudge. Instead a nudge queued before the
  -- window leaves no earlier than window_start_hour (default 9) Dubai the same day: not_before, exactly as
  -- enqueue_supplier_invites spreads its batch from the window's start. After window_end_hour it is held.
  v_not_before := greatest(p_now, (v_dxb::date + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9)))
                                  at time zone 'Asia/Dubai');
  if extract(hour from v_dxb) >= coalesce((v_cfg->>'window_end_hour')::int, 17) then
    return jsonb_build_object('held', 'after the Dubai sending window', 'queued', 0); end if;
  -- THE GO SWITCH governs every mode, the probe's fixture mode included (30 Sep 2026).
  if not (coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive()) then
    return jsonb_build_object('held', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)', 'queued', 0,
                              'due', (select count(*) from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures)));
  end if;
  -- THE BATCH'S BRAKES, for real mail (a fixture address never leaves: send_outbox suppresses @example.invalid).
  if not p_include_fixtures then
    -- per mailbox class (27 Oct 2026): held only when no class passes; a failing class is skipped in the loop
    v_open := public.fn_invite_placement_open_providers(v_dxb::date, p_now);
    v_gate := public.fn_invite_placement_class_verdicts(p_now) ->> 'strict';
    if cardinality(v_open) = 0 then
      return jsonb_build_object('held', 'inbox placement ' || v_gate, 'queued', 0); end if;
    -- enqueue_supplier_invites' 3-day bounce brake, read only (the batch owns the auto-pause)
    select count(*), count(*) filter (where invite_status = 'bounced') into v_inv_recent, v_bounced_recent
      from public.leads where invited_at > p_now - interval '3 days';
    v_max_rate := coalesce((select nullif(value, '')::numeric from public.app_secrets where key = 'invite_max_bounce_rate'), 0.08);
    if (v_inv_recent >= 15 and v_bounced_recent::numeric / greatest(v_inv_recent, 1) > v_max_rate)
       or v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
      return jsonb_build_object('held', 'bounce brake: ' || v_bounced_recent || ' of ' || v_inv_recent || ' in 3 days', 'queued', 0); end if;
  end if;

  -- ONE daily cap for the domain: invitations and nudges queued this day, same class (real or fixture). The day is
  -- the UTC date, exactly as enqueue_supplier_invites counts it (review of #1007): on a Dubai-date basis the two
  -- would disagree between 00:00 and 04:00 Dubai and could each spend a full cap.
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  v_cap := least(v_cap, coalesce(p_cap, v_cap));
  select count(*) into v_used from public.notifications n
   where n.type in ('supplier_invite', 'supplier_invite_nudge')
     and (n.created_at at time zone 'UTC')::date = (p_now at time zone 'UTC')::date
     and public.fn_is_demo_email(n.to_email) = p_include_fixtures;
  v_left := greatest(0, v_cap - v_used);

  for r in select d.*, l.company_name, l.claim_token from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures) d
             join public.leads l on l.id = d.lead_id loop
    v_due := v_due + 1;
    -- a recipient whose mailbox class did not pass the GlockApps verdict is skipped, not failed (27 Oct 2026)
    if not p_include_fixtures and public.fn_mail_provider_of_email(r.to_email) <> all(v_open) then
      v_skipped := v_skipped + 1; continue; end if;
    continue when v_queued >= v_left;
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English): one copy, and the link is
    -- the invitation's own: fn_supplier_invite_link (#1051) - /en/portal with the claim token and the invitation ref.
    -- A lead with no claim token (the function then answers null) gets the plain English portal.
    v_link := coalesce(public.fn_supplier_invite_link(
                         (select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), r.claim_token, r.lead_id),
                       coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
                       || '/en/portal');
    v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_invite_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en', 'dedupe_key', r.dedupe_key,
      'subject', case when r.step = 3 then 'A last reminder: ' else '' end || 'your invitation to join QuotesDone as a supplier',
      -- #1070's greeting guard: an Arabic-script company name is not written into an English letter
      'body', coalesce('Dear ' || nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), '') || ',',
                       'Dear Sir or Madam,') || E'\n\n'
          || 'A reminder of our invitation to register your company as a supplier on QuotesDone. It is free and takes a few minutes.'
          || E'\n\n' || v_link
          || case when r.step = 3 then E'\n\nThis is the last reminder we will send about it.' else '' end
          || E'\n\nIf you would rather not receive these e-mails, reply to this one and we will remove your address.')));
    -- support's handler queues the row without a not_before (it takes only the words and the address), so the
    -- requester sets the window start on the row it was just given back (by id, whatever the outbox's status:
    -- a fixture address is 'suppressed' on insert, a real one 'queued')
    update public.notifications set not_before = v_not_before
     where id = (v_res->0->>'notification_id')::bigint and type = 'supplier_invite_nudge';
    v_queued := v_queued + 1;
  end loop;
  return jsonb_build_object('held', null, 'due', v_due, 'queued', v_queued, 'cap', v_cap, 'used_before', v_used,
                            'placement_gate', v_gate, 'open_providers', to_jsonb(v_open), 'skipped_provider', v_skipped);
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_outreach_tick(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
  v_go boolean; v_weekend boolean; v_invited int; r record; s jsonb; v_cap int;
  v_due int := 0; v_sent int := 0; v_failed jsonb := '[]'::jsonb; v_clock jsonb; v_out jsonb; v_why text;
  v_gate text; v_daily_done boolean; v_batch_done boolean; v_batch_why text; v_batch_wait boolean := false;
begin
  select exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date),
         exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer'
                    and ((a.counts->>'job' = 'supplier_outreach' and coalesce(a.counts->>'batch_waiting', 'false') <> 'true')
                         or a.counts->>'job' = 'supplier_outreach_batch')
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date)
    into v_daily_done, v_batch_done;
  if not p_force then
    if extract(hour from v_now_dxb) < 9 then return jsonb_build_object('due', false, 'reason', 'before 09:00 Dubai'); end if;
    if v_daily_done and v_batch_done then
      return jsonb_build_object('due', false, 'reason', 'already ran this Dubai day');
    end if;
  end if;

  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  v_weekend := extract(isodow from v_now_dxb) in (6, 7);
  v_why := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                when not v_go then 'invite_enabled is false'
                when v_weekend then 'it is the UAE weekend' end;

  -- 1. THE BATCH, behind the PLACEMENT GATE (24 Sep 2026, it_engineer). On an open day it goes only after that
  --    morning's seed landed in the Inbox of both seed mailboxes; while the check can still finish it waits (the
  --    next beat asks again); any other answer holds it (fail closed). enqueue_supplier_invites asks the same gate.
  if p_force or not v_batch_done then
    v_batch_why := v_why;
    if v_why is null then
      -- 27 Oct 2026: the GlockApps verdict, per mailbox class. The batch is held only when no class passes;
      -- enqueue_supplier_invites invites the passing classes and skips the rest. It never answers 'wait'.
      if cardinality(public.fn_invite_placement_open_providers(v_now_dxb::date)) = 0 then
        v_batch_why := 'the GlockApps inbox placement verdict cleared no mailbox class ('
                       || (public.fn_invite_placement_class_verdicts(now()) ->> 'strict') || ')';
      end if;
      v_gate := public.fn_invite_placement_class_verdicts(now()) ->> 'strict';
    end if;
    if not v_batch_wait then
      -- THE WARM-UP (22 Sep 2026). fn_invite_ramp sets today's invite_daily_cap from the last 48 h of bounces and
      -- complaints. Open days only: a held day sends nothing, so it must not move the cap.
      if v_batch_why is null then v_cap := public.fn_invite_ramp(); end if;
      -- enqueue_supplier_invites holds itself (gates, weekend, holiday, bounce brake, cap, placement).
      v_invited := public.enqueue_supplier_invites(null);
    end if;
  end if;

  -- A later beat of the same day: the daily work is done, only the batch was owed.
  if v_daily_done and not p_force then
    if v_batch_wait then
      return jsonb_build_object('due', false, 'reason', 'the batch waits for the morning inbox placement check');
    end if;
    v_out := jsonb_build_object('job', 'supplier_outreach_batch', 'dubai_day', v_now_dxb::date, 'held', v_batch_why is not null,
      'held_because', v_batch_why, 'placement_gate', v_gate, 'invites', jsonb_build_object('queued', v_invited, 'cap', v_cap));
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('sales_engineer', 'ok', now(), now(), v_out,
            case when v_batch_why is not null
                 then 'Supplier invitation batch HELD (' || v_batch_why || '): ' || coalesce(v_invited, 0) || ' queued.'
                 else 'Supplier invitation batch: ' || coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') || '.' end);
    return v_out;
  end if;

  -- 2. Reminders: always counted; written only on an open weekday (the campaign gates, not the placement gate).
  for r in select * from public.fn_supplier_registration_reminders_due() loop
    v_due := v_due + 1;
    if v_why is not null then continue; end if;
    s := public.fn_sales_engineer_sends_registration_reminder(r.lead_id, r.stage, r.step, r.last_activity);
    if coalesce((s->>'ok')::boolean, false) then v_sent := v_sent + 1;
    else v_failed := v_failed || jsonb_build_array(jsonb_build_object('lead_id', r.lead_id, 'reason', s->>'reason'));
    end if;
  end loop;

  -- 3. The 24-hour clock: internal, so not held by the campaign gates.
  v_clock := public.fn_sales_engineer_raises_undecided_submissions(false);

  v_out := jsonb_build_object('job', 'supplier_outreach', 'dubai_day', v_now_dxb::date, 'held', v_why is not null, 'held_because', v_why,
    'placement_gate', v_gate, 'batch_waiting', v_batch_wait, 'batch_held_because', v_batch_why,
    'invites', jsonb_build_object('queued', coalesce(v_invited, 0), 'cap', v_cap),
    'reminders', jsonb_build_object('due', v_due, 'sent', v_sent, 'failed', v_failed),
    'submissions', v_clock);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', case when jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end, now(), now(), v_out,
          case when v_why is not null
               then 'Supplier outreach HELD (' || v_why || '): ' || coalesce(v_invited, 0) || ' invitation(s) queued, ' || v_due
                    || ' reminder(s) due and none written; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: '
                    || case when v_batch_wait then 'the invitation batch waits for the morning inbox placement check'
                            when v_batch_why is not null then 'the invitation batch was HELD (' || v_batch_why || ')'
                            else coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') end
                    || ', ' || v_sent || ' of ' || v_due
                    || ' reminder(s) sent; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.' end);
  return v_out;
end
$function$;
