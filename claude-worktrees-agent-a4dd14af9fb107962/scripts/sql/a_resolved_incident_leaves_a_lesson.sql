-- A RESOLVED INCIDENT LEAVES A LESSON (autonomy audit, degrading gap 11a).
--
-- MEASURED. fn_os_incident_close_task closes the linked corrective task when an incident resolves, but
-- captures nothing: 19 incidents have resolved and institutional_memory holds 0 rows about any of them.
-- A company that fixes the same thing twice because it never wrote down the first fix is not learning.
--
-- THIS FILE extends the close trigger to also write an institutional_memory row on resolution — the
-- headline, the resolution text, who owned it — keyed to the incident so the lesson is retrievable. It
-- is wrapped in its own begin/exception so a memory-write failure can never block an incident from
-- closing. CREATE OR REPLACE keeps the trigger binding and the ACL; this supersedes the definition in
-- incidents_get_an_owner_a_task_and_a_watchdog.sql (ledger synced alongside).
--
--   node scripts/apply_sql.mjs scripts/sql/a_resolved_incident_leaves_a_lesson.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_os_incident_close_task()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.status in ('resolved','closed') and coalesce(old.status,'') not in ('resolved','closed') then
    -- close the corrective task the incident opened
    if new.org_task_id is not null then
      update public.org_tasks
         set status='done', updated_at=now()
       where id = new.org_task_id and status <> 'done';
    end if;
    -- capture the lesson so the resolution is remembered, not re-learned
    begin
      insert into public.institutional_memory
        (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence, evidence_ref, occurred_at)
      values ('incident', 'os_incident', new.id::text,
              left('Incident resolved: '||coalesce(new.title, '#'||new.id::text), 200),
              left(coalesce(new.detail->>'resolution', new.detail->>'description',
                            'Resolved on '||to_char(now(),'DD Mon YYYY')), 2000),
              'resolved', coalesce(new.owner, 'system'), 0.7, 'os_incident#'||new.id, now());
    exception when others then null; end;
  end if;
  return new;
end $function$;

commit;
