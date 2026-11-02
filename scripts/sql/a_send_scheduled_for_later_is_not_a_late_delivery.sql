-- A SEND SCHEDULED FOR LATER IS NOT A LATE DELIVERY, AND THE CLEARED DELIVERY FINDINGS CLOSE THEMSELVES.
-- Seat: it_engineer, for customer_support's queue. 2 Nov 2026, founder ledger 1436/1447, audit section B.
--
-- MEASURED 1-2 Nov 2026 (production, read-only): 970 pending it.finding handoffs; 758 parked at awaiting_learning, of which
-- 727 are duty:delivery:request:<id> whose finding is ALREADY CLOSED and whose request has its loop verdict. They park
-- because it_playbook.delivery_request_unconfirmed has a null typical_cause, and fn_it_playbook_for refuses a class with
-- no cause, so fn_it_loop_reverify can never record the learning. Nothing here closes a handoff: the loop closes each one,
-- by its own finding, once its class has a cause. The 18 findings still open are 18 supplier_invite rows queued with
-- not_before 4 Nov: on a schedule, not lost.
--
-- Prevented by: scripts/checks/nothing_a_person_sends_us_waits.test.mjs
update public.it_playbook
   set typical_cause = 'Measured on 727 occurrences, 12 Oct - 30 Oct 2026: every request later reached a loop verdict and its finding closed. '
        || 'They were sends slower than the two-hour window (a batch scheduled through the day, seeds, digests held to their hour) rather than lost mail.'
 where failure_class = 'delivery_request_unconfirmed' and coalesce(btrim(typical_cause), '') = '';

CREATE OR REPLACE FUNCTION public.fn_it_duties(p_r jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
              -- 2 Nov 2026: a send whose not_before is ahead (18 queued invitations held to 4 Nov) is on a schedule, not lost.
              and not exists (select 1 from public.notifications n where n.id = (a.evidence->>'notification_id')::bigint and n.not_before > now())
              -- 22 Sep 2026: a founder-bound request customer_support holds for the 19:00 Dubai IT digest
              -- is waiting on a schedule, not lost. It is late only once the digest could have taken it.
              and not (a.status = 'pending' and a.evidence->>'digest' = 'pending'
                       -- 29 Sep 2026 (incident 484): the digest ages a new bug by its FINDING's started_at
                       -- ("still young: judged again tomorrow"), and a finding that re-opened restarts that
                       -- clock. Handoff 80605 was created 23 Sep 12:31Z for duty:handoff_sla:it.finding:ceo:unclosed;
                       -- the finding re-opened 24 Sep 07:00Z, so the 24 Sep digest held it as young and took it
                       -- on 25 Sep, while this duty, timing from the handoff, called it late at 29 hours. The
                       -- hold now runs from the later of the two clocks, the one the digest actually obeys.
                       and now() < public.fn_it_digest_hold_ends(greatest(a.created_at, coalesce(
                         (select f.started_at from public.it_engineer_finding f
                           where f.issue_key = regexp_replace(a.detail->>'dedupe_key', '^it_new_bug:', '')
                             and f.closed_at is null), a.created_at)))) loop
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

  -- ── 4c. EVERY PACK ROW HAS ITS MULTILINGUAL VECTOR ──
  -- Reads: fn_pack_rows_without_fresh_ml_vector, the eligible verified_pack rows of the six seat tables whose
  -- ml vector is missing or stale for over an hour since their load. Cannot see: why the queue is slow.
  v_items := '[]'::jsonb;
  for x in select * from public.fn_pack_rows_without_fresh_ml_vector(interval '1 hour') p where p.overdue > 0 loop
    v_items := v_items || jsonb_build_object('item', x.src, 'owner_seat', 'it_engineer', 'subject', 'knowledge_ml',
      'title', x.overdue || ' ' || x.src || ' pack rows have had no fresh multilingual vector for over an hour',
      'blast', 'agent_facing', 'affected', x.overdue,
      'evidence', jsonb_build_object('pack_rows', x.pack_rows, 'without_fresh', x.without_fresh, 'overdue', x.overdue,
        'oldest_due', x.oldest_due, 'remedy', 'gh workflow run ml-embed-backfill.yml; fn_ml_embed_claim serves the rows'));
  end loop;
  v_out := v_out || jsonb_build_object('pack_ml_vectors', public.fn_it_duty_settle('pack_ml_vectors', v_items));

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
  -- THE FOUNDER'S STANDING DEMO IS NOT A LEFTOVER (22 Sep 2026, PR #831; see the file header).
  for x in select 'customers' t, count(*) n, (array_agg(c.id::text order by c.created_at))[1:10] ids from public.customers c
            where (c.is_demo or c.email like 'qd-%@example.invalid') and c.created_at < now() - interval '6 hours'
              and coalesce(c.email, '') not like 'qd-founderdemo-%'
           union all
           select 'leads', count(*), (array_agg(l.id::text order by l.created_at))[1:10] from public.leads l
            where (l.is_demo or l.email like 'qd-%@example.invalid') and l.created_at < now() - interval '6 hours'
              and coalesce(l.email, '') not like 'qd-founderdemo-%' loop
    -- Only a run still in progress excuses leftovers. Measured on the proof: four e2e windows and one
    -- from 5 Sep were never closed, and "any open window" silenced this check for good.
    if x.n > 0 and not exists (select 1 from public.rehearsal_window w
                                where w.ended_at is null and w.started_at > now() - interval '6 hours') then
      v_items := v_items || jsonb_build_object('item', x.t, 'owner_seat', 'ceo', 'subject', 'e2e_harness',
        'title', x.n || ' demo ' || x.t || ' row(s) outlived their run by more than six hours',
        'blast', 'internal', 'affected', 1, 'demo', true,
        'evidence', jsonb_build_object('table', x.t, 'rows', x.n, 'ids', to_jsonb(x.ids), 'purge', 'node scripts/e2e/run.mjs --purge-tag <tag>'));
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
end $function$;

select case when (select failure_class from public.fn_it_playbook_for('duty:delivery:request:1')) is distinct from 'delivery_request_unconfirmed'
            then 'PROBE FAILED: the delivery class still has no cause' else 'PROBE OK' end as verdict;
