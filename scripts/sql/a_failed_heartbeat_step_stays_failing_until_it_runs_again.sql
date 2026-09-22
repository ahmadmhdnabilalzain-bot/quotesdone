-- A FAILED HEARTBEAT STEP STAYS FAILING UNTIL IT RUNS AGAIN.
-- Assigned: it_engineer. 22 Sep 2026.
--
-- ══ MEASURED, 21-22 Sep 2026, htdblwldjkcgjvmqkbeh, read-only ══════════════════════════════════════
-- resilience_step backupVerify (every 6 h): last_ok_at 20 Sep 03:31Z, last_started_at 21 Sep 17:16Z —
--   no passing run for 38 hours ("the backup check failing since 20 Sep"). Its cause, fn_it_backup_tick
--   cancelled at the 8 s statement timeout by fn_enqueue_doc_backups (7.0 s mean), was fixed by #785
--   (a_conversation_party_is_found_by_index_…, applied 21 Sep ~18:03Z; the stages now total ~0.9 s,
--   timed read-only 21 Sep 21:05Z). Next due ~23:16Z.
-- What let it hide: it_engineer_finding duty:heartbeat:backupVerify was raised 17:16:12Z and closed
--   17:31:35Z "the heartbeat duty no longer finds it". resilience_ping settles the heartbeat duty with
--   THIS tick's failures, and fn_it_duty_settle closes every open duty:heartbeat key not in the list —
--   so a step on a slow cadence is "fixed" on the next tick where it is simply not due. seen_count 83.
--
-- ══ CHANGES ══════════════════════════════════════════════════════════════════════════════════════
-- fn_it_duty_settle: an item flagged "carried": true whose finding is OPEN is held — the key stays in
--   the settled set (so the sweep does not close it) and the row is not touched (no seen_count, no
--   title change, no alert), because nothing was observed this tick. A carried item whose finding is
--   closed falls through to the normal upsert and reopens. resilience_ping (steps.ts carriedFailures)
--   sends a step as carried when its last_started_at is newer than its last_ok_at and it did not run.
--
-- ══ NOT CHANGED ══════════════════════════════════════════════════════════════════════════════════
-- Every other branch of fn_it_duty_settle (the config hold, the upsert, the sweep) is the live body,
-- md5(prosrc) 1265b4f769180b0e567c70be45719dbf on 22 Sep 2026, copied verbatim. No other duty sends
-- "carried", so no other duty's behaviour moves. The ACL: CREATE OR REPLACE keeps it; revoked again below.
--
-- Prevented by: supabase/functions/resilience_ping/steps.test.ts ("a failed step that was not due this
-- tick is still failing") and the verdict row at the end of this file.
-- Apply: node scripts/apply_sql.mjs scripts/sql/a_failed_heartbeat_step_stays_failing_until_it_runs_again.sql --apply --ddl
-- then deploy resilience_ping (order matters only in that the deploy without this file upserts instead of holding).

CREATE OR REPLACE FUNCTION public.fn_it_duty_settle(p_duty text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare x jsonb; v_keys text[] := '{}'; v_key text; n_closed int := 0; v_open text; v_config boolean;
        n_held int := 0;
begin
  if coalesce(btrim(p_duty), '') = '' or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'fn_it_duty_settle(duty, items[]): a duty name and an array of failing items are required';
  end if;
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce(btrim(x->>'item'), '') = '' or coalesce(btrim(x->>'title'), '') = '' then
      raise exception 'fn_it_duty_settle: every item needs an item key and a title (%)', x;
    end if;
    v_key := 'duty:' || p_duty || ':' || (x->>'item');
    v_keys := v_keys || v_key;

    -- A CARRIED ITEM WAS NOT OBSERVED THIS TICK (22 Sep 2026): its step failed earlier and has not run
    -- since. An open finding is held exactly as it stands; a closed one falls through and reopens.
    if coalesce((x->>'carried')::boolean, false) and exists (select 1 from public.it_engineer_finding f
                                                             where f.issue_key = v_key and f.closed_at is null) then
      n_held := n_held + 1;
      continue;
    end if;

    -- A CONFIGURATION GAP IS NOT NEWS ON THE SECOND TICK. Nothing about the running system changed
    -- between one reading and the next; what is missing is a number or a date nobody has entered yet.
    -- The key stays in v_keys so the sweep below does NOT close it - the gap is still open, and closes
    -- the moment the cap or the date is recorded and the producer stops emitting the item. Recognised
    -- from the item key both producers already use, or from an explicit 'config' flag for future ones.
    v_config := coalesce((x->>'config')::boolean, false)
                or (x->>'item') ~ '(^|:)cap_unknown:' or (x->>'item') ~ ':date_unknown$';
    -- A CLOSED configuration finding is NOT held: it falls through to the upsert and reopens, because a
    -- gap that was filled and has come back is news. Only an already-open one is held.
    if v_config and exists (select 1 from public.it_engineer_finding f
                             where f.issue_key = v_key and f.closed_at is null) then
      -- The reading itself moves even though the gap does not: supabase storage was 34 GB when the
      -- finding was raised and will be more when somebody reads it. So the title and the evidence are
      -- refreshed to today's measurement while seen_count, last_seen_at and started_at stand still -
      -- the row says what is true now without claiming anything happened this tick.
      update public.it_engineer_finding f
         set title = left(x->>'title', 300),
             evidence = coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
               'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
               'demo', coalesce((x->>'demo')::boolean, false), 'reading_refreshed_at', now())
       where f.issue_key = v_key and f.closed_at is null;
      n_held := n_held + 1;
      continue;
    end if;

    perform public.fn_it_engineer_finding_upsert(v_key, x->>'title', 'IT engineer duty: ' || p_duty,
      coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
      coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
        'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
        'demo', coalesce((x->>'demo')::boolean, false)),
      '{}'::text[], '{}'::text[], 'it_engineer.' || p_duty);
  end loop;
  for v_open in select issue_key from public.it_engineer_finding
                 where closed_at is null and issue_key like 'duty:' || p_duty || ':%' and not (issue_key = any (v_keys)) loop
    perform public.fn_it_engineer_finding_close(v_open, 'the ' || p_duty || ' duty no longer finds it');
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('duty', p_duty, 'failing', coalesce(array_length(v_keys, 1), 0),
                            'closed', n_closed, 'configuration_already_recorded', n_held);
end $function$;



revoke execute on function public.fn_it_duty_settle(text, jsonb) from public, anon, authenticated;

-- VERDICT: one row. The hold exists, the rest of the body is still there, and nobody but the owner
-- and service_role can call it.
select case when position('''carried''' in p.prosrc) > 0
             and position('the '' || p_duty || '' duty no longer finds it' in p.prosrc) > 0
             and position('configuration_already_recorded' in p.prosrc) > 0
             and not has_function_privilege('anon', p.oid, 'execute')
             and not has_function_privilege('authenticated', p.oid, 'execute')
             and array_to_string(p.proconfig, ',') like '%search_path%'
            then 'PROBE OK' else 'PROBE FAILED' end as verdict
  from pg_proc p where p.oid = 'public.fn_it_duty_settle(text,jsonb)'::regprocedure;
