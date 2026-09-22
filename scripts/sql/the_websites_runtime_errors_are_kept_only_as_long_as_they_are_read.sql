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
-- MOST p_limit rows per call, picked by id from an index-ordered scan, and it is called once per
-- resilience tick (~96 times a Dubai day = up to ~192k rows a day of headroom, far above any
-- plausible error rate). It never touches a row of any other source.
--
-- RETENTION, set by what reads them:
--   runtime_error      14 days. The reading is hourly; a fortnight is for a human looking back at
--                      a bad deploy, and it is the same order as the estate's other short logs.
--   site_report_ready  48 hours. The heartbeat's question is "in the last 24 h", and one row per
--                      cold start is the highest-volume kind here.
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

-- The count and the prune both ask for one source and one kind, newest first.
create index if not exists idx_error_events_website
  on public.error_events (kind, created_at desc) where source = 'website';

-- ── 2. the bounded prune ────────────────────────────────────────────────────────────────────
create or replace function public.fn_prune_website_error_events(p_limit integer default 2000)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_deleted int; v_left bigint;
begin
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'fn_prune_website_error_events: p_limit must be between 1 and 5000, got %', p_limit;
  end if;
  with doomed as (
    select id from public.error_events
     where source = 'website'
       and ((kind = 'runtime_error'     and created_at < now() - interval '14 days')
         or (kind = 'site_report_ready' and created_at < now() - interval '48 hours')
         or (kind not in ('runtime_error', 'site_report_ready') and created_at < now() - interval '14 days'))
     order by id
     limit p_limit)
  delete from public.error_events e using doomed d where e.id = d.id;
  get diagnostics v_deleted = row_count;
  select count(*) into v_left from public.error_events where source = 'website';
  return jsonb_build_object('deleted', v_deleted, 'website_rows_left', v_left, 'limit', p_limit,
                            'more', v_deleted = p_limit);
end $fn$;
revoke execute on function public.fn_prune_website_error_events(integer) from public, anon, authenticated;

comment on function public.fn_prune_website_error_events(integer) is
  'Deletes at most p_limit public.error_events rows of source=website past their retention (runtime_error 14 days, site_report_ready 48 h). Called once per resilience tick by resilience_ping''s IT detection tick, which is the only reader of these rows. 22 Sep 2026, it_engineer (SEATS-06).';

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the probe must not raise. It stages two ZZ DEMO rows — one past retention, one
-- inside it — proves the prune takes exactly the expired one, and deletes both again itself. It
-- can reach nobody: error_events is a log with no reader that notifies anyone.
do $$
declare v jsonb; v_old bigint; v_new bigint; v_left int;
begin
  insert into public.error_events (source, kind, severity, detail, created_at)
  values ('website', 'runtime_error', 'error', '{"message":"ZZ DEMO expired"}'::jsonb, now() - interval '20 days')
  returning id into v_old;
  insert into public.error_events (source, kind, severity, detail, created_at)
  values ('website', 'runtime_error', 'error', '{"message":"ZZ DEMO fresh"}'::jsonb, now() - interval '1 hour')
  returning id into v_new;

  v := public.fn_prune_website_error_events(10);

  if exists (select 1 from public.error_events where id = v_old) then
    raise exception 'the prune left a row 20 days past its retention (id %)', v_old;
  end if;
  if not exists (select 1 from public.error_events where id = v_new) then
    raise exception 'the prune deleted a row one hour old (id %) — it must only take expired rows', v_new;
  end if;

  delete from public.error_events where id in (v_old, v_new);
  select count(*) into v_left from public.error_events where id in (v_old, v_new);
  if v_left <> 0 then raise exception 'the probe left % row(s) behind', v_left; end if;
  raise notice 'PROBE ok: the prune took the expired row and left the fresh one (%); nothing of the probe remains', v;
end $$;
