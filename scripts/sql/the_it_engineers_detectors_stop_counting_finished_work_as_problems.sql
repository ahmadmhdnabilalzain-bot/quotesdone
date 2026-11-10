-- Seat: it_engineer
-- THE IT ENGINEER'S DETECTORS STOP COUNTING FINISHED WORK AS PROBLEMS (10 Nov 2026).
--
-- The founder brief says "The IT engineer works on N open technical problems" and N had swung between 160 and 833
-- (28 Oct 512, 2 Nov 833, 3 Nov 486, 4 Nov 529). A read-only triage of production (htdblwldjkcgjvmqkbeh, 10 Nov) found
-- four detectors that keep a finding open for work that is finished or already recovered. Each change below is the
-- smallest one that stops that, starting from the LIVE definition read with pg_get_functiondef on 10 Nov.
--
-- 1. fn_it_duties, duty "delivery". A delivery.request handoff older than two hours without detail.loop is a finding.
--    The handoffs the delivery loop closes with "the queued notification was deleted afterwards" are status done,
--    result record_removed, and never carry a loop key, so each one became its own finding. MEASURED 10 Nov: 16 open
--    duty:delivery:request findings, all 16 status done / result record_removed; the current logic raises 23 handoffs
--    (16 done + 7 pending), the new logic raises the 7 pending. 2,757 of the 2 to 4 Nov burst were this same misfire.
--    A handoff that is done with a result other than a failure result is finished work. A failure result
--    (not_sent, no_response_confirmation, sent_unconfirmed) is still raised.
--
-- 2. fn_it_slo_judge, the 30-day term of budget_breach. It was "30-day bad rate above 0.1 %" on its own, a lifetime
--    average: with zero slow runs in the last 24 h a recovered function could not clear until its bad days left the
--    window (early December). The 30-day term now also needs the 24-hour burn rate above 1 (the budget being spent
--    faster than it accrues), the usual multi-window rule. MEASURED 10 Nov, evaluated over the same agent_runs the
--    duty reads: customer_api 656 bad of 6,652 runs in 30 days, 0 runs and 0 bad in 24 h, budget_breach true before and
--    false after; the same for the other six open duty:latency_slo findings (customer_portal, kyc, messages_api,
--    project_api, supplier_api, supplier_portal). A function that is still failing today (24 h burn above 1) and
--    has a bad 30 days still breaches. The 24 h burn-rate term (>= 2, at least 5 runs) is unchanged.
--
-- 3. fn_accountant_reveal_reconcile_record, reveal_reconcile. The hourly sweep re-reads Stripe's window and writes
--    every unmatched payment again, so one test-mode payment on a real quote was recorded 139 times (attempts 139 on
--    all 7 open non-demo items; 46 open items have attempts >= 10). After 10 attempts an item that is still open as
--    failed, test_mode_not_demo or refunded_unrecorded is left as it is: the finding stays open (it is built from the
--    unresolved item, not from this write) and the sweep stops rewriting it. A later result that RESOLVES or changes
--    its meaning (recovered, refunded, second_payment) is still written, and the "recorded elsewhere" update at the
--    end is untouched. Ten is the point where an hourly retry has had ten hours: a payment Stripe could not return or a
--    quote that was not there ten hours ago is not going to appear on the eleventh; a transient fault clears in one or two.
--    The existing 7 findings are NOT closed or altered here: the founder decides them. This stops the database write;
--    the accountant function still reads Stripe each hour, which is outside this file.
--
-- 4. credential_rotations_per_run, 3 -> 15. It is a data row in it_threshold, not code (duty 15 in
--    the_it_engineer_takes_on_seven_more_duties.sql reads it as a LIMIT). 43 credentials created together on 3 Aug
--    crossed the 90 + 7 day limit together on 9 Nov; MEASURED 10 Nov: 45 are eligible to rotate now, the duty rotates 3
--    a day (25 retired, 3 in overlap), so the tail was 15 days. SAFE because the rotation path has an overlap window:
--    fn_it_credential_rotate writes the new secret to app_secrets (every caller reads it at call time), keeps the old
--    credential valid for credential_overlap_hours (24) plus two cadences of the duty (2 days), and
--    fn_it_credential_reverify retires the old one only when it has not been presented since the rotation, otherwise
--    holds it, extends it and raises a finding. 28 rotations have run, 25 retired and none held. At 15 a run, a fault in
--    one caller touches at most 15 of 99 credentials, each still accepted on its old secret for at least 3 days.
--    45 eligible / 15 = 3 days.
--
-- Prevented by: scripts/checks/the_it_engineers_detectors_stop_counting_finished_work_as_problems.test.mjs
--
-- Routines keep their live grants (create or replace preserves the ACL), owner and pinned search_path; the revokes
-- below restate them.

-- ── 2. The SLO judge ──
create or replace function public.fn_it_slo_judge(p_runs_24h integer, p_p95_ms numeric, p_budget_ms integer, p_bad_24h integer, p_runs_30d integer, p_bad_30d integer)
 returns jsonb
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  -- MIN_RUNS 5, SLO 99.9 % (error budget 0.001), burn-rate alarm 2x. One place for every threshold.
  select jsonb_build_object(
    'p95_breach',   coalesce(p_runs_24h, 0) >= 5 and p_p95_ms > p_budget_ms,
    'small_sample', coalesce(p_runs_24h, 0) between 5 and 29,
    'availability', case when p_runs_30d > 0 then round(1 - p_bad_30d::numeric / p_runs_30d, 4) end,
    'budget_spent', case when p_runs_30d > 0 then round((p_bad_30d::numeric / p_runs_30d) / 0.001, 2) end,
    'burn_rate_24h', case when p_runs_24h > 0 then round((p_bad_24h::numeric / p_runs_24h) / 0.001, 2) end,
    'budget_breach', (case when coalesce(p_runs_24h, 0) >= 5 then p_bad_24h::numeric / p_runs_24h / 0.001 >= 2 else false end)
                     -- 10 Nov 2026: the 30-day term counts only while the last 24 h is also burning above 1x. On its own it is a
                     -- lifetime average and a recovered function could not clear for a month.
                     or (case when coalesce(p_runs_30d, 0) >= 5 and coalesce(p_runs_24h, 0) > 0
                              then p_bad_30d::numeric / p_runs_30d > 0.001 and p_bad_24h::numeric / p_runs_24h / 0.001 > 1
                              else false end));
$function$;

revoke execute on function public.fn_it_slo_judge(integer, numeric, integer, integer, integer, integer) from public, anon, authenticated;

-- ── 3. The reveal reconcile record ──
create or replace function public.fn_accountant_reveal_reconcile_record(p_run_id bigint, p_r jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_run bigint; x jsonb; n_kept int := 0; n_refused int := 0; n_resolved int := 0; v_demo boolean; v_qid uuid;
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if jsonb_typeof(p_r) is distinct from 'object' or jsonb_typeof(coalesce(p_r->'outcomes', '[]'::jsonb)) is distinct from 'array' then
    raise exception 'fn_accountant_reveal_reconcile_record(run, readings): readings must be an object with an outcomes array';
  end if;
  select id into v_run from public.accountant_reveal_reconcile_run where id = p_run_id;
  if v_run is null then   -- a call the duty did not dispatch (the founder, by hand): it is a run of its own
    insert into public.accountant_reveal_reconcile_run (window_days)
    values (greatest(1, least(90, coalesce(nullif(p_r->>'days', '')::int, 30)))) returning id into v_run;
  end if;
  update public.accountant_reveal_reconcile_run
     set reported_at = now(),
         result = (p_r - 'outcomes') || jsonb_build_object('reported', jsonb_array_length(coalesce(p_r->'outcomes', '[]'::jsonb)))
   where id = v_run;

  for x in select e from jsonb_array_elements(coalesce(p_r->'outcomes', '[]'::jsonb)) e loop
    if coalesce(x->>'key', '') !~ '^(in|pi)_[A-Za-z0-9_]+$' or coalesce(btrim(x->>'quote_id'), '') = ''
       or coalesce(x->>'outcome', '') not in ('recovered', 'second_payment', 'refunded', 'refunded_unrecorded', 'failed', 'deferred', 'test_mode_not_demo')
       or coalesce(x->>'source', '') not in ('invoice', 'payment_intent') then
      n_refused := n_refused + 1;   -- 'recorded' (a plain match) never needs a row; anything malformed is refused, not guessed
      continue;
    end if;
    v_qid := case when x->>'quote_id' ~ c_uuid then (x->>'quote_id')::uuid end;
    -- DEMO: a test-mode payment, an email the one demo rule names, or a customer the database marks is_demo.
    -- 'test_mode_not_demo': a test payment whose quote is not provably a demo account's. It reaches the findings,
    -- unless Stripe's own customer e-mail is a demo address (fn_is_demo_email, the identity that picks the Stripe test
    -- key, #1835): the e2e teardown deletes a demo quote while its paid test invoice stays in the window, and that is
    -- demo, not a finding.
    v_demo := case when x->>'outcome' = 'test_mode_not_demo' then public.fn_is_demo_email(x->>'customer_email')
      else (not coalesce((x->>'livemode')::boolean, false)
           or public.fn_is_demo_email(x->>'customer_email')
           or exists (select 1 from public.customers c where c.is_demo and c.id::text = x->>'customer_id')
           or exists (select 1 from public.quotes q join public.inquiries iq on iq.id = q.inquiry_id
                        join public.customers c on c.id = iq.customer_id where q.id = v_qid and c.is_demo)) end;
    insert into public.accountant_reveal_reconcile_item as it (key, livemode, source, quote_id, invoice_id, payment_intent,
        customer_id, customer_email, amount_fils, currency, paid_at, demo, outcome, transaction_id, error, last_run_id, resolved_at)
    values (x->>'key', coalesce((x->>'livemode')::boolean, false), x->>'source', x->>'quote_id', nullif(x->>'invoice_id', ''),
        nullif(x->>'payment_intent', ''), nullif(x->>'customer_id', ''), lower(nullif(x->>'customer_email', '')),
        nullif(x->>'amount_fils', '')::bigint, nullif(x->>'currency', ''),
        case when x->>'paid_at' ~ '^[0-9]+$' then to_timestamp((x->>'paid_at')::bigint) end,
        v_demo, x->>'outcome', case when x->>'transaction_id' ~ c_uuid then (x->>'transaction_id')::uuid end,
        left(nullif(x->>'error', ''), 1000), v_run,
        case when x->>'outcome' in ('recovered', 'refunded') then now() end)
    -- 'deferred' says only "not looked at this run": it never overwrites what an earlier run found (failed, second payment).
    on conflict (key) do update set
        outcome = case when excluded.outcome = 'deferred' and it.resolved_at is null then it.outcome else excluded.outcome end,
        error = case when excluded.outcome = 'deferred' and it.resolved_at is null then it.error else excluded.error end,
        demo = excluded.demo,
        payment_intent = coalesce(excluded.payment_intent, it.payment_intent),
        customer_email = coalesce(excluded.customer_email, it.customer_email),
        transaction_id = coalesce(excluded.transaction_id, it.transaction_id),
        attempts = it.attempts + 1, last_seen_at = now(), last_run_id = excluded.last_run_id,
        resolved_at = case when excluded.outcome in ('recovered', 'refunded') then coalesce(it.resolved_at, now())
                           when excluded.outcome = 'deferred' then null end
    -- 10 Nov 2026: after 10 attempts (ten hourly sweeps) an item still open as failed / test_mode_not_demo /
    -- refunded_unrecorded is not rewritten again. Its finding stays open, built from the unresolved item. A result
    -- that resolves it or changes what it is (recovered, refunded, second_payment) is still written.
    where not (it.resolved_at is null and it.attempts >= 10
               and it.outcome in ('failed', 'test_mode_not_demo', 'refunded_unrecorded')
               and excluded.outcome in ('failed', 'test_mode_not_demo', 'refunded_unrecorded', 'deferred'));
    n_kept := n_kept + 1;
  end loop;

  -- A payment the books now hold by another path (the webhook, a by-hand recording) is resolved, whatever this run saw.
  update public.accountant_reveal_reconcile_item i
     set outcome = 'recorded_elsewhere', resolved_at = now(), transaction_id = t.id
    from public.transactions t
   where i.resolved_at is null and i.outcome in ('failed', 'refunded_unrecorded', 'deferred')
     and ((i.invoice_id is not null and t.stripe_invoice_id = i.invoice_id) or (i.payment_intent is not null and t.payment_ref = i.payment_intent));
  get diagnostics n_resolved = row_count;

  return jsonb_build_object('run', v_run, 'kept', n_kept, 'refused', n_refused, 'resolved_elsewhere', n_resolved,
    'findings', public.fn_accountant_reveal_reconcile_findings());
end
$function$;

revoke execute on function public.fn_accountant_reveal_reconcile_record(bigint, jsonb) from public, anon, authenticated;

-- ── 4. The rotation cap ──
update public.it_threshold
   set value = 15,
       basis = 'At most fifteen rotations a run (one run a day). Each keeps its old secret valid for the overlap window and two more cadences, and reverify holds any still in use, so a fault in one caller touches at most fifteen credentials and none is cut off. Was 3 until 10 Nov 2026, when 45 credentials created in one batch were due together.'
 where key = 'credential_rotations_per_run';

-- ── 1. The IT duties: delivery ──
create or replace function public.fn_it_duties(p_r jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
              -- 10 Nov 2026: a request already DONE with a result that is not a failure is finished work. 16 handoffs closed
              -- as record_removed (the queued notification was deleted afterwards) carry no loop key and each became a
              -- finding; the 2 to 4 Nov burst was 2,757 of them. A failure result is still raised.
              and not (a.status = 'done' and a.detail->>'result' is not null
                       and a.detail->>'result' not in ('not_sent', 'no_response_confirmation', 'sent_unconfirmed'))
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
end
$function$;

revoke execute on function public.fn_it_duties(jsonb) from public, anon, authenticated;

-- ── Probe: a verdict row, reads only, never raises ──
-- Checks each of the four changes is live in what this file just defined, the judge's behaviour on the customer_api
-- numbers (656 bad of 6,652 in 30 days, none in 24 h), and that none of the three routines opened to a browser role.
select case
  when not coalesce((select prosrc like '%a.status = ''done'' and a.detail->>''result'' is not null%' from pg_proc
                      where oid = to_regprocedure('public.fn_it_duties(jsonb)')), false)
    then 'PROBE FAILED: fn_it_duties does not exclude finished delivery handoffs'
  when (public.fn_it_slo_judge(0, null, 2500, 0, 6652, 656)->>'budget_breach')::boolean is distinct from false
    then 'PROBE FAILED: a recovered function (30 d bad, 24 h clean) still breaches'
  when (public.fn_it_slo_judge(100, null, 2500, 5, 6652, 656)->>'budget_breach')::boolean is distinct from true
    then 'PROBE FAILED: a function still burning its budget no longer breaches'
  when not coalesce((select prosrc like '%it.attempts >= 10%' from pg_proc
                      where oid = to_regprocedure('public.fn_accountant_reveal_reconcile_record(bigint,jsonb)')), false)
    then 'PROBE FAILED: the reveal sweep still rewrites an item after 10 attempts'
  when (select value from public.it_threshold where key = 'credential_rotations_per_run') is distinct from 15
    then 'PROBE FAILED: credential_rotations_per_run is not 15'
  when exists (select 1 from pg_proc p
                where p.oid in (to_regprocedure('public.fn_it_duties(jsonb)'),
                                to_regprocedure('public.fn_it_slo_judge(integer,numeric,integer,integer,integer,integer)'),
                                to_regprocedure('public.fn_accountant_reveal_reconcile_record(bigint,jsonb)'))
                  and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')))
    then 'PROBE FAILED: a rewritten routine is executable by a browser role'
  else 'PROBE OK'
end as verdict;
