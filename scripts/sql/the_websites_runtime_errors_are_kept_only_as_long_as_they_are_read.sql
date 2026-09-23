-- THE WEBSITE'S RUNTIME ERRORS ARE KEPT ONLY AS LONG AS THEY ARE READ.
--
-- Assigned: it_engineer. 22 Sep 2026 (review of PR #852, SEATS-06).
--
-- ══ WHY ══════════════════════════════════════════════════════════════════════════════════════
-- SEATS-06 gives public.error_events its first real producer: src/instrumentation.ts posts one row
-- per uncaught server error on the website, and one 'site_report_ready' per Vercel cold start.
-- public.error_events has 0 rows today and the ONLY delete anywhere in the estate is scoped to
-- resend_webhook bounce rows (a_bounce_report_is_proven_to_arrive_every_day_or_it_is_a_finding.sql:68),
-- so nothing would ever have removed a website row. resilience_ping reads the last HOUR (the count)
-- and the last 24 HOURS (the heartbeat) and nothing reads anything older, so a bad deploy throwing
-- on every request would grow a table nobody reads, for ever.
--
-- BOUNDED, BECAUSE A BIG BATCH DELETE HAS ALREADY RESTARTED THIS DATABASE (21 Sep 2026: a 50k purge
-- sequential-scanned, retried on 524, went past 4 GB and forced a hard restart). This deletes AT
-- MOST p_limit rows per call, and it is called once per resilience tick (~96 times a Dubai day =
-- up to ~192k rows a day of headroom, far above any plausible error rate). It never touches a row
-- of any other source. The WRITE is what p_limit bounds; the READ is bounded by walking
-- idx_error_events_website_age (created_at, where source = 'website') in order and stopping at the
-- first row inside retention, which is why the delete orders by created_at and not by id.
-- MEASURED (22 Sep 2026, 6,000 staged website rows all inside retention — the steady state — in an
-- aborted transaction): `Index Scan using idx_error_events_website_age … Index Cond: (created_at <
-- now() - '8 days') … rows=0, Buffers: shared hit=3, Execution Time 0.035 ms`. An earlier version
-- ordered by id against a (kind, created_at desc) index; the review measured that the index was
-- never used and the scan had to walk every website row to prove none was expired.
--
-- RETENTION, set by what reads them — AND ONE READER IS NOT THE TICK:
--   runtime_error      14 days. The reading is hourly; a fortnight is for a human looking back at
--                      a bad deploy, and it is the same order as the estate's other short logs.
--   site_report_ready  8 DAYS, and the number is load-bearing. fn_it_detect's D4 arm
--                      (the_it_detector_evaluates_its_row_rules_as_sets_not_as_function_calls.sql:430)
--                      computes capture_alive from `count(*) from public.error_events where
--                      created_at > now() - c_base` with c_base = 7 days and NO filter on source,
--                      kind or severity. Heartbeats are the only kind this table will hold in
--                      volume, so pruning them at 48 h would drive rows_7d toward 0 on a perfectly
--                      healthy site and make D4 report capture_alive:false / 'no_capture_yet' —
--                      manufacturing the exact blindness that arm exists to prevent (review of
--                      #852; a row staged at 3 days old was measured inside D4's window and would
--                      have been deleted by a 48 h rule). 8 days clears c_base with a day to spare,
--                      one row per Vercel cold start is a trivial count, and nothing else cares:
--                      resilience_ping only ever asks about the last 24 h.
--
-- ALSO CLOSED HERE: error_events has had RLS ENABLED WITH NO POLICY since it was created — the
-- state the apply discipline names ("indistinguishable from one where somebody meant to write a
-- policy and forgot"). It is made deliberately service-role only. anon/authenticated hold no grant
-- on it today; the revoke keeps it that way.
--
--   node scripts/apply_sql.mjs scripts/sql/the_websites_runtime_errors_are_kept_only_as_long_as_they_are_read.sql --apply --ddl

-- ── 1. the table says out loud that it is service-role only ─────────────────────────────────
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'error_events') then
    create policy error_events_service_role_only on public.error_events
      as permissive for all to public using (false) with check (false);
  end if;
end $$;
revoke all on public.error_events from anon, authenticated;

-- The prune walks website rows OLDEST FIRST and stops inside retention, so the index it needs is
-- (created_at) over source = 'website'. A (kind, created_at desc) index was written here first and
-- the review measured that the delete never used it at all — in steady state the scan then had to
-- walk every website row to prove none was expired. The kind is not in the key because there are
-- two kinds and the age decides everything.
create index if not exists idx_error_events_website_age
  on public.error_events (created_at) where source = 'website';

-- ── 2. the bounded prune ────────────────────────────────────────────────────────────────────
create or replace function public.fn_prune_website_error_events(p_limit integer default 2000)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_deleted int;
begin
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'fn_prune_website_error_events: p_limit must be between 1 and 5000, got %', p_limit;
  end if;
  with doomed as (
    select id from public.error_events
     where source = 'website'
       and created_at < now() - interval '8 days'           -- nothing younger can be expired
       and ((kind = 'site_report_ready' and created_at < now() - interval '8 days')
         or (kind is distinct from 'site_report_ready' and created_at < now() - interval '14 days'))
     order by created_at                                    -- oldest first: walks the index and stops
     limit p_limit)
  delete from public.error_events e using doomed d where e.id = d.id;
  get diagnostics v_deleted = row_count;
  -- No count of what is LEFT: that was an unconditional count(*) over every website row on every
  -- tick — an unbounded read to produce a number nobody reads (review of #852). `more` is what the
  -- caller needs, and it costs nothing.
  return jsonb_build_object('deleted', v_deleted, 'limit', p_limit, 'more', v_deleted = p_limit);
end $fn$;
revoke execute on function public.fn_prune_website_error_events(integer) from public, anon, authenticated;

comment on function public.fn_prune_website_error_events(integer) is
  'Deletes at most p_limit public.error_events rows of source=website past their retention (runtime_error 14 days, site_report_ready 8 days, which clears fn_it_detect''s 7-day capture_alive window). Called once per resilience tick by resilience_ping''s IT detection tick, which is the only reader of these rows. 22 Sep 2026, it_engineer (SEATS-06).';

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the probe must not raise. It stages two ZZ DEMO rows — one past retention, one
-- inside it — proves the prune takes exactly the expired one, and deletes both again itself. It
-- can reach nobody: error_events is a log with no reader that notifies anyone.
-- FOUR ROWS, and the third is the one the review caught: a heartbeat three days old sits inside
-- fn_it_detect's 7-day capture_alive window and MUST survive the prune.
do $$
declare v jsonb; v_old bigint; v_new bigint; v_hb_in bigint; v_hb_out bigint; v_left int;
begin
  insert into public.error_events (source, kind, severity, detail, created_at)
  values ('website', 'runtime_error', 'error', '{"message":"ZZ DEMO expired"}'::jsonb, now() - interval '20 days')
  returning id into v_old;
  insert into public.error_events (source, kind, severity, detail, created_at)
  values ('website', 'runtime_error', 'error', '{"message":"ZZ DEMO fresh"}'::jsonb, now() - interval '1 hour')
  returning id into v_new;
  insert into public.error_events (source, kind, severity, detail, created_at)
  values ('website', 'site_report_ready', 'info', '{"message":"ZZ DEMO heartbeat inside D4 window"}'::jsonb, now() - interval '3 days')
  returning id into v_hb_in;
  insert into public.error_events (source, kind, severity, detail, created_at)
  values ('website', 'site_report_ready', 'info', '{"message":"ZZ DEMO heartbeat past retention"}'::jsonb, now() - interval '9 days')
  returning id into v_hb_out;

  v := public.fn_prune_website_error_events(10);

  if exists (select 1 from public.error_events where id = v_old) then
    raise exception 'the prune left a row 20 days past its retention (id %)', v_old;
  end if;
  if not exists (select 1 from public.error_events where id = v_new) then
    raise exception 'the prune deleted a row one hour old (id %) — it must only take expired rows', v_new;
  end if;
  if not exists (select 1 from public.error_events where id = v_hb_in) then
    raise exception 'the prune deleted a 3-day-old heartbeat (id %) — that row is inside fn_it_detect''s 7-day capture_alive window, and taking it makes D4 report no_capture_yet on a healthy site', v_hb_in;
  end if;
  if exists (select 1 from public.error_events where id = v_hb_out) then
    raise exception 'the prune left a 9-day-old heartbeat (id %) past its 8-day retention', v_hb_out;
  end if;

  delete from public.error_events where id in (v_old, v_new, v_hb_in, v_hb_out);
  select count(*) into v_left from public.error_events where id in (v_old, v_new, v_hb_in, v_hb_out);
  if v_left <> 0 then raise exception 'the probe left % row(s) behind', v_left; end if;
  raise notice 'PROBE ok: expired rows taken, the fresh error and the 3-day heartbeat left (%); nothing of the probe remains', v;
end $$;
