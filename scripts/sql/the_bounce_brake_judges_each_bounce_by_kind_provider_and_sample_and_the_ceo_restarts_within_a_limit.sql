-- THE BOUNCE BRAKE JUDGES EACH BOUNCE BY ITS KIND, ITS MAILBOX PROVIDER AND A SAMPLE THAT MEANS SOMETHING, AND THE CEO
-- RESTARTS WITHIN A LIMIT HELD AS DATA. Seat: sales_engineer (the brake and the seat's restart) + ceo (the CEO's restart and
-- its limit). 15 Nov 2026. Founder rulings 1696, 1701, 1705, 1706 (15 Nov 2026): the CEO has full authority and does not rely
-- on the founder; profitability first, enough registered suppliers first; bring solutions, not issues.
--
-- WHAT WAS THERE (READ from origin/main 06881a2d6; SELECT 15 Nov 2026):
--   * enqueue_supplier_invites braked on ONE number: bounced/sent over 3 days > invite_max_bounce_rate (5%) with >= 15 sends,
--     or >= 5 bounces. On 13 Nov 05:00 it read 2 of 32 = 6.3% and set invite_enabled=false (invite_brake 47). A second
--     breach inside 30 days of the seat's restart goes to the CEO; app_secrets.invite_ceo_ceiling = 0 and
--     ceo_growth_act_golive = false, so nobody could resume it: 2 bounces stopped the company for 2+ days and counting.
--   * fn_invite_same_day_brake paused on 3 bounces at >= 5% in one Dubai day, whatever the population.
--   * A bounce was one kind. notifications.provider_error_code already says which kind (fn_mail_bounce_marks_its_send):
--     SELECT 15 Nov, all 129 real invitation sends: 13 hard (5.1.1 x6, gmail:NoSuchUser x4, 5.4.310/311 domain gone x2, one
--     lead marked bounced with no code), 1 policy (5.7.368), 1 soft (5.4.316 connection expired), 0 complaints.
--   * One number over two populations (the lesson of the_bounce_rate_was_one_number_over_two_populations.sql, again):
--     since 2 Nov the CEO's lever invite_reachable_only sends only checked mailboxes. Checked: 5 hard of 91 sent all time;
--     unchecked: 8 of 38. The 3-day number mixed what the company no longer sends with what it does.
-- WHAT THIS DOES:
--   1. fn_invite_bounce_kind: hard (the address or domain does not exist), policy (the provider refused us: 5.7.x), soft
--      (temporary, mailbox full, connection), complaint (a person pressed spam).
--   2. fn_invite_bounce_judgement: over a 14-day window (and over today's sends alone, for a burst), per mailbox provider
--      class (fn_mail_provider_of_email) and per list segment (checked / unchecked mailbox), the Wilson score 95% one-sided
--      LOWER bound of each rate. A rate brakes only when we are 95% sure the true rate is over its limit, and only on at least
--      2 events of that kind. Limits as data (app_secrets.invite_bounce_judge, seeded below with the reasons):
--        hard     lower bound > 3%   (ESP warning line 2%, review line 5%: we brake when the evidence says we are above 3%)
--        policy   lower bound > 3%   (a provider refusing us is reputation, judged per provider class: that class is held)
--        complaint lower bound > 0.3% on 1 event (Google and Yahoo bulk-sender rule: 0.3%): the company stops, any segment
--        soft     never brakes; lower bound > 15% only holds the ramp (a provider throttling or greylisting us)
--      Measured on the real sends (SELECT 15 Nov): 13 Nov 05:00 3-day 2/32 -> lower bound 2.1%: no brake (the old rule
--      braked). 4 Nov same day 3/20 -> 6.2%: brake (the old rule braked too, rightly). Checked segment, 14 days to 15 Nov:
--      3/60 -> 2.0%: no brake. Unchecked segment, 14 days: 4/17 -> brake, but nothing in it is sent while reachable_only is on.
--   3. fn_invite_judge_and_brake: the one place a judgement becomes a brake. A complaint, or a hard-bounce breach in a
--      segment being sent, stops the company (invite_brake + fn_invite_campaign_pause, paused_by invite_bounce_judge); a
--      policy or hard breach confined to one provider class holds that class only (enqueue_supplier_invites leaves it out:
--      the_invitation_ramps_on_measured_health_and_tests_its_copy.sql). Every brake and hold is a row in
--      public.invite_brake_decision with its reason and the evidence.
--   4. fn_invite_same_day_brake: a complaint still stops the campaign the same hour; a bounce now asks the judgement.
--   5. fn_sales_engineer_restarts_invites_after_a_brake: unchanged rules (suppress first, go-live, no complaint, another
--      seat's pause, second breach to the CEO, 3-day cooldown), except that its probation is judged by the same lower bound
--      on the sends since the restart, and every restart, hold and refusal is recorded.
--   6. public.growth_limit_change + fn_growth_limit: the CEO's limits as an append-only history, the pattern of
--      the_company_limits_bind_every_seat_and_the_ceo_changes_one_only_after_a_day.sql (branch
--      ceo-the-ceo-acts-and-orders-the-seats-to-grow-supply), self-contained here so this file does not depend on that branch
--      being merged: the first value in force at once, every later change a day after it is written, with a reason, only by
--      the CEO. One limit: ceo_invite_restarts_per_30d, seeded 2 (one restart is the seat's job; the CEO may restart twice in
--      30 days beyond it; a third needs him to raise his own limit, a day ahead, with a reason).
--   7. fn_ceo_restarts_invites(reason): the CEO's restart, within that limit, never over a complaint, never under another
--      seat's pause, 24 h after the brake at the earliest, bounced addresses suppressed first, on the seat's probation (a first
--      batch of at most 10, fn_invite_restart_cap). fn_ceo_reviews_the_invite_brake (seat duty ceo.invite_brake_review, hourly):
--      the CEO seat decides a brake the seat may not lift, by the judgement: it restarts when the brake would not fire on the
--      judgement of today, or after 7 days of rest with no complaint; otherwise it records why it holds (once a Dubai day).
-- WHAT THIS DOES NOT CHANGE: the placement gate (fn_invite_placement_open_providers; never Microsoft or Yahoo/AOL, founder
-- instruction 1537), suppression, the founder's supplier_outreach_golive, the complaint pause of fn_invite_ramp.
-- prevented by: scripts/checks/the_supplier_funnel_runs_itself.test.mjs (text) and
-- the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit_probe.sql (LOCAL).
-- APPLY ORDER: this file, then the_invitation_ramps_on_measured_health_and_tests_its_copy.sql (its enqueue reads the
-- judgement), then every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql, then
-- the_ceo_approves_the_marketing_month_publishes_articles_and_holds_the_marketing_switch.sql.
-- LOCKS: two new tables; invite_brake (47 rows) gets two nullable columns (ACCESS EXCLUSIVE for milliseconds); the trigger
-- function z80_invite_same_day_brake runs is replaced in place (no lock on public.leads). Apply outside a sending minute.
set local lock_timeout = '1500ms';

-- ── 1. THE CEO'S LIMITS, AS DATA ──────────────────────────────────────────────────────────────────────────────────
create table if not exists public.growth_limit_change (
  id bigserial primary key,
  limit_key text not null check (limit_key in ('ceo_invite_restarts_per_30d')),
  value numeric(12,2) not null check (value >= 0 and value <= 1000),
  reason text not null check (length(btrim(reason)) >= 20),
  set_by text not null check (set_by in ('ceo', 'seed')),
  set_at timestamptz not null default now(),
  effective_at timestamptz not null);
comment on table public.growth_limit_change is 'The CEO''s growth limits (founder ledger 1696): append-only; the first value of a limit is in force at once, every later change 24 hours after it is written, only by the CEO and with a reason; fn_growth_limit(key) is the value in force now. the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql';

create or replace function public.trg_growth_limit_change_waits_a_day()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if tg_op <> 'INSERT' then
    raise exception 'growth_limit_change is append-only: a limit is changed by a new row (fn_ceo_sets_growth_limit), never edited';
  end if;
  new.set_at := now();
  if exists (select 1 from public.growth_limit_change c where c.limit_key = new.limit_key) then
    if new.set_by <> 'ceo' then raise exception 'only the CEO changes a growth limit once it exists'; end if;
    new.effective_at := now() + interval '24 hours';   -- whatever the writer asked: a change waits a day
  else
    new.effective_at := now();                          -- the first value of a limit is in force at once
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_growth_limit_change_waits_a_day() from public, anon, authenticated;
create or replace trigger trg_growth_limit_change_waits_a_day before insert or update or delete on public.growth_limit_change
  for each row execute function public.trg_growth_limit_change_waits_a_day();

create table if not exists public.invite_brake_decision (
  id bigserial primary key,
  brake_id bigint,
  decision text not null check (decision in ('brake', 'class_held', 'restart', 'restart_refused', 'hold')),
  actor text not null check (actor in ('judge', 'sales_engineer', 'ceo')),
  provider_class text,
  reason text not null check (length(btrim(reason)) >= 10),
  evidence jsonb not null default '{}'::jsonb,
  decided_at timestamptz not null default now());
comment on table public.invite_brake_decision is 'Every brake, held provider class, restart, refused restart and hold of the supplier invitations, with who decided, why and the judgement it read (rulings 1696/1705). Append-only. the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql';
create index if not exists invite_brake_decision_actor_at on public.invite_brake_decision (actor, decision, decided_at desc);

create or replace function public.trg_invite_brake_decision_is_history()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  raise exception 'invite_brake_decision is history: a decision is never edited or deleted';
end $fn$;
revoke execute on function public.trg_invite_brake_decision_is_history() from public, anon, authenticated;
create or replace trigger trg_invite_brake_decision_is_history before update or delete on public.invite_brake_decision
  for each row execute function public.trg_invite_brake_decision_is_history();

do $guard$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.growth_limit_change'::regclass) then
    alter table public.growth_limit_change enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'growth_limit_change' and policyname = 'growth_limit_change_service_role_only') then
    create policy growth_limit_change_service_role_only on public.growth_limit_change as permissive for all to public using (false) with check (false);
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.invite_brake_decision'::regclass) then
    alter table public.invite_brake_decision enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invite_brake_decision' and policyname = 'invite_brake_decision_service_role_only') then
    create policy invite_brake_decision_service_role_only on public.invite_brake_decision as permissive for all to public using (false) with check (false);
  end if;
end $guard$;
revoke all on public.growth_limit_change from anon, authenticated;
revoke all on public.invite_brake_decision from anon, authenticated;
revoke all on sequence public.growth_limit_change_id_seq from anon, authenticated;
revoke all on sequence public.invite_brake_decision_id_seq from anon, authenticated;

-- who restarted, and the judgement a brake read (nullable: the 47 rows before this file keep restarted_by_seat as they were)
alter table public.invite_brake add column if not exists restarted_by text;
alter table public.invite_brake add column if not exists evidence jsonb;

create or replace function public.fn_growth_limit(p_key text)
returns numeric language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select c.value from public.growth_limit_change c
   where c.limit_key = p_key and c.effective_at <= now()
   order by c.effective_at desc, c.id desc limit 1
$fn$;
revoke execute on function public.fn_growth_limit(text) from public, anon, authenticated;

create or replace function public.fn_ceo_sets_growth_limit(p_key text, p_value numeric, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.growth_limit_change;
begin
  if p_key not in ('ceo_invite_restarts_per_30d') then return jsonb_build_object('ok', false, 'reason', 'no such limit: ceo_invite_restarts_per_30d'); end if;
  if p_value is null or p_value < 0 or p_value > 1000 then return jsonb_build_object('ok', false, 'reason', 'a limit is a number from 0 to 1000'); end if;
  if length(btrim(coalesce(p_reason, ''))) < 20 then return jsonb_build_object('ok', false, 'reason', 'say why, in a sentence (20 characters or more)'); end if;
  if exists (select 1 from public.growth_limit_change x where x.limit_key = p_key and x.effective_at > now()) then
    return jsonb_build_object('ok', false, 'reason', 'a change of ' || p_key || ' already waits; it takes effect first');
  end if;
  insert into public.growth_limit_change (limit_key, value, reason, set_by, effective_at)
  values (p_key, p_value, btrim(p_reason), 'ceo', now()) returning * into c;   -- the trigger moves effective_at a day on
  return jsonb_build_object('ok', true, 'id', c.id, 'limit', c.limit_key, 'value', c.value, 'in_force_now', public.fn_growth_limit(p_key),
                            'effective_at', c.effective_at);
end $fn$;
revoke execute on function public.fn_ceo_sets_growth_limit(text, numeric, text) from public, anon, authenticated;
grant execute on function public.fn_ceo_sets_growth_limit(text, numeric, text) to service_role;

insert into public.growth_limit_change (limit_key, value, reason, set_by, effective_at)
select 'ceo_invite_restarts_per_30d', 2,
       'Seed (founder ledger 1696, 1705): the CEO may restart the supplier invitations twice in 30 days beyond the sales engineer''s one; each restart starts on probation at 10 invitations, so two restarts risk at most 20 sends on a bad list.',
       'seed', now()
 where not exists (select 1 from public.growth_limit_change where limit_key = 'ceo_invite_restarts_per_30d');

-- The judge's limits (data; a seat changes them with a reason in the same row's note). Seeded once.
insert into public.app_secrets (key, value) values ('invite_bounce_judge', jsonb_build_object(
  'window_days', 14, 'z', 1.645,
  'hard_limit', 0.03, 'hard_min', 2,
  'policy_limit', 0.03, 'policy_min', 2,
  'complaint_limit', 0.003, 'complaint_min', 1,
  'soft_hold_limit', 0.15,
  'note', 'Wilson 95% one-sided lower bounds. hard 3%: between the ESP warning line (2%) and review line (5%); policy 3% per provider class; complaint 0.3% (Google/Yahoo bulk-sender rule) on one event; soft never brakes. Seeded 15 Nov 2026 by the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql.')::text)
on conflict (key) do nothing;

-- ── 2. THE KIND OF A BOUNCE, AND THE LOWER BOUND OF A RATE ────────────────────────────────────────────────────────
-- p_code: notifications.provider_error_code ('bounce:5.1.1', 'bounce:gmail:NoSuchUser'); p_status: the send's provider_status;
-- p_lead_status: leads.invite_status. Null = no bounce of any kind.
create or replace function public.fn_invite_bounce_kind(p_code text, p_status text, p_lead_status text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_lead_status = 'complained' then 'complaint'
    when c ~ '(^|:)5\.7\.[0-9]' or c ~* 'gmail:(unsolicited|policy|blocked|bulk|spam|dmarc|auth)' then 'policy'
    when c ~ '(^|:)5\.1\.[0-9]' or c ~ '(^|:)5\.4\.(1|4|310|311)$' or c ~* 'gmail:(nosuchuser|disableduser|invalid|addressnotfound)' then 'hard'
    when c <> '' then 'soft'
    when p_lead_status = 'bounced' then 'hard'          -- marked bounced by a permanent-failure reading, code not stored
    when lower(coalesce(p_status, '')) in ('bounced', 'undelivered', 'failed') then 'soft'
    else null end
    from (select lower(btrim(coalesce(p_code, ''))) as c) x
$fn$;
revoke execute on function public.fn_invite_bounce_kind(text, text, text) from public, anon, authenticated;

-- Wilson score interval, lower end: the smallest true rate the evidence does not rule out at confidence z (one-sided).
create or replace function public.fn_invite_wilson_lower(p_k integer, p_n integer, p_z numeric default 1.645)
returns numeric language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when coalesce(p_n, 0) <= 0 or coalesce(p_k, 0) <= 0 then 0::numeric else
    round(greatest(0::numeric,
      ((p_k::numeric / p_n) + p_z * p_z / (2 * p_n)
        - p_z * sqrt(((p_k::numeric / p_n) * (1 - p_k::numeric / p_n) + p_z * p_z / (4 * p_n)) / p_n))
      / (1 + p_z * p_z / p_n)), 4) end
$fn$;
revoke execute on function public.fn_invite_wilson_lower(integer, integer, numeric) from public, anon, authenticated;

-- One cell of the judgement: counts, lower bounds, and which limit (if any) it breaches.
create or replace function public.fn_invite_judge_cell(p_sent integer, p_hard integer, p_policy integer, p_soft integer, p_complaint integer, p_cfg jsonb)
returns jsonb language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare z numeric := coalesce((p_cfg->>'z')::numeric, 1.645);
  hl numeric := public.fn_invite_wilson_lower(p_hard, p_sent, z);
  pl numeric := public.fn_invite_wilson_lower(p_policy, p_sent, z);
  sl numeric := public.fn_invite_wilson_lower(p_soft, p_sent, z);
  cl numeric := public.fn_invite_wilson_lower(p_complaint, p_sent, z);
  v_breach text;
begin
  v_breach := case
    when p_complaint >= coalesce((p_cfg->>'complaint_min')::int, 1) and cl > coalesce((p_cfg->>'complaint_limit')::numeric, 0.003) then 'complaint'
    when p_hard >= coalesce((p_cfg->>'hard_min')::int, 2) and hl > coalesce((p_cfg->>'hard_limit')::numeric, 0.03) then 'hard'
    when p_policy >= coalesce((p_cfg->>'policy_min')::int, 2) and pl > coalesce((p_cfg->>'policy_limit')::numeric, 0.03) then 'policy'
    end;
  return jsonb_build_object('sent', p_sent, 'hard', p_hard, 'policy', p_policy, 'soft', p_soft, 'complaint', p_complaint,
    'hard_lb', hl, 'policy_lb', pl, 'soft_lb', sl, 'complaint_lb', cl, 'breach', v_breach,
    'soft_hold', p_sent > 0 and sl > coalesce((p_cfg->>'soft_hold_limit')::numeric, 0.15));
end $fn$;
revoke execute on function public.fn_invite_judge_cell(integer, integer, integer, integer, integer, jsonb) from public, anon, authenticated;

-- ── 3. THE JUDGEMENT ──────────────────────────────────────────────────────────────────────────────────────────────
-- p_since overrides the window (a probation reads only the sends since its restart). A segment is 'checked' when the lead's
-- mailbox was proven (email_verified verified/true/maps/social: the set invite_reachable_only sends to), else 'unchecked'.
create or replace function public.fn_invite_bounce_judgement(p_now timestamptz default now(), p_since timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_bounce_judge'), '{}'::jsonb);
  v_from timestamptz := coalesce(p_since, p_now - make_interval(days => coalesce((v_cfg->>'window_days')::int, 14)));
  v_day timestamptz := ((p_now at time zone 'Asia/Dubai')::date)::timestamp at time zone 'Asia/Dubai';
  v_reach boolean := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_reachable_only'), false);
  v_cells jsonb := '{}'::jsonb; v_today jsonb := '{}'::jsonb; v_all jsonb; v_today_all jsonb; r record;
  v_company text; v_held text[] := '{}'; v_why text; v_sent_segments text[]; v_rows jsonb; v_segall jsonb;
begin
  -- the sends being judged, read once into one array (a STABLE routine: no temporary table)
  select coalesce(jsonb_agg(jsonb_build_object(
           'c', coalesce(public.fn_mail_provider_of_email(n.to_email), 'other'),
           's', case when l.email_verified in ('verified', 'true', 'maps', 'social') then 'checked' else 'unchecked' end,
           'k', public.fn_invite_bounce_kind(n.provider_error_code, n.provider_status, l.invite_status),
           't', n.sent_at >= v_day)), '[]'::jsonb)
    into v_rows
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.sent_at is not null and n.sent_at > v_from and n.sent_at <= p_now
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email);

  for r in select x.c as cls, x.s as seg, count(*)::int sent, (count(*) filter (where x.k = 'hard'))::int hard, (count(*) filter (where x.k = 'policy'))::int pol,
                  (count(*) filter (where x.k = 'soft'))::int soft, (count(*) filter (where x.k = 'complaint'))::int compl
             from jsonb_to_recordset(v_rows) as x(c text, s text, k text, t boolean) group by x.c, x.s loop
    v_cells := v_cells || jsonb_build_object(r.cls || ':' || r.seg, public.fn_invite_judge_cell(r.sent, r.hard, r.pol, r.soft, r.compl, v_cfg)
                 || jsonb_build_object('class', r.cls, 'segment', r.seg));
  end loop;
  for r in select x.c as cls, x.s as seg, count(*)::int sent, (count(*) filter (where x.k = 'hard'))::int hard, (count(*) filter (where x.k = 'policy'))::int pol,
                  (count(*) filter (where x.k = 'soft'))::int soft, (count(*) filter (where x.k = 'complaint'))::int compl
             from jsonb_to_recordset(v_rows) as x(c text, s text, k text, t boolean) where x.t group by x.c, x.s loop
    v_today := v_today || jsonb_build_object(r.cls || ':' || r.seg, public.fn_invite_judge_cell(r.sent, r.hard, r.pol, r.soft, r.compl, v_cfg)
                 || jsonb_build_object('class', r.cls, 'segment', r.seg));
  end loop;
  select public.fn_invite_judge_cell(count(*)::int, (count(*) filter (where x.k = 'hard'))::int, (count(*) filter (where x.k = 'policy'))::int,
           (count(*) filter (where x.k = 'soft'))::int, (count(*) filter (where x.k = 'complaint'))::int, v_cfg)
    into v_all from jsonb_to_recordset(v_rows) as x(c text, s text, k text, t boolean);
  select public.fn_invite_judge_cell(count(*)::int, (count(*) filter (where x.k = 'hard'))::int, (count(*) filter (where x.k = 'policy'))::int,
           (count(*) filter (where x.k = 'soft'))::int, (count(*) filter (where x.k = 'complaint'))::int, v_cfg)
    into v_today_all from jsonb_to_recordset(v_rows) as x(c text, s text, k text, t boolean) where x.t;

  -- the segments the company sends now: checked only while invite_reachable_only is on
  v_sent_segments := case when v_reach then array['checked'] else array['checked', 'unchecked'] end;

  -- A COMPLAINT stops the company whatever its segment or class (a person pressed spam: never noise)
  if (v_all->>'complaint')::int > 0 and v_all->>'breach' = 'complaint' then
    v_company := 'complaint'; v_why := (v_all->>'complaint') || ' spam complaint(s) on ' || (v_all->>'sent') || ' invitation(s) in the window (95% lower bound '
      || round((v_all->>'complaint_lb')::numeric * 100, 2) || '% > ' || round(coalesce((v_cfg->>'complaint_limit')::numeric, 0.003) * 100, 2) || '%)';
  elsif (v_today_all->>'complaint')::int > 0 and v_today_all->>'breach' = 'complaint' then
    v_company := 'complaint'; v_why := (v_today_all->>'complaint') || ' spam complaint(s) on ' || (v_today_all->>'sent') || ' invitation(s) today';
  end if;

  -- HARD or POLICY in a sent segment: that provider class is held. Hard over every sent segment together: the company stops.
  for r in select key, value from jsonb_each(v_cells) union all select key, value from jsonb_each(v_today) loop
    if r.value->>'segment' = any (v_sent_segments) and r.value->>'breach' in ('hard', 'policy') and not ((r.value->>'class') = any (v_held)) then
      v_held := v_held || (r.value->>'class');
    end if;
  end loop;
  if v_company is null then
    select public.fn_invite_judge_cell(count(*)::int, (count(*) filter (where x.k = 'hard'))::int, 0, 0, 0, v_cfg) into v_all
      from jsonb_to_recordset(v_rows) as x(c text, s text, k text, t boolean) where x.s = any (v_sent_segments);
    if v_all->>'breach' = 'hard' then
      v_company := 'hard'; v_why := (v_all->>'hard') || ' hard bounce(s) on ' || (v_all->>'sent') || ' invitation(s) to the mailboxes the company sends to (95% lower bound '
        || round((v_all->>'hard_lb')::numeric * 100, 1) || '% > ' || round(coalesce((v_cfg->>'hard_limit')::numeric, 0.03) * 100, 1) || '%)';
    else
      select public.fn_invite_judge_cell(count(*)::int, (count(*) filter (where x.k = 'hard'))::int, 0, 0, 0, v_cfg) into v_today_all
        from jsonb_to_recordset(v_rows) as x(c text, s text, k text, t boolean) where x.t and x.s = any (v_sent_segments);
      if v_today_all->>'breach' = 'hard' then
        v_company := 'hard'; v_why := (v_today_all->>'hard') || ' hard bounce(s) on ' || (v_today_all->>'sent') || ' invitation(s) today (95% lower bound '
          || round((v_today_all->>'hard_lb')::numeric * 100, 1) || '% > ' || round(coalesce((v_cfg->>'hard_limit')::numeric, 0.03) * 100, 1) || '%)';
      end if;
    end if;
  end if;

  select public.fn_invite_judge_cell(count(*)::int, (count(*) filter (where x.k = 'hard'))::int, (count(*) filter (where x.k = 'policy'))::int,
           (count(*) filter (where x.k = 'soft'))::int, (count(*) filter (where x.k = 'complaint'))::int, v_cfg)
    into v_all from jsonb_to_recordset(v_rows) as x(c text, s text, k text, t boolean);
  select public.fn_invite_judge_cell(count(*)::int, (count(*) filter (where x.k = 'hard'))::int, (count(*) filter (where x.k = 'policy'))::int,
           (count(*) filter (where x.k = 'soft'))::int, (count(*) filter (where x.k = 'complaint'))::int, v_cfg)
    into v_segall from jsonb_to_recordset(v_rows) as x(c text, s text, k text, t boolean) where x.s = any (v_sent_segments);
  return jsonb_build_object(
    'at', p_now, 'since', v_from, 'window_days', coalesce((v_cfg->>'window_days')::int, 14), 'limits', v_cfg - 'note',
    'sent_segments', to_jsonb(v_sent_segments), 'cells', v_cells, 'today', v_today,
    'all', v_all, 'sent_segment_all', v_segall,
    'company_brake', v_company is not null, 'company_reason', v_company, 'why', v_why,
    'held_classes', to_jsonb(v_held));
end $fn$;
revoke execute on function public.fn_invite_bounce_judgement(timestamptz, timestamptz) from public, anon, authenticated;

-- ── 4. A JUDGEMENT BECOMES A BRAKE HERE, AND ONLY HERE ────────────────────────────────────────────────────────────
create or replace function public.fn_invite_judge_and_brake(p_source text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare j jsonb := public.fn_invite_bounce_judgement(now()); v_bid bigint; c text;
  v_on boolean := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false);
begin
  -- a held provider class: recorded once a Dubai day per class (enqueue leaves it out while the judgement holds it)
  for c in select jsonb_array_elements_text(j->'held_classes') loop
    if not exists (select 1 from public.invite_brake_decision d where d.decision = 'class_held' and d.provider_class = c
                    and (d.decided_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date) then
      insert into public.invite_brake_decision (decision, actor, provider_class, reason, evidence)
      values ('class_held', 'judge', c, 'the ' || c || ' mailboxes breach a bounce limit on the judgement: held from today''s batch while the window shows it ('
              || coalesce(p_source, '-') || ')', j);
    end if;
  end loop;
  if not (j->>'company_brake')::boolean or not v_on then
    return jsonb_build_object('braked', false, 'held_classes', j->'held_classes', 'judgement', j);
  end if;
  insert into public.invite_brake (source, why, evidence) values (coalesce(p_source, 'invite_bounce_judge'), j->>'why', j)
  on conflict do nothing returning id into v_bid;
  perform public.fn_invite_campaign_pause('invite_bounce_judge', j->>'why', jsonb_build_object('judgement', j, 'called_by', p_source),
    jsonb_build_object('company_reason', j->>'company_reason'));
  insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
  values (coalesce(v_bid, (select id from public.invite_brake where resumed_at is null order by id desc limit 1)), 'brake', 'judge',
          'Supplier invitations stopped: ' || (j->>'why'), j);
  -- the CEO reads it in his own review (ceo.invite_brake_review); the founder is informed, never asked (ruling 1696)
  if not exists (select 1 from public.founder_alerts where event = 'invite_paused_bounce' and created_at > now() - interval '24 hours') then
    insert into public.founder_alerts (level, event, detail, channel)
    values ('warn', 'invite_paused_bounce', 'Supplier invitations stopped by the bounce judgement: ' || (j->>'why')
            || '. The sales engineer restarts after the cooldown; a second stop is the CEO''s to decide within his limit. Information only.', 'system');
  end if;
  return jsonb_build_object('braked', true, 'brake_id', v_bid, 'why', j->>'why', 'judgement', j);
end $fn$;
revoke execute on function public.fn_invite_judge_and_brake(text) from public, anon, authenticated;

-- ── 5. THE SAME-DAY BRAKE: a complaint stops at once; a bounce asks the judgement ─────────────────────────────────
create or replace function public.fn_invite_same_day_brake()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_cr_max numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_c_min  int     := coalesce((c->>'same_day_pause_min_complaints')::int, 1);
  v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_sent int; v_b int; v_c int; v_why text;
begin
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    return null;  -- already stopped; nothing more to stop
  end if;
  select h.sent, h.bounced, h.complained into v_sent, v_b, v_c
    from public.fn_invite_send_health(v_day::timestamp at time zone 'Asia/Dubai') h;
  if v_c >= v_c_min and v_c::numeric / greatest(v_sent, 1) >= v_cr_max then
    -- a person pressed spam: the campaign stops this hour, as before
    v_why := v_c || ' spam complaint(s) on ' || v_sent || ' invitation(s) today';
    perform public.fn_invite_campaign_pause('invite_same_day_brake', v_why,
      jsonb_build_object('dubai_day', v_day, 'sent', v_sent, 'bounced', v_b, 'complained', v_c),
      jsonb_build_object('sent_today', v_sent, 'bounced_today', v_b, 'complained_today', v_c));
    insert into public.invite_brake_decision (decision, actor, reason, evidence)
    values ('brake', 'judge', 'Supplier invitations stopped the same hour: ' || v_why, jsonb_build_object('dubai_day', v_day, 'sent', v_sent, 'complained', v_c));
    return null;
  end if;
  -- a bounce: the judgement decides by kind, provider and a sample that means something (today's sends and the window)
  perform public.fn_invite_judge_and_brake('invite_same_day_brake');
  return null;
end $fn$;
revoke execute on function public.fn_invite_same_day_brake() from public, anon, authenticated;

-- ── 6. THE SALES ENGINEER'S RESTART (the rules of 2-13 Nov; the probation judged by the lower bound; every step recorded) ─
create or replace function public.fn_sales_engineer_restarts_invites_after_a_brake()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  b public.invite_brake; v_on boolean; v_suppressed int; v_batch int; v_since timestamptz; j jsonb; v_why text;
begin
  select * into b from public.invite_brake where resumed_at is null order by id desc limit 1;
  if not found then
    -- A campaign somebody else stopped is not on probation.
    if not coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false) then
      return jsonb_build_object('open_brake', false);
    end if;
    -- PROBATION: for 30 days after a restart (the seat's or the CEO's) the sends SINCE that restart answer for it, judged by
    -- the same lower bound as the brake (a batch of 10 cannot reach a 3-day rule's 15 sends; a rate on 10 is not evidence).
    select max(x.resumed_at) into v_since from public.invite_brake x where x.resumed_at > now() - interval '30 days'
       and exists (select 1 from public.invite_brake y where y.restarted_by_seat and y.resumed_at > now() - interval '30 days');
    if v_since is null then return jsonb_build_object('open_brake', false); end if;
    j := public.fn_invite_bounce_judgement(now(), v_since);
    if not coalesce((j->>'company_brake')::boolean, false) then
      return jsonb_build_object('open_brake', false, 'probation', true, 'since', v_since, 'sent', j->'sent_segment_all'->'sent',
                                'hard', j->'sent_segment_all'->'hard', 'hard_lb', j->'sent_segment_all'->'hard_lb');
    end if;
    update public.app_secrets set value = 'false' where key = 'invite_enabled';
    update public.notifications set status = 'cancelled' where type = 'supplier_invite' and status = 'queued';
    insert into public.invite_brake(source, why, evidence)
    values ('invite_restart_probation', 'on probation since the restart: ' || (j->>'why'), j)
    returning * into b;
    insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
    values (b.id, 'brake', 'judge', 'The restart''s probation failed: ' || (j->>'why'), j);
  end if;
  v_on := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false);
  if v_on then
    update public.invite_brake set resumed_at = now(), resume_note = 'invite_enabled was already back on: not this seat''s restart' where id = b.id;
    return jsonb_build_object('open_brake', true, 'closed', 'already on');
  end if;

  -- The bounced addresses first: every real bounce is suppressed, whatever else holds the restart.
  insert into public.email_suppressions (email, reason, source)
  select distinct lower(btrim(l.email)), 'hard_bounce:permanent', 'sales_engineer_invite_restart'
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.sent_at is not null and l.invite_status = 'bounced'
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
  on conflict (email) do nothing;
  get diagnostics v_suppressed = row_count;

  j := public.fn_invite_bounce_judgement(now());
  -- Not this seat's to lift: the founder's go, a complaint (a person pressed spam; read it, do not resend), another seat's pause.
  if not public.fn_supplier_outreach_golive() then
    return jsonb_build_object('open_brake', true, 'held', 'supplier_outreach_golive is false', 'suppressed', v_suppressed);
  end if;
  if coalesce((j->'all'->>'complaint')::int, 0) > 0 then
    return jsonb_build_object('open_brake', true, 'held', 'a complaint in the judgement window', 'suppressed', v_suppressed);
  end if;
  if exists (select 1 from public.it_watch_finding f
              where f.detector_key = 'deliverability:supplier_invite' and f.status = 'open' and f.state = 'paused'
                and f.evidence->>'paused_by' not in ('invite_same_day_brake', 'invite_bounce_judge')) then
    return jsonb_build_object('open_brake', true, 'held', 'another seat''s pause is open', 'suppressed', v_suppressed);
  end if;

  -- A SECOND BREACH inside 30 days of a restart stays paused, and the CEO seat owns it (fn_ceo_reviews_the_invite_brake).
  if exists (select 1 from public.invite_brake x where x.id <> b.id and x.restarted_by_seat and x.resumed_at > b.fired_at - interval '30 days') then
    if b.ceo_task_opened_at is null then
      perform public.fn_ceo_task_open('Supplier invitations stopped twice on bounces in 30 days',
        'The bounce brake fired again after a restart: ' || b.why || '. The sales engineer does not restart a second breach. '
        || 'The CEO seat decides it in ceo.invite_brake_review, by the judgement, within ceo_invite_restarts_per_30d.');
      update public.invite_brake set ceo_task_opened_at = now() where id = b.id;
      insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
      values (b.id, 'hold', 'sales_engineer', 'A second stop inside 30 days of a restart: the CEO seat decides it, within its restart limit.', j);
    end if;
    return jsonb_build_object('open_brake', true, 'held', 'second breach: the CEO seat decides', 'suppressed', v_suppressed);
  end if;

  -- THE COOLDOWN. The judgement window is not reset by a restart, so a restart cannot erase its own breach.
  if now() < b.fired_at + interval '3 days' then
    return jsonb_build_object('open_brake', true, 'held', 'cooldown', 'until', b.fired_at + interval '3 days', 'suppressed', v_suppressed);
  end if;

  -- Somebody must be there to send to; candidates come only through the verdict gate, so this is a count, not a second check.
  select count(*) into v_batch from public.fn_supplier_invite_candidates(10, null::text[]) c;
  if v_batch = 0 then
    return jsonb_build_object('open_brake', true, 'held', 'no verified lead to send to yet', 'suppressed', v_suppressed);
  end if;

  v_why := 'bounced addresses suppressed (' || v_suppressed || ' new); first batch of at most ' || v_batch || '; on probation by the judgement';
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  update public.invite_brake set resumed_at = now(), restarted_by_seat = true, restarted_by = 'sales_engineer', resume_note = v_why where id = b.id;
  update public.it_watch_finding set status = 'resolved', resolved_at = now()
   where detector_key = 'deliverability:supplier_invite' and status = 'open';
  insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
  values (b.id, 'restart', 'sales_engineer', 'Invitations resumed after the cooldown of the brake of '
          || to_char(b.fired_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z: ' || v_why, j);
  insert into public.agent_runs(agent, status, counts, note, finished_at)
  values ('sales_engineer', 'ok', jsonb_build_object('action', 'invite_restart', 'brake', b.id, 'batch', v_batch, 'suppressed', v_suppressed),
          'Invitations resumed after the bounce brake of ' || to_char(b.fired_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z: ' || b.why, now());
  return jsonb_build_object('resumed', true, 'batch', v_batch, 'suppressed', v_suppressed);
end $fn$;
revoke execute on function public.fn_sales_engineer_restarts_invites_after_a_brake() from public, anon, authenticated;

-- ── 7. THE CEO'S RESTART, WITHIN ITS LIMIT ────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_restarts_invites(p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare b public.invite_brake; j jsonb; v_limit numeric := public.fn_growth_limit('ceo_invite_restarts_per_30d'); v_used int;
  v_suppressed int; v_batch int; v_refuse text;
begin
  perform pg_advisory_xact_lock(hashtext('fn_ceo_restarts_invites'));
  select * into b from public.invite_brake where resumed_at is null order by id desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no brake is open: nothing to restart'); end if;
  j := public.fn_invite_bounce_judgement(now());
  select count(*) into v_used from public.invite_brake_decision d
   where d.actor = 'ceo' and d.decision = 'restart' and d.decided_at > now() - interval '30 days';
  v_refuse := case
    when length(btrim(coalesce(p_reason, ''))) < 20 then 'a restart says why, in a sentence (20 characters or more)'
    when v_limit is null then 'the CEO''s restart limit is not set (growth_limit_change ceo_invite_restarts_per_30d)'
    when v_used >= v_limit then 'the CEO''s restart limit is reached: ' || v_used || ' of ' || v_limit || ' in 30 days (fn_ceo_sets_growth_limit raises it a day later, with a reason)'
    when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
    when coalesce((j->'all'->>'complaint')::int, 0) > 0 then 'a person complained in the judgement window: never restarted over a complaint'
    when exists (select 1 from public.it_watch_finding f where f.detector_key = 'deliverability:supplier_invite' and f.status = 'open'
                  and f.state = 'paused' and f.evidence->>'paused_by' not in ('invite_same_day_brake', 'invite_bounce_judge')) then 'another seat''s pause is open'
    when now() < b.fired_at + interval '24 hours' then 'the brake is not 24 hours old yet (until ' || to_char((b.fired_at + interval '24 hours') at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z)'
    end;
  if v_refuse is not null then
    insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
    values (b.id, 'restart_refused', 'ceo', 'Restart refused: ' || v_refuse, jsonb_build_object('asked_reason', p_reason, 'judgement', j, 'used', v_used, 'limit', v_limit));
    return jsonb_build_object('ok', false, 'reason', v_refuse, 'used', v_used, 'limit', v_limit);
  end if;
  insert into public.email_suppressions (email, reason, source)
  select distinct lower(btrim(l.email)), 'hard_bounce:permanent', 'ceo_invite_restart'
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.sent_at is not null and l.invite_status = 'bounced'
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
  on conflict (email) do nothing;
  get diagnostics v_suppressed = row_count;
  select count(*) into v_batch from public.fn_supplier_invite_candidates(10, null::text[]) c;
  if v_batch = 0 then
    insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
    values (b.id, 'restart_refused', 'ceo', 'Restart refused: no checked lead in an open mailbox class to send to', j);
    return jsonb_build_object('ok', false, 'reason', 'no checked lead in an open mailbox class to send to', 'suppressed', v_suppressed);
  end if;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  -- restarted_by_seat: the CEO is a seat; it puts the restart on the same probation and first-day cap (fn_invite_restart_cap)
  update public.invite_brake set resumed_at = now(), restarted_by_seat = true, restarted_by = 'ceo',
         resume_note = left('CEO: ' || btrim(p_reason), 1000) where id = b.id;
  update public.it_watch_finding set status = 'resolved', resolved_at = now()
   where detector_key = 'deliverability:supplier_invite' and status = 'open';
  update public.ceo_task set state = 'done', closed_at = now(), evidence = left('Restarted by the CEO seat: ' || btrim(p_reason), 4000)
   where state in ('open', 'working', 'blocked') and title = 'Supplier invitations stopped twice on bounces in 30 days';
  insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
  values (b.id, 'restart', 'ceo', btrim(p_reason), jsonb_build_object('judgement', j, 'used_before', v_used, 'limit', v_limit, 'suppressed', v_suppressed, 'first_batch', v_batch));
  insert into public.agent_runs(agent, status, counts, note, finished_at)
  values ('ceo', 'ok', jsonb_build_object('action', 'invite_restart', 'brake', b.id, 'batch', v_batch, 'suppressed', v_suppressed, 'used', v_used + 1, 'limit', v_limit),
          left('The CEO restarted the supplier invitations: ' || btrim(p_reason), 500), now());
  return jsonb_build_object('ok', true, 'brake', b.id, 'first_batch', v_batch, 'suppressed', v_suppressed, 'used', v_used + 1, 'limit', v_limit);
end $fn$;
revoke execute on function public.fn_ceo_restarts_invites(text) from public, anon, authenticated;
grant execute on function public.fn_ceo_restarts_invites(text) to service_role;

-- The CEO seat's own review of a brake the seat may not lift (hourly duty). Code decides from the judgement; the reason is
-- the evidence, written out.
create or replace function public.fn_ceo_reviews_the_invite_brake()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare b public.invite_brake; j_now jsonb; j_then jsonb; v_reason text; v_out jsonb; v_seg jsonb;
begin
  select * into b from public.invite_brake where resumed_at is null order by id desc limit 1;
  if not found then return jsonb_build_object('open_brake', false); end if;
  -- the seat's own restart comes first: the CEO decides only what the sales engineer may not (a second breach)
  if b.ceo_task_opened_at is null then return jsonb_build_object('open_brake', true, 'owner', 'sales_engineer', 'brake', b.id); end if;
  j_now := public.fn_invite_bounce_judgement(now());
  j_then := public.fn_invite_bounce_judgement(b.fired_at);
  v_seg := j_now->'sent_segment_all';
  if coalesce((j_now->'all'->>'complaint')::int, 0) > 0 then
    v_reason := null;   -- never over a complaint; recorded below as a hold
  elsif not coalesce((j_then->>'company_brake')::boolean, false) and not coalesce((j_now->>'company_brake')::boolean, false) then
    v_reason := format('Re-judged by bounce kind, provider and sample: at the brake (%s) the mailboxes the company sends to read %s hard of %s sent, '
      || '95%% lower bound %s%%, under the %s%% limit; today %s hard of %s (lower bound %s%%), %s policy, %s soft, 0 complaints. The old 3-day rule braked on "%s". '
      || 'Bounced addresses suppressed; restart on probation at 10 invitations.',
      to_char(b.fired_at at time zone 'UTC', 'DD Mon HH24:MI') || 'Z', j_then->'sent_segment_all'->>'hard', j_then->'sent_segment_all'->>'sent',
      round(coalesce((j_then->'sent_segment_all'->>'hard_lb')::numeric, 0) * 100, 1), round(coalesce((j_now->'limits'->>'hard_limit')::numeric, 0.03) * 100, 1),
      v_seg->>'hard', v_seg->>'sent', round(coalesce((v_seg->>'hard_lb')::numeric, 0) * 100, 1), v_seg->>'policy', v_seg->>'soft', b.why);
  elsif now() >= b.fired_at + interval '7 days' and not coalesce((j_now->>'company_brake')::boolean, false) then
    v_reason := format('Seven days of rest since the brake of %s, no complaint, the judgement of today does not brake (%s hard of %s, lower bound %s%%); '
      || 'bounced addresses suppressed; restart on probation at 10 invitations.',
      to_char(b.fired_at at time zone 'UTC', 'DD Mon') , v_seg->>'hard', v_seg->>'sent', round(coalesce((v_seg->>'hard_lb')::numeric, 0) * 100, 1));
  end if;
  if v_reason is not null then
    v_out := public.fn_ceo_restarts_invites(v_reason);
    return jsonb_build_object('open_brake', true, 'decided', 'restart', 'result', v_out, 'reason', v_reason);
  end if;
  if not exists (select 1 from public.invite_brake_decision d where d.brake_id = b.id and d.actor = 'ceo' and d.decision = 'hold'
                  and (d.decided_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date) then
    insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
    values (b.id, 'hold', 'ceo', case when coalesce((j_now->'all'->>'complaint')::int, 0) > 0
              then 'Held: a person complained in the judgement window; the CEO never restarts over a complaint.'
              else 'Held: the judgement still brakes (' || coalesce(j_now->>'why', j_then->>'why', 'see evidence') || '); the CEO restarts after 7 days of rest or when it clears.' end,
            jsonb_build_object('now', j_now, 'at_brake', j_then));
  end if;
  return jsonb_build_object('open_brake', true, 'decided', 'hold', 'why', coalesce(j_now->>'why', j_then->>'why'));
end $fn$;
revoke execute on function public.fn_ceo_reviews_the_invite_brake() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.invite_brake_review', 'ceo', interval '1 hour', 'fn_ceo_reviews_the_invite_brake',
   'The CEO decides a supplier-invitation brake the sales engineer may not lift (a second stop inside 30 days): restarts when the bounce judgement (kind, provider, Wilson lower bound) would not brake, or after 7 days of rest with no complaint, within ceo_invite_restarts_per_30d; otherwise records why it holds. Rulings 1696/1705.',
   'scripts/sql/the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('growth_limit_change', true, 'ceo', 'The CEO''s growth limits as an append-only history (ruling 1696).', 'ceo'),
  ('invite_brake_decision', true, 'sales_engineer', 'Every brake, held class, restart and hold of the supplier invitations, with its reason and evidence (rulings 1696/1705).', 'sales_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;
