-- The it_engineer runs the GlockApps test and files its verdict without the founder (27 Oct 2026).
-- Assigned: it_engineer
--
-- FOUNDER, 27 Oct 2026 (ledger 1312): "Run the GlockApps check of the new supplier invitation, sent from
-- supplier@quotesdone.com, and report inbox, spam and promotions for each email provider. Keep the batch held, so the
-- invitations stay paused, unless Outlook is at least 80% inbox." He has run that check by hand each time (5, 19 and
-- 27 Oct; 27 Oct test 2026-10-27-09:33:53:634t, 112 seeds: Microsoft 0 of 18 inbox). This makes it a loop.
--
-- MEASURED 27 Oct 2026, before writing this:
--   - this cloud container cannot reach glockapps.com or api.glockapps.com (proxy 403 on CONNECT), so the API is
--     called from the edge function deliverability_test, which runs server-side. The routes, the x-api-key header
--     and the report schema were read from the published Swagger (see supabase/functions/deliverability_test/
--     glockapps.ts); none is guessed.
--   - public.invite_placement_check (the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql)
--     is keyed by dubai_day, pins gmail_to and outlook_to to the founder's two inboxes by CHECK, and its verdict is
--     what fn_invite_placement_due's batch gate reads. A GlockApps test is many providers, has its own id, and can
--     run any day; written there it would collide with the morning seed's row or need a fake token, and could move
--     the daily batch gate. So the GlockApps results get their own two tables and leave that one alone.
--   - notifications holds 112 invite_m365_seed rows of 27 Oct whose bodies end "id:2026-10-27-09:33:53:634t"; that
--     test is adopted below, so the first collect reads the founder's own test of today and spends no credit.
--
-- WHAT THIS ADDS
--   1. public.deliverability_test: one row per GlockApps test (seeds, status, filter scores, Outlook %, verdict, the
--      summary, when it was filed); public.deliverability_test_provider: per provider inbox / spam / tabs / missing.
--      RLS on, service-role-only policy, revoked from anon and authenticated; both in the daily export registry.
--   2. fn_deliverability_test_tick(): the it_engineer duty it_engineer.deliverability_test, every 15 minutes. An open
--      test -> kick the edge function to collect it. Else a one-shot request (app_secrets deliverability_test_request,
--      set by fn_deliverability_test_request) or, when app_secrets deliverability_retest_weekly is 'true' (seeded
--      'false', so no seed is spent without intent) and the last test is 7 days old -> kick create. Else nothing.
--      The kick is net.http_post with the scoped credential cred_fn_deliverability_test (scope: deliverability_test).
--   3. fn_deliverability_test_file(test_id): once a verdict is decided, ONE founder email (founder_mail_policy kind
--      deliverability_verdict, deduped per test) and the it_engineer finding deliverability_outlook_not_proven raised
--      on fail / incomplete, closed on pass. Filed once (reported_at).
--   4. fn_deliverability_known_parties(text[]): which of these addresses belong to a lead or customer; the edge
--      function never queues a seed to one of them.
--
-- WHAT THIS DOES NOT DO: it never changes the invitation campaign's switches (the supplier invitation and WhatsApp
-- go-live keys), never resumes anything, and sends nothing to a supplier: seeds go only to the addresses GlockApps
-- returns for the test. Resuming at >= 80% is a real send and stays the founder's confirmation (ledger 1312, 1340).
-- It does not touch invite_placement_check or the morning seed.
--
-- Prevented by: scripts/checks/the_glockapps_test_runs_and_files_its_verdict_without_the_founder.test.mjs,
--               supabase/functions/deliverability_test/*.test.ts.

-- == 1. THE TABLES ====================================================================================================
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
  check (verdict = 'pending' or decided_at is not null),
  check (verdict <> 'pass' or outlook_inbox_pct >= 80)
);
comment on table public.deliverability_test is
  'it_engineer: one row per GlockApps inbox-placement test of the supplier invitation over the Microsoft 365 lane: seeds, filter scores, Outlook inbox % against the 80% bar (ledger 1312), verdict, and when it was filed (the_it_engineer_runs_the_glockapps_test_and_files_its_verdict_without_the_founder.sql).';
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
comment on table public.deliverability_test_provider is
  'it_engineer: per provider of one GlockApps test, inbox / spam / tabs (promotions and other tabs) / missing, and the raw iType labels counted (the_it_engineer_runs_the_glockapps_test_and_files_its_verdict_without_the_founder.sql).';
alter table public.deliverability_test_provider enable row level security;
drop policy if exists deliverability_test_provider_service_role_only on public.deliverability_test_provider;
create policy deliverability_test_provider_service_role_only on public.deliverability_test_provider
  as permissive for all to public using (false) with check (false);
revoke all on public.deliverability_test_provider from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('deliverability_test', true, 'deliverability', 'Each GlockApps inbox-placement test of the supplier invitation and its verdict against the founder''s 80% Outlook bar (ledger 1312).', 'it_engineer'),
  ('deliverability_test_provider', true, 'deliverability', 'Per-provider inbox, spam, tabs and missing counts of each GlockApps test.', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- == 2. THE SWITCHES, THE CREDENTIAL, THE MAIL KIND, THE OWNER =======================================================
-- 'false' unless someone sets it: a weekly re-test spends a GlockApps credit and ~110 seeds from supplier@.
insert into public.app_secrets (key, value) values ('deliverability_retest_weekly', 'false') on conflict (key) do nothing;

do $mint$
declare v_secret text;
begin
  if not exists (select 1 from public.internal_credential where context = 'fn.deliverability_test') then
    v_secret := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
    values ('fn.deliverability_test', 'it_engineer duty fn_deliverability_test_tick -> the deliverability_test edge function, and nothing else',
            public.fn_internal_credential_hash(v_secret), array['deliverability_test'], false, true);
    insert into public.app_secrets (key, value) values ('cred_fn_deliverability_test', v_secret)
    on conflict (key) do update set value = excluded.value;
  end if;
end
$mint$;

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('deliverability_verdict', true,
   'Ledger 1312: the GlockApps verdict (Outlook inbox % against 80%) decides whether supplier invitations may resume, and resuming is his confirmation. One email per test.',
   'it_engineer')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role;

insert into public.function_owner (function_slug, owner, note) values
  ('deliverability_test', 'it_engineer',
   'GlockApps inbox-placement test of the supplier invitation (ledger 1312): create the test and queue its seeds over the Microsoft 365 lane, collect the per-provider report, file the 80% Outlook verdict.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

-- == 3. WHICH ADDRESSES ARE REAL PARTIES ==============================================================================
create or replace function public.fn_deliverability_known_parties(p_emails text[])
 returns text[]
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
  -- A seed address that is also a lead or a customer is never sent to, demo or not: a seed must not be able to
  -- reach a party we hold, whatever GlockApps returns.
  select coalesce(array_agg(distinct e), '{}'::text[]) from (
    select lower(btrim(l.email)) e from public.leads l where lower(btrim(l.email)) = any(p_emails)
    union all select lower(btrim(l.claimed_by)) from public.leads l where lower(btrim(l.claimed_by)) = any(p_emails)
    union all select lower(btrim(c.email)) from public.customers c where lower(btrim(c.email)) = any(p_emails)
  ) x
$function$;
revoke execute on function public.fn_deliverability_known_parties(text[]) from public, anon, authenticated;
grant execute on function public.fn_deliverability_known_parties(text[]) to service_role;

-- == 4. A ONE-SHOT REQUEST FOR A TEST ===================================================================================
create or replace function public.fn_deliverability_test_request(p_reason text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_reason text := left(coalesce(nullif(btrim(p_reason), ''), 'requested'), 200);
begin
  -- The duty picks the request up on its next tick (15 minutes) and the edge function deletes it once a test exists.
  insert into public.app_secrets (key, value) values ('deliverability_test_request', v_reason)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('requested', true, 'reason', v_reason,
    'open_test', (select test_id from public.deliverability_test where status in ('seeds_queued', 'collecting') order by created_at limit 1));
end $function$;
revoke execute on function public.fn_deliverability_test_request(text) from public, anon, authenticated;
grant execute on function public.fn_deliverability_test_request(text) to service_role;

-- == 5. THE DUTY ======================================================================================================
create or replace function public.fn_deliverability_test_tick()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_open text; v_req text; v_weekly boolean; v_last timestamptz; v_ref text; v_secret text; v_body jsonb; v_id bigint;
begin
  select test_id into v_open from public.deliverability_test
   where status in ('seeds_queued', 'collecting') order by created_at limit 1;
  if v_open is not null then
    v_body := jsonb_build_object('action', 'collect', 'test_id', v_open);
  else
    select nullif(btrim(value), '') into v_req from public.app_secrets where key = 'deliverability_test_request';
    select lower(btrim(value)) = 'true' into v_weekly from public.app_secrets where key = 'deliverability_retest_weekly';
    select max(created_at) into v_last from public.deliverability_test;
    if v_req is not null then
      v_body := jsonb_build_object('action', 'create', 'reason', v_req);
    elsif coalesce(v_weekly, false) and (v_last is null or v_last < now() - interval '7 days') then
      v_body := jsonb_build_object('action', 'create', 'reason', 'weekly re-test during the warm-up (app_secrets deliverability_retest_weekly)');
    else
      return jsonb_build_object('action', 'none', 'weekly', coalesce(v_weekly, false), 'last_test_at', v_last);
    end if;
  end if;
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_deliverability_test';
  if coalesce(v_ref, '') = '' or coalesce(v_secret, '') = '' then
    return v_body || jsonb_build_object('kicked', false, 'reason', 'app_secrets project_ref or cred_fn_deliverability_test is missing');
  end if;
  select net.http_post(
           url := 'https://' || v_ref || '.supabase.co/functions/v1/deliverability_test',
           headers := '{"Content-Type":"application/json"}'::jsonb,
           body := v_body || jsonb_build_object('__secret', v_secret, 'source', 'seat_duty'),
           timeout_milliseconds := 120000) into v_id;
  -- the returned row lands in seat_duty.last_result: it carries the action, never the credential
  return v_body || jsonb_build_object('kicked', true, 'request_id', v_id);
end $function$;
revoke execute on function public.fn_deliverability_test_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.deliverability_test', 'it_engineer', interval '15 minutes', 'fn_deliverability_test_tick',
   'GlockApps inbox-placement test of the supplier invitation (ledger 1312): collect an open test until GlockApps finishes, then file the Outlook-vs-80% verdict to the founder and the it_engineer; create a test on request or, when deliverability_retest_weekly is true, weekly.',
   'scripts/sql/the_it_engineer_runs_the_glockapps_test_and_files_its_verdict_without_the_founder.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- == 6. FILING THE VERDICT =============================================================================================
create or replace function public.fn_deliverability_test_file(p_test_id text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  t public.deliverability_test;
  v_stub boolean := coalesce(current_setting('app.qd_stub_founder_notify', true), '') = 'on';
  v_pct text; v_event text; v_founder jsonb; v_it jsonb;
begin
  select * into t from public.deliverability_test where test_id = p_test_id for update;
  if not found then return jsonb_build_object('filed', false, 'reason', 'no such test'); end if;
  if t.verdict = 'pending' then return jsonb_build_object('filed', false, 'reason', 'not decided yet'); end if;
  if t.reported_at is not null then return jsonb_build_object('filed', false, 'reason', 'already filed', 'reported_at', t.reported_at); end if;
  v_pct := coalesce(t.outlook_inbox_pct::text || '%', 'no Outlook seed');
  v_event := '[GlockApps] Outlook ' || v_pct || ' inbox against the 80% bar: ' || upper(t.verdict) || ' (test ' || t.test_id || ')';
  if v_stub then
    v_founder := jsonb_build_object('stubbed', true, 'event', v_event);
  else
    v_founder := public.fn_notify_founder(p_event => v_event, p_detail => coalesce(t.summary, v_event),
      p_level => case when t.verdict = 'pass' then 'info' else 'warn' end, p_kind => 'deliverability_verdict',
      p_dedupe_key => 'deliverability_verdict:' || t.test_id, p_owner_agent => 'it_engineer');
  end if;
  if t.verdict = 'pass' then
    v_it := public.fn_it_engineer_finding_close('deliverability_outlook_not_proven',
      'closed by fn_deliverability_test_file: GlockApps test ' || t.test_id || ' put Outlook at ' || v_pct || ' inbox');
  else
    v_it := public.fn_it_engineer_finding_upsert('deliverability_outlook_not_proven',
      'Outlook inbox placement is not proven at 80%, so supplier invitations stay held',
      'GlockApps test ' || t.test_id || ' (public.deliverability_test)', 'internal',
      coalesce((t.outlook ->> 'seeds')::integer, 0),
      jsonb_build_object('test_id', t.test_id, 'verdict', t.verdict, 'outlook', t.outlook, 'filters', t.filters,
        'providers', (select coalesce(jsonb_agg(to_jsonb(p) - 'test_id' order by p.is_outlook desc, p.provider), '[]'::jsonb)
                        from public.deliverability_test_provider p where p.test_id = t.test_id)),
      '{}'::text[], '{}'::text[], 'it_engineer');
  end if;
  update public.deliverability_test set reported_at = now(),
         report_result = jsonb_build_object('founder', v_founder, 'it_engineer', v_it)
   where test_id = t.test_id;
  return jsonb_build_object('filed', true, 'verdict', t.verdict, 'founder', v_founder, 'it_engineer', v_it);
end $function$;
revoke execute on function public.fn_deliverability_test_file(text) from public, anon, authenticated;
grant execute on function public.fn_deliverability_test_file(text) to service_role;

-- == 7. ADOPT THE FOUNDER'S TEST OF 27 OCT ==============================================================================
-- Its seeds are the 27 Oct invite_m365_seed rows whose body ends with its marker. Read, never changed.
insert into public.deliverability_test (test_id, reason, requested_by, created_at, marker, from_address, seeds, notification_ids, status)
select '2026-10-27-09:33:53:634t',
       'adopted: the founder''s GlockApps test of 27 Oct 2026, run by hand (ledger 1312)', 'it_engineer',
       min(n.created_at), 'id:2026-10-27-09:33:53:634t',
       (select value from public.app_secrets where key = 'invite_m365_mailbox'),
       jsonb_agg(distinct jsonb_build_object('email', lower(btrim(n.to_email)), 'provider', '', 'provider_group_id', '')),
       array_agg(n.id order by n.id), 'collecting'
  from public.notifications n
 where n.type = 'supplier_invite_seed' and n.kind = 'invite_m365_seed'
   and rtrim(n.body) like '%id:2026-10-27-09:33:53:634t'
having count(*) > 0
on conflict (test_id) do nothing;

-- == PROBE (structure only; reads, writes nothing, returns a verdict row) ===============================================
-- The behaviour (tick, filing, refusal) is proved by ..._probe.sql in one rolled-back transaction.
with c(step, v) as (values
  ('rls_and_policy', (select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('public.deliverability_test'::regclass, 'public.deliverability_test_provider'::regclass))
                     and (select count(*) = 2 from pg_policies where schemaname = 'public' and policyname in ('deliverability_test_service_role_only', 'deliverability_test_provider_service_role_only'))),
  ('anon_refused', not has_function_privilege('anon', 'public.fn_deliverability_test_tick()', 'execute')
                   and not has_function_privilege('anon', 'public.fn_deliverability_test_file(text)', 'execute')
                   and not has_function_privilege('anon', 'public.fn_deliverability_test_request(text)', 'execute')
                   and not has_function_privilege('anon', 'public.fn_deliverability_known_parties(text[])', 'execute')
                   and not has_table_privilege('anon', 'public.deliverability_test', 'select')),
  ('credential_scoped', exists (select 1 from public.internal_credential c join public.app_secrets s on s.key = 'cred_fn_deliverability_test'
                          where c.context = 'fn.deliverability_test' and c.active and c.scope = array['deliverability_test']
                            and c.secret_hash = public.fn_internal_credential_hash(s.value))),
  ('duty_registered', exists (select 1 from public.seat_duty where duty = 'it_engineer.deliverability_test' and enabled and routine = 'fn_deliverability_test_tick')),
  ('weekly_switch_exists', exists (select 1 from public.app_secrets where key = 'deliverability_retest_weekly')),
  ('mail_kind_allowed', exists (select 1 from public.founder_mail_policy where kind = 'deliverability_verdict' and allowed_to_email))
)
select coalesce('PROBE FAILED: ' || string_agg(step, ', ' order by step) filter (where not coalesce(v, false)), 'PROBE OK') as verdict from c;
