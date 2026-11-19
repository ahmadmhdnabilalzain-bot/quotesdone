-- A CANCELLED INVITATION FREES ITS LEAD AND ITS INDEX SLOT. Seat: ceo (the supplier invitation lane). 19 Nov 2026. The short first
-- half of invitations_go_only_to_addresses_that_were_checked.sql, split out on review so that the two strong locks on
-- public.notifications (the index rebuild and the trigger, ACCESS EXCLUSIVE until COMMIT, which stop the outbox) are held for
-- milliseconds and not across that file's funnel refresh, judgements and probe.
--
-- MEASURED (production SELECTs, 19 Nov 2026): 37 leads sat with invite_status 'queued' behind a supplier_invite that was cancelled
-- and never sent (16 with no last_error, 17 'held: the Microsoft 365 lane reached invite_daily_cap', 4 'cancelled: the supplier
-- campaign was paused by invite_bounce_judge'; all 37 still carry a 'verified' lead_email_check verdict). The once-only index
-- notifications_supplier_invite_once_uidx (one supplier_invite per address, ever; 1,664 rows, 0 duplicates under the new predicate)
-- counted those rows, so a new invitation to the same address would be dropped by enqueue's ON CONFLICT. Every pause strands that
-- day's batch the same way.
-- WHAT THIS DOES: the index leaves out a row cancelled before it left; enqueue_supplier_invites names the same predicate (its live
-- body, equal to its canonical file an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.sql, with only the ON
-- CONFLICT line changed); a zero-row insert proves the conflict target is inferred; trigger z82 frees a lead whose queued invitation
-- the campaign itself stopped. It sends nothing, writes no notification and changes no lead now (the 37 are released by the second
-- file).
-- prevented by: scripts/checks/invitations_go_only_to_addresses_that_were_checked.test.mjs.
-- APPLY FIRST, outside a sending minute, then the second file:
--   node scripts/apply_sql.mjs scripts/sql/a_cancelled_invitation_frees_its_lead_and_its_index_slot.sql --apply --ddl --seat ceo
--   then delete scripts/sql/pending/a_cancelled_invitation_frees_its_lead_and_its_index_slot.txt and append this file as the LAST line
--   of scripts/sql/MANIFEST.txt.
-- LOCKS: notifications (about 1,700 rows): DROP INDEX, CREATE INDEX and CREATE TRIGGER, milliseconds; enqueue is replaced in place.
-- ROLLBACK: in one transaction, recreate notifications_supplier_invite_once_uidx with "where type = 'supplier_invite'", re-apply
-- enqueue_supplier_invites from its canonical file, drop trigger z82_notifications_a_cancelled_invitation_frees_its_lead.
set local lock_timeout = '1500ms';

-- the outbox's highest id before this file (the probe proves the file queued no message)
select set_config('qd.invite_slot_n0', (select coalesce(max(id), 0)::text from public.notifications), true);

-- ── 1. NEVER TWICE, BUT A CANCELLED, NEVER-SENT ROW IS NOT A SEND ───────────────────────────────────────────────────
-- The once-only index (one supplier_invite per address, ever) leaves out a row cancelled before it left, and enqueue's ON CONFLICT
-- names the same predicate, in the same transaction, so the batch never runs against an index it cannot infer.
drop index if exists public.notifications_supplier_invite_once_uidx;
create unique index notifications_supplier_invite_once_uidx on public.notifications (lower(btrim(to_email)))
  where type = 'supplier_invite' and (status is distinct from 'cancelled' or sent_at is not null);
comment on index public.notifications_supplier_invite_once_uidx is 'One supplier invitation per address, ever; a row cancelled before it left (sent_at null) does not count (19 Nov 2026: 37 leads were stranded behind such rows). enqueue_supplier_invites names this predicate in its ON CONFLICT. invitations_go_only_to_addresses_that_were_checked.sql';

-- the batch: the live body (MANIFEST: an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.sql) with its ON CONFLICT
-- naming the new predicate, and nothing else changed
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
  select count(*) into v_pool from public.fn_supplier_invite_eligible_ids();
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
  -- 18 Nov 2026 (sales_engineer, review of #2051): the reply follow-ups spend the SAME cap (fn_sales_engineer_follows_up_supplier_replies):
  -- those sent this UTC day and those still due today, so invitations queued after the day's follow-ups cannot exceed it on any route.
  -- The same advisory lock as the follow-ups' read-and-spend, so the two cannot both take the last slot.
  perform pg_advisory_xact_lock(hashtext('qd_invite_daily_cap'));
  select count(*) into v_used from notifications where type in ('supplier_invite', 'supplier_invite_nudge') and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
  v_used := v_used + (select count(*) from public.supplier_reply_followup x
                       where not public.fn_is_demo_email(x.to_email)
                         and ((x.state = 'sent' and (x.done_at at time zone 'UTC')::date = v_today)
                           or (x.state = 'due' and (x.due_at at time zone 'UTC')::date <= v_today)));
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  -- the warm classes first, then at most new_class_cap from the classes not yet warmed up (both through the verdict gate);
  -- each candidate call is made only for a non-empty class list (a null list would mean every class)
  v_pick := '[]'::jsonb;
  if cardinality(v_cold) = 0 then
    -- every open class is warm (the usual day): one pick over all of them, exactly as before
    select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) into v_pick from public.fn_supplier_invite_candidates(v_remaining, v_open) c;
  elsif cardinality(v_warm) > 0 then
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
    -- 19 Nov 2026 (ceo): the once-only index leaves out an invitation cancelled before it left, so this names its predicate
    on conflict (lower(btrim(to_email))) where type = 'supplier_invite' and (status is distinct from 'cancelled' or sent_at is not null) do nothing
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
$function$;

-- the conflict target above is inferred from the new index: a zero-row insert plans it now (an error here rolls the whole file
-- back, rather than leaving a batch that fails at 10:00). WHERE false: no row, no row trigger, no message, no person.
insert into public.notifications (type, to_email, to_role, status)
select 'supplier_invite', 'zz-demo-never-sent@example.invalid', 'supplier', 'queued' where false
on conflict (lower(btrim(to_email))) where type = 'supplier_invite' and (status is distinct from 'cancelled' or sent_at is not null) do nothing;

-- A QUEUED INVITATION THE CAMPAIGN STOPPED BEFORE IT LEFT FREES ITS LEAD: a pause (fn_invite_campaign_pause, last_error 'cancelled:
-- the supplier campaign was paused by ...'), a failed probation (fn_sales_engineer_restarts_invites_after_a_brake, 'cancelled: the
-- restart''s probation failed: ...') and the send-time check (send_outbox/invite_lane.ts campaignStep, 'cancelled at send time: ...');
-- the three prefixes read from the live routines and the code on 19 Nov 2026. The lead goes back to never invited, so the next batch
-- may take it under every rule of the day; a lead with any other live invitation is left as it is.
create or replace function public.trg_notifications_a_cancelled_invitation_frees_its_lead()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  update public.leads l set invite_status = null, invited_at = null
   where l.id = new.lead_id and l.invite_status = 'queued'
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and n.id <> new.id
                        and (n.lead_id = l.id or lower(btrim(n.to_email)) = lower(btrim(l.email)))
                        and (n.status is distinct from 'cancelled' or n.sent_at is not null));
  return null;
end $fn$;
revoke execute on function public.trg_notifications_a_cancelled_invitation_frees_its_lead() from public, anon, authenticated;
create or replace trigger z82_notifications_a_cancelled_invitation_frees_its_lead after update of status on public.notifications
  for each row when (new.type = 'supplier_invite' and new.status = 'cancelled' and old.status is distinct from 'cancelled'
                     and new.sent_at is null and new.lead_id is not null
                     -- only the campaign's own stops (review of 19 Nov 2026): a rejected address (fn_sales_engineer_records_email_checks
                     -- cancels with no last_error) or a cancel by hand keeps the lead and its company's one-per-company mark
                     and (new.last_error like 'cancelled: the supplier campaign was paused%'
                          or new.last_error like 'cancelled: the restart''s probation failed%'
                          or new.last_error like 'cancelled at send time:%'))
  execute function public.trg_notifications_a_cancelled_invitation_frees_its_lead();

-- ── 2. THE PROBE: one verdict row ───────────────────────────────────────────────────────────────────────────────────
with t as (select pg_get_triggerdef(oid) as d from pg_trigger
            where tgname = 'z82_notifications_a_cancelled_invitation_frees_its_lead' and tgrelid = 'public.notifications'::regclass),
i as (select pg_get_indexdef('public.notifications_supplier_invite_once_uidx'::regclass) as d),
e as (select pg_get_functiondef('public.enqueue_supplier_invites(integer)'::regprocedure) as d),
dup as (select count(*) as n from (select lower(btrim(to_email)) from public.notifications
          where type = 'supplier_invite' and (status is distinct from 'cancelled' or sent_at is not null) group by 1 having count(*) > 1) x),
mine as (select count(*) as n from public.notifications
          where id > coalesce(nullif(current_setting('qd.invite_slot_n0', true), ''), '0')::bigint and created_at = now()),
f as (select array_remove(array[
    case when i.d !~ 'cancelled' or i.d !~* 'unique' then 'the once-only index does not leave out a cancelled invitation: ' || i.d end,
    case when e.d !~ 'status is distinct from ''cancelled'' or sent_at is not null' then 'enqueue''s ON CONFLICT does not name the new predicate' end,
    case when (select count(*) from t) = 0 then 'trigger z82 is missing' end,
    case when (select count(*) from t) > 0 and (select d from t) !~ 'probation failed' then 'trigger z82 frees a lead on any cancel' end,
    case when dup.n > 0 then dup.n || ' address(es) hold two live invitations' end,
    case when mine.n > 0 then 'this file queued ' || mine.n || ' notification(s)' end], null) as fails
  from i, e, dup, mine)
select case when cardinality(f.fails) = 0 then 'PROBE OK: ' else 'PROBE FAILED: ' || array_to_string(f.fails, '; ') || ' || ' end
    || 'index ' || i.d || '; z82 ' || coalesce((select d from t), '(missing)') || '; notifications queued by this file ' || mine.n as verdict
  from f, i, mine;
