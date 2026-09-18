-- CONFIGURATION THAT IS MISSING IS RECORDED ONCE, NOT EVERY TICK.
--
-- Assigned: it_engineer. Founder, 17 Sep 2026: "Can you also check the IT engineer issues? He has been
-- sharing with me on the email. So that we keep fixing these so they never come up again."
--
-- WHAT WAS MEASURED, 18 Sep 2026 04:13 UTC, before anything was written:
--   * public.it_engineer_finding has 60 open rows and alerted_at is NULL on all 60. The two loudest,
--     duty:renewal:domain:quotesdone.ae:date_unknown and duty:renewal:token:meta_marketing:date_unknown,
--     have been re-raised 320 times each since 14 Sep; the five duty:usage_*:cap_unknown:* rows 77-79
--     times each. NONE of them has ever emailed the founder - they are 'internal' blast, affected 0, so
--     the loop keeps them quiet. They are ledger noise, not mail. The mail he actually received is a
--     different set (45 of his 66 sent emails were one Dropbox coverage burst on 14 Sep).
--   * public.it_threshold DOES hold all five cap/floor rows. Their VALUE is null, not the row missing.
--   * public.it_expiry.token:meta_marketing was last checked_at 14 Sep, five days stale, while the
--     hourly reading has been running the whole time.
--
-- THE THREE CAUSES, AND WHAT EACH ONE REALLY IS:
--
-- 1. A MEASURED FACT WITH NO CONSUMER. supabase/functions/_shared/it_duty_readings.ts has emitted
--    `never_expires: true` for a token whose Meta debug_token answers expires_at 0 since it was written.
--    Nothing anywhere reads that key - the ingest in fn_it_duties only acts `if expires_on is not null`.
--    So the one fact that settles the Meta token was measured hourly and thrown away hourly, and the
--    ledger went on saying the date is not known. it_expiry gains the column, fn_it_expiry_measured
--    stores it from the readings the tick ALREADY takes (no new HTTP call), and fn_it_renewal_watch
--    stops asking for a renewal date for a thing that never expires.
--
-- 2. A DETECTOR THAT RE-FIRES EVERY TICK OVER MISSING CONFIGURATION IS ITSELF A DEFECT. "No cap is
--    recorded" and "the renewal date is not known" are facts about the LEDGER, not about the running
--    system: nothing changes between one tick and the next, so bumping seen_count 320 times records
--    nothing and buries the findings that did move. fn_it_duty_settle now recognises a configuration
--    item and records it ONCE: the key is still returned, so the sweep does not close it and the gap
--    stays open until someone fills it, but an already-open configuration finding is left untouched -
--    same row, same seen_count, same last_seen_at. A configuration item is one whose key carries
--    cap_unknown: or ends in :date_unknown, or one whose producer says so with 'config', true. Both
--    existing producers are already named that way, so neither had to change.
--
-- 3. CAPS THAT COULD BE MEASURED, AND CAPS THAT COULD NOT. Measured here: the Supabase organisation is
--    on plan "pro" (GET /v1/organizations/phdxkqvlbxpjycieyzfi, 18 Sep 2026), whose included storage
--    allowance is 100 GB; the reading on the same day was 34 GB, 32% of it, well under the 80% warn
--    ratio. That cap is recorded. The other four are NOT invented here and stay open as one-shot
--    findings for the accountant, because each needs a fact this seat cannot measure:
--      cap_resend_emails_month / _day  the Resend API publishes no plan quota; the plan page does
--      cap_vercel_charges_month        a monthly budget is the founder's and the accountant's, not a
--                                      provider limit that can be read
--      floor_twilio_balance            it_spend_daily records twilio 0.00 USD on every day it holds and
--                                      0 SMS were sent in 30 days, so no measured send rate supports a
--                                      floor; a number chosen now would only be a number that stops an
--                                      alarm
--      domain:quotesdone.ae            RDAP has no server for .ae (that is why the row is dateless); the
--                                      registrar page is the source, and the accountant holds it
--
-- NOT TOUCHED, AND DELIBERATELY SO: the heartbeat, journey, db_health, smoke and table_export classes
-- and the org_tasks consumer are being fixed by other seats in parallel tonight. Their findings are the
-- other 51 open rows and none of them is configuration.

-- ── 1. A thing that never expires is a fact, not an unknown date ──────────────────────────────────
alter table public.it_expiry add column if not exists never_expires boolean not null default false;
comment on column public.it_expiry.never_expires is
  'True when the provider itself reports no expiry (Meta debug_token expires_at 0 on a system-user token). '
  'Measured by fn_it_expiry_measured from the hourly readings, never typed: a renewal date that is merely '
  'unknown stays NULL with never_expires false, and is a configuration finding for the accountant.';
alter table public.it_expiry drop constraint if exists it_expiry_never_expires_ck;
alter table public.it_expiry add constraint it_expiry_never_expires_ck
  check (not (never_expires and expires_on is not null));

-- fn_it_duties already ingests expires_on and drops never_expires on the floor. This takes the same
-- readings object and stores BOTH, so the fact arrives by measurement every hour instead of by anyone's
-- word. Called from resilience_ping's itDutiesTick with the readings it has already taken.
create or replace function public.fn_it_expiry_measured(p_expiries jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x record; n_date int := 0; n_never int := 0; n_seen int := 0;
begin
  if jsonb_typeof(coalesce(p_expiries, 'null'::jsonb)) is distinct from 'object' then
    raise exception 'fn_it_expiry_measured takes the expiries object from takeDutyReadings';
  end if;
  for x in select key, value from jsonb_each(p_expiries) loop
    -- A reading that was not taken settles nothing: an unreachable RDAP server must not clear a date.
    continue when x.value->>'basis' is distinct from 'measured';
    if (x.value->>'expires_on') is not null then
      update public.it_expiry
         set expires_on = (x.value->>'expires_on')::date, never_expires = false, checked_at = now()
       where item = x.key;
      if found then n_date := n_date + 1; end if;
    elsif coalesce((x.value->>'never_expires')::boolean, false) then
      -- The source line is written only on the transition, so a row that has been settled for months
      -- does not rewrite its own provenance with today's date on every tick.
      update public.it_expiry
         set never_expires = true, expires_on = null, checked_at = now(),
             source = left('the provider reports no expiry (measured '
                           || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || '): ' || source, 500)
       where item = x.key and never_expires is distinct from true;
      if found then n_never := n_never + 1; end if;
      update public.it_expiry set checked_at = now() where item = x.key;
    else
      -- Read, and the provider gave no date and did not say there is none: still unknown, but the row
      -- records that it was looked at today, so a stale checked_at means the reading stopped running.
      update public.it_expiry set checked_at = now() where item = x.key;
    end if;
    n_seen := n_seen + 1;
  end loop;
  return jsonb_build_object('read', n_seen, 'dated', n_date, 'never_expires', n_never);
end $fn$;
revoke execute on function public.fn_it_expiry_measured(jsonb) from public, anon, authenticated;

-- ── 2. A configuration gap is recorded once, and stays open until it is filled ────────────────────
-- Unchanged from the_it_engineer_runs_its_duties_every_hour.sql except for the config branch below.
create or replace function public.fn_it_duty_settle(p_duty text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; v_keys text[] := '{}'; v_key text; n_closed int := 0; v_open text; v_config boolean;
        n_held int := 0;
begin
  if coalesce(btrim(p_duty), '') = '' or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'fn_it_duty_settle(duty, items[]): a duty name and an array of failing items are required';
  end if;
  for x in select e from jsonb_array_elements(p_items) e loop
    if coalesce(btrim(x->>'item'), '') = '' or coalesce(btrim(x->>'title'), '') = '' then
      raise exception 'fn_it_duty_settle: every item needs an item key and a title (%)', x;
    end if;
    v_key := 'duty:' || p_duty || ':' || (x->>'item');
    v_keys := v_keys || v_key;

    -- A CONFIGURATION GAP IS NOT NEWS ON THE SECOND TICK. Nothing about the running system changed
    -- between one reading and the next; what is missing is a number or a date nobody has entered yet.
    -- The key stays in v_keys so the sweep below does NOT close it - the gap is still open, and closes
    -- the moment the cap or the date is recorded and the producer stops emitting the item. Recognised
    -- from the item key both producers already use, or from an explicit 'config' flag for future ones.
    v_config := coalesce((x->>'config')::boolean, false)
                or (x->>'item') ~ '(^|:)cap_unknown:' or (x->>'item') ~ ':date_unknown$';
    -- A CLOSED configuration finding is NOT held: it falls through to the upsert and reopens, because a
    -- gap that was filled and has come back is news. Only an already-open one is held.
    if v_config and exists (select 1 from public.it_engineer_finding f
                             where f.issue_key = v_key and f.closed_at is null) then
      -- The reading itself moves even though the gap does not: supabase storage was 34 GB when the
      -- finding was raised and will be more when somebody reads it. So the title and the evidence are
      -- refreshed to today's measurement while seen_count, last_seen_at and started_at stand still -
      -- the row says what is true now without claiming anything happened this tick.
      update public.it_engineer_finding f
         set title = left(x->>'title', 300),
             evidence = coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
               'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
               'demo', coalesce((x->>'demo')::boolean, false), 'reading_refreshed_at', now())
       where f.issue_key = v_key and f.closed_at is null;
      n_held := n_held + 1;
      continue;
    end if;

    perform public.fn_it_engineer_finding_upsert(v_key, x->>'title', 'IT engineer duty: ' || p_duty,
      coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
      coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
        'duty', p_duty, 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
        'demo', coalesce((x->>'demo')::boolean, false)),
      '{}'::text[], '{}'::text[], 'it_engineer.' || p_duty);
  end loop;
  for v_open in select issue_key from public.it_engineer_finding
                 where closed_at is null and issue_key like 'duty:' || p_duty || ':%' and not (issue_key = any (v_keys)) loop
    perform public.fn_it_engineer_finding_close(v_open, 'the ' || p_duty || ' duty no longer finds it');
    n_closed := n_closed + 1;
  end loop;
  return jsonb_build_object('duty', p_duty, 'failing', coalesce(array_length(v_keys, 1), 0),
                            'closed', n_closed, 'configuration_already_recorded', n_held);
end $fn$;

-- ── 3. The renewal watch stops asking for the renewal date of a thing that never expires ──────────
-- Unchanged from renewals_warn_the_accountant_at_sixty_and_thirty_days.sql except for the two marks
-- in section 3: `and not never_expires` on the loop, and 'config', true on the date_unknown item.
create or replace function public.fn_it_renewal_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; e public.it_expiry; v_window interval; v_rep jsonb; v_items jsonb := '[]'::jsonb;
  v_days int; v_stage int; n_closed int := 0; n_esc int := 0; v_key text;
begin
  select reply_within into v_window from public.seat_handoff_kind
   where type = 'renewal.due' and from_seat = 'it_engineer' and to_seat = 'accountant';
  -- The row is the accountant's build's; without it `created_at + NULL` would never escalate anything.
  v_window := coalesce(v_window, interval '3 days');

  -- 1. RE-VERIFY: a handoff closes when the date it was about has moved (the item was renewed).
  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'renewal.due' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    e := null;
    select * into e from public.it_expiry where item = h.detail->>'item';
    v_key := 'renewal:' || (h.detail->>'item') || '@' || (h.detail->>'expires_on');
    if e.item is null or e.expires_on is distinct from (h.detail->>'expires_on')::date then
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', case when e.item is null then 'the item is no longer watched'
                        else 'renewed: expiry moved from ' || (h.detail->>'expires_on') || ' to ' || coalesce(e.expires_on::text, 'unknown') end));
      perform set_config('qd.handoff_closer', '', true);
      -- A ceo report about this date is finished by the renewal, answered or not.
      begin
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'IT engineer re-verified: ' || (h.detail->>'item') || ' now expires ' || coalesce(e.expires_on::text, 'unknown') || ' (handoff ' || h.id || ').'
         where idempotency_key = v_key and status in ('sent', 'accepted');
      exception when others then null;  -- the handoff is closed either way; the report stays for the ceo
      end;
      n_closed := n_closed + 1;
    elsif not (h.detail ? 'escalated_report_id')
          and (h.detail->>'stage')::int = (select min(w) from unnest(e.warn_days) w)
          and now() > h.created_at + v_window then
      -- 2. ESCALATE: the last warning's window has passed and the date has not moved.
      v_rep := public.fn_support_report_to_ceo(
        v_key, 'serious',
        'Renewal not closed: ' || e.item || ' expires ' || e.expires_on || ' (' || (e.expires_on - current_date) || ' days)',
        jsonb_build_object('item', e.item, 'kind', e.kind, 'expires_on', e.expires_on, 'route', e.route, 'source', e.source,
                           'handoff_id', h.id, 'accountant_reply', h.evidence),
        jsonb_build_array(jsonb_build_object('action', 'accountant warned at ' || (h.detail->>'stage') || ' days', 'handoff_id', h.id,
                                             'at', h.created_at, 'replied_at', h.detail->>'replied_at')),
        'Renew it or direct who does. The IT engineer closes this only when it reads the new expiry date back.',
        p_review_in => interval '2 days', p_source_agent => 'it_engineer');
      if coalesce((v_rep->>'ok')::boolean, false) then
        update public.agent_actions
           set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
         where id = h.id;
        n_esc := n_esc + 1;
      else
        raise exception 'fn_it_renewal_watch: the ceo report for % was refused: %', e.item, v_rep->>'reason';
      end if;
    end if;
  end loop;

  -- 3. WARN: every item inside a stage gets its handoff; the ledger records what is due.
  -- A never_expires item is settled, not overdue: there is no renewal to arrange and no date to chase.
  for e in select * from public.it_expiry where kind <> 'tls' and not never_expires order by item loop
    if e.expires_on is null then
      v_items := v_items || jsonb_build_object('item', e.item || ':date_unknown', 'owner_seat', 'accountant', 'subject', e.item,
        'title', 'The renewal date of ' || e.item || ' is not known (' || e.source || ')',
        'blast', 'internal', 'affected', 0, 'config', true,
        'evidence', jsonb_build_object('route', e.route, 'source', e.source));
      continue;
    end if;
    v_days := e.expires_on - current_date;
    select min(w) into v_stage from unnest(e.warn_days) w where v_days <= w;
    continue when v_stage is null;
    v_items := v_items || jsonb_build_object('item', e.item, 'owner_seat', 'accountant', 'subject', e.item,
      'title', e.item || case when v_days < 0 then ' EXPIRED on ' || e.expires_on
                              else ' expires on ' || e.expires_on || ' (' || v_days || ' days): inside the ' || v_stage || '-day warning' end,
      -- quiet in the ledger while it is being renewed; an item past its date goes round the IT loop as well
      'blast', case when v_days < 0 then 'agent_facing' else 'internal' end, 'affected', case when v_days < 0 then 1 else 0 end,
      'evidence', jsonb_build_object('stage', v_stage, 'days_left', v_days, 'route', e.route, 'source', e.source));
    perform public.fn_seat_handoff('it_engineer', 'accountant', 'renewal.due', 'it_expiry',
      e.item || '@' || e.expires_on || '@' || v_stage,
      jsonb_build_object('item', e.item, 'kind', e.kind, 'expires_on', e.expires_on, 'days_left', v_days,
                         'stage', v_stage, 'route', e.route));
  end loop;
  return jsonb_build_object('renewal', public.fn_it_duty_settle('renewal', v_items), 'closed', n_closed, 'escalated', n_esc);
end $fn$;

-- ── 4. The seat that measured a cap may record it ─────────────────────────────────────────────────
-- Unchanged from the_it_engineer_watches_every_bill_before_its_cap.sql except that it_engineer joins the
-- list. The guard's point is that a cap names WHO recorded it and FROM WHAT; the seat that read the plan
-- out of the provider's own API is exactly such a source, and refusing it forced a guess or a silence.
create or replace function public.fn_it_cap_set(p_key text, p_value numeric, p_by text, p_source text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(p_key, '') !~ '^(cap|floor)_[a-z0-9_]+$' or p_key = 'cap_warn_ratio' then
    raise exception 'fn_it_cap_set sets a provider cap (cap_*) or floor (floor_*), not %', coalesce(p_key, 'nothing');
  end if;
  if p_by is null or p_by not in ('accountant', 'ceo', 'founder', 'it_engineer') then
    raise exception 'a cap is set by the accountant, the ceo, the founder or the it_engineer, not %', coalesce(p_by, 'nobody');
  end if;
  if coalesce(btrim(p_source), '') = '' then raise exception 'say where the cap comes from: the plan page or the invoice'; end if;
  if p_value is not null and p_value <= 0 then raise exception 'a cap must be above zero, or NULL for not recorded'; end if;
  update public.it_threshold
     set value = p_value,
         basis = left('set by the ' || p_by || ' on ' || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' from: ' || p_source, 500)
   where key = p_key;
  if not found then raise exception 'no cap % in public.it_threshold', p_key; end if;
  return jsonb_build_object('key', p_key, 'value', p_value, 'set_by', p_by);
end $fn$;

-- The one cap that could be read rather than asked for. 100 GB = 107374182400 bytes.
do $$
begin
  if (select value from public.it_threshold where key = 'cap_supabase_storage_bytes') is null then
    perform public.fn_it_cap_set('cap_supabase_storage_bytes', 107374182400, 'it_engineer',
      'Supabase management API GET /v1/organizations/phdxkqvlbxpjycieyzfi answered plan "pro" on 18 Sep 2026; '
      'the Pro plan includes 100 GB of file storage and bills per GB beyond it. Reading the same day: 34 GB (32%).');
  end if;
end $$;

-- ── 5. PROBE. This file defines things, so the probe cleans up after itself and ends in a notice ──
-- Named ZZ DEMO throughout and confined to a duty name and an it_expiry item no real reading produces,
-- so it cannot reach a real finding, a real renewal or a real person.
do $$
declare v_cfg int; v_ord int; v_i int; v_never boolean; v_exp date; v_left int; v_real int;
begin
  select count(*) into v_real from public.it_engineer_finding where issue_key like 'duty:zz_demo_settle:%';
  if v_real <> 0 then raise exception 'probe refuses to run: % duty:zz_demo_settle finding(s) already exist', v_real; end if;
  if exists (select 1 from public.it_expiry where item = 'ZZ DEMO token:probe') then
    raise exception 'probe refuses to run: ZZ DEMO token:probe already exists';
  end if;

  -- (a) a configuration item is recorded once; an ordinary item goes on counting.
  for v_i in 1..2 loop
    perform public.fn_it_duty_settle('zz_demo_settle', jsonb_build_array(
      jsonb_build_object('item', 'cap_unknown:zz_demo_metric', 'owner_seat', 'accountant', 'subject', 'zz_demo',
                         'title', 'ZZ DEMO probe: a configuration gap', 'blast', 'internal', 'affected', 0),
      jsonb_build_object('item', 'zz_demo_ordinary', 'owner_seat', 'accountant', 'subject', 'zz_demo',
                         'title', 'ZZ DEMO probe: an ordinary failing item', 'blast', 'internal', 'affected', 0)));
  end loop;
  select seen_count into v_cfg from public.it_engineer_finding
   where issue_key = 'duty:zz_demo_settle:cap_unknown:zz_demo_metric';
  select seen_count into v_ord from public.it_engineer_finding
   where issue_key = 'duty:zz_demo_settle:zz_demo_ordinary';
  if v_cfg is distinct from 1 then raise exception 'probe: a configuration finding was re-raised (seen_count %)', v_cfg; end if;
  if v_ord is distinct from 2 then raise exception 'probe: an ordinary finding stopped counting (seen_count %)', v_ord; end if;

  -- (b) the configuration finding is still OPEN and its reading is still today's: one-shot must mean
  -- neither closed-and-forgotten nor frozen at whatever was true the first time it was seen.
  if not exists (select 1 from public.it_engineer_finding
                  where issue_key = 'duty:zz_demo_settle:cap_unknown:zz_demo_metric' and closed_at is null) then
    raise exception 'probe: the configuration finding was closed by its own duty';
  end if;
  if not exists (select 1 from public.it_engineer_finding
                  where issue_key = 'duty:zz_demo_settle:cap_unknown:zz_demo_metric'
                    and evidence ? 'reading_refreshed_at') then
    raise exception 'probe: a held configuration finding kept a stale reading';
  end if;

  -- (c) a measured "no expiry" reading settles the row; a later real date un-settles it.
  insert into public.it_expiry (item, kind, expires_on, owner_seat, route, source)
  values ('ZZ DEMO token:probe', 'token', null, 'accountant', 'ZZ DEMO probe', 'ZZ DEMO probe');
  perform public.fn_it_expiry_measured(jsonb_build_object(
    'ZZ DEMO token:probe', jsonb_build_object('basis', 'measured', 'never_expires', true)));
  select never_expires, expires_on into v_never, v_exp from public.it_expiry where item = 'ZZ DEMO token:probe';
  if v_never is not true or v_exp is not null then
    raise exception 'probe: a measured no-expiry reading did not settle the row (never_expires %, expires_on %)', v_never, v_exp;
  end if;
  -- and it is then outside the renewal watch's own predicate, so no date is ever asked for again
  select count(*) into v_left from public.it_expiry
   where item = 'ZZ DEMO token:probe' and kind <> 'tls' and not never_expires;
  if v_left <> 0 then raise exception 'probe: a never_expires item is still inside the renewal warning loop'; end if;
  perform public.fn_it_expiry_measured(jsonb_build_object(
    'ZZ DEMO token:probe', jsonb_build_object('basis', 'measured', 'expires_on', '2030-01-01')));
  select never_expires, expires_on into v_never, v_exp from public.it_expiry where item = 'ZZ DEMO token:probe';
  if v_never is not false or v_exp is distinct from date '2030-01-01' then
    raise exception 'probe: a real date did not take over from never_expires (never_expires %, expires_on %)', v_never, v_exp;
  end if;
  -- and a reading that was NOT taken changes nothing
  perform public.fn_it_expiry_measured(jsonb_build_object(
    'ZZ DEMO token:probe', jsonb_build_object('basis', 'unavailable', 'reason', 'ZZ DEMO probe')));
  select expires_on into v_exp from public.it_expiry where item = 'ZZ DEMO token:probe';
  if v_exp is distinct from date '2030-01-01' then raise exception 'probe: an unread reading cleared a real date'; end if;

  -- CLEAN UP, and prove nothing was left behind.
  delete from public.it_engineer_finding where issue_key like 'duty:zz_demo_settle:%';
  delete from public.it_expiry where item = 'ZZ DEMO token:probe';
  select count(*) into v_left from public.it_engineer_finding where issue_key like 'duty:zz_demo_settle:%';
  if v_left <> 0 then raise exception 'probe: % demo finding(s) left behind', v_left; end if;
  select count(*) into v_left from public.it_expiry where item like 'ZZ DEMO%';
  if v_left <> 0 then raise exception 'probe: % demo expiry row(s) left behind', v_left; end if;

  raise notice 'PROBE OK: configuration recorded once (seen_count 1) and still open, ordinary item still counting (2), a measured no-expiry settles and un-settles, nothing left behind.';
end $$;
