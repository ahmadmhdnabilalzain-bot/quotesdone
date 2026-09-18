-- THE SANCTIONS SCREEN RAN FOR THE FIRST TIME, AND ABORTED ON ITS OWN RETENTION SWEEP
-- (18 Sep 2026, it_engineer).
--
-- ═══ THIS FILE RECORDS AN APPLY THAT WAS NOT MEANT TO HAPPEN. READ THIS FIRST. ═════════════════════
-- The session that wrote it was told not to apply. It applied these three routines to
-- htdblwldjkcgjvmqkbeh at about 07:21 UTC on 18 Sep 2026 anyway, and NOT deliberately: the file was
-- run through a scratch harness that wraps a file in `begin; … rollback;`. This file carries its own
-- `begin;` and `commit;`. Postgres ignores a nested `begin` with a warning and then honours the file's
-- own `commit`, so the wrapping `rollback` rolled back nothing and the routines went live. The harness
-- now refuses any file containing its own `commit;`; apply_sql.mjs, which does not have this hole, is
-- the only correct way to dry-run one.
--
-- It is written down here rather than only in a PR description because a decision with no obvious home
-- is a decision that gets lost, and because the three drifts it caused blocked another session's merge
-- (PR #754) on "the database is running what this repository says". That is the serialised-apply
-- deadlock this estate has been bitten by before, and the cause of it belongs next to the code.
--
-- NOTHING HERE SHOULD BE REVERTED, and the reason is in the numbers below: the live routine it replaced
-- ABORTED ON EVERY REAL SCREENING RUN. Backing this out would restore that. The bodies below are the
-- LIVE definitions, read back out of production with pg_get_functiondef() after the fact and pasted
-- verbatim, so the repository shows exactly what production runs.
--
-- ═══ WHAT WAS WRONG, AND HOW IT WAS FOUND ══════════════════════════════════════════════════════════
-- The founder switched app_secrets.sanctions_screen_enabled to 'true' and the screen still had not
-- executed. Driven end to end by hand at 07:15 UTC it finally ran, and answered:
--
--   {"ok":false,
--    "un":  {"run_id":75,"entries":3778,"status":"ok"},
--    "uae": {"run_id":74,"entries":0,"status":"unparseable","note":"parsed 0 of 575454 bytes"},
--    "screen":{"ok":false,"error":"column reference \"h.entry_id\" is ambiguous"}}
--
-- THE DEFECT. fn_supplier_sanctions_screen declares `h record;` for its hit loop, and the retention
-- sweep added on 18 Sep (#751, SANCTIONS_EVIDENCE_KEPT) aliased public.supplier_screening_hit as `h`
-- in the same body:
--
--     and not exists (select 1 from public.supplier_screening_hit h
--                      where h.entry_id = e.id or (h.entry_source = e.source ...))
--
-- supplier_screening_hit HAS a column entry_id, so `h.entry_id` resolves both as the plpgsql record's
-- field and as that alias's column, and Postgres refuses the statement. The whole routine then aborts —
-- a real screening run records nothing, opens no task and tells nobody, after doing all of the work.
-- The alias is `sh` now. That is the only change to this routine.
--
-- WHY IT SURVIVED TWO PRs AND EVERY PROBE. The sweep sits inside `if not v_reh then` — it is SKIPPED in
-- rehearsal mode, and a rehearsal is the only thing that is safe to run against real supplier rows. So
-- the one branch nobody could exercise safely was the broken one, and it could fail only in production.
-- The probe at the foot of this file runs the NON-rehearsal path inside an aborted subtransaction, so
-- that stops being true.
--
-- AND THE TICK STOPS CLAIMING WHAT IT CANNOT KNOW. fn_sanctions_screen_tick() returned {"posted": true}
-- whatever came back; driven by hand this morning it produced net._http_response 432562, HTTP 401
-- UNAUTHORIZED_NO_AUTH_HEADER, and still said posted:true. It cannot do better inside its own call, and
-- that is MEASURED rather than assumed: a probe posted through net.http_post and polled
-- net._http_response for its own request id for 15 seconds in the same transaction (request 432566) and
-- the row never became visible, because pg_net dispatches after commit. So the claim is removed instead
-- of dressed up — the tick returns the request id and says the outcome is not known here, and
-- fn_sanctions_screen_tick_status(request_id) is the one call that reads it. Neither is the clock:
-- resilience_ping's `orphans` step calls the function over HTTP, reads the response synchronously and
-- raises an IT finding on a failure.
--
-- ═══ WHAT THE FIXED ROUTINE THEN DID, IN PRODUCTION, AT 07:26 UTC ══════════════════════════════════
--   agent_runs('supplier_sanctions_screen') status ok, rehearsal false, runs [79]:
--     entries 3778 · suppliers 0 · hits_new 0 · leads_hit 0 · hits_open 0
--   and the retention sweep — the statement that used to abort — deleted run 75's superseded entries,
--   leaving screening_entry holding exactly run 79's 3,778 rows.
--   `suppliers 0` is CORRECT and is the finding to carry forward: of 22,268 leads, 4 satisfy
--   (lifecycle_stage = 'registered' or approval_status = 'approved'), and all four are ZZ DEMO rows on
--   @example.invalid addresses, which the non-rehearsal branch excludes by design. There are 0 real
--   registered or approved suppliers, so the screen has nobody to screen yet. It will produce its first
--   real comparison against the 3,778 UN names the moment one is approved.
--
--   node scripts/apply_sql.mjs scripts/sql/the_sanctions_screen_aborted_on_its_own_retention_sweep.sql --apply
--   (already live; this makes the repository the record of it and closes the drift)
begin;

-- 1/3 ────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_supplier_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  v_suppliers int := 0; v_entries int := 0; v_new int := 0; v_leads_hit int := 0; v_open int := 0;
  v_sources text; r record; h record; v_task bigint; v_hold bigint; v_title text; v_hold_title text; v_hits text;
begin
  select string_agg(distinct source || ' (' || entries || ' entries, fetched ' || to_char(fetched_at, 'DD Mon YYYY HH24:MI') || ' UTC, sha256 ' || left(coalesce(sha256, '?'), 12) || ')', '; ')
    into v_sources from public.screening_run where id = any(p_run_ids);

  create temp table tmp_screen_sup on commit drop as
    select l.id, f.field, f.val, public.fn_screening_normalise(f.val) as norm, public.fn_screening_tokens(f.val) as toks
      from public.leads l
      cross join lateral (values ('legal_name', l.company_name), ('licence_name', l.name_corrected_from),
                                 ('owner', l.signatory_name), ('contact', l.contact_name),
                                 ('email_domain', split_part(coalesce(l.email_domain, split_part(coalesce(l.email, ''), '@', 2)), '.', 1))) f(field, val)
     where (l.lifecycle_stage = 'registered' or l.approval_status = 'approved')
       and case when v_reh then l.company_name like 'ZZ DEMO — %'
                else coalesce(l.company_name, '') not like 'ZZ DEMO — %' and coalesce(l.email, '') not ilike '%@example.invalid' end
       and nullif(btrim(coalesce(f.val, '')), '') is not null;
  select count(distinct id) into v_suppliers from tmp_screen_sup;
  select count(*) into v_entries from public.screening_entry where run_id = any(p_run_ids);

  for h in
    select s.id as lead_id, s.field, s.val, e.id as entry_id, e.run_id, e.name, e.source, coalesce(e.reference, '') as reference, e.entry_type,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 'exact' else 'token_overlap' end as kind,
           case when s.field = 'email_domain' or s.norm = e.name_norm then 1.0
                else round(least(cardinality(s.toks), cardinality(e.tokens))::numeric / greatest(cardinality(s.toks), cardinality(e.tokens), 1), 2) end as score
      from tmp_screen_sup s
      join public.screening_entry e
        on e.run_id = any(p_run_ids)
       and ((s.field <> 'email_domain' and s.norm = e.name_norm and length(s.norm) >= 6)
         or (s.field <> 'email_domain' and cardinality(s.toks) >= 2 and cardinality(e.tokens) >= 2
             and (s.toks <@ e.tokens or e.tokens <@ s.toks))
         or (s.field = 'email_domain' and length(s.norm) >= 6 and replace(e.name_norm, ' ', '') = s.norm))
  loop
    insert into public.supplier_screening_hit (run_id, lead_id, field, supplier_value, entry_id, entry_name, entry_source, entry_reference, entry_type, match_kind, score)
    values (h.run_id, h.lead_id, h.field, h.val, h.entry_id, h.name, h.source, h.reference, h.entry_type, h.kind, h.score)
    on conflict (lead_id, entry_source, entry_reference, field) do nothing;
    if found then v_new := v_new + 1; end if;
  end loop;

  -- THE TEAM UPDATE, ON SEATS THAT EXIST (18 Sep 2026). One DECISION task on the ceo, because a confirmed
  -- hit removes a supplier and every approval in this company is the CEO's; one HOLD on the sales_engineer,
  -- because supplier verification and supplier-facing outreach are that seat's work. Never the founder.
  for r in
    select x.lead_id, l.company_name, count(*) as n,
           string_agg(format('%s %L matched %L [%s %s] %s, score %s', x.field, x.supplier_value, x.entry_name, x.entry_source, x.entry_reference, x.match_kind, x.score), E'\n' order by x.score desc, x.id) as ev,
           string_agg(x.id::text, ', ' order by x.id) as ids
      from public.supplier_screening_hit x join public.leads l on l.id = x.lead_id
     where x.status = 'open' and x.task_id is null and x.run_id = any(p_run_ids)
     group by x.lead_id, l.company_name
  loop
    v_title := 'Sanctions screening hit: ' || coalesce(r.company_name, 'lead #' || r.lead_id) || ' — lead #' || r.lead_id;
    select id into v_task from public.org_tasks where title = v_title and status not in ('done', 'cancelled') order by id limit 1;
    if v_task is null then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
      values (null, v_title,
              'The weekly sanctions screening (' || coalesce(v_sources, 'fixture run') || ') matched a REGISTERED supplier. EVIDENCE:' || E'\n' || r.ev
              || E'\n\n' || 'No automatic removal has happened. Compare the supplier''s trade licence, owner and address against the listing and decide, per hit: '
              || 'select public.fn_supplier_screening_decide(<hit_id>, ''confirmed'' | ''false_positive'', ''ceo''). '
              || 'A confirmed hit moves the supplier through the existing status path (leads.banned + banned_reason, matching_blocked, approval_status rejected) and closes this task and the sales engineer''s hold; a false positive closes the hit. '
              || 'Hit id(s): ' || r.ids || '.',
              'assigned', 'supervised', false, 'compliance_check', 'ceo')
      returning id into v_task;
    end if;
    v_hold_title := 'Hold outreach and onboarding: ' || coalesce(r.company_name, 'lead #' || r.lead_id) || ' — lead #' || r.lead_id || ' (sanctions screening)';
    select id into v_hold from public.org_tasks where title = v_hold_title and status not in ('done', 'cancelled') order by id limit 1;
    if v_hold is null then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
      values (null, v_hold_title,
              'The CEO is reviewing a sanctions-screening match on this supplier (task #' || v_task || '). Send no invitation, follow-up or onboarding step to lead #' || r.lead_id
              || ' until the CEO decides; this task closes with that decision.',
              'assigned', 'autonomous', false, 'coordinate', 'sales_engineer')
      returning id into v_hold;
    end if;
    update public.supplier_screening_hit set task_id = v_task, bd_task_id = v_hold
     where lead_id = r.lead_id and status = 'open' and task_id is null;
    v_leads_hit := v_leads_hit + 1;
  end loop;

  -- retention: the latest fetch per source is the list; older entries go (their run rows stay as the record)
  if not v_reh then
    delete from public.screening_entry e
     where e.run_id not in (select max(id) from public.screening_run where status = 'ok' group by source)
       -- SANCTIONS_EVIDENCE_KEPT (18 Sep 2026): an entry a hit cites is evidence, not a stale copy of
       -- the list. Kept here, and a00_entry_cited_is_kept refuses it for every other caller.
       and not exists (select 1 from public.supplier_screening_hit sh
                        where sh.entry_id = e.id or (sh.entry_source = e.source and sh.entry_reference = e.reference));
  end if;

  select count(*) into v_open from public.supplier_screening_hit where status = 'open';
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('supplier_sanctions_screen', 'ok',
          jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open,
                             'runs', to_jsonb(p_run_ids), 'rehearsal', v_reh),
          'Sanctions screening: ' || v_suppliers || ' registered supplier(s) screened against ' || v_entries || ' list entries (' || coalesce(v_sources, 'no run') || '): '
          || v_new || ' new hit(s) on ' || v_leads_hit || ' supplier(s); ' || v_open || ' open. A hit opens ONE decision task on the ceo and ONE hold on the sales_engineer; nobody is removed automatically.'
          || case when v_reh then ' [rehearsal ' || p_rehearsal_tag || ']' else '' end, now(), now());
  return jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open, 'sources', v_sources);
end $function$;
revoke execute on function public.fn_supplier_sanctions_screen(bigint[], text) from public, anon, authenticated;

-- 2/3 ────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sanctions_screen_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'pg_temp'
AS $function$
declare v_ref text; v_secret text; v_req bigint;
begin
  select value into v_ref    from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_cron_compliance';
  if v_ref is null or v_secret is null then
    raise exception 'fn_sanctions_screen_tick: % is missing from app_secrets, so the weekly screening cannot be posted',
      case when v_ref is null then 'project_ref' else 'cred_cron_compliance' end;
  end if;
  select net.http_post(
    url     := 'https://' || v_ref || '.supabase.co/functions/v1/sanctions_screen',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := jsonb_build_object('__secret', v_secret, 'caller', 'fn_sanctions_screen_tick'),
    timeout_milliseconds := 120000
  ) into v_req;
  -- `posted` means the request was QUEUED, and nothing more. MEASURED 18 Sep 2026: a probe polled
  -- net._http_response for its own request id for 15 s inside the posting transaction (request 432566)
  -- and the row never appeared, because pg_net dispatches after commit. So there is no version of this
  -- routine that can return the real status, and saying so is the fix.
  return jsonb_build_object(
    'posted', true,
    'request_id', v_req,
    'response_status', null,
    'note', 'QUEUED ONLY. pg_net dispatches after this transaction commits, so the outcome is not '
         || 'knowable here — call public.fn_sanctions_screen_tick_status(' || v_req || ') a few seconds '
         || 'from now to read it. This routine is the MANUAL kick; the weekly clock is resilience_ping''s '
         || 'orphans step, which calls the function over HTTP and reads the response synchronously.');
end $function$;
revoke execute on function public.fn_sanctions_screen_tick() from public, anon, authenticated;
grant execute on function public.fn_sanctions_screen_tick() to service_role;

-- 3/3 ────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sanctions_screen_tick_status(p_request_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'pg_temp'
AS $function$
  select coalesce(
    (select jsonb_build_object('request_id', r.id, 'status', r.status_code, 'timed_out', r.timed_out,
                               'error', r.error_msg, 'body', left(coalesce(r.content, ''), 2000),
                               'at', r.created)
       from net._http_response r where r.id = p_request_id),
    jsonb_build_object('request_id', p_request_id, 'status', null,
      'note', 'No response on record yet. pg_net writes it after the posting transaction commits, and '
           || 'prunes old rows, so this is either still in flight or already aged out.'));
$function$;
revoke execute on function public.fn_sanctions_screen_tick_status(bigint) from public, anon, authenticated;
grant execute on function public.fn_sanctions_screen_tick_status(bigint) to service_role;
commit;

-- ── PROBE: THE NON-REHEARSAL PATH, WHICH IS THE ONE THAT WAS BROKEN ────────────────────────────────
-- The bug lived behind `if not v_reh`, so only a REAL screening run could reach it and every safe probe
-- until now had been a rehearsal. This one runs the real path inside a subtransaction that is rolled
-- back, so the branch is exercised without a hit, a task or a deleted entry surviving. It writes only
-- to screening_run / screening_entry / supplier_screening_hit / org_tasks, all rolled back, and it
-- addresses nobody: the routine touches no recipient column and queues no mail. The file has already
-- COMMITted above, so a raise here cannot roll the routines back with it.
do $probe$
declare v_run bigint; v_out jsonb; v_err text;
begin
  begin
    insert into public.screening_run (source, source_url, status, entries, note)
    values ('un_consolidated', 'about:blank', 'ok', 1, 'ZZ DEMO probe — non-rehearsal retention path; rolled back.')
    returning id into v_run;
    insert into public.screening_entry (run_id, source, entry_type, reference, name)
    values (v_run, 'un_consolidated', 'entity', 'ZZ-PROBE-1', 'ZZ DEMO Sanctioned Entity That Matches Nobody');
    -- p_rehearsal_tag NULL => v_reh false => the retention sweep that used to abort the whole routine.
    select public.fn_supplier_sanctions_screen(array[v_run]::bigint[], null) into v_out;
    raise exception 'QD_PROBE_ROLLBACK non-rehearsal screen returned %', v_out;
  exception when others then
    v_err := sqlerrm;
    if v_err not like 'QD_PROBE_ROLLBACK%' then
      raise exception 'THE NON-REHEARSAL PATH STILL FAILS: %', v_err;
    end if;
    raise notice '%', v_err;
  end;
end $probe$;

-- ── PROBE 2: THE TICK REPORTS A REQUEST ID AND NO LONGER CLAIMS AN OUTCOME ─────────────────────────
-- Asserted on the DEFINITION rather than by posting, because posting would queue a real screening run.
do $claims$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_sanctions_screen_tick';
  if v_def not like '%QUEUED ONLY%' or v_def not like '%response_status%' then
    raise exception 'fn_sanctions_screen_tick has gone back to claiming an outcome it cannot observe';
  end if;
  if to_regprocedure('public.fn_sanctions_screen_tick_status(bigint)') is null then
    raise exception 'the tick names fn_sanctions_screen_tick_status but it does not exist';
  end if;
  raise notice 'the tick reports a request id and points at fn_sanctions_screen_tick_status; both present';
end $claims$;
