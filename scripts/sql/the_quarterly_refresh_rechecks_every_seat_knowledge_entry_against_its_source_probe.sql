-- PROBE: THE QUARTERLY REFRESH RE-CHECKS EVERY SEAT KNOWLEDGE ENTRY AGAINST ITS SOURCE. Seat: it_engineer.
--
-- Pure probe, nothing survives it: it ends in `raise exception 'CHK<<...>>'` ALWAYS, so the whole request rolls
-- back. Before the_quarterly_refresh_rechecks_every_seat_knowledge_entry_against_its_source.sql is applied, it is
-- run APPENDED to that file in one request through scripts/lib/safe_replay.mjs (the file's DDL rolls back with it);
-- after the apply, run it alone the same way. It must print CHK<<PROBE OK ...>>.
--
-- It writes two ZZ DEMO knowledge entries (an it_engineer pack entry with no source; a marketing entry with a
-- source at example.invalid, written 200 days ago). The held questions it files go to the seats' own queues and
-- the handoffs it starts go to the seats' own inboxes, inside the aborted transaction: nothing is sent, nobody is
-- contacted, nothing is reasoned.
--
-- VERDICT: PROBE OK only if
--   1. the first run re-checks all six seats;
--   2. THE DAILY CAP holds: the questions filed today (the quarter's five aside) are at most 2 for ceo and 20 for
--      the other seats, and exactly the cap for a class that still has unfiled stale entries;
--   3. THE CEO SUMMARY: one it.finding handoff to ceo for the quarter, carrying all six seats' results, and the
--      marketing seat (which owns the old demo entry) has its own notice;
--   4. the old marketing entry is recorded stale (source_old), set validation_status 'stale', and the staleness tag
--      now prints for it;
--   5. each seat's per-quarter result is written and the sales_engineer seat is not wholly stale;
--   6. a second run the same day re-checks nothing, files nothing and starts no handoff;
--   7. the next day (filed_at moved back a day; every other unfiled row removed inside this transaction so the demo
--      rows are next) the no-source entry is filed in the it_engineer queue and the marketing entry in its own;
--   8. reasoning the filed question resolves the stale row;
--   9. and puts the agent_knowledge entry back to the status it had before it was marked stale.
do $probe$
declare v_q date := date_trunc('quarter', (now() at time zone 'Asia/Dubai'))::date;
  v_today_start timestamptz := ((now() at time zone 'Asia/Dubai')::date)::timestamp at time zone 'Asia/Dubai';
  v_ak bigint; r1 jsonb; r2 jsonb; r3 jsonb; fails text := ''; st1 public.seat_knowledge_stale; st2 public.seat_knowledge_stale;
  v_tag text; v_rc jsonb; v_rs jsonb; n_stale int; n_held int; n_stale2 int; n_held2 int; v_app jsonb; v_tot jsonb;
  f_ceo int; f_oth int; u_ceo int; u_oth int; n_ho int; n_ho2 int; v_ceo jsonb;
begin
  insert into public.it_engineer_knowledge (record_id, record_type, title, content, epistemic_status, pack_id, pack_version, body_sha256, source_ids)
  values ('zz_demo_probe_t4_nosrc', 'probe', 'ZZ DEMO probe entry', 'ZZ DEMO probe content, never served', 'method_engineering', 'zz_demo', '0', 'zz', '{}');
  insert into public.agent_knowledge (agent_key, topic, content, source_ref, layer, validation_status)
  values ('marketing:zz_demo_probe', 'ZZ DEMO probe topic', 'ZZ DEMO probe content', 'https://example.invalid/zz', 'profession', 'unvalidated')
  returning id into v_ak;
  update public.agent_knowledge set created_at = now() - interval '200 days', updated_at = now() - interval '200 days' where id = v_ak;
  if (select coalesce(updated_at, created_at) from public.agent_knowledge where id = v_ak) > now() - interval '199 days' then
    fails := fails || ' 0:could_not_age_the_demo_entry'; end if;

  r1 := public.fn_it_engineer_knowledge_refresh();
  if (r1->>'rechecked')::int <> 6 then fails := fails || ' 1:rechecked=' || coalesce(r1->>'rechecked', 'null'); end if;

  -- 2. the cap (the quarter's five reuse their own question and are not counted)
  select count(*) filter (where s.seat = 'ceo' and s.held_id is not null), count(*) filter (where s.seat <> 'ceo' and s.held_id is not null),
         count(*) filter (where s.seat = 'ceo' and s.held_id is null), count(*) filter (where s.seat <> 'ceo' and s.held_id is null)
    into f_ceo, f_oth, u_ceo, u_oth
    from public.seat_knowledge_stale s
   where s.quarter = v_q and (s.held_id is null or s.filed_at >= v_today_start)
     and not exists (select 1 from public.seat_knowledge_refresh r, jsonb_array_elements(r.items) x
                      where r.seat = s.seat and r.quarter = s.quarter and x->>'item_key' = s.item_key);
  if f_ceo > 2 or f_oth > 20 or (u_ceo > 0 and f_ceo <> 2) or (u_oth > 0 and f_oth <> 20) then
    fails := fails || ' 2:cap(ceo ' || f_ceo || ' filed/' || u_ceo || ' left, other ' || f_oth || ' filed/' || u_oth || ' left)'; end if;

  -- 3. the ceo summary and the owner's notice
  select a.detail into v_ceo from public.agent_actions a
   where a.kind = 'handoff' and a.agent = 'ceo' and a.target_id = 'it.finding:knowledge_recheck:' || v_q;
  if v_ceo is null or v_ceo->>'type' <> 'it.finding' or v_ceo->>'from' <> 'it_engineer'
     or (select count(*) from jsonb_object_keys(v_ceo->'per_seat')) <> 6 or (v_ceo->>'stale')::int < 2
     or not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'marketing'
                     and a.target_id = 'it.finding:knowledge_recheck:' || v_q || ':marketing' and a.status <> 'failed') then
    fails := fails || ' 3:ceo_summary(' || coalesce(left(v_ceo::text, 300), 'no row') || ')'; end if;

  -- 4. the old entry is marked
  select * into st2 from public.seat_knowledge_stale where quarter = v_q and item_key = 'agent_knowledge:' || v_ak;
  select public.fn_knowledge_staleness_tag(review_due, validation_status) into v_tag from public.agent_knowledge where id = v_ak;
  if st2.item_key is null or not ('source_old' = any(st2.reasons)) or st2.prior_status <> 'unvalidated'
     or (select validation_status from public.agent_knowledge where id = v_ak) <> 'stale' or coalesce(v_tag, '') = '' then
    fails := fails || ' 4:old_entry_not_marked(' || coalesce(st2.reasons::text, 'no row') || ',tag=' || coalesce(v_tag, 'null') || ')'; end if;

  -- 5. per-quarter results
  select recheck into v_rc from public.seat_knowledge_refresh where seat = 'it_engineer' and quarter = v_q;
  select recheck into v_rs from public.seat_knowledge_refresh where seat = 'sales_engineer' and quarter = v_q;
  if (select count(*) from public.seat_knowledge_refresh where quarter = v_q and recheck is not null) <> 6
     or (v_rc->>'no_source')::int < 1 or (v_rc ? 'unfiled') is not true
     or (v_rs->>'checked')::int < 1 or (v_rs->>'stale')::int >= (v_rs->>'checked')::int then
    fails := fails || ' 5:result(' || coalesce(v_rc::text, 'null') || '|' || coalesce(v_rs::text, 'null') || ')'; end if;

  -- 6. idempotent the same day
  select count(*) into n_stale from public.seat_knowledge_stale where quarter = v_q;
  select count(*) into n_held from public.reasoning_held_question where dedupe_key like 'krecheck:' || v_q || ':%';
  select count(*) into n_ho from public.agent_actions where kind = 'handoff' and target_id like 'it.finding:knowledge_recheck:' || v_q || '%';
  r2 := public.fn_it_engineer_knowledge_refresh();
  select count(*) into n_stale2 from public.seat_knowledge_stale where quarter = v_q;
  select count(*) into n_held2 from public.reasoning_held_question where dedupe_key like 'krecheck:' || v_q || ':%';
  select count(*) into n_ho2 from public.agent_actions where kind = 'handoff' and target_id like 'it.finding:knowledge_recheck:' || v_q || '%';
  if (r2->>'rechecked')::int <> 0 or (r2->>'filed_today')::int <> 0 or n_stale2 <> n_stale or n_held2 <> n_held or n_ho2 <> n_ho then
    fails := fails || ' 6:not_idempotent(' || r2::text || ',' || n_stale || '->' || n_stale2 || ',' || n_held || '->' || n_held2
          || ',handoffs ' || n_ho || '->' || n_ho2 || ')'; end if;

  -- 7. the next day: the demo rows are filed in their own seats' queues
  delete from public.seat_knowledge_stale where quarter = v_q and held_id is null
     and item_key not in ('it_engineer_knowledge:zz_demo_probe_t4_nosrc', 'agent_knowledge:' || v_ak);
  update public.seat_knowledge_stale set filed_at = filed_at - interval '1 day' where quarter = v_q and filed_at is not null;
  r3 := public.fn_it_engineer_knowledge_refresh();
  select * into st1 from public.seat_knowledge_stale where quarter = v_q and item_key = 'it_engineer_knowledge:zz_demo_probe_t4_nosrc';
  select * into st2 from public.seat_knowledge_stale where quarter = v_q and item_key = 'agent_knowledge:' || v_ak;
  if st1.item_key is null or not ('no_source' = any(st1.reasons)) or st1.seat <> 'it_engineer' or st1.held_id is null
     or not exists (select 1 from public.reasoning_held_question h where h.id = st1.held_id and h.seat = 'it_engineer'
                     and h.surface = 'it_engineer.knowledge_refresh')
     or st2.held_id is null
     or not exists (select 1 from public.reasoning_held_question h where h.id = st2.held_id and h.seat = 'marketing'
                     and h.surface = 'marketing.knowledge_refresh') then
    fails := fails || ' 7:next_day_not_filed(' || coalesce(r3::text, 'null') || ',' || coalesce(st1.held_id::text, 'null') || ','
          || coalesce(st2.held_id::text, 'null') || ')'; end if;

  -- 8, 9. reasoning resolves and restores
  v_app := public.fn_it_engineer_knowledge_refreshed(st1.held_id, '{"sources":[]}'::jsonb);
  if (select resolved_at from public.seat_knowledge_stale where quarter = v_q and item_key = st1.item_key) is null then
    fails := fails || ' 8:not_resolved(' || coalesce(v_app::text, 'null') || ')'; end if;
  v_app := public.fn_it_engineer_knowledge_refreshed(st2.held_id, '{"sources":[]}'::jsonb);
  if (v_app->>'applied')::boolean is not true
     or (select validation_status from public.agent_knowledge where id = v_ak) <> 'unvalidated' then
    fails := fails || ' 9:status_not_restored(' || coalesce(v_app::text, 'null') || ')'; end if;

  select jsonb_object_agg(seat, recheck - 'at') into v_tot from public.seat_knowledge_refresh where quarter = v_q;
  raise exception 'CHK<<%>>', case when fails = '' then
    'PROBE OK stale=' || n_stale || ' filed_day1(ceo ' || f_ceo || ', other ' || f_oth || ') unfiled_day1(ceo ' || u_ceo || ', other ' || u_oth
      || ') ceo_summary=yes per_seat=' || v_tot::text
    else 'PROBE FAILED:' || fails end;
end $probe$;
