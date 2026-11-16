-- a_backup_alert_blames_dropbox_only_when_dropbox_refused_probe.sql (it_engineer, 16 Nov 2026)
-- A pure probe of fn_ceo_backup_escalation_decide: it RUNS the routine on ZZ DEMO reports inside a block that always
-- rolls itself back, so no report, backup row or handoff it makes survives, and a case whose every file is ZZ DEMO never
-- reaches the founder (the routine's demo rule). It answers with ONE ROW: 'PROBE OK' or 'PROBE FAILED: <why>'.
-- A demo case reads only zz_demo backup rows and no uploader run, so nothing real can change its verdict.
--   1. the shape of report 27338 (16 Nov 2026): export pages that were never written, 'waiting: storage holds no object
--      at backups/<day>/<table>/page_0000.json', with table names that carry the words the old pattern matched, and an
--      upload Dropbox accepted an hour ago                                   -> internal, a remediation handoff, no founder
--   2. the same pages with no upload at all                                  -> still internal (Dropbox never answered)
--   3. a genuine Dropbox refusal, insufficient_space, no upload since        -> external: the Dropbox account is out of space
--   4. the same refusal three hours ago, an upload accepted one hour ago     -> internal (Dropbox is accepting)
--   5. then a second refusal now, after that upload                         -> external again (the latest refusal counts)
-- Run on a local Postgres 16 (scripts/db/local_pg16.mjs) twice; production's body before this fix fails case 1.
create temp table if not exists zz_probe_verdict (verdict text, detail text) on commit drop;
truncate zz_probe_verdict;
do $probe$
declare
  v_tag constant text := 'zz-demo-dbx-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS');
  v_fail text := ''; v_detail jsonb := '{}'::jsonb; v_left int;
  d_wait1 bigint; d_wait2 bigint; d_refuse bigint; d_done bigint;
  v_rep bigint; v jsonb; v_files jsonb;
  c_space constant text := 'dbx_upload 409 {"error_summary": "path/insufficient_space/..", "error": {".tag": "path", "reason": {".tag": "insufficient_space"}}}';
begin
  begin
    -- the never-written export pages, as the table export and the admit trigger leave them
    insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, source, status, error, attempts, dedupe_key)
    values ('zz_demo', v_tag, 'table_export', 'backups', '2026-11-14/payment_events/page_0000.json', 'storage', 'waiting_source',
            'waiting: storage holds no object at backups/2026-11-14/payment_events/page_0000.json', 0, v_tag || ':w1')
    returning id into d_wait1;
    insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, source, status, error, attempts, dedupe_key)
    values ('zz_demo', v_tag, 'table_export', 'backups', '2026-11-14/supplier_billing_plan_limit_disabled/page_0000.json', 'storage', 'waiting_source',
            'waiting: storage holds no object at backups/2026-11-14/supplier_billing_plan_limit_disabled/page_0000.json', 0, v_tag || ':w2')
    returning id into d_wait2;
    select jsonb_agg(jsonb_build_object('doc_backup_id', d.id, 'demo', true, 'kind', 'storage', 'bucket', d.bucket, 'path', d.path,
                                        'key', 'exp:obj:backups:' || d.path, 'owner', 'company:table_export:2026-11-14',
                                        'reason', 'never_queued', 'refile', 'queued', 'state', 'waiting', 'status', d.status,
                                        'attempts', d.attempts, 'error', d.error) order by d.id)
      into v_files from public.doc_backups d where d.id in (d_wait1, d_wait2);

    -- case 2 first: the pages with no upload at all
    insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
                                           requested_outcome, owner_role_id, next_review_at)
    values ('backup_escalation:' || v_tag || ':2', 'it_engineer', 'serious', 'ZZ DEMO backup escalation, pages never written',
            jsonb_build_object('handoff_id', null, 'files', v_files), '[]'::jsonb, 'ZZ DEMO', 'ceo', now() + interval '1 day')
    returning id into v_rep;
    v := public.fn_ceo_backup_escalation_decide(v_rep);
    v_detail := v_detail || jsonb_build_object('case2', v);
    if v->>'cause' is distinct from 'internal' or v->'remediate_handoff' = 'null'::jsonb or v->'founder' <> 'null'::jsonb then
      v_fail := v_fail || ' case2 (pages never written, no upload) did not read internal;';
    end if;

    -- case 1: report 27338's shape, with an upload Dropbox accepted an hour ago
    insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, source, status, attempts, dedupe_key, backed_up_at)
    values ('zz_demo', v_tag, 'table_export', 'backups', '2026-11-16/agent_runs/page_0000.json', 'storage', 'done', 1, v_tag || ':done',
            now() - interval '1 hour')
    returning id into d_done;
    insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
                                           requested_outcome, owner_role_id, next_review_at)
    values ('backup_escalation:' || v_tag || ':1', 'it_engineer', 'serious', 'ZZ DEMO backup escalation, report 27338 shape',
            jsonb_build_object('handoff_id', null, 'files', v_files), '[]'::jsonb, 'ZZ DEMO', 'ceo', now() + interval '1 day')
    returning id into v_rep;
    v := public.fn_ceo_backup_escalation_decide(v_rep);
    v_detail := v_detail || jsonb_build_object('case1', v);
    if v->>'cause' is distinct from 'internal' or v->'remediate_handoff' = 'null'::jsonb or v->'founder' <> 'null'::jsonb then
      v_fail := v_fail || ' case1 (report 27338 shape) did not read internal: ' || coalesce(v->>'cause', 'null') || ';';
    end if;

    -- case 3: a genuine Dropbox refusal given now, with no upload accepted since
    insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, source, status, error, attempts, dedupe_key, last_attempt_at)
    values ('zz_demo', v_tag, 'quotation', 'quotes', v_tag || '/quote.pdf', 'storage', 'error', c_space, 5, v_tag || ':r', now())
    returning id into d_refuse;
    insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
                                           requested_outcome, owner_role_id, next_review_at)
    values ('backup_escalation:' || v_tag || ':3', 'it_engineer', 'serious', 'ZZ DEMO backup escalation, Dropbox out of space',
            jsonb_build_object('handoff_id', null, 'files', jsonb_build_array(jsonb_build_object(
              'doc_backup_id', d_refuse, 'demo', true, 'kind', 'storage', 'bucket', 'quotes', 'path', v_tag || '/quote.pdf',
              'state', 'failing', 'status', 'error', 'attempts', 5, 'error', c_space))),
            '[]'::jsonb, 'ZZ DEMO', 'ceo', now() + interval '1 day')
    returning id into v_rep;
    v := public.fn_ceo_backup_escalation_decide(v_rep);
    v_detail := v_detail || jsonb_build_object('case3', v);
    if v->>'cause' is distinct from 'the Dropbox account is out of space' or (v->>'external')::boolean is not true
       or (v->>'dropbox_refusals')::int is distinct from 1 or v->'founder' <> 'null'::jsonb then
      v_fail := v_fail || ' case3 (insufficient_space, no upload since) did not read external out of space;';
    end if;

    -- case 4: the same refusal three hours ago; the upload an hour ago came after it
    update public.doc_backups set last_attempt_at = now() - interval '3 hours' where id = d_refuse;
    insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
                                           requested_outcome, owner_role_id, next_review_at)
    values ('backup_escalation:' || v_tag || ':4', 'it_engineer', 'serious', 'ZZ DEMO backup escalation, Dropbox accepting again',
            jsonb_build_object('handoff_id', null, 'files', jsonb_build_array(jsonb_build_object(
              'doc_backup_id', d_refuse, 'demo', true, 'state', 'failing', 'status', 'error', 'attempts', 5, 'error', c_space))),
            '[]'::jsonb, 'ZZ DEMO', 'ceo', now() + interval '1 day')
    returning id into v_rep;
    v := public.fn_ceo_backup_escalation_decide(v_rep);
    v_detail := v_detail || jsonb_build_object('case4', v);
    if v->>'cause' is distinct from 'internal' or (v->>'uploads_accepted_since')::int is distinct from 1 then
      v_fail := v_fail || ' case4 (refusal, then an upload accepted) did not read internal;';
    end if;

    -- case 5: Dropbox refused again AFTER that upload (the refusal three hours ago, the upload an hour ago, a refusal now):
    -- it is refusing now, so the upload before the latest refusal proves nothing
    insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, source, status, error, attempts, dedupe_key, last_attempt_at)
    values ('zz_demo', v_tag, 'quotation', 'quotes', v_tag || '/quote2.pdf', 'storage', 'error', c_space, 5, v_tag || ':r2', now())
    returning id into d_wait1;
    insert into public.support_ceo_report (idempotency_key, source_agent, severity, subject, verified_evidence, attempted_actions,
                                           requested_outcome, owner_role_id, next_review_at)
    values ('backup_escalation:' || v_tag || ':5', 'it_engineer', 'serious', 'ZZ DEMO backup escalation, Dropbox refusing again',
            jsonb_build_object('handoff_id', null, 'files', jsonb_build_array(
              jsonb_build_object('doc_backup_id', d_refuse, 'demo', true, 'state', 'failing', 'status', 'error', 'attempts', 5, 'error', c_space),
              jsonb_build_object('doc_backup_id', d_wait1, 'demo', true, 'state', 'failing', 'status', 'error', 'attempts', 5, 'error', c_space))),
            '[]'::jsonb, 'ZZ DEMO', 'ceo', now() + interval '1 day')
    returning id into v_rep;
    v := public.fn_ceo_backup_escalation_decide(v_rep);
    v_detail := v_detail || jsonb_build_object('case5', v);
    if v->>'cause' is distinct from 'the Dropbox account is out of space' or (v->>'uploads_accepted_since')::int is distinct from 0 then
      v_fail := v_fail || ' case5 (refusal, upload, refusal again) did not read external out of space;';
    end if;

    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then v_fail := v_fail || ' the routine raised: ' || sqlerrm || ';'; end if;
  end;

  select (select count(*) from public.doc_backups where entity = 'zz_demo' and entity_id = v_tag)
       + (select count(*) from public.support_ceo_report where idempotency_key like 'backup_escalation:' || v_tag || ':%')
    into v_left;
  if v_left <> 0 then v_fail := v_fail || ' ' || v_left || ' probe row(s) survived;'; end if;

  insert into zz_probe_verdict values (case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED:' || v_fail end, v_detail::text);
end $probe$;
select verdict, detail from zz_probe_verdict;
