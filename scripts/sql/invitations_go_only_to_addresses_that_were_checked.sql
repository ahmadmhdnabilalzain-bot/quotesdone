-- THE INVITATIONS GO ONLY TO ADDRESSES THAT WERE CHECKED, THE BRAKE WAITS FOR A SAMPLE THAT MEANS SOMETHING, AND THE CEO
-- RESTARTS THEM ON THAT EVIDENCE. Seat: ceo (the supplier invitation lane). 19 Nov 2026. Founder rulings 1455 (the sending cap is
-- the CEO's decision, on measured sender health), 1231 (the ceiling is 50 a day), 1486 (inbox-going addresses only; Microsoft
-- ignored), 1696 (the CEO has full authority).
--
-- MEASURED (production SELECTs only, 19 Nov 2026, 12:00Z; the funnel analysis of the same day):
--   * 150 invitations (notifications.type 'supplier_invite', sent) since the first on 28 Oct; 16 leads bounced, 15 of them hard
--     (NoSuchUser / 5.1.1). By the address's evidence (leads.email_verified), invitations and hard bounces:
--       web_scrape 'verified'          74 sent,  1 hard  (1.4%)
--       web_scrape 'maps' / 'social'    3 sent,  0 hard
--       web_scrape 'true'              38 sent,  6 hard  (15.8%)   'true' is syntax + MX only: it says nothing of the mailbox
--       uaecsd directory (null)        32 sent,  8 hard  (25.0%)   unchecked
--       other unchecked (null)          3 sent,  0 hard
--     So the addresses with evidence bounced 1 of 77 (1.3%) in 30 days and everything else 14 of 73 (19.2%).
--   * Brake 51, 18 Nov 10:00:34Z (invite_same_day_brake -> fn_invite_judge_and_brake): 2 hard of 6 invitations that day, Wilson
--     95% lower bound 11.7% > 3%. Both bounces were 'true' addresses. The 14-day window read 5 hard of 98 (lower bound 2.51%);
--     every one of the 5 was a 'true' address; the other 71 (46 invitations to addresses with evidence, 25 nudges) had 0. invite_enabled has
--     been false since; invite_daily_cap is 5; the CEO's review holds 7 days (until 25 Nov). The ramp halves the cap while the
--     window's lower bound is above backoff_hard_lb (2.5%), so a plain restart would have halved again on the first day.
--   * 37 leads stranded: invite_status 'queued', invited_at set, and only a CANCELLED, never-sent supplier_invite row (brake 51
--     cancelled 18 Nov's batch; the lane cap and earlier pauses the rest). Eligibility wants invite_status null, the "never twice"
--     test counted the cancelled row, and notifications_supplier_invite_once_uidx (one supplier_invite per address, ever) would
--     have dropped a new invitation to the same address in enqueue's ON CONFLICT. Every pause strands that day's batch the same way.
--   * ceo_supplier_funnel_daily read 190 sent / 174 delivered: fn_ceo_supplier_funnel_refresh counted the 40 nudges as sends.
--     The invitations are 150 sent / 134 delivered.
--   * The last note to a parked lead (send_outbox/m365_lane.ts m365FinalTouchText) wrote out the WhatsApp sender's United States
--     number to UAE suppliers. Removed from that copy in the same commit; the sender itself is untouched (ruling 863).
--
-- WHAT THIS DOES:
--   1. fn_invite_address_has_evidence(email_verified): 'verified', 'maps' or 'social' (the address checked as a mailbox, or
--      published by the company itself on its map listing or social page). Not 'true', not 'mx_ok', not null. Both eligibility
--      rules (fn_supplier_invite_eligible, the outbox guard's row rule, and fn_supplier_invite_eligible_ids, the set the batch
--      reads) require it, whatever invite_reachable_only says. Every other rule is kept as it was: one per domain and one per
--      company (fn_supplier_invite_candidates, unchanged), suppression, the verdict of lead_email_check, MX, consent, the holiday
--      and weekend holds (enqueue_supplier_invites), and the founder-inbox guards on notifications.
--   2. THE BRAKE NEEDS A SAMPLE: fn_invite_judge_cell judges a hard-bounce rate only on at least hard_min_sent (20) sends, by the
--      same Wilson lower bound; below it, 3 hard bounces in one Dubai day (hard_burst) still stop the company. The judgement's
--      'checked' segment is the population the company sends now (an invitation to an address with evidence, or a nudge).
--      Replayed at brake 51: no brake (today 0 hard of 4 checked; window 0 of 71). A complaint still stops it whatever the sample.
--   3. fn_invite_restart_projection(now, 30 days): the bounce rate of the last 30 days' invitations to addresses with evidence.
--      fn_ceo_restarts_invites refuses a restart unless it is under restart_max_rate (3%) on at least restart_min_sent (20). Then
--      this file restarts under the CEO's authority through that routine (the existing path: invite_brake resumed, a 'restart'
--      row in invite_brake_decision, agent_runs 'ceo') and sets invite_daily_cap to the ramp's start (invite_warmup.base_cap,
--      20, under the founder cap of 50), first batch at most 10 (fn_invite_restart_cap). If refused, it stays off and the refusal
--      is the record. Either way one row in ceo_own_decision says what the CEO decided and why.
--   4. The 37 stranded leads are released (invite_status and invited_at back to null; their ids and old stamps in agent_runs), the
--      once-only index and enqueue's ON CONFLICT leave out a row cancelled before it left, and a trigger frees a lead whenever its
--      queued invitation is cancelled before it left (every pause and send-time cancel), so this does not recur.
--   5. ceo_supplier_funnel_daily counts only first invitations as sent and delivered; nudges get their own column, nudges_sent.
--   6. The probe at the end returns the verdict row (PROBE OK / PROBE FAILED).
-- WHAT THIS DOES NOT CHANGE: the placement gate (fn_invite_placement_open_providers; Microsoft and Yahoo stay closed, ruling 1486),
-- the founder's supplier_outreach_golive, the ceiling of 50 (ruling 1231), the ramp, the nudges, the sales engineer's restart, the
-- WhatsApp sender.
--
-- prevented by: scripts/checks/invitations_go_only_to_addresses_that_were_checked.test.mjs (text, with known-bad controls) and
-- supabase/functions/send_outbox/invite_variants.test.ts (the last note carries no foreign number; m365CopyLint refuses one).
-- APPLY (after 19 Nov 10:01Z, 24 hours after brake 51; outside a sending minute):
--   node scripts/apply_sql.mjs scripts/sql/invitations_go_only_to_addresses_that_were_checked.sql --apply --ddl --seat ceo
--   then delete scripts/sql/pending/invitations_go_only_to_addresses_that_were_checked.txt, append this file as the LAST line of
--   scripts/sql/MANIFEST.txt and regenerate the schema mirror (export_from_either_source_is_identical.mjs --write) in one commit.
-- LOCKS: notifications (about 1,700 rows) gets its once-only index rebuilt and one trigger (ACCESS EXCLUSIVE for milliseconds);
-- ceo_supplier_funnel_daily (17 rows) gets a column with a constant default; every routine is replaced in place; 37 leads rows.
-- ROLLBACK: re-apply the previous bodies from their canonical files (fn_supplier_invite_eligible and _ids:
-- an_invitation_goes_only_to_a_checked_mailbox_and_a_bounce_brake_restarts_itself.sql; enqueue_supplier_invites:
-- an_interested_prospect_is_chased_three_times_until_he_registers_or_declines.sql; fn_invite_judge_cell, fn_invite_bounce_judgement,
-- fn_ceo_restarts_invites: the_bounce_brake_judges_each_bounce_by_kind_provider_and_sample_and_the_ceo_restarts_within_a_limit.sql;
-- fn_ceo_supplier_funnel_refresh: the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql), recreate
-- notifications_supplier_invite_once_uidx with "where type = 'supplier_invite'" in the same transaction as enqueue, drop trigger
-- z82_notifications_a_cancelled_invitation_frees_its_lead, and set invite_enabled false if the restart is to be undone.
set local lock_timeout = '1500ms';

-- the outbox's highest id before this file, so the probe can prove the file queued no message (read back at the end)
select set_config('qd.invite_checked_n0', (select coalesce(max(id), 0)::text from public.notifications), true);

-- ── 1. WHAT COUNTS AS A CHECKED ADDRESS ──────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_invite_address_has_evidence(p_email_verified text)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  -- 'verified': the address answered as a mailbox (1 hard bounce in 74 invitations to 19 Nov 2026); 'maps' / 'social': the company
  -- published it on its own map listing or social page (0 of 3). Not 'true' (syntax + MX: 6 of 38), 'mx_ok' or null (8 of 32).
  select coalesce(lower(btrim(p_email_verified)), '') in ('verified', 'maps', 'social')
$fn$;
revoke execute on function public.fn_invite_address_has_evidence(text) from public, anon, authenticated;
comment on function public.fn_invite_address_has_evidence(text) is 'An address with evidence that its mailbox exists (verified, maps, social), the only addresses a supplier invitation goes to since 19 Nov 2026 (ruling 1486). invitations_go_only_to_addresses_that_were_checked.sql';

-- ── 2. ELIGIBILITY: THE ROW RULE AND ITS SET FORM ───────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_invite_eligible(p leads)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     -- a fixture is never a supplier: the flag, the naming convention, and the reserved domains
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     -- screened and matched but undecided is not cleared; a confirmed ban is total
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h
                      where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     -- never twice, read from the outbox rather than from a status column. 19 Nov 2026 (ceo): an invitation cancelled before it
     -- left (status cancelled, sent_at null) was never a send; 37 leads were stranded behind such rows (brake 51, the lane cap).
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email))
                        and (n.status is distinct from 'cancelled' or n.sent_at is not null))
     and coalesce((public.fn_email_sendable(p.email)->>'ok')::boolean, false)
     -- 2 Nov 2026 (ledger 1449): the sales engineer's stored verdict for THIS address (public.lead_email_check)
     and exists (select 1 from public.lead_email_check ec
                  where ec.lead_id = p.id and ec.verdict = 'verified' and ec.email_md5 = md5(lower(btrim(p.email))))
     -- 19 Nov 2026 (ceo, rulings 1455/1486/1696): only an address with evidence that its mailbox exists. 'true' (syntax + MX) bounced
     -- 6 of 38 invitations and the unchecked directory rows 8 of 32; 'verified' bounced 1 of 74 (since 28 Oct).
     and public.fn_invite_address_has_evidence(p.email_verified)
     -- 22 Sep 2026: a COLD invitation needs a measured MX. An A-record-only domain (361 leads), a lookup
     -- that errored (86) or a domain never asked is a bounce risk on a domain with no history to spend.
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     -- ... and never a mailbox whose reader is not the business (44 leads): a recruiter or a lawyer
     -- presses "spam", they do not register.
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
     -- 24 Sep 2026 (marketing, ledger 993): never an address on a directory, marketplace, hosting, template or
     -- placeholder domain (public.email_platform_domain, exact domain equality, no word is read) -- the reader is not
     -- the company. The one exception is a platform that IS the lead: its own website host is that domain.
     and not exists (select 1 from public.email_platform_domain d
                      where d.domain = split_part(lower(btrim(p.email)), '@', 2)
                        and d.domain is distinct from lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(p.website), ''), p.maps_website, '')),
                                                          '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi')))
$function$;

create or replace function public.fn_supplier_invite_eligible_ids()
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- The small reference tables (sanctions 46 rows, screening hits, 37 suppressions, block patterns,
  -- 47 platform domains) are read ONCE into arrays: with the leads estimate at 1 row the planner
  -- chose nested loops and re-read each of them 19,444 times (EXPLAIN ANALYZE, 4.8 s). NULLs are
  -- filtered out of each array, because `x <> all(array[..., null])` is null and would drop every lead.
  select p.id
    from public.leads p
   where coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     and p.id <> all (array(select b.lead_id from public.sanctions_ban b where b.lead_id is not null))
     and p.id <> all (array(select h.lead_id from public.supplier_screening_hit h
                             where h.lead_id is not null and h.status in ('open', 'confirmed')))
     -- never twice; an invitation cancelled before it left was never a send (19 Nov 2026, as the row rule)
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email))
                        and (n.status is distinct from 'cancelled' or n.sent_at is not null))
     -- fn_email_sendable(p.email)->>'ok', clause for clause
     and lower(btrim(p.email)) ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$'
     and lower(btrim(p.email)) <> all (array(select lower(s.email) from public.email_suppressions s where s.email is not null))
     and not exists (select 1 from public.email_domain_mx m0
                      where m0.domain = split_part(lower(btrim(p.email)), '@', 2) and m0.has_mx = false
                        and m0.kind in ('nxdomain', 'no_records'))
     and not coalesce(lower(btrim(p.email)) ~ any (array(select bp.pattern from public.email_block_pattern bp
                                                         where bp.active and bp.pattern is not null)), false)
     -- 2 Nov 2026 (ledger 1449): the sales engineer's stored verdict for THIS address (public.lead_email_check)
     and exists (select 1 from public.lead_email_check ec
                  where ec.lead_id = p.id and ec.verdict = 'verified' and ec.email_md5 = md5(lower(btrim(p.email))))
     -- 19 Nov 2026 (ceo): only an address with evidence that its mailbox exists (as the row rule)
     and public.fn_invite_address_has_evidence(p.email_verified)
     -- a measured MX
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
     and not (split_part(lower(btrim(p.email)), '@', 2) = any (array(select d.domain from public.email_platform_domain d where d.domain is not null))
              and split_part(lower(btrim(p.email)), '@', 2) is distinct from
                  lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(p.website), ''), p.maps_website, '')),
                                       '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi')))
$function$;

-- ── 3. NEVER TWICE, BUT A CANCELLED, NEVER-SENT ROW IS NOT A SEND ───────────────────────────────────────────────────
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

-- A QUEUED INVITATION CANCELLED BEFORE IT LEFT FREES ITS LEAD (every pause and every send-time cancel; measured: brake 51 cancelled
-- 18 Nov's batch, the lane cap and earlier pauses the rest of the 37). The lead goes back to never invited, so the next batch may
-- take it under every rule of the day; a lead with any other live invitation is left as it is.
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
                     and new.sent_at is null and new.lead_id is not null)
  execute function public.trg_notifications_a_cancelled_invitation_frees_its_lead();

-- ── 4. THE BRAKE JUDGES A SAMPLE THAT MEANS SOMETHING ───────────────────────────────────────────────────────────────
update public.app_secrets
   set value = jsonb_set(value::jsonb || jsonb_build_object('hard_min_sent', 20, 'hard_burst', 3, 'restart_days', 30,
                                                            'restart_max_rate', 0.03, 'restart_min_sent', 20),
         '{note}', to_jsonb(coalesce(value::jsonb->>'note', '') || ' 19 Nov 2026 (ceo, invitations_go_only_to_addresses_that_were_checked.sql): '
           || 'a hard-bounce rate brakes only on hard_min_sent (20) sends in its cell; below that, hard_burst (3) hard bounces in one Dubai '
           || 'day stop the company; the CEO restarts only when the last restart_days (30) of invitations to checked addresses bounced '
           || 'under restart_max_rate (3%) on at least restart_min_sent (20) sends.'))::text
 where key = 'invite_bounce_judge' and not (value::jsonb ? 'hard_min_sent');

-- the cell rule: the live body with the minimum sample on the hard-bounce rate, nothing else changed
create or replace function public.fn_invite_judge_cell(p_sent integer, p_hard integer, p_policy integer, p_soft integer, p_complaint integer, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare z numeric := coalesce((p_cfg->>'z')::numeric, 1.645);
  hl numeric := public.fn_invite_wilson_lower(p_hard, p_sent, z);
  pl numeric := public.fn_invite_wilson_lower(p_policy, p_sent, z);
  sl numeric := public.fn_invite_wilson_lower(p_soft, p_sent, z);
  cl numeric := public.fn_invite_wilson_lower(p_complaint, p_sent, z);
  v_breach text;
begin
  v_breach := case
    when p_complaint >= coalesce((p_cfg->>'complaint_min')::int, 1) and cl > coalesce((p_cfg->>'complaint_limit')::numeric, 0.003) then 'complaint'
    -- 19 Nov 2026 (ceo): a hard-bounce rate is judged only on a sample that means something, hard_min_sent sends in the cell (20).
    -- Brake 51 (18 Nov 10:00Z) stopped the company on 2 hard of 6 sent that day, lower bound 11.7%: at 6 sends one address moves
    -- the rate by 17 points. Below the sample the judgement's burst count (hard_burst, 3 in a day) still stops it.
    when p_hard >= coalesce((p_cfg->>'hard_min')::int, 2) and p_sent >= coalesce((p_cfg->>'hard_min_sent')::int, 20)
         and hl > coalesce((p_cfg->>'hard_limit')::numeric, 0.03) then 'hard'
    when p_policy >= coalesce((p_cfg->>'policy_min')::int, 2) and pl > coalesce((p_cfg->>'policy_limit')::numeric, 0.03) then 'policy'
    end;
  return jsonb_build_object('sent', p_sent, 'hard', p_hard, 'policy', p_policy, 'soft', p_soft, 'complaint', p_complaint,
    'hard_lb', hl, 'policy_lb', pl, 'soft_lb', sl, 'complaint_lb', cl, 'breach', v_breach,
    'soft_hold', p_sent > 0 and sl > coalesce((p_cfg->>'soft_hold_limit')::numeric, 0.15));
end $function$;

-- the judgement: the live body with the 'checked' segment read as eligibility reads it and the burst count below the sample
create or replace function public.fn_invite_bounce_judgement(p_now timestamp with time zone DEFAULT now(), p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_bounce_judge'), '{}'::jsonb);
  v_from timestamptz := coalesce(p_since, p_now - make_interval(days => coalesce((v_cfg->>'window_days')::int, 14)));
  v_day timestamptz := ((p_now at time zone 'Asia/Dubai')::date)::timestamp at time zone 'Asia/Dubai';
  v_reach boolean := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_reachable_only'), false);
  v_cells jsonb := '{}'::jsonb; v_today jsonb := '{}'::jsonb; v_all jsonb; v_today_all jsonb; r record;
  v_company text; v_held text[] := '{}'; v_why text; v_sent_segments text[]; v_rows jsonb; v_segall jsonb;
begin
  -- the sends being judged, read once into one array (a STABLE routine: no temporary table): EVERY supplier campaign mail
  -- (fn_invite_campaign_types), not only the invitation. The send's own provider code is read on each; the lead's mark
  -- (bounced / complained, written by the webhook with no code) is read only on the lead's LAST campaign send, so one mark
  -- is one event, not one per mail the lead received.
  select coalesce(jsonb_agg(jsonb_build_object(
           'c', coalesce(public.fn_mail_provider_of_email(x.to_email), 'other'),
           's', x.seg,
           'k', public.fn_invite_bounce_kind(x.provider_error_code, x.provider_status, case when x.last_send then x.invite_status end),
           't', x.sent_at >= v_day)), '[]'::jsonb)
    into v_rows
    from (select n.to_email, n.provider_error_code, n.provider_status, n.sent_at, l.invite_status,
                 -- 19 Nov 2026 (ceo): 'checked' is the population the company sends now: an invitation to an address with evidence
                 -- (fn_invite_address_has_evidence, as eligibility), or a nudge, which goes only to an address the invitation reached
                 case when public.fn_invite_address_has_evidence(l.email_verified) or n.type <> 'supplier_invite' then 'checked' else 'unchecked' end as seg,
                 n.id = (select n2.id from public.notifications n2
                          where n2.lead_id = n.lead_id and n2.type = any (public.fn_invite_campaign_types())
                            and n2.sent_at is not null and n2.sent_at <= p_now
                          order by n2.sent_at desc, n2.id desc limit 1) as last_send
            from public.notifications n join public.leads l on l.id = n.lead_id
           where n.type = any (public.fn_invite_campaign_types()) and n.sent_at is not null and n.sent_at > v_from and n.sent_at <= p_now
             and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email)) x;

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

  -- ANY COMPLAINT stops the company, whatever its segment, class or sample (review item 2: a person pressed spam; never noise,
  -- and never a matter of how many others were mailed: the lower bound let one complaint pass at 74 sends). Not read from the
  -- config, so no seat can relax it there.
  if coalesce((v_all->>'complaint')::int, 0) > 0 then
    v_company := 'complaint'; v_why := (v_all->>'complaint') || ' spam complaint(s) on ' || (v_all->>'sent') || ' supplier campaign e-mail(s) in the '
      || coalesce((v_cfg->>'window_days')::int, 14) || '-day window: any complaint stops the company';
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
      -- a burst below the minimum sample still stops it: hard_burst (3) hard bounces in one Dubai day (19 Nov 2026)
      if v_today_all->>'breach' = 'hard' or coalesce((v_today_all->>'hard')::int, 0) >= coalesce((v_cfg->>'hard_burst')::int, 3) then
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
end $function$;

-- ── 5. THE CEO RESTARTS ON THE ADDRESSES THE COMPANY NOW SENDS TO ───────────────────────────────────────────────────
-- The bounce rate of the last p_days of invitations (first invitations only; real leads) to addresses with evidence: the rate the
-- new eligibility would have had. Any bounce kind counts (hard, policy, soft); a complaint is the judgement's, never a rate here.
create or replace function public.fn_invite_restart_projection(p_now timestamp with time zone default now(), p_days integer default null)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with cfg as (select coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_bounce_judge'), '{}'::jsonb) as c),
  k as (select coalesce(p_days, (c->>'restart_days')::int, 30) as days, coalesce((c->>'restart_max_rate')::numeric, 0.03) as max_rate,
               coalesce((c->>'restart_min_sent')::int, 20) as min_sent, coalesce((c->>'z')::numeric, 1.645) as z from cfg),
  s as (select public.fn_invite_address_has_evidence(l.email_verified) as ev,
               public.fn_invite_bounce_kind(n.provider_error_code, n.provider_status, l.invite_status) as kind
          from public.notifications n join public.leads l on l.id = n.lead_id, k
         where n.type = 'supplier_invite' and n.sent_at is not null
           and n.sent_at > p_now - make_interval(days => k.days) and n.sent_at <= p_now
           and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email)),
  t as (select (count(*) filter (where ev))::int as sent,
               (count(*) filter (where ev and kind in ('hard', 'policy', 'soft')))::int as bounced,
               (count(*) filter (where ev and kind = 'hard'))::int as hard,
               count(*)::int as all_sent, (count(*) filter (where kind in ('hard', 'policy', 'soft')))::int as all_bounced
          from s)
  select jsonb_build_object('at', p_now, 'days', k.days, 'sent', t.sent, 'bounced', t.bounced, 'hard', t.hard,
           'rate', round(t.bounced::numeric / nullif(t.sent, 0), 4),
           'lower_bound', public.fn_invite_wilson_lower(t.bounced, t.sent, k.z),
           'all_sent', t.all_sent, 'all_bounced', t.all_bounced, 'all_rate', round(t.all_bounced::numeric / nullif(t.all_sent, 0), 4),
           'max_rate', k.max_rate, 'min_sent', k.min_sent,
           'ok', coalesce(t.sent >= k.min_sent and t.bounced::numeric / nullif(t.sent, 0) < k.max_rate, false),
           'why', case
             when t.sent < k.min_sent then 'only ' || t.sent || ' invitation(s) to checked addresses in the last ' || k.days
                                           || ' days: too few to project a bounce rate (needs ' || k.min_sent || ')'
             when t.bounced::numeric / nullif(t.sent, 0) >= k.max_rate then 'the checked addresses bounced ' || t.bounced || ' of ' || t.sent || ' ('
                  || round(t.bounced::numeric * 100 / nullif(t.sent, 0), 1) || '%) in the last ' || k.days || ' days: not under ' || round(k.max_rate * 100, 1) || '%'
             end)
    from t, k
$fn$;
revoke execute on function public.fn_invite_restart_projection(timestamp with time zone, integer) from public, anon, authenticated;
comment on function public.fn_invite_restart_projection(timestamp with time zone, integer) is 'The bounce rate of the last 30 days of invitations to addresses with evidence (fn_invite_address_has_evidence) and whether it is under the CEO''s restart limit (invite_bounce_judge restart_max_rate 3% on restart_min_sent 20). fn_ceo_restarts_invites refuses without it. invitations_go_only_to_addresses_that_were_checked.sql';

-- the CEO's restart: the live body with the projection as one more refusal and in its evidence, nothing else changed
create or replace function public.fn_ceo_restarts_invites(p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare b public.invite_brake; j jsonb; v_limit numeric := public.fn_growth_limit('ceo_invite_restarts_per_30d'); v_used int;
  v_suppressed int; v_batch int; v_refuse text;
  -- 19 Nov 2026 (ceo, ruling 1455): a restart needs the addresses the company now sends to measured under the restart limit
  v_proj jsonb := public.fn_invite_restart_projection(now());
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
    when not coalesce((v_proj->>'ok')::boolean, false) then coalesce(v_proj->>'why', 'the projected bounce rate of the checked addresses could not be read')
    when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
    when coalesce((j->'all'->>'complaint')::int, 0) > 0 then 'a person complained in the judgement window: never restarted over a complaint'
    when exists (select 1 from public.it_watch_finding f where f.detector_key = 'deliverability:supplier_invite' and f.status = 'open'
                  and f.state = 'paused' and f.evidence->>'paused_by' not in ('invite_same_day_brake', 'invite_bounce_judge')) then 'another seat''s pause is open'
    when now() < b.fired_at + interval '24 hours' then 'the brake is not 24 hours old yet (until ' || to_char((b.fired_at + interval '24 hours') at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || 'Z)'
    end;
  if v_refuse is not null then
    insert into public.invite_brake_decision (brake_id, decision, actor, reason, evidence)
    values (b.id, 'restart_refused', 'ceo', 'Restart refused: ' || v_refuse, jsonb_build_object('asked_reason', p_reason, 'judgement', j, 'used', v_used, 'limit', v_limit, 'projection', v_proj));
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
  values (b.id, 'restart', 'ceo', btrim(p_reason), jsonb_build_object('judgement', j, 'used_before', v_used, 'limit', v_limit, 'suppressed', v_suppressed, 'first_batch', v_batch, 'projection', v_proj));
  insert into public.agent_runs(agent, status, counts, note, finished_at)
  values ('ceo', 'ok', jsonb_build_object('action', 'invite_restart', 'brake', b.id, 'batch', v_batch, 'suppressed', v_suppressed, 'used', v_used + 1, 'limit', v_limit),
          left('The CEO restarted the supplier invitations: ' || btrim(p_reason), 500), now());
  return jsonb_build_object('ok', true, 'brake', b.id, 'first_batch', v_batch, 'suppressed', v_suppressed, 'used', v_used + 1, 'limit', v_limit);
end $function$;

-- ── 6. THE FUNNEL COUNTS FIRST INVITATIONS AS SENDS; NUDGES HAVE THEIR OWN COLUMN ───────────────────────────────────
alter table public.ceo_supplier_funnel_daily add column if not exists nudges_sent integer not null default 0;
comment on column public.ceo_supplier_funnel_daily.nudges_sent is 'Follow-ups to an invitation that were sent that day (supplier_invite_nudge: day 3/7/14 and the last note). Not in sent or delivered, which count first invitations only (19 Nov 2026). invitations_go_only_to_addresses_that_were_checked.sql';

-- the refresh: the live body with nudges out of sent and delivered and into nudges_sent
create or replace function public.fn_ceo_supplier_funnel_refresh(p_from date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_n int;
begin
  delete from public.ceo_supplier_funnel_daily where day >= p_from;
  with real_lead as (
    select l.id, l.invite_status, l.owner_email_verified, l.claimed, l.invite_clicked_at, l.portal_updated_at,
           l.registration_submitted_at, l.approved_at,
           coalesce((select case when n.type = 'supplier_invite_wa' then 'whatsapp' else 'email' end from public.notifications n
                      where n.lead_id = l.id and n.type in ('supplier_invite', 'supplier_invite_wa') and n.status = 'sent'
                      order by n.sent_at limit 1), 'direct') as channel
      from public.leads l
     where not coalesce(l.is_demo, false) and coalesce(l.company_name, '') not ilike 'ZZ DEMO%'
       and not public.fn_is_demo_email(coalesce(l.email, ''))
       and (l.invite_status is not null or l.claimed or l.registration_submitted_at is not null or l.approved_at is not null)
  ), ev as (
    select (n.sent_at at time zone 'Asia/Dubai')::date as day,
           case when n.type = 'supplier_invite_wa' then 'whatsapp' else 'email' end as channel,
           -- 19 Nov 2026 (ceo): a send is the FIRST invitation; a nudge (the day 3/7/14 follow-up and the last note) is its own column.
           -- It read 190 sent and 174 delivered for 150 invitations, 134 of them delivered, because the 40 nudges counted as sends.
           case when n.type = 'supplier_invite_nudge' then 0 else 1 end as sent,
           case when n.type = 'supplier_invite_nudge' or r.invite_status = 'bounced' then 0 else 1 end as delivered,
           0 as replied, 0 as started, 0 as submitted, 0 as approved,
           case when n.type = 'supplier_invite_nudge' then 1 else 0 end as nudges
      from public.notifications n join real_lead r on r.id = n.lead_id
     where n.type in ('supplier_invite', 'supplier_invite_nudge', 'supplier_invite_wa') and n.status = 'sent' and n.sent_at is not null
    union all
    -- one reply per lead per day. ponytail: email replies only; a WhatsApp reply becomes an invite.reply handoff and is counted once that channel has run.
    select d.day, r.channel, 0, 0, 1, 0, 0, 0, 0
      from (select distinct i.lead_id, (i.created_at at time zone 'Asia/Dubai')::date as day from public.inbound_messages i
             where i.lead_id is not null and coalesce(i.from_email, '') not ilike '%@quotesdone.com'
               and coalesce(i.from_email, '') not ilike '%@mail.quotesdone.com') d
      join real_lead r on r.id = d.lead_id
    union all
    select (coalesce(r.invite_clicked_at, r.portal_updated_at) at time zone 'Asia/Dubai')::date, r.channel, 0, 0, 0, 1, 0, 0, 0
      from real_lead r where (r.owner_email_verified or coalesce(r.claimed, false)) and coalesce(r.invite_clicked_at, r.portal_updated_at) is not null
    union all
    select (r.registration_submitted_at at time zone 'Asia/Dubai')::date, r.channel, 0, 0, 0, 0, 1, 0, 0 from real_lead r where r.registration_submitted_at is not null
    union all
    select (r.approved_at at time zone 'Asia/Dubai')::date, r.channel, 0, 0, 0, 0, 0, 1, 0 from real_lead r where r.approved_at is not null
  ), ins as (
    insert into public.ceo_supplier_funnel_daily (day, channel, sent, delivered, replied, started, submitted, approved, nudges_sent)
    select e.day, e.channel, sum(e.sent), sum(e.delivered), sum(e.replied), sum(e.started), sum(e.submitted), sum(e.approved), sum(e.nudges)
      from ev e where e.day >= p_from group by e.day, e.channel
    returning 1)
  select count(*) into v_n from ins;
  return v_n;
end $function$;

-- the whole history again, as the CEO's daily number does (a late bounce changes an old day)
select public.fn_ceo_supplier_funnel_refresh(date '2026-01-01');

-- ── 7. THE 37 STRANDED LEADS GO BACK TO NEVER INVITED ───────────────────────────────────────────────────────────────
-- queued, with only a cancelled never-sent invitation behind them; their ids and old stamps are kept in the agent_runs row
with s as (
  select l.id, l.invited_at as was_invited_at
    from public.leads l
   where l.invite_status = 'queued' and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
     and exists (select 1 from public.notifications n
                  where n.lead_id = l.id and n.type = 'supplier_invite' and n.status = 'cancelled' and n.sent_at is null)
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and (n.lead_id = l.id or lower(btrim(n.to_email)) = lower(btrim(l.email)))
                        and (n.status is distinct from 'cancelled' or n.sent_at is not null))
), u as (
  update public.leads l set invite_status = null, invited_at = null
    from s where l.id = s.id
  returning l.id, s.was_invited_at
)
insert into public.agent_runs (agent, status, counts, note, finished_at)
select 'ceo', 'ok',
       jsonb_build_object('action', 'invite_stranded_release', 'released', count(*),
                          'lead_ids', coalesce(jsonb_agg(u.id order by u.id), '[]'::jsonb),
                          'was_invited_at', coalesce(jsonb_object_agg(u.id::text, u.was_invited_at), '{}'::jsonb),
                          'file', 'invitations_go_only_to_addresses_that_were_checked.sql'),
       'The CEO released ' || count(*) || ' lead(s) queued behind an invitation that was cancelled before it left (brake 51, the lane '
       || 'cap): invite_status and invited_at back to null, so the next batch takes each under every rule of the day.', now()
  from u;


-- ── 8. THE CEO'S DECISION: RESTART ON THE CHECKED ADDRESSES, OR STAY OFF AND SAY WHY ────────────────────────────────
-- Rulings 1455 and 1696: the cap and the restart are the CEO's, on measured sender health. The restart goes through
-- fn_ceo_restarts_invites (its limit of 2 in 30 days, no complaint, 24 hours after the brake, bounced addresses suppressed, the
-- projection above); this block only asks it, sets the cap to the ramp's start when it restarted, and records the decision.
do $ceo$
declare
  v_brake public.invite_brake; v_proj jsonb := public.fn_invite_restart_projection(now());
  v_then jsonb; v_res jsonb; v_reason text; v_choice text; v_ok boolean := false;
  v_cap_before text := (select value from public.app_secrets where key = 'invite_daily_cap');
  v_cap int := least(coalesce((select (nullif(value, '')::jsonb->>'base_cap')::int from public.app_secrets where key = 'invite_warmup'), 20),
                     public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date));
begin
  select * into v_brake from public.invite_brake where resumed_at is null order by id desc limit 1;
  if not found then
    return;   -- nothing is stopped (the CEO's review restarted it first): there is no decision to take here
  end if;
  v_then := public.fn_invite_bounce_judgement(v_brake.fired_at);
  v_reason := format('Restart on checked addresses only (rulings 1455, 1486, 1696). In the last %s days the invitations to addresses with '
    || 'evidence (verified, maps, social) bounced %s of %s (%s%%), under the %s%% restart limit; the unchecked sources that bounced (web_scrape '
    || '''true'' and the directory rows) are out of eligibility. Brake %s fired on "%s"; re-judged with a minimum sample of 20 it is %s. '
    || 'Cap set to the ramp start, %s a day (ceiling 50), first batch at most 10.',
    v_proj->>'days', v_proj->>'bounced', v_proj->>'sent', round(coalesce((v_proj->>'rate')::numeric, 0) * 100, 1),
    round((v_proj->>'max_rate')::numeric * 100, 1), v_brake.id, v_brake.why,
    case when coalesce((v_then->>'company_brake')::boolean, false) then 'still a brake' else 'no brake' end, v_cap);
  v_res := public.fn_ceo_restarts_invites(v_reason);
  v_ok := coalesce((v_res->>'ok')::boolean, false);
  if v_ok then
    update public.app_secrets set value = v_cap::text where key = 'invite_daily_cap' and value is distinct from v_cap::text;
    v_choice := 'restart_on_checked_addresses';
  else
    v_choice := 'hold';
    v_reason := 'Held: the restart was refused: ' || coalesce(v_res->>'reason', 'no reason returned') || '. Invitations stay off; the cap stays at '
      || coalesce(v_cap_before, '-') || '. Asked: ' || v_reason;
  end if;
  insert into public.ceo_own_decision (world, source, subject, choice, reason, reading, dedupe_key)
  values ('real', 'standing', 'supplier invitations after brake ' || v_brake.id, v_choice, left(v_reason, 2000),
          jsonb_build_object('projection', v_proj, 'restart', v_res, 'brake', v_brake.id, 'brake_why', v_brake.why,
                             'rejudged_at_brake', jsonb_build_object('company_brake', v_then->'company_brake', 'why', v_then->'why',
                                                                     'sent_segment_all', v_then->'sent_segment_all', 'today', v_then->'today'),
                             'cap_before', v_cap_before, 'cap_after', case when v_ok then v_cap::text else v_cap_before end,
                             'rulings', jsonb_build_array(1455, 1231, 1486, 1696), 'file', 'invitations_go_only_to_addresses_that_were_checked.sql'),
          'invite_restart:checked_addresses_only:brake_' || v_brake.id)
  on conflict (dedupe_key) do nothing;
end $ceo$;


-- ── 9. THE PROBE: light SELECTs over what this file left, the last statement, one verdict row ─────────────────────────
-- It runs the routines (eligibility, the candidates, the judgement replayed at brake 51, the cell rule) rather than reading their
-- text. It writes nothing; the file above wrote no notification, and this proves it from the id read at the start.
with cfg as (select coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_bounce_judge'), '{}'::jsonb) as c),
elig as materialized (
  select l.id, coalesce(l.email_verified, '(none)') as ev, coalesce(l.source, '(none)') as src,
         public.fn_mail_provider_of_email(l.email) as cls
    from public.leads l where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))),
by_src as (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) as j from (select ev || '/' || src as k, count(*) as n from elig group by 1) x),
by_ev as (select count(*) filter (where public.fn_invite_address_has_evidence(ev)) as with_ev,
                 count(*) filter (where not public.fn_invite_address_has_evidence(ev)) as without_ev,
                 count(*) filter (where ev = 'true') as ev_true, count(*) filter (where src like 'uaecsd%') as directory,
                 count(*) filter (where cls = 'google') as google from elig),
ready as materialized (select c.lead_id from public.fn_supplier_invite_candidates(5000, array['google']::text[]) c),
ready_src as (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) as j, coalesce(sum(n), 0)::int as n
                from (select coalesce(l.email_verified, '(none)') as k, count(*) as n from ready r join public.leads l on l.id = r.lead_id group by 1) x),
cell as (select public.fn_invite_judge_cell(6, 2, 0, 0, 0, c) as six, public.fn_invite_judge_cell(20, 3, 0, 0, 0, c) as twenty from cfg),
replay as (select public.fn_invite_bounce_judgement(b.fired_at) as j from public.invite_brake b where b.id = 51),
rel as (select a.counts from public.agent_runs a
         where a.agent = 'ceo' and a.counts->>'action' = 'invite_stranded_release'
           and a.counts->>'file' = 'invitations_go_only_to_addresses_that_were_checked.sql'
         order by a.id desc limit 1),
rel_ids as (select (jsonb_array_elements_text(rel.counts->'lead_ids'))::bigint as id from rel),
rel_read as (
  select count(*) as n,
         count(*) filter (where r.id in (select id from elig)) as eligible_again,
         count(*) filter (where r.id in (select lead_id from ready)) as in_ready_pool,
         count(*) filter (where r.id not in (select id from elig) and not public.fn_invite_address_has_evidence(l.email_verified)) as no_evidence,
         count(*) filter (where r.id not in (select id from elig) and public.fn_invite_address_has_evidence(l.email_verified)) as other_rule,
         count(*) filter (where l.invite_status is not null or l.invited_at is not null) as not_reset,
         count(*) filter (where exists (select 1 from public.notifications n where n.type = 'supplier_invite'
                                         and lower(btrim(n.to_email)) = lower(btrim(l.email))
                                         and (n.status is distinct from 'cancelled' or n.sent_at is not null))) as still_counted
    from rel_ids r join public.leads l on l.id = r.id),
stranded_left as (
  select count(*) as n from public.leads l
   where l.invite_status = 'queued' and not coalesce(l.is_demo, false)
     and exists (select 1 from public.notifications n where n.lead_id = l.id and n.type = 'supplier_invite' and n.status = 'cancelled' and n.sent_at is null)
     and not exists (select 1 from public.notifications n where n.type = 'supplier_invite' and n.lead_id = l.id
                      and (n.status is distinct from 'cancelled' or n.sent_at is not null))),
real_inv as (
  select n.type, l.invite_status from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type in ('supplier_invite', 'supplier_invite_nudge', 'supplier_invite_wa') and n.status = 'sent' and n.sent_at is not null
     and not coalesce(l.is_demo, false) and coalesce(l.company_name, '') not ilike 'ZZ DEMO%' and not public.fn_is_demo_email(coalesce(l.email, ''))
     and (l.invite_status is not null or l.claimed or l.registration_submitted_at is not null or l.approved_at is not null)),
want as (select count(*) filter (where type <> 'supplier_invite_nudge')::int as sent,
                count(*) filter (where type <> 'supplier_invite_nudge' and invite_status is distinct from 'bounced')::int as delivered,
                count(*) filter (where type = 'supplier_invite_nudge')::int as nudges,
                not exists (select 1 from public.notifications n where n.type in ('supplier_invite', 'supplier_invite_nudge')
                             and n.sent_at >= timestamptz '2026-11-19 00:00Z') as frozen from real_inv),
fun as (select coalesce(sum(sent), 0)::int as sent, coalesce(sum(delivered), 0)::int as delivered, coalesce(sum(nudges_sent), 0)::int as nudges
          from public.ceo_supplier_funnel_daily),
mine as (select count(*)::int as n from public.notifications
          where id > coalesce(nullif(current_setting('qd.invite_checked_n0', true), ''), '0')::bigint and created_at = now()),
dec as (select d.choice, d.reason from public.ceo_own_decision d where d.dedupe_key like 'invite_restart:checked_addresses_only:brake_%'
         order by d.id desc limit 1),
sw as (select (select value from public.app_secrets where key = 'invite_enabled') as enabled,
              (select value from public.app_secrets where key = 'invite_daily_cap') as cap,
              least(coalesce((select (nullif(value, '')::jsonb->>'base_cap')::int from public.app_secrets where key = 'invite_warmup'), 20),
                    public.fn_invite_founder_cap((now() at time zone 'Asia/Dubai')::date))::text as start_cap,
              exists (select 1 from public.invite_brake where resumed_at is null) as brake_open),
proj as (select public.fn_invite_restart_projection(now()) as p),
idx as (select pg_get_indexdef('public.notifications_supplier_invite_once_uidx'::regclass) as d,
               exists (select 1 from pg_trigger where tgname = 'z82_notifications_a_cancelled_invitation_frees_its_lead'
                         and tgrelid = 'public.notifications'::regclass) as trg),
f as (
  select array_remove(array[
    case when e.ev_true > 0 or e.without_ev > 0 then 'eligibility still takes ' || e.without_ev || ' address(es) without evidence (' || e.ev_true || ' ''true'')' end,
    case when e.with_ev = 0 then 'no address with evidence is eligible: the rule shut the pool' end,
    case when rs.n = 0 then 'the google ready pool (fn_supplier_invite_candidates) is empty' end,
    case when rs.j ? 'true' or rs.j ? '(none)' then 'the ready pool holds an unchecked address: ' || rs.j::text end,
    case when (c.six->>'breach') is not null then 'a 2-of-6 cell still breaches: ' || c.six::text end,
    case when coalesce(c.twenty->>'breach', '') <> 'hard' then 'control: 3 hard of 20 (the 4 Nov burst) no longer breaches: ' || c.twenty::text end,
    case when coalesce((rp.j->>'company_brake')::boolean, true) then 'brake 51 replayed still brakes: ' || coalesce(rp.j->>'why', '-') end,
    case when coalesce((rr.n), 0) <> 37 and sl.n > 0 then 'released ' || coalesce(rr.n, 0) || ' and ' || sl.n || ' still stranded' end,
    case when sl.n > 0 then sl.n || ' lead(s) still queued behind a cancelled invitation' end,
    case when coalesce(rr.not_reset, 0) > 0 then rr.not_reset || ' released lead(s) still carry invite_status or invited_at' end,
    case when coalesce(rr.still_counted, 0) > 0 then rr.still_counted || ' released lead(s) still counted as invited by the never-twice test' end,
    case when coalesce(rr.n, 0) <> coalesce(rr.eligible_again, 0) + coalesce(rr.no_evidence, 0) + coalesce(rr.other_rule, 0) then 'the released leads do not add up' end,
    case when fu.sent <> w.sent or fu.delivered <> w.delivered or fu.nudges <> w.nudges then 'the funnel reads ' || fu.sent || '/' || fu.delivered || '/' || fu.nudges
         || ' (sent/delivered/nudges), the outbox ' || w.sent || '/' || w.delivered || '/' || w.nudges end,
    case when w.frozen and (fu.sent <> 150 or fu.delivered <> 134) then 'no send since 19 Nov, yet the funnel is not 150/134: ' || fu.sent || '/' || fu.delivered end,
    case when m.n > 0 then 'this file queued ' || m.n || ' notification(s)' end,
    case when i.d !~ 'cancelled' then 'the once-only index still counts a cancelled invitation: ' || i.d end,
    case when not i.trg then 'the trigger that frees a lead behind a cancelled invitation is missing' end,
    case when dc.choice = 'restart_on_checked_addresses' and (s.enabled <> 'true' or s.cap <> s.start_cap or s.brake_open)
         then 'the CEO restarted but invite_enabled=' || s.enabled || ', cap=' || s.cap || ' (start ' || s.start_cap || '), brake open=' || s.brake_open end,
    case when dc.choice = 'hold' and s.enabled = 'true' then 'the CEO held but invite_enabled is true' end,
    case when dc.choice is null and s.brake_open then 'a brake is open and no CEO decision was recorded' end,
    case when dc.choice = 'restart_on_checked_addresses' and not coalesce((p.p->>'ok')::boolean, false) then 'restarted on a projection that is not under the limit' end
  ], null) as fails
  from by_ev e, ready_src rs, cell c, replay rp, stranded_left sl, want w, fun fu, mine m, idx i, sw s, proj p
  left join rel_read rr on true left join dec dc on true)
select case when cardinality(f.fails) = 0 then 'PROBE OK: ' else 'PROBE FAILED: ' || array_to_string(f.fails, '; ') || ' || ' end
    || 'decision ' || coalesce(dc.choice, '(none: no brake open)') || ', invite_enabled ' || s.enabled || ', cap ' || s.cap
    || '; projection ' || (p.p->>'bounced') || '/' || (p.p->>'sent') || ' checked in ' || (p.p->>'days') || ' days (all sources '
    || (p.p->>'all_bounced') || '/' || (p.p->>'all_sent') || ')'
    || '; eligible ' || e.with_ev || ' with evidence, ' || e.without_ev || ' without (' || e.google || ' google); google ready pool ' || rs.n || ' ' || rs.j::text
    || '; cell 2/6 breach ' || coalesce(c.six->>'breach', 'none') || ', 3/20 ' || coalesce(c.twenty->>'breach', 'none')
    || '; brake 51 replayed: company_brake ' || coalesce(rp.j->>'company_brake', '-') || ', today ' || coalesce((rp.j->'today')::text, '-')
    || '; released ' || coalesce(rr.n, 0) || ': eligible again ' || coalesce(rr.eligible_again, 0) || ' (in the google pool ' || coalesce(rr.in_ready_pool, 0)
    || '), no evidence ' || coalesce(rr.no_evidence, 0) || ', another rule ' || coalesce(rr.other_rule, 0)
    || '; funnel ' || fu.sent || ' sent / ' || fu.delivered || ' delivered / ' || fu.nudges || ' nudges'
    || '; notifications queued by this file ' || m.n
    || '; eligible by source ' || bs.j::text as verdict
  from f, by_ev e, by_src bs, ready_src rs, cell c, replay rp, want w, fun fu, mine m, sw s, proj p
  left join rel_read rr on true left join dec dc on true;
