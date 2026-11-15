-- THE INVITATION RAMPS ON MEASURED HEALTH, AND TESTS ITS COPY. Seat: sales_engineer (the ramp, the batch, the nudges) +
-- marketing (the copy test and its readout). 15 Nov 2026. Founder rulings 1696/1701/1705/1706: enough registered suppliers
-- first; seats act on KPIs that drive action.
--
-- WHAT WAS THERE (READ from origin/main 06881a2d6; SELECT 15 Nov 2026):
--   * app_secrets.invite_daily_cap = 3. fn_invite_ramp grows only when 48 h carry backoff_min_sends (20) sends: at 3 a day two
--     days carry 6, so the ramp answered "too few to judge" forever. The cap could only fall.
--   * One invitation text (send_outbox/m365_lane.ts variant A, founder: "approved. dont ask me", 27 Oct). Variants B and C were
--     written that day (docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md) and never sent. Nothing measured
--     which wording gets a reply. 129 real invitations, 1 click, 0 registrations from invitations.
--   * The nudges and the batch read the old 3-day brake, so a nudge would have been held on 2 bounces of 32 too.
-- WHAT THIS DOES:
--   1. fn_invite_ramp: health is the bounce judgement over 14 days (fn_invite_bounce_judgement, the file before this one).
--      Step up once per send day, +50% and at least +2 (3 -> 5 -> 8 -> 12 -> 18 -> 27 -> 41 -> 50 = the founder cap), only when
--      the last send day used 80% of the cap AND the 14-day hard bounces are at most 3% of sends (or a single one), at most one
--      policy refusal, no throttling soft bounces, no complaint. Back off by half when the 95% lower bound of the hard-bounce
--      rate passes 2% (under the brake's 3%) or on any complaint. The complaint pause (Gmail/Yahoo 0.3%) is unchanged.
--      Thresholds are invite_warmup keys (grow_max_hard_rate, backoff_hard_lb, min_step, new_class_cap), added below.
--   2. enqueue_supplier_invites: the brake is fn_invite_judge_and_brake; a provider class the judgement holds is left out; a
--      class not yet sent to (fewer than 20 sends in the window) gets at most new_class_cap (3) a day while the warm class
--      takes the rest; Microsoft and Yahoo/AOL stay out (fn_invite_placement_open_providers, founder instruction 1537).
--   3. THE COPY TEST. public.invite_variant holds the variants in the test ('a' the founder-approved control, 'b' "we set up
--      your page", 'c' "two sentences"; their words live in send_outbox/m365_lane.ts INVITE_VARIANTS, held to the same copy
--      rules); fn_invite_variant_for_lead fixes each lead's variant once, deterministically (hashtext of the lead id over the
--      active variants; the winner for everyone once there is one); enqueue writes it on the row's kind ('invite_variant:b')
--      and public.invite_variant_assignment; the nudge carries the same variant. fn_invite_copy_readout measures, per variant,
--      sends, replies, clicks and registrations; a lead counts once as "engaged" (a reply, a click or a registration: the copy
--      carries no link, so a reply is the action it asks for). fn_marketing_decides_the_invite_copy (seat duty
--      marketing.invite_copy_readout, daily) promotes the winner automatically when every active variant has min_sends (150)
--      sends, the leader has min_engaged (5) engaged leads and beats each other variant on a one-sided two-proportion z-test at
--      z >= 1.645 (95%); at max_sends (600) per variant with no winner, the control stays and the test ends ("no difference").
--   4. fn_sales_engineer_nudges_invited_suppliers: reads the judgement, skips a held class, and puts the lead's variant on the nudge.
-- prevented by: scripts/checks/the_supplier_funnel_runs_itself.test.mjs, supabase/functions/send_outbox/invite_variants.test.ts,
-- the_invitation_ramps_on_measured_health_and_tests_its_copy_probe.sql (LOCAL).
-- APPLY ORDER: after the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql.
-- DEPLOY ORDER: send_outbox FIRST (it must know 'invite_variant:b' before a row carries it; an older send_outbox writes variant A
-- for every row, which only blurs the test, never breaks a send), then this file.
-- LOCKS: two new tables; three routines replaced in place; app_secrets.invite_warmup gains four keys. No busy-table DDL.
set local lock_timeout = '1500ms';

-- ── 1. THE VARIANTS IN THE TEST ───────────────────────────────────────────────────────────────────────────────────
create table if not exists public.invite_variant (
  variant_key text primary key check (variant_key ~ '^[a-z]$'),
  label text not null,
  status text not null default 'active' check (status in ('active', 'retired', 'winner')),
  is_control boolean not null default false,
  note text not null,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_reason text);
comment on table public.invite_variant is 'The supplier-invitation copy variants under test (marketing). The words live in send_outbox/m365_lane.ts INVITE_VARIANTS; this row says whether the variant is in the test, retired or the winner, and why. the_invitation_ramps_on_measured_health_and_tests_its_copy.sql';
create table if not exists public.invite_variant_assignment (
  lead_id bigint primary key,
  variant_key text not null references public.invite_variant (variant_key),
  notification_id bigint,
  assigned_at timestamptz not null default now());
comment on table public.invite_variant_assignment is 'The copy variant each invited lead received, fixed once at its first invitation (deterministic). the_invitation_ramps_on_measured_health_and_tests_its_copy.sql';
create index if not exists invite_variant_assignment_variant on public.invite_variant_assignment (variant_key);

do $guard$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.invite_variant'::regclass) then
    alter table public.invite_variant enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invite_variant' and policyname = 'invite_variant_service_role_only') then
    create policy invite_variant_service_role_only on public.invite_variant as permissive for all to public using (false) with check (false);
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.invite_variant_assignment'::regclass) then
    alter table public.invite_variant_assignment enable row level security;
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invite_variant_assignment' and policyname = 'invite_variant_assignment_service_role_only') then
    create policy invite_variant_assignment_service_role_only on public.invite_variant_assignment as permissive for all to public using (false) with check (false);
  end if;
end $guard$;
revoke all on public.invite_variant from anon, authenticated;
revoke all on public.invite_variant_assignment from anon, authenticated;

insert into public.invite_variant (variant_key, label, is_control, note) values
  ('a', 'One question, no offer (control)', true, 'The founder-approved text of 27 Oct 2026 (m365InvitationText): who we are, the list we are building, would your company like to receive the requests of its trade.'),
  ('b', 'We set up your page', false, 'Variant B of 27 Oct, without the offer phrase: asks which trades the company covers and offers to set up its company page from the reply.'),
  ('c', 'Two sentences', false, 'Variant C of 27 Oct, made honest (buyers have not started sending requests yet): a direct trade question and why we ask.')
on conflict (variant_key) do nothing;

-- The test's thresholds and the ramp's new keys (data; added once, never overwriting a value a seat has set)
insert into public.app_secrets (key, value) values ('invite_copy_test', jsonb_build_object(
  'min_sends', 150, 'min_engaged', 5, 'z', 1.645, 'max_sends', 600,
  'note', 'A winner needs every active variant at 150 sends, 5 engaged leads in the leader and a one-sided two-proportion z >= 1.645 against each other variant; at 600 each with no winner the control stays. 15 Nov 2026.')::text)
on conflict (key) do nothing;
update public.app_secrets set value = (jsonb_build_object('grow_max_hard_rate', 0.03, 'backoff_hard_lb', 0.02, 'min_step', 2, 'new_class_cap', 3)
                                       || coalesce(nullif(value, '')::jsonb, '{}'::jsonb))::text
 where key = 'invite_warmup' and not (coalesce(nullif(value, '')::jsonb, '{}'::jsonb) ? 'grow_max_hard_rate');

-- ── 2. A LEAD'S VARIANT, FIXED ONCE ───────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_invite_variant_for_lead(p_lead_id bigint)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(
    (select a.variant_key from public.invite_variant_assignment a where a.lead_id = p_lead_id),
    (select v.variant_key from public.invite_variant v where v.status = 'winner' order by v.decided_at desc nulls last limit 1),
    (select k.keys[1 + mod(abs(hashtext('invite_variant:' || p_lead_id::text))::bigint, cardinality(k.keys))::int]
       from (select array_agg(v.variant_key order by v.variant_key) as keys from public.invite_variant v where v.status = 'active') k
      where cardinality(k.keys) > 0),
    'a')
$fn$;
revoke execute on function public.fn_invite_variant_for_lead(bigint) from public, anon, authenticated;

-- ── 3. THE READOUT AND THE DECISION ───────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_invite_copy_readout(p_now timestamptz default now())
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with sent as (
    select a.variant_key, a.lead_id, min(n.sent_at) as sent_at
      from public.invite_variant_assignment a
      join public.notifications n on n.lead_id = a.lead_id and n.type = 'supplier_invite' and n.sent_at is not null and n.sent_at <= p_now
      join public.leads l on l.id = a.lead_id
     where not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email)
     group by a.variant_key, a.lead_id),
  per_lead as (
    select s.variant_key, s.lead_id,
           exists (select 1 from public.inbound_messages m where m.lead_id = s.lead_id and m.created_at > s.sent_at and m.created_at <= p_now
                    and not public.fn_inbound_is_bounce(m.from_email, m.subject, m.raw)) as replied,
           l.invite_clicked_at is not null and l.invite_clicked_at <= p_now as clicked,
           (coalesce(l.claimed, false) or l.registration_submitted_at is not null) as registered
      from sent s join public.leads l on l.id = s.lead_id)
  select jsonb_build_object('at', p_now, 'variants', coalesce(jsonb_agg(jsonb_build_object(
           'variant', v.variant_key, 'status', v.status, 'control', v.is_control, 'label', v.label,
           'sent', coalesce(x.sent, 0), 'replied', coalesce(x.replied, 0), 'clicked', coalesce(x.clicked, 0),
           'registered', coalesce(x.registered, 0), 'engaged', coalesce(x.engaged, 0),
           'engaged_rate', round(coalesce(x.engaged, 0)::numeric / greatest(coalesce(x.sent, 0), 1), 4)) order by v.variant_key), '[]'::jsonb))
    from public.invite_variant v
    left join (select variant_key, count(*)::int sent, (count(*) filter (where replied))::int replied, (count(*) filter (where clicked))::int clicked,
                      (count(*) filter (where registered))::int registered, (count(*) filter (where replied or clicked or registered))::int engaged
                 from per_lead group by variant_key) x on x.variant_key = v.variant_key
$fn$;
revoke execute on function public.fn_invite_copy_readout(timestamptz) from public, anon, authenticated;

create or replace function public.fn_marketing_decides_the_invite_copy(p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_copy_test'), '{}'::jsonb);
  v_min int := coalesce((c->>'min_sends')::int, 150); v_min_e int := coalesce((c->>'min_engaged')::int, 5);
  v_z numeric := coalesce((c->>'z')::numeric, 1.645); v_max int := coalesce((c->>'max_sends')::int, 600);
  r jsonb := public.fn_invite_copy_readout(p_now); v_act jsonb; best jsonb; o jsonb; v_zmin numeric; z numeric; p numeric; se numeric;
  v_reason text;
begin
  if exists (select 1 from public.invite_variant where status = 'winner') then
    return jsonb_build_object('decided', false, 'reason', 'a winner is already promoted', 'readout', r);
  end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_act from jsonb_array_elements(r->'variants') e where e->>'status' = 'active';
  if jsonb_array_length(v_act) < 2 then
    return jsonb_build_object('decided', false, 'reason', 'fewer than two variants in the test', 'readout', r);
  end if;
  if exists (select 1 from jsonb_array_elements(v_act) e where (e->>'sent')::int < v_min) then
    return jsonb_build_object('decided', false, 'reason', 'every variant needs ' || v_min || ' sends first', 'readout', r);
  end if;
  select e into best from jsonb_array_elements(v_act) e order by (e->>'engaged_rate')::numeric desc, (e->>'control')::boolean desc, e->>'variant' limit 1;
  -- the leader against each other variant: one-sided two-proportion z-test, pooled
  for o in select e from jsonb_array_elements(v_act) e where e->>'variant' <> best->>'variant' loop
    p := ((best->>'engaged')::numeric + (o->>'engaged')::numeric) / ((best->>'sent')::numeric + (o->>'sent')::numeric);
    se := sqrt(greatest(p * (1 - p) * (1 / (best->>'sent')::numeric + 1 / (o->>'sent')::numeric), 0));
    z := case when se = 0 then 0 else ((best->>'engaged_rate')::numeric - (o->>'engaged_rate')::numeric) / se end;
    v_zmin := least(coalesce(v_zmin, z), z);
  end loop;
  if (best->>'engaged')::int >= v_min_e and v_zmin >= v_z then
    v_reason := format('Variant %s ("%s") engaged %s of %s (%s%%), ahead of every other variant at z >= %s (weakest z %s). Promoted automatically by fn_marketing_decides_the_invite_copy.',
      best->>'variant', best->>'label', best->>'engaged', best->>'sent', round((best->>'engaged_rate')::numeric * 100, 2), v_z, round(v_zmin, 2));
    update public.invite_variant set status = 'winner', decided_at = now(), decided_reason = v_reason where variant_key = best->>'variant';
    update public.invite_variant set status = 'retired', decided_at = now(), decided_reason = 'Lost to variant ' || (best->>'variant') || ': ' || v_reason
     where status = 'active' and variant_key <> best->>'variant';
  elsif not exists (select 1 from jsonb_array_elements(v_act) e where (e->>'sent')::int < v_max) then
    v_reason := format('No variant beat the others after %s sends each (leader %s at %s%%, weakest z %s): the control stays, the test ends.',
      v_max, best->>'variant', round((best->>'engaged_rate')::numeric * 100, 2), round(coalesce(v_zmin, 0), 2));
    update public.invite_variant set status = 'winner', decided_at = now(), decided_reason = v_reason where is_control;
    update public.invite_variant set status = 'retired', decided_at = now(), decided_reason = v_reason where status = 'active' and not is_control;
  else
    return jsonb_build_object('decided', false, 'reason', 'no significant leader yet', 'leader', best->>'variant', 'weakest_z', round(coalesce(v_zmin, 0), 3), 'readout', r);
  end if;
  insert into public.agent_runs (agent, status, counts, note, finished_at)
  values ('marketing', 'ok', jsonb_build_object('action', 'invite_copy_decided', 'readout', r), left(v_reason, 500), now());
  return jsonb_build_object('decided', true, 'reason', v_reason, 'readout', r);
end $fn$;
revoke execute on function public.fn_marketing_decides_the_invite_copy(timestamptz) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('marketing.invite_copy_readout', 'marketing', interval '1 day', 'fn_marketing_decides_the_invite_copy',
   'The supplier-invitation copy test: per variant sends, replies, clicks, registrations; promotes the winner automatically at 150 sends per variant and a one-sided z >= 1.645, or keeps the control at 600 with no winner. Rulings 1705/1706.',
   'scripts/sql/the_invitation_ramps_on_measured_health_and_tests_its_copy.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('invite_variant', true, 'marketing', 'The supplier-invitation copy variants under test and the decision on each.', 'marketing'),
  ('invite_variant_assignment', true, 'marketing', 'Which copy variant each invited lead received (the denominator of the copy test).', 'marketing')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;

-- ── 4. THE RAMP, THE BATCH AND THE NUDGES (the live definitions of 15 Nov 2026, changed only where marked 15 Nov) ───
create or replace function public.fn_invite_ramp()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  -- founder ruling 1231: the dated founder cap is an upper bound only. It lowers the configured ceiling and the
  -- restart base; it never raises a cap set lower, and the back-off below can still halve.
  v_base int     := least(coalesce((c->>'base_cap')::int, 30), public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
  v_ceiling int  := least(coalesce((c->>'ceiling_cap')::int, 200), public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
  v_growth numeric := coalesce((c->>'growth_factor')::numeric, 1.5);
  v_used_pct numeric := coalesce((c->>'grow_if_used_pct')::numeric, 0.8);
  v_ok_b numeric := coalesce((c->>'grow_max_bounce_rate')::numeric, 0.02);
  v_ok_c numeric := coalesce((c->>'grow_max_complaint_rate')::numeric, 0.001);
  v_back_b numeric := coalesce((c->>'backoff_bounce_rate')::numeric, 0.035);
  v_back_n int   := coalesce((c->>'backoff_min_sends')::int, 20);
  v_pause_c numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_pause_n int  := coalesce((c->>'pause_min_complaints')::int, 2);
  -- 15 Nov 2026 (sales_engineer): health is the bounce judgement over 14 days (fn_invite_bounce_judgement), not a 48 h count
  -- that a 3-a-day cap could never fill (backoff_min_sends 20 > 2 days x 3: the cap was stuck at 3 for good).
  v_grow_hard numeric := coalesce((c->>'grow_max_hard_rate')::numeric, 0.03);
  v_back_lb numeric := coalesce((c->>'backoff_hard_lb')::numeric, 0.02);
  v_min_step int := coalesce((c->>'min_step')::int, 2);
  v_j jsonb; v_seg jsonb; v_wsent int; v_whard int; v_wpol int;
  v_cur int; v_new int; v_note text; v_status text := 'ok';
  v_sent_total int; v_last_sent timestamptz; v_last_day date; v_last_day_sent int;
  v_s48 int; v_b48 int; v_c48 int; v_br numeric; v_cr numeric;
  v_restart boolean := false; v_prev_restart boolean; v_grew_since boolean; v_uncontacted int;
  -- THE LANE'S OWN HISTORY (24 Sep 2026): '-infinity' while invite_lane_enabled is off (every scope below is
  -- then a no-op); the activation stamp while it is on, so the new subdomain restarts at day 1.
  v_since timestamptz := public.fn_invite_lane_since();
begin
  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key = 'invite_daily_cap'), v_base);
  -- ruling 1231 review: the restart base (a new lane's day 1) is never above the cap already set, so a restart
  -- lowers to base and never raises a cap set lower.
  v_base := least(v_base, v_cur);

  -- PAUSED IS A REPORTABLE STATE: a paused campaign files a row and leaves the cap alone. The daily tick
  -- calls this only on open days, so the previous body's daily "campaign paused" warning (which, called
  -- every day of a founder's deliberate hold, would page him daily) is not carried over.
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    select count(*) into v_uncontacted from leads where invited_at is null and coalesce(btrim(email),'') <> '';
    insert into agent_runs(agent, status, counts, note, finished_at)
    values ('invite_ramp', 'ok', jsonb_build_object('paused', true, 'cap', v_cur, 'uncontacted_with_email', v_uncontacted),
            'PAUSED: invite_enabled is false; cap left at ' || v_cur || '.', now());
    return v_cur;
  end if;

  -- ISSUED MEANS SENT, AND WHEN IT WAS SENT (3 Nov 2026): the same rows fn_invite_send_health reads, from the lane's stamp.
  select count(distinct n.lead_id), max(n.sent_at), max((n.sent_at at time zone 'Asia/Dubai')::date)
    into v_sent_total, v_last_sent, v_last_day
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at >= v_since
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email);
  -- THE 48 h HEALTH READ IS NOT LANE-SCOPED (review of #963): complaints and bounces reflect the list and the
  -- copy, not the domain, so switching the lane on must never hide yesterday's complaints from the pause.
  select h.sent, h.bounced, h.complained into v_s48, v_b48, v_c48
    from public.fn_invite_send_health(now() - interval '48 hours') h;
  v_br := v_b48::numeric / greatest(v_s48, 1);
  v_cr := v_c48::numeric / greatest(v_s48, 1);
  v_j := public.fn_invite_bounce_judgement(now());
  v_seg := v_j->'sent_segment_all';
  v_wsent := coalesce((v_seg->>'sent')::int, 0); v_whard := coalesce((v_seg->>'hard')::int, 0); v_wpol := coalesce((v_seg->>'policy')::int, 0);

  if v_c48 >= v_pause_n and v_cr >= v_pause_c then
    -- SPAM COMPLAINTS STOP THE CAMPAIGN. Gmail and Yahoo reject bulk senders above 0.3%; two people
    -- pressing "spam" inside 48 hours is not noise at this volume.
    update app_secrets set value = 'false' where key = 'invite_enabled';
    v_new := v_base; v_status := 'error';
    v_note := 'PAUSED ON COMPLAINTS: ' || v_c48 || ' spam complaint(s) on ' || v_s48 || ' invitation(s) in 48 h ('
              || round(v_cr * 100, 2) || '% >= ' || round(v_pause_c * 100, 2) || '%). invite_enabled set to false; cap reset to base '
              || v_base || '.';
    if not exists (select 1 from founder_alerts where event = 'invite_paused_complaints' and created_at > now() - interval '24 hours') then
      insert into founder_alerts(level, event, detail, channel)
      values ('crit', 'invite_paused_complaints', 'Supplier invites AUTO-PAUSED: ' || v_note || ' Read the complaints before resuming.', 'system');
    end if;
  elsif v_last_sent is null or v_last_sent < now() - interval '3 days' then
    -- A RESTART, NOT A STALL. After days of silence the domain is cold again, so it starts at the base.
    -- It is a stall only if the previous run was ALSO a restart and still nothing has been issued.
    -- A lane that has just been switched on has issued nothing yet, so it lands here: day 1 of its own ramp.
    v_restart := true; v_new := v_base;
    select coalesce((a.counts->>'restart')::boolean, false) into v_prev_restart
      from agent_runs a where a.agent = 'invite_ramp' and coalesce((a.counts->>'paused')::boolean, false) = false
     order by a.id desc limit 1;
    v_note := 'restart: nothing issued since ' || coalesce(to_char(v_last_sent at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z', 'ever')
              || case when v_since > '-infinity'::timestamptz
                      then ' on the invitation lane (switched on ' || to_char(v_since at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z)' else '' end
              || '; cap set to the base ' || v_base || '.';
    if coalesce(v_prev_restart, false) then
      v_status := 'error';
      v_note := 'STALLED: the previous run was already a restart and nothing has been issued since. ' || v_note;
      if not exists (select 1 from founder_alerts where event = 'invite_sender_stalled' and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level, event, detail, channel)
        values ('crit', 'invite_sender_stalled', 'Supplier invites: ' || v_note || ' invite_enabled is true, so the enqueuer or the outbox is failing.', 'system');
      end if;
    end if;
  elsif (v_whard >= 2 and coalesce((v_seg->>'hard_lb')::numeric, 0) > v_back_lb) or coalesce((v_seg->>'complaint')::int, 0) >= 1 or v_c48 >= 1 then
    -- BACK OFF on evidence: the 95% lower bound of the hard-bounce rate over 14 days above backoff_hard_lb (2%, under the
    -- brake's 3%), or any complaint
    v_new := greatest(1, floor(v_cur * 0.5)::int);   -- ruling 1231 review: a back-off must reduce, so no floor at base
    v_note := 'back off: 14-day hard bounce ' || v_whard || '/' || v_wsent || ' (95% lower bound ' || round(coalesce((v_seg->>'hard_lb')::numeric, 0) * 100, 1)
              || '% > ' || round(v_back_lb * 100, 1) || '%), complaints ' || coalesce(v_seg->>'complaint', '0') || '; cap ' || v_cur || '->' || v_new || '.';
    if v_new = v_cur then
      v_status := 'error';
      if not exists (select 1 from founder_alerts where event = 'invite_throttle_exhausted' and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level, event, detail, channel)
        values ('crit', 'invite_throttle_exhausted', 'Supplier invites: ' || v_note || ' The cap is already at its base; the hard brake pauses at '
                || round(coalesce((select nullif(value,'')::numeric from app_secrets where key = 'invite_max_bounce_rate'), 0.05) * 100, 1) || '%.', 'system');
      end if;
    end if;
  elsif (v_whard > 1 and v_whard::numeric / greatest(v_wsent, 1) > v_grow_hard) or v_wpol > 1
        or coalesce((v_seg->>'soft_hold')::boolean, false) or v_cr >= v_ok_c then
    -- STEP UP ONLY WHILE THE RATES STAY UNDER THEIR THRESHOLDS: hard bounces at most 3% of the 14-day sends (or a single one),
    -- at most one policy refusal, soft bounces not throttling us, no complaint
    v_new := v_cur;
    v_note := 'hold: 14-day hard bounce ' || v_whard || '/' || v_wsent || ', policy ' || v_wpol || ', soft hold ' || coalesce(v_seg->>'soft_hold', 'false')
              || ' — growth needs hard <= ' || round(v_grow_hard * 100, 1) || '% (or one), policy <= 1 and no complaint.';
  elsif v_wsent = 0 then
    -- NO GROWTH ON AN EMPTY WINDOW (3 Nov 2026): "0 bounces of 0" is not health.
    v_new := v_cur;
    v_note := 'hold: nothing sent in the 14-day window, nothing to judge.';
  else
    -- GROW ON VOLUME ISSUED, ONCE PER SEND DAY. Weekends and holidays run no batch, so a calendar-based
    -- ladder would ratchet on days the domain sent nothing.
    select count(*) into v_last_day_sent
      from public.notifications n join public.leads l on l.id = n.lead_id
     where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at >= v_since
       and (n.sent_at at time zone 'Asia/Dubai')::date = v_last_day
       and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email);
    select exists (select 1 from agent_runs a where a.agent = 'invite_ramp' and a.finished_at > v_last_sent
                     and (a.counts->>'new_cap')::int > (a.counts->>'old_cap')::int) into v_grew_since;
    if v_grew_since then
      v_new := v_cur; v_note := 'hold: already grew once since the last send day.';
    elsif v_last_day_sent < ceil(v_cur * v_used_pct) then
      v_new := v_cur; v_note := 'hold: the last send day (' || v_last_day || ') issued ' || v_last_day_sent || ' of a cap of ' || v_cur
                                || '; growth needs ' || round(v_used_pct * 100) || '%.';
    else
      -- a step of +50%, at least +2 (3 -> 5 -> 8 -> 12 -> 18 -> 27 -> 41 -> 50), never above the ceiling
      v_new := least(v_ceiling, greatest(v_cur + v_min_step, ceil(v_cur * v_growth)::int));
      v_note := 'healthy: 14-day hard bounce ' || v_whard || '/' || v_wsent || ', policy ' || v_wpol || ', complaints 0'
                || '; last send day issued ' || v_last_day_sent || '; cap ' || v_cur || '->' || v_new || '.';
    end if;
  end if;

  v_new := greatest(1, least(v_new, v_ceiling));     -- ruling 1231: the schedule only ever lowers the cap
  if v_new <> v_cur then
    update app_secrets set value = v_new::text where key = 'invite_daily_cap';
  end if;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values ('invite_ramp', v_status,
          jsonb_build_object('old_cap', v_cur, 'new_cap', v_new, 'sent_total', v_sent_total, 'restart', v_restart,
                             'sent_48h', v_s48, 'bounced_48h', v_b48, 'complained_48h', v_c48,
                             'bounce_pct_48h', round(v_br * 100, 2), 'complaint_pct_48h', round(v_cr * 100, 3),
                             'window_sent', v_wsent, 'window_hard', v_whard, 'window_policy', v_wpol, 'window_hard_lb', v_seg->'hard_lb')
          || case when v_since > '-infinity'::timestamptz then jsonb_build_object('lane_since', v_since) else '{}'::jsonb end,
          v_note, now());
  if v_new < v_cur and not v_restart then
    insert into founder_alerts(level, event, detail, channel)
    values ('warn', 'invite_cap_throttled', 'Supplier-invite cap reduced ' || v_cur || '->' || v_new || ' — ' || v_note, 'system');
  end if;
  return v_new;
end
$function$

;
revoke execute on function public.fn_invite_ramp() from public, anon, authenticated;

create or replace function public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
  v_cfg jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_win_start timestamptz; v_win_end timestamptz;
  v_gate text; v_open text[];
  v_judge jsonb; v_held text[]; v_warm text[]; v_cold text[]; v_cold_cap int; v_rest int; v_pick jsonb;
begin
  select c.event_name, c.action, c.ends_on into v_hol_name, v_hol_action, v_hol_end
    from public.company_calendar c
   where c.kind = 'public_holiday'
     and v_today between c.starts_on and coalesce(c.ends_on, c.starts_on)
   order by c.starts_on limit 1;
  if v_hol_name is not null then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'calendar_paused', true, 'resumes_on', coalesce(v_hol_end, v_today) + 1),
            'Invites held: company_calendar has "' || v_hol_name || '" covering today. Its recorded action: '
            || coalesce(v_hol_action, '(none recorded)'), now(), now());
    return 0;
  end if;

  -- THE UAE WEEKEND IS SATURDAY AND SUNDAY. A cold invitation queued then waits under Monday's pile.
  -- Self-clearing like the holiday hold: nothing is switched off, Monday simply runs.
  if extract(isodow from (now() at time zone 'Asia/Dubai')) in (6, 7) then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'weekend_hold', true),
            'Invites held: it is the UAE weekend in Dubai; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_go  := (coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true')
           and public.fn_supplier_outreach_golive();
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  -- founder ruling 1231: never more than the dated founder cap, whatever invite_daily_cap holds.
  v_cap := least(v_cap, public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
  v_cap := public.fn_invite_restart_cap(v_cap);   -- a small first batch after a restart
  select count(*) into v_pool from leads l where public.fn_supplier_invite_eligible(l);
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' eligible never-invited lead(s), cap ' || v_cap
          || case when v_go then '; sending open'
                  when not public.fn_supplier_outreach_golive() then '; HELD — real invitations wait for the founder''s go (app_secrets.supplier_outreach_golive is false)'
                  else '; HELD — real invitations wait for the founder''s go (app_secrets.invite_enabled)' end)
    on conflict (day) do update
      set planned = excluded.planned, status = excluded.status, note = excluded.note;

  if not v_go then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'planned', greatest(v_planned, 0), 'pool', v_pool, 'cap', v_cap, 'held', true),
            'Invites planned and HELD: ' || greatest(v_planned, 0) || ' of a pool of ' || v_pool
            || ' would be queued at cap ' || v_cap || '; '
            || case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive' else 'invite_enabled' end
            || ' is false, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_planned <= 0 then return 0; end if;

  -- PLACEMENT GATE, PER MAILBOX CLASS (27 Oct 2026, it_engineer; was the morning seed, retired by #1696). Recipients
  -- go only in a class whose latest GlockApps verdict meets public.invite_placement_bar (fn_invite_placement_open_providers);
  -- the others are skipped, not failed. No class open, no verdict, or a stale one: the whole batch is held.
  v_open := public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date);
  v_gate := public.fn_invite_placement_class_verdicts(now()) ->> 'strict';
  if cardinality(v_open) = 0 then
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; held: inbox placement ' || v_gate where day = v_today;
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'placement_gate', v_gate, 'held', true),
            'Invites held: the GlockApps inbox placement verdict answered ' || v_gate || ' for every mailbox class, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_gate <> 'pass' then
    update invite_schedule set note = coalesce(note,'') || '; placement ' || v_gate || ': invited only ' || array_to_string(v_open, ', ') where day = v_today;
  end if;

  -- THE SENDING WINDOW (22 Sep 2026). Invitations leave between the later of now and the window's start
  -- and the end of the Dubai working day, evenly spaced. Past the window nothing is queued: a cold
  -- invitation at night lands under the morning's pile, and tomorrow's batch runs as normal.
  v_win_start := greatest(now(), ((now() at time zone 'Asia/Dubai')::date
                   + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9))) at time zone 'Asia/Dubai');
  v_win_end := ((now() at time zone 'Asia/Dubai')::date + make_interval(hours => coalesce((v_cfg->>'window_end_hour')::int, 17)))
               at time zone 'Asia/Dubai';
  if v_win_end < v_win_start + interval '30 minutes' then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'outside_window', true),
            'Invites held: the Dubai sending window closes at ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI')
            || '; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  -- THE BOUNCE JUDGEMENT (15 Nov 2026, sales_engineer; the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_
  -- the_ceo_restarts_within_a_limit.sql). Was: one 3-day rate over every population, which stopped the company on 2 bounces
  -- of 32. Now: each bounce by its kind, per mailbox provider class and list segment, the Wilson 95% lower bound over 14 days
  -- and over today. A complaint or a hard-bounce breach in the segment being sent stops the company (fn_invite_judge_and_brake
  -- writes the brake and its reason); a breach confined to one provider class holds that class only.
  v_judge := public.fn_invite_judge_and_brake('enqueue_supplier_invites');
  if coalesce((v_judge->>'braked')::boolean, false) then
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || (v_judge->>'why') where day = v_today;
    return 0;
  end if;
  v_held := coalesce((select array_agg(x) from jsonb_array_elements_text(v_judge->'held_classes') x), '{}'::text[]);
  v_open := array(select p from unnest(v_open) p where not (p = any (v_held)));
  if cardinality(v_open) = 0 then
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; held: every open mailbox class breaches a bounce limit (' || array_to_string(v_held, ', ') || ')' where day = v_today;
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'held_classes', to_jsonb(v_held), 'held', true),
            'Invites held: every open mailbox class breaches a bounce limit on the judgement (' || array_to_string(v_held, ', ') || ').', now(), now());
    return 0;
  end if;
  -- A CLASS THE COMPANY HAS NOT YET SENT TO IN THE WINDOW starts at the ramp's base (invite_warmup.new_class_cap, 3): a newly
  -- opened provider never takes the warm class's whole day. "Warm" = 20 sends or more in the judgement window.
  v_cold_cap := coalesce((v_cfg->>'new_class_cap')::int, 3);
  v_warm := array(select p from unnest(v_open) p
                   where coalesce((select sum((c.value->>'sent')::int) from jsonb_each(v_judge->'judgement'->'cells') c where c.value->>'class' = p), 0) >= 20);
  v_cold := array(select p from unnest(v_open) p where not (p = any (v_warm)));

  -- test-path rows (fixture addresses) are not invitations and must not spend the day's cap:
  -- measured in the rolled-back rehearsal, two test sends plus one real row cut a batch of 5 to 2.
  -- ONE daily cap for invitations and their nudges (review of #1007, 29 Sep 2026): a nudge queued today spends it too,
  -- as fn_sales_engineer_nudges_invited_suppliers already counts the invitations queued today against the same cap.
  select count(*) into v_used from notifications where type in ('supplier_invite', 'supplier_invite_nudge') and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  -- the warm classes first, then at most new_class_cap from the classes not yet warmed up (both through the verdict gate);
  -- each candidate call is made only for a non-empty class list (a null list would mean every class)
  v_pick := '[]'::jsonb;
  if cardinality(v_warm) > 0 then
    select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) into v_pick from public.fn_supplier_invite_candidates(v_remaining, v_warm) c;
  end if;
  v_rest := v_remaining - jsonb_array_length(v_pick);
  if v_rest > 0 and cardinality(v_cold) > 0 then
    v_pick := v_pick || (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) from public.fn_supplier_invite_candidates(least(v_rest, v_cold_cap), v_cold) c);
  end if;
  -- THE COPY TEST (15 Nov 2026, marketing): each lead's variant is fixed once (fn_invite_variant_for_lead, deterministic) and
  -- carried on the row's kind ('invite_variant:<key>'); send_outbox's campaignMail writes that variant's text.
  with c as (
    select c.*, public.fn_invite_variant_for_lead(c.lead_id) as variant, row_number() over () as rn, count(*) over () as n
      from (select distinct on (x.lead_id) x.* from jsonb_to_recordset(v_pick)
              as x(lead_id bigint, to_email text, company_name text, lang text, subject text, body text) order by x.lead_id) c
  ), ins as (
    insert into notifications(type, to_email, to_role, lead_id, subject, body, lang, status, created_at, not_before, kind)
    select 'supplier_invite', c.to_email, 'supplier', c.lead_id, c.subject, c.body, c.lang, 'queued', now(),
           v_win_start + (c.rn - 1) * ((v_win_end - v_win_start) / greatest(c.n, 1)), 'invite_variant:' || c.variant
      from c
    on conflict (lower(btrim(to_email))) where type = 'supplier_invite' do nothing
    returning id, lead_id, kind
  ), asg as (
    insert into public.invite_variant_assignment (lead_id, variant_key, notification_id)
    select ins.lead_id, substr(ins.kind, length('invite_variant:') + 1), ins.id from ins
    on conflict (lead_id) do nothing
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and id in (select lead_id from ins);
  get diagnostics v_count = row_count;
  -- invite_schedule.sent is written when the outbox sends (trg_invite_schedule_counts_a_real_send), never here at queue time
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false,
                             'window_ends', v_win_end, 'placement_gate', v_gate, 'open_providers', to_jsonb(v_open),
                             'held_classes', to_jsonb(v_held), 'cold_classes', to_jsonb(v_cold)),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap
          || '), spread until ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI') || ' Dubai.', now(), now());
  return v_count;
end;
$function$

;
revoke execute on function public.enqueue_supplier_invites(integer) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_nudges_invited_suppliers(p_now timestamp with time zone DEFAULT now(), p_cap integer DEFAULT NULL::integer, p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_dxb timestamp := p_now at time zone 'Asia/Dubai';
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_hol text; v_cap int; v_used int; v_left int; v_queued int := 0; v_due int := 0; r record; v_link text;
  v_res jsonb; v_not_before timestamptz;
  v_gate text; v_open text[]; v_skipped int := 0; v_inv_recent int; v_bounced_recent int; v_max_rate numeric; v_judge jsonb;
begin
  select c.event_name into v_hol from public.company_calendar c
   where c.kind = 'public_holiday' and v_dxb::date between c.starts_on and coalesce(c.ends_on, c.starts_on) limit 1;
  if v_hol is not null then return jsonb_build_object('held', 'holiday: ' || v_hol, 'queued', 0); end if;
  if extract(isodow from v_dxb) in (6, 7) then return jsonb_build_object('held', 'UAE weekend', 'queued', 0); end if;
  -- THE SENDING WINDOW (review of #1007, 29 Sep 2026). The duty that calls this runs at 00:01 UTC (04:01 Dubai),
  -- before the window opens, so a start-hour HOLD would block every nudge. Instead a nudge queued before the
  -- window leaves no earlier than window_start_hour (default 9) Dubai the same day: not_before, exactly as
  -- enqueue_supplier_invites spreads its batch from the window's start. After window_end_hour it is held.
  v_not_before := greatest(p_now, (v_dxb::date + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9)))
                                  at time zone 'Asia/Dubai');
  if extract(hour from v_dxb) >= coalesce((v_cfg->>'window_end_hour')::int, 17) then
    return jsonb_build_object('held', 'after the Dubai sending window', 'queued', 0); end if;
  -- THE GO SWITCH governs every mode, the probe's fixture mode included (30 Sep 2026).
  if not (coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive()) then
    return jsonb_build_object('held', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)', 'queued', 0,
                              'due', (select count(*) from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures)));
  end if;
  -- THE BATCH'S BRAKES, for real mail (a fixture address never leaves: send_outbox suppresses @example.invalid).
  if not p_include_fixtures then
    -- per mailbox class (27 Oct 2026): held only when no class passes; a failing class is skipped in the loop
    v_open := public.fn_invite_placement_open_providers(v_dxb::date, p_now);
    v_gate := public.fn_invite_placement_class_verdicts(p_now) ->> 'strict';
    if cardinality(v_open) = 0 then
      return jsonb_build_object('held', 'inbox placement ' || v_gate, 'queued', 0); end if;
    -- THE BOUNCE JUDGEMENT, read only (15 Nov 2026: the batch owns the brake, fn_invite_judge_and_brake): held when it would
    -- stop the company; a provider class it holds is skipped like a class the placement gate refused
    v_judge := public.fn_invite_bounce_judgement(p_now);
    if coalesce((v_judge->>'company_brake')::boolean, false) then
      return jsonb_build_object('held', 'bounce judgement: ' || coalesce(v_judge->>'why', 'brake'), 'queued', 0); end if;
    v_open := array(select p from unnest(v_open) p where not (p = any (coalesce((select array_agg(x) from jsonb_array_elements_text(v_judge->'held_classes') x), '{}'::text[]))));
    if cardinality(v_open) = 0 then
      return jsonb_build_object('held', 'every open mailbox class breaches a bounce limit', 'queued', 0); end if;
  end if;

  -- ONE daily cap for the domain: invitations and nudges queued this day, same class (real or fixture). The day is
  -- the UTC date, exactly as enqueue_supplier_invites counts it (review of #1007): on a Dubai-date basis the two
  -- would disagree between 00:00 and 04:00 Dubai and could each spend a full cap.
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  v_cap := public.fn_invite_restart_cap(least(v_cap, coalesce(p_cap, v_cap)));
  select count(*) into v_used from public.notifications n
   where n.type in ('supplier_invite', 'supplier_invite_nudge')
     and (n.created_at at time zone 'UTC')::date = (p_now at time zone 'UTC')::date
     and public.fn_is_demo_email(n.to_email) = p_include_fixtures;
  v_left := greatest(0, v_cap - v_used);

  for r in select d.*, l.company_name, l.claim_token from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures) d
             join public.leads l on l.id = d.lead_id loop
    v_due := v_due + 1;
    -- a recipient whose mailbox class did not pass the GlockApps verdict is skipped, not failed (27 Oct 2026)
    if not p_include_fixtures and public.fn_mail_provider_of_email(r.to_email) <> all(v_open) then
      v_skipped := v_skipped + 1; continue; end if;
    continue when v_queued >= v_left;
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English): one copy, and the link is
    -- the invitation's own: fn_supplier_invite_link (#1051) - /en/portal with the claim token and the invitation ref.
    -- A lead with no claim token (the function then answers null) gets the plain English portal.
    v_link := coalesce(public.fn_supplier_invite_link(
                         (select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), r.claim_token, r.lead_id),
                       coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
                       || '/en/portal');
    v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_invite_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en', 'dedupe_key', r.dedupe_key,
      'subject', case when r.step = 3 then 'A last reminder: ' else '' end || 'your invitation to join QuotesDone as a supplier',
      -- #1070's greeting guard: an Arabic-script company name is not written into an English letter
      'body', coalesce('Dear ' || nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), '') || ',',
                       'Dear Sir or Madam,') || E'\n\n'
          || 'A reminder of our invitation to register your company as a supplier on QuotesDone. It is free and takes a few minutes.'
          || E'\n\n' || v_link
          || case when r.step = 3 then E'\n\nThis is the last reminder we will send about it.' else '' end
          || E'\n\nIf you would rather not receive these e-mails, reply to this one and we will remove your address.')));
    -- support's handler queues the row without a not_before (it takes only the words and the address), so the
    -- requester sets the window start on the row it was just given back (by id, whatever the outbox's status:
    -- a fixture address is 'suppressed' on insert, a real one 'queued')
    -- ...and the lead's copy-test variant, so the nudge is the same email the invitation was (campaignMail reads kind)
    update public.notifications set not_before = v_not_before,
           kind = 'invite_variant:' || coalesce((select a.variant_key from public.invite_variant_assignment a where a.lead_id = r.lead_id), 'a')
     where id = (v_res->0->>'notification_id')::bigint and type = 'supplier_invite_nudge';
    v_queued := v_queued + 1;
  end loop;
  return jsonb_build_object('held', null, 'due', v_due, 'queued', v_queued, 'cap', v_cap, 'used_before', v_used,
                            'placement_gate', v_gate, 'open_providers', to_jsonb(v_open), 'skipped_provider', v_skipped);
end
$function$

;
revoke execute on function public.fn_sales_engineer_nudges_invited_suppliers(timestamp with time zone, integer, boolean) from public, anon, authenticated;
