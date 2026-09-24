-- THE CEO DECIDES WHETHER JANUARY HOLDS, ON WHETHER THE SUPPLIER BASE CAN QUOTE EVERY TRADE.
--
-- Assigned: ceo. 24 Sep 2026. Seat audit GAPS.md, CEO gap 3 (ledger 983). The founder, 24 Sep 2026 (seat ownership
-- map): no customer revenue before January 2027; "customers are launched only once the supplier base is strong
-- enough to quote every inquiry"; October to December is supplier registration only. Approved job description,
-- quarterly: "Review strategy: ... supply coverage and the readiness gate for the customer launch. Decide whether
-- January 2027 holds."
--
-- ══ MEASURED, 24 Sep 2026 ═════════════════════════════════════════════════════════════════════════════
--   * public.supply_gap already holds the sales engineer's per-trade measurement (fn_sales_engineer_supply_gap):
--     199 rows; for every active trade in taxonomy_trade (195) one 'UAE' row with `matchable` (confirmed,
--     matchable suppliers) against `target` (pricing_config.category_open_min_suppliers, "the level at which we
--     open requests to customers", default 10). Nothing reads it as a launch gate: no routine turns it into
--     "can the base quote every inquiry", and no seat decides January on it.
--   * 4 leads carry approved_at. The gate is far from met, which is the point of measuring it now.
--
-- ══ WHAT THIS ADDS ════════════════════════════════════════════════════════════════════════════════════
--   ceo.launch_readiness, weekly (fn_ceo_launch_readiness): one row per ISO week in ceo_launch_gate —
--     trades_total  every active trade (taxonomy_trade.active), since a customer may ask for any of them;
--     trades_ready  those whose UAE-wide supply_gap row has matchable >= target;
--     the ten widest gaps by name, and the supply measurement's age.
--   The verdict is code: 'ready' only when EVERY active trade is ready (the founder's "quote every inquiry"), else
--   'not_ready'; 'not_measurable' when the supply measurement is older than 8 days (a stale reading is not a gate).
--   THE DECISION (every week from 1 Dec 2026 to 31 Jan 2027, then by the first run of each quarter): 'january_holds' when ready, otherwise
--   'launch_waits' — the customer launch waits for the gate, it is not moved to a guessed date. The founder is told
--   the decision through customer_support (information, not approval), once per decision.
--   The gate is necessary, not sufficient: launch also waits for the product to be proven in the sandbox, which
--   this does not measure and does not claim.
--
-- NOT CHANGED: fn_sales_engineer_supply_gap (the sales engineer owns the measurement and the recruitment), any
-- switch. Nothing here launches or holds anything by itself; it decides and records, and the month report carries it.
--
-- Pending: scripts/sql/pending/the_ceo_decides_whether_january_holds_on_supply_coverage.txt.

create table if not exists public.ceo_launch_gate (
  week           date primary key,            -- the ISO week's Monday, Dubai
  trades_total   integer not null,
  trades_ready   integer not null,
  coverage_pct   numeric not null,
  widest_gaps    jsonb not null default '[]'::jsonb,
  measured_at    timestamptz,                  -- max(supply_gap.measured_at) the verdict read
  verdict        text not null check (verdict in ('ready', 'not_ready', 'not_measurable')),
  decision       text check (decision in ('january_holds', 'launch_waits')),
  decided_on     date,                         -- the Dubai day the decision was taken
  founder_notice bigint,
  created_at     timestamptz not null default now()
);
alter table public.ceo_launch_gate enable row level security;
drop policy if exists ceo_launch_gate_service_role_only on public.ceo_launch_gate;
create policy ceo_launch_gate_service_role_only on public.ceo_launch_gate as permissive for all to public using (false) with check (false);
revoke all on public.ceo_launch_gate from anon, authenticated;

create or replace function public.fn_ceo_launch_readiness(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_week date := date_trunc('week', p_at at time zone 'Asia/Dubai')::date;
  v_total int; v_ready int; v_gaps jsonb; v_measured timestamptz; v_verdict text; v_decision text; v_decide boolean; v_hid bigint;
begin
  select count(*), count(*) filter (where g.matchable >= g.target), max(g.measured_at)
    into v_total, v_ready, v_measured
    from public.taxonomy_trade t left join public.supply_gap g on g.trade = t.code and g.emirate = 'UAE'
   where t.active;
  select coalesce(jsonb_agg(jsonb_build_object('trade', x.code, 'label', x.label, 'matchable', x.matchable, 'target', x.target)
                            order by x.short desc, x.code), '[]'::jsonb)
    into v_gaps
    from (select t.code, t.label, coalesce(g.matchable, 0) as matchable, g.target, coalesce(g.target, 0) - coalesce(g.matchable, 0) as short
            from public.taxonomy_trade t left join public.supply_gap g on g.trade = t.code and g.emirate = 'UAE'
           where t.active and (g.trade is null or g.matchable < g.target)
           order by short desc, t.code limit 10) x;
  v_verdict := case when v_total = 0 or v_measured is null or v_measured < p_at - interval '8 days' then 'not_measurable'
                    when v_ready = v_total then 'ready' else 'not_ready' end;
  -- Every week from 1 Dec 2026 to 31 Jan 2027 (the last month before January, and January itself); after that, the
  -- first run of each quarter decides, whatever weekday the weekly duty happens to run on (decided_on, not the week).
  -- Before December nothing is decided: October to December is supplier registration by the founder's plan.
  v_decide := (v_day >= date '2026-12-01' and v_day < date '2027-02-01')
              or (v_day >= date '2027-02-01'
                  and not exists (select 1 from public.ceo_launch_gate g where g.decided_on >= date_trunc('quarter', v_day)::date));
  v_decision := case when not v_decide then null when v_verdict = 'ready' then 'january_holds' else 'launch_waits' end;

  insert into public.ceo_launch_gate (week, trades_total, trades_ready, coverage_pct, widest_gaps, measured_at, verdict, decision, decided_on)
  values (v_week, v_total, v_ready, case when v_total > 0 then round(100.0 * v_ready / v_total, 1) else 0 end, v_gaps, v_measured, v_verdict, v_decision,
          case when v_decision is not null then v_day end)
  on conflict (week) do update set trades_total = excluded.trades_total, trades_ready = excluded.trades_ready,
    coverage_pct = excluded.coverage_pct, widest_gaps = excluded.widest_gaps, measured_at = excluded.measured_at,
    verdict = excluded.verdict,
    -- a run that takes no decision never erases one already taken this week
    decision = coalesce(excluded.decision, ceo_launch_gate.decision),
    decided_on = coalesce(excluded.decided_on, ceo_launch_gate.decided_on);

  -- the founder is told a decision once: when it is first taken, and when it changes
  if v_decision is not null and v_decision is distinct from
       (select g.decision from public.ceo_launch_gate g where g.week < v_week and g.decision is not null order by g.week desc limit 1)
     and (select founder_notice from public.ceo_launch_gate where week = v_week) is null then
    v_hid := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_launch_gate', v_week::text,
      jsonb_build_object('recipient_role', 'founder', 'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_launch_gate:' || v_week,
        'event', case v_decision when 'january_holds' then 'CEO: the customer launch in January 2027 holds'
                                 else 'CEO: the customer launch waits for supply' end,
        'detail', format('The supplier base can quote %s of %s trades (%s%%) at the level where requests open to customers. ', v_ready, v_total,
                         case when v_total > 0 then round(100.0 * v_ready / v_total, 1) else 0 end)
          || case v_decision when 'january_holds' then 'Every trade is covered, so January holds on supply.'
             else 'Customers launch only when every trade is covered. Widest gaps: '
                  || coalesce((select string_agg(format('%s %s/%s', e->>'label', e->>'matchable', e->>'target'), ', ')
                                 from jsonb_array_elements(v_gaps) e), 'none measured') || '.' end
          || ' This is the supply gate only; the product is proven in the sandbox before any launch.'));
    update public.ceo_launch_gate set founder_notice = v_hid where week = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'trades_total', v_total, 'trades_ready', v_ready, 'verdict', v_verdict,
                            'decision', v_decision, 'founder_notice', v_hid);
end $fn$;
revoke execute on function public.fn_ceo_launch_readiness(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_launch_readiness(timestamptz) to service_role;

-- the duty clock calls a routine with no arguments
create or replace function public.fn_ceo_launch_readiness_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_launch_readiness(now()) $fn$;
revoke execute on function public.fn_ceo_launch_readiness_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_launch_readiness_now() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.launch_readiness', 'ceo', interval '7 days', 'fn_ceo_launch_readiness_now',
   'Every week, the share of active trades the supplier base can quote at the customer-opening level; from 1 Dec 2026 and each quarter, the decision whether January 2027 holds.',
   'scripts/sql/the_ceo_decides_whether_january_holds_on_supply_coverage.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
