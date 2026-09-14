-- THE IT ENGINEER FIXES WHAT IT FINDS, AND EMAILS THE FOUNDER ONLY A NEW BUG.
--
-- Assigned: it_engineer (classification, playbook, re-verification, new-bug email, Dropbox health,
-- the daily line), with ceo (acknowledges the daily line) and accountant (the Dropbox renewal date).
-- 14 Sep 2026. No model call anywhere: every decision here is a rule and every message a template.
--
-- The founder, 14 Sep 2026 (founder_instruction 208-212):
--   "we need to eliminate all other causes with fixes. unless its a server issue from dropbox or
--    supabase then i see no reason for any failures"
--   "option 2 'anything else' basically mean i need to interfere with a session in claude to fix
--    that. and sometimes i am busy. how can we avoid it? how can the IT engineer actually fix stuff
--    instead of just reporting"
--   "option 1, but for new bugs i just need to be notified on email"
--   "also we should not rely on the LLM as much as possible in the operation"
--   "always make sure things are in loop. nothing literally should ever be a one way communication"
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production): public.agent_remediation existed with 0 rows
-- (status open/training/retesting/passed/escalated/abandoned); founder_mail_policy had no kind for a
-- new bug; the daily IT line counted rows but never classified a failure; the only it_engineer
-- response to any finding was a handoff to the sales engineer. Dropbox: plan 'pro', 62.6 GB of
-- 539 GB used (11.6%); public.expenses holds no Dropbox row and no routine read expenses.next_due.
--
-- THE CONTRACT (generic, keyed by domain; other it_engineer duties reuse it):
--   fn_it_classify_failure(domain, error)  -> a failure class. 'provider_outage' is the only class
--        that is not a defect (Dropbox or Supabase server errors, 429, timeouts); every other class
--        is internal.
--   it_playbook_entry(domain, failure_class, action, fix, verify) -> the fixes on file.
--   fn_it_playbook_run(domain, class, items[], why, demo, at_risk) -> runs fn_it_playbook_<domain>(class,
--        items) and records the fix in agent_remediation (status 'retesting'). No entry -> new bug.
--   fn_it_playbook_verify() -> for each 'retesting' fix, fn_it_playbook_<domain>_verify(detail,
--        opened_at) answers passed / failed / waiting; passed closes it (and its new bug), failed or
--        still waiting after 48 hours escalates it -> new bug.
--   fn_it_new_bug_notify(domain, class, reason, what, since, affected, tried, at_risk, ref, demo)
--        -> ONE email per bug class (kind 'it_new_bug', a delivery.request to customer_support), an open
--        agent_actions item (kind 'it_new_bug') and a CEO report; a repeat while open or within 7 days
--        of closing only counts (the daily line), it never emails again. Reasons: no_playbook_entry,
--        fix_did_not_hold, provider_outage_over_6h. Demo bugs are addressed to
--        founder.it-new-bug@example.invalid, which zzzz_notifications_demo_capture suppresses.
--   fn_it_new_bug_close(domain, class, evidence) -> only the it_engineer closes a bug
--        (trg_it_new_bug_only_it_engineer_closes), with the evidence.
--   A new domain adds: its classes to fn_it_classify_failure, rows to it_playbook_entry, and the pair
--   fn_it_playbook_<domain>(text, jsonb) / fn_it_playbook_<domain>_verify(jsonb, timestamptz).
--
-- BACKUP DOMAIN:
--   auto-fixed  never_queued, missing_in_dropbox, mismatch, auth, path_rejected, timeout_large,
--               source_missing (relink, else source_lost -> the CEO), stuck_no_run, backlog,
--               unknown (three more tries with backoff, then escalate).
--   not a defect provider_outage: the uploader retries with backoff; > 6 hours -> new bug email.
--   emailed     storage_full, render_failed, dropbox_auth_revoked, any class with no entry, any fix
--               whose re-check failed, provider outage > 6 h.
--   The CEO sees everything in the daily line and acknowledges it (fn_ceo_acknowledges_it_reports);
--   an IT report left unacknowledged past its review time reaches the founder through
--   fn_it_ceo_silence_watch (the_it_engineer_closes_every_loop_it_opens.sql).
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_fixes_what_it_finds_and_emails_only_a_new_bug.sql --apply --ddl

-- ── 1. THE MAIL KIND ──────────────────────────────────────────────────────────────────────────────
-- founder_mail_policy 'it_new_bug' (allowed, owner it_engineer) is already registered by
-- the_it_engineer_closes_every_loop_it_opens.sql; this file uses it and does not restate it. The
-- email goes the way that file sends it: a 'delivery.request' handoff to customer_support, the only
-- sender (customer_support_is_the_only_sender_on_email_and_whatsapp.sql), which reports back.
do $check$ begin
  assert exists (select 1 from public.founder_mail_policy where kind = 'it_new_bug' and allowed_to_email), 'founder_mail_policy it_new_bug is missing';
end $check$;

-- ── 2. CLASSIFICATION ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_classify_failure(p_domain text, p_error text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_domain is distinct from 'backup' then 'unknown'
    when e ~* '(no_dropbox_auth|invalid_access_token|expired_access_token|invalid_grant|\m401\M)' then 'auth'
    when e ~* '(insufficient_space|over_quota)' then 'storage_full'
    when e ~* '(malformed_path|disallowed_name|too_long|path/(malformed|disallowed)|restricted_content)' then 'path_rejected'
    when e ~* 'missing in Dropbox' then 'missing_in_dropbox'
    when e ~* '(content_hash mismatch|content_hash in Dropbox differs|verify: size)' then 'mismatch'
    when e ~* '(pdf_native|unknown_gen_kind)' then 'render_failed'
    when e ~* '(supplier_missing|customer_missing|inquiry_missing|no_source|object not found|not in storage|storage holds no object|download (range )?4[0-9][0-9])' then 'source_missing'
    when e ~* '(WORKER_RESOURCE_LIMIT|out of memory|claim by .* expired|resuming:)' then 'timeout_large'
    when e ~* '(\m5[0-9][0-9]\M|\m429\M|too_many_requests|timed? ?out|network|ECONNRESET|connection (reset|refused|closed)|fetch failed|service unavailable|bad gateway)' then 'provider_outage'
    else 'unknown' end
  from (select coalesce(p_error, '') as e) z
$fn$;
revoke execute on function public.fn_it_classify_failure(text, text) from public, anon, authenticated;

-- ── 3. THE PLAYBOOK ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.it_playbook_entry (
  domain        text not null,
  failure_class text not null,
  action        text not null,
  fix           text not null,
  verify        text not null,
  created_at    timestamptz not null default now(),
  primary key (domain, failure_class));
alter table public.it_playbook_entry enable row level security;
drop policy if exists it_playbook_entry_service_role_only on public.it_playbook_entry;
create policy it_playbook_entry_service_role_only on public.it_playbook_entry as permissive for all to public using (false) with check (false);
revoke all on public.it_playbook_entry from anon, authenticated;
comment on table public.it_playbook_entry is
  'The IT engineer''s fixes on file, by domain and failure class. A failure class with no row here is a new bug: the founder is emailed once (fn_it_new_bug_notify).';

insert into public.it_playbook_entry (domain, failure_class, action, fix, verify) values
  ('backup', 'never_queued',       'enqueue_from_registry',  'Run the enqueue; file any item it does not cover as a row of its own.', 'Each item has a row that is done and verified in Dropbox after the fix.'),
  ('backup', 'missing_in_dropbox', 'force_reupload',         'Requeue the row; the uploader overwrites the file and re-reads its metadata.', 'Row done and verified after the fix.'),
  ('backup', 'mismatch',           'force_reupload',         'Requeue the row; the uploader overwrites the file and re-reads its metadata.', 'Row done and verified after the fix.'),
  ('backup', 'auth',               'refresh_token_retry',    'Requeue; the next run takes a fresh token and repeats a 401 once.', 'Row done and verified after the fix.'),
  ('backup', 'path_rejected',      'resanitise_strict',      'Rebuild the Dropbox path with 80-character components keeping the id suffix; requeue.', 'Row done and verified after the fix.'),
  ('backup', 'timeout_large',      'chunked_resume',         'Requeue keeping the upload session; the chunked upload resumes from its offset.', 'Row done and verified after the fix.'),
  ('backup', 'source_missing',     'relink_or_source_lost',  'Search every backed-up bucket for the same file name and relink; otherwise mark the row source_lost with the evidence and report it to the CEO.', 'Relinked rows done and verified; lost rows recorded and reported.'),
  ('backup', 'stuck_no_run',       'invoke_backup',          'The IT engineer kicks dropbox_backup itself (fn_backup_kick).', 'A successful dropbox_backup run after the fix.'),
  ('backup', 'backlog',            'drain_in_batches',       'Kick dropbox_backup; a full batch calls itself again until the queue is empty.', 'A successful run after the fix and fewer than 50 rows queued.'),
  ('backup', 'unknown',            'retry_backoff_3x',       'Requeue with three more attempts on exponential backoff, then classify again.', 'Row done and verified after the fix.')
on conflict (domain, failure_class) do update set action = excluded.action, fix = excluded.fix, verify = excluded.verify;

-- ── 4. THE NEW BUG ────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_new_bug_notify(
  p_domain text, p_class text, p_reason text, p_what text, p_since timestamptz, p_affected integer,
  p_tried text, p_at_risk text, p_ref text, p_demo boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_key text := p_domain || ':' || p_class; a public.agent_actions; v_id bigint; v_subj text; v_body text;
  v_mail jsonb; v_nid bigint; v_demo boolean := coalesce(p_demo, false);
begin
  if p_reason not in ('no_playbook_entry', 'fix_did_not_hold', 'provider_outage_over_6h') then
    raise exception 'fn_it_new_bug_notify: unknown reason %', p_reason;
  end if;
  if coalesce(btrim(p_what), '') = '' then raise exception 'fn_it_new_bug_notify: say what failed'; end if;

  select * into a from public.agent_actions
   where agent = 'it_engineer' and kind = 'it_new_bug' and detail->>'bug_key' = v_key
     and coalesce((detail->>'demo')::boolean, false) = v_demo
     and (status = 'pending' or decided_at > now() - interval '7 days')
   order by id desc limit 1 for update;
  if found then
    -- a repeat: counted for the daily line, never a second email; a closed bug that returns reopens
    perform set_config('qd.it_bug_closer', 'it_engineer', true);
    update public.agent_actions
       set status = 'pending', decided_at = null, decided_by = null,
           detail = detail || jsonb_build_object('repeats', coalesce((detail->>'repeats')::int, 0) + 1, 'last_seen', now(),
                                                 'last_reason', p_reason, 'last_affected', p_affected, 'reopened', status <> 'pending')
     where id = a.id;
    perform set_config('qd.it_bug_closer', '', true);
    return jsonb_build_object('emailed', false, 'repeat', true, 'bug_id', a.id);
  end if;

  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
  values ('it_engineer', 'it_new_bug', 'pending', 'high', left('New bug: ' || p_what, 200),
          'The IT engineer emailed the founder once and closes this only when re-verification passes.',
          'it_playbook_entry', v_key,
          jsonb_build_object('bug_key', v_key, 'domain', p_domain, 'class', p_class, 'reason', p_reason, 'what', p_what,
                             'since', coalesce(p_since, now()), 'affected', p_affected, 'tried', p_tried, 'at_risk', p_at_risk,
                             'ref', p_ref, 'demo', v_demo, 'repeats', 0, 'last_seen', now()))
  returning id into v_id;

  v_subj := 'New problem the IT engineer could not fix: ' || left(p_what, 120);
  v_body := 'What failed: ' || p_what || E'\n'
         || 'Since: ' || to_char(coalesce(p_since, now()) at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai time)' || E'\n'
         || 'Items affected: ' || coalesce(p_affected, 0) || E'\n'
         || 'What the IT engineer already tried: ' || coalesce(nullif(btrim(p_tried), ''), 'nothing yet') || E'\n'
         || 'Is anything at risk now: ' || coalesce(nullif(btrim(p_at_risk), ''), 'not known') || E'\n'
         || 'Why this reached you: ' || case p_reason
              when 'no_playbook_entry' then 'there is no automatic fix on file for this kind of failure'
              when 'fix_did_not_hold' then 'the automatic fix ran and the re-check failed'
              else 'the provider has been failing for more than 6 hours' end || E'\n'
         || 'Reference: IT-' || v_id || ' (' || v_key || coalesce(', ' || p_ref, '') || ')' || E'\n\n'
         || 'You get one email per new problem. Repeats are counted in the daily line and are not emailed again. '
         || 'This stays open until the IT engineer has verified the fix.';

  if v_demo then
    insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel)
    values ('founder_alert', 'it_new_bug', 'founder.it-new-bug@example.invalid', 'founder', '[Attention] ' || v_subj, v_body, 'queued', 'email')
    returning id into v_nid;
    v_mail := jsonb_build_object('demo', true, 'notification_id', v_nid);
  else
    v_mail := jsonb_build_object('delivery_request', public.fn_seat_handoff('it_engineer', 'customer_support', 'delivery.request',
      'agent_actions', v_id::text,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'it_new_bug', 'level', 'high',
                         'event', v_subj, 'detail', v_body, 'dedupe_key', 'it_new_bug:' || v_key)));
    v_mail := v_mail || jsonb_build_object('ceo', public.fn_support_report_to_ceo(
      'it_new_bug:' || v_id, 'serious', v_subj,
      (select detail from public.agent_actions where id = v_id), jsonb_build_array(jsonb_build_object('tried', p_tried)),
      'Note it. The IT engineer has emailed the founder and closes this only when re-verification passes.',
      p_review_in => interval '1 day', p_source_agent => 'it_engineer'));
  end if;
  update public.agent_actions set detail = detail || jsonb_build_object('mail', v_mail) where id = v_id;
  return jsonb_build_object('emailed', true, 'bug_id', v_id, 'mail', v_mail);
end $fn$;
revoke execute on function public.fn_it_new_bug_notify(text, text, text, text, timestamptz, integer, text, text, text, boolean) from public, anon, authenticated;

-- Only the it_engineer closes a bug it opened: the loop's originator is its only closer.
create or replace function public.trg_it_new_bug_only_it_engineer_closes()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.kind = 'it_new_bug' and new.status is distinct from old.status
     and coalesce(current_setting('qd.it_bug_closer', true), '') <> 'it_engineer' then
    raise exception 'only the it_engineer changes the state of a new bug (%), through fn_it_new_bug_close or fn_it_new_bug_notify', new.id;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_it_new_bug_only_it_engineer_closes() from public, anon, authenticated;
drop trigger if exists z61_it_new_bug_only_it_engineer_closes on public.agent_actions;
create trigger z61_it_new_bug_only_it_engineer_closes before update of status on public.agent_actions
  for each row execute function public.trg_it_new_bug_only_it_engineer_closes();

create or replace function public.fn_it_new_bug_close(p_domain text, p_class text, p_evidence text)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n int;
begin
  if coalesce(btrim(p_evidence), '') = '' then raise exception 'fn_it_new_bug_close: evidence is required'; end if;
  perform set_config('qd.it_bug_closer', 'it_engineer', true);
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = 'it_engineer',
         detail = detail || jsonb_build_object('closed_evidence', p_evidence, 'closed_at', now())
   where agent = 'it_engineer' and kind = 'it_new_bug' and status = 'pending' and detail->>'bug_key' = p_domain || ':' || p_class;
  get diagnostics n = row_count;
  perform set_config('qd.it_bug_closer', '', true);
  return n;
end $fn$;
revoke execute on function public.fn_it_new_bug_close(text, text, text) from public, anon, authenticated;

-- A bug with no fix on file closes when the IT engineer has not seen it for 36 hours (a daily check
-- runs in between): the evidence is the silence of the check that found it.
create or replace function public.fn_it_new_bug_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare b record; n int := 0;
begin
  for b in select detail->>'domain' d, detail->>'class' c, detail->>'last_seen' s from public.agent_actions
            where agent = 'it_engineer' and kind = 'it_new_bug' and status = 'pending'
              and (detail->>'last_seen')::timestamptz < now() - interval '36 hours' loop
    n := n + public.fn_it_new_bug_close(b.d, b.c, 'not seen by the IT engineer''s checks for 36 hours (last seen ' || b.s || ')');
  end loop;
  return jsonb_build_object('closed', n);
end $fn$;
revoke execute on function public.fn_it_new_bug_sweep() from public, anon, authenticated;

-- ── 5. RUN AND VERIFY (generic) ───────────────────────────────────────────────────────────────────
create or replace function public.fn_it_playbook_run(p_domain text, p_class text, p_items jsonb, p_why text,
                                                     p_demo boolean default false, p_at_risk text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare e public.it_playbook_entry; v_items jsonb := coalesce(p_items, '[]'::jsonb); v_res jsonb; v_id bigint;
begin
  if coalesce(p_domain, '') !~ '^[a-z][a-z_]{1,40}$' or coalesce(p_class, '') !~ '^[a-z][a-z0-9_]{1,60}$' then
    raise exception 'fn_it_playbook_run: bad domain or class %/%', p_domain, p_class;
  end if;
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then raise exception 'fn_it_playbook_run: items must be a non-empty json array'; end if;
  if exists (select 1 from public.agent_remediation r
              where r.agent_key = 'it_engineer' and r.status = 'retesting' and r.failure_class = p_domain || ':' || p_class
                and r.detail->'items' @> v_items) then
    return jsonb_build_object('skipped', 'already being fixed', 'domain', p_domain, 'class', p_class);
  end if;

  select * into e from public.it_playbook_entry where domain = p_domain and failure_class = p_class;
  if not found then
    return jsonb_build_object('entry', false, 'class', p_class, 'new_bug', public.fn_it_new_bug_notify(
      p_domain, p_class, 'no_playbook_entry', coalesce(p_why, p_domain || ' ' || p_class),
      (select min((i->>'since')::timestamptz) from jsonb_array_elements(v_items) i where i ? 'since'),
      jsonb_array_length(v_items), 'Nothing automatic: there is no fix on file for this kind of failure.',
      coalesce(p_at_risk, 'The affected items are not confirmed until this is fixed.'),
      'first item ' || left(v_items->0->>'key', 80), p_demo));
  end if;

  execute format('select public.%I($1, $2)', 'fn_it_playbook_' || p_domain) into v_res using p_class, v_items;
  insert into public.agent_remediation (agent_key, failure_class, competency, opened_at, status, attempts, max_attempts, blocks_autonomy, detail)
  values ('it_engineer', p_domain || ':' || p_class, e.action, now(), 'retesting', 1, 1, false,
          jsonb_build_object('domain', p_domain, 'class', p_class, 'what', e.fix, 'verify', e.verify, 'why', p_why,
                             'result', v_res, 'items', v_items, 'demo', coalesce(p_demo, false)))
  returning id into v_id;
  return jsonb_build_object('entry', true, 'class', p_class, 'remediation_id', v_id, 'action', e.action, 'result', v_res);
end $fn$;
revoke execute on function public.fn_it_playbook_run(text, text, jsonb, text, boolean, text) from public, anon, authenticated;

create or replace function public.fn_it_playbook_verify()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.agent_remediation; v text; n_pass int := 0; n_fail int := 0; n_wait int := 0; d text;
begin
  for r in select * from public.agent_remediation where agent_key = 'it_engineer' and status = 'retesting' order by id for update skip locked loop
    d := r.detail->>'domain';
    execute format('select public.%I($1, $2)', 'fn_it_playbook_' || d || '_verify') into v using r.detail, r.opened_at;
    if v = 'waiting' and r.opened_at < now() - interval '48 hours' then v := 'failed'; end if;
    if v = 'passed' then
      update public.agent_remediation set status = 'passed', closed_at = now(), latest_score = 1,
             detail = detail || jsonb_build_object('verified_at', now()) where id = r.id;
      perform public.fn_it_new_bug_close(d, r.detail->>'class', 'the automatic fix held: remediation ' || r.id || ' re-verified');
      n_pass := n_pass + 1;
    elsif v = 'failed' then
      update public.agent_remediation set status = 'escalated', closed_at = now(), latest_score = 0,
             detail = detail || jsonb_build_object('verified_at', now(), 'verdict', 'fix did not hold') where id = r.id;
      perform public.fn_it_new_bug_notify(d, r.detail->>'class', 'fix_did_not_hold', coalesce(r.detail->>'why', r.failure_class),
        r.opened_at, jsonb_array_length(r.detail->'items'),
        'Ran "' || r.competency || '" (' || (r.detail->>'what') || ') at ' || to_char(r.opened_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai; the re-check failed.',
        'The affected items are still not confirmed.', 'remediation ' || r.id, coalesce((r.detail->>'demo')::boolean, false));
      n_fail := n_fail + 1;
    else n_wait := n_wait + 1;
    end if;
  end loop;
  return jsonb_build_object('passed', n_pass, 'failed', n_fail, 'waiting', n_wait);
end $fn$;
revoke execute on function public.fn_it_playbook_verify() from public, anon, authenticated;

-- ── 6. THE BACKUP DOMAIN ──────────────────────────────────────────────────────────────────────────
-- Filing an expected item that has no row: extracted from fn_sales_engineer_refiles_backup so the
-- sales engineer's refile and the IT engineer's fix share one implementation.
create or replace function public.fn_backup_file_expected_item(p jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_row bigint;
begin
  select x.doc_backup_id into v_row from public.fn_it_backup_expected_status() x where x.item_key = p->>'item_key';
  if v_row is null and p->>'bucket' is not null and p->>'kind' <> 'conversation' then
    insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key)
    values (split_part(p->>'owner', ':', 1), split_part(p->>'owner', ':', 2), 'Refiled', p->>'bucket', p->>'path',
            regexp_replace(p->>'path', '^.*/', ''), '/QuotesDone Backup/Refiled/' || (p->>'bucket') || '/' || (p->>'path'),
            'storage', 'REFILE:' || (p->>'bucket') || ':' || (p->>'path'))
    on conflict do nothing returning id into v_row;
  elsif v_row is null and p->>'kind' = 'generated' then
    insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
    values (split_part(p->>'owner', ':', 1), split_part(p->>'owner', ':', 2), 'Refiled', 'generated', p->>'gen_kind', p->>'gen_ref',
            '/QuotesDone Backup/Refiled/' || (p->>'gen_kind') || '/' || (p->>'gen_ref') || '.pdf', 'REFILE:' || (p->>'item_key'))
    on conflict do nothing returning id into v_row;
  end if;
  return v_row;
end $fn$;
revoke execute on function public.fn_backup_file_expected_item(jsonb) from public, anon, authenticated;

-- fn_sales_engineer_refiles_backup: the MANIFEST-last definition (the_it_engineer_knows_what_should_be_
-- backed_up_and_closes_the_loop.sql) with its inline filing replaced by fn_backup_file_expected_item.
create or replace function public.fn_sales_engineer_refiles_backup(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; fin jsonb; fout jsonb := '[]'::jsonb; v_att int; v_row bigint; n int; v_out text;
  v_enq boolean := false; s record;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_att := coalesce((a.detail->>'refile_attempts')::int, 0) + 1;
  fin := coalesce(a.detail->'files',
           jsonb_build_array(jsonb_build_object('key', 'db:' || (a.detail->>'doc_backup_id'), 'reason', a.detail->>'reason',
                                                'doc_backup_id', (a.detail->>'doc_backup_id')::bigint)));
  for s in select e from jsonb_array_elements(fin) e loop
    v_row := (s.e->>'doc_backup_id')::bigint; v_out := null;
    if v_row is null then
      -- never queued: the enqueue first, then a row of our own for what it does not cover
      if not v_enq then perform public.fn_enqueue_doc_backups(); v_enq := true; end if;
      v_row := public.fn_backup_file_expected_item(s.e);
      v_out := case when v_row is null then 'cannot_refile: no source to file from' else 'queued' end;
    end if;
    if v_row is not null and v_out is null then
      update public.doc_backups
         set status = 'pending', attempts = 0, verified_at = null, requeued_at = now(),
             error = left('refile ' || v_att || ': ' || coalesce(s.e->>'reason', 'requested') || ' (handoff ' || p_id || ')', 300)
       where id = v_row and status <> 'abandoned';
      get diagnostics n = row_count;
      v_out := case when n = 1 then 'requeued' else 'cannot_refile: row missing or abandoned' end;
    end if;
    fout := fout || (s.e || jsonb_build_object('doc_backup_id', v_row, 'refile', v_out));
  end loop;
  update public.agent_actions
     set detail = detail || jsonb_build_object('files', fout, 'refile_attempts', v_att, 'refiled_at', now(), 'sales_done_at', now())
   where id = p_id;
  return jsonb_build_object('waiting', 'it_engineer re-verification', 'refile_attempt', v_att, 'files', fout);
end $fn$;
revoke execute on function public.fn_sales_engineer_refiles_backup(bigint) from public, anon, authenticated;

create or replace function public.fn_it_playbook_backup(p_class text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_ids bigint[] := array(select (i->>'doc_backup_id')::bigint from jsonb_array_elements(p_items) i where i->>'doc_backup_id' is not null);
  v_fixed bigint[] := '{}'; v_lost jsonb := '[]'::jsonb; s jsonb; v_row bigint; d public.doc_backups; v_b text; v_p text; v_rep jsonb;
begin
  if p_class = 'never_queued' then
    perform public.fn_enqueue_doc_backups();
    for s in select value from jsonb_array_elements(p_items) loop
      v_row := coalesce((s->>'doc_backup_id')::bigint, public.fn_backup_file_expected_item(s));
      if v_row is null then v_lost := v_lost || (s || jsonb_build_object('evidence', 'no source to file from'));
      else v_fixed := v_fixed || v_row; end if;
    end loop;
    update public.doc_backups set status = 'pending', attempts = 0, verified_at = null, requeued_at = now(),
           error = 'it_engineer playbook: never_queued'
     where id = any(v_fixed) and status in ('pending', 'error');

  elsif p_class in ('missing_in_dropbox', 'mismatch', 'auth', 'path_rejected', 'timeout_large', 'unknown') then
    with u as (
      update public.doc_backups
         set status = 'pending', verified_at = null, requeued_at = now(), claimed_at = null, claimed_by = null,
             attempts = case when p_class = 'unknown' then 2 else 0 end,
             dropbox_path = case when p_class = 'path_rejected' then public.fn_dbx_path(dropbox_path, true) else dropbox_path end,
             upload_state = case when p_class = 'timeout_large' then upload_state end,
             error = 'it_engineer playbook: ' || p_class
       where id = any(v_ids) and status not in ('abandoned', 'processing')
      returning id)
    select coalesce(array_agg(id), '{}') into v_fixed from u;

  elsif p_class = 'source_missing' then
    for d in select * from public.doc_backups where id = any(v_ids) and status <> 'processing' loop
      v_b := null; v_p := null;
      if d.path is not null then
        select o.bucket_id, o.name into v_b, v_p from storage.objects o
         where o.bucket_id in (select r.bucket from public.fn_backup_source_registry() r where r.kind = 'bucket' and r.backed_up)
           and (o.name = regexp_replace(d.path, '^.*/', '') or o.name like '%/' || regexp_replace(d.path, '^.*/', ''))
           and not exists (select 1 from public.doc_backups x where x.bucket = o.bucket_id and x.path = o.name)
         order by o.created_at desc limit 1;
      end if;
      if v_p is not null then
        update public.doc_backups set bucket = v_b, path = v_p, status = 'pending', attempts = 0, requeued_at = now(),
               error = left('it_engineer playbook: relinked from ' || d.bucket || '/' || d.path, 300)
         where id = d.id;
        v_fixed := v_fixed || d.id;
      else
        update public.doc_backups
           set status = 'abandoned',
               error = left('abandoned: source_lost - ' || coalesce(d.bucket || '/' || d.path, d.gen_kind || ' ' || d.gen_ref)
                            || ' is in no backed-up bucket under that file name and its owner record is gone (it_engineer, '
                            || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || ')', 300)
         where id = d.id;
        v_lost := v_lost || jsonb_build_object('doc_backup_id', d.id, 'source', coalesce(d.bucket || '/' || d.path, d.gen_kind || ':' || d.gen_ref),
                                               'dropbox_path', d.dropbox_path, 'demo', d.entity = 'zz_demo');
      end if;
    end loop;
    -- a lost original is the one outcome only the CEO can decide on (ask the owner again, or accept)
    if exists (select 1 from jsonb_array_elements(v_lost) l where not coalesce((l->>'demo')::boolean, false)) then
      v_rep := public.fn_support_report_to_ceo('it_source_lost:' || md5(v_lost::text), 'serious',
        jsonb_array_length(v_lost) || ' document(s) cannot be backed up: the original is gone',
        jsonb_build_object('lost', v_lost), jsonb_build_array(jsonb_build_object('action', 'searched every backed-up bucket for the same file name')),
        'Decide whether the owner must be asked for the document again. The rows are recorded as abandoned with the evidence; nothing else can recover them.',
        p_review_in => interval '1 day', p_source_agent => 'it_engineer');
    end if;

  elsif p_class in ('stuck_no_run', 'backlog') then
    return jsonb_build_object('kick', public.fn_backup_kick('it_engineer:' || p_class, 'enqueue'));
  else
    raise exception 'fn_it_playbook_backup: no handler for %', p_class;
  end if;
  return jsonb_build_object('fixed', to_jsonb(v_fixed), 'lost', v_lost, 'ceo_report', v_rep);
end $fn$;
revoke execute on function public.fn_it_playbook_backup(text, jsonb) from public, anon, authenticated;

create or replace function public.fn_it_playbook_backup_verify(p jsonb, p_opened timestamptz)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_class text := p->>'class';
  v_fixed bigint[] := array(select jsonb_array_elements_text(coalesce(p->'result'->'fixed', '[]'::jsonb))::bigint);
  n_total int; n_ok int; n_bad int;
begin
  if v_class in ('stuck_no_run', 'backlog') then
    return case when exists (select 1 from public.agent_runs where agent = 'dropbox_backup' and status = 'ok' and started_at > p_opened)
                 and (v_class = 'stuck_no_run' or (select count(*) from public.doc_backups
                                                    where status in ('pending', 'error', 'processing') and attempts < 5 and entity <> 'zz_demo') < 50)
                then 'passed' else 'waiting' end;
  end if;
  if cardinality(v_fixed) = 0 then
    return case when jsonb_array_length(coalesce(p->'result'->'lost', '[]'::jsonb)) > 0 then 'passed' else 'failed' end;
  end if;
  select count(*), count(*) filter (where status = 'done' and verified_at > p_opened),
         count(*) filter (where status in ('abandoned', 'skipped_large') or (status = 'error' and attempts >= 5))
    into n_total, n_ok, n_bad from public.doc_backups where id = any(v_fixed);
  return case when n_bad > 0 or n_total < cardinality(v_fixed) then 'failed' when n_ok = n_total then 'passed' else 'waiting' end;
end $fn$;
revoke execute on function public.fn_it_playbook_backup_verify(jsonb, timestamptz) from public, anon, authenticated;

-- ── 7. THE DAILY CHECK NOW FIXES BEFORE IT HANDS OVER ─────────────────────────────────────────────
-- fn_it_backup_check: the MANIFEST-last definition with three additions: parked rows older than an
-- hour are findings (source_missing); every finding is classified and run through the playbook; only
-- a class with no fix on file still goes to the sales engineer (and has already emailed a new bug).
create or replace function public.fn_it_backup_check(p_results jsonb, p_job text default 'dropbox_daily_check', p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r jsonb; v_id bigint; v_out text; f jsonb := '[]'::jsonb; x record; d public.doc_backups; g record;
  n_ok int := 0; n_unver int := 0; n_err int := 0; v_h bigint; v_status text; c jsonb;
  v_pb jsonb; v_fixes jsonb := '{}'::jsonb; v_handover text[] := '{}';
  v_weekly boolean := exists (select 1 from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) e where e->>'why' = 'weekly');
begin
  if p_error is not null then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'error', jsonb_build_object('job', p_job, 'stage', 'fatal'),
            left('The IT engineer''s Dropbox check did not run: ' || p_error || '. Retried after 6 hours.', 500), now(), now());
    return jsonb_build_object('ok', false, 'error', p_error);
  end if;

  -- (2) doc_backups vs Dropbox
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    v_id := (r->>'id')::bigint; v_out := r->>'outcome';
    if v_out = 'ok' then
      update public.doc_backups set dropbox_content_hash = r->>'hash', dropbox_size = (r->>'size')::bigint, verified_at = now()
       where id = v_id and status = 'done';
      n_ok := n_ok + 1;
    elsif v_out in ('missing', 'changed') then
      update public.doc_backups set verified_at = null,
             error = case when v_out = 'missing' then 'it_engineer: missing in Dropbox' else 'it_engineer: size/content_hash in Dropbox differs' end
       where id = v_id returning * into d;
      if found then
        f := f || jsonb_build_object('key', 'db:' || d.id, 'reason', case when v_out = 'missing' then 'missing_in_dropbox' else 'mismatch' end,
               'doc_backup_id', d.id, 'dropbox_path', d.dropbox_path, 'bucket', d.bucket, 'path', d.path, 'demo', d.entity = 'zz_demo');
      end if;
    elsif v_out = 'unverifiable' then n_unver := n_unver + 1;
    else n_err := n_err + 1;
    end if;
  end loop;

  if p_job = 'dropbox_daily_check' then
    -- (1) expected vs doc_backups: never queued, past a 24-hour grace
    for x in select * from public.fn_it_backup_expected_status() s
              where s.doc_backup_id is null and s.since < now() - interval '24 hours' loop
      f := f || jsonb_build_object('key', 'exp:' || x.item_key, 'reason', 'never_queued', 'item_key', x.item_key, 'kind', x.kind,
             'bucket', x.bucket, 'path', x.path, 'gen_kind', x.gen_kind, 'gen_ref', x.gen_ref, 'owner', x.owner, 'since', x.since, 'demo', false);
    end loop;
    -- (3) the uploader gave up
    for d in select * from public.doc_backups b
              where b.entity <> 'zz_demo' and ((b.status = 'error' and b.attempts >= 5) or b.status = 'skipped_large') loop
      f := f || jsonb_build_object('key', 'db:' || d.id, 'reason', 'upload_failed', 'doc_backup_id', d.id, 'dropbox_path', d.dropbox_path,
             'bucket', d.bucket, 'path', d.path, 'error', d.error, 'since', d.created_at, 'demo', false);
    end loop;
    -- (4) a queued document whose original storage never received
    for d in select * from public.doc_backups b
              where b.entity <> 'zz_demo' and b.status = 'waiting_source' and b.created_at < now() - interval '1 hour' loop
      f := f || jsonb_build_object('key', 'db:' || d.id, 'reason', 'source_missing', 'doc_backup_id', d.id, 'dropbox_path', d.dropbox_path,
             'bucket', d.bucket, 'path', d.path, 'error', d.error, 'since', d.created_at, 'demo', false);
    end loop;
  end if;

  -- a file already in an open refile or remediation is not handed over twice
  select coalesce(jsonb_agg(e), '[]'::jsonb) into f
    from jsonb_array_elements(f) e
   where not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' in ('backup.refile', 'backup.remediate')
                        and exists (select 1 from jsonb_array_elements(a.detail->'files') g2 where g2->>'key' = e->>'key'));

  -- THE IT ENGINEER FIXES FIRST (founder, 14 Sep 2026). One playbook run per class.
  select coalesce(jsonb_agg(e || jsonb_build_object('class',
           case when e->>'reason' = 'upload_failed' then public.fn_it_classify_failure('backup', e->>'error') else e->>'reason' end)), '[]'::jsonb)
    into f from jsonb_array_elements(f) e;
  for g in select e->>'class' as cls, jsonb_agg(e) as items, bool_or(coalesce((e->>'demo')::boolean, false)) as demo
             from jsonb_array_elements(f) e group by 1 loop
    if g.cls = 'provider_outage' then
      v_fixes := v_fixes || jsonb_build_object(g.cls, jsonb_build_object('waiting', 'the provider; the uploader retries with backoff', 'items', jsonb_array_length(g.items)));
      continue;
    end if;
    v_pb := public.fn_it_playbook_run('backup', g.cls, g.items,
              jsonb_array_length(g.items) || ' document(s) found by the ' || p_job || ': ' || g.cls, g.demo,
              jsonb_array_length(g.items) || ' document(s) are not confirmed in Dropbox; each original is still in Supabase storage unless recorded as lost.');
    v_fixes := v_fixes || jsonb_build_object(g.cls, v_pb);
    if v_pb->>'entry' = 'false' then v_handover := v_handover || g.cls; end if;
  end loop;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into f from jsonb_array_elements(f) e where e->>'class' = any(v_handover);

  if jsonb_array_length(f) > 0 then
    v_h := public.fn_seat_handoff('it_engineer', 'sales_engineer', 'backup.refile', 'doc_backups',
             'check:' || p_job || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'),
             jsonb_build_object('files', f, 'job', p_job, 'refile_attempts', 0));
  end if;

  c := jsonb_build_object('job', p_job, 'weekly', v_weekly, 'checked', jsonb_array_length(coalesce(p_results, '[]'::jsonb)),
         'confirmed', n_ok, 'unverifiable', n_unver, 'read_errors', n_err, 'findings', jsonb_array_length(f),
         'by_reason', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select e->>'reason' k, count(*) n from jsonb_array_elements(f) e group by 1) z),
         'playbook', v_fixes, 'handoff', v_h);
  v_status := case when jsonb_array_length(f) + n_err > 0 then 'warn' else 'ok' end;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, c,
          left('IT engineer Dropbox check (' || p_job || '): ' || (c->>'checked') || ' read in Dropbox, ' || n_ok || ' confirmed; fixed itself: '
               || (select coalesce(string_agg(k, ', '), 'nothing to fix') from jsonb_object_keys(v_fixes) k)
               || '; ' || jsonb_array_length(f) || ' finding(s) with no fix on file'
               || case when v_h is not null then ', handed to the sales engineer as handoff ' || v_h else '' end || '.', 500),
          now(), now());
  return c || jsonb_build_object('status', v_status);
end $fn$;
revoke execute on function public.fn_it_backup_check(jsonb, text, text) from public, anon, authenticated;

-- The queue itself: nothing running, a backlog, or a provider failing for 6 hours.
create or replace function public.fn_it_backup_queue_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_q int; v_last timestamptz; v_ok timestamptz; v_note text; o jsonb := '{}'::jsonb;
begin
  select count(*) into v_q from public.doc_backups where status in ('pending', 'error') and attempts < 5 and entity <> 'zz_demo';
  select max(started_at) into v_last from public.agent_runs where agent = 'dropbox_backup';
  select max(started_at) into v_ok from public.agent_runs where agent = 'dropbox_backup' and status = 'ok';
  if v_q > 0 and coalesce(v_last, '-infinity') < now() - interval '2 hours' then
    o := o || jsonb_build_object('stuck', public.fn_it_playbook_run('backup', 'stuck_no_run', '[{"key":"queue"}]'::jsonb,
                v_q || ' document(s) queued and no backup run for 2 hours'));
  end if;
  if v_q >= 50 then
    o := o || jsonb_build_object('backlog', public.fn_it_playbook_run('backup', 'backlog', '[{"key":"queue"}]'::jsonb, v_q || ' document(s) queued'));
  end if;
  select note into v_note from public.agent_runs where agent = 'dropbox_backup' and status = 'error' order by id desc limit 1;
  if v_q > 0 and coalesce(v_ok, '-infinity') < now() - interval '6 hours' and public.fn_it_classify_failure('backup', v_note) = 'provider_outage' then
    o := o || jsonb_build_object('provider', public.fn_it_new_bug_notify('backup', 'provider_outage', 'provider_outage_over_6h',
                'Dropbox or Supabase storage has been failing for more than 6 hours', v_ok, v_q,
                'Retried on every run with backoff; the failures are the provider''s (server errors or timeouts), not ours.',
                v_q || ' document(s) are waiting; every one is still in Supabase storage and is sent as soon as the provider recovers.',
                'dropbox_backup runs', false));
  end if;
  return o || jsonb_build_object('queued', v_q, 'last_run', v_last, 'last_ok', v_ok);
end $fn$;
revoke execute on function public.fn_it_backup_queue_watch() from public, anon, authenticated;

-- ── 8. DROPBOX HEALTH: auth probe, space, plan; the renewal date is the accountant's ─────────────
create or replace function public.fn_it_dropbox_health_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select not exists (select 1 from public.agent_runs r where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_health'
                        and r.status in ('ok', 'warn') and (r.started_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date)
     and not exists (select 1 from public.agent_runs r where r.agent = 'it_engineer' and r.counts->>'job' = 'dropbox_health'
                        and r.status = 'error' and r.started_at > now() - interval '2 hours');
$fn$;
revoke execute on function public.fn_it_dropbox_health_due() from public, anon, authenticated;

create or replace function public.fn_it_dropbox_health_record(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_pct numeric; v_status text; v_cls text; v_rep jsonb; v_bug jsonb; v_gap bigint;
  v_date text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
begin
  if jsonb_typeof(p) is distinct from 'object' then raise exception 'fn_it_dropbox_health_record: the reading must be a json object'; end if;
  v_pct := case when coalesce((p->>'allocated')::numeric, 0) > 0 then round((p->>'used')::numeric * 100 / (p->>'allocated')::numeric, 1) end;
  if p->>'error' is not null or not coalesce((p->>'write_ok')::boolean, false) or not coalesce((p->>'read_ok')::boolean, false) then
    v_status := 'error';
    v_cls := public.fn_it_classify_failure('backup', coalesce(p->>'error', 'auth probe incomplete'));
    if v_cls = 'auth' then
      v_bug := public.fn_it_new_bug_notify('backup', 'dropbox_auth_revoked', 'no_playbook_entry',
        'Dropbox refused the company''s stored authorisation', now(),
        (select count(*)::int from public.doc_backups where status in ('pending', 'error') and entity <> 'zz_demo'),
        'Took a fresh access token from the stored refresh token and repeated the call once; Dropbox still refused.',
        'New documents are not reaching Dropbox until the connection is authorised again. Every document is still kept in Supabase storage.',
        'dropbox health probe', false);
    end if;
  elsif v_pct >= 85 then
    v_status := 'warn';
    v_rep := public.fn_support_report_to_ceo('dropbox_space_85:' || v_date, 'serious', 'Dropbox is ' || v_pct || '% full',
      p, '[]'::jsonb, 'Decide on more Dropbox space or an archive policy; at 100% new documents stop reaching Dropbox.',
      p_review_in => interval '1 day', p_source_agent => 'it_engineer');
  elsif v_pct >= 70 then v_status := 'warn';
  else v_status := 'ok';
  end if;

  -- a paid plan renews; the accountant keeps its date. The IT engineer opened the item, so the IT
  -- engineer closes it once the date is in the books.
  if coalesce(p->>'plan', '') not in ('', 'basic', 'unknown')
     and not exists (select 1 from public.expenses where active and vendor ilike 'dropbox%' and next_due is not null)
     and not exists (select 1 from public.agent_actions where agent = 'accountant' and kind = 'subscription_record_missing'
                        and status = 'pending' and target_id = 'Dropbox') then
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
    values ('accountant', 'subscription_record_missing', 'pending', 'medium',
            'Dropbox ' || (p->>'plan') || ' plan has no renewal date in the books',
            'Record the Dropbox subscription in public.expenses (amount, cadence, next_due) from its receipt in the expenses mailbox. The IT engineer re-checks every day and closes this when the renewal date is on file.',
            'expenses', 'Dropbox', jsonb_build_object('plan', p->>'plan', 'measured_at', now(), 'opened_by', 'it_engineer'))
    returning id into v_gap;
  end if;
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = 'it_engineer',
         detail = detail || jsonb_build_object('closed_evidence', 'an active Dropbox expenses row with next_due is on file')
   where agent = 'accountant' and kind = 'subscription_record_missing' and status = 'pending' and target_id = 'Dropbox'
     and exists (select 1 from public.expenses where active and vendor ilike 'dropbox%' and next_due is not null);

  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', v_status, jsonb_build_object('job', 'dropbox_health', 'pct_used', v_pct, 'class', v_cls) || p,
          left('Dropbox health: probe write ' || coalesce(p->>'write_ok', 'false') || ', read ' || coalesce(p->>'read_ok', 'false')
               || ', delete ' || coalesce(p->>'delete_ok', 'false') || '; ' || coalesce(v_pct::text || '% of the ' || (p->>'plan') || ' plan used', 'space not read')
               || coalesce('; error ' || (p->>'error'), ''), 500), now(), now());
  return jsonb_build_object('status', v_status, 'pct_used', v_pct, 'class', v_cls, 'ceo_report', v_rep, 'new_bug', v_bug, 'accountant_item', v_gap);
end $fn$;
revoke execute on function public.fn_it_dropbox_health_record(jsonb) from public, anon, authenticated;

-- The accountant's renewal rule, for every subscription with a date on file. Its own item closes
-- when next_due moves past the date it reminded about (the receipt was booked).
create or replace function public.fn_accountant_subscription_renewals_due()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n_new int; n_closed int;
begin
  with due as (
    update public.expenses e set last_reminded_at = now()
     where e.active and e.next_due is not null and current_date >= e.next_due - e.reminder_days
       and (e.last_reminded_at is null or e.last_reminded_at < (e.next_due - e.reminder_days)::timestamptz)
    returning e.*)
  insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
  select 'accountant', 'subscription_renewal', 'pending', 'medium', due.vendor || ' renews on ' || to_char(due.next_due, 'DD Mon YYYY'),
         'Confirm the card on file covers it, and move next_due forward when the receipt is booked.', 'expenses', due.id::text,
         jsonb_build_object('vendor', due.vendor, 'next_due', due.next_due, 'amount', due.amount, 'currency', due.currency)
    from due;
  get diagnostics n_new = row_count;
  update public.agent_actions a set status = 'done', decided_at = now(), decided_by = 'accountant',
         detail = a.detail || jsonb_build_object('closed_evidence', 'next_due moved to ' || e.next_due)
    from public.expenses e
   where a.agent = 'accountant' and a.kind = 'subscription_renewal' and a.status = 'pending'
     and e.id::text = a.target_id and e.next_due > (a.detail->>'next_due')::date;
  get diagnostics n_closed = row_count;
  return jsonb_build_object('reminded', n_new, 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_accountant_subscription_renewals_due() from public, anon, authenticated;

-- ── 9. THE DAILY LINE, AND THE CEO ACKNOWLEDGES IT ────────────────────────────────────────────────
-- fn_dropbox_backup_summary: the MANIFEST-last definition plus the IT engineer's own day: fixes,
-- failures by class (provider vs internal), open new bugs and repeats, Dropbox space; and the queue
-- counts 'processing' (claimed) and 'waiting_source' (parked) rows.
create or replace function public.fn_dropbox_backup_summary()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with e as (select * from public.fn_it_backup_expected_status()),
  ex as (
    select count(*) as expected,
           count(*) filter (where status = 'done') as backed_up,
           count(*) filter (where status = 'done' and verified_at is not null) as verified,
           count(*) filter (where doc_backup_id is null) as never_queued
      from e),
  f as (
    select
      count(*) filter (where created_at > now() - interval '24 hours')                  as queued_24h,
      count(*) filter (where backed_up_at > now() - interval '24 hours')                as uploaded_24h,
      count(*) filter (where verified_at > now() - interval '24 hours')                 as verified_24h,
      count(*) filter (where status in ('pending','error','processing') and coalesce(attempts,0) < 5) as pending,
      count(*) filter (where status = 'waiting_source')                                 as waiting_source,
      count(*) filter (where status = 'done')                                           as uploaded_total,
      count(*) filter (where status = 'done' and verified_at is not null)               as verified_total,
      count(*) filter (where (status = 'error' and attempts >= 5) or status = 'skipped_large') as failed,
      count(*) filter (where status = 'abandoned')                                      as abandoned,
      count(*)                                                                          as total
    from public.doc_backups where entity <> 'zz_demo'),
  h as (select count(*) as open_handoffs from public.agent_actions
         where kind = 'handoff' and status = 'pending' and detail->>'type' in ('backup.refile','backup.remediate')),
  cls as (select public.fn_it_classify_failure('backup', error) as c, count(*) as n from public.doc_backups
           where entity <> 'zz_demo' and status = 'error' and last_attempt_at > now() - interval '24 hours' group by 1),
  it as (
    select
      (select count(*) from public.agent_remediation where agent_key = 'it_engineer' and failure_class like 'backup:%'
          and opened_at > now() - interval '24 hours' and not coalesce((detail->>'demo')::boolean, false)) as auto_fixes_24h,
      (select count(*) from public.agent_remediation where agent_key = 'it_engineer' and failure_class like 'backup:%' and status = 'passed'
          and closed_at > now() - interval '24 hours' and not coalesce((detail->>'demo')::boolean, false)) as fixes_verified_24h,
      (select count(*) from public.agent_remediation where agent_key = 'it_engineer' and failure_class like 'backup:%' and status = 'escalated'
          and closed_at > now() - interval '24 hours' and not coalesce((detail->>'demo')::boolean, false)) as fixes_failed_24h,
      (select count(*) from public.agent_actions where agent = 'it_engineer' and kind = 'it_new_bug' and status = 'pending'
          and not coalesce((detail->>'demo')::boolean, false)) as open_new_bugs,
      (select coalesce(sum((detail->>'repeats')::int), 0) from public.agent_actions where agent = 'it_engineer' and kind = 'it_new_bug'
          and status = 'pending' and not coalesce((detail->>'demo')::boolean, false)) as new_bug_repeats,
      (select coalesce(sum(n) filter (where c = 'provider_outage'), 0) from cls) as failures_provider_24h,
      (select coalesce(sum(n) filter (where c <> 'provider_outage'), 0) from cls) as failures_internal_24h,
      (select coalesce(jsonb_object_agg(c, n), '{}'::jsonb) from cls) as failures_by_class_24h,
      (select (counts->>'pct_used')::numeric from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'dropbox_health'
          order by id desc limit 1) as dropbox_pct_used)
  select to_jsonb(ex) || to_jsonb(f) || to_jsonb(h) || to_jsonb(it) || jsonb_build_object('line',
    'Dropbox backup: ' || ex.expected || ' expected, ' || ex.backed_up || ' backed up, ' || ex.verified || ' verified in Dropbox, '
    || ex.never_queued || ' never queued; queue ' || f.pending || ' pending, ' || f.waiting_source || ' waiting for their original, ' || f.failed || ' failed, '
    || h.open_handoffs || ' open refile handoff(s). Last 24h: ' || f.queued_24h || ' queued, ' || f.uploaded_24h || ' uploaded, '
    || f.verified_24h || ' verified. IT engineer, last 24h: ' || it.auto_fixes_24h || ' automatic fix(es) (' || it.fixes_verified_24h || ' verified, '
    || it.fixes_failed_24h || ' did not hold); failures ' || it.failures_provider_24h || ' provider outage, ' || it.failures_internal_24h || ' internal '
    || it.failures_by_class_24h::text || '; ' || it.open_new_bugs || ' open new bug(s) emailed to the founder (' || it.new_bug_repeats || ' repeat(s) not re-emailed); Dropbox '
    || coalesce(it.dropbox_pct_used::text || '% full', 'space not yet read') || '. All rows: ' || f.uploaded_total || ' uploaded (' || f.verified_total || ' verified), '
    || f.abandoned || ' abandoned with a recorded reason, of ' || f.total || '.',
    'measured_at', now())
  from ex, f, h, it;
$fn$;
revoke execute on function public.fn_dropbox_backup_summary() from public, anon, authenticated;

create or replace function public.fn_dropbox_backup_daily_report()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local timestamp := now() at time zone 'Asia/Dubai'; s jsonb;
begin
  if v_local::time < time '19:00' then
    return jsonb_build_object('filed', false, 'reason', 'before 19:00 Asia/Dubai');
  end if;
  if exists (select 1 from public.support_ceo_report
              where idempotency_key = 'dropbox_backup_daily:' || to_char(v_local, 'YYYY-MM-DD')) then
    return jsonb_build_object('filed', false, 'reason', 'already filed today');
  end if;
  s := public.fn_dropbox_backup_summary();
  return public.fn_support_report_to_ceo(
    'dropbox_backup_daily:' || to_char(v_local, 'YYYY-MM-DD'),
    case when (s->>'failed')::int > 0 or (s->>'never_queued')::int > 0 or (s->>'open_handoffs')::int > 0
              or (s->>'open_new_bugs')::int > 0 or (s->>'fixes_failed_24h')::int > 0 then 'elevated' else 'routine' end,
    'Dropbox backup ' || to_char(v_local, 'DD Mon') || ': ' || (s->>'line'),
    s, '[]'::jsonb,
    'Acknowledge the day''s backup position. The IT engineer fixed what it could itself and has already emailed the founder any new bug; a line not acknowledged by its review time reaches the founder (fn_it_ceo_silence_watch).',
    p_review_in => interval '1 day', p_source_agent => 'it_engineer') || jsonb_build_object('filed', true);
end $fn$;
revoke execute on function public.fn_dropbox_backup_daily_report() from public, anon, authenticated;

-- The CEO reads the daily line and the new-bug reports and acknowledges them with a receipt.
create or replace function public.fn_ceo_acknowledges_it_reports()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n int;
begin
  update public.support_ceo_report r
     set status = 'accepted', accepted_at = now(),
         acceptance_receipt = case when r.idempotency_key like 'dropbox_backup_daily:%'
           then 'ceo: read the IT engineer''s daily backup line - ' || coalesce(r.verified_evidence->>'auto_fixes_24h', '0') || ' automatic fix(es), '
                || coalesce(r.verified_evidence->>'open_new_bugs', '0') || ' open new bug(s), each already emailed to the founder.'
           else 'ceo: noted the new bug; the founder has the email and the IT engineer closes it on re-verification.' end
   where r.source_agent = 'it_engineer' and r.status = 'sent'
     and (r.idempotency_key like 'dropbox_backup_daily:%' or r.idempotency_key like 'it_new_bug:%');
  get diagnostics n = row_count;
  return jsonb_build_object('acknowledged', n);
end $fn$;
revoke execute on function public.fn_ceo_acknowledges_it_reports() from public, anon, authenticated;

-- ── 10. THE TICK ──────────────────────────────────────────────────────────────────────────────────
-- fn_it_backup_tick: the MANIFEST-last definition plus the IT engineer's own stages, each failing
-- through fn_it_backup_stage_failed like the others, and 'health_due' for resilience_ping.
create or replace function public.fn_it_backup_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o jsonb := '{}'::jsonb;
begin
  begin o := o || jsonb_build_object('recheck', public.fn_it_backup_recheck());
  exception when others then o := o || jsonb_build_object('recheck', public.fn_it_backup_stage_failed('recheck', sqlerrm)); end;
  begin o := o || jsonb_build_object('playbook_verify', public.fn_it_playbook_verify());
  exception when others then o := o || jsonb_build_object('playbook_verify', public.fn_it_backup_stage_failed('playbook_verify', sqlerrm)); end;
  begin o := o || jsonb_build_object('queue', public.fn_it_backup_queue_watch());
  exception when others then o := o || jsonb_build_object('queue', public.fn_it_backup_stage_failed('queue', sqlerrm)); end;
  begin o := o || jsonb_build_object('new_bugs', public.fn_it_new_bug_sweep());
  exception when others then o := o || jsonb_build_object('new_bugs', public.fn_it_backup_stage_failed('new_bugs', sqlerrm)); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_backup_escalation_sweep());
  exception when others then o := o || jsonb_build_object('ceo', public.fn_it_backup_stage_failed('ceo', sqlerrm)); end;
  begin o := o || jsonb_build_object('watch', public.fn_backup_watch());
  exception when others then o := o || jsonb_build_object('watch', public.fn_it_backup_stage_failed('watch', sqlerrm)); end;
  begin o := o || jsonb_build_object('daily', public.fn_dropbox_backup_daily_report());
  exception when others then o := o || jsonb_build_object('daily', public.fn_it_backup_stage_failed('daily', sqlerrm)); end;
  begin o := o || jsonb_build_object('ceo_ack', public.fn_ceo_acknowledges_it_reports());
  exception when others then o := o || jsonb_build_object('ceo_ack', public.fn_it_backup_stage_failed('ceo_ack', sqlerrm)); end;
  begin o := o || jsonb_build_object('renewals', public.fn_accountant_subscription_renewals_due());
  exception when others then o := o || jsonb_build_object('renewals', public.fn_it_backup_stage_failed('renewals', sqlerrm)); end;
  return o || jsonb_build_object('reconcile', public.fn_dropbox_reconcile_due(), 'health_due', public.fn_it_dropbox_health_due());
end $fn$;
revoke execute on function public.fn_it_backup_tick() from public, anon, authenticated;

-- ── 11. PROBE: every playbook entry, and the new-bug email, on ZZ DEMO rows; self-cleaning ────────
do $probe$
declare
  v_ids bigint[]; r jsonb; v_rem bigint[] := '{}'; v jsonb; n int; v_obj text; v_bug jsonb; v_bug2 jsonb; v_nid bigint;
  v_notif_before int := (select count(*) from public.notifications where kind = 'it_new_bug' and to_email not like '%@example.invalid');
  v_real_rem int := (select count(*) from public.agent_remediation where not coalesce((detail->>'demo')::boolean, false));
begin
  -- classification
  assert public.fn_it_classify_failure('backup', 'dbx_upload 503 busy after 3 tries') = 'provider_outage';
  assert public.fn_it_classify_failure('backup', 'no_dropbox_auth') = 'auth';
  assert public.fn_it_classify_failure('backup', 'supplier_missing') = 'source_missing';
  assert public.fn_it_classify_failure('backup', 'dbx_upload 409 {"error":{"path":{".tag":"malformed_path"}}}') = 'path_rejected';
  assert public.fn_it_classify_failure('backup', 'something nobody has seen') = 'unknown';

  -- one ZZ DEMO row per row-based entry
  select o.name into v_obj from storage.objects o where o.bucket_id = 'brand'
     and not exists (select 1 from public.doc_backups d where d.bucket = o.bucket_id and d.path = o.name) order by o.name limit 1;
  insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key, status, attempts, error)
  select 'zz_demo', 'zz_demo', 'ZZ DEMO', 'generated', 'zz_demo', c, '/QuotesDone Backup/_zz_demo/' || c || '.pdf', 'ZZDEMO:pb:' || c, 'error', 5, c
    from unnest(array['never_queued','missing_in_dropbox','mismatch','auth','path_rejected','timeout_large','unknown']) c;
  foreach r in array array(select jsonb_build_object('key', 'db:' || id, 'doc_backup_id', id, 'cls', gen_ref) from public.doc_backups where dedupe_key like 'ZZDEMO:pb:%') loop
    v := public.fn_it_playbook_run('backup', r->>'cls', jsonb_build_array(r - 'cls'), 'ZZ DEMO probe', true);
    assert (v->>'entry')::boolean and jsonb_array_length(v->'result'->'fixed') = 1, 'entry ' || (r->>'cls') || ': ' || v::text;
    v_rem := v_rem || (v->>'remediation_id')::bigint;
  end loop;
  assert (select count(*) from public.doc_backups where dedupe_key like 'ZZDEMO:pb:%' and status = 'pending') = 7, 'every row requeued';
  -- nothing running: the IT engineer invokes the backup itself (a real, harmless kick)
  v := public.fn_it_playbook_run('backup', 'stuck_no_run', '[{"key":"zz:queue"}]'::jsonb, 'ZZ DEMO probe', true);
  assert v->'result' ? 'kick', 'stuck_no_run kicks dropbox_backup: ' || v::text;
  assert (select attempts from public.doc_backups where dedupe_key = 'ZZDEMO:pb:unknown') = 2, 'unknown: three more tries';
  -- source_missing: one relinked (its file name exists in a backed-up bucket... here: nowhere -> lost)
  insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key, status, error)
  values ('zz_demo', 'zz_demo', 'ZZ DEMO', 'generated', 'supplier_details', '0', '/QuotesDone Backup/_zz_demo/lost.pdf', 'ZZDEMO:pb:lost', 'error', 'supplier_missing');
  v := public.fn_it_playbook_run('backup', 'source_missing',
         jsonb_build_array(jsonb_build_object('key', 'db:x', 'doc_backup_id', (select id from public.doc_backups where dedupe_key = 'ZZDEMO:pb:lost'))), 'ZZ DEMO probe', true);
  assert jsonb_array_length(v->'result'->'lost') = 1 and v->'result'->'ceo_report' = 'null'::jsonb, 'lost demo row recorded, no CEO report for demo';
  assert (select error from public.doc_backups where dedupe_key = 'ZZDEMO:pb:lost') like 'abandoned: source_lost%', 'source_lost evidence';
  v_rem := v_rem || (v->>'remediation_id')::bigint;
  -- the same items are not fixed twice while the fix is being verified
  assert public.fn_it_playbook_run('backup', 'mismatch', jsonb_build_array(jsonb_build_object('key', 'db:' || (select id from public.doc_backups where dedupe_key = 'ZZDEMO:pb:mismatch'),
           'doc_backup_id', (select id from public.doc_backups where dedupe_key = 'ZZDEMO:pb:mismatch'))), 'again', true) ? 'skipped', 'no double fix';

  -- re-verification: five rows 'uploaded' the way dropbox_backup marks them, one fails again
  update public.doc_backups set status = 'done', verified_at = now() + interval '1 second'
   where dedupe_key like 'ZZDEMO:pb:%' and dedupe_key not in ('ZZDEMO:pb:unknown', 'ZZDEMO:pb:lost');
  update public.doc_backups set status = 'error', attempts = 5 where dedupe_key = 'ZZDEMO:pb:unknown';
  v := public.fn_it_playbook_verify();
  assert (select count(*) from public.agent_remediation where id = any(v_rem) and status = 'passed') = 7, 'seven fixes held: ' || v::text;
  assert (select status from public.agent_remediation r where id = any(v_rem) and r.failure_class = 'backup:unknown') = 'escalated', 'the fix that did not hold escalates';
  assert (select count(*) from public.agent_actions where kind = 'it_new_bug' and detail->>'bug_key' = 'backup:unknown'
            and (detail->>'demo')::boolean and status = 'pending') = 1, 'fix_did_not_hold opened one demo bug';

  -- a class with no entry: exactly one email, captured; a repeat inside the window: none
  v_bug := public.fn_it_playbook_run('backup', 'zz_demo_class', '[{"key":"zz:1"}]'::jsonb, 'ZZ DEMO failure class with no playbook entry', true);
  v_bug2 := public.fn_it_playbook_run('backup', 'zz_demo_class', '[{"key":"zz:2"}]'::jsonb, 'ZZ DEMO failure class, again', true);
  v_nid := (v_bug->'new_bug'->'mail'->>'notification_id')::bigint;
  assert (v_bug->'new_bug'->>'emailed')::boolean and not (v_bug2->'new_bug'->>'emailed')::boolean and (v_bug2->'new_bug'->>'repeat')::boolean, 'one email, then a repeat';
  assert (select status from public.notifications where id = v_nid) = 'suppressed', 'the demo email is captured, never sent';
  assert (select count(*) from public.notifications where kind = 'it_new_bug' and subject like '%ZZ DEMO failure class%') = 1, 'exactly one email queued';
  assert (select (detail->>'repeats')::int from public.agent_actions where id = (v_bug->'new_bug'->>'bug_id')::bigint) = 1, 'the repeat is counted';
  raise notice 'new-bug email (captured): %', (select subject || ' | ' || left(replace(body, E'\n', ' / '), 400) from public.notifications where id = v_nid);

  -- only the it_engineer closes a bug
  begin
    update public.agent_actions set status = 'done' where id = (v_bug->'new_bug'->>'bug_id')::bigint;
    assert false, 'a bug was closed outside the it_engineer';
  exception when raise_exception then null;
  end;
  assert public.fn_it_new_bug_close('backup', 'zz_demo_class', 'ZZ DEMO probe teardown') = 1, 'the it_engineer closes it';

  -- teardown, and proof nothing real was touched
  delete from public.notifications where kind = 'it_new_bug' and to_email = 'founder.it-new-bug@example.invalid';
  delete from public.agent_actions where kind = 'it_new_bug' and coalesce((detail->>'demo')::boolean, false);
  delete from public.agent_remediation where coalesce((detail->>'demo')::boolean, false);
  delete from public.doc_backups where dedupe_key like 'ZZDEMO:pb:%';
  assert (select count(*) from public.doc_backups where dedupe_key like 'ZZDEMO:pb:%') = 0;
  assert (select count(*) from public.agent_remediation where coalesce((detail->>'demo')::boolean, false)) = 0;
  assert (select count(*) from public.notifications where to_email = 'founder.it-new-bug@example.invalid') = 0;
  assert (select count(*) from public.notifications where kind = 'it_new_bug' and to_email not like '%@example.invalid') = v_notif_before, 'no real email was queued';
  assert (select count(*) from public.agent_remediation where not coalesce((detail->>'demo')::boolean, false)) = v_real_rem, 'no real remediation was touched';
  raise notice 'playbook probe: 9 entries run on ZZ DEMO rows (7 re-verified, 1 escalated, stuck_no_run kicked), 1 new bug emailed once (captured), repeat counted; cleaned';
  raise notice 'summary now: %', public.fn_dropbox_backup_summary()->>'line';
end $probe$;
