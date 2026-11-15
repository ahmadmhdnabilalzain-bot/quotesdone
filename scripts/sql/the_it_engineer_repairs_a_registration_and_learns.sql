-- THE IT ENGINEER REPAIRS A REGISTRATION AND LEARNS: SEVEN OPERATIONAL FIX FAMILIES ON THE REGISTRATION PATH, THREE DETECTORS,
-- AND THE CLASSIFIER THAT SENDS WHAT IT CANNOT REPAIR TO THE ENGINEER SESSION. Seats: it_engineer (the repair) and customer_support
-- (the person). Founder rulings 1705 (15 Nov 2026: "Someone is registering and there is an issue. Who would solve this issue? The
-- IT engineer should solve it, not report it ... His auto-learning loop should help him. And the knowledge loop in the company,
-- where everyone knows what everyone else is doing, is extremely important"), 1706 (bring solutions, not issues), 1574 (standing:
-- the IT engineer fixes the glitches it can fix itself). The families are approved by ruling 1705 (approval_ruling), exactly as
-- the first eight carry 1574; the CEO approves any further family once (fn_ceo_approves_safe_fix_family).
--
-- MEASURED BEFORE WRITING (SP/audit/SUPPORT_IT.md, production SELECTs of 15 Nov 2026 about 19:00 UTC, and the code at 06881a2d6):
--   * fn_it_safe_fix_tick: 8 families, 1,640 runs and 632 fixes in 30 days, none on the registration path (SELECT).
--   * registration failures, 14 days (agent_runs): 368 licence reads failed on "every model route for this task class is
--     open-circuit" (11-13 Nov); 19 terms acceptances produced no signed certificate (2-13 Nov); >= 54 SMS sign-ins refused
--     because more than one account carries the mobile; 73 because the number has no account.
--   * the licence re-read backs off 10 min x 2^tries up to 8 tries (fn_supplier_licence_reread_claim): a 6-hour open circuit
--     spends the tries while no model can answer, and nothing gives the supplier a read once the circuit closes.
--   * the agreement re-sign (fn_sales_engineer_resigns_unsigned_agreements) stops at 3 attempts and leaves a needs_review row
--     nobody acts on.
--   * production on 15 Nov: 15 claimed suppliers (12 read, 3 not yet), 1 held (licence_expired); llm_route_health: no open
--     circuit; model_fallback_chain covers no extraction class (only whatsapp_conversation and whatsapp_voice_note).
--
-- WHAT THIS FILE DOES:
--   1. Registers (service-role only):
--        it_rerunnable_job   the idempotency fact the 9 Sep charter asked for before job_rerun could be granted: which reader
--                            may be re-run, the routine, why running it twice is harmless, and its daily limit. Seeded with
--                            the two registration readers whose own code proves it (see the rows).
--        it_route_plan_b     a registration task class's recorded plan B: a model the estate ALREADY routes extraction work
--                            to. Seeded only where one exists (json_extraction*: anthropic/claude-sonnet-5.5, the
--                            document_extraction fallback that reads licences today). document_extraction has none, so the
--                            family refuses for it until the CEO records one (never the seat's choice).
--        it_route_failover   each 1-hour failover, the fallback it replaced, and when it was put back.
--   2. Seven family routines, each answering fixed / nothing_to_do / refused_by_guardrail / failed for fn_it_safe_fix_tick, which
--      bounds them (max_runs_per_occurrence, max_per_tick) and parks a family after 2 failed runs in a day:
--        licence_read_rerun        reg:stall:licence_read:<lead>   makes the failed read due now and kicks the one reader
--        terms_certificate_retry   reg:stall:certificate:<lead|c:uuid>  asks compliance_archive to sign the recorded acceptance
--        code_resend_assist        support:code_unused:<report>    sends a fresh sign-in code to the verified e-mail
--        held_registration_explain reg:stall:held:<lead>           tells a person in a support conversation exactly what is missing
--        duplicate_mobile_guide    reg:dup_mobile:<hash>           tells each account owner to sign in by e-mail; the CEO decides the data
--        stuck_job_rerun           reg:job_stalled:<job>           re-runs a registered idempotent reader once
--        route_failover            reg:circuit_open:<task_class>   puts the recorded plan B on the class's ladder for 1 hour
--   3. fn_it_registration_watch() (duty it_engineer.registration_watch, every 5 minutes): puts back expired failovers, closes
--      what cleared (and, where a family repaired it, tells the person through support and emits support.registration_rescued),
--      raises the findings above, and the three detectors:
--        (a) STALL     a registering person (claimed, not approved) idle 30 minutes with a cause on their row; at once when they
--                      told support something is broken;
--        (b) BURST     the same cause at 3 or more distinct people (leads or support reports) inside 15 minutes;
--        (c) RETURNS   a class a family said it fixed comes back (two fixed occurrences of one key in 7 days), or a verified
--                      defect's class returns (fn_it_code_defect_open reopens it with its old PR and lesson).
--      and the classifier: an issue is operational when a family matches it and its guardrail admits it; it is a CODE DEFECT
--      (fn_it_code_defect_open) when no family matches a person's report for 2 hours, a family ran its maximum and the fault
--      persists 30 minutes on, a family parked itself, a burst fired, or a fixed class returned.
--   4. it.safe_fix: every run that did something (fixed, refused, failed) is a company_event, so every seat sees what IT did
--      (trigger on it_safe_fix_run); it.defect_opened / it.defect_fixed (a_code_defect_goes_to_the_engineer_session.sql) and
--      support.registration_rescued (support_and_the_it_engineer_hand_a_fault_both_ways.sql) complete the four kinds.
--
-- THE GUARDRAILS (each refusal is answered refused_by_guardrail, never an error): no family deletes or overwrites business data,
-- approves, rejects or unbans a supplier, writes a licence value, touches money, credit or a cap, weakens a gate (the licence
-- gate, the sanctions check, the OTP limits, the reply guard, suppression), changes a secret, deploys, or messages a suppressed
-- or opted-out person (fn_customer_support_duty_send checks fn_email_sendable). The two writes outside the seat's own records
-- are named and bounded: licence_read_rerun sets the READER'S OWN schedule fields (licence_read_at, and licence_read_tries back
-- to 7 when the 8 tries were spent) so the one licence reader runs once more; route_failover sets model_policy.model_fallback to
-- the recorded plan B for one hour and puts the previous value back.
--
-- Prevented by: scripts/checks/the_it_engineer_repairs_a_registration_and_learns.test.mjs (every family registered with a
-- routine, a guardrail and ruling 1705; no family routine deletes, approves or writes a licence value; the local-database replay
-- of each planted failure: fixed exactly once, refused where the guardrail says, the person told once, the defect opened once).
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql --apply --ddl --seat it_engineer

-- ── 1. THE REGISTERS ────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.it_rerunnable_job (
  job_key text primary key check (job_key ~ '^[a-z_]+$'),
  routine text not null check (routine ~ '^fn_[a-z0-9_]+$'),
  idempotency_fact text not null check (length(btrim(idempotency_fact)) >= 40),
  max_per_day integer not null default 3 check (max_per_day between 1 and 6),
  active boolean not null default true,
  recorded_by text not null default 'it_engineer',
  owner_file text not null check (owner_file ~ '^scripts/sql/[a-z0-9_]+\.sql$'),
  recorded_at timestamptz not null default now()
);
create table if not exists public.it_route_plan_b (
  task_class text primary key,
  plan_b_model text not null check (plan_b_model ~ '^[a-z0-9._-]+/[a-z0-9._:-]+$'),
  why text not null check (length(btrim(why)) >= 30),
  recorded_by text not null check (recorded_by in ('it_engineer', 'ceo')),
  active boolean not null default true,
  recorded_at timestamptz not null default now()
);
create table if not exists public.it_route_failover (
  id bigint generated always as identity primary key,
  task_class text not null,
  prior_fallback text,
  plan_b_model text not null,
  issue_key text,
  started_at timestamptz not null default now(),
  until timestamptz not null,
  restored_at timestamptz,
  restore_note text,
  check (until <= started_at + interval '1 hour')
);
create unique index if not exists it_route_failover_one_live_idx on public.it_route_failover (task_class) where restored_at is null;
do $rls$ declare t text; begin
  foreach t in array array['it_rerunnable_job', 'it_route_plan_b', 'it_route_failover'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_service_role_only', t);
    execute format('create policy %I on public.%I as permissive for all to public using (false) with check (false)', t || '_service_role_only', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $rls$;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('it_rerunnable_job', true, 'company', 'which reader the IT engineer may re-run, with the fact that makes a second run harmless (ruling 1705)', 'it_engineer'),
  ('it_route_plan_b', true, 'company', 'a registration task class''s recorded plan B model, already routed for extraction work (ruling 1705)', 'it_engineer'),
  ('it_route_failover', true, 'decision', 'each 1-hour failover of a registration task class to its plan B and when it was put back (ruling 1705)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

insert into public.it_rerunnable_job (job_key, routine, idempotency_fact, max_per_day, owner_file) values
  ('supplier_doc_reread', 'fn_supplier_doc_reread_kick',
   'posts supplier_api docs_reread only when fn_supplier_doc_reread_due() says a read is due; each licence is handed out under for update skip locked and its try counted, so a second run reads nothing twice',
   3, 'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql'),
  ('agreement_resign', 'fn_sales_engineer_resigns_unsigned_agreements',
   'compliance_archive returns the certificate already issued for the acceptance and writes a new one only by compare-and-set; the sweep waits 5 minutes between attempts and stops at 3, so a second run signs nothing twice',
   3, 'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql')
on conflict (job_key) do update set routine = excluded.routine, idempotency_fact = excluded.idempotency_fact, max_per_day = excluded.max_per_day,
  owner_file = excluded.owner_file;

insert into public.it_route_plan_b (task_class, plan_b_model, why, recorded_by) values
  ('json_extraction', 'anthropic/claude-sonnet-5.5',
   'already the fallback of document_extraction, which reads every supplier licence today: a model the estate routes extraction work to, not a new one', 'it_engineer'),
  ('json_extraction_text', 'anthropic/claude-sonnet-5.5',
   'already the fallback of document_extraction, which reads every supplier licence today: a model the estate routes extraction work to, not a new one', 'it_engineer')
on conflict (task_class) do nothing;

-- ── HELPERS ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- the registering person a lead stands for, as the families need them (null when the lead is not registering)
create or replace function public.fn_it_registering_lead(p_lead_id bigint)
returns public.leads language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select l.* from public.leads l
   where l.id = p_lead_id and l.claimed_by is not null and not coalesce(l.banned, false)
     and coalesce(l.approval_status, '') <> 'approved'
     and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.claimed_by)) = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
$fn$;

-- the reader's own model routes: open-circuit when the primary AND the fallback of every licence class are open
create or replace function public.fn_it_licence_routes_open()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(bool_and(exists (select 1 from public.llm_route_health h where h.model_id = p.model_primary and h.open_until > now())
                           and (p.model_fallback is null or exists (select 1 from public.llm_route_health h where h.model_id = p.model_fallback and h.open_until > now()))), false)
    from public.model_policy p where p.active and p.task_class in ('document_extraction', 'document_extraction_multimodal')
$fn$;

-- a person a family repaired: closed with the observation, told once through support, the knowledge loop told
create or replace function public.fn_it_registration_rescued(p_issue_key text, p_lead_id bigint, p_customer uuid, p_what text, p_observed text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_email text; v_role text; v_told boolean := false; v_faults jsonb; f public.it_engineer_finding;
begin
  select * into f from public.it_engineer_finding where issue_key = p_issue_key;
  if p_lead_id is not null then select lower(claimed_by), 'supplier' into v_email, v_role from public.leads where id = p_lead_id;
  elsif p_customer is not null then select lower(email), 'customer' into v_email, v_role from public.customers where id = p_customer; end if;
  if p_what in ('licence_read', 'certificate') and v_email is not null then
    v_told := public.fn_it_tells_the_person('it.repair.done', p_issue_key || '@' || floor(extract(epoch from coalesce(f.started_at, now())))::bigint,
      v_role, v_email, 'en',
      case when p_what = 'licence_read' then 'QuotesDone: your trade licence has been read' else 'QuotesDone: your signed agreement certificate is ready' end,
      case when p_what = 'licence_read'
           then 'Your trade licence could not be read the first time. We read it again and it is done, so you can carry on with your registration from where you stopped.'
           else 'Your signed agreement certificate was not produced the first time. We produced it again and it is on your account now, so you can carry on from where you stopped.' end
        || chr(10) || chr(10) || 'The QuotesDone team',
      'Write a short e-mail telling them a step of their QuotesDone registration that had not finished is now done (the facts say which) and they can carry on from where they stopped. Do not mention any cause or system.',
      'DONE: ' || case when p_what = 'licence_read' then 'their trade licence has been read' else 'their signed agreement certificate has been produced' end
        || chr(10) || 'WHAT THEY CAN DO NOW: carry on with the registration', '');
  end if;
  v_faults := case when p_lead_id is not null then public.fn_support_fault_fixed(null, p_lead_id, p_observed) else '{}'::jsonb end;
  perform public.fn_emit('support.registration_rescued', case when p_lead_id is not null then 'leads' else 'customers' end,
    coalesce(p_lead_id::text, p_customer::text), 'it_engineer',
    jsonb_build_object('supplier_id', p_lead_id, 'customer_id', p_customer, 'issue_key', p_issue_key, 'what', p_what, 'told', v_told,
                       'support_reports', v_faults, 'observed', left(p_observed, 300)));
  return jsonb_build_object('told', v_told, 'support_reports', v_faults);
end $fn$;

-- ── 2. THE SEVEN FAMILY ROUTINES ────────────────────────────────────────────────────────────────────────────────────
-- (1) licence_read_rerun: the one licence reader reads the failed licence again once the routes are back
create or replace function public.fn_it_safe_fix_licence_read_rerun(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint := nullif(substring(p_issue_key from '^reg:stall:licence_read:([0-9]+)$'), '')::bigint; l public.leads; n_today int; v_req bigint;
begin
  if v_id is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a stalled licence read'); end if;
  l := public.fn_it_registering_lead(v_id);
  if l.id is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a registering supplier (approved, banned, unclaimed, or the other side of the fixture switch)'); end if;
  if l.licence_read_state is distinct from 'ours_failed' or l.license_doc_path is null then
    return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'the licence is not in a failed read (' || coalesce(l.licence_read_state, 'no state') || ')');
  end if;
  if public.fn_it_licence_routes_open() then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'every licence-reading route is still open-circuit: a read now would fail the same way (route_failover acts first)');
  end if;
  select count(*) into n_today from public.it_safe_fix_run r
   where r.family = 'licence_read_rerun' and r.issue_key = p_issue_key and r.outcome = 'fixed' and r.ran_at > now() - interval '1 day';
  if n_today >= 2 then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'two re-reads of this licence today already: the third is a code defect'); end if;
  -- THE READER'S OWN SCHEDULE, NEVER A LICENCE VALUE: due now, and one more try when the 8 were spent while no model could answer
  update public.leads set licence_read_at = now() - interval '30 days', licence_read_tries = least(licence_read_tries, 7)
   where id = l.id and licence_read_state = 'ours_failed';
  if not public.fn_supplier_doc_reread_due() then
    return jsonb_build_object('outcome', 'failed', 'why', 'the licence was made due and the reader still says nothing is due', 'lead_id', l.id);
  end if;
  v_req := public.fn_supplier_doc_reread_kick();
  return jsonb_build_object('outcome', 'fixed', 'lead_id', l.id, 'reader_request', v_req, 'tries_left', 8 - least(l.licence_read_tries, 7),
                            'verify', 'the watch closes the finding when licence_read_state leaves ours_failed');
end $fn$;

-- (2) terms_certificate_retry: compliance_archive signs the acceptance on record (it reads the acceptance and its IP itself)
create or replace function public.fn_it_safe_fix_terms_certificate_retry(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_lead bigint := nullif(substring(p_issue_key from '^reg:stall:certificate:([0-9]+)$'), '')::bigint;
  v_cust uuid := case when p_issue_key ~ '^reg:stall:certificate:c:[0-9a-f-]{36}$' then substring(p_issue_key from 24)::uuid end;
  l public.leads; c public.customers; v_kind text; v_email text; v_accepted timestamptz; v_signed timestamptz; v_secret text; v_ref text; v_req bigint;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
begin
  if v_lead is null and v_cust is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a missing-certificate finding'); end if;
  if v_lead is not null then
    l := public.fn_it_registering_lead(v_lead);
    if l.id is null then
      select * into l from public.leads where id = v_lead and claimed_by is not null and not coalesce(banned, false)
         and (coalesce(is_demo, false) or public.fn_is_demo_email(claimed_by)) = v_fx;
    end if;
    if l.id is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a supplier account this run may act for'); end if;
    v_kind := 'supplier'; v_email := lower(l.claimed_by); v_accepted := l.accepted_terms_at; v_signed := case when l.signed_terms_path is not null then l.signed_terms_at end;
  else
    select * into c from public.customers where id = v_cust and not coalesce(banned, false) and coalesce(is_demo, false) = v_fx;
    if c.id is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a customer account this run may act for'); end if;
    v_kind := 'customer'; v_email := lower(c.email); v_accepted := c.tos_accepted_at; v_signed := case when c.signed_terms_path is not null then c.signed_terms_at end;
  end if;
  -- A CERTIFICATE ASSERTS AN ACCEPTANCE: with none on record there is nothing to sign (compliance_archive's 409 no_acceptance_on_record)
  if v_accepted is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'no acceptance on record: the certificate is never issued without one'); end if;
  if v_signed is not null and v_signed >= v_accepted then return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'the certificate for this acceptance has landed'); end if;
  select value into v_secret from public.app_secrets where key = 'cred_db_internal';
  begin v_ref := public.qd_project_ref(); exception when others then v_ref := null; end;
  if v_ref is null or coalesce(v_secret, '') = '' then return jsonb_build_object('outcome', 'failed', 'why', 'no project ref or internal credential'); end if;
  v_req := net.http_post('https://' || v_ref || '.supabase.co/functions/v1/compliance_archive',
    jsonb_build_object('__secret', v_secret, 'action', 'sign', 'kind', v_kind, 'email', v_email), '{}'::jsonb, '{"Content-Type":"application/json"}'::jsonb, 60000);
  return jsonb_build_object('outcome', 'fixed', 'kind', v_kind, 'lead_id', v_lead, 'customer_id', v_cust, 'sign_request', v_req,
                            'verify', 'the watch closes the finding when signed_terms_at reaches the acceptance');
end $fn$;

-- (3) code_resend_assist: a fresh sign-in code to the verified e-mail of a person who told support it never came
create or replace function public.fn_it_safe_fix_code_resend_assist(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint := nullif(substring(p_issue_key from '^support:code_unused:([0-9]+)$'), '')::bigint; r public.support_fault_report;
  v_ok jsonb; n_hour int; v_ref text; v_key text; v_req bigint;
begin
  if v_id is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not an unused-code finding'); end if;
  select * into r from public.support_fault_report where id = v_id;
  if r.id is null or r.email is null or (r.lead_id is null and r.customer_id is null) then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'no verified e-mail with an account: a code goes only to the address an account is registered with');
  end if;
  v_ok := public.fn_email_sendable(r.email, 'login_code');
  if not coalesce((v_ok->>'ok')::boolean, false) then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'the address may not be written to: ' || coalesce(v_ok->>'reason', '?'));
  end if;
  -- login_otp's own limit (8 codes an hour per address) is never raced: this family stays two under it, and sends one an hour
  select count(*) into n_hour from public.email_verifications where lower(email) = r.email and created_at > now() - interval '1 hour';
  if n_hour >= 6 then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'the address asked for ' || n_hour || ' codes this hour: the sign-in limit stands'); end if;
  if exists (select 1 from public.it_safe_fix_run x where x.family = 'code_resend_assist' and x.outcome = 'fixed' and x.ran_at > now() - interval '1 hour'
               and x.result->>'email_hash' = md5(r.email)) then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'a code was resent to this address within the hour');
  end if;
  begin v_ref := public.qd_project_ref(); exception when others then v_ref := null; end;
  v_key := public.fn_gateway_client_key();
  if v_ref is null or v_key is null then return jsonb_build_object('outcome', 'failed', 'why', 'no project ref or gateway key'); end if;
  v_req := net.http_post('https://' || v_ref || '.supabase.co/functions/v1/login_otp',
    jsonb_build_object('action', 'send', 'identifier', r.email, 'user_kind', case when r.lead_id is not null then 'supplier' else 'customer' end, 'lang', r.lang),
    '{}'::jsonb, jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'apikey', v_key), 30000);
  return jsonb_build_object('outcome', 'fixed', 'report_id', r.id, 'email_hash', md5(r.email), 'send_request', v_req,
                            'verify', 'login_otp records the new code in email_verifications; the watch closes the finding when it is used');
end $fn$;

-- (4) held_registration_explain: the exact missing item, to a person who is talking to support (the decider writes on day 0/3/7)
create or replace function public.fn_it_safe_fix_held_registration_explain(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint := nullif(substring(p_issue_key from '^reg:stall:held:([0-9]+)$'), '')::bigint; l public.leads; v_talking boolean; v_item text; v_owed boolean;
begin
  if v_id is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a held-registration finding'); end if;
  l := public.fn_it_registering_lead(v_id);
  if l.id is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a registering supplier'); end if;
  if l.licence_gate_reason is null then return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'the registration is no longer held'); end if;
  v_talking := exists (select 1 from public.support_fault_report r where r.lead_id = l.id and r.reported_at > now() - interval '7 days')
            or exists (select 1 from public.support_case s left join public.support_customer_profile p on p.id = s.customer_profile_id
                        where s.state <> 'closed' and s.last_activity_at > now() - interval '7 days'
                          and ((s.party_kind = 'supplier' and s.party_id = l.id::text) or p.lead_id = l.id or lower(p.email) = lower(l.claimed_by)));
  if not v_talking then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'the person is not in a support conversation: the held-registration decider writes to them on day 0, 3 and 7');
  end if;
  -- THE EXACT MISSING ITEM. Never an approval and never a licence value: the person sends the page; the licence reader reads it.
  v_item := case
    when l.licence_gate_reason ~* 'expir' then 'the trade licence on file has expired: upload the renewed licence, the page that shows the new expiry date'
    when l.licence_gate_reason ~* 'unread|unreadable|blur|quality' then 'the licence could not be read: upload a clear photo or PDF of the whole first page'
    when l.licence_gate_reason ~* 'number' then 'the licence number could not be read: upload the page that shows the licence number'
    when l.licence_gate_reason ~* 'name|mismatch' then 'the company name on the licence does not match the account: upload the licence of the company you are registering'
    else 'the licence step is not complete: upload the trade licence again' end;
  v_owed := public.fn_it_tells_the_person('it.repair.held_explain', p_issue_key || ':' || md5(l.licence_gate_reason), 'supplier', l.claimed_by, 'en',
    'QuotesDone: one thing is needed to finish your registration',
    'Your registration is almost done. One thing is needed: ' || v_item || '. You can upload it on your supplier page, and we read it straight away.' || chr(10) || chr(10) || 'The QuotesDone team',
    'Write a short e-mail telling them their registration is almost done and exactly the one thing needed (the facts say what), that they can upload it on their supplier page and it is read straight away. Never say it is approved.',
    'THE ONE THING NEEDED: ' || v_item || chr(10) || 'WHERE: their supplier page', '');
  if not v_owed then return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'already told about this reason, or the address cannot be written to in this mode'); end if;
  return jsonb_build_object('outcome', 'fixed', 'lead_id', l.id, 'item', v_item);
end $fn$;

-- (5) duplicate_mobile_guide: each account owner is told to sign in by e-mail; the data decision is the CEO's
create or replace function public.fn_it_safe_fix_duplicate_mobile_guide(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_hash text := substring(p_issue_key from '^reg:dup_mobile:([0-9a-f]{12})$'); a record; n_told int := 0; n int := 0;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
begin
  if v_hash is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a duplicate-mobile finding'); end if;
  -- NEVER MERGED, NEVER DELETED: each owner hears about their OWN account only, and no other account is named
  for a in select 'supplier' role, lower(l.claimed_by) email from public.leads l
            where l.claimed_by is not null and not coalesce(l.banned, false) and left(md5(l.phone_e164), 12) = v_hash
              and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.claimed_by)) = v_fx
           union
           select 'customer', lower(c.email) from public.customers c
            where c.email is not null and not coalesce(c.banned, false) and c.phone is not null
              and left(md5(regexp_replace(c.phone, '[^0-9+]', '', 'g')), 12) = v_hash and coalesce(c.is_demo, false) = v_fx loop
    n := n + 1;
    if public.fn_it_tells_the_person('it.repair.dup_mobile', v_hash || ':' || md5(a.email), a.role, a.email, 'en',
         'QuotesDone: sign in with your e-mail address',
         'Your mobile number is also on another QuotesDone account, so a sign-in code cannot be sent to it by SMS. Please sign in with your e-mail address instead; your account and everything on it are as you left them.'
           || chr(10) || chr(10) || 'The QuotesDone team',
         'Write a short e-mail telling them their mobile number is on more than one QuotesDone account, so a code cannot be sent to it by SMS, and asking them to sign in with their e-mail address; their account is as they left it. Name no other account.',
         'WHAT THEY CAN DO NOW: sign in with their e-mail address', '') then n_told := n_told + 1; end if;
  end loop;
  if n < 2 then return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'the mobile is no longer on more than one account'); end if;
  update public.it_engineer_finding set evidence = evidence || jsonb_build_object('owner_seat', 'ceo', 'decision_needed',
           'which account keeps this mobile: the data decision is the CEO''s; the IT engineer never merges or deletes an account')
   where issue_key = p_issue_key;
  return jsonb_build_object('outcome', 'fixed', 'accounts', n, 'told', n_told, 'data_decision', 'ceo');
end $fn$;

-- (6) stuck_job_rerun: a registered idempotent reader, once
create or replace function public.fn_it_safe_fix_stuck_job_rerun(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_job text := substring(p_issue_key from '^reg:job_stalled:([a-z_]+)$'); j public.it_rerunnable_job; n_today int; v jsonb; v_raw text;
begin
  if v_job is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a stalled-job finding'); end if;
  select * into j from public.it_rerunnable_job where job_key = v_job and active;
  if j.job_key is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'no idempotency fact is registered for ' || v_job || ': only it_rerunnable_job readers are re-run'); end if;
  if to_regprocedure('public.' || j.routine || '()') is null and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = j.routine and p.pronargs = p.pronargdefaults) then
    return jsonb_build_object('outcome', 'failed', 'why', 'the registered routine ' || j.routine || ' cannot be called without arguments');
  end if;
  select count(*) into n_today from public.it_safe_fix_run r where r.family = 'stuck_job_rerun' and r.result->>'job' = v_job and r.outcome = 'fixed' and r.ran_at > now() - interval '1 day';
  if n_today >= j.max_per_day then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', v_job || ' was re-run ' || n_today || ' times today, its registered limit'); end if;
  execute format('select (public.%I())::text', j.routine) into v_raw;
  -- a reader that answers {"ok": false, ...} did not run: that is a failed remedy, never a fix
  begin v := v_raw::jsonb; exception when others then v := null; end;
  if jsonb_typeof(v) = 'object' and v->>'ok' = 'false' then
    return jsonb_build_object('outcome', 'failed', 'job', v_job, 'why', left(coalesce(v->>'error', v->>'reason', 'the reader said it did not run'), 300));
  end if;
  return jsonb_build_object('outcome', 'fixed', 'job', v_job, 'routine', j.routine, 'answer', left(coalesce(v_raw, 'null'), 400));
end $fn$;

-- (7) route_failover: the recorded plan B on a registration class's ladder for one hour, then put back
create or replace function public.fn_it_safe_fix_route_failover(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_class text := substring(p_issue_key from '^reg:circuit_open:([a-z0-9_]+)$'); b public.it_route_plan_b; p public.model_policy; v_gate jsonb; n_today int;
begin
  if v_class is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not an open-circuit finding'); end if;
  select * into b from public.it_route_plan_b where task_class = v_class and active;
  if b.task_class is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'no plan B is recorded for ' || v_class || ': choosing a model is not the seat''s (the CEO records one)'); end if;
  select * into p from public.model_policy where task_class = v_class and active limit 1;
  if p.task_class is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'no active model policy for ' || v_class); end if;
  if p.model_fallback is not distinct from b.plan_b_model or p.model_primary = b.plan_b_model then
    return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'the plan B is already on the ladder');
  end if;
  if exists (select 1 from public.it_route_failover f where f.task_class = v_class and f.restored_at is null) then
    return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'a failover is already live for ' || v_class);
  end if;
  if exists (select 1 from public.llm_route_health h where h.model_id = b.plan_b_model and h.open_until > now()) then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'the plan B route is itself open-circuit');
  end if;
  -- NEVER PAST A GATE: the founder's hold, a cap or a held provider refuses the plan B exactly as it would refuse the primary
  v_gate := public.fn_kernel_paid_provider_gate(b.plan_b_model);
  if not coalesce((v_gate->>'allowed')::boolean, false) then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'the paid-provider gate refuses the plan B: ' || coalesce(v_gate->>'rule', '?'));
  end if;
  select count(*) into n_today from public.it_route_failover f where f.task_class = v_class and f.started_at > now() - interval '1 day';
  if n_today >= 2 then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'two failovers of ' || v_class || ' today already: the third is a code defect'); end if;
  insert into public.it_route_failover (task_class, prior_fallback, plan_b_model, issue_key, until)
  values (v_class, p.model_fallback, b.plan_b_model, p_issue_key, now() + interval '1 hour');
  update public.model_policy set model_fallback = b.plan_b_model where task_class = v_class and active;
  if not exists (select 1 from public.model_policy where task_class = v_class and active and model_fallback = b.plan_b_model) then
    return jsonb_build_object('outcome', 'failed', 'why', 'the plan B did not land on the ladder');
  end if;
  return jsonb_build_object('outcome', 'fixed', 'task_class', v_class, 'plan_b', b.plan_b_model, 'replaced', p.model_fallback, 'until', now() + interval '1 hour');
end $fn$;

-- ── 4. EVERY RUN THAT DID SOMETHING IS A COMPANY EVENT (it.safe_fix) ────────────────────────────────────────────────
create or replace function public.fn_it_safe_fix_run_emits()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.outcome <> 'nothing_to_do' then
    perform public.fn_emit('it.safe_fix', 'it_safe_fix_run', new.id::text, 'it_engineer',
      jsonb_build_object('family', new.family, 'outcome', new.outcome, 'issue_key', new.issue_key,
                         'supplier_id', coalesce(new.result->>'lead_id', substring(coalesce(new.issue_key, '') from '^reg:stall:[a-z_]+:([0-9]+)$')),
                         'why', left(coalesce(new.result->>'why', new.error, ''), 200)));
  end if;
  return new;
end $fn$;
drop trigger if exists it_safe_fix_run_emits on public.it_safe_fix_run;
create trigger it_safe_fix_run_emits after insert on public.it_safe_fix_run for each row execute function public.fn_it_safe_fix_run_emits();

-- ── THE DISPATCHER, ONE COPY: the live body (the_it_engineer_runs_the_safe_fix_playbooks_itself.sql), plus a filter the watch
--    sets for its own transaction (qd.safe_fix_only_ruling = 1705), so a stalled registration is repaired within 5 minutes while
--    the eight housekeeping families keep their hourly duty. Unset, it runs every active family exactly as before.
create or replace function public.fn_it_safe_fix_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare fam public.it_safe_fix_family; f record; v jsonb; v_outcome text; v_err text; n int; v_out jsonb := '{}'::jsonb; v_fam jsonb;
  v_until timestamptz := clock_timestamp() + interval '40 seconds';
  v_only integer := nullif(current_setting('qd.safe_fix_only_ruling', true), '')::integer;
begin
  for fam in select * from public.it_safe_fix_family where active and (v_only is null or approval_ruling = v_only) order by family loop
    v_fam := jsonb_build_object('fixed', 0, 'nothing_to_do', 0, 'refused_by_guardrail', 0, 'failed', 0);
    n := 0;
    for f in select null::text issue_key, null::timestamptz started_at where fam.issue_like is null
             union all
             select x.issue_key, x.started_at from public.it_engineer_finding x
              where fam.issue_like is not null and x.closed_at is null and x.issue_key like fam.issue_like
                and x.issue_key not ilike '%demo%' and not coalesce((x.evidence->>'demo')::boolean, false)
                and (select count(*) from public.it_safe_fix_run r where r.family = fam.family and r.issue_key = x.issue_key
                      and r.occurrence_started_at is not distinct from x.started_at) < fam.max_runs_per_occurrence
             order by 2 nulls first, 1 loop
      exit when n >= fam.max_per_tick or clock_timestamp() > v_until;
      n := n + 1; v := null; v_err := null;
      begin
        if fam.issue_like is null then execute format('select public.%I()', fam.routine) into v;
        else execute format('select public.%I($1)', fam.routine) into v using f.issue_key; end if;
        v_outcome := coalesce(v->>'outcome', 'failed');
        if v_outcome not in ('fixed', 'nothing_to_do', 'refused_by_guardrail', 'failed') then v_outcome := 'failed'; end if;
      exception when others then
        v_outcome := 'failed'; v_err := left(sqlerrm, 500);
      end;
      insert into public.it_safe_fix_run (family, issue_key, occurrence_started_at, outcome, result, error)
      values (fam.family, f.issue_key, f.started_at, v_outcome, coalesce(v, '{}'::jsonb), v_err);
      v_fam := jsonb_set(v_fam, array[v_outcome], to_jsonb((v_fam->>v_outcome)::int + 1));
    end loop;
    -- TWO FAILED REMEDIES PARK THE FAMILY: it stops, says why, and goes on the session's daily list
    if (select count(*) from public.it_safe_fix_run r where r.family = fam.family and r.outcome = 'failed' and r.ran_at > now() - interval '1 day') >= 2 then
      update public.it_safe_fix_family set active = false, parked_at = now(),
             parked_reason = 'two failed runs in a day: ' || coalesce((select string_agg(coalesce(r.error, r.result->>'why', '?'), ' | ')
                                                                       from (select * from public.it_safe_fix_run r where r.family = fam.family and r.outcome = 'failed'
                                                                              order by r.id desc limit 2) r), '?')
       where family = fam.family;
      v_fam := v_fam || jsonb_build_object('parked', true);
    end if;
    v_out := v_out || jsonb_build_object(fam.family, v_fam);
  end loop;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), clock_timestamp(), jsonb_build_object('job', 'playbook', 'families', v_out, 'only_ruling', v_only),
          case when v_only is null then 'the IT engineer''s safe-fix playbooks ran (ruling 1574)'
               else 'the IT engineer''s safe-fix playbooks of ruling ' || v_only || ' ran' end);
  return jsonb_build_object('families', v_out);
end $fn$;
revoke execute on function public.fn_it_safe_fix_tick() from public, anon, authenticated;

-- ── 3. THE WATCH: DETECT, CLOSE, CLASSIFY ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_registration_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  f record; l record; r record; v_key text; v_cleared boolean; v_obs text; v_fixed boolean; v_lead bigint; v_cust uuid;
  n_raised int := 0; n_closed int := 0; n_rescued int := 0; n_defects int := 0; n_restored int := 0; v_fam text; v_what text;
  v_routes_open boolean := public.fn_it_licence_routes_open(); v_tick jsonb;
begin
  -- 0. A FAILOVER LASTS ONE HOUR: put the previous fallback back (only if nobody changed it since)
  for r in select * from public.it_route_failover where restored_at is null and until <= now() for update skip locked loop
    update public.model_policy set model_fallback = r.prior_fallback where task_class = r.task_class and active and model_fallback = r.plan_b_model;
    update public.it_route_failover set restored_at = now(),
           restore_note = case when found then 'the previous fallback is back' else 'the policy had changed since; left as it is' end where id = r.id;
    n_restored := n_restored + 1;
  end loop;

  -- 1. CLOSE WHAT CLEARED; a family that repaired it tells the person and the company
  for f in select x.* from public.it_engineer_finding x where x.closed_at is null and x.raised_by = 'it_engineer'
             and (x.issue_key like 'reg:%' or x.issue_key like 'support:code\_unused:%') and coalesce((x.evidence->>'demo')::boolean, false) = v_fx loop
    v_cleared := false; v_obs := null; v_lead := null; v_cust := null; v_what := null;
    if f.issue_key like 'reg:stall:licence\_read:%' then
      v_lead := substring(f.issue_key from '([0-9]+)$')::bigint; v_what := 'licence_read';
      select * into l from public.leads where id = v_lead;
      v_cleared := l.id is null or l.licence_read_state is distinct from 'ours_failed' or coalesce(l.approval_status, '') = 'approved' or coalesce(l.banned, false);
      v_obs := 'licence_read_state ' || coalesce(l.licence_read_state, 'null');
    elsif f.issue_key like 'reg:stall:certificate:c:%' then
      v_cust := substring(f.issue_key from 24)::uuid; v_what := 'certificate';
      select * into l from public.customers where id = v_cust;
      v_cleared := l.id is null or l.tos_accepted_at is null or (l.signed_terms_path is not null and l.signed_terms_at >= l.tos_accepted_at);
      v_obs := 'signed_terms_at ' || coalesce(l.signed_terms_at::text, 'null');
    elsif f.issue_key like 'reg:stall:certificate:%' then
      v_lead := substring(f.issue_key from '([0-9]+)$')::bigint; v_what := 'certificate';
      select * into l from public.leads where id = v_lead;
      v_cleared := l.id is null or l.accepted_terms_at is null or (l.signed_terms_path is not null and l.signed_terms_at >= l.accepted_terms_at);
      v_obs := 'signed_terms_at ' || coalesce(l.signed_terms_at::text, 'null');
    elsif f.issue_key like 'reg:stall:held:%' then
      v_lead := substring(f.issue_key from '([0-9]+)$')::bigint; v_what := 'held';
      select * into l from public.leads where id = v_lead;
      v_cleared := l.id is null or l.licence_gate_reason is null or coalesce(l.approval_status, '') = 'approved';
      v_obs := 'licence_gate_reason ' || coalesce(l.licence_gate_reason, 'cleared');
    elsif f.issue_key like 'reg:job\_stalled:supplier\_doc\_reread' then
      v_cleared := not exists (select 1 from public.leads x where x.licence_read_state = 'ours_failed' and x.license_doc_path is not null
                                 and x.claimed_by is not null and x.licence_read_tries < 8
                                 and coalesce(x.licence_read_at, '-infinity'::timestamptz) + make_interval(mins => 10 * (2 ^ x.licence_read_tries)::int) < now() - interval '30 minutes');
      v_obs := 'no licence read waits 30 minutes past its due time';
    elsif f.issue_key like 'reg:job\_stalled:agreement\_resign' then
      v_cleared := not exists (select 1 from public.leads x where x.accepted_terms_at is not null and x.claimed_by is not null and not coalesce(x.banned, false)
                                 and (x.signed_terms_path is null or x.signed_terms_at < x.accepted_terms_at) and x.accepted_terms_at < now() - interval '30 minutes'
                                 and x.accepted_terms_at > now() - interval '14 days');
      v_obs := 'no acceptance waits 30 minutes for its certificate';
    elsif f.issue_key like 'reg:circuit\_open:%' then
      v_cleared := not v_routes_open; v_obs := 'the licence routes are closed';
    elsif f.issue_key like 'reg:dup\_mobile:%' then
      v_cleared := (select count(*) from public.leads x where x.claimed_by is not null and left(md5(x.phone_e164), 12) = substring(f.issue_key from 16)) < 2;
      v_obs := 'the mobile is on one account';
    elsif f.issue_key like 'support:code\_unused:%' then
      select * into r from public.support_fault_report where id = substring(f.issue_key from 21)::bigint;
      v_cleared := r.id is null or exists (select 1 from public.email_verifications e where lower(e.email) = r.email and e.created_at > f.started_at
                                             and (e.used_at is not null or e.verified_at is not null));
      v_obs := 'a code sent after the report was used';
    elsif f.issue_key like 'reg:burst:%' then
      v_cleared := f.last_seen_at < now() - interval '30 minutes'; v_obs := 'no new person with this cause for 30 minutes';
    end if;
    continue when not v_cleared;
    v_fixed := exists (select 1 from public.it_safe_fix_run x where x.issue_key = f.issue_key and x.occurrence_started_at is not distinct from f.started_at and x.outcome = 'fixed');
    perform public.fn_it_engineer_finding_close(f.issue_key, case when v_fixed then 'repaired by the IT engineer''s safe fix and verified: ' else 'cleared: ' end || v_obs);
    n_closed := n_closed + 1;
    if v_fixed and (v_lead is not null or v_cust is not null) then
      perform public.fn_it_registration_rescued(f.issue_key, v_lead, v_cust, v_what, v_obs);
      n_rescued := n_rescued + 1;
    elsif v_fixed and f.issue_key like 'support:code\_unused:%' and r.id is not null then
      perform public.fn_support_fault_fixed(r.issue_key, null, 'a new sign-in code was sent and used');
      n_rescued := n_rescued + 1;
    end if;
  end loop;

  -- 2. (a) STALL: a registering person idle 30 minutes with a cause on their row; at once when they told support
  for l in select x.*, exists (select 1 from public.support_fault_report s where s.lead_id = x.id and s.told_at is null and s.reported_at > now() - interval '2 hours') reported
             from public.leads x
            where x.claimed_by is not null and not coalesce(x.banned, false) and coalesce(x.approval_status, '') <> 'approved'
              and coalesce(x.portal_updated_at, x.created_at) > now() - interval '14 days'
              and (coalesce(x.is_demo, false) or public.fn_is_demo_email(x.claimed_by)) = v_fx
              and (x.licence_read_state = 'ours_failed' or x.licence_gate_reason is not null
                   or (x.accepted_terms_at is not null and x.accepted_terms_at < now() - interval '10 minutes'
                       and (x.signed_terms_path is null or x.signed_terms_at is null or x.signed_terms_at < x.accepted_terms_at)))
            limit 200 loop
    continue when not l.reported and greatest(coalesce(l.portal_updated_at, '-infinity'), coalesce(l.accepted_terms_at, '-infinity'), coalesce(l.licence_read_at, '-infinity'),
                                              coalesce(l.signed_terms_at, '-infinity'), coalesce(l.created_at, '-infinity')) > now() - interval '30 minutes';
    if l.licence_read_state = 'ours_failed' then
      perform public.fn_it_engineer_finding_upsert('reg:stall:licence_read:' || l.id, 'A registering supplier''s licence read failed and is waiting',
        'supplier_api process_docs (the licence reader)', 'agent_facing', 1,
        jsonb_build_object('owner_seat', 'it_engineer', 'subject', 'supplier_api', 'duty', 'registration_watch', 'lead_id', l.id, 'cause', 'licence_read',
                           'tries', l.licence_read_tries, 'routes_open', v_routes_open, 'told_support', l.reported, 'demo', v_fx),
        '{}'::text[], '{}'::text[], 'it_engineer');
      n_raised := n_raised + 1;
    end if;
    if l.accepted_terms_at is not null and (l.signed_terms_path is null or l.signed_terms_at is null or l.signed_terms_at < l.accepted_terms_at)
       and l.accepted_terms_at < now() - interval '10 minutes' then
      perform public.fn_it_engineer_finding_upsert('reg:stall:certificate:' || l.id, 'A registering supplier accepted the agreement and no signed certificate landed',
        'kyc accept_terms -> compliance_archive sign', 'agent_facing', 1,
        jsonb_build_object('owner_seat', 'it_engineer', 'subject', 'compliance_archive', 'duty', 'registration_watch', 'lead_id', l.id, 'cause', 'certificate',
                           'told_support', l.reported, 'demo', v_fx),
        '{}'::text[], '{}'::text[], 'it_engineer');
      n_raised := n_raised + 1;
    end if;
    if l.licence_gate_reason is not null then
      perform public.fn_it_engineer_finding_upsert('reg:stall:held:' || l.id, 'A registering supplier is held at the licence gate',
        'the licence gate (licence_gate_reason)', 'agent_facing', 1,
        jsonb_build_object('owner_seat', 'customer_support', 'subject', 'supplier_api', 'duty', 'registration_watch', 'lead_id', l.id, 'cause', 'held',
                           'reason', l.licence_gate_reason, 'told_support', l.reported, 'demo', v_fx),
        '{}'::text[], '{}'::text[], 'it_engineer');
      n_raised := n_raised + 1;
    end if;
  end loop;
  -- a customer's missing certificate
  for l in select c.id from public.customers c
            where c.tos_accepted_at is not null and c.tos_accepted_at < now() - interval '30 minutes' and c.tos_accepted_at > now() - interval '14 days'
              and (c.signed_terms_path is null or c.signed_terms_at is null or c.signed_terms_at < c.tos_accepted_at)
              and not coalesce(c.banned, false) and coalesce(c.is_demo, false) = v_fx limit 50 loop
    perform public.fn_it_engineer_finding_upsert('reg:stall:certificate:c:' || l.id, 'A customer accepted the terms and no signed certificate landed',
      'kyc accept_terms -> compliance_archive sign', 'agent_facing', 1,
      jsonb_build_object('owner_seat', 'it_engineer', 'subject', 'compliance_archive', 'duty', 'registration_watch', 'customer_id', l.id, 'cause', 'certificate', 'demo', v_fx),
      '{}'::text[], '{}'::text[], 'it_engineer');
    n_raised := n_raised + 1;
  end loop;

  -- a mobile on more than one account, where one of them is registering
  for r in select left(md5(x.phone_e164), 12) h, count(*) n from public.leads x
            where x.claimed_by is not null and x.phone_e164 is not null and not coalesce(x.banned, false)
              and (coalesce(x.is_demo, false) or public.fn_is_demo_email(x.claimed_by)) = v_fx
            group by 1 having count(*) > 1 and max(coalesce(x.portal_updated_at, x.created_at)) > now() - interval '14 days' loop
    perform public.fn_it_engineer_finding_upsert('reg:dup_mobile:' || r.h, 'A mobile number is on more than one account, so SMS sign-in cannot select one',
      'login_otp (ambiguous_phone)', 'agent_facing', r.n::int,
      jsonb_build_object('owner_seat', 'customer_support', 'subject', 'login_otp', 'duty', 'registration_watch', 'accounts', r.n, 'demo', v_fx),
      '{}'::text[], array['which account keeps the mobile: the CEO''s data decision'], 'it_engineer');
    n_raised := n_raised + 1;
  end loop;

  -- a registered reader that stopped: a due licence read waiting 30 minutes past due, or an acceptance with no certificate and no re-sign
  if exists (select 1 from public.leads x where x.licence_read_state = 'ours_failed' and x.license_doc_path is not null and x.claimed_by is not null
               and x.licence_read_tries < 8 and not coalesce(x.banned, false)
               and (coalesce(x.is_demo, false) or public.fn_is_demo_email(x.claimed_by)) = v_fx
               and coalesce(x.licence_read_at, '-infinity'::timestamptz) + make_interval(mins => 10 * (2 ^ x.licence_read_tries)::int) < now() - interval '30 minutes') then
    perform public.fn_it_engineer_finding_upsert('reg:job_stalled:supplier_doc_reread', 'A due licence re-read has waited 30 minutes past its time',
      'pg_cron supplier_doc_reread_5min -> supplier_api docs_reread', 'agent_facing', 1,
      jsonb_build_object('owner_seat', 'it_engineer', 'subject', 'supplier_api', 'duty', 'registration_watch', 'job', 'supplier_doc_reread', 'demo', v_fx),
      '{}'::text[], '{}'::text[], 'it_engineer');
    n_raised := n_raised + 1;
  end if;
  if exists (select 1 from public.leads x where x.accepted_terms_at is not null and x.claimed_by is not null and not coalesce(x.banned, false)
               and (x.signed_terms_path is null or x.signed_terms_at < x.accepted_terms_at)
               and x.accepted_terms_at < now() - interval '30 minutes' and x.accepted_terms_at > now() - interval '14 days'
               and (coalesce(x.is_demo, false) or public.fn_is_demo_email(x.claimed_by)) = v_fx
               and not exists (select 1 from public.agent_actions a where a.agent = 'sales_engineer' and a.kind = 'supplier_agreement_resign'
                                 and a.target_id = x.id::text and a.created_at > now() - interval '20 minutes')
               and (select count(*) from public.agent_actions a where a.agent = 'sales_engineer' and a.kind = 'supplier_agreement_resign'
                      and a.target_id = x.id::text and a.status = 'auto_done') < 3) then
    perform public.fn_it_engineer_finding_upsert('reg:job_stalled:agreement_resign', 'An acceptance has waited 30 minutes with no certificate and no re-sign',
      'fn_sales_engineer_resigns_unsigned_agreements (the minute sweep)', 'agent_facing', 1,
      jsonb_build_object('owner_seat', 'it_engineer', 'subject', 'compliance_archive', 'duty', 'registration_watch', 'job', 'agreement_resign', 'demo', v_fx),
      '{}'::text[], '{}'::text[], 'it_engineer');
    n_raised := n_raised + 1;
  end if;
  -- every licence-reading route open-circuit: a class with a recorded plan B gets a failover finding
  if v_routes_open then
    for r in select b.task_class from public.it_route_plan_b b where b.active loop
      perform public.fn_it_engineer_finding_upsert('reg:circuit_open:' || r.task_class, 'Every licence-reading route is open-circuit',
        'ai_gateway (llm_route_health)', 'agent_facing', 1,
        jsonb_build_object('owner_seat', 'it_engineer', 'subject', 'ai_gateway', 'duty', 'registration_watch', 'task_class', r.task_class, 'demo', v_fx),
        '{}'::text[], '{}'::text[], 'it_engineer');
      n_raised := n_raised + 1;
    end loop;
  end if;

  -- a person who told support a code never came: an unused code for their address around the report
  for r in select s.* from public.support_fault_report s
            where s.told_at is null and s.email is not null and (s.lead_id is not null or s.customer_id is not null)
              and s.fixture = v_fx and s.reported_at > now() - interval '2 hours'
              and exists (select 1 from public.email_verifications e where lower(e.email) = s.email
                            and e.created_at between s.reported_at - interval '2 hours' and s.reported_at + interval '10 minutes'
                            and e.used_at is null and e.verified_at is null and (e.expires_at < now() or e.created_at < now() - interval '10 minutes'))
              and not exists (select 1 from public.email_verifications e where lower(e.email) = s.email and e.created_at > s.reported_at - interval '2 hours'
                                and (e.used_at is not null or e.verified_at is not null)) loop
    perform public.fn_it_engineer_finding_upsert('support:code_unused:' || r.id, 'A person told support a sign-in code never came, and it was never used',
      'login_otp send (e-mail)', 'agent_facing', 1,
      jsonb_build_object('owner_seat', 'customer_support', 'subject', 'login_otp', 'duty', 'registration_watch', 'report_id', r.id, 'demo', v_fx),
      '{}'::text[], '{}'::text[], 'it_engineer');
    n_raised := n_raised + 1;
  end loop;

  -- ── THE REPAIR, NOW: the seven families run on what was just raised (the dispatcher's bounds and parking hold) ──
  perform set_config('qd.safe_fix_only_ruling', '1705', true);
  v_tick := public.fn_it_safe_fix_tick();
  perform set_config('qd.safe_fix_only_ruling', '', true);

  -- ── THE CLASSIFIER: what no family can repair becomes a code defect ──
  -- (b) BURST: one cause at 3 or more distinct people inside 15 minutes
  for r in select cause, array_agg(distinct who) people from (
             select x.evidence->>'cause' cause, 'lead:' || (x.evidence->>'lead_id') who from public.it_engineer_finding x
              where x.closed_at is null and x.issue_key like 'reg:stall:%' and x.started_at > now() - interval '15 minutes'
                and x.evidence ? 'lead_id' and coalesce((x.evidence->>'demo')::boolean, false) = v_fx
             union all
             select 'support_fault_' || s.channel, 'fault:' || s.id from public.support_fault_report s
              where s.reported_at > now() - interval '15 minutes' and s.fixture = v_fx) z
            group by cause having count(distinct who) >= 3 loop
    perform public.fn_it_engineer_finding_upsert('reg:burst:' || r.cause, 'The same registration fault reached ' || cardinality(r.people) || ' people in 15 minutes',
      'registration (' || r.cause || ')', 'customer_facing', cardinality(r.people),
      jsonb_build_object('owner_seat', 'it_engineer', 'subject', 'registration', 'duty', 'registration_watch', 'cause', r.cause, 'people', cardinality(r.people), 'demo', v_fx),
      '{}'::text[], array['the code path all of them hit'], 'it_engineer');
    perform public.fn_it_code_defect_open('burst.' || r.cause, 'P1', 'reg:burst:' || r.cause,
      case when r.cause = 'licence_read' then 'supplier_api' when r.cause = 'certificate' then 'compliance_archive' end, null, r.cause,
      jsonb_build_object('people', cardinality(r.people), 'window', '15 minutes', 'cause', r.cause), r.people);
    n_defects := n_defects + 1;
  end loop;
  -- (ii) a family ran its maximum on this occurrence and the fault is still there 30 minutes after its last run
  for r in select x.issue_key, x.evidence, fam.family, max(run.ran_at) last_run
             from public.it_engineer_finding x
             join public.it_safe_fix_family fam on fam.approval_ruling = 1705 and x.issue_key like fam.issue_like
             join public.it_safe_fix_run run on run.family = fam.family and run.issue_key = x.issue_key and run.occurrence_started_at is not distinct from x.started_at
            where x.closed_at is null and coalesce((x.evidence->>'demo')::boolean, false) = v_fx
            group by x.issue_key, x.evidence, fam.family, fam.max_runs_per_occurrence
           having count(run.*) >= fam.max_runs_per_occurrence and max(run.ran_at) < now() - interval '30 minutes'
              and bool_or(run.outcome in ('fixed', 'failed')) loop
    perform public.fn_it_code_defect_open('remedy_exhausted.' || r.family, case when r.issue_key like 'reg:%' then 'P1' else 'P2' end, r.issue_key,
      case r.family when 'licence_read_rerun' then 'supplier_api' when 'terms_certificate_retry' then 'compliance_archive' when 'code_resend_assist' then 'login_otp'
                    when 'route_failover' then 'ai_gateway' end, null, r.family,
      jsonb_build_object('family', r.family, 'last_run', r.last_run, 'runs', (select jsonb_agg(jsonb_build_object('outcome', x.outcome, 'why', x.result->>'why', 'error', x.error))
        from (select * from public.it_safe_fix_run where family = r.family and issue_key = r.issue_key order by id desc limit 3) x)),
      case when r.evidence ? 'lead_id' then array['lead:' || (r.evidence->>'lead_id')]
           when r.evidence ? 'customer_id' then array['customer:' || (r.evidence->>'customer_id')]
           when r.evidence ? 'report_id' then array['fault:' || (r.evidence->>'report_id')] else '{}'::text[] end);
    n_defects := n_defects + 1;
  end loop;
  -- (iii) a family of this file parked itself today
  for r in select family, parked_reason from public.it_safe_fix_family where approval_ruling = 1705 and not active and parked_at > now() - interval '1 day' loop
    perform public.fn_it_code_defect_open('family_parked.' || r.family, 'P2', null, null, null, r.family,
      jsonb_build_object('family', r.family, 'parked_reason', left(r.parked_reason, 500)));
    n_defects := n_defects + 1;
  end loop;
  -- (c) RETURNS: one key a family fixed on two different occurrences inside 7 days
  for r in select run.family, run.issue_key, count(distinct run.occurrence_started_at) n from public.it_safe_fix_run run
             join public.it_safe_fix_family fam on fam.family = run.family and fam.approval_ruling = 1705
            where run.outcome = 'fixed' and run.ran_at > now() - interval '7 days'
              and exists (select 1 from public.it_engineer_finding x where x.issue_key = run.issue_key and coalesce((x.evidence->>'demo')::boolean, false) = v_fx)
            group by 1, 2 having count(distinct run.occurrence_started_at) >= 2 loop
    perform public.fn_it_code_defect_open('returns_after_fix.' || r.family, 'P2', r.issue_key, null, null, r.family,
      jsonb_build_object('family', r.family, 'issue_key', r.issue_key, 'fixed_occurrences_7d', r.n));
    n_defects := n_defects + 1;
  end loop;
  -- (i) a person's report no family matched for 2 hours (no repair finding for their account, no unused code)
  for r in select s.* from public.support_fault_report s
            where s.told_at is null and s.fixture = v_fx and s.reported_at < now() - interval '2 hours' and s.reported_at > now() - interval '3 days'
              and not exists (select 1 from public.it_engineer_finding x where x.started_at > s.reported_at - interval '1 day'
                                and ((s.lead_id is not null and x.issue_key ~ ('^reg:stall:[a-z_]+:' || s.lead_id || '$'))
                                     or (s.customer_id is not null and x.issue_key = 'reg:stall:certificate:c:' || s.customer_id)
                                     or x.issue_key = 'support:code_unused:' || s.id))
              and not exists (select 1 from public.it_code_defect d where ('fault:' || s.id) = any (d.affected_cases)) loop
    perform public.fn_it_code_defect_open('support_fault.' || r.channel || case when r.lead_id is not null then '.registering' else '' end,
      case when r.lead_id is not null then 'P2' else 'P3' end, r.issue_key, null, null, 'support_fault',
      jsonb_build_object('channel', r.channel, 'turns', r.turns, 'audience', r.audience), array['fault:' || r.id]);
    n_defects := n_defects + 1;
  end loop;

  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), clock_timestamp(),
          jsonb_build_object('job', 'registration_watch', 'raised', n_raised, 'closed', n_closed, 'rescued', n_rescued, 'defects', n_defects,
                             'failovers_restored', n_restored, 'fixture', v_fx, 'repairs', v_tick->'families'),
          'the IT engineer watched registration: ' || n_raised || ' raised, ' || n_closed || ' closed, ' || n_rescued || ' rescued, ' || n_defects || ' to the engineer session');
  return jsonb_build_object('raised', n_raised, 'closed', n_closed, 'rescued', n_rescued, 'defects', n_defects, 'failovers_restored', n_restored, 'fixture', v_fx,
                            'repairs', v_tick->'families');
end $fn$;

revoke execute on function public.fn_it_registering_lead(bigint) from public, anon, authenticated;
revoke execute on function public.fn_it_licence_routes_open() from public, anon, authenticated;
revoke execute on function public.fn_it_registration_rescued(text, bigint, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_licence_read_rerun(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_terms_certificate_retry(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_code_resend_assist(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_held_registration_explain(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_duplicate_mobile_guide(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_stuck_job_rerun(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_route_failover(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_run_emits() from public, anon, authenticated;
revoke execute on function public.fn_it_registration_watch() from public, anon, authenticated;

-- ── THE SEVEN FAMILIES (ruling 1705) ────────────────────────────────────────────────────────────────────────────────
insert into public.it_safe_fix_family (family, issue_like, routine, guardrail, max_runs_per_occurrence, max_per_tick, approval_ruling, active, owner_file) values
  ('licence_read_rerun', 'reg:stall:licence\_read:%', 'fn_it_safe_fix_licence_read_rerun',
   'makes a failed licence read due now and kicks the one licence reader, only once the licence routes are closed; at most 2 a licence a day; sets only the reader''s own schedule fields, never a licence value, never an approval', 2, 10, 1705, true,
   'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql'),
  ('terms_certificate_retry', 'reg:stall:certificate:%', 'fn_it_safe_fix_terms_certificate_retry',
   'asks compliance_archive to sign the acceptance on record, only when one is on record; the acceptance row and its IP are never changed; at most 2 an occurrence', 2, 10, 1705, true,
   'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql'),
  ('code_resend_assist', 'support:code\_unused:%', 'fn_it_safe_fix_code_resend_assist',
   'sends one fresh sign-in code to the e-mail an account is registered with, after the person told support it never came; never past login_otp''s limits, never to a suppressed address, never to a phone, one an hour', 1, 10, 1705, true,
   'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql'),
  ('held_registration_explain', 'reg:stall:held:%', 'fn_it_safe_fix_held_registration_explain',
   'tells a held supplier who is in a support conversation the exact missing item, through support; never approves, never edits a licence value, never writes to one who is not talking to us (the decider does)', 1, 10, 1705, true,
   'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql'),
  ('duplicate_mobile_guide', 'reg:dup\_mobile:%', 'fn_it_safe_fix_duplicate_mobile_guide',
   'tells each account owner whose mobile is on another account to sign in by e-mail, naming no other account; never merges or deletes an account; the data decision is the CEO''s', 1, 10, 1705, true,
   'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql'),
  ('stuck_job_rerun', 'reg:job\_stalled:%', 'fn_it_safe_fix_stuck_job_rerun',
   're-runs once a reader registered in it_rerunnable_job with its idempotency fact, within its daily limit; any other job is refused and stays a finding', 1, 5, 1705, true,
   'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql'),
  ('route_failover', 'reg:circuit\_open:%', 'fn_it_safe_fix_route_failover',
   'puts a registration class''s recorded plan B on its ladder for one hour and puts the previous fallback back; never a new provider or model, never past the paid-provider gate, never a cap or credit change; 2 a class a day', 1, 5, 1705, true,
   'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql')
on conflict (family) do update set issue_like = excluded.issue_like, routine = excluded.routine, guardrail = excluded.guardrail,
  max_runs_per_occurrence = excluded.max_runs_per_occurrence, max_per_tick = excluded.max_per_tick, approval_ruling = excluded.approval_ruling,
  owner_file = excluded.owner_file;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.registration_watch', 'it_engineer', interval '5 minutes', 'fn_it_registration_watch',
   'The IT engineer watches every registration: a stalled person, a burst of one fault at 3 or more people in 15 minutes, a fixed class that returns. It raises what its families repair (licence re-read, certificate, code resend, held explanation, duplicate mobile, stuck reader, route failover), closes what cleared and tells the person through support, and sends what no family can repair to the engineer session as a code defect. Ruling 1705.',
   'scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('fn_it_registering_lead', 'fn_it_licence_routes_open', 'fn_it_registration_rescued', 'fn_it_safe_fix_licence_read_rerun',
             'fn_it_safe_fix_terms_certificate_retry', 'fn_it_safe_fix_code_resend_assist', 'fn_it_safe_fix_held_registration_explain', 'fn_it_safe_fix_duplicate_mobile_guide',
             'fn_it_safe_fix_stuck_job_rerun', 'fn_it_safe_fix_route_failover', 'fn_it_safe_fix_run_emits', 'fn_it_registration_watch')
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'a family of ruling 1705 names a routine that does not exist: ' || f.family from public.it_safe_fix_family f
     where f.approval_ruling = 1705 and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = f.routine)
    union all select 'not seven families of ruling 1705' where (select count(*) from public.it_safe_fix_family where approval_ruling = 1705) <> 7
    union all select 'a register is readable by a client: ' || t from unnest(array['it_rerunnable_job', 'it_route_plan_b', 'it_route_failover']) t
     where has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('authenticated', 'public.' || t, 'select')
    union all select 'a registered reader routine does not exist: ' || j.job_key from public.it_rerunnable_job j
     where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = j.routine)
    union all select 'the watch duty is not registered' where not exists (select 1 from public.seat_duty where duty = 'it_engineer.registration_watch' and enabled)
    union all select 'the it.safe_fix trigger is missing' where not exists (select 1 from pg_trigger where tgname = 'it_safe_fix_run_emits' and not tgisinternal)
  ) z) y;
