-- The bodies three sanctions routines are ACTUALLY running, transcribed from production.
--
-- WHY THIS FILE EXISTS. On 18 Sep 2026 the session fixing the sanctions screen applied three
-- routines straight to production instead of handing the apply back: fn_sanctions_screen_tick and
-- fn_supplier_sanctions_screen were rewritten, and fn_sanctions_screen_tick_status was created and
-- existed in no scripts/sql file at all. canonical_routine_manifest then reported 3 findings and
-- BLOCKED EVERY OPEN PULL REQUEST, which is the serialized-apply deadlock this estate has been
-- bitten by before. The behaviour in production is wanted and is left exactly as it is; what was
-- missing was a file that shows it.
--
-- HOW THESE BODIES WERE OBTAINED. Read back out of htdblwldjkcgjvmqkbeh with pg_get_functiondef()
-- on 18 Sep 2026 and pasted verbatim - byte-for-byte what production runs, not what anyone believes
-- it runs. Re-applying this file is therefore a no-op against the live database. That is the same
-- correction PR #751 made for the same reason: a canonical file has to carry a BODY, and a dynamic
-- rewrite block carries only a difference.
--
-- This file is LAST in MANIFEST.txt, so it owns these three routines. If the session that applied
-- them lands a better-documented file afterwards, that file goes below this one and takes ownership.

set local statement_timeout = '120s';

-- fn_sanctions_screen_tick
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

-- fn_sanctions_screen_tick_status
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

-- fn_supplier_sanctions_screen
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

revoke execute on function public.fn_sanctions_screen_tick() from public, anon, authenticated;
revoke execute on function public.fn_sanctions_screen_tick_status(bigint) from public, anon, authenticated;
revoke execute on function public.fn_supplier_sanctions_screen(bigint[], text) from public, anon, authenticated;

-- Verdict row, because the management API discards raise notice (measured 18 Sep 2026, PR #749).
select case when (
  select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('fn_sanctions_screen_tick','fn_sanctions_screen_tick_status','fn_supplier_sanctions_screen')
) = 3
  then 'PROBE OK: all three sanctions routines are present and this file carries their live bodies'
  else 'PROBE FAILED: one of the three sanctions routines is missing after this file applied'
end as verdict;
