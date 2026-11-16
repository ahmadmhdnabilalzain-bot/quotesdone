-- THE SUPPLIER OUTREACH DUTY NEVER SLOWS A SUPPLIER'S PAGE (it_engineer, 16 Nov 2026).
-- Assigned: it_engineer - the database's latency (the seat-duty scheduler and its load are its; the_seat_duty_jobs_are_spread_
-- over_the_five_minutes.sql). The invitation rules stay sales_engineer's and marketing's: nothing they decide changes here.
--
-- MEASURED (production, read-only SELECTs, 16 Nov 2026 05:00-05:20 UTC):
--   * The sign-up certification at 05:00 UTC loaded the supplier portal home in 9.2 s (budget 3 s; 21 of 23 other loads that
--     night 1.1-2.4 s). Edge logs: every supplier_api call 0.4-0.9 s until 05:00:00, then kyc 3.5 s, supplier_api 2.8 s and
--     6.3 s, supplier_portal dashboard 8.4 s.
--   * cron.job_run_details, 04:59:30-05:02: seat_duty:sales_engineer.supplier_outreach ran 05:00:01.1 -> 05:00:20.3, 19,199 ms.
--     The next longest job of those two minutes took 1,573 ms; the other 57 took 13-600 ms.
--   * The same job over 7 days: every run over 1 s is the 05:00 UTC run (09:00 Dubai, the routine's once-a-day open beat) of an
--     open weekday: 10 Nov 25,296 ms, 11 Nov 24,143 ms, 12 Nov 18,569 ms, 13 Nov 6,655 ms (0 queued), 16 Nov 19,199 ms. 14-15 Nov
--     the campaign was held (invite_enabled false) and the open beat returned at once. seat_duty.avg_ms 5,815 after 16 Nov is that
--     one run in the 0.3-weighted average: the beats before it averaged about 80 ms (0.7 a + 0.3 x 19,199 = 5,815).
--   * Not the five-minute spread: the job is on minute 0 of the five ('0-59/5'), and seat_duty jobs sit 20/21/21/21/20 over the
--     five minutes; no minute is crowded. The cost is the one daily run itself, in one transaction, on a 2-worker instance
--     (max_parallel_workers 2; jit off). Its writes (app_secrets cap, the invite_schedule day row, 5 notifications, 5 uninvited
--     leads) are rows a supplier's page only reads, so no page waited on its locks; it took the CPU the pages needed (inference
--     from the timings: the slow page calls lie inside 05:00:01-05:00:20).
--
-- WHERE THE 19 s GOES (LOCAL Postgres 16, 20,276 synthetic ZZ DEMO-sourced leads shaped like production's counts of 16 Nov:
-- 14,072 eligible, 5,531 reachable, 3 claimed; the GlockApps verdict stubbed to production's 05:00 answer, Microsoft held;
-- EXPLAIN ANALYZE through auto_explain): the whole open beat 11.7 s, of which
--   1. fn_supplier_invite_candidates 10.2-10.7 s. The planner reads leads as 40 rows after its function filters (it is 3,649) and
--      fn_supplier_invite_eligible_ids() as 1,000 (it is 14,072), so it joins them by nested loop: 35,419,250 rows compared
--      against the eligible set (5.8 s) and 43,981,844 against the keyed CTE (8.8 s). Hash joins do the same work in 30 ms.
--   2. fn_supplier_listing_has_registered_twin 1.3 s: a LANGUAGE sql routine with SECURITY DEFINER and a SET clause is never
--      inlined, and Postgres 16/17 re-plans its inner query on every call: 0.24 ms per listing x 5,531 listings (the 12 Nov review
--      measured 0.60 ms per listing on production). The same rule in plpgsql keeps its plan: 39 us.
--   3. enqueue_supplier_invites counts the pool with the per-row rule over every lead (fn_supplier_invite_eligible(l)): 1.6-1.8 s.
--      The set rule fn_supplier_invite_eligible_ids(), which candidates already reads, counts the same 14,072 in 0.29 s.
--
-- CHANGE (three routines, each the LIVE body read from production on 16 Nov 2026 05:10 UTC, md5 of pg_get_functiondef matched
-- before the edit: candidates 54310c950f3d89e0ac92d645192d15e8, enqueue bb4b6a06777ee23e07bf2268ca124433):
--   1. fn_supplier_invite_candidates: one added line, SET enable_nestloop TO 'off', for this routine's statements only. The body is
--      unchanged. Its one lateral join (the plan rank) still runs as a nested loop, which is the only way a lateral can run.
--   2. fn_supplier_listing_has_registered_twin: the same rule, the same key, the same exclusions (claimed, not demo, not itself),
--      written in plpgsql so its plan is kept. A name with no key has no twin, as before.
--   3. enqueue_supplier_invites: one line, v_pool counted from fn_supplier_invite_eligible_ids() (the set statement of the row rule,
--      proved lead for lead equal on 17,401 leads when it was applied; scripts/checks/the_invitation_pool_set_states_the_row_rule
--      .test.mjs keeps them reading the same tables). The count is only used for the planned number and the notes.
--   LOCAL after: the open beat 1.15-1.24 s (pool count 0.29 s, candidates 0.73 s); candidates alone 0.53-0.87 s.
--
-- NOT CHANGED: who is invited, how many, in what order, with what text, when, and every switch, cap, brake, holiday, weekend,
-- window, consent and placement gate. The final order of fn_supplier_invite_candidates is total (target_rank, plan_rank,
-- mailbox_rank, is_none, then rk within pdomain), so no plan change can reorder it; the LOCAL open beat queued the same 5 leads,
-- same addresses, same variants, same bodies (md5), before and after. The trigger that refuses an invitation
-- (fn_notifications_supplier_invite_is_whole) still asks the per-row rule for every row it lets through.
-- CREATE OR REPLACE keeps each routine's live ACL (postgres and service_role, read 16 Nov); the revokes are restated.
-- One overload each: fn_supplier_invite_candidates(integer, text[]), enqueue_supplier_invites(integer),
-- fn_supplier_listing_has_registered_twin(bigint, text). search_path pinned on all three.
-- Prevented by: scripts/checks/the_supplier_outreach_duty_never_slows_a_suppliers_page.test.mjs (the latest definition of each
-- routine keeps its change; a redefinition from an older body fails) and the probe
-- the_supplier_outreach_duty_never_slows_a_suppliers_page_probe.sql (the twin rule answers as before; the pool counts agree;
-- the candidates call returns inside 3 s).
-- Apply at merge, away from 05:00 UTC and from a :x0/:x5 mark, then run the probe:
--   node scripts/apply_sql.mjs scripts/sql/the_supplier_outreach_duty_never_slows_a_suppliers_page.sql --apply --ddl

-- 1. THE CANDIDATES: the live body, one added line (the SET clause) ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_supplier_invite_candidates(p_limit integer, p_providers text[])
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET enable_nestloop TO 'off'
AS $function$
declare v_site text; v_target int;
  v_reach boolean := coalesce((select value from app_secrets where key = 'invite_reachable_only'), '') = 'true';
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  -- 27 Oct 2026: the founder's invitation carries no link ("safer to not send links"); a supplier registers at
  -- quotesdone.com or replies. Only an EMPTY template is refused now. A template that still has {{link}} is filled.
  if coalesce(v_body, '') ~ '^[[:space:]]*$' then
    raise exception 'app_secrets.invite_body is empty: no invitation is built from nothing';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  -- ONE COMPANY, ONE INVITATION (24 Sep 2026, marketing). A company is its email domain, unless the domain is
  -- a shared mailbox provider (gmail, emirates.net.ae ...: measured as a domain carrying 3+ different company
  -- names), where it is the address itself; and, independently, its normalised company name.
  shared as materialized (
    select split_part(lower(btrim(l.email)), '@', 2) as dom from leads l where coalesce(btrim(l.email), '') <> ''
    group by 1 having count(distinct lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g'))) >= 3
  ),
  keyed as materialized (
    select l.id,
           case when s.dom is null then split_part(lower(btrim(l.email)), '@', 2) else lower(btrim(l.email)) end as dkey,
           nullif(lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g')), '') as nkey,
           (l.invite_status is not null or l.invited_at is not null or coalesce(l.claimed, false)) as touched
    from leads l left join shared s on s.dom = split_part(lower(btrim(l.email)), '@', 2)
    where coalesce(btrim(l.email), '') <> ''
  ),
  touched_d as materialized (select distinct dkey from keyed where touched),
  touched_n as materialized (select distinct nkey from keyed where touched and nkey is not null),
  -- instr 1013: marketing's ranking of the trades below ten suppliers (the ranking orders the queue; since 27 Oct 2026
  -- every row stores the one approved text, not a per-trade variant)
  plans as materialized (select p.trade, p.emirate, p.rank from public.marketing_gap_recruitment_plan p),
  -- 29 Sep 2026 (ledger 1018): the trades and areas of the open, real stalled-request rescues (public.stalled_inquiry_rescue).
  -- A fixture rescue never moves the real queue.
  rescue as materialized (select x.trades, x.emirate from public.stalled_inquiry_rescue x where x.cleared_at is null and not x.fixture and cardinality(x.trades) > 0),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey, ec.mailbox,
           -- ALWAYS ENGLISH (24 Sep 2026, ledger 993 item 4; #1065): suppliers are always written in English.
           'en'::text as lang
    from leads l join keyed k on k.id = l.id left join public.lead_email_check ec on ec.lead_id = l.id
    where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))   -- the set, read once (see header)
      -- 27 Oct 2026 (it_engineer): only recipients whose mailbox class passed the GlockApps verdict; null = every class
      and (p_providers is null or public.fn_mail_provider_of_email(l.email) = any(p_providers))
      -- 2 Nov 2026 (ceo, ledger 1438, 1449): the CEO's reachability lever; unchecked addresses wait while it is on
      and (not v_reach or l.email_verified in ('verified', 'true', 'maps', 'social'))
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
      -- 12 Nov 2026 (customer_support, ruling 1645, walk finding H10): a listing whose company registered itself under the same
      -- legal name key (fn_company_registration_name_key, the key leads_claimed_company_name_uidx uses) is not invited. The alnum
      -- key above misses "&"/"and", "Establishment"/"Est" and Arabic letter variants. Only ever removes candidates.
      and not public.fn_supplier_listing_has_registered_twin(l.id, l.company_name)
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 29 Sep 2026 (ledger 1018): ahead of every tier below, a lead in the trade and area of a stalled request a customer waits on.
      -- 23 Sep 2026: a lead in a trade the sales engineer marked for recruitment (supply_gap 'recruit') goes first;
      -- 29 Sep 2026 (instr 1013): then a lead in any trade marketing planned, by the plan's rank.
      case when exists (select 1 from rescue x where x.trades && coalesce(c.invite_trades, '{}'::text[])
                          and (x.emirate is null or x.emirate = 'UAE' or x.emirate = c.emirate)) then -1
           when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0
           when pl.rank is not null then 1 else 2 end as target_rank,
      -- 2 Nov 2026 (ceo): a trade the CEO put first leads inside its tier; a stalled request's rescue still comes before it
      case when exists (select 1 from public.ceo_invite_trade_priority t where t.cleared_at is null and t.trade = any(coalesce(c.invite_trades, '{}'::text[])))
           then -1 else coalesce(pl.rank, 2147483647) end as plan_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      -- THE LIKELIEST MAILBOX FIRST (2 Nov 2026, ledger 1449). Measured on the 52 real sends: proven 'verified' 1 bounce of 22,
      -- proven 'true' 1 of 9, unproven role address 0 of 2, unproven named address 5 of 16. So an unproven info@ goes before
      -- an unproven named address (this used to be the other way round), and free mail last. ponytail: small sample, re-read at 200.
      case when c.email_verified in ('verified','true') then 0 when c.mailbox = 'free' then 3 when c.mailbox = 'role' then 1 else 2 end as mailbox_rank
    from cand c
    left join lateral (select p.rank from plans p
                        where p.trade = any(coalesce(c.invite_trades, '{}'::text[])) and (p.emirate = 'UAE' or p.emirate = c.emirate)
                        order by p.rank limit 1) pl on true
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.mailbox_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.mailbox_rank, p.id) as domain_rk,
        -- the best contact per company, by mailbox_rank. ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.mailbox_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.mailbox_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.plan_rank, r.mailbox_rank, r.is_none, r.rk, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang, v_subj,
         -- an Arabic-script company name is not written into an English letter (the 29 Sep probe found 11 of 200);
         -- with no usable name the greeting is the neutral "Hello," the Microsoft 365 lane also sends
         -- (a template that still carries {{link}} is filled as before; the approved one has none)
         replace(replace(case when n.nm = '' then replace(v_body, 'Hi {{company}} team,', 'Hello,') else v_body end,
                         '{{company}}', case when n.nm = '' then 'there' else n.nm end),
                 '{{link}}', public.fn_supplier_invite_link(v_site, e.claim_token, e.id))
  from elig e
  cross join lateral (select coalesce(nullif(btrim(case when e.company_name ~ '[؀-ۿ]' then '' else e.company_name end), ''), '') as nm) n;
end
$function$;
revoke execute on function public.fn_supplier_invite_candidates(integer, text[]) from public, anon, authenticated;
grant execute on function public.fn_supplier_invite_candidates(integer, text[]) to service_role;

-- 2. THE REGISTERED-TWIN RULE, in plpgsql so its plan is kept --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_supplier_listing_has_registered_twin(p_lead_id bigint, p_company_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_key text := public.fn_company_registration_name_key(p_company_name);
begin
  if v_key is null then return false; end if;
  return exists (select 1 from public.leads o
                  where o.claimed and o.id is distinct from p_lead_id and not coalesce(o.is_demo, false)
                    and public.fn_company_registration_name_key(o.company_name) = v_key);
end
$function$;
revoke execute on function public.fn_supplier_listing_has_registered_twin(bigint, text) from public, anon, authenticated;

-- 3. THE BATCH: the live body, the pool counted from the set rule ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_supplier_invites(p_cap integer DEFAULT NULL::integer)
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
  select count(*) into v_used from notifications where type in ('supplier_invite', 'supplier_invite_nudge') and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
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
$function$;
revoke execute on function public.enqueue_supplier_invites(integer) from public, anon, authenticated;
grant execute on function public.enqueue_supplier_invites(integer) to service_role;
