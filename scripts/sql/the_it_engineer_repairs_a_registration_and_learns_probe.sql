-- PROBE (pure, no DDL, aborted transaction; LOCAL DATABASE ONLY) for the four files of the self-healing path. Seat: it_engineer.
-- Run after, in the same rolled-back transaction: support_and_the_it_engineer_hand_a_fault_both_ways.sql,
-- a_code_defect_goes_to_the_engineer_session.sql, the_it_engineer_repairs_a_registration_and_learns.sql and
-- the_it_engineer_repairs_within_its_guardrails.sql (scripts/checks/the_it_engineer_repairs_a_registration_and_learns.test.mjs).
--
-- INCAPABLE OF REACHING A PERSON, not merely careful: it refuses to run unless app_secrets.project_ref is the local database's
-- seed ('localpg16localpg16lo', scripts/db/local_standins.sql), so on production it raises before it writes a row; its planted
-- people use the undeliverable top-level domain .qd-probe (not a demo domain, so the live path is the one exercised); every
-- net.http_post on the local database only queues a row; and it ends in raise exception, so every row it wrote rolls back.
--
-- What it plants and what PROBE OK needs (each line of the CHK names one):
--   A  a failed licence read (8 tries spent): raised once, re-read exactly once, closed when the reader succeeds, the person told
--      once, support.registration_rescued; a re-read while every licence route is open-circuit is refused.
--   A2 a licence read the family re-reads twice without success: one code defect remedy_exhausted.licence_read_rerun, the person
--      told once that it is being fixed; a second watch counts, never a second row.
--   B  an acceptance with no certificate: retried exactly once, closed when it lands; with no acceptance on record, refused.
--   C  a held registration: refused while the person is not talking to support; explained once (the exact item) once they are.
--   D  a mobile on two accounts: each owner told once, no account merged or deleted, the data decision handed to the CEO.
--   E  a code that never came: a fresh code sent once to the account's e-mail; when used, the report is told once and its
--      hand-over completed.
--   F  a job that is not registered is refused; a registered one runs once.
--   G  route failover: refused without a plan B; with one, the gate's answer is obeyed, and a failover past its hour is put back.
--   H  BURST: the same cause at 3 or more people opens one P1 defect.
--   I  RETURNS: a key fixed on two occurrences opens returns_after_fix.
--   J  an unmatched report becomes a P3 defect; claim, lease take-back, verified only after deployed, the people told; a verified
--      class that returns is reopened with its PR in history.
--   K  a demo report is not filed; a second report from one case in one hour is not filed.
--   L  guardrails: no lead deleted, no approval, no licence value, no ban changed; the four event kinds were emitted.
do $p$
declare
  v_ok boolean := true; v_fail text[] := '{}'; v jsonb; r jsonb; n int; n2 int; v_id bigint; v_d bigint; v_d2 bigint;
  l1 bigint; l2 bigint; l3 bigint; l4 bigint; l5 bigint; l6 bigint; l7 bigint; l8 bigint; l9 bigint; l10 bigint; c1 uuid;
  v_rep bigint; v_rep2 bigint; v_leads_before int; v_snap jsonb; v_snap_after jsonb; v_failover text; v_events jsonb;
begin
  if coalesce((select value from public.app_secrets where key = 'project_ref'), '') <> 'localpg16localpg16lo' then
    raise exception 'PROBE REFUSED: this probe runs only on the local database (project_ref is not the local seed)';
  end if;
  perform set_config('qd.duty_fixtures', '', true);
  -- what the local seeds do not hold and production does
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('support.root_cause', 'customer_support', 'it_engineer', 'probe stand-in', 'fn_seat_takes_support_root_cause', null, true,
          'scripts/sql/customer_support_finds_the_root_cause_each_week_and_measures_the_fix.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.app_secrets (key, value) values ('cred_fn_resilience_ping', 'local-not-a-secret'), ('publishable_key', 'local-not-a-key')
  on conflict (key) do nothing;
  -- the eight 1574 families are not on the local database: the dispatcher sees only the seven of 1705 here
  select count(*) into v_leads_before from public.leads;

  -- ── plant the people (idle 2 hours) ──
  insert into public.leads (company_name, claimed, claimed_by, email, licence_read_state, license_doc_path, licence_read_tries, licence_read_at,
                            portal_updated_at, created_at, trade_license_no, license_expiry)
  values ('Probe Licence One LLC', true, 'one@selfheal.qd-probe', 'one@selfheal.qd-probe', 'ours_failed', 'probe/one.pdf', 8, now() - interval '1 hour',
          now() - interval '2 hours', now() - interval '3 hours', 'P-1001', date '2027-01-01') returning id into l1;
  insert into public.leads (company_name, claimed, claimed_by, email, licence_read_state, license_doc_path, licence_read_tries, licence_read_at, portal_updated_at, created_at)
  values ('Probe Licence Two LLC', true, 'two@selfheal.qd-probe', 'two@selfheal.qd-probe', 'ours_failed', 'probe/two.pdf', 8, now() - interval '1 hour',
          now() - interval '2 hours', now() - interval '3 hours') returning id into l2;
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at)
  values ('Probe Certificate Three LLC', true, 'three@selfheal.qd-probe', 'three@selfheal.qd-probe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours')
  returning id into l3;
  insert into public.leads (company_name, claimed, claimed_by, email, portal_updated_at, created_at)
  values ('Probe No Acceptance Four LLC', true, 'four@selfheal.qd-probe', 'four@selfheal.qd-probe', now() - interval '2 hours', now() - interval '3 hours') returning id into l4;
  insert into public.leads (company_name, claimed, claimed_by, email, licence_gate_reason, approval_status, portal_updated_at, created_at)
  values ('Probe Held Five LLC', true, 'five@selfheal.qd-probe', 'five@selfheal.qd-probe', 'licence_expired', 'action_required', now() - interval '2 hours', now() - interval '3 hours')
  returning id into l5;
  insert into public.leads (company_name, claimed, claimed_by, email, phone_e164, portal_updated_at, created_at)
  values ('Probe Shared Mobile Six LLC', true, 'six@selfheal.qd-probe', 'six@selfheal.qd-probe', '+971559990001', now() - interval '2 hours', now() - interval '3 hours') returning id into l6;
  insert into public.leads (company_name, claimed, claimed_by, email, phone_e164, portal_updated_at, created_at)
  values ('Probe Shared Mobile Seven LLC', true, 'seven@selfheal.qd-probe', 'seven@selfheal.qd-probe', '+971559990001', now() - interval '2 hours', now() - interval '3 hours') returning id into l7;
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst Eight LLC', true, 'eight@selfheal.qd-probe', 'eight@selfheal.qd-probe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into l8;
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst Nine LLC', true, 'nine@selfheal.qd-probe', 'nine@selfheal.qd-probe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into l9;
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst Ten LLC', true, 'ten@selfheal.qd-probe', 'ten@selfheal.qd-probe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into l10;
  insert into public.customers (email, full_name) values ('cust@selfheal.qd-probe', 'Probe Customer') returning id into c1;
  insert into public.email_verifications (email, purpose, user_kind, expires_at, created_at)
  values ('cust@selfheal.qd-probe', 'signin', 'customer', now() - interval '20 minutes', now() - interval '30 minutes');
  select jsonb_agg(jsonb_build_object('id', id, 'a', approval_status, 'b', banned, 'n', trade_license_no, 'e', license_expiry, 'c', claimed_by) order by id) into v_snap
    from public.leads where id in (l1, l2, l3, l4, l5, l6, l7, l8, l9, l10);

  -- ── K: demo not filed; one per case per hour ──
  r := public.fn_support_hands_it_a_fault('email', 'email:probe-demo', 'en', 'customer', '[{"role":"customer","text":"ZZ DEMO broken"}]', 'zz@example.invalid');
  if coalesce((r->>'filed')::boolean, true) then v_fail := v_fail || 'K: a demo report was filed'; end if;
  r := public.fn_support_hands_it_a_fault('email', 'email:probe-cust', 'en', 'customer', '[{"role":"customer","text":"the code never came, write to me at x@y.ae"}]', 'cust@selfheal.qd-probe');
  v_rep := (r->>'report_id')::bigint;
  if not coalesce((r->>'filed')::boolean, false) or (r->>'handoff_id') is null then v_fail := v_fail || ('K: the fault was not filed with its hand-over: ' || r::text); end if;
  if exists (select 1 from public.support_fault_report where id = v_rep and turns::text ~ '@') then v_fail := v_fail || 'K: an address survived the mask'::text; end if;
  r := public.fn_support_hands_it_a_fault('email', 'email:probe-cust', 'en', 'customer', '[{"role":"customer","text":"again"}]', 'cust@selfheal.qd-probe');
  if coalesce((r->>'filed')::boolean, true) then v_fail := v_fail || 'K: a second report in one hour was filed'; end if;
  if not exists (select 1 from public.agent_actions where id = (select handoff_id from public.support_fault_report where id = v_rep)
                   and agent = 'it_engineer' and detail->>'type' = 'support.root_cause' and status = 'pending' and detail ? 'awaiting') then
    v_fail := v_fail || 'K: the hand-over is not waiting with the IT engineer';
  end if;

  -- ── refusals by direct call (no run recorded) ──
  r := public.fn_it_safe_fix_terms_certificate_retry('reg:stall:certificate:' || l4);
  if r->>'outcome' <> 'refused_by_guardrail' then v_fail := v_fail || ('B: a certificate with no acceptance was not refused: ' || r::text); end if;
  r := public.fn_it_safe_fix_held_registration_explain('reg:stall:held:' || l5);
  if r->>'outcome' <> 'refused_by_guardrail' then v_fail := v_fail || ('C: a held person not talking to us was written to: ' || r::text); end if;
  r := public.fn_it_safe_fix_stuck_job_rerun('reg:job_stalled:send_outbox');
  if r->>'outcome' <> 'refused_by_guardrail' then v_fail := v_fail || ('F: an unregistered job was re-run: ' || r::text); end if;
  r := public.fn_it_safe_fix_route_failover('reg:circuit_open:document_extraction');
  if r->>'outcome' <> 'refused_by_guardrail' then v_fail := v_fail || ('G: a failover with no plan B was not refused: ' || r::text); end if;
  -- every licence route open-circuit: a re-read is refused
  insert into public.model_policy (task_class, tier, model_primary, model_fallback) values ('document_extraction', 'probe', 'probe/primary', 'probe/fallback')
  on conflict do nothing;
  insert into public.llm_route_health (model_id, open_until) values ('probe/primary', now() + interval '10 minutes'), ('probe/fallback', now() + interval '10 minutes')
  on conflict (model_id) do update set open_until = excluded.open_until;
  r := public.fn_it_safe_fix_licence_read_rerun('reg:stall:licence_read:' || l1);
  if r->>'outcome' <> 'refused_by_guardrail' then v_fail := v_fail || ('A: a re-read ran while every route was open: ' || r::text); end if;
  -- G with a plan B: json_extraction (seeded) on a ladder whose two routes are open
  insert into public.model_policy (task_class, tier, model_primary, model_fallback) values ('json_extraction', 'probe', 'probe/primary', 'probe/fallback')
  on conflict do nothing;
  r := public.fn_it_safe_fix_route_failover('reg:circuit_open:json_extraction');
  v_failover := r->>'outcome';
  if v_failover = 'fixed' then
    if not exists (select 1 from public.model_policy where task_class = 'json_extraction' and model_fallback = 'anthropic/claude-sonnet-5.5') then v_fail := v_fail || 'G: the plan B is not on the ladder'; end if;
    update public.it_route_failover set started_at = now() - interval '2 hours', until = now() - interval '1 hour' where task_class = 'json_extraction';
  elsif not (v_failover = 'refused_by_guardrail' and r->>'why' like 'the paid-provider gate refuses%') then
    v_fail := v_fail || ('G: the failover neither landed nor was refused by the gate: ' || r::text);
  end if;
  update public.llm_route_health set open_until = null where model_id in ('probe/primary', 'probe/fallback');

  -- ── WATCH 1: raise and repair ──
  v := public.fn_it_registration_watch();
  if v_failover = 'fixed' and exists (select 1 from public.model_policy where task_class = 'json_extraction' and model_fallback <> 'probe/fallback') then
    v_fail := v_fail || 'G: a failover past its hour was not put back';
  end if;
  -- backdate this occurrence of A so a later return is a new occurrence (one transaction has one now())
  update public.it_engineer_finding set started_at = now() - interval '1 hour' where issue_key = 'reg:stall:licence_read:' || l1;
  update public.it_safe_fix_run set occurrence_started_at = now() - interval '1 hour' where issue_key = 'reg:stall:licence_read:' || l1;
  select count(*) into n from public.it_safe_fix_run where issue_key = 'reg:stall:licence_read:' || l1 and outcome = 'fixed';
  if n <> 1 then v_fail := v_fail || ('A: the licence was re-read ' || n || ' times on watch 1, not once'); end if;
  if not exists (select 1 from public.leads where id = l1 and licence_read_tries = 7) then v_fail := v_fail || 'A: the spent tries were not given one more'; end if;
  select count(*) into n from public.it_safe_fix_run where issue_key = 'reg:stall:certificate:' || l3 and outcome = 'fixed';
  if n <> 1 then v_fail := v_fail || ('B: the certificate was retried ' || n || ' times, not once'); end if;
  select count(*) into n from public.it_safe_fix_run where family = 'duplicate_mobile_guide' and outcome = 'fixed';
  if n <> 1 then v_fail := v_fail || ('D: the shared mobile was guided ' || n || ' times, not once'); end if;
  select count(*) into n from public.customer_support_voice_owed where stage = 'it.repair.dup_mobile';
  if n <> 2 then v_fail := v_fail || ('D: ' || n || ' owners told, not 2'); end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key like 'reg:dup\_mobile:%' and evidence->>'owner_seat' = 'ceo') then v_fail := v_fail || 'D: the data decision is not the CEO''s'; end if;
  select count(*) into n from public.it_safe_fix_run where family = 'code_resend_assist' and outcome = 'fixed';
  if n <> 1 then v_fail := v_fail || ('E: the code was resent ' || n || ' times, not once: ' || coalesce((select string_agg(coalesce(result->>'why', error, outcome), ' | ') from public.it_safe_fix_run where family = 'code_resend_assist'), 'no run')); end if;
  select count(*) into n from public.it_safe_fix_run where family = 'stuck_job_rerun' and issue_key = 'reg:job_stalled:agreement_resign' and outcome = 'fixed';
  if n <> 1 then v_fail := v_fail || ('F: the registered re-sign ran ' || n || ' times, not once'); end if;
  if not exists (select 1 from public.it_code_defect where class_key = 'burst.certificate' and severity = 'P1' and cardinality(affected_cases) >= 3) then
    v_fail := v_fail || ('H: no P1 burst defect for 3 people: ' || coalesce((select string_agg(class_key, ',') from public.it_code_defect), 'none'));
  end if;

  -- ── C: the held person talks to support, and is told the one thing missing ──
  r := public.fn_support_hands_it_a_fault('email', 'email:probe-five', 'en', 'supplier', '[{"role":"supplier","text":"registration stuck"}]', 'five@selfheal.qd-probe');
  update public.it_safe_fix_run set issue_key = issue_key || ':moved' where issue_key = 'reg:stall:held:' || l5;   -- the earlier refusal: this probe replays the next occurrence
  -- the reader succeeds for l1 and the certificate lands for l3; the code is used for c1
  update public.leads set licence_read_state = 'read' where id = l1;
  update public.leads set signed_terms_path = 'probe/cert.pdf', signed_terms_at = now() where id = l3;
  insert into public.email_verifications (email, purpose, user_kind, expires_at, created_at, used_at)
  values ('cust@selfheal.qd-probe', 'signin', 'customer', now() + interval '10 minutes', now() + interval '1 second', now() + interval '2 seconds');

  -- ── WATCH 2: close and tell; A2 re-read a second time ──
  v := public.fn_it_registration_watch();
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'reg:stall:licence_read:' || l1 and closed_at is not null) then v_fail := v_fail || 'A: the repaired licence finding did not close'; end if;
  select count(*) into n from public.customer_support_voice_owed where stage = 'it.repair.done' and to_email = 'one@selfheal.qd-probe';
  if n <> 1 then v_fail := v_fail || ('A: the person was told ' || n || ' times, not once'); end if;
  select count(*) into n from public.customer_support_voice_owed where stage = 'it.repair.done' and to_email = 'three@selfheal.qd-probe';
  if n <> 1 then v_fail := v_fail || ('B: the certificate person was told ' || n || ' times, not once'); end if;
  select count(*) into n from public.customer_support_voice_owed where stage = 'it.repair.held_explain' and to_email = 'five@selfheal.qd-probe' and draft ~ 'expired';
  if n <> 1 then v_fail := v_fail || ('C: the held person was told the missing item ' || n || ' times, not once: '
                                       || coalesce((select string_agg(coalesce(result->>'why', outcome), ' | ') from public.it_safe_fix_run where family = 'held_registration_explain'), 'no run')); end if;
  if not exists (select 1 from public.support_fault_report where id = v_rep and told = 'owed') then v_fail := v_fail || 'E: the code report was not told it is fixed'; end if;
  if not exists (select 1 from public.agent_actions a join public.support_fault_report s on s.handoff_id = a.id where s.id = v_rep and a.status = 'done') then
    v_fail := v_fail || 'E: the code report''s hand-over did not complete';
  end if;
  select count(*) into n from public.it_safe_fix_run where issue_key = 'reg:stall:licence_read:' || l2 and outcome = 'fixed';
  if n <> 2 then v_fail := v_fail || ('A2: the unsuccessful licence was re-read ' || n || ' times across two watches, not 2'); end if;

  -- ── WATCH 3 and 4: still failing 30 minutes on -> one defect; a second watch counts, never a second row ──
  update public.it_safe_fix_run set ran_at = now() - interval '31 minutes' where issue_key = 'reg:stall:licence_read:' || l2;
  v := public.fn_it_registration_watch();
  v := public.fn_it_registration_watch();
  select count(*), max(occurrences) into n, n2 from public.it_code_defect where class_key = 'remedy_exhausted.licence_read_rerun';
  if n <> 1 or n2 < 2 then v_fail := v_fail || ('A2: remedy_exhausted rows ' || n || ', occurrences ' || coalesce(n2, 0)); end if;
  select count(*) into n from public.customer_support_voice_owed where stage = 'it.defect.opened' and to_email = 'two@selfheal.qd-probe';
  if n <> 1 then v_fail := v_fail || ('A2: the person was told ' || n || ' times that it is being fixed, not once'); end if;

  -- ── I: the repaired licence fails again (a new occurrence) and is fixed again -> returns_after_fix ──
  update public.leads set licence_read_state = 'ours_failed', licence_read_at = now() - interval '1 day' where id = l1;
  v := public.fn_it_registration_watch();
  if not exists (select 1 from public.it_code_defect where class_key = 'returns_after_fix.licence_read_rerun') then
    v_fail := v_fail || ('I: a key fixed on two occurrences did not open returns_after_fix: ' || coalesce((select string_agg(class_key, ',') from public.it_code_defect), 'none'));
  end if;

  -- ── J: an unmatched widget report -> P3 defect; the session's life cycle ──
  r := public.fn_support_hands_it_a_fault('widget', 'widget:probe-anon', 'en', 'visitor', '[{"role":"visitor","text":"the page shows an error"}]', null);
  v_rep2 := (r->>'report_id')::bigint;
  update public.support_fault_report set reported_at = now() - interval '3 hours' where id = v_rep2;
  v := public.fn_it_registration_watch();
  select id into v_d from public.it_code_defect where class_key = 'support_fault.widget' and ('fault:' || v_rep2) = any (affected_cases);
  if v_d is null then v_fail := v_fail || 'J: the unmatched report opened no defect'; end if;
  select id into v_d2 from public.it_code_defect where class_key = 'burst.certificate';
  r := public.fn_it_code_defect_claim('probe-session-1', v_d);
  if not coalesce((r->>'claimed')::boolean, false) then v_fail := v_fail || ('J: the defect could not be claimed: ' || r::text); end if;
  r := public.fn_it_code_defect_claim('probe-session-2', v_d);
  if coalesce((r->>'claimed')::boolean, false) then v_fail := v_fail || 'J: a claimed defect was claimed twice'; end if;
  r := public.fn_it_code_defect_verified(v_d, 'probe-session-1', 'a SELECT showed no new occurrence for 30 minutes', 'probe-lesson');
  if coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || 'J: a defect was verified before it was deployed'; end if;
  perform public.fn_it_code_defect_progress(v_d, 'probe-session-1', 'fixing', null, 'reproduced');
  perform public.fn_it_code_defect_progress(v_d, 'probe-session-1', 'in_review', null, 'review: agreed');
  r := public.fn_it_code_defect_progress(v_d, 'probe-session-1', 'merged', null, 'no pr');
  if coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || 'J: merged without a PR number'; end if;
  perform public.fn_it_code_defect_progress(v_d, 'probe-session-1', 'merged', 9999, 'merged');
  perform public.fn_it_code_defect_progress(v_d, 'probe-session-1', 'deployed', 9999, 'DEPLOYED_OK 1/1');
  r := public.fn_it_code_defect_verified(v_d, 'probe-session-1', 'a SELECT showed no new occurrence for 30 minutes after the deploy', 'probe-lesson');
  if not coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || ('J: the deployed defect did not verify: ' || r::text); end if;
  if not exists (select 1 from public.support_fault_report where id = v_rep2 and told like 'no_email%') then v_fail := v_fail || 'J: the anonymous reporter was not recorded as not reachable'; end if;
  -- the lease: a claim that dies is taken back after its lease
  r := public.fn_it_code_defect_claim('probe-session-3', v_d2);
  update public.it_code_defect set lease_until = now() - interval '1 minute' where id = v_d2;
  r := public.fn_it_code_defect_claim('probe-session-4', v_d2);
  if not coalesce((r->>'claimed')::boolean, false) or r->'defect'->>'claimed_by_session' <> 'probe-session-4' then v_fail := v_fail || 'J: an expired lease was not taken back'; end if;
  r := public.fn_it_code_defect_progress(v_d2, 'probe-session-4', 'wont_fix', null, 'because I said so');
  if coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || 'J: wont_fix took a reason outside the allowed list'; end if;
  -- the verified class returns: reopened with its PR in history
  v_id := public.fn_it_code_defect_open('support_fault.widget', 'P3', null, null, null, 'support_fault', '{"again": true}'::jsonb, '{}'::text[]);
  if not exists (select 1 from public.it_code_defect where id = v_id and id = v_d and status = 'queued' and reopened_count = 1 and history::text like '%9999%') then
    v_fail := v_fail || 'J: a verified class that returned was not reopened with its PR';
  end if;
  if (select count(*) from public.it_code_defect where class_key = 'support_fault.widget') <> 1 then v_fail := v_fail || 'J: a class has two rows'; end if;

  -- ── L: guardrails and the knowledge loop ──
  select jsonb_agg(jsonb_build_object('id', id, 'a', approval_status, 'b', banned, 'n', trade_license_no, 'e', license_expiry, 'c', claimed_by) order by id) into v_snap_after
    from public.leads where id in (l1, l2, l3, l4, l5, l6, l7, l8, l9, l10);
  if v_snap_after is distinct from v_snap then v_fail := v_fail || 'L: an approval, a ban, a licence value or an owner changed'; end if;
  if (select count(*) from public.leads) <> v_leads_before + 10 then v_fail := v_fail || 'L: a lead was deleted or created'; end if;
  select jsonb_object_agg(event_type, n) into v_events from (select event_type, count(*) n from public.company_event
    where event_type in ('it.safe_fix', 'it.defect_opened', 'it.defect_fixed', 'support.registration_rescued') and occurred_at >= now() group by 1) z;
  if (select count(*) from jsonb_object_keys(coalesce(v_events, '{}'::jsonb))) <> 4 then v_fail := v_fail || ('L: not all four event kinds were emitted: ' || coalesce(v_events::text, 'none')); end if;
  if exists (select 1 from public.it_safe_fix_family where approval_ruling = 1705 and not active) then
    v_fail := v_fail || ('L: a family parked: ' || (select string_agg(family || ' (' || left(parked_reason, 120) || ')', '; ') from public.it_safe_fix_family where approval_ruling = 1705 and not active));
  end if;

  v_ok := cardinality(v_fail) = 0;
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_fail, ' || ') end,
    jsonb_build_object('failover', v_failover, 'events', v_events,
      'runs', (select jsonb_object_agg(family || ':' || outcome, n) from (select family, outcome, count(*) n from public.it_safe_fix_run group by 1, 2) z),
      'defects', (select jsonb_agg(jsonb_build_object('class', class_key, 'sev', severity, 'status', status, 'occ', occurrences, 'aff', cardinality(affected_cases))) from public.it_code_defect),
      'told', (select jsonb_object_agg(stage, n) from (select stage, count(*) n from public.customer_support_voice_owed where stage like 'it.%' group by 1) z));
end $p$;
