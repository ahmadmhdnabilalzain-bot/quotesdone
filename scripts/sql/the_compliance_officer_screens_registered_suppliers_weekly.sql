-- THE COMPLIANCE OFFICER SCREENS REGISTERED SUPPLIERS AGAINST THE SANCTIONS LISTS EVERY WEEK (6 Sep 2026).
--
-- Founder, 6 Sep 2026 (final): "for supplier screening, one agent should check the list on weekly basis
-- and update the team if one of our registered suppliers is included so he will be removed." No new AI
-- employee: the supplier_onboarding workflow already has step 4 "Compliance screen before anything is
-- activated" acted by compliance_and_privacy_officer (Compliance & Privacy Officer, org_agents.compliance_mgr,
-- department legal). That employee owns this loop.
--
-- MEASURED before building (6 Sep 2026): the UN Security Council consolidated list is machine-readable XML
-- at https://scsanctions.un.org/resources/xml/en/consolidated.xml (2,176,957 bytes, dateGenerated
-- 2026-09-05T23:00:04Z, 736 INDIVIDUAL + 275 ENTITY blocks, 2,767 ALIAS_NAME). The UAE local terrorist list
-- on https://www.uaeiec.gov.ae/en-us/un-page is published as a PDF (LS 130923 2026.pdf, 12 pages) AND as a
-- legacy Excel workbook (LS 130923 2026.xls, application/vnd.ms-excel, 183,808 bytes) linked as "Download
-- Excel File" (FileID 0433bfdb-8a3d-44db-9015-90cbbf48f6f6): sheets الأفراد (171 individuals), التنظيمات
-- (75 organisations), الكيانات (entities), plus two de-listing sheets that are excluded. The .xls parses
-- with SheetJS; the PDF is not parsed. No JSON/XML endpoint exists for the UAE list — the FileID changes when
-- a new file is published, so the edge function re-reads the page for the current "Download Excel File"
-- link and falls back to the last known FileID. That limitation is recorded on every screening_run row.
-- Registered suppliers today: 1 lead in lifecycle_stage registered / approval_status approved.
--
-- WHAT THIS FILE BUILDS
--   screening_run / screening_entry        one row per source per weekly fetch (source, entries, fetched_at,
--                                           sha256, status, note) and the parsed names (normalised + tokenised
--                                           by trigger, so the SQL is the single normaliser).
--   supplier_screening_hit                  a match between a registered supplier field and an entry: open →
--                                           confirmed / false_positive. Never an automatic removal.
--   fn_supplier_sanctions_screen(runs,tag)  screens registered suppliers (legal name, licence name, owner,
--                                           contact, e-mail domain label) by normalised EXACT match and by
--                                           CONSERVATIVE token overlap (>= 2 significant tokens, full
--                                           containment); on a hit opens ONE task on the compliance officer
--                                           with the evidence and ONE on the BD manager (hold outreach and
--                                           onboarding). Team update = tasks on BD and compliance, never the founder.
--   fn_supplier_screening_decide(hit, d, by) the compliance officer's decision: confirmed moves the supplier
--                                           through the EXISTING status path (leads.banned + banned_reason,
--                                           matching_blocked, approval_status rejected — the same columns
--                                           fn_ban_overdue_dues uses) and closes both tasks as facts;
--                                           false_positive closes the hit.
--   fn_sanctions_screen_tick()              the cron command: posts to the sanctions_screen edge function
--                                           (downloads, parses, stores, then calls fn_supplier_sanctions_screen)
--                                           with a credential scoped to that one callee.
--   sanctions_screen_weekly                 pg_cron Mondays 03:00 UTC (07:00 Dubai), wrapped and traced by the
--                                           kernel under compliance_and_privacy_officer / legal; registered for
--                                           the Phase D door; edge:sanctions_screen declared as a component in
--                                           SYSTEM_SCOPE (no phase_b workflow step), like the cron row.
-- This loop is NOT behind supplier_outreach_golive: it sends nothing and removes nobody by itself, and the
-- founder asked for the weekly check as such; the acquisition switch governs outreach.
--
--   node scripts/apply_sql.mjs scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql --apply --ddl
begin;

-- ---------------------------------------------------------------- the lists, as fetched
create table if not exists public.screening_run (
  id          bigserial primary key,
  source      text not null,                       -- 'un_consolidated' | 'uae_local_terrorist_list'
  source_url  text,
  fetched_at  timestamptz not null default now(),
  sha256      text,
  entries     integer not null default 0,
  status      text not null default 'ok' check (status in ('ok', 'failed', 'unparseable')),
  note        text,
  run_tag     text,
  created_at  timestamptz not null default now()
);
create table if not exists public.screening_entry (
  id          bigserial primary key,
  run_id      bigint not null references public.screening_run(id) on delete cascade,
  source      text not null,
  entry_type  text not null check (entry_type in ('individual', 'entity')),
  reference   text,
  name        text not null,
  name_norm   text,
  tokens      text[]
);
create index if not exists screening_entry_run_idx  on public.screening_entry (run_id);
create index if not exists screening_entry_norm_idx on public.screening_entry (name_norm);
create table if not exists public.supplier_screening_hit (
  id              bigserial primary key,
  run_id          bigint references public.screening_run(id) on delete set null,
  lead_id         bigint not null references public.leads(id) on delete cascade,
  field           text not null,
  supplier_value  text,
  entry_id        bigint,
  entry_name      text,
  entry_source    text not null,
  entry_reference text not null default '',
  entry_type      text,
  match_kind      text not null check (match_kind in ('exact', 'token_overlap')),
  score           numeric,
  status          text not null default 'open' check (status in ('open', 'confirmed', 'false_positive')),
  task_id         bigint,
  bd_task_id      bigint,
  decided_by      text,
  decided_at      timestamptz,
  created_at      timestamptz not null default now(),
  unique (lead_id, entry_source, entry_reference, field)
);
alter table public.screening_run enable row level security;
alter table public.screening_entry enable row level security;
alter table public.supplier_screening_hit enable row level security;
revoke all on public.screening_run, public.screening_entry, public.supplier_screening_hit from public, anon, authenticated;
grant select, insert, update on public.screening_run, public.screening_entry to service_role;
grant usage on sequence public.screening_run_id_seq, public.screening_entry_id_seq to service_role;

-- ---------------------------------------------------------------- one normaliser, in SQL
create or replace function public.fn_screening_normalise(p text)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select nullif(btrim(regexp_replace(
           regexp_replace(
             ' ' || regexp_replace(
               translate(lower(coalesce(p, '')), 'áàâäãåéèêëíìîïóòôöõúùûüçñýÿ', 'aaaaaaeeeeiiiiooooouuuucnyy'),
               '[^[:alnum:][:space:]]+', ' ', 'g') || ' ',
             '\s(llc|l l c|fze|fzc|fzco|fz|ltd|limited|inc|co|company|corp|corporation|est|establishment|trading|general|contracting|contractors|services|group|international|technical|the|of|and|for|in|dmcc|plc|sarl|sal|gmbh|bv|sole|proprietorship)(?=\s)', ' ', 'g'),
           '\s+', ' ', 'g')), '');
$function$;

create or replace function public.fn_screening_tokens(p text)
returns text[]
language sql
immutable
set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(array(
    select distinct t from unnest(string_to_array(coalesce(public.fn_screening_normalise(p), ''), ' ')) t
     where length(t) >= 3
       and t <> all (array['abd','abdul','abdel','bin','ibn','abu','bint','umm','von','van','der','del','della','les','das','dos'])
     order by t), '{}'::text[]);
$function$;

create or replace function public.trg_screening_entry_normalise()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  new.name_norm := public.fn_screening_normalise(new.name);
  new.tokens    := public.fn_screening_tokens(new.name);
  return new;
end $function$;
drop trigger if exists a00_screening_entry_normalise on public.screening_entry;
create trigger a00_screening_entry_normalise before insert or update of name on public.screening_entry
for each row execute function public.trg_screening_entry_normalise();

-- ---------------------------------------------------------------- the screen
create or replace function public.fn_supplier_sanctions_screen(p_run_ids bigint[], p_rehearsal_tag text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_reh boolean := p_rehearsal_tag is not null;
  v_suppliers int := 0; v_entries int := 0; v_new int := 0; v_leads_hit int := 0; v_open int := 0;
  v_sources text; r record; h record; v_task bigint; v_bd bigint; v_title text; v_bd_title text; v_hits text;
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

  -- the team update: one task on compliance with the evidence, one on BD to hold outreach; never the founder
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
      values ('legal', v_title,
              'The weekly sanctions screening (' || coalesce(v_sources, 'fixture run') || ') matched a REGISTERED supplier. EVIDENCE:' || E'\n' || r.ev
              || E'\n\n' || 'No automatic removal has happened. Compare the supplier''s trade licence, owner and address against the listing and decide, per hit: '
              || 'select public.fn_supplier_screening_decide(<hit_id>, ''confirmed'' | ''false_positive'', ''compliance_mgr''). '
              || 'A confirmed hit moves the supplier through the existing status path (leads.banned + banned_reason, matching_blocked, approval_status rejected) and closes this task and the BD hold; a false positive closes the hit. '
              || 'Hit id(s): ' || r.ids || '.',
              'assigned', 'supervised', false, 'compliance_check', 'compliance_mgr')
      returning id into v_task;
    end if;
    v_bd_title := 'Hold outreach and onboarding: ' || coalesce(r.company_name, 'lead #' || r.lead_id) || ' — lead #' || r.lead_id || ' (sanctions screening)';
    select id into v_bd from public.org_tasks where title = v_bd_title and status not in ('done', 'cancelled') order by id limit 1;
    if v_bd is null then
      insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, assigned_agent)
      values ('supply', v_bd_title,
              'Compliance is reviewing a sanctions-screening match on this supplier (task #' || v_task || '). Send no invitation, follow-up or onboarding step to lead #' || r.lead_id
              || ' until compliance decides; this task closes with that decision.',
              'assigned', 'autonomous', false, 'coordinate', 'bd')
      returning id into v_bd;
    end if;
    update public.supplier_screening_hit set task_id = v_task, bd_task_id = v_bd
     where lead_id = r.lead_id and status = 'open' and task_id is null;
    v_leads_hit := v_leads_hit + 1;
  end loop;

  -- retention: the latest fetch per source is the list; older entries go (their run rows stay as the record)
  if not v_reh then
    delete from public.screening_entry e
     where e.run_id not in (select max(id) from public.screening_run where status = 'ok' group by source);
  end if;

  select count(*) into v_open from public.supplier_screening_hit where status = 'open';
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('supplier_sanctions_screen', 'ok',
          jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open,
                             'runs', to_jsonb(p_run_ids), 'rehearsal', v_reh),
          'Sanctions screening: ' || v_suppliers || ' registered supplier(s) screened against ' || v_entries || ' list entries (' || coalesce(v_sources, 'no run') || '): '
          || v_new || ' new hit(s) on ' || v_leads_hit || ' supplier(s); ' || v_open || ' open. A hit opens a compliance task and a BD hold; nobody is removed automatically.'
          || case when v_reh then ' [rehearsal ' || p_rehearsal_tag || ']' else '' end, now(), now());
  return jsonb_build_object('suppliers', v_suppliers, 'entries', v_entries, 'hits_new', v_new, 'leads_hit', v_leads_hit, 'hits_open', v_open, 'sources', v_sources);
end $function$;
revoke execute on function public.fn_supplier_sanctions_screen(bigint[], text) from public, anon, authenticated;
grant execute on function public.fn_supplier_sanctions_screen(bigint[], text) to service_role;

-- ---------------------------------------------------------------- the decision, through the existing status path
create or replace function public.fn_supplier_screening_decide(p_hit_id bigint, p_decision text, p_actor text default 'compliance_mgr')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare h record; v_open int; v_closed int := 0; t bigint; v jsonb;
begin
  if p_decision not in ('confirmed', 'false_positive') then
    raise exception 'fn_supplier_screening_decide: decision must be confirmed or false_positive, not %', p_decision;
  end if;
  select * into h from public.supplier_screening_hit where id = p_hit_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such hit ' || p_hit_id); end if;
  if h.status <> 'open' then return jsonb_build_object('ok', false, 'reason', 'hit ' || p_hit_id || ' is already ' || h.status); end if;

  update public.supplier_screening_hit set status = p_decision, decided_by = p_actor, decided_at = now() where id = p_hit_id;

  if p_decision = 'confirmed' then
    -- the same columns fn_ban_overdue_dues writes: banned + reason, matching blocked, and the approval withdrawn
    update public.leads
       set banned = true,
           banned_reason = 'Sanctions screening hit confirmed by ' || p_actor || ' on ' || to_char(now(), 'DD Mon YYYY') || ': '
                           || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || ') matched ' || h.field || ' "' || coalesce(h.supplier_value, '') || '".',
           matching_blocked = true,
           matching_block_reason = 'Banned: sanctions screening hit confirmed (' || h.entry_source || ')',
           approval_status = case when approval_status = 'approved' then 'rejected' else approval_status end,
           rejection_reason = coalesce(rejection_reason, 'sanctions screening hit confirmed')
     where id = h.lead_id;
    -- every other open hit on the same supplier is decided by the same fact
    update public.supplier_screening_hit set status = 'confirmed', decided_by = p_actor, decided_at = now()
     where lead_id = h.lead_id and status = 'open';
  end if;

  select count(*) into v_open from public.supplier_screening_hit where lead_id = h.lead_id and status = 'open';
  if v_open = 0 then
    foreach t in array array_remove(array[h.task_id, h.bd_task_id], null) loop
      v := public.fn_org_task_close_as_fact(t, p_actor,
             case when p_decision = 'confirmed'
                  then 'Sanctions screening hit CONFIRMED by ' || p_actor || ': ' || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || '). The supplier (lead #' || h.lead_id || ') is banned through the existing status path: leads.banned, matching_blocked, approval withdrawn. Outreach and onboarding stop.'
                  else 'Sanctions screening hit reviewed by ' || p_actor || ' and recorded as a FALSE POSITIVE: ' || h.entry_source || ' ' || h.entry_reference || ' (' || h.entry_name || ') is not lead #' || h.lead_id || '. No status change; outreach and onboarding may continue.' end,
             jsonb_build_object('hit_id', p_hit_id, 'decision', p_decision, 'lead_id', h.lead_id, 'owner', p_actor));
      if coalesce((v ->> 'ok')::boolean, false) then v_closed := v_closed + 1; end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'hit_id', p_hit_id, 'decision', p_decision, 'lead_id', h.lead_id, 'open_hits_left', v_open, 'tasks_closed', v_closed);
end $function$;
revoke execute on function public.fn_supplier_screening_decide(bigint, text, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_screening_decide(bigint, text, text) to service_role;

-- ---------------------------------------------------------------- the cron command
create or replace function public.fn_sanctions_screen_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'net', 'pg_temp'
as $function$
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
    body    := jsonb_build_object('__secret', v_secret, 'caller', 'cron.sanctions_screen_weekly'),
    timeout_milliseconds := 120000
  ) into v_req;
  return jsonb_build_object('posted', true, 'request_id', v_req);
end $function$;
revoke execute on function public.fn_sanctions_screen_tick() from public, anon, authenticated;
grant execute on function public.fn_sanctions_screen_tick() to service_role;

-- ---------------------------------------------------------------- credential, component, clock, owner, door
do $cron$
declare v_job bigint; v jsonb; v_cred jsonb;
begin
  if not exists (select 1 from public.app_secrets where key = 'cred_cron_compliance') then
    v_cred := public.fn_internal_credential_issue('cron.compliance', array['sanctions_screen'],
                'weekly sanctions screening tick -> sanctions_screen (6 Sep 2026)');
    insert into public.app_secrets (key, value) values ('cred_cron_compliance', v_cred ->> 'secret');
  end if;

  insert into public.phase_c_component (
    component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
    schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id, department_id,
    workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy,
    activation_state, classification, gap, repair_or_keep_action, evidence, measured_at)
  values (
    'edge:sanctions_screen', 'edge_function', 'supabase/functions/sanctions_screen/index.ts',
    'invoked by repo/database/cron caller', 'fn_sanctions_screen_tick (cron sanctions_screen_weekly) with credential context cron.compliance',
    'internal_credential_only', 'weekly, Mondays 03:00 UTC via cron sanctions_screen_weekly',
    true, 'service_role', 'system.scheduler', 'compliance_and_privacy_officer', 'legal',
    -- SYSTEM_SCOPE / '' like its cron sibling: the weekly screen is a scheduled system routine owned by the
    -- compliance officer, not a step of a phase_b workflow. (The first cut copied workflow_id/step_id from
    -- edge:uptime_check, which bound it to W29 'Security incident and reliability recovery' / W29-S01 'Open
    -- incident' under it_operations_engineer — measured wrong 6 Sep 2026 and corrected here.)
    'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION', 'request:source:sha256',
    'next_scheduled_tick', 'deployed', 'WIRE_TO_CANONICAL', '',
    'keep; downloads the UN consolidated list (XML) and the UAE local terrorist list (.xls), stores screening_run/screening_entry, then screens registered suppliers through fn_supplier_sanctions_screen (no model, no removal)',
    'built 6 Sep 2026 (scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql)', now())
  on conflict (component_id) do update set
    activation_state = excluded.activation_state, classification = excluded.classification, accountable_role_id = excluded.accountable_role_id,
    department_id = excluded.department_id, workflow_id = excluded.workflow_id, step_id = excluded.step_id,
    current_callers = excluded.current_callers, evidence = excluded.evidence, measured_at = excluded.measured_at;

  select jobid into v_job from cron.job where jobname = 'sanctions_screen_weekly';
  if v_job is null then
    v_job := cron.schedule('sanctions_screen_weekly', '0 3 * * 1', 'select public.fn_sanctions_screen_tick();');
  end if;
  v := public.fn_kernel_wrap_and_enable_cron(v_job, 'compliance_and_privacy_officer', 'legal', 'routine_operational_decision');
  if coalesce((v ->> 'ok')::boolean, false) is not true then raise exception 'fn_kernel_wrap_and_enable_cron(%) refused: %', v_job, v; end if;
  update public.phase_c_component
     set repair_or_keep_action = 'built 6 Sep 2026: the compliance officer''s weekly sanctions screening of registered suppliers (UN consolidated XML + UAE local list .xls); a hit opens tasks on compliance and BD, never a removal by itself',
         evidence = 'scheduled and wrapped 6 Sep 2026 (scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql)'
   where component_id = 'cron:sanctions_screen_weekly';

  insert into public.cron_registry (jobname, human_name, category, purpose) values
    ('sanctions_screen_weekly', 'Weekly sanctions screening (compliance officer)', 'Legal',
     'fn_sanctions_screen_tick() — Mondays 03:00 UTC: posts to the sanctions_screen edge function, which downloads the UN consolidated list (XML) and the UAE local terrorist list (.xls), records a screening_run per source (entries, fetched_at, sha256) and screens every registered supplier (legal name, licence name, owner, contact, e-mail domain) by normalised exact match and conservative token overlap. A hit opens one task on the compliance officer with the evidence and one hold on the BD manager; a confirmed hit is moved through the existing ban path by fn_supplier_screening_decide. No model, no automatic removal, never the founder.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine) values
    (v_job, 'sanctions_screen_weekly',
     'POSTs to the sanctions_screen edge function through pg_net; the function INSERTs public.screening_run / public.screening_entry and public.agent_runs, then fn_supplier_sanctions_screen INSERTs public.supplier_screening_hit and, on a hit, public.org_tasks (compliance + BD). It UPDATEs nothing on public.leads (a removal needs fn_supplier_screening_decide by the compliance officer).',
     'Weekly, Mondays 03:00 UTC, in its own transactions. Without a rehearsal tag the screen EXCLUDES every ZZ DEMO — / @example.invalid lead by predicate, and its list entries carry no fixture marker; a scenario''s fixtures are invisible to it. close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $cron$;

-- ---------------------------------------------------------------- the ownership ledger follows the manifest
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification, recorded_at)
values
  ('public', 'fn_screening_normalise', 'p text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql', null, now()),
  ('public', 'fn_screening_tokens', 'p text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql', null, now()),
  ('public', 'trg_screening_entry_normalise', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql', null, now()),
  ('public', 'fn_supplier_sanctions_screen', 'p_run_ids bigint[], p_rehearsal_tag text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql', null, now()),
  ('public', 'fn_supplier_screening_decide', 'p_hit_id bigint, p_decision text, p_actor text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql', null, now()),
  ('public', 'fn_sanctions_screen_tick', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql', null, now())
on conflict (schema_name, routine_name, identity_args) do update set ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file, justification = null, recorded_at = now();

-- ---------------------------------------------------------------- proof, in the same transaction
do $proof$
declare n int; v_job bigint;
begin
  if public.fn_screening_normalise('Al-Qaida Trading L.L.C.') <> 'al qaida' then raise exception 'normaliser: %', public.fn_screening_normalise('Al-Qaida Trading L.L.C.'); end if;
  if public.fn_screening_tokens('Abd Al-Rahman Bin Umayr Al-Nuaymi') <> array['nuaymi','rahman','umayr'] then raise exception 'tokens: %', public.fn_screening_tokens('Abd Al-Rahman Bin Umayr Al-Nuaymi'); end if;
  select count(*) into n from public.app_secrets where key = 'cred_cron_compliance' and length(value) >= 32;
  if n <> 1 then raise exception 'cred_cron_compliance was not issued'; end if;
  select jobid into v_job from cron.job where jobname = 'sanctions_screen_weekly' and active and command ilike '%fn_kernel_cron_exec%';
  if v_job is null then raise exception 'sanctions_screen_weekly is not wrapped and active'; end if;
  select count(*) into n from public.phase_c_component
   where component_id in ('edge:sanctions_screen', 'cron:sanctions_screen_weekly') and workflow_id = 'SYSTEM_SCOPE' and step_id = '';
  if n <> 2 then raise exception 'components missing or bound to a workflow step (% of 2 in SYSTEM_SCOPE)', n; end if;
  raise notice 'proof: normaliser and tokens right, credential issued, cron % wrapped and active, 2 components declared', v_job;
end $proof$;

commit;
