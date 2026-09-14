-- THE IT ENGINEER RUNS ITS DUTIES EVERY HOUR, AND EACH ONE GOES ROUND THE LOOP.
--
-- Assigned: it_engineer (every check and its record). Each failure is answered by the seat that owns
-- it: payments -> accountant, deliveries -> customer_support, the rest by public.function_owner or ceo.
--
-- Founder, 14 Sep 2026: "fine add them" — the eight duties — and "also we should not rely on the LLM as
-- much as possible in the operation". Every check here is a comparison, a threshold or a date; no model
-- call is on this path.
--
-- HOW A DUTY REPORTS. The edge tick (resilience_ping -> _shared/it_duty_readings.ts) takes the
-- readings Postgres cannot take — HTTP to the sites, Stripe, GitHub, Vercel, the providers — and hands
-- them to fn_it_duties, which decides. Each failing item becomes an it_engineer_finding keyed
-- 'duty:<duty>:<item>' through fn_it_duty_settle; an item no longer failing is closed the same call.
-- fn_it_loop_tick (the_it_engineer_closes_every_loop_it_opens.sql) then hands each actionable finding
-- to its owner, re-verifies and closes. A duty whose reading could not be taken is NOT settled: its
-- open findings stay open and the basis says why, so "could not look" never reads as "all clear".
--
-- WHAT EACH DUTY CAN AND CANNOT SEE is written above it. Duty 1 (the nightly journey) arrives through
-- fn_it_journey_ingest from scripts/e2e/report_to_it_engineer.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_runs_its_duties_every_hour.sql --apply --ddl

-- ── 0. SETTLING A DUTY'S FINDINGS ────────────────────────────────────────────────────────────────
-- p_items: [{item, title, owner_seat, subject, blast, affected, evidence}] — everything failing NOW.
create or replace function public.fn_it_duty_settle(p_duty text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; v_keys text[] := '{}'; v_key text; n_closed int := 0; v_open text;
begin
  if coalesce(btrim(p_duty), '') = '' or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'fn_it_duty_settle(duty, items[]): a duty name and an array of failing items are required';
  end if;
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce(btrim(x->>'item'), '') = '' or coalesce(btrim(x->>'title'), '') = '' then
      raise exception 'fn_it_duty_settle: every item needs an item key and a title (%)', x;
    end if;
    v_key := 'duty:' || p_duty || ':' || (x->>'item');
    v_keys := v_keys || v_key;
    perform public.fn_it_engineer_finding_upsert(v_key, x->>'title', 'IT engineer duty: ' || p_duty,
      coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
      coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
        'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
        'demo', coalesce((x->>'demo')::boolean, false)),
      '{}'::text[], '{}'::text[], 'it_engineer.' || p_duty);
  end loop;
  for v_open in select issue_key from public.it_engineer_finding
                 where closed_at is null and issue_key like 'duty:' || p_duty || ':%' and not (issue_key = any (v_keys)) loop
    perform public.fn_it_engineer_finding_close(v_open, 'the ' || p_duty || ' duty no longer finds it');
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('duty', p_duty, 'failing', coalesce(array_length(v_keys, 1), 0), 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_it_duty_settle(text, jsonb) from public, anon, authenticated;

-- ── 3a. DATES THE COMPANY MUST RENEW ─────────────────────────────────────────────────────────────
-- Licence and NOL dates are facts the founder gave (memory: trade licence DET 1633275 expires
-- 24 Jun 2027; TDRA NOL-26-100000665 expires 14 Sep 2027). Domain and TLS rows are written by the
-- readings (source 'rdap' / 'crt.sh'); nobody types them.
create table if not exists public.it_expiry (
  item        text primary key,
  kind        text not null check (kind in ('licence', 'domain', 'tls')),
  expires_on  date,
  owner_seat  text not null,
  route       text not null,
  source      text not null,
  checked_at  timestamptz not null default now()
);
comment on table public.it_expiry is
  'What the company must renew and by when. Warned 30 days ahead through the IT loop; owner_seat answers, route says who can actually renew (ceo for licences, accountant for paid renewals, founder for what only he can do).';
alter table public.it_expiry enable row level security;
drop policy if exists it_expiry_service_role_only on public.it_expiry;
create policy it_expiry_service_role_only on public.it_expiry as permissive for all to public using (false) with check (false);
revoke all on public.it_expiry from anon, authenticated;

insert into public.it_expiry (item, kind, expires_on, owner_seat, route, source) values
  ('trade_licence_det_1633275', 'licence', date '2027-06-24', 'ceo', 'ceo renews with DET; the fee is the accountant''s', 'founder, recorded 9 Sep 2026'),
  ('tdra_nol_26_100000665',     'licence', date '2027-09-14', 'ceo', 'ceo renews with TDRA for www.quotesdone.ae', 'founder, recorded 14 Sep 2026'),
  ('domain:quotesdone.com',     'domain',  null,              'accountant', 'accountant pays the registrar; the founder only if the registrar account is his alone', 'rdap'),
  ('domain:quotesdone.ae',      'domain',  null,              'accountant', 'accountant pays the registrar; the founder only if the registrar account is his alone', 'rdap'),
  ('tls:quotesdone.com',        'tls',     null,              'ceo', 'Vercel renews automatically; a date inside 30 days means it did not', 'crt.sh'),
  ('tls:quotesdone.ae',         'tls',     null,              'ceo', 'Vercel renews automatically; a date inside 30 days means it did not', 'crt.sh')
on conflict (item) do update set kind = excluded.kind, owner_seat = excluded.owner_seat, route = excluded.route,
  expires_on = coalesce(excluded.expires_on, public.it_expiry.expires_on), source = excluded.source;

-- ── 6a. THE SECURITY BASELINE ────────────────────────────────────────────────────────────────────
-- Exposures someone has ACCEPTED, each with its reason and who accepted it. It starts empty.
-- Review of #636, 14 Sep 2026: the first cut seeded this from whatever was exposed at apply time and so
-- accepted two live holes for good — fn_customer_documents(text,text,integer,text[]) and
-- fn_customer_document_refs(), anon-executable SECURITY DEFINER routines that documents_customer_vault.sql
-- meant for authenticated + service_role only. Those rows are deleted below and the sweep raises them.
create table if not exists public.it_security_baseline (
  object      text not null,
  kind        text not null check (kind in ('anon_executable_definer', 'rls_off', 'rls_no_policy')),
  recorded_at timestamptz not null default now(),
  primary key (object, kind)
);
alter table public.it_security_baseline add column if not exists reason text;
alter table public.it_security_baseline add column if not exists accepted_by text;
-- Each reasonless row is written to agent_runs before it goes, so the deletion leaves a trace.
insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
select 'it_engineer', 'ok', now(), now(),
       jsonb_build_object('job', 'security_baseline_cleanup', 'object', object, 'kind', kind, 'recorded_at', recorded_at),
       'removed from it_security_baseline: accepted with no reason and nobody named'
  from public.it_security_baseline
 where coalesce(btrim(reason), '') = '' or coalesce(btrim(accepted_by), '') = '';
delete from public.it_security_baseline where coalesce(btrim(reason), '') = '' or coalesce(btrim(accepted_by), '') = '';
alter table public.it_security_baseline drop constraint if exists it_security_baseline_kind_check;
alter table public.it_security_baseline add constraint it_security_baseline_kind_check
  check (kind in ('anon_executable_definer', 'authenticated_executable_definer', 'rls_off', 'rls_no_policy'));
alter table public.it_security_baseline alter column reason set not null;
alter table public.it_security_baseline alter column accepted_by set not null;
alter table public.it_security_baseline drop constraint if exists it_security_baseline_accepted_with_reason;
alter table public.it_security_baseline add constraint it_security_baseline_accepted_with_reason
  check (btrim(reason) <> '' and btrim(accepted_by) <> '');
comment on table public.it_security_baseline is
  'Security exposures deliberately accepted, each with a stated reason and who accepted it (a reasonless row is refused). The sweep raises every exposure not listed here; removing a row withdraws the acceptance.';
alter table public.it_security_baseline enable row level security;
drop policy if exists it_security_baseline_service_role_only on public.it_security_baseline;
create policy it_security_baseline_service_role_only on public.it_security_baseline as permissive for all to public using (false) with check (false);
revoke all on public.it_security_baseline from anon, authenticated;

create or replace function public.fn_it_security_exposures()
returns table(object text, kind text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- Review of #639: this used to call a routine anon-executable when anon OR authenticated could run
  -- it, and so flagged the two portal RPCs fn_customer_documents and fn_customer_document_refs, which
  -- are authenticated-only (anon_exec false, measured). The two are different findings now:
  --   anon_executable_definer          anyone at all can run it with the definer's rights — always raised
  --   authenticated_executable_definer a signed-in user can, and the body never asks who they are
  --                                    (no auth.uid(), auth.email() or auth.jwt()) — raised
  -- A signed-in RPC that scopes itself by the caller's identity is the portals working, not a finding.
  select p.oid::regprocedure::text, 'anon_executable_definer'
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and has_function_privilege('anon', p.oid, 'execute')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select p.oid::regprocedure::text, 'authenticated_executable_definer'
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.prosrc !~* 'auth\.(uid|email|jwt)\s*\('
     -- Scoping by delegation counts: fn_customer_documents asks no identity itself and joins
     -- fn_customer_document_refs(), which does (measured 14 Sep 2026). One level of call is followed.
     and not exists (select 1 from pg_proc q join pg_namespace qn on qn.oid = q.pronamespace
                      where qn.nspname = 'public' and q.oid <> p.oid
                        and q.prosrc ~* 'auth\.(uid|email|jwt)\s*\('
                        and p.prosrc ~* ('public\.' || q.proname || '\s*\('))
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select c.oid::regclass::text, case when not c.relrowsecurity then 'rls_off' else 'rls_no_policy' end
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and (not c.relrowsecurity or not exists (select 1 from pg_policy pl where pl.polrelid = c.oid))
     -- Only what a browser role can actually read: an RLS-less table nobody is granted is not exposed.
     and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select'))
$fn$;
revoke execute on function public.fn_it_security_exposures() from public, anon, authenticated;

-- ── THE DUTIES ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_duties(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_out jsonb := '{}'::jsonb; v_items jsonb; x record; s jsonb; v_mode text; v_hook jsonb; v_missing text[];
  v_p95 numeric; v_hour int;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_it_duties takes the readings object from _shared/it_duty_readings.ts';
  end if;

  -- ── 2. LIVE == CODE ──
  -- Reads: the latest main commit's GitHub check runs ('checks', 'deploy functions') and the Vercel
  -- production deployment for that commit. The canonical routine manifest itself runs inside the
  -- 'checks' workflow, so its conclusion is the drift verdict. Cannot see: drift introduced after the
  -- last merge by a live apply with no commit (the manifest check in the next CI run catches that).
  if (p_r->'github'->>'basis') = 'measured' then
    v_items := '[]'::jsonb;
    for x in select key, value from jsonb_each(coalesce(p_r->'github'->'conclusions', '{}'::jsonb)) loop
      if x.value #>> '{}' not in ('success', 'skipped', 'neutral', 'in_progress', 'queued') then
        v_items := v_items || jsonb_build_object('item', 'ci:' || x.key, 'owner_seat', 'ceo', 'subject', 'github',
          'title', 'On main ' || left(p_r->'github'->>'sha', 7) || ', "' || x.key || '" ended ' || (x.value #>> '{}')
                   || ' — what is live may not be what is merged',
          'blast', 'agent_facing', 'affected', 1, 'evidence', p_r->'github');
      end if;
    end loop;
    if (p_r->'vercel'->>'basis') = 'measured' and coalesce(p_r->'vercel'->>'state', '') not in ('READY', 'BUILDING', 'QUEUED', 'INITIALIZING') then
      v_items := v_items || jsonb_build_object('item', 'vercel', 'owner_seat', 'ceo', 'subject', 'website',
        'title', 'The website deployment for main ' || left(p_r->'github'->>'sha', 7) || ' is ' || coalesce(p_r->'vercel'->>'state', 'missing'),
        'blast', 'customer_facing', 'affected', 0, 'evidence', p_r->'vercel');
    end if;
    v_out := v_out || jsonb_build_object('live_code', public.fn_it_duty_settle('live_code', v_items));
  else
    v_out := v_out || jsonb_build_object('live_code', jsonb_build_object('basis', coalesce(p_r->'github'->>'basis', 'not_read'), 'reason', p_r->'github'->>'reason'));
  end if;

  -- ── 3. EXPIRIES ──
  -- Reads: it_expiry (licences from the founder, domains from RDAP, TLS from crt.sh), internal_credential
  -- expires_at, and each provider credential answering a harmless authenticated GET. Cannot see: a
  -- provider key's own expiry date — Stripe, Resend, Twilio and Dropbox do not publish one, so the
  -- test is whether the key still works today. Credentials used to rotate on a pg_cron job that went
  -- with the 7 Sep removal and no routine rotates them now, so an expiry inside 30 days is handed on.
  for x in select key, value from jsonb_each(coalesce(p_r->'expiries', '{}'::jsonb)) loop
    if (x.value->>'expires_on') is not null then
      update public.it_expiry set expires_on = (x.value->>'expires_on')::date, checked_at = now() where item = x.key;
    end if;
  end loop;
  v_items := '[]'::jsonb;
  -- Certificates only: licences, domains and tokens are warned to the accountant at 60 and 30 days by
  -- fn_it_renewal_watch (renewals_warn_the_accountant_at_sixty_and_thirty_days.sql).
  for x in select * from public.it_expiry where kind = 'tls' and expires_on is not null and expires_on < current_date + 30 loop
    v_items := v_items || jsonb_build_object('item', x.item, 'owner_seat', x.owner_seat, 'subject', x.item,
      'title', x.item || ' expires on ' || x.expires_on || ' (' || (x.expires_on - current_date) || ' days)',
      'blast', case when x.expires_on < current_date + 7 then 'customer_facing' else 'agent_facing' end, 'affected', 1,
      'evidence', jsonb_build_object('route', x.route, 'source', x.source, 'checked_at', x.checked_at));
  end loop;
  -- Only what cannot rotate itself: a legacy credential, or one whose secret has no app_secrets key
  -- (duty 15, the_it_engineer_takes_on_seven_more_duties.sql, rotates the rest 30 days ahead).
  for x in select ic.context, ic.expires_at from public.internal_credential ic
            where ic.active and ic.expires_at is not null and ic.expires_at < now() + interval '30 days'
              and (ic.is_legacy or not exists (select 1 from public.app_secrets s where s.key = 'cred_' || replace(ic.context, '.', '_'))) loop
    v_items := v_items || jsonb_build_object('item', 'credential:' || x.context, 'owner_seat', 'ceo', 'subject', x.context,
      'title', 'Internal credential ' || x.context || ' expires ' || to_char(x.expires_at, 'DD Mon YYYY') || ' and cannot be rotated automatically',
      'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('expires_at', x.expires_at));
  end loop;
  v_out := v_out || jsonb_build_object('expiry', public.fn_it_duty_settle('expiry', v_items));

  -- Provider credentials are their own duty so a tick without the providers reading leaves them as
  -- they were instead of closing them.
  if jsonb_typeof(p_r->'providers') = 'object' then
    v_items := '[]'::jsonb;
    for x in select key, value from jsonb_each(p_r->'providers') loop
      if (x.value->>'basis') = 'measured' and (x.value->>'status')::int in (401, 403) then
        v_items := v_items || jsonb_build_object('item', x.key,
          'owner_seat', coalesce(x.value->>'owner_seat', 'ceo'), 'subject', x.key,
          'title', 'The ' || x.key || ' credential was refused (HTTP ' || (x.value->>'status') || ')',
          'blast', 'customer_facing', 'affected', 1, 'evidence', x.value);
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('credential', public.fn_it_duty_settle('credential', v_items));
  end if;

  -- ── 4. DELIVERY CONFIRMATION ──
  -- Reads: the delivery loop (customer_support's build) — every delivery.request gets a delivery.result
  -- back to its originator, which records detail.loop. What IT watches is that the loop CLOSED: a request
  -- older than two hours with no loop verdict, and an email marked sent with no provider id.
  v_items := '[]'::jsonb;
  for x in select a.id, a.detail->>'from' frm, a.created_at from public.agent_actions a
            where a.kind = 'handoff' and a.detail->>'type' = 'delivery.request'
              and a.created_at < now() - interval '2 hours' and a.created_at > now() - interval '7 days'
              and not (a.detail ? 'loop') and a.title not ilike '%ZZ DEMO%' loop
    v_items := v_items || jsonb_build_object('item', 'request:' || x.id, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
      'title', 'Delivery request ' || x.id || ' from ' || x.frm || ' has had no confirmed outcome for '
               || round(extract(epoch from now() - x.created_at) / 3600) || ' hours',
      'blast', 'customer_facing', 'affected', 0, 'evidence', jsonb_build_object('handoff_id', x.id));
  end loop;
  for x in select n.id, n.to_role, n.sent_at from public.notifications n
            where n.status = 'sent' and n.channel = 'email' and coalesce(btrim(n.provider_message_id), '') = ''
              and n.sent_at > now() - interval '48 hours' loop
    v_items := v_items || jsonb_build_object('item', 'notification:' || x.id, 'owner_seat', 'customer_support', 'subject', 'send_outbox',
      'title', 'Email ' || x.id || ' to the ' || coalesce(x.to_role, 'recipient') || ' is marked sent but the provider never gave it an id',
      'blast', 'customer_facing', 'affected', 0, 'evidence', jsonb_build_object('notification_id', x.id, 'sent_at', x.sent_at));
  end loop;
  v_out := v_out || jsonb_build_object('delivery', public.fn_it_duty_settle('delivery', v_items));

  -- ── 5. PAYMENT RECONCILIATION ──
  -- Reads: Stripe live and test — completed Checkout Sessions and refunds of the last 72 hours, and the
  -- webhook endpoints' enabled events against HANDLED_STRIPE_EVENTS (passed in from
  -- _shared/stripe_events.ts, the list the webhook itself branches on). IT checks the wiring; the
  -- accountant owns the money and answers every mismatch. A mode whose key is absent is reported, not
  -- treated as matched.
  v_items := '[]'::jsonb;
  for v_mode in select unnest(array['live', 'test']) loop
    s := p_r->'stripe'->v_mode;
    continue when coalesce(s->>'basis', '') <> 'measured';
    for x in select e from jsonb_array_elements(coalesce(s->'paid_sessions', '[]'::jsonb)) e loop
      if not exists (select 1 from public.transactions t
                      where t.payment_ref in (x.e->>'id', x.e->>'payment_intent')) then
        v_items := v_items || jsonb_build_object('item', v_mode || ':session:' || (x.e->>'id'), 'owner_seat', 'accountant',
          'subject', 'stripe_webhook',
          'title', 'Stripe ' || v_mode || ' took AED ' || round(coalesce((x.e->>'amount_total')::numeric, 0) / 100, 2)
                   || ' in session ' || (x.e->>'id') || ' and no transaction records it',
          'blast', 'customer_facing', 'affected', 1, 'demo', v_mode = 'test', 'evidence', x.e);
      end if;
    end loop;
    for x in select e from jsonb_array_elements(coalesce(s->'refunds', '[]'::jsonb)) e loop
      if not exists (select 1 from public.refunds r where r.stripe_refund_id = x.e->>'id')
         and not exists (select 1 from public.transactions t where t.refund_stripe_id = x.e->>'id') then
        v_items := v_items || jsonb_build_object('item', v_mode || ':refund:' || (x.e->>'id'), 'owner_seat', 'accountant',
          'subject', 'stripe_webhook',
          'title', 'Stripe ' || v_mode || ' refunded ' || (x.e->>'id') || ' and our books do not record it',
          'blast', 'customer_facing', 'affected', 1, 'demo', v_mode = 'test', 'evidence', x.e);
      end if;
    end loop;
    v_hook := (select e from jsonb_array_elements(coalesce(s->'webhooks', '[]'::jsonb)) e
                where e->>'url' like '%/functions/v1/stripe_webhook%' and e->>'status' = 'enabled' limit 1);
    select array_agg(h) into v_missing from jsonb_array_elements_text(coalesce(p_r->'stripe'->'handled', '[]'::jsonb)) h
     where v_hook is null or not (v_hook->'enabled_events' ? h or v_hook->'enabled_events' ? '*');
    if v_missing is not null then
      v_items := v_items || jsonb_build_object('item', v_mode || ':webhook', 'owner_seat', 'accountant', 'subject', 'stripe_webhook',
        'title', case when v_hook is null then 'No enabled Stripe ' || v_mode || ' webhook points at stripe_webhook'
                      else 'The Stripe ' || v_mode || ' webhook does not send ' || array_to_string(v_missing, ', ') end,
        'blast', 'customer_facing', 'affected', 0, 'demo', v_mode = 'test',
        'evidence', jsonb_build_object('missing', to_jsonb(v_missing), 'endpoint', v_hook));
    end if;
  end loop;
  if coalesce(p_r->'stripe'->'live'->>'basis', '') = 'measured' or coalesce(p_r->'stripe'->'test'->>'basis', '') = 'measured' then
    v_out := v_out || jsonb_build_object('payment', public.fn_it_duty_settle('payment', v_items));
  else
    v_out := v_out || jsonb_build_object('payment', jsonb_build_object('basis', 'not_read', 'reading', p_r->'stripe'));
  end if;

  -- ── 6. SECURITY SWEEP ──
  -- Reads: the catalogue (routines anon/authenticated may execute with the definer's rights, tables with
  -- RLS off or on with no policy) against it_security_baseline, and sign-in codes sent in the last hour
  -- against this estate's own hourly p95 over seven days. Cannot see: the Supabase security advisors
  -- (management API, run in CI by security_advisors_match_the_baseline.mjs). A known fix — a revoke or
  -- a pinned search_path — is shipped only as a file with a MANIFEST line in a PR, never live.
  v_items := '[]'::jsonb;
  for x in select e.object, e.kind from public.fn_it_security_exposures() e
            where not exists (select 1 from public.it_security_baseline b where b.object = e.object and b.kind = e.kind) loop
    v_items := v_items || jsonb_build_object('item', x.kind || ':' || x.object, 'owner_seat', 'ceo', 'subject', x.object,
      'title', case x.kind when 'anon_executable_definer' then 'Anyone, signed in or not, can run ' || x.object || ' with the definer''s rights'
                           when 'authenticated_executable_definer' then 'Any signed-in user can run ' || x.object || ' with the definer''s rights, and it never checks who they are'
                           when 'rls_off' then 'Table ' || x.object || ' has row security switched off'
                           else 'Table ' || x.object || ' has row security on and no policy, and a browser role can read it' end,
      'blast', 'security', 'affected', 1,
      'evidence', jsonb_build_object('kind', x.kind, 'baseline_size', (select count(*) from public.it_security_baseline),
                                     'fix', 'a file with a MANIFEST line in a PR: revoke execute / enable RLS and add a policy'));
  end loop;
  select coalesce(percentile_cont(0.95) within group (order by n), 0) into v_p95
    from (select date_trunc('hour', created_at) h, count(*) n from public.customer_phone_otps
           where created_at > now() - interval '7 days' and created_at <= now() - interval '1 hour' group by 1) z;
  select count(*) into v_hour from public.customer_phone_otps where created_at > now() - interval '1 hour';
  if v_hour > greatest(10, 3 * v_p95) then
    v_items := v_items || jsonb_build_object('item', 'otp_spike', 'owner_seat', 'ceo', 'subject', 'login_otp',
      'title', v_hour || ' sign-in codes were sent in the last hour against an hourly p95 of ' || round(v_p95),
      'blast', 'security', 'affected', 1, 'evidence', jsonb_build_object('last_hour', v_hour, 'p95_hourly_7d', v_p95));
  end if;
  v_out := v_out || jsonb_build_object('security', public.fn_it_duty_settle('security', v_items));

  -- ── 7. UPTIME ──
  -- Reads: each public origin answered this hour. fn_it_detect already judges the edge functions'
  -- failure rates (D1, with the founder's hold now counted as held) and public_site_url's latency; this
  -- adds the other origins. Cannot see: that a UAE visitor is really sent to .ae — the redirect keys on
  -- Vercel's x-vercel-ip-country, which an outside request cannot set. What is checked is its other
  -- half: that quotesdone.ae itself serves the site.
  if jsonb_typeof(p_r->'sites') = 'array' then
    v_items := '[]'::jsonb;
    for x in select e from jsonb_array_elements(p_r->'sites') e loop
      if coalesce((x.e->>'status')::int, 0) not between 200 and 399 then
        v_items := v_items || jsonb_build_object('item', x.e->>'url', 'owner_seat', 'ceo', 'subject', 'website',
          'title', x.e->>'url' || ' ' || coalesce('answered HTTP ' || (x.e->>'status'), 'did not answer: ' || coalesce(x.e->>'error', 'no status')),
          'blast', 'customer_facing', 'affected', 1, 'evidence', x.e);
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('uptime', public.fn_it_duty_settle('uptime', v_items));
  end if;

  -- ── 8. DEMO HYGIENE ──
  -- Reads: demo customers and suppliers (is_demo, or the harness's qd-<tag>- address) created more
  -- than six hours ago outside an open rehearsal window. A leftover is a demo row that can reach a
  -- count; the harness purges its own tag, so one that survives is a teardown fault. Cannot see: a
  -- dashboard that counts demo rows while none exist — with zero leftovers there is nothing to leak.
  v_items := '[]'::jsonb;
  for x in select 'customers' t, count(*) n from public.customers c
            where (c.is_demo or c.email like 'qd-%@example.invalid') and c.created_at < now() - interval '6 hours'
           union all
           select 'leads', count(*) from public.leads l
            where (l.is_demo or l.email like 'qd-%@example.invalid') and l.created_at < now() - interval '6 hours' loop
    -- Only a run still in progress excuses leftovers. Measured on the proof: four e2e windows and one
    -- from 5 Sep were never closed, and "any open window" silenced this check for good.
    if x.n > 0 and not exists (select 1 from public.rehearsal_window w
                                where w.ended_at is null and w.started_at > now() - interval '6 hours') then
      v_items := v_items || jsonb_build_object('item', x.t, 'owner_seat', 'ceo', 'subject', 'e2e_harness',
        'title', x.n || ' demo ' || x.t || ' row(s) outlived their run by more than six hours',
        'blast', 'internal', 'affected', 1, 'demo', true,
        'evidence', jsonb_build_object('table', x.t, 'rows', x.n, 'purge', 'node scripts/e2e/run.mjs --purge-tag <tag>'));
    end if;
  end loop;
  -- A rehearsal window left open is a run that never tore down.
  for x in select w.id, w.run_tag, w.opened_by, w.started_at from public.rehearsal_window w
            where w.ended_at is null and w.started_at < now() - interval '6 hours' loop
    v_items := v_items || jsonb_build_object('item', 'window:' || x.id, 'owner_seat', 'ceo', 'subject', 'e2e_harness',
      'title', 'Rehearsal window ' || x.run_tag || ' (' || x.opened_by || ') has been open since '
               || to_char(x.started_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
      -- agent_facing, so it is handed on at once: an open window already silences the failed-run pager.
      'blast', 'agent_facing', 'affected', 1, 'demo', true,
      'evidence', jsonb_build_object('rehearsal_window_id', x.id, 'close', 'update public.rehearsal_window set ended_at = now() where id = ' || x.id));
  end loop;
  v_out := v_out || jsonb_build_object('demo', public.fn_it_duty_settle('demo', v_items));

  -- ── 1. THE NIGHTLY JOURNEY'S HEARTBEAT ──
  -- The run itself reports through fn_it_journey_ingest. Silence for 26 hours is its own finding —
  -- but only once this tick has itself been running for 26 hours. Measured 14 Sep 2026: the first cut
  -- raised "no run" the hour it was deployed, before nightly-journey.yml's first 22:00 UTC schedule
  -- had come round (the repository secret it uses has existed since 7 Sep).
  v_items := '[]'::jsonb;
  if exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duties'
              and started_at < now() - interval '26 hours')
     and not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'journey'
                  and started_at > now() - interval '26 hours') then
    v_items := jsonb_build_array(jsonb_build_object('item', 'no_run', 'owner_seat', 'ceo', 'subject', 'e2e_harness',
      'title', 'The nightly full-journey test has not reported for 26 hours',
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('workflow', '.github/workflows/nightly-journey.yml',
        'look_at', 'the workflow''s runs in GitHub Actions: not triggered, failed, or failed to report')));
  end if;
  v_out := v_out || jsonb_build_object('journey_heartbeat', public.fn_it_duty_settle('journey_heartbeat', v_items));

  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'duties', 'result', v_out), null);
  return v_out;
end $fn$;
revoke execute on function public.fn_it_duties(jsonb) from public, anon, authenticated;

-- Hourly: the tick asks before it spends the HTTP calls.
create or replace function public.fn_it_duties_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select not exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duties'
                      and started_at > now() - interval '55 minutes')
$fn$;
revoke execute on function public.fn_it_duties_due() from public, anon, authenticated;

-- ── 1. THE NIGHTLY JOURNEY ───────────────────────────────────────────────────────────────────────
-- p_report: {tag, steps:[{journey, name, status, detail}], leftovers}. A failed step is handed to the
-- seat that owns that part of the funnel; a later passing run closes it; leftovers are a demo finding.
create or replace function public.fn_it_journey_ingest(p_report jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb := '[]'::jsonb; x jsonb; v_owner text; v_letter text; v_res jsonb;
begin
  if jsonb_typeof(p_report->'steps') is distinct from 'array' or coalesce(btrim(p_report->>'tag'), '') = '' then
    raise exception 'fn_it_journey_ingest takes {tag, steps:[...]} from scripts/e2e/report_to_it_engineer.mjs';
  end if;
  for x in select e from jsonb_array_elements(p_report->'steps') e where e->>'status' = 'FAIL' loop
    v_letter := left(coalesce(x->>'journey', ''), 1);
    -- a/b/c/f drive the portals, the intake, the quotes and the comparison — the sales engineer's
    -- (function_owner: customer_portal, supplier_portal, inquiry_intake, quote_compare). d/e are the
    -- payment and the invoice — the accountant's (stripe_checkout, reveal_invoice). Fixtures, safety
    -- and cleanup are the harness itself, which the ceo owns.
    v_owner := case when v_letter in ('a', 'b', 'c', 'f') then 'sales_engineer'
                    when v_letter in ('d', 'e') then 'accountant' else 'ceo' end;
    v_items := v_items || jsonb_build_object(
      'item', coalesce(x->>'journey', '?') || ':' || left(regexp_replace(coalesce(x->>'name', '?'), '[^a-zA-Z0-9]+', '_', 'g'), 80),
      'owner_seat', v_owner, 'subject', 'journey ' || coalesce(x->>'journey', '?'),
      'title', 'Nightly journey failed: [' || coalesce(x->>'journey', '?') || '] ' || coalesce(x->>'name', '?'),
      'blast', 'customer_facing', 'affected', 0,
      'demo', coalesce((p_report->>'demo')::boolean, false),
      'evidence', jsonb_build_object('tag', p_report->>'tag', 'detail', left(x->>'detail', 600)));
  end loop;
  v_res := public.fn_it_duty_settle('journey', v_items);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', case when jsonb_array_length(v_items) = 0 then 'ok' else 'warn' end, now(), now(),
          jsonb_build_object('job', 'journey', 'tag', p_report->>'tag', 'failed', jsonb_array_length(v_items),
                             'steps', jsonb_array_length(p_report->'steps'), 'leftovers', p_report->'leftovers'), null);
  return v_res;
end $fn$;
revoke execute on function public.fn_it_journey_ingest(jsonb) from public, anon, authenticated;
