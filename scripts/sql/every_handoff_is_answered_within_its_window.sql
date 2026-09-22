-- EVERY HANDOFF IS ANSWERED WITHIN ITS WINDOW, OR THE IT ENGINEER SAYS SO.
--
-- Assigned: ceo. 22 Sep 2026. Founder, 14 Sep 2026: "nothing literally should ever be a one way
-- communication"; 21 Sep 2026: "i dont want things to pop up again for the same reasons".
--
-- MEASURED, read-only against htdblwldjkcgjvmqkbeh, 22 Sep 2026 06:50-07:30Z:
--   29 handoffs pending for more than 6 h -- ceo 18 (oldest 14 Sep), customer_support 5, sales_engineer 6.
--   ALL 29 are it.finding from it_engineer. ALL 29 were answered by their seat within the same second
--   (replied_at = created_at), ALL 29 findings are CLOSED (or the occurrence ended and reopened later),
--   ALL 29 were escalated and their CEO report ('it_loop:<id>') accepted, and ALL 29 carry
--   awaiting_learning: fn_it_loop_reverify parked them because their it_incident has no cause, fix or
--   regression check and no it_playbook class with a typical_cause covers the key. The parked branch has
--   no clock and no addressee, so nothing ever looked at them again: "waits for a human" with nobody
--   told. Their 29 CEO reports sit 'accepted' too, because only the reverify close path completes them
--   and fn_it_attach_learning, the one way out, never did.
--   duty:delivery:request:48729 and :50861 -- both are founder-bound delivery.requests customer_support
--   deliberately holds for the 19:00 Dubai IT digest (evidence.digest = 'pending'; a fault younger than
--   24 h waits for the next day's). fn_it_duties' delivery duty raises any request older than 2 h with
--   no loop verdict and did not know about that hold. Nothing was lost; the duty misread a schedule.
--
-- WHAT THIS CHANGES.
--   1. fn_it_digest_hold_ends(created_at): the latest moment the digest can still legitimately hold a
--      request -- the first 19:00 Dubai at least 24 h after it was raised, plus the delivery duty's 2 h.
--   2. fn_it_duties: the delivery duty skips a request while the digest legitimately holds it, and a NEW
--      duty, handoff_sla, raises 'duty:handoff_sla:<type>:<seat>:<state>' when any handoff is
--        unanswered -- no reply from the receiving seat past its seat_handoff_kind.reply_within, or
--        unclosed   -- answered, but the originator has not closed it past the window: an it.finding
--                      whose finding has cleared (the parked-at-learning shape above), or any other type
--                      24 h past its window. An it.finding whose finding is still OPEN is not late: the
--                      finding itself is tracked, escalated and digested.
--      delivery.request stays the delivery duty's. Everything else in fn_it_duties is byte-identical to
--      the_it_engineer_runs_its_duties_every_hour.sql (live matched it on 22 Sep 07:20Z).
--   3. it_playbook 'handoff_sla' with a typical_cause measured above, so a cleared SLA finding closes its
--      own loop instead of parking at the same gate it reports on; and dependency_advisory gains the
--      typical_cause its four 21 Sep occurrences measured, so that class stops parking.
--   4. fn_it_loop_reverify completes the 'it_loop:<id>' CEO report of any it.finding handoff that is
--      already done -- including one closed by fn_it_attach_learning. Otherwise unchanged from
--      the_it_learning_gate_closes_what_the_playbook_already_knows.sql.
--
-- WHAT THIS DOES NOT CHANGE. The learning gate (trigger z62) is NOT lowered: a class nobody has
-- explained still waits for a human -- but the wait is now a finding with an owner, not silence.
-- It does not close the 29 or the 2: every_parked_it_handoff_of_22_september_is_closed_by_its_exact_id.sql
-- does that row by row, and must be applied AFTER this file (it checks for it).
--
--   node scripts/apply_sql.mjs scripts/sql/every_handoff_is_answered_within_its_window.sql --apply --ddl

-- ── 1. HOW LONG THE IT DIGEST MAY HOLD A REQUEST ─────────────────────────────────────────────────
-- 19:00 is c_hour inside fn_customer_support_sends_the_it_digest; the 24 h is its "still young" rule
-- (a fault newer than a day is judged the next evening). ponytail: the hour is repeated here, not read
-- from the digest; if the digest's hour ever moves, move this with it.
create or replace function public.fn_it_digest_hold_ends(p_created_at timestamptz)
returns timestamptz language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select ((date_trunc('day', (p_created_at + interval '24 hours') at time zone 'Asia/Dubai')
           + interval '19 hours'
           + case when ((p_created_at + interval '24 hours') at time zone 'Asia/Dubai')::time > time '19:00'
                  then interval '1 day' else interval '0' end)
          at time zone 'Asia/Dubai') + interval '2 hours';
$fn$;
revoke execute on function public.fn_it_digest_hold_ends(timestamptz) from public, anon, authenticated;

-- ── 2. WHICH HANDOFFS ARE LATE, GROUPED SO ONE CAUSE IS ONE FINDING ──────────────────────────────
-- One item per (type, receiving seat, state), not per handoff: 29 rows parked for one reason are one
-- fault, and 29 findings would each open a loop of their own. p_include_demo exists for the check's
-- rolled-back ZZ DEMO fixture only; the duty always calls it without.
create or replace function public.fn_it_handoff_sla_items(p_include_demo boolean default false)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with h as (
    select a.id, a.agent, a.created_at, a.detail->>'type' t, a.detail ? 'replied_at' replied,
           coalesce(k.reply_within, interval '1 hour') w,
           f.closed_at f_closed,
           (f.issue_key is null or f.closed_at is not null
            or f.started_at > (a.detail->>'occurrence_started_at')::timestamptz) cleared
      from public.agent_actions a
      left join public.seat_handoff_kind k
        on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
      left join public.it_engineer_finding f
        on a.detail->>'type' = 'it.finding' and f.issue_key = a.detail->>'issue_key'
     where a.kind = 'handoff' and a.status in ('pending', 'failed')
       and a.detail->>'type' <> 'delivery.request'
       and (p_include_demo or (a.title not ilike '%ZZ DEMO%' and coalesce(a.detail->>'demo', 'false') <> 'true'))
  ), late as (
    select h.*, case
        when not h.replied and now() > h.created_at + h.w then 'unanswered'
        when h.replied and h.t = 'it.finding' and h.cleared
             and now() > greatest(h.created_at, coalesce(h.f_closed, h.created_at)) + h.w then 'unclosed'
        -- ponytail: other originator-closed types get a flat 24 h past their window, because
        -- fn_originators_reverify_handoffs escalates them to the CEO at the window first. Per-type
        -- rules belong in seat_handoff_kind if one of them ever needs a different allowance.
        when h.replied and h.t <> 'it.finding' and now() > h.created_at + h.w + interval '24 hours' then 'unclosed'
      end state
      from h)
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', g.t || ':' || g.agent || ':' || g.state,
           'owner_seat', case when g.state = 'unanswered' and g.agent in ('ceo', 'customer_support', 'sales_engineer', 'accountant')
                              then g.agent else 'ceo' end,
           'subject', 'agent_actions',
           'title', g.n || ' ' || g.t || ' handoff(s) to ' || g.agent
                    || case g.state when 'unanswered' then ' have had no reply'
                       else ' were answered but never closed by the seat that sent them' end
                    || ' past the ' || g.w || ' window; the oldest is #' || g.oldest_id || ' from '
                    || to_char(g.oldest_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
           'blast', 'agent_facing', 'affected', g.n,
           'evidence', jsonb_build_object('state', g.state, 'type', g.t, 'seat', g.agent, 'reply_within', g.w::text,
                                          'handoff_ids', g.ids, 'oldest_at', g.oldest_at,
                                          'look_at', 'select id, detail, evidence from public.agent_actions where id in (<handoff_ids>)'))
           order by g.t, g.agent, g.state), '[]'::jsonb)
    from (select t, agent, state, min(w) w, count(*) n, min(id) oldest_id, min(created_at) oldest_at,
                 jsonb_agg(id order by id) ids
            from late where state is not null group by t, agent, state) g;
$fn$;
revoke execute on function public.fn_it_handoff_sla_items(boolean) from public, anon, authenticated;

-- ── 3. THE PLAYBOOK ─────────────────────────────────────────────────────────────────────────────
insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values
  ('handoff_sla', 'duty:handoff_sla:',
   'Read the handoffs named in the finding. An unanswered one is its receiving seat''s handler failing or missing (seat_handoff_kind.handler). An unclosed it.finding is the learning gate: record the cause, fix and regression check with fn_it_attach_learning, or give the class a measured typical_cause in it_playbook so the loop closes itself. The duty closes the finding when no handoff is late.',
   null, null,
   'fn_it_duties duty handoff_sla (fn_it_handoff_sla_items), every hourly tick; scripts/checks/every_handoff_is_answered_within_its_window.test.mjs',
   'A handoff sat past its reply window with nobody holding the next move. Measured 22 Sep 2026: all 29 then late were it.finding handoffs whose seat had replied and whose finding had cleared, parked by fn_it_loop_reverify at awaiting_learning because no it_playbook class with a typical_cause covered their keys -- a branch with no clock and no addressee, so they waited 1 to 8 days unseen.',
   'ceo')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix, remedy = excluded.remedy,
  regression_check = excluded.regression_check, typical_cause = excluded.typical_cause;

-- Measured from the four occurrences' own close note (21 Sep 2026), not from the class name.
update public.it_playbook
   set typical_cause = 'A published npm advisory matched a version pinned in package-lock.json. Measured 21 Sep 2026: next 1193676 (critical), postcss 1117015, sharp 1124066 and nanoid 1139427 (high) against the lockfile on main; #776 bumped all four and npm audit --package-lock-only then read 0 at every severity.'
 where failure_class = 'dependency_advisory' and coalesce(btrim(typical_cause), '') = '';

-- ── 4. THE DUTIES ───────────────────────────────────────────────────────────────────────────────
-- Unchanged from the_it_engineer_runs_its_duties_every_hour.sql except duty 4 (the digest hold) and the
-- new handoff_sla duty after it.
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
              and not (a.detail ? 'loop') and a.title not ilike '%ZZ DEMO%'
              -- 22 Sep 2026: a founder-bound request customer_support holds for the 19:00 Dubai IT digest
              -- is waiting on a schedule, not lost. It is late only once the digest could have taken it.
              and not (a.status = 'pending' and a.evidence->>'digest' = 'pending'
                       and now() < public.fn_it_digest_hold_ends(a.created_at)) loop
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

  -- ── 4b. EVERY HANDOFF IS ANSWERED ──
  -- Reads: every pending handoff against its seat_handoff_kind.reply_within (every_handoff_is_answered_
  -- within_its_window.sql). Cannot see: a conversation that was never started -- only one that stalled.
  v_out := v_out || jsonb_build_object('handoff_sla', public.fn_it_duty_settle('handoff_sla', public.fn_it_handoff_sla_items()));

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

-- ── 4c. RE-VERIFY ────────────────────────────────────────────────────────────────────────────────
-- Unchanged from the_it_learning_gate_closes_what_the_playbook_already_knows.sql except the report sweep
-- before the loop and reports_completed in the result.
create or replace function public.fn_it_loop_reverify()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; f public.it_engineer_finding; v_window interval; v_rep jsonb; v_cleared boolean;
  n_closed int := 0; n_esc int := 0; n_wait int := 0; n_playbook int := 0; v_class text; n_reports int := 0;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  -- Review finding, 18 Sep 2026: with no such row v_window is null, `now() > created_at + null` is
  -- null, and EVERY handoff fell quietly into 'waiting' -- the loop would never escalate again and
  -- would say nothing about why. A missing conversation row is a configuration fault, not a default.
  if v_window is null then
    raise exception 'fn_it_loop_reverify: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  -- 22 Sep 2026: a handoff closed anywhere but the close branch below -- fn_it_attach_learning is the
  -- one other door -- left its CEO report 'accepted' for good. The report follows its handoff here.
  update public.support_ceo_report r
     set status = 'completed', completed_at = now(),
         completion_note = 'IT engineer re-verified: handoff ' || a.id || ' is closed ('
           || coalesce(a.evidence->>'verdict', 'learning recorded by ' || coalesce(a.evidence->>'learning_recorded_by', 'an unnamed recorder')) || ').'
    from public.agent_actions a
   where r.status = 'accepted' and r.idempotency_key ~ '^it_loop:[0-9]+$'
     and a.id = substr(r.idempotency_key, 9)::bigint and a.kind = 'handoff' and a.status = 'done';
  get diagnostics n_reports = row_count;

  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    -- The occurrence this loop tracked is over when the finding is closed, or when it has since
    -- closed and reopened (a later started_at is a different occurrence with its own loop).
    v_cleared := f.issue_key is null or f.closed_at is not null
                 or f.started_at > (h.detail->>'occurrence_started_at')::timestamptz;

    if v_cleared then
      -- A new bug that has cleared needs what was learned (trigger z62). Where the playbook already
      -- covers this failure class, the IT engineer records it from there and closes now; where it
      -- does not, the handoff waits for a human, which is what the gate is for.
      v_class := public.fn_it_learning_from_playbook(h.id);
      if v_class is not null then n_playbook := n_playbook + 1; end if;
    end if;

    if v_cleared and exists (select 1 from public.it_incident i where i.handoff_id = h.id
                              and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = ''
                                   or coalesce(btrim(i.regression_check), '') = ''
                                   or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = ''))) then
      if not (h.detail ? 'awaiting_learning') then
        update public.agent_actions set detail = detail || jsonb_build_object('awaiting_learning', now()) where id = h.id;
        update public.it_incident set ended_at = coalesce(f.closed_at, now()), updated_at = now() where handoff_id = h.id and ended_at is null;
      end if;
      n_wait := n_wait + 1;
    elsif v_cleared then
      update public.it_incident set ended_at = coalesce(ended_at, f.closed_at, now()), updated_at = now() where handoff_id = h.id;
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', coalesce(f.close_note, 'the finding is no longer open'),
        'learning_from_playbook', v_class,
        'reply_before_close', h.detail ? 'replied_at'));
      perform set_config('qd.handoff_closer', '', true);
      update public.support_ceo_report
         set status = 'completed', completed_at = now(),
             completion_note = 'IT engineer re-verified: ' || coalesce(f.close_note, 'the finding is no longer open') || ' (handoff ' || h.id || ').'
       where idempotency_key = 'it_loop:' || h.id and status = 'accepted';
      n_closed := n_closed + 1;
    elsif not (h.detail ? 'escalated_report_id') and now() > h.created_at + v_window then
      v_rep := public.fn_support_report_to_ceo(
        'it_loop:' || h.id,
        case when h.detail->>'severity' = 'critical' then 'critical' else 'serious' end,
        'Still broken after ' || h.agent || '''s reply window: ' || left(coalesce(h.detail->>'title', h.detail->>'issue_key'), 160),
        jsonb_build_object('handoff_id', h.id, 'issue_key', h.detail->>'issue_key', 'seat', h.agent,
                           'reply', h.evidence, 'finding', to_jsonb(f)),
        jsonb_build_array(jsonb_build_object('action', 'handed to ' || h.agent, 'handoff_id', h.id,
                                             'at', h.created_at, 'replied_at', h.detail->>'replied_at')),
        'Decide the remedy, or record that this is a new bug for the founder. The IT engineer keeps re-checking and closes the loop only when the finding is gone.',
        p_review_in => interval '2 hours', p_source_agent => 'it_engineer');
      if not coalesce((v_rep->>'ok')::boolean, false) then
        raise exception 'fn_it_loop_reverify: the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
      end if;
      update public.agent_actions
         set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
       where id = h.id;
      perform public.fn_ceo_it_escalation_decide((v_rep->>'report_id')::bigint);
      n_esc := n_esc + 1;
    else
      n_wait := n_wait + 1;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'escalated', n_esc, 'waiting', n_wait, 'learned_from_playbook', n_playbook,
                            'reports_completed', n_reports);
end $fn$;
revoke execute on function public.fn_it_loop_reverify() from public, anon, authenticated;

-- ── 5. PROBE: READ-ONLY, ONE VERDICT ROW ─────────────────────────────────────────────────────────
-- This file defines routines, so the probe must not raise (a raise would roll them back). It writes
-- nothing, so it cannot reach anyone. The write paths are proved in a rolled-back transaction by
-- scripts/checks/every_handoff_is_answered_within_its_window.test.mjs.
with c as (
  select public.fn_it_digest_hold_ends(timestamptz '2026-09-22 02:30:53+00') = timestamptz '2026-09-23 17:00:00+00' same_day_slot,
         public.fn_it_digest_hold_ends(timestamptz '2026-09-22 16:00:00+00') = timestamptz '2026-09-24 17:00:00+00' next_day_slot,
         jsonb_typeof(public.fn_it_handoff_sla_items()) = 'array' items_is_array,
         (select prosrc like '%fn_it_digest_hold_ends%' and prosrc like '%fn_it_handoff_sla_items%'
            from pg_proc where oid = 'public.fn_it_duties(jsonb)'::regprocedure) duties_live,
         (select prosrc like '%reports_completed%' from pg_proc where oid = 'public.fn_it_loop_reverify()'::regprocedure) reverify_live,
         exists (select 1 from public.it_playbook where failure_class = 'handoff_sla' and coalesce(btrim(typical_cause), '') <> '') playbook_row,
         (public.fn_it_playbook_for('duty:handoff_sla:it.finding:ceo:unclosed')).failure_class = 'handoff_sla' playbook_matches,
         jsonb_array_length(public.fn_it_handoff_sla_items()) late_groups)
select case when same_day_slot and next_day_slot and items_is_array and duties_live and reverify_live
                 and playbook_row and playbook_matches then 'PROBE OK' else 'PROBE FAILED' end verdict, c.*
  from c;
