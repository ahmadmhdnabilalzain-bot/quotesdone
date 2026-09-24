-- THE INVITATIONS LEAVE ON THEIR OWN SUBDOMAIN, SO A CAMPAIGN CANNOT COST THE SIGN-UP CODES
-- (24 Sep 2026; Assigned: marketing (campaign) + it_engineer (mail path)).
--
-- MEASURED (24 Sep 2026, production, read-only):
--   * app_secrets.email_from_supplier = email_from_info = 'QuotesDone <info@quotesdone.com>'
--     (the_supplier_invitation_is_sent_from_info.sql moved invitations there because supplier@ was junked by
--     Microsoft 365). login_otp sends every sign-up code from email_from_info, and every customer notice and
--     internal report leaves from the same address. So a cold-campaign reputation hit (bounces, spam
--     complaints) lands on the one identity the sign-up codes depend on.
--   * DNS: quotesdone.com (DMARC p=quarantine, rua management@quotesdone.com) and mail.quotesdone.com are
--     Resend sending domains (send.<d> MX feedback-smtp.us-east-1.amazonses.com, TXT v=spf1 include:amazonses.com
--     ~all). mail.quotesdone.com is ALSO the inbound domain whose MX is Resend inbound (suppliers@, docs@,
--     calendar+ replies). hello.quotesdone.com resolves to nothing: it is free.
--   * invite_enabled = false, supplier_outreach_golive = false, invite_daily_cap = 50.
--
-- WHAT THIS CHANGES
--   1. Three campaign rows next to invite_enabled: invite_lane_enabled = 'false' (the flag, OFF),
--      invite_lane_from = 'QuotesDone <invite@hello.quotesdone.com>', invite_lane_since = '' (stamped, never typed).
--      hello.quotesdone.com and not mail.quotesdone.com: Gmail and Microsoft keep domain reputation per
--      (sub)domain, and mail. already carries the inbound mailboxes and whatever else is sent from it. A
--      subdomain that sends nothing but invitations is the only reputation a campaign can burn.
--      send_outbox reads these (send_outbox/invite_lane.ts); OFF = the From it uses today, byte for byte.
--   2. trg_invite_lane_since: the moment invite_lane_enabled turns 'true', invite_lane_since is stamped now().
--      Every activation restamps: a restart only ever costs volume, never reputation.
--   3. fn_invite_lane_since(): the stamp while the lane is ON, '-infinity' while it is OFF.
--   4. fn_invite_ramp: the SAME ramp (no second ramp). Its restart and growth reads (last send, send total, last
--      send day and its volume) are scoped to invited_at >= fn_invite_lane_since() AND an invitation that was
--      actually sent (fn_invite_lane_sent; a held lane invitation has invited_at but never left). With the lane
--      ON, the history info@ built does not count toward the new subdomain: the first run after activation finds
--      no lane send, so the ramp's own restart branch sets the cap to invite_warmup.base_cap (day 1).
--      The 48 h health read behind the complaint PAUSE and the bounce BACK-OFF stays UNSCOPED: complaints reflect
--      the list and the copy, not the domain, and activation must never hide them. OFF: '-infinity' makes every
--      scope a no-op and agent_runs.counts carries no lane key, i.e. today's ramp and today's run log.
--      KNOWN UNDERCOUNT, ACCEPTED: a row queued just before activation and sent after it leaves on the lane but
--      has invited_at < the stamp, so it is not counted. At most one day's batch (the rows queued before the
--      flip); the ramp is conservative for that one day, never generous.
--      Non-destructive: no lead, no invited_at and no ramp history is rewritten; turning the lane off returns
--      the ramp to reading the whole history.
--   5. fn_supplier_campaign_next_list (the 18:00 list): the same scope on its cold-domain check, so the list
--      predicts the day-1 base cap the ramp will set.
--
-- NOT CHANGED: login_otp and every non-invitation email (they never read invite_lane_*; send_outbox applies the
-- lane to supplier_invite and supplier_invite_seed only), the Reply-To (suppliers@mail.quotesdone.com, read by
-- resend_inbound), the unsubscribe mailbox, the hourly bounce/complaint brake (a bounce on either lane is a
-- bounce), and invite_warmup.
--
-- The lane cannot go live until the founder adds hello.quotesdone.com in Resend and its DNS verifies:
-- send_outbox asks Resend (GET /domains) before using it. With the flag ON and anything but verified + sending
-- enabled (or Resend unreachable), lane invitations are HELD, never sent from info@ (that would put the cold
-- campaign back on the sign-up codes' identity), and the it_engineer finding 'invite_lane_domain_unverified' is
-- filed; every other mail is untouched. Held rows stay queued with not_before moved out, so they never take the
-- claim slots of other mail, and on the lane no more than invite_daily_cap invitations leave in a UTC day
-- however many were held; send_outbox's email_stale_hours guard retires any held longer than that.
--
-- prevented by: scripts/checks/the_invitations_leave_on_their_own_subdomain.test.mjs
--               supabase/functions/send_outbox/invite_lane.test.ts
--   node scripts/apply_sql.mjs scripts/sql/the_invitations_leave_on_their_own_subdomain_so_a_campaign_cannot_cost_the_sign_up_codes.sql --apply --ddl

begin;

-- ── 1. THE FLAG AND THE LANE'S SENDER, OFF ─────────────────────────────────────────────────────────────────
insert into public.app_secrets (key, value) values
  ('invite_lane_enabled', 'false'),
  ('invite_lane_from', 'QuotesDone <invite@hello.quotesdone.com>'),
  ('invite_lane_since', '')
on conflict (key) do nothing;

-- ── 2. THE ACTIVATION STAMP ─────────────────────────────────────────────────────────────────────────────
create or replace function public.trg_invite_lane_since()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if lower(btrim(coalesce(new.value, ''))) = 'true'
     and (tg_op = 'INSERT' or lower(btrim(coalesce(old.value, ''))) is distinct from 'true') then
    insert into public.app_secrets (key, value) values ('invite_lane_since', now()::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;
  return new;
end
$fn$;
revoke execute on function public.trg_invite_lane_since() from public, anon, authenticated;

drop trigger if exists a60_invite_lane_since on public.app_secrets;
create trigger a60_invite_lane_since after insert or update on public.app_secrets
  for each row when (new.key = 'invite_lane_enabled') execute function public.trg_invite_lane_since();

-- ── 3. WHERE THE RAMP STARTS COUNTING ───────────────────────────────────────────────────────────────────
create or replace function public.fn_invite_lane_since()
returns timestamptz
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_on boolean; v_since timestamptz;
begin
  v_on := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_lane_enabled'), false);
  if not v_on then return '-infinity'::timestamptz; end if;
  begin
    v_since := nullif(btrim((select value from public.app_secrets where key = 'invite_lane_since')), '')::timestamptz;
  exception when others then v_since := null;
  end;
  -- ON with no readable stamp: count nothing before now, so the lane starts at day 1 rather than inheriting.
  return coalesce(v_since, now());
end
$fn$;
revoke execute on function public.fn_invite_lane_since() from public, anon, authenticated;

-- A lane invitation counts toward the lane's warm-up only once it has actually LEFT. leads.invited_at is written
-- when enqueue_supplier_invites QUEUES the row; send_outbox holds a lane invitation while the subdomain is not
-- verified, and a held invitation must not warm a ramp for mail nobody received.
create or replace function public.fn_invite_lane_sent(p_lead_id bigint)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (select 1 from public.notifications n
                  where n.lead_id = p_lead_id and n.type = 'supplier_invite' and n.status = 'sent')
$fn$;
revoke execute on function public.fn_invite_lane_sent(bigint) from public, anon, authenticated;

-- ── 4. THE EXISTING RAMP, SCOPED TO THE LANE ────────────────────────────────────────────────────────────
create or replace function public.fn_invite_ramp()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_base int     := coalesce((c->>'base_cap')::int, 30);
  v_ceiling int  := coalesce((c->>'ceiling_cap')::int, 200);
  v_growth numeric := coalesce((c->>'growth_factor')::numeric, 1.5);
  v_used_pct numeric := coalesce((c->>'grow_if_used_pct')::numeric, 0.8);
  v_ok_b numeric := coalesce((c->>'grow_max_bounce_rate')::numeric, 0.02);
  v_ok_c numeric := coalesce((c->>'grow_max_complaint_rate')::numeric, 0.001);
  v_back_b numeric := coalesce((c->>'backoff_bounce_rate')::numeric, 0.035);
  v_back_n int   := coalesce((c->>'backoff_min_sends')::int, 20);
  v_pause_c numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_pause_n int  := coalesce((c->>'pause_min_complaints')::int, 2);
  v_cur int; v_new int; v_note text; v_status text := 'ok';
  v_sent_total int; v_last_sent timestamptz; v_last_day date; v_last_day_sent int;
  v_s48 int; v_b48 int; v_c48 int; v_br numeric; v_cr numeric;
  v_restart boolean := false; v_prev_restart boolean; v_grew_since boolean; v_uncontacted int;
  -- THE LANE'S OWN HISTORY (24 Sep 2026): '-infinity' while invite_lane_enabled is off (every scope below is
  -- then a no-op); the activation stamp while it is on, so the new subdomain restarts at day 1.
  v_since timestamptz := public.fn_invite_lane_since();
begin
  v_cur := coalesce((select nullif(value,'')::int from app_secrets where key = 'invite_daily_cap'), v_base);

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

  select count(*), max(invited_at) into v_sent_total, v_last_sent from leads where invited_at is not null and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
  -- THE 48 h HEALTH READ IS NOT LANE-SCOPED (review of #963): complaints and bounces reflect the list and the
  -- copy, not the domain, so switching the lane on must never hide yesterday's complaints from the pause.
  select count(*),
         count(*) filter (where invite_status = 'bounced'),
         count(*) filter (where invite_status = 'complained')
    into v_s48, v_b48, v_c48
    from leads where invited_at > now() - interval '48 hours' and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
  v_br := v_b48::numeric / greatest(v_s48, 1);
  v_cr := v_c48::numeric / greatest(v_s48, 1);

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
  elsif v_s48 >= v_back_n and (v_br >= v_back_b or v_c48 >= 1) then
    v_new := greatest(v_base, floor(v_cur * 0.5)::int);
    v_note := 'back off: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaints ' || v_c48
              || '; cap ' || v_cur || '->' || v_new || '.';
    if v_new = v_cur then
      v_status := 'error';
      if not exists (select 1 from founder_alerts where event = 'invite_throttle_exhausted' and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level, event, detail, channel)
        values ('crit', 'invite_throttle_exhausted', 'Supplier invites: ' || v_note || ' The cap is already at its base; the hard brake pauses at '
                || round(coalesce((select nullif(value,'')::numeric from app_secrets where key = 'invite_max_bounce_rate'), 0.05) * 100, 1) || '%.', 'system');
      end if;
    end if;
  elsif v_br >= v_ok_b or v_cr >= v_ok_c then
    v_new := v_cur;
    v_note := 'hold: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaint ' || round(v_cr * 100, 2)
              || '% — growth needs bounce < ' || round(v_ok_b * 100, 1) || '% and complaint < ' || round(v_ok_c * 100, 2) || '%.';
  else
    -- GROW ON VOLUME ISSUED, ONCE PER SEND DAY. Weekends and holidays run no batch, so a calendar-based
    -- ladder would ratchet on days the domain sent nothing.
    select max((invited_at at time zone 'Asia/Dubai')::date) into v_last_day from leads where invited_at is not null and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
    select count(*) into v_last_day_sent from leads where (invited_at at time zone 'Asia/Dubai')::date = v_last_day and invited_at >= v_since and (v_since = '-infinity'::timestamptz or public.fn_invite_lane_sent(id)) and not coalesce(is_demo, false) and not public.fn_is_demo_email(email);
    select exists (select 1 from agent_runs a where a.agent = 'invite_ramp' and a.finished_at > v_last_sent
                     and (a.counts->>'new_cap')::int > (a.counts->>'old_cap')::int) into v_grew_since;
    if v_grew_since then
      v_new := v_cur; v_note := 'hold: already grew once since the last send day.';
    elsif v_last_day_sent < ceil(v_cur * v_used_pct) then
      v_new := v_cur; v_note := 'hold: the last send day (' || v_last_day || ') issued ' || v_last_day_sent || ' of a cap of ' || v_cur
                                || '; growth needs ' || round(v_used_pct * 100) || '%.';
    else
      v_new := least(v_ceiling, ceil(v_cur * v_growth)::int);
      v_note := 'healthy: 48 h bounce ' || round(v_br * 100, 1) || '% (' || v_b48 || '/' || v_s48 || '), complaints ' || v_c48
                || '; last send day issued ' || v_last_day_sent || '; cap ' || v_cur || '->' || v_new || '.';
    end if;
  end if;

  v_new := greatest(v_base, least(v_new, v_ceiling));
  if v_new <> v_cur then
    update app_secrets set value = v_new::text where key = 'invite_daily_cap';
  end if;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values ('invite_ramp', v_status,
          jsonb_build_object('old_cap', v_cur, 'new_cap', v_new, 'sent_total', v_sent_total, 'restart', v_restart,
                             'sent_48h', v_s48, 'bounced_48h', v_b48, 'complained_48h', v_c48,
                             'bounce_pct_48h', round(v_br * 100, 2), 'complaint_pct_48h', round(v_cr * 100, 3))
          || case when v_since > '-infinity'::timestamptz then jsonb_build_object('lane_since', v_since) else '{}'::jsonb end,
          v_note, now());
  if v_new < v_cur and not v_restart then
    insert into founder_alerts(level, event, detail, channel)
    values ('warn', 'invite_cap_throttled', 'Supplier-invite cap reduced ' || v_cur || '->' || v_new || ' — ' || v_note, 'system');
  end if;
  return v_new;
end
$fn$;
revoke execute on function public.fn_invite_ramp() from public, anon, authenticated;

-- ── 5. THE 18:00 LIST PREDICTS THE SAME DAY-1 CAP ───────────────────────────────────────────────────────
create or replace function public.fn_supplier_campaign_next_list(p_after date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_after date := coalesce(p_after, (now() at time zone 'Asia/Dubai')::date);
  v_day date := v_after + 1; v_skipped jsonb := '[]'::jsonb; v_why text; i int := 0;
  v_cap int; v_pool int; v_n int; v_switch boolean; v_held text; v_rows jsonb;
begin
  loop
    v_why := public.fn_supplier_invites_hold_reason(v_day);
    exit when v_why is null;
    v_skipped := v_skipped || jsonb_build_object('day', v_day, 'why', v_why);
    v_day := v_day + 1; i := i + 1;
    if i > 20 then raise exception 'no supplier sending day within 20 days of %', v_after; end if;
  end loop;
  v_switch := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
              and public.fn_supplier_outreach_golive();
  v_held := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                 when not v_switch then 'invite_enabled is false' end;
  -- the sender's own numbers (enqueue_supplier_invites): cap, eligible pool, planned = least of the two
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  -- fn_invite_ramp runs before the batch on the sending day; with nothing sent in the 3 days before it, it resets
  -- the cap to invite_warmup.base_cap (a cold domain restarts). Show that number, not the stale stored cap.
  -- Scoped to the invitation lane exactly as the ramp is (fn_invite_lane_since; '-infinity' while it is off).
  if coalesce((select max(l.invited_at) from public.leads l where l.invited_at >= public.fn_invite_lane_since() and (public.fn_invite_lane_since() = '-infinity'::timestamptz or public.fn_invite_lane_sent(l.id)) and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)), '-infinity'::timestamptz) < (v_day::timestamp at time zone 'Asia/Dubai') - interval '3 days' then
    v_cap := coalesce((select (nullif(value, '')::jsonb->>'base_cap')::int from public.app_secrets where key = 'invite_warmup'), 30);
  end if;
  select count(*) into v_pool from public.leads l where public.fn_supplier_invite_eligible(l);
  v_n := greatest(least(v_cap, v_pool), 0);
  select coalesce(jsonb_agg(jsonb_build_object('n', c.rn, 'lead_id', c.lead_id,
            'company', coalesce(nullif(btrim(c.company_name), ''), '(no company name)'),
            'emirate', coalesce(nullif(btrim(l.emirate), ''), '-'), 'language', c.lang,
            'email', public.fn_mask_email(c.to_email)) order by c.rn), '[]'::jsonb)
    into v_rows
    from (select x.*, row_number() over () rn from public.fn_supplier_invite_candidates(v_n) x) c
    join public.leads l on l.id = c.lead_id;
  return jsonb_build_object('send_day', v_day, 'skipped', v_skipped, 'switch_on', v_switch, 'held_because', v_held,
                            'cap', v_cap, 'pool', v_pool, 'planned', v_n, 'rows', v_rows);
end $fn$;
revoke execute on function public.fn_supplier_campaign_next_list(date) from public, anon, authenticated;

commit;

-- ── VERDICT (reads only; the lane is OFF, so its scope must be a no-op) ───────────────────────────────────
select case
  when (select value from public.app_secrets where key = 'invite_lane_enabled') is distinct from 'false'
    then 'PROBE FAILED: invite_lane_enabled is not the seeded false'
  when public.fn_invite_lane_since() <> '-infinity'::timestamptz
    then 'PROBE FAILED: the lane is off but fn_invite_lane_since() is not -infinity, so the ramp would not be today''s'
  when not exists (select 1 from pg_trigger where tgname = 'a60_invite_lane_since' and tgrelid = 'public.app_secrets'::regclass)
    then 'PROBE FAILED: the activation stamp trigger is missing'
  else 'PROBE OK' end as verdict;
