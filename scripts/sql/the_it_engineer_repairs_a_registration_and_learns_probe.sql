-- PROBE (pure, no DDL, aborted transaction; LOCAL DATABASE ONLY) for the four files of the self-healing path. Seat: it_engineer.
-- Run after, in the same rolled-back transaction: support_and_the_it_engineer_hand_a_fault_both_ways.sql,
-- a_code_defect_goes_to_the_engineer_session.sql, the_it_engineer_repairs_a_registration_and_learns.sql and
-- the_it_engineer_repairs_within_its_guardrails.sql (scripts/checks/the_it_engineer_repairs_a_registration_and_learns.test.mjs).
--
-- INCAPABLE OF REACHING A PERSON, not merely careful: it refuses to run unless app_secrets.project_ref is the local database's
-- seed ('localpg16localpg16lo', scripts/db/local_standins.sql), so on production it raises before it writes a row; its planted
-- people use the undeliverable top-level domain .qdprobe (not a demo domain, so the live path is the one exercised); every
-- net.http_post on the local database only queues a row; and it ends in raise exception, so every row it wrote rolls back.
--
-- EVERY REPAIR HERE GOES THROUGH THE DISPATCHER (review of f79833d44: the first probe called the families directly, so it never
-- saw that a refusal spent the run budget). The probe calls fn_it_registration_watch(), which raises, runs fn_it_safe_fix_tick
-- for the families of ruling 1705, closes and classifies, exactly as the 5-minute duty does. The defect life cycle is driven
-- through its own routines. Each numbered line below is one row of the review (FIX 1-9); each fails on f79833d44.
--   1   a refusal spends nothing: a licence re-read refused while the routes are open runs once they close; a held registration
--       refused while the person is not talking to support is explained once they report; one refusal row per unchanged answer.
--   2   a licence whose reader stopped on purpose (licence_read_tries 8: held for a person, a wrong document) is never re-read.
--   3   one person, one repair, one message: a licence repaired for a person with three hourly support reports, and a verified
--       defect naming the same person twice (lead and fault), each send exactly one "fixed" notice; one "being fixed" notice.
--   4   a burst is repaired first: no P1 defect and no notice in its first 30 minutes; one that cleared opens none; one still
--       stalled 30 minutes on opens one P1 defect naming only the people who had their repair window, each told once.
--   5   a defect of 260 people stores 200 refs and the count; one bad finding never rolls the watch back.
--   6   a verified defect does not reopen on a condition older than its verification, does on a newer one; a duplicate stays closed.
--   7   only the leaseholder advances; claimed -> fixing -> in_review -> merged -> deployed -> verified, no step skipped; a session
--       that died at merged is taken back at merged and counted; a fixture defect is never claimed by a live session.
--   8   no plan B for json_extraction*; qwen/qwen3.8-flash recorded by the CEO for both document classes, pending its eval, and
--       the failover refuses while it is pending.
--   9   the shared-mobile key is a keyed hash (never md5 of the phone); the certificate retry names the account by id; the watch
--       adds no 'playbook' agent_runs row; a repaired lead's support:fault finding closes; it.escalation routes to the CEO.
--   R2.1-R2.3 (REVIEW2 of 3cf4baf07; each fails on 3cf4baf07): a burst counts only IT-owned stalls (held licences and reads at
--       tries 8 raise none and tell no one); a tell family (held explain, shared-mobile guide, code resend) opens no
--       remedy_exhausted defect; a verified defect tells no "fixed" to a person a repair notice reached since it opened.
--   and the earlier rows that still hold: K (demo not filed, once per case per hour), D (each owner of a shared mobile told once,
--   the CEO handed the data decision), E (a code resent once, the report told when used), F (a registered reader re-run once),
--   L (no lead deleted, no approval, ban or licence value changed, the four event kinds emitted, no family parked).
do $p$
declare
  v_fail text[] := '{}'; v jsonb; r jsonb; n int; n2 int; v_id bigint; v_d bigint; v_t0 timestamptz := now();
  la bigint; l8 bigint; lr bigint; lh bigint; ld1 bigint; ld2 bigint; lx bigint; b1 bigint; b2 bigint; b3 bigint; b4 bigint; b5 bigint; b6 bigint; b7 bigint;
  c1 uuid; v_rep bigint; v_repx bigint; v_leads_before int; v_snap jsonb; v_snap_after jsonb; v_events jsonb; v_refs text[];
begin
  if coalesce((select value from public.app_secrets where key = 'project_ref'), '') <> 'localpg16localpg16lo' then
    raise exception 'PROBE REFUSED: this probe runs only on the local database (project_ref is not the local seed)';
  end if;
  perform set_config('qd.duty_fixtures', '', true);
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('support.root_cause', 'customer_support', 'it_engineer', 'probe stand-in', 'fn_seat_takes_support_root_cause', null, true,
          'scripts/sql/customer_support_finds_the_root_cause_each_week_and_measures_the_fix.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.app_secrets (key, value) values ('cred_fn_resilience_ping', 'local-not-a-secret'), ('publishable_key', 'local-not-a-key')
  on conflict (key) do nothing;
  select count(*) into v_leads_before from public.leads;
  -- the licence routes, all open-circuit at first; the plan B model registered as it is on production
  insert into public.model_registry (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd) values
    ('probe/primary', 'probe', 'medium', 1, 1), ('probe/fallback', 'probe', 'medium', 1, 1), ('qwen/qwen3.8-flash', 'openrouter', 'small', 0.15, 0.47)
  on conflict do nothing;
  insert into public.llm_route_health (model_id, open_until) values ('probe/primary', now() + interval '10 minutes'), ('probe/fallback', now() + interval '10 minutes')
  on conflict (model_id) do update set open_until = excluded.open_until;
  insert into public.model_policy (task_class, tier, model_primary, model_fallback) values
    ('document_extraction', 'medium', 'probe/primary', 'probe/fallback'), ('document_extraction_multimodal', 'medium', 'probe/primary', 'probe/fallback')
  on conflict do nothing;

  -- ── plant the people (idle 2 hours) ──
  insert into public.leads (company_name, claimed, claimed_by, email, licence_read_state, license_doc_path, licence_read_at, portal_updated_at, created_at, trade_license_no, license_expiry)
  values ('Probe Licence A LLC', true, 'a@selfheal.qdprobe', 'a@selfheal.qdprobe', 'ours_failed', 'probe/a.pdf', now() - interval '1 hour', now() - interval '2 hours', now() - interval '3 hours', 'P-1001', date '2027-01-01')
  returning id into la;
  insert into public.leads (company_name, claimed, claimed_by, email, licence_read_state, license_doc_path, licence_read_at, portal_updated_at, created_at)
  values ('Probe Held For A Person LLC', true, 'eight@selfheal.qdprobe', 'eight@selfheal.qdprobe', 'ours_failed', 'probe/eight.pdf', now() - interval '1 hour', now() - interval '2 hours', now() - interval '3 hours')
  returning id into l8;
  insert into public.leads (company_name, claimed, claimed_by, email, licence_read_state, license_doc_path, licence_read_at, portal_updated_at, created_at)
  values ('Probe Licence R LLC', true, 'r@selfheal.qdprobe', 'r@selfheal.qdprobe', 'ours_failed', 'probe/r.pdf', now() - interval '1 hour', now() - interval '2 hours', now() - interval '3 hours')
  returning id into lr;
  insert into public.leads (company_name, claimed, claimed_by, email, licence_gate_reason, approval_status, portal_updated_at, created_at)
  values ('Probe Held H LLC', true, 'h@selfheal.qdprobe', 'h@selfheal.qdprobe', 'licence_expired', 'action_required', now() - interval '2 hours', now() - interval '3 hours')
  returning id into lh;
  insert into public.leads (company_name, claimed, claimed_by, email, phone_e164, portal_updated_at, created_at)
  values ('Probe Shared Mobile D1 LLC', true, 'd1@selfheal.qdprobe', 'd1@selfheal.qdprobe', '+971559990001', now() - interval '2 hours', now() - interval '3 hours') returning id into ld1;
  insert into public.leads (company_name, claimed, claimed_by, email, phone_e164, portal_updated_at, created_at)
  values ('Probe Shared Mobile D2 LLC', true, 'd2@selfheal.qdprobe', 'd2@selfheal.qdprobe', '+971559990001', now() - interval '2 hours', now() - interval '3 hours') returning id into ld2;
  insert into public.leads (company_name, claimed, claimed_by, email, portal_updated_at, created_at)
  values ('Probe Defect X LLC', true, 'x@selfheal.qdprobe', 'x@selfheal.qdprobe', now() - interval '2 hours', now() - interval '3 hours') returning id into lx;
  -- four acceptances with no certificate: a burst of one cause (the first stored with capitals: the retry must name it by id)
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst B1 LLC', true, 'Bee1@Selfheal.qdprobe', 'bee1@selfheal.qdprobe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into b1;
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst B2 LLC', true, 'bee2@selfheal.qdprobe', 'bee2@selfheal.qdprobe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into b2;
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst B3 LLC', true, 'bee3@selfheal.qdprobe', 'bee3@selfheal.qdprobe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into b3;
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst B4 LLC', true, 'bee4@selfheal.qdprobe', 'bee4@selfheal.qdprobe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into b4;
  -- the licence-read clock (a05_leads_licence_read_clock) starts a new licence at 0 tries: A has spent 3, R 2, and the held one
  -- sits at the reader's deliberate ceiling of 8 (supplier_api documents.ts: held for a person, or a wrong document)
  update public.leads set licence_read_tries = 3 where id = la;
  update public.leads set licence_read_tries = 2 where id = lr;
  update public.leads set licence_read_tries = 8 where id = l8;
  insert into public.customers (email, full_name) values ('cust@selfheal.qdprobe', 'Probe Customer') returning id into c1;
  insert into public.email_verifications (email, purpose, user_kind, expires_at, created_at)
  values ('cust@selfheal.qdprobe', 'signin', 'customer', now() - interval '20 minutes', now() - interval '30 minutes');
  -- R told support three times, in three different hours (three report rows, one person)
  insert into public.support_fault_report (channel, case_key, hour_key, audience, email, lead_id, turns, issue_key, reported_at)
  select 'email', 'email:probe-r', h, 'supplier', 'r@selfheal.qdprobe', lr, '[]'::jsonb, 'support:fault:proberrrrrrrrrrr', now() - make_interval(hours => k)
    from (values ('2026111501', 3), ('2026111502', 2), ('2026111503', 1)) z(h, k);
  perform public.fn_it_engineer_finding_upsert('support:fault:proberrrrrrrrrrr', 'A person told support something is broken (email)', 'probe', 'internal', 1,
    jsonb_build_object('owner_seat', 'it_engineer', 'lead_id', lr), '{}'::text[], '{}'::text[], 'customer_support');
  select jsonb_agg(jsonb_build_object('id', id, 'a', approval_status, 'b', banned, 'n', trade_license_no, 'e', license_expiry, 'c', claimed_by) order by id) into v_snap
    from public.leads where id in (la, l8, lr, lh, ld1, ld2, lx, b1, b2, b3, b4);

  -- ── K: demo not filed; one per case per hour ──
  r := public.fn_support_hands_it_a_fault('email', 'email:probe-demo', 'en', 'customer', '[{"role":"customer","text":"ZZ DEMO broken"}]', 'zz@example.invalid');
  if coalesce((r->>'filed')::boolean, true) then v_fail := v_fail || 'K: a demo report was filed'::text; end if;
  r := public.fn_support_hands_it_a_fault('email', 'email:probe-cust', 'en', 'customer', '[{"role":"customer","text":"the code never came, write to me at x@y.ae"}]', 'cust@selfheal.qdprobe');
  v_rep := (r->>'report_id')::bigint;
  if not coalesce((r->>'filed')::boolean, false) or (r->>'handoff_id') is null then v_fail := v_fail || ('K: the fault was not filed with its hand-over: ' || r::text); end if;
  if exists (select 1 from public.support_fault_report where id = v_rep and turns::text ~ '@') then v_fail := v_fail || 'K: an address survived the mask'::text; end if;
  r := public.fn_support_hands_it_a_fault('email', 'email:probe-cust', 'en', 'customer', '[{"role":"customer","text":"again"}]', 'cust@selfheal.qdprobe');
  if coalesce((r->>'filed')::boolean, true) then v_fail := v_fail || 'K: a second report in one hour was filed'::text; end if;

  -- ── WATCH 1 and 2, every licence route open ──
  v := public.fn_it_registration_watch();
  v := public.fn_it_registration_watch();
  begin
    select count(*) filter (where outcome = 'refused_by_guardrail'), count(*) filter (where outcome = 'fixed') into n, n2
      from public.it_safe_fix_run where issue_key = 'reg:stall:licence_read:' || la;
    if n <> 1 or n2 <> 0 then v_fail := v_fail || ('1: a re-read refused twice on open routes left ' || n || ' refusal rows and ' || n2 || ' fixes, not 1 and 0'); end if;
    select count(*) into n from public.it_safe_fix_run where issue_key = 'reg:stall:held:' || lh and outcome = 'refused_by_guardrail';
    if n <> 1 then v_fail := v_fail || ('1: the held registration refused ' || n || ' rows, not 1'); end if;
    -- 8: the document classes have the CEO's plan B, pending its eval; the failover refuses while it is pending
    if exists (select 1 from public.it_route_plan_b where task_class like 'json\_extraction%') then v_fail := v_fail || '8: a plan B is still recorded for json_extraction'::text; end if;
    select count(*) into n from public.it_route_plan_b b where task_class in ('document_extraction', 'document_extraction_multimodal')
       and plan_b_model = 'qwen/qwen3.8-flash' and recorded_by = 'ceo' and not active and (to_jsonb(b)->>'pending_eval') ~* 'ZZ DEMO';
    if n <> 2 then v_fail := v_fail || ('8: ' || n || ' document classes carry the CEO''s pending qwen plan B, not 2'); end if;
    if not exists (select 1 from public.it_safe_fix_run where family = 'route_failover' and issue_key = 'reg:circuit_open:document_extraction'
                     and outcome = 'refused_by_guardrail' and result->>'why' ~* 'eval') then
      v_fail := v_fail || ('8: the failover of document_extraction was not refused for its pending eval: '
        || coalesce((select string_agg(coalesce(result->>'why', outcome), ' | ') from public.it_safe_fix_run where family = 'route_failover'), 'no run'));
    end if;
    if exists (select 1 from public.model_policy where task_class like 'document\_extraction%' and model_fallback = 'qwen/qwen3.8-flash') then
      v_fail := v_fail || '8: a pending plan B was put on the ladder'::text;
    end if;
    -- 4: the burst is raised and repaired, not escalated, in its first 30 minutes
    if not exists (select 1 from public.it_engineer_finding where issue_key = 'reg:burst:certificate' and closed_at is null) then
      v_fail := v_fail || '4: the certificate burst was not raised'::text;
    end if;
    if exists (select 1 from public.it_code_defect where class_key = 'burst.certificate') then v_fail := v_fail || '4: a burst opened a P1 defect before any repair'::text; end if;
    select count(*) into n from public.customer_support_voice_owed where stage = 'it_defect.opened' and to_email like 'bee%';
    if n <> 0 then v_fail := v_fail || ('4: ' || n || ' "we are fixing it" notices went out while the repair was in flight'); end if;
    select count(*) into n from public.it_safe_fix_run where family = 'terms_certificate_retry' and outcome = 'fixed' and (result->>'lead_id')::bigint in (b1, b2, b3, b4);
    if n < 4 then v_fail := v_fail || ('4: the burst''s certificates were retried ' || n || ' times, fewer than its 4 people'); end if;
    -- 9: the certificate retry names the account by id, never by an address it would lower-case
    select convert_from(q.body, 'UTF8')::jsonb into v from net.http_request_queue q
     where q.id = (select (result->>'sign_request')::bigint from public.it_safe_fix_run where family = 'terms_certificate_retry' and (result->>'lead_id')::bigint = b1 order by id limit 1);
    if v is null or v->>'id' is distinct from b1::text or v ? 'email' then v_fail := v_fail || ('9: the certificate retry did not name the account by id: ' || coalesce(v - '__secret', 'null'::jsonb)::text); end if;
    -- 9: the shared mobile's key is a keyed hash, never md5 of the phone
    if not exists (select 1 from public.it_engineer_finding where issue_key like 'reg:dup\_mobile:%') then v_fail := v_fail || '9: the shared mobile was not raised'::text; end if;
    if exists (select 1 from public.it_engineer_finding where issue_key = 'reg:dup_mobile:' || left(md5('+971559990001'), 12)) then
      v_fail := v_fail || '9: the shared-mobile key is md5 of the phone (reversible)'::text;
    end if;
    -- D: each owner told once; the data decision is the CEO's
    select count(*) into n from public.customer_support_voice_owed where stage = 'it_repair.dup_mobile' and to_email in ('d1@selfheal.qdprobe', 'd2@selfheal.qdprobe');
    if n <> 2 then v_fail := v_fail || ('D: ' || n || ' owners told, not 2'); end if;
    if not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'ceo' and detail->>'type' = 'it.finding' and detail->>'issue_key' like 'reg:dup\_mobile:%') then
      v_fail := v_fail || 'D: the CEO was not handed the data decision'::text;
    end if;
    -- E and F
    select count(*) into n from public.it_safe_fix_run where family = 'code_resend_assist' and outcome = 'fixed';
    if n <> 1 then v_fail := v_fail || ('E: the code was resent ' || n || ' times, not once'); end if;
    select count(*) into n from public.it_safe_fix_run where family = 'stuck_job_rerun' and issue_key = 'reg:job_stalled:agreement_resign' and outcome = 'fixed';
    if n <> 1 then v_fail := v_fail || ('F: the registered re-sign ran ' || n || ' times, not once'); end if;
  exception when others then v_fail := v_fail || ('watch 1-2 checks raised: ' || sqlerrm);
  end;

  -- ── the held person writes to support; the routes close ──
  r := public.fn_support_hands_it_a_fault('email', 'email:probe-h', 'en', 'supplier', '[{"role":"supplier","text":"registration stuck"}]', 'h@selfheal.qdprobe');
  update public.llm_route_health set open_until = null where model_id in ('probe/primary', 'probe/fallback');
  v := public.fn_it_registration_watch();
  begin
    select count(*) into n from public.it_safe_fix_run where issue_key = 'reg:stall:licence_read:' || la and outcome = 'fixed';
    if n <> 1 then v_fail := v_fail || ('1: the licence was re-read ' || n || ' times once the routes closed, not once'); end if;
    if not exists (select 1 from public.leads where id = la and licence_read_tries = 3 and licence_read_at < now() - interval '1 day') then
      v_fail := v_fail || '1: the re-read did not make the licence due, or touched its tries'::text;
    end if;
    select count(*) into n from public.customer_support_voice_owed where stage = 'it_repair.held_explain' and to_email = 'h@selfheal.qdprobe' and draft ~ 'expired';
    if n <> 1 then v_fail := v_fail || ('1: the held person who reported was told the missing item ' || n || ' times, not once: '
      || coalesce((select string_agg(coalesce(result->>'why', outcome), ' | ') from public.it_safe_fix_run where family = 'held_registration_explain'), 'no run')); end if;
    -- 2: the reader's own stop stands
    if not exists (select 1 from public.leads where id = l8 and licence_read_tries = 8) then v_fail := v_fail || '2: a licence held for a person had its tries reset'::text; end if;
    if exists (select 1 from public.it_safe_fix_run where issue_key = 'reg:stall:licence_read:' || l8 and outcome = 'fixed') then v_fail := v_fail || '2: a licence held for a person was re-read'::text; end if;
    if not exists (select 1 from public.it_safe_fix_run where issue_key = 'reg:stall:licence_read:' || l8 and outcome = 'refused_by_guardrail' and result->>'why' ~* 'person') then
      v_fail := v_fail || '2: the refusal does not say a person judges it'::text;
    end if;
  exception when others then v_fail := v_fail || ('watch 3 checks raised: ' || sqlerrm);
  end;

  -- ── the reader succeeds for A and R; the code is used for the customer ──
  update public.leads set licence_read_state = 'read' where id in (la, lr);
  insert into public.email_verifications (email, purpose, user_kind, expires_at, created_at, used_at)
  values ('cust@selfheal.qdprobe', 'signin', 'customer', now() + interval '10 minutes', now() + interval '1 second', now() + interval '2 seconds');
  v := public.fn_it_registration_watch();
  begin
    if not exists (select 1 from public.it_engineer_finding where issue_key = 'reg:stall:licence_read:' || la and closed_at is not null) then v_fail := v_fail || 'A: the repaired licence finding did not close'::text; end if;
    select count(*) into n from public.customer_support_voice_owed where stage in ('it_repair.done', 'it_fault.fixed', 'it_defect.fixed') and to_email = 'r@selfheal.qdprobe';
    if n <> 1 then v_fail := v_fail || ('3: one repair sent ' || n || ' "fixed" notices to one person with three reports, not 1'); end if;
    if exists (select 1 from public.support_fault_report where lead_id = lr and told_at is null) then v_fail := v_fail || '3: a report of the repaired person was left untold'::text; end if;
    if not exists (select 1 from public.it_engineer_finding where issue_key = 'support:fault:proberrrrrrrrrrr' and closed_at is not null) then
      v_fail := v_fail || '9: the repaired lead''s support:fault finding stayed open'::text;
    end if;
    if not exists (select 1 from public.support_fault_report where id = v_rep and told = 'owed') then v_fail := v_fail || 'E: the code report was not told it is fixed'::text; end if;
  exception when others then v_fail := v_fail || ('watch 4 checks raised: ' || sqlerrm);
  end;

  -- ── 4: three certificates land, the fourth does not; 30 minutes later one person is not a burst ──
  update public.leads set signed_terms_path = 'probe/cert.pdf', signed_terms_at = now() where id in (b1, b2, b3);
  v := public.fn_it_registration_watch();
  update public.it_engineer_finding set started_at = now() - interval '31 minutes' where issue_key in ('reg:burst:certificate', 'reg:stall:certificate:' || b4);
  update public.it_safe_fix_run set occurrence_started_at = now() - interval '31 minutes' where issue_key = 'reg:stall:certificate:' || b4;
  v := public.fn_it_registration_watch();
  begin
    if exists (select 1 from public.it_code_defect where class_key = 'burst.certificate') then v_fail := v_fail || '4: a burst the repair cleared opened a defect'::text; end if;
  exception when others then v_fail := v_fail || ('burst checks raised: ' || sqlerrm);
  end;
  -- three more stall and stay stalled past their repair window: now it is a defect, naming only those who had their window
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst B5 LLC', true, 'bee5@selfheal.qdprobe', 'bee5@selfheal.qdprobe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into b5;
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst B6 LLC', true, 'bee6@selfheal.qdprobe', 'bee6@selfheal.qdprobe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into b6;
  v := public.fn_it_registration_watch();
  update public.it_engineer_finding set started_at = now() - interval '31 minutes' where issue_key in ('reg:stall:certificate:' || b5, 'reg:stall:certificate:' || b6);
  update public.it_safe_fix_run set occurrence_started_at = now() - interval '31 minutes' where issue_key in ('reg:stall:certificate:' || b5, 'reg:stall:certificate:' || b6);
  insert into public.leads (company_name, claimed, claimed_by, email, accepted_terms_at, portal_updated_at, created_at) values
    ('Probe Burst B7 LLC', true, 'bee7@selfheal.qdprobe', 'bee7@selfheal.qdprobe', now() - interval '40 minutes', now() - interval '2 hours', now() - interval '3 hours') returning id into b7;
  v := public.fn_it_registration_watch();
  begin
    select count(*), max(cardinality(affected_cases)) into n, n2 from public.it_code_defect where class_key = 'burst.certificate' and severity = 'P1';
    if n <> 1 or n2 <> 3 then v_fail := v_fail || ('4: a burst still stalled 30 minutes on opened ' || n || ' P1 defects naming ' || coalesce(n2, 0) || ' people, not 1 naming 3'); end if;
    if exists (select 1 from public.it_code_defect where class_key = 'burst.certificate' and ('lead:' || b7) = any (affected_cases)) then
      v_fail := v_fail || '4: a person still inside their repair window was escalated'::text;
    end if;
    select count(*), count(distinct to_email) into n, n2 from public.customer_support_voice_owed where stage = 'it_defect.opened' and to_email like 'bee%';
    if n <> 3 or n2 <> 3 then v_fail := v_fail || ('4: ' || n || ' "being fixed" notices to ' || n2 || ' people, not 3 to 3'); end if;
  exception when others then v_fail := v_fail || ('burst escalation checks raised: ' || sqlerrm);
  end;

  -- ── 3: a verified defect naming one person twice sends one "being fixed" and one "fixed" ──
  begin
    insert into public.support_fault_report (channel, case_key, hour_key, audience, email, lead_id, turns, issue_key)
    values ('email', 'email:probe-x', '2026111509', 'supplier', 'x@selfheal.qdprobe', lx, '[]'::jsonb, 'support:fault:probexxxxxxxxxxx') returning id into v_repx;
    v_d := public.fn_it_code_defect_open('probe.dedupe', 'P2', null, null, null, 'probe', '{}'::jsonb, array['lead:' || lx, 'fault:' || v_repx]);
    perform public.fn_it_code_defect_claim('probe-s-x', v_d);
    perform public.fn_it_code_defect_progress(v_d, 'probe-s-x', s, case when s in ('merged', 'deployed') then 77 end, 'probe') from unnest(array['fixing', 'in_review', 'merged', 'deployed']) s;
    r := public.fn_it_code_defect_verified(v_d, 'probe-s-x', 'a SELECT showed the class gone for 30 minutes after the deploy', 'probe-lesson');
    if not coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || ('3: the dedupe defect did not verify: ' || r::text); end if;
    select count(*) into n from public.customer_support_voice_owed where stage = 'it_defect.opened' and to_email = 'x@selfheal.qdprobe';
    select count(*) into n2 from public.customer_support_voice_owed where stage in ('it_repair.done', 'it_fault.fixed', 'it_defect.fixed') and to_email = 'x@selfheal.qdprobe';
    if n <> 1 or n2 <> 1 then v_fail := v_fail || ('3: one person named twice on a defect got ' || n || ' "being fixed" and ' || n2 || ' "fixed" notices, not 1 and 1'); end if;
  exception when others then v_fail := v_fail || ('3: the defect dedupe raised: ' || sqlerrm);
  end;

  -- ── R2.1: a burst counts only IT-owned stalls. Three more held licences and three more reads at tries 8 (with lh and l8, four
  --    of each, all owner_seat customer_support) raise no burst and, 30 minutes on, open no P1 defect and tell no one ──
  begin
    insert into public.leads (company_name, claimed, claimed_by, email, licence_gate_reason, approval_status, portal_updated_at, created_at)
    select 'Probe R2 Held ' || g || ' LLC', true, 'r2held' || g || '@selfheal.qdprobe', 'r2held' || g || '@selfheal.qdprobe', 'licence_expired', 'action_required',
           now() - interval '2 hours', now() - interval '3 hours' from generate_series(1, 3) g;
    insert into public.leads (company_name, claimed, claimed_by, email, licence_read_state, license_doc_path, licence_read_at, portal_updated_at, created_at)
    select 'Probe R2 Eight ' || g || ' LLC', true, 'r2eight' || g || '@selfheal.qdprobe', 'r2eight' || g || '@selfheal.qdprobe', 'ours_failed', 'probe/r2e' || g || '.pdf',
           now() - interval '1 hour', now() - interval '2 hours', now() - interval '3 hours' from generate_series(1, 3) g;
    update public.leads set licence_read_tries = 8 where claimed_by like 'r2eight%@selfheal.qdprobe';
    v := public.fn_it_registration_watch();
    if exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key in ('reg:burst:held', 'reg:burst:licence_read')) then
      v_fail := v_fail || ('R2.1: a burst was raised from stalls a person judges: '
        || (select string_agg(issue_key, ', ') from public.it_engineer_finding where closed_at is null and issue_key in ('reg:burst:held', 'reg:burst:licence_read')));
    end if;
    update public.it_engineer_finding set started_at = now() - interval '31 minutes'
     where closed_at is null and (issue_key like 'reg:stall:held:%' or issue_key like 'reg:stall:licence\_read:%' or issue_key in ('reg:burst:held', 'reg:burst:licence_read'));
    update public.it_safe_fix_run run set occurrence_started_at = x.started_at from public.it_engineer_finding x
     where x.issue_key = run.issue_key and x.closed_at is null and (x.issue_key like 'reg:stall:held:%' or x.issue_key like 'reg:stall:licence\_read:%');
    v := public.fn_it_registration_watch();
    select count(*) into n from public.it_code_defect where class_key in ('burst.held', 'burst.licence_read');
    select count(*) into n2 from public.customer_support_voice_owed where stage = 'it_defect.opened' and (to_email like 'r2held%' or to_email like 'r2eight%' or to_email in ('h@selfheal.qdprobe', 'eight@selfheal.qdprobe'));
    if n <> 0 or n2 <> 0 then v_fail := v_fail || ('R2.1: held licences and reads at tries 8 opened ' || n || ' burst defects and sent ' || n2 || ' "our team is fixing it" notices, not 0 and 0'); end if;
  exception when others then v_fail := v_fail || ('R2.1: raised: ' || sqlerrm);
  end;

  -- ── R2.2: a "tell" family is not a failed repair. The held person told the missing item (lh), the owners of a shared mobile
  --    told to sign in by e-mail (ld1, ld2) and a resent code still unused, each 31 minutes on, open no remedy_exhausted defect ──
  begin
    insert into public.customers (email, full_name) values ('cust2@selfheal.qdprobe', 'Probe Customer Two');
    insert into public.email_verifications (email, purpose, user_kind, expires_at, created_at)
    values ('cust2@selfheal.qdprobe', 'signin', 'customer', now() - interval '20 minutes', now() - interval '30 minutes');
    r := public.fn_support_hands_it_a_fault('email', 'email:probe-cust2', 'en', 'customer', '[{"role":"customer","text":"no code arrived"}]', 'cust2@selfheal.qdprobe');
    v := public.fn_it_registration_watch();
    select count(*) into n from public.it_safe_fix_run where family = 'code_resend_assist' and outcome = 'fixed' and result->>'email_hash' = md5('cust2@selfheal.qdprobe');
    if n <> 1 then v_fail := v_fail || ('R2.2: the second customer''s code was resent ' || n || ' times, not once (the row needs it): '
      || coalesce((select string_agg(coalesce(result->>'why', outcome), ' | ') from public.it_safe_fix_run where family = 'code_resend_assist'), 'no run')); end if;
    select count(distinct run.family) into n from public.it_engineer_finding x
      join public.it_safe_fix_run run on run.issue_key = x.issue_key and run.outcome = 'fixed' and run.occurrence_started_at is not distinct from x.started_at
     where x.closed_at is null and run.family in ('held_registration_explain', 'duplicate_mobile_guide', 'code_resend_assist');
    if n <> 3 then v_fail := v_fail || ('R2.2: ' || n || ' of the three tell families hold a fixed run on an open occurrence (the row needs all three)'); end if;
    update public.it_safe_fix_run set ran_at = ran_at - interval '31 minutes' where family in ('held_registration_explain', 'duplicate_mobile_guide', 'code_resend_assist');
    v := public.fn_it_registration_watch();
    select count(*) into n from public.it_code_defect
     where class_key in ('remedy_exhausted.held_registration_explain', 'remedy_exhausted.duplicate_mobile_guide', 'remedy_exhausted.code_resend_assist');
    select count(*) into n2 from public.customer_support_voice_owed where stage = 'it_defect.opened'
       and to_email in ('h@selfheal.qdprobe', 'd1@selfheal.qdprobe', 'd2@selfheal.qdprobe', 'cust2@selfheal.qdprobe');
    if n <> 0 or n2 <> 0 then v_fail := v_fail || ('R2.2: a tell family opened ' || n || ' remedy_exhausted defects ('
      || coalesce((select string_agg(class_key, ', ') from public.it_code_defect where class_key like 'remedy\_exhausted.%'), '') || ') and sent '
      || n2 || ' "our team is fixing it" notices, not 0 and 0'); end if;
  exception when others then v_fail := v_fail || ('R2.2: raised: ' || sqlerrm);
  end;

  -- ── R2.3: one problem, one "fixed". The burst defect's people (b4, b5, b6) get it_repair.done when their certificates land;
  --    two hours later the session verifies the defect: none of them is told "fixed" again ──
  begin
    update public.leads set signed_terms_path = 'probe/cert.pdf', signed_terms_at = now() where id in (b4, b5, b6, b7);
    v := public.fn_it_registration_watch();
    select count(*) into n from public.customer_support_voice_owed where stage = 'it_repair.done' and to_email in ('bee4@selfheal.qdprobe', 'bee5@selfheal.qdprobe', 'bee6@selfheal.qdprobe');
    if n <> 3 then v_fail := v_fail || ('R2.3: ' || n || ' of the burst defect''s 3 people were told their repair landed (the row needs 3)'); end if;
    update public.customer_support_voice_owed set created_at = created_at - interval '2 hours' where stage like 'it\_%' and to_email like 'bee%';
    select id into v_d from public.it_code_defect where class_key = 'burst.certificate';
    update public.it_code_defect set opened_at = opened_at - interval '2 hours 1 minute' where id = v_d;
    perform public.fn_it_code_defect_claim('probe-s-b', v_d);
    perform public.fn_it_code_defect_progress(v_d, 'probe-s-b', s, case when s in ('merged', 'deployed') then 79 end, 'probe') from unnest(array['fixing', 'in_review', 'merged', 'deployed']) s;
    r := public.fn_it_code_defect_verified(v_d, 'probe-s-b', 'a SELECT showed no unsigned acceptance for 30 minutes after the deploy', 'probe-lesson');
    if not coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || ('R2.3: the burst defect did not verify: ' || r::text); end if;
    select count(*) into n from public.customer_support_voice_owed where stage = 'it_defect.fixed' and to_email like 'bee%';
    if n <> 0 then v_fail := v_fail || ('R2.3: the verified burst defect sent ' || n || ' second "fixed" notices to people its repair had already told, not 0'); end if;
  exception when others then v_fail := v_fail || ('R2.3: raised: ' || sqlerrm);
  end;

  -- ── 5: 260 people; one bad finding ──
  begin
    select array_agg('lead:' || (9000000 + g)) into v_refs from generate_series(1, 250) g;
    v_d := public.fn_it_code_defect_open('probe.many', 'P2', null, null, null, 'probe', '{}'::jsonb, v_refs);
    select array_agg('lead:' || (9100000 + g)) into v_refs from generate_series(1, 10) g;
    perform public.fn_it_code_defect_open('probe.many', 'P2', null, null, null, 'probe', '{}'::jsonb, v_refs);
    select cardinality(affected_cases), (to_jsonb(d)->>'affected_count')::int into n, n2 from public.it_code_defect d where class_key = 'probe.many';
    if n <> 200 or coalesce(n2, 0) < 260 then v_fail := v_fail || ('5: 260 people stored ' || n || ' refs and a count of ' || coalesce(n2::text, 'none') || ', not 200 and 260'); end if;
  exception when others then v_fail := v_fail || ('5: a defect of 260 people raised: ' || sqlerrm);
  end;
  begin
    perform public.fn_it_engineer_finding_upsert('reg:stall:certificate:c:not-a-uuid-not-a-uuid-not-a-uuid-xx', 'probe: a malformed key', 'probe', 'internal', 1,
      '{}'::jsonb, '{}'::text[], '{}'::text[], 'it_engineer');
    v := public.fn_it_registration_watch();
    if coalesce(jsonb_array_length(v->'errors'), 0) = 0 then v_fail := v_fail || ('5: the watch did not record the bad finding as an error: ' || left(v::text, 300)); end if;
  exception when others then v_fail := v_fail || ('5: one bad finding rolled the whole watch back: ' || sqlerrm);
  end;
  perform public.fn_it_engineer_finding_close('reg:stall:certificate:c:not-a-uuid-not-a-uuid-not-a-uuid-xx', 'probe');

  -- ── 6: a verified defect and the age of the condition; a duplicate ──
  begin
    v_d := public.fn_it_code_defect_open('probe.verified', 'P2', null, null, null, 'probe', '{}'::jsonb, '{}'::text[], '{}'::text[], '{}'::jsonb, now() - interval '2 hours');
    perform public.fn_it_code_defect_claim('probe-s-v', v_d);
    perform public.fn_it_code_defect_progress(v_d, 'probe-s-v', s, case when s in ('merged', 'deployed') then 78 end, 'probe') from unnest(array['fixing', 'in_review', 'merged', 'deployed']) s;
    perform public.fn_it_code_defect_verified(v_d, 'probe-s-v', 'a SELECT showed the class gone for 30 minutes after the deploy', 'probe-lesson');
    perform public.fn_it_code_defect_open('probe.verified', 'P2', null, null, null, 'probe', '{}'::jsonb, '{}'::text[], '{}'::text[], '{}'::jsonb, now() - interval '1 hour');
    if not exists (select 1 from public.it_code_defect where id = v_d and status = 'verified') then v_fail := v_fail || '6: a condition older than the fix reopened a verified defect'::text; end if;
    update public.it_code_defect set verified_at = now() - interval '3 hours', deployed_at = now() - interval '3 hours' where id = v_d;
    perform public.fn_it_code_defect_open('probe.verified', 'P2', null, null, null, 'probe', '{}'::jsonb, '{}'::text[], '{}'::text[], '{}'::jsonb, now());
    if not exists (select 1 from public.it_code_defect where id = v_d and status = 'queued' and reopened_count = 1 and history::text like '%78%') then
      v_fail := v_fail || '6: a condition newer than the fix did not reopen the defect with its PR'::text;
    end if;
    v_d := public.fn_it_code_defect_open('probe.duplicate', 'P3', null, null, null, 'probe', '{}'::jsonb);
    perform public.fn_it_code_defect_claim('probe-s-d', v_d);
    r := public.fn_it_code_defect_progress(v_d, 'probe-s-d', 'wont_fix', null, 'duplicate of 1');
    perform public.fn_it_code_defect_open('probe.duplicate', 'P3', null, null, null, 'probe', '{}'::jsonb);
    if not exists (select 1 from public.it_code_defect where id = v_d and status = 'wont_fix' and reopened_count = 0) then v_fail := v_fail || '6: a duplicate reopened'::text; end if;
  exception when others then v_fail := v_fail || ('6: raised: ' || sqlerrm);
  end;

  -- ── 7: the lease and the order ──
  begin
    v_d := public.fn_it_code_defect_open('probe.lease', 'P1', null, null, null, 'probe', '{}'::jsonb);
    r := public.fn_it_code_defect_progress(v_d, null, 'deployed', 99, 'no session');
    if coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || '7: a null session advanced an unclaimed defect'::text; end if;
    r := public.fn_it_code_defect_verified(v_d, null, 'a SELECT showed the class gone for 30 minutes after the deploy', 'x');
    if coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || '7: a null session verified an unclaimed defect'::text; end if;
    r := public.fn_it_code_defect_claim('probe-s1', v_d);
    r := public.fn_it_code_defect_progress(v_d, 'probe-s1', 'deployed', 99, 'skip');
    if coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || '7: claimed went straight to deployed'::text; end if;
    r := public.fn_it_code_defect_progress(v_d, 'probe-s1', 'merged', 99, 'skip');
    if coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || '7: claimed went straight to merged'::text; end if;
    perform public.fn_it_code_defect_progress(v_d, 'probe-s1', s, case when s = 'merged' then 99 end, 'probe') from unnest(array['fixing', 'in_review', 'merged']) s;
    r := public.fn_it_code_defect_progress(v_d, 'probe-s2', 'deployed', 99, 'not mine');
    if coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || '7: a session that holds no lease advanced the defect'::text; end if;
    -- the session dies at merged
    update public.it_code_defect set lease_until = now() - interval '1 minute' where id = v_d;
    if coalesce((public.fn_it_code_defect_queue()->>'taken_back_after_merge')::int, 0) < 1 then
      v_fail := v_fail || ('7: a defect whose session died at merged is not counted claimable: ' || public.fn_it_code_defect_queue()::text);
    end if;
    r := public.fn_it_code_defect_claim('probe-s2', v_d);
    if not coalesce((r->>'claimed')::boolean, false) or r->'defect'->>'status' <> 'merged' then v_fail := v_fail || ('7: the dead session''s merged defect was not taken back at merged: ' || left(r::text, 200)); end if;
    r := public.fn_it_code_defect_progress(v_d, 'probe-s2', 'deployed', null, 'deployed');
    if not coalesce((r->>'ok')::boolean, false) then v_fail := v_fail || ('7: the new leaseholder could not deploy from merged: ' || r::text); end if;
    -- a fixture defect is never handed to a live session
    v_id := public.fn_it_code_defect_open('probe.fixture', 'P1', null, null, null, 'probe', '{}'::jsonb);
    update public.it_code_defect set fixture = true, opened_at = now() - interval '1 year' where id = v_id;
    r := public.fn_it_code_defect_claim('probe-s3', null);
    if (r->'defect'->>'id')::bigint = v_id then v_fail := v_fail || '7: a live session claimed a fixture defect'::text; end if;
    r := public.fn_it_code_defect_claim('probe-s3', v_id);
    if coalesce((r->>'claimed')::boolean, false) then v_fail := v_fail || '7: a live session claimed a fixture defect by its id'::text; end if;
  exception when others then v_fail := v_fail || ('7: raised: ' || sqlerrm);
  end;

  -- ── 9 and L: what the watch left behind ──
  select count(*) into n from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'playbook' and started_at >= v_t0;
  if n <> 0 then v_fail := v_fail || ('9: the watch added ' || n || ' playbook agent_runs rows (the founder list counts them as hourly runs)'); end if;
  if not exists (select 1 from public.ceo_standing_grant where grant_key = 'it.escalation' and active and scope_note ~ 'CEO' and scope_note ~ '1696'
                   and limit_note ~* 'destructive' and limit_note ~* 'information') then
    v_fail := v_fail || '9: it.escalation does not route to the CEO under ruling 1696 with the founder told for information'::text;
  end if;
  select jsonb_agg(jsonb_build_object('id', id, 'a', approval_status, 'b', banned, 'n', trade_license_no, 'e', license_expiry, 'c', claimed_by) order by id) into v_snap_after
    from public.leads where id in (la, l8, lr, lh, ld1, ld2, lx, b1, b2, b3, b4);
  if v_snap_after is distinct from v_snap then v_fail := v_fail || 'L: an approval, a ban, a licence value or an owner changed'::text; end if;
  if (select count(*) from public.leads) <> v_leads_before + 20 then v_fail := v_fail || 'L: a lead was deleted or created'::text; end if;
  select jsonb_object_agg(event_type, k) into v_events from (select event_type, count(*) k from public.company_event
    where event_type in ('it.safe_fix', 'it.defect_opened', 'it.defect_fixed', 'support.registration_rescued') and occurred_at >= v_t0 group by 1) z;
  if (select count(*) from jsonb_object_keys(coalesce(v_events, '{}'::jsonb))) <> 4 then v_fail := v_fail || ('L: not all four event kinds were emitted: ' || coalesce(v_events::text, 'none')); end if;
  if exists (select 1 from public.it_safe_fix_family where approval_ruling = 1705 and not active) then
    v_fail := v_fail || ('L: a family parked: ' || (select string_agg(family || ' (' || left(parked_reason, 120) || ')', '; ') from public.it_safe_fix_family where approval_ruling = 1705 and not active));
  end if;

  raise exception '% CHK<<%>>', case when cardinality(v_fail) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_fail, ' || ') end,
    jsonb_build_object('events', v_events,
      'runs', (select jsonb_object_agg(family || ':' || outcome, k) from (select family, outcome, count(*) k from public.it_safe_fix_run group by 1, 2) z),
      'defects', (select jsonb_agg(jsonb_build_object('class', class_key, 'sev', severity, 'status', status, 'occ', occurrences, 'aff', cardinality(affected_cases))) from public.it_code_defect),
      'told', (select jsonb_object_agg(stage, k) from (select stage, count(*) k from public.customer_support_voice_owed where stage like 'it\_%' group by 1) z));
end $p$;
