-- AUDIT 9.5 step 3, recorded as a migration.
--
-- The work was performed live on 3 Aug 2026 and verified through the cutover; this file is the
-- record, and is idempotent - every block is guarded, so re-applying it is a no-op. It does NOT
-- re-issue credentials that already exist, because doing so would invalidate the ones the crons
-- are currently using.
--
-- Result: 43 of 43 cron jobs and 18 of 18 database functions moved off app_secrets.inbound_secret
-- onto eleven scoped credentials. legacy.shared use_count went flat from the moment of the move.

-- ---------------------------------------------------------------- cron contexts
do $$
declare
  ctxmap jsonb := jsonb_build_object(
    'cron.monitoring',   jsonb_build_array('uptime_check','ai_health'),
    'cron.knowledge',    jsonb_build_array('kb_ingest','kb_embed','kb_deepen','kb_autofill_gaps','knowledge_exam','gen_category_knowledge','gen_category_personas','learn_gaps'),
    'cron.agents',       jsonb_build_array('agent_autogen','agent_learnings_report','exec_agents','reflect','dept_learn','dept_plan','cos_execute'),
    'cron.notifications',jsonb_build_array('email_cron','send_sms','send_whatsapp','email_triage'),
    'cron.finance',      jsonb_build_array('finance_ingest','cost_snapshot','money_tests','collections_legal'),
    'cron.marketplace',  jsonb_build_array('embed_leads','enrich_capability','match_eval','boost_recommend','archive_rfq'),
    'cron.content',      jsonb_build_array('blog_weekly','seo_gen','content_revise','assets_ingest'),
    'cron.backup',       jsonb_build_array('backup','dropbox_backup','dropbox_sync','dr_drill','retention_purge','github_sync'),
    'cron.documents',    jsonb_build_array('doc_extract'),
    'cron.marketing',    jsonb_build_array('meta_sync')
  );
  ctx text; fns text[]; iss jsonb; keyname text; j record; moved int := 0; issued int := 0;
begin
  for ctx in select jsonb_object_keys(ctxmap) loop
    fns := array(select jsonb_array_elements_text(ctxmap -> ctx));
    keyname := 'cred_' || replace(ctx, '.', '_');

    -- The issued secret goes straight into app_secrets inside this transaction. It is never
    -- returned to the caller, so it appears in no log, no console output and no migration diff.
    if not exists (select 1 from public.internal_credential
                    where context = ctx and active and retired_at is null and not is_legacy) then
      iss := public.fn_internal_credential_issue(ctx, fns, 'cron context');
      insert into public.app_secrets (key, value) values (keyname, iss ->> 'secret')
        on conflict (key) do update set value = excluded.value;
      issued := issued + 1;
    end if;

    -- Only the key NAME is rewritten. cron.alter_job is used rather than UPDATE cron.job, because
    -- the Supabase roles cannot write that table directly (42501).
    for j in
      select jobid, command, (regexp_match(command, 'functions/v1/([a-z0-9_]+)'))[1] as fn
        from cron.job where command ~ 'key\s*=\s*''inbound_secret'''
    loop
      if j.fn = any(fns) then
        perform cron.alter_job(j.jobid,
          command := regexp_replace(j.command, 'key\s*=\s*''inbound_secret''', 'key=''' || keyname || '''', 'g'));
        moved := moved + 1;
      end if;
    end loop;
  end loop;
  raise notice 'cron: issued % credential(s), moved % job(s)', issued, moved;
end $$;

-- ---------------------------------------------------------------- database functions
-- One context for everything the database itself initiates - triggers and scheduled helpers, not
-- user traffic - calling a known, closed set of 13 edge functions.
do $$
declare
  iss jsonb; r record; newdef text; n int := 0;
  scope_fns text[] := array['prompt_improve','category_provision','canon_eval','vt_scan','compliance_archive',
                            'agents','site_deploy','doc_reminder','pending_digest','dispatch_inquiry',
                            'alert_founder','kb_autofill_gaps','enrich_capability'];
begin
  if not exists (select 1 from public.internal_credential where context = 'db.internal' and active and retired_at is null) then
    iss := public.fn_internal_credential_issue('db.internal', scope_fns, 'database triggers and helpers');
    insert into public.app_secrets (key, value) values ('cred_db_internal', iss ->> 'secret')
      on conflict (key) do update set value = excluded.value;
  end if;

  for r in
    select p.oid, p.proname, pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     -- prokind='f' is required, not tidiness: pg_get_functiondef raises 42809 on aggregates, and
     -- this schema contains a public aggregate named "avg".
     where ns.nspname = 'public' and p.prokind = 'f'
       and pg_get_functiondef(p.oid) ~ 'key\s*=\s*''inbound_secret'''
  loop
    newdef := regexp_replace(r.def, 'key\s*=\s*''inbound_secret''', 'key=''cred_db_internal''', 'g');
    if newdef = r.def then continue; end if;
    execute newdef;
    n := n + 1;
  end loop;
  raise notice 'database: rewrote % function(s)', n;
end $$;
;
