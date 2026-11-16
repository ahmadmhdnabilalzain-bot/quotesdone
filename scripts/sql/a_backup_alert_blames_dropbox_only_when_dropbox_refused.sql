-- A BACKUP ALERT BLAMES DROPBOX ONLY WHEN DROPBOX REFUSED.
--
-- Assigned: it_engineer (16 Nov 2026). Redefines fn_ceo_backup_escalation_decide from the PRODUCTION body
-- (pg_get_functiondef md5 7719be673599ea66e0d5852ba905d441, read 16 Nov 2026; identical to the body in
-- the_it_engineer_knows_what_should_be_backed_up_and_closes_the_loop.sql). Nothing else in it changes.
--
-- WHAT HAPPENED (SELECT, 16 Nov 2026). support_ceo_report 27338, accepted 04:30:22 UTC, carried 454 files.
-- Every file's error read "waiting: storage holds no object at backups/2026-11-1x/<table>/page_0000.json":
-- export pages the 12-15 Nov table export never wrote (it stopped at ceo_year_plan_archive). The routine
-- joined EVERY file error into one string and ran a keyword pattern over it; a table NAME in a page path
-- carried the word for a payment, which the pattern read as the third external cause, so the founder was
-- told on WhatsApp that "the Dropbox plan or billing is blocking uploads ... it needs you". Dropbox was
-- fine: 1,586 doc_backups rows done in the 72 hours before, no dropbox_backup error run in 60 hours,
-- uploads every hour (757 rows done in the 6 hours before the read).
--
-- THE RULE NOW. The founder hears of an external cause only when BOTH hold:
--   (a) the evidence is Dropbox's own answer: a file error, or a failed dropbox_backup run's '#<row>: '
--       entry, that starts with a Dropbox endpoint and the HTTP status Dropbox returned
--       ('dbx_upload 409 {...}', 'files/upload 401 ...', 'finish 409 ...'), or 'no_dropbox_auth', which
--       dropbox.ts throws only when Dropbox refused the refresh token. A source-side state ('waiting:',
--       'abandoned:', 'read N of M bytes'), a path, a table name or a network failure is never evidence.
--       The cause is read from Dropbox's own fields only (error_summary, else the '.tag' values, else the
--       status), never from the rest of the text:
--         insufficient_space / over_quota / insufficient_quota            -> out of space
--         user_suspended / account_suspended / invalid_account_type / payment_required -> plan or billing
--         401, invalid_access_token / expired_access_token / invalid_grant / missing_scope,
--         no_dropbox_auth                                                 -> credentials
--       Anything else Dropbox answered (409 conflict, 429, 5xx) is not a cause the founder can fix.
--   (b) Dropbox has NOT accepted an upload since the refusals began: no doc_backups row of the same world
--       (real for a real report, zz_demo for a demo one) reached 'done' in the last 6 hours after the
--       earliest refusal on record. An upload it accepted since proves it is accepting, so the cause is
--       ours, whatever any text says.
-- Otherwise the cause is internal and the CEO sends the existing 'backup.remediate' handoff to the sales
-- engineer (which marks never-existing sources abandoned). The demo rule is unchanged: a case whose every
-- file is ZZ DEMO never reaches the founder, and a demo case reads no agent_runs.
-- The result names the evidence: 'dropbox_refusals', 'uploads_accepted_since', 'external'.
--
-- Prevented by: scripts/sql/a_backup_alert_blames_dropbox_only_when_dropbox_refused_probe.sql (the report
-- 27338 shape must read internal; a genuine insufficient_space refusal with no upload since must read
-- external, out of space). Production's body fails its first case.
--
--   node scripts/apply_sql.mjs scripts/sql/a_backup_alert_blames_dropbox_only_when_dropbox_refused.sql --apply --ddl

create or replace function public.fn_ceo_backup_escalation_decide(p_report_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  r public.support_ceo_report; v_files jsonb; v_demo boolean; v_cause text; v_h bigint; v_out jsonb;
  v_rank int; v_refusals int := 0; v_first_refusal timestamptz; v_accepted int := 0; v_why text;
  -- a Dropbox answer as dropbox.ts / upload.ts / index.ts throw it: '<endpoint> <status> <body>'
  c_answer constant text := '(?:dbx_upload|session_start|append|finish|get_metadata|get_space_usage|delete_v2|(?:files|users|oauth2)/[a-z0-9_/]+) [0-9]{3}\M';
begin
  select * into r from public.support_ceo_report where id = p_report_id for update;
  if not found or r.status <> 'sent' then return jsonb_build_object('ok', false, 'reason', 'no open report ' || p_report_id); end if;
  v_files := coalesce(r.verified_evidence->'files', '[]'::jsonb);
  v_demo := jsonb_array_length(v_files) > 0
            and not exists (select 1 from jsonb_array_elements(v_files) e where not coalesce((e->>'demo')::boolean, false));

  -- (a) Dropbox's own answers, each with when it was given; a demo case reads no run of the real uploader.
  with answers as (
    select regexp_replace(coalesce(e->>'error', ''), '^requeued: ', '') as answer, d.last_attempt_at as at
      from jsonb_array_elements(v_files) e
      left join public.doc_backups d
        on d.id = case when e->>'doc_backup_id' ~ '^[0-9]{1,18}$' then (e->>'doc_backup_id')::bigint end
    union all
    select m[1], a.started_at
      from public.agent_runs a
      cross join lateral regexp_matches(coalesce(a.note, ''), '#[0-9]+: (?:requeued: )?(' || c_answer || '[^|]*|no_dropbox_auth\M)', 'g') m
     where not v_demo and a.agent in ('dropbox_backup', 'fn:dropbox_backup') and a.status = 'error'
       and a.started_at > now() - interval '48 hours'
  ), dropbox as (
    select at,
           case when answer ~ '^no_dropbox_auth\M' then 401 else substring(answer from '^\S+ ([0-9]{3})')::int end as http,
           case when answer ~ '^no_dropbox_auth\M' then 'no_dropbox_auth'
                else coalesce(substring(answer from '"error_summary"\s*:\s*"([^"]*)"'),
                              (select string_agg(t[1], '/') from regexp_matches(answer, '"\.tag"\s*:\s*"([a-z_]+)"', 'g') t), '') end as code
      from answers
     where answer ~ ('^' || c_answer) or answer ~ '^no_dropbox_auth\M'
  ), classified as (
    select at, case
      when code ~* '\m(insufficient_space|over_quota|insufficient_quota)\M' then 2
      when code ~* '\m(user_suspended|account_suspended|invalid_account_type|payment_required)\M' then 3
      when http = 401 or code ~* '\m(no_dropbox_auth|invalid_access_token|expired_access_token|invalid_grant|missing_scope)\M' then 1
      end as rank
      from dropbox
  )
  select min(rank), count(*) filter (where rank is not null), min(at) filter (where rank is not null)
    into v_rank, v_refusals, v_first_refusal
    from classified;

  v_cause := case v_rank
    when 1 then 'Dropbox refused our credentials (the connection needs to be re-authorised)'
    when 2 then 'the Dropbox account is out of space'
    when 3 then 'the Dropbox plan or billing is blocking uploads'
    else null end;

  -- (b) an upload Dropbox accepted after the refusals began proves it is accepting: the cause is ours.
  if v_cause is not null then
    select count(*) into v_accepted
      from (select 1 from public.doc_backups b
             where b.status = 'done'
               and b.backed_up_at > greatest(now() - interval '6 hours', coalesce(v_first_refusal, '-infinity'::timestamptz))
               and (b.entity = 'zz_demo') = v_demo
             limit 1000) x;
    if v_accepted > 0 then
      v_why := 'Dropbox refused (' || v_cause || ') but has accepted ' || v_accepted || ' upload(s) since';
      v_cause := null;
    end if;
  else
    v_why := 'no file error is a refusal from Dropbox';
  end if;

  if v_cause is not null and not v_demo then
    v_out := public.fn_notify_founder(
      'Dropbox backup is blocked by something outside the company',
      'Our document backup to your Dropbox has stopped because ' || v_cause || '. ' || jsonb_array_length(v_files)
        || ' document(s) are waiting and will be sent as soon as it is fixed. Nothing inside the company can fix this part; it needs you.',
      'high', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_external:' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD'));
  else
    v_h :=public.fn_seat_handoff('ceo', 'sales_engineer', 'backup.remediate', 'support_ceo_report', r.id::text,
      jsonb_build_object('report_id', r.id, 'refile_handoff_id', r.verified_evidence->'handoff_id',
        'files', (select coalesce(jsonb_agg(e - 'state' - 'status' - 'attempts'), '[]'::jsonb) from jsonb_array_elements(v_files) e where e->>'state' <> 'ok'),
        'refile_attempts', 0,
        'instructions', 'Re-file each file below from its source. Where the source no longer exists, mark its row abandoned with the reason (error ''abandoned: ...'') so it stops counting as lost. Do not close this: the IT engineer re-checks and closes.'));
  end if;
  update public.support_ceo_report
     set status = 'accepted', accepted_at = now(),
         acceptance_receipt = 'ceo: ' || case when v_h is not null then 'instructions sent back as handoff ' || v_h
                                                || case when v_cause is null then ' (cause internal: ' || v_why || ')'
                                                        else ' (external cause ' || v_cause || ', but every file is ZZ DEMO)' end
                                              else 'external cause (' || v_cause || '), founder notified' end
   where id = r.id;
  return jsonb_build_object('ok', true, 'report_id', r.id, 'cause', coalesce(v_cause, 'internal'), 'demo', v_demo,
                            'external', v_cause is not null, 'dropbox_refusals', v_refusals, 'uploads_accepted_since', v_accepted,
                            'remediate_handoff', v_h, 'founder', v_out);
end $fn$;
-- CREATE OR REPLACE preserves the ACL; the revoke is restated on the one signature (no other overload exists).
revoke execute on function public.fn_ceo_backup_escalation_decide(bigint) from public, anon, authenticated;
