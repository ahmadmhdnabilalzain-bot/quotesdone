-- PROBE: THE QUARTERLY REFRESH RE-CHECKS EVERY SEAT KNOWLEDGE ENTRY AGAINST ITS SOURCE. Seat: it_engineer.
--
-- Pure probe, nothing survives it: it ends in `raise exception 'CHK<<...>>'` ALWAYS, so the whole request rolls
-- back. Before the_quarterly_refresh_rechecks_every_seat_knowledge_entry_against_its_source.sql is applied, run it
-- APPENDED to that file in one request (the file's DDL rolls back with it); after the apply, run it alone:
--   node scripts/qsql.mjs scripts/sql/the_quarterly_refresh_rechecks_every_seat_knowledge_entry_against_its_source_probe.sql
-- -> must print CHK<<PROBE OK ...>>.
--
-- It writes two ZZ DEMO knowledge entries (an it_engineer pack entry with no source; a marketing entry with a
-- source at example.invalid, written 200 days ago). The held questions it files go to the seats' own queues
-- inside the aborted transaction: nothing is sent, nobody is contacted, nothing is reasoned.
--
-- VERDICT: PROBE OK only if
--   1. the first run re-checks all six seats;
--   2. the no-source entry is recorded stale (no_source) and filed in the it_engineer queue;
--   3. the old marketing entry is recorded stale (source_old), set validation_status 'stale', and the staleness tag
--      now prints for it;
--   4. each seat's per-quarter result is written and the sales_engineer seat is not wholly stale (fresh, sourced
--      entries are not flagged);
--   5. a second run re-checks nothing and files nothing new;
--   6. reasoning the filed question resolves the stale row;
--   7. and puts the agent_knowledge entry back to the status it had before it was marked stale.
do $probe$
declare v_q date := date_trunc('quarter', (now() at time zone 'Asia/Dubai'))::date;
  v_ak bigint; r1 jsonb; r2 jsonb; fails text := ''; st1 public.seat_knowledge_stale; st2 public.seat_knowledge_stale;
  v_tag text; v_rc jsonb; v_rs jsonb; n_stale int; n_held int; n_stale2 int; n_held2 int; v_app jsonb; v_tot jsonb;
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

  select * into st1 from public.seat_knowledge_stale where quarter = v_q and item_key = 'it_engineer_knowledge:zz_demo_probe_t4_nosrc';
  if st1.item_key is null or not ('no_source' = any(st1.reasons)) or st1.seat <> 'it_engineer' or st1.held_id is null
     or not exists (select 1 from public.reasoning_held_question h where h.id = st1.held_id and h.seat = 'it_engineer'
                     and h.surface = 'it_engineer.knowledge_refresh') then
    fails := fails || ' 2:no_source_not_filed(' || coalesce(st1.reasons::text, 'no row') || ')'; end if;

  select * into st2 from public.seat_knowledge_stale where quarter = v_q and item_key = 'agent_knowledge:' || v_ak;
  select public.fn_knowledge_staleness_tag(review_due, validation_status) into v_tag from public.agent_knowledge where id = v_ak;
  if st2.item_key is null or not ('source_old' = any(st2.reasons)) or st2.prior_status <> 'unvalidated'
     or (select validation_status from public.agent_knowledge where id = v_ak) <> 'stale' or coalesce(v_tag, '') = '' then
    fails := fails || ' 3:old_entry_not_marked(' || coalesce(st2.reasons::text, 'no row') || ',tag=' || coalesce(v_tag, 'null') || ')'; end if;

  select recheck into v_rc from public.seat_knowledge_refresh where seat = 'it_engineer' and quarter = v_q;
  select recheck into v_rs from public.seat_knowledge_refresh where seat = 'sales_engineer' and quarter = v_q;
  if (select count(*) from public.seat_knowledge_refresh where quarter = v_q and recheck is not null) <> 6
     or (v_rc->>'no_source')::int < 1 or (v_rc->>'filed')::int < 1
     or (v_rs->>'checked')::int < 1 or (v_rs->>'stale')::int >= (v_rs->>'checked')::int then
    fails := fails || ' 4:result(' || coalesce(v_rc::text, 'null') || '|' || coalesce(v_rs::text, 'null') || ')'; end if;

  select count(*) into n_stale from public.seat_knowledge_stale where quarter = v_q;
  select count(*) into n_held from public.reasoning_held_question where dedupe_key like 'krecheck:' || v_q || ':%';
  r2 := public.fn_it_engineer_knowledge_refresh();
  select count(*) into n_stale2 from public.seat_knowledge_stale where quarter = v_q;
  select count(*) into n_held2 from public.reasoning_held_question where dedupe_key like 'krecheck:' || v_q || ':%';
  if (r2->>'rechecked')::int <> 0 or n_stale2 <> n_stale or n_held2 <> n_held then
    fails := fails || ' 5:not_idempotent(' || r2::text || ',' || n_stale || '->' || n_stale2 || ',' || n_held || '->' || n_held2 || ')'; end if;

  v_app := public.fn_it_engineer_knowledge_refreshed(st1.held_id, '{"sources":[]}'::jsonb);
  if (select resolved_at from public.seat_knowledge_stale where quarter = v_q and item_key = st1.item_key) is null then
    fails := fails || ' 6:not_resolved(' || coalesce(v_app::text, 'null') || ')'; end if;
  v_app := public.fn_it_engineer_knowledge_refreshed(st2.held_id, '{"sources":[]}'::jsonb);
  if (v_app->>'applied')::boolean is not true
     or (select validation_status from public.agent_knowledge where id = v_ak) <> 'unvalidated' then
    fails := fails || ' 7:status_not_restored(' || coalesce(v_app::text, 'null') || ')'; end if;

  select jsonb_object_agg(seat, recheck - 'at') into v_tot from public.seat_knowledge_refresh where quarter = v_q;
  raise exception 'CHK<<%>>', case when fails = '' then
    'PROBE OK stale=' || n_stale || ' filed=' || n_held || ' per_seat=' || v_tot::text
    else 'PROBE FAILED:' || fails end;
end $probe$;
