-- THE DAILY TABLE EXPORTS ARE KEPT FOR 30 DAYS, AND ONE MONTHLY COPY FOR EACH OF THE LAST 12 MONTHS.
--
-- Assigned: it_engineer. 6 Oct 2026. Founder ruling, ledger 1127 (item 3): "propose and implement
-- retention of 30 days of dailies + 12 monthlies ... that's backup data, not conversations, and it's
-- safe to rotate. Never touch the newest 7 days."
--
-- SUPERSEDES the rules in fn_backup_prune_decide from
-- the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql (90 days + Friday fulls for 12 months
-- + the first full copy of every month FOREVER). That file stays the owner of everything else in the
-- prune path (the allow-list, the planner, the log, the storage and Dropbox deleters); only the pure
-- decision function is replaced here, so this file is later in MANIFEST and is its canonical body.
-- The 15 Sep "a copy of every month for ever" rule is replaced by ruling 1127's 12 monthlies; the live
-- tables are the record of customers and suppliers, the backups are only restore points.
--
-- MEASURED BEFORE WRITING (6 Oct 2026, production, read-only):
--   * bucket 'backups': 21,063 objects, 43 GB. fn_backup_prune_mode() = 'dry_run' (app_secrets has no
--     backup_prune_mode = 'delete'). backup_prune_log's latest rows (decided_for 2026-10-05) are dry-run
--     decisions only: objects_removed 0 everywhere. So today nothing is ever deleted.
--
-- THE RULES (unchanged except where marked):
--   keep   a day 30 days old or newer                                      (was 90)
--   keep   the first complete full copy of a month within the last 12 months, or a full-less month's
--          last complete copy                                              (was: of EVERY month, forever)
--   keep   the newest complete full copy, every day after it, every day still being written, and every
--          day a kept incremental's restore chain needs
--   keep   EVERYTHING when the latest full copy failed or none is complete
--   delete everything else.                                                (the Friday rule is gone)
--   The newest 7 days are inside the 30-day window, so they can never be selected.
--
-- WHAT THIS DOES NOT DO: it does not switch deletion on. backup_prune_mode stays as it is (dry_run);
-- turning it to 'delete' is a separate, recorded production act after this is merged and applied.
-- Documents and the conversations/, generated/, accountant/ folders stay off the allow-list, as before.
--
--   node scripts/apply_sql.mjs scripts/sql/the_backups_keep_thirty_daily_copies_and_twelve_monthly_copies.sql --apply --ddl

create or replace function public.fn_backup_prune_decide(p_days jsonb, p_today date)
returns table(day date, origin text, kind text, day_status text, decision text, reason text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  with d as (
    select (e->>'day')::date as dy, coalesce(e->>'origin', 'export') as og,
           coalesce(e->>'kind', 'full') as kd, coalesce(e->>'status', '') as st
      from jsonb_array_elements(coalesce(p_days, '[]'::jsonb)) e),
  g as (
    select max(d.dy) filter (where d.kd = 'full' and d.st = 'done') as newest_full,
           max(d.dy) filter (where d.kd = 'full') as latest_full_attempt
      from d),
  -- the month's copy: its first complete full copy, or a full-less month's last complete copy
  mf as (
    select date_trunc('month', d.dy)::date as mo,
           min(d.dy) filter (where d.kd = 'full' and d.st = 'done') as first_full,
           max(d.dy) filter (where d.st = 'done') as last_done
      from d group by 1),
  k as (
    select d.dy, d.og, d.kd, d.st,
           (d.st = 'done' and (d.dy = mf.first_full or (mf.first_full is null and d.dy = mf.last_done))) as month_copy,
           (date_trunc('month', d.dy)::date > (date_trunc('month', p_today) - interval '12 months')::date) as within_12_months,
           case when g.newest_full is null then 'blocked: no complete full copy exists, so nothing is deleted'
                when g.latest_full_attempt > g.newest_full
                  then 'blocked: the latest full copy (' || g.latest_full_attempt || ') did not complete, so nothing is deleted'
           end as blocked,
           d.dy = g.newest_full as is_newest_full,
           d.dy > g.newest_full as after_newest_full,
           d.st = 'running' as running,
           (p_today - d.dy) <= 30 as within_30
      from d cross join g left join mf on mf.mo = date_trunc('month', d.dy)::date),
  kp as (
    select k.*, (k.is_newest_full or k.after_newest_full or k.running or k.within_30
                 or (k.month_copy and k.within_12_months)) as policy_keep from k),
  anchor as (
    select kp.dy as inc_day,
           (select max(f.dy) from d f where f.kd = 'full' and f.st = 'done' and f.dy <= kp.dy) as full_day
      from kp where kp.kd = 'incremental' and kp.policy_keep),
  c as (
    select kp.*, exists (select 1 from anchor a where kp.dy between a.full_day and a.inc_day) as in_kept_chain from kp)
  select c.dy, c.og, c.kd, c.st,
         case when c.blocked is not null or c.policy_keep or c.in_kept_chain then 'keep' else 'delete' end,
         case when c.blocked is not null then c.blocked
              when c.is_newest_full then 'the newest complete full copy'
              when c.after_newest_full then 'part of the newest restore chain (the newest full copy and every day after it)'
              when c.running then 'still being written'
              when c.within_30 then 'within 30 days'
              when c.month_copy and c.within_12_months and c.kd = 'full' then 'the first complete full copy of its month, within 12 months'
              when c.month_copy and c.within_12_months then 'the last complete copy of a month with no full copy, within 12 months'
              when c.in_kept_chain then 'needed by a kept kb_chunks restore chain (its full copy, or a day between)'
              when c.month_copy then 'a monthly copy older than 12 months'
              when c.st <> 'done' then 'an incomplete export (' || coalesce(nullif(c.st, ''), 'unknown') || ') older than 30 days'
              else 'a daily copy older than 30 days'
         end
    from c order by c.dy;
$fn$;
-- CREATE OR REPLACE keeps the ACL the owning file already revoked; restated so a fresh database matches.
revoke execute on function public.fn_backup_prune_decide(jsonb, date) from public, anon, authenticated;

-- PROBE: the rules on invented ZZ DEMO days (a weekly Friday full, daily incrementals, 420 days).
-- Pure: reads and writes nothing real. Returns ONE verdict row.
with p as (select date '2027-09-16' as today),
days as (
  select jsonb_agg(jsonb_build_object('day', g::date, 'origin', 'ZZ DEMO', 'status', 'done',
           'kind', case when extract(isodow from g) = 5 then 'full' else 'incremental' end)) as j
    from p, generate_series(p.today - 420, p.today, interval '1 day') g),
r as (select x.* from p, days, public.fn_backup_prune_decide(days.j, p.today) x),
checks as (
  select array_remove(array[
    case when exists (select 1 from r, p where r.decision = 'delete' and p.today - r.day <= 30)
         then 'a day 30 days old or newer was deleted' end,
    case when exists (select 1 from r, p where r.decision = 'delete' and p.today - r.day <= 7)
         then 'one of the newest 7 days was deleted' end,
    case when not exists (select 1 from r where r.reason = 'a daily copy older than 30 days' and r.decision = 'delete')
         then 'no daily copy older than 30 days was deleted' end,
    case when (select count(*) from r where r.reason like 'the first complete full copy of its month, within 12 months') not between 11 and 12
         then 'not 11-12 monthly copies kept outside 30 days: ' ||
              (select count(*) from r where r.reason like 'the first complete full copy of its month, within 12 months') end,
    case when exists (select 1 from r, p where r.decision = 'keep' and r.reason like '%month%'
                        and date_trunc('month', r.day) <= date_trunc('month', p.today) - interval '12 months')
         then 'a monthly copy 12+ months old was kept' end,
    case when not exists (select 1 from r where r.reason = 'a monthly copy older than 12 months' and r.decision = 'delete')
         then 'no old monthly copy was deleted' end,
    case when exists (select 1 from r where r.reason like '%Friday%')
         then 'the Friday rule is still live' end
  ], null) as fails)
select case when cardinality(fails) = 0 then 'PROBE OK: 30 dailies, 12 monthlies, newest 7 never deleted'
            else 'PROBE FAILED: ' || array_to_string(fails, '; ') end as verdict
  from checks;
