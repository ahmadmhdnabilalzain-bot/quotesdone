-- THE RECRUITMENT FUNNEL COUNTS WHAT WAS SENT AND NAMES THE STAGE THAT LOST THEM.
-- Seat: marketing (analytics and attribution). 28 Sep 2026, seat audit gap (marketing.md P2, priority 4):
-- "Recruitment funnel: pool 2,802, invited 54, registered 0" and "marketing_first_touch = 0. CAC/ROI null".
--
-- WHAT WAS MEASURED (production, 28 Sep 2026, read-only)
--   * seat_duty marketing.recruitment_funnel last_result: pool 2,802, invited 54, registered 0, 7 gaps. It reports
--     totals and nothing reasons over them.
--   * leads.invited_at is set on 171 leads (162 'sent', 10 'bounced'; July to 23 Aug, plus 1 ZZ DEMO today).
--     notifications holds 0 rows of type 'supplier_invite' (the outbox starts 7 Sep; the 16 'supplier_invite_seed'
--     rows are test-path sends to mail-tester and the founder, lead_id null). So no invitation counted as "invited"
--     has a delivery record: the invited column is a status, not a send. Since 7 Sep enqueue_supplier_invites holds
--     every batch (supplier_outreach_golive = false, invite_enabled = false; 28 Sep: planned 50, queued 0).
--     WhatsApp invitations: 0.
--   * The invitation link is <site>/<lang>/portal?t=<claim_token>: no UTM. The browser's first-touch capture
--     (src/lib/firstTouch.ts) keeps only a link with utm_source, so a supplier who came from an invitation could
--     never be attributed. marketing_first_touch = 0 rows. Posts are already tagged (70 of 70 cta_url carry
--     utm_source/utm_content), so only invitations lacked a ref.
--
-- WHAT CHANGES
--   1. The invitation link carries utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&
--      utm_content=lead-<id>. That part is NOT in this file (review, 29 Sep 2026): its first version copied
--      fn_supplier_invite_candidates from MANIFEST 1757, which chose Arabic copy and /ar/portal links, over the
--      canonical always-English body (MANIFEST 1824, #964). fn_supplier_invite_link (always /en/, no language
--      argument) and the one combined candidates definition live in
--      the_invitation_pool_is_read_once_as_a_set_so_the_daily_list_fits_its_timeout.sql (#1051). Depends-on: #1051.
--   2. fn_marketing_first_touch_record (copied from each_post_is_measured_and_names_the_suppliers_it_brought.sql):
--      when the browser kept no tagged visit but the lead opened its own claim link (leads.invite_clicked_at, set by
--      claim_lookup), the first touch is the invitation. Idempotent: first touch wins (on conflict do nothing).
--   3. fn_marketing_funnel_largest_drop + fn_marketing_funnel_diagnosis: plain SQL. Stages per channel and trade:
--      invited (status) -> sent (outbox row status 'sent') -> delivered (provider_status 'delivered') -> clicked
--      (invite_clicked_at) -> started (claimed) -> registered (registration_submitted_at). Names the stage pair with
--      the largest drop and a rule-based cause and fix. When a channel has >= N invited (app_secrets
--      recruitment_diagnosis_min_invites, default 20) and 0 registered, it is filed to the CEO as a ceo_improvement
--      ('funnel_stage_drop', one per channel, cause and month), which assigns it to marketing.
--   4. fn_marketing_recruitment_funnel: its result carries the diagnosis, and it files it. Depends-on: #996
--      (re-review, 29 Sep 2026). The body is #996's
--      an_open_supply_gap_becomes_a_recruitment_brief_marketing_reads_and_closes_at_target.sql byte for byte (one
--      pool_empty finding per trade group, the null-extended-row pool fix, 'agent_facing'), with only its return
--      value extended by 'diagnosis'. The first version copied the older body from MANIFEST 1727, so whichever of
--      #996 and #1012 applied second would have undone the other. Apply #996 first, then this file.
--   5. ceo_improvement_source_kind_check gains 'funnel_stage_drop' (list copied from
--      the_ceo_turns_the_binding_constraint_into_an_improvement_every_week.sql).
--
-- WHAT THIS DOES NOT DO: it sends nothing and opens no go (the invitation and its release are sales_engineer's and
-- customer_support's, instr 625); it calls no model (the proposed fix is a rule per cause; no narrative is written,
-- so the model hold is not touched); it does not score social posts (fn_marketing_scorecard already attributes
-- registrations to posts through the same first-touch table); CAC stays null because spend is 0 (organic only).

-- ── 1. the invitation link carries its ref: NOT HERE ─────────────────────────────────────────────────────
-- fn_supplier_invite_link and the fn_supplier_invite_candidates that uses it are defined once, in
-- the_invitation_pool_is_read_once_as_a_set_so_the_daily_list_fits_its_timeout.sql (#1051), on the canonical
-- always-English body. This file depends on it and is applied after it (review of #1051 and #1012, 29 Sep 2026).

-- ── 2. first touch at registration, the invitation when the browser kept none ───────────────────────
create or replace function public.fn_marketing_first_touch_record(p_lead_id bigint, p_touch jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ok constant text := '^[A-Za-z0-9._-]{1,100}$';
  v_src text; v_med text; v_cmp text; v_cnt text; v_path text; v_at timestamptz; v_post bigint; v_id bigint;
begin
  if p_lead_id is null then
    return jsonb_build_object('ok', true, 'recorded', false, 'reason', 'no lead');
  end if;
  if p_touch is null or jsonb_typeof(p_touch) <> 'object' then p_touch := '{}'::jsonb; end if;
  v_src := nullif(btrim(p_touch->>'utm_source'), '');     if v_src !~ v_ok then v_src := null; end if;
  v_med := nullif(btrim(p_touch->>'utm_medium'), '');     if v_med !~ v_ok then v_med := null; end if;
  v_cmp := nullif(btrim(p_touch->>'utm_campaign'), '');   if v_cmp !~ v_ok then v_cmp := null; end if;
  v_cnt := nullif(btrim(p_touch->>'utm_content'), '');    if v_cnt !~ v_ok then v_cnt := null; end if;
  v_path := nullif(btrim(p_touch->>'landing_path'), '');  if v_path !~ '^/\S{0,200}$' then v_path := null; end if;
  -- THE INVITATION IS A TOUCH EVEN WHEN THE BROWSER KEPT NONE (28 Sep 2026, this file): private mode or a link
  -- opened before the ref existed leaves no tagged visit, but claim_lookup stamps invite_clicked_at when the
  -- lead's own claim link is opened. That is evidence of the invitation, not a status column.
  if v_src is null then
    select 'invite', 'email', 'supplier_invite', 'lead-' || l.id, '/portal', l.invite_clicked_at
      into v_src, v_med, v_cmp, v_cnt, v_path, v_at
      from public.leads l where l.id = p_lead_id and l.invite_clicked_at is not null;
    if v_src is null then
      return jsonb_build_object('ok', true, 'recorded', false, 'reason', 'no valid utm_source and no opened invitation');
    end if;
    p_touch := jsonb_build_object('first_seen_at', v_at);
  end if;
  begin
    v_at := (p_touch->>'first_seen_at')::timestamptz;
    if v_at < now() - interval '400 days' or v_at > now() + interval '1 hour' then v_at := null; end if;
  exception when others then v_at := null;
  end;
  if v_med = 'social' and v_cnt is not null then
    select id into v_post from public.marketing_post where ingest_key = lower(v_cnt);
  end if;
  insert into public.marketing_first_touch (lead_id, utm_source, utm_medium, utm_campaign, utm_content, landing_path, first_seen_at, post_id)
  values (p_lead_id, lower(v_src), v_med, v_cmp, v_cnt, v_path, v_at, v_post)
  on conflict (lead_id) do nothing
  returning id into v_id;
  return jsonb_build_object('ok', true, 'recorded', v_id is not null, 'post_id', v_post);
end
$fn$;
revoke execute on function public.fn_marketing_first_touch_record(bigint, jsonb) from public, anon, authenticated;

-- ── 3. the stage that lost them ──────────────────────────────────────────────────────────────────────────
-- p_stages: {"invited":n,"sent":n,"delivered":n,"clicked":n,"started":n,"registered":n}. The pair with the largest
-- drop (the earliest on a tie) and the rule for it. A rule, not a judgement: each cause is what that pair means.
create or replace function public.fn_marketing_funnel_largest_drop(p_stages jsonb)
returns jsonb
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce((
    select jsonb_build_object('from', s.a, 'to', s.b, 'lost', s.lost, 'cause', s.cause, 'proposed_fix', s.fix)
      from (select a, b, coalesce((p_stages->>a)::int, 0) - coalesce((p_stages->>b)::int, 0) as lost, cause, fix, ord
              from (values
                (1, 'invited', 'sent', 'not_actually_sent',
                 'Leads are marked invited but the outbox holds no sent invitation for them. Count only outbox sends; the batch is released by enqueue_supplier_invites once supplier_outreach_golive and invite_enabled are true.'),
                (2, 'sent', 'delivered', 'bounced_or_undelivered',
                 'Invitations left the outbox but were not delivered. Clean the list (role and dead domains) and check the sending domain before the next batch.'),
                (3, 'delivered', 'clicked', 'no_clicks',
                 'Invitations were delivered but nobody opened the link. Test the subject line, the first sentence and the sender name per trade.'),
                (4, 'clicked', 'started', 'clicks_but_no_start',
                 'Suppliers opened the link but did not claim their company. Walk the portal claim step from the invitation link and shorten it.'),
                (5, 'started', 'registered', 'started_not_finished',
                 'Suppliers claimed but did not submit the registration. Find the form step they stop at and follow up through customer_support.')
              ) v(ord, a, b, cause, fix)) s
     where s.lost > 0
     order by s.lost desc, s.ord
     limit 1),
    jsonb_build_object('from', null, 'to', null, 'lost', 0, 'cause', 'no_drop', 'proposed_fix', null))
$fn$;
revoke execute on function public.fn_marketing_funnel_largest_drop(jsonb) from public, anon, authenticated;

-- Per channel and per (channel, trade). The population is every lead with invited_at (the status); each later stage
-- is measured on its own record. Demo leads only when asked (the probe). p_file: a channel with >= N invited and
-- 0 registered is filed to the CEO as an improvement for marketing, once per channel, cause and month.
create or replace function public.fn_marketing_funnel_diagnosis(p_include_demo boolean default false, p_file boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_min int := coalesce((select nullif(btrim(value), '')::int from public.app_secrets where key = 'recruitment_diagnosis_min_invites'), 20);
  v_month text := to_char((now() at time zone 'Asia/Dubai')::date, 'YYYY-MM');
  v_channels jsonb; v_trades jsonb; c record; v_filed jsonb := '[]'::jsonb; v_imp bigint;
begin
  with f as (
    select l.id, coalesce(n.channel, 'email') as channel,
           coalesce(nullif(l.invite_trades, '{}'::text[]), array['unknown']) as trades,
           coalesce(n.sent, false)::int as sent, coalesce(n.delivered, false)::int as delivered,
           (l.invite_clicked_at is not null)::int as clicked, coalesce(l.claimed, false)::int as started,
           (l.registration_submitted_at is not null)::int as registered
      from public.leads l
      left join lateral (
        select max(x.channel) as channel, bool_or(x.status = 'sent') as sent,
               bool_or(x.status = 'sent' and x.provider_status = 'delivered') as delivered
          from public.notifications x where x.lead_id = l.id and x.type = 'supplier_invite') n on true
     where l.invited_at is not null and (p_include_demo or not coalesce(l.is_demo, false))
  ), per_channel as (
    select channel, jsonb_build_object('invited', count(*), 'sent', sum(sent), 'delivered', sum(delivered),
           'clicked', sum(clicked), 'started', sum(started), 'registered', sum(registered)) st
      from f group by channel
  ), per_trade as (
    select f.channel, t.trade, jsonb_build_object('invited', count(*), 'sent', sum(f.sent), 'delivered', sum(f.delivered),
           'clicked', sum(f.clicked), 'started', sum(f.started), 'registered', sum(f.registered)) st
      from f cross join lateral unnest(f.trades) t(trade) group by f.channel, t.trade
  )
  select (select coalesce(jsonb_agg(jsonb_build_object('channel', channel, 'stages', st,
                   'drop', public.fn_marketing_funnel_largest_drop(st)) order by channel), '[]'::jsonb) from per_channel),
         (select coalesce(jsonb_agg(jsonb_build_object('channel', channel, 'trade', trade, 'stages', st,
                   'drop', public.fn_marketing_funnel_largest_drop(st)) order by channel, trade), '[]'::jsonb) from per_trade)
    into v_channels, v_trades;

  if p_file then
    for c in select e from jsonb_array_elements(v_channels) e
              where (e->'stages'->>'invited')::int >= v_min and (e->'stages'->>'registered')::int = 0 loop
      v_imp := public.fn_ceo_improvement_open('funnel_stage_drop',
        (c.e->>'channel') || ':' || (c.e->'drop'->>'cause') || ':' || v_month, 'marketing',
        format('Recruitment by %s: %s invited, 0 registered. The largest drop is %s -> %s (%s lost): %s. %s',
               c.e->>'channel', c.e->'stages'->>'invited', c.e->'drop'->>'from', c.e->'drop'->>'to', c.e->'drop'->>'lost',
               c.e->'drop'->>'cause', c.e->'drop'->>'proposed_fix'),
        jsonb_build_object('stages', c.e->'stages', 'drop', c.e->'drop', 'min_invites', v_min,
                           'source', 'fn_marketing_funnel_diagnosis'));
      v_filed := v_filed || jsonb_build_object('channel', c.e->>'channel', 'improvement_id', v_imp);
    end loop;
  end if;

  return jsonb_build_object('min_invites', v_min, 'channels', v_channels, 'by_trade', v_trades, 'filed', v_filed);
end $fn$;
revoke execute on function public.fn_marketing_funnel_diagnosis(boolean, boolean) from public, anon, authenticated;

-- ── 4. the CEO's improvement kinds gain the funnel ───────────────────────────────────────────────────────
alter table public.ceo_improvement drop constraint if exists ceo_improvement_source_kind_check;
alter table public.ceo_improvement add constraint ceo_improvement_source_kind_check
  check (source_kind in ('recurring_miss', 'month_miss', 'lesson', 'recurring_finding', 'binding_constraint',
                         'marketing_plan_late', 'seat_audit',
                         -- marketing's recruitment funnel with 0 registrations (this file)
                         'funnel_stage_drop'));

-- ── 5. the daily duty carries and files the diagnosis ────────────────────────────────────────────────────
-- #996's body (one pool_empty finding per trade group), byte for byte except the 'diagnosis' key in the result.
create or replace function public.fn_marketing_recruitment_funnel()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_day date := (now() at time zone 'Asia/Dubai')::date; v_rows int; gp record; v_empty int := 0; v_keys text[] := '{}';
begin
  insert into public.supplier_recruitment_funnel as f (trade, emirate, day, pool, invited, clicked, registered, approved, quoting)
  select g.trade, g.emirate, v_day,
         -- l.id is not null: a gap with NO matching lead is a null-extended row whose invite_status is
         -- null, which counted as a pool of 1 and so never fired pool_empty (found by this PR's probe).
         count(*) filter (where l.id is not null and l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)),
         count(*) filter (where l.invited_at is not null),
         count(*) filter (where l.invite_clicked_at is not null),
         count(*) filter (where l.registration_submitted_at is not null or coalesce(l.claimed, false)),
         count(*) filter (where l.approval_status = 'approved'),
         count(*) filter (where exists (select 1 from public.quotes q where q.supplier_id = l.id))
    from public.supply_gap g
    left join public.leads l on g.trade = any(coalesce(l.invite_trades, '{}'::text[]))
                            and (g.emirate = 'UAE' or l.emirate = g.emirate) and coalesce(l.is_demo, false) = false
   where g.status = 'recruit'
   group by g.trade, g.emirate
  on conflict (trade, emirate, day) do update set pool = excluded.pool, invited = excluded.invited, clicked = excluded.clicked,
    registered = excluded.registered, approved = excluded.approved, quoting = excluded.quoting;
  get diagnostics v_rows = row_count;

  -- An empty pool is the lead source, not the invitation: marketing's finding, one per trade group.
  for gp in select coalesce(tt.group_code, 'ungrouped') as grp, count(*)::int as n,
                   jsonb_agg(jsonb_build_object('trade', f.trade, 'emirate', f.emirate) order by f.trade, f.emirate) as gaps
              from public.supplier_recruitment_funnel f
              join public.supply_gap s on s.trade = f.trade and s.emirate = f.emirate and s.status = 'recruit'
              left join public.taxonomy_trade tt on tt.code = f.trade
             where f.day = v_day and f.pool = 0
             group by 1 loop
    v_empty := v_empty + gp.n;
    v_keys := v_keys || ('recruitment:pool_empty:' || gp.grp);
    perform public.fn_it_engineer_finding_upsert('recruitment:pool_empty:' || gp.grp,
      'No uninvited lead is left for ' || gp.n || ' recruiting gap(s) in trade group ' || gp.grp,
      'public.supplier_recruitment_funnel', 'agent_facing', gp.n,
      jsonb_build_object('trade_group', gp.grp, 'gap_count', gp.n, 'gaps', gp.gaps, 'owner_seat', 'marketing'), '{}'::text[],
      array['which source can supply leads for these trades while lead scraping is paused'], 'marketing');
  end loop;
  update public.it_engineer_finding fi
     set closed_at = now(),
         close_note = case when fi.issue_key ~ '^recruitment:pool_empty:[^:]+:'
                           then 'superseded: empty pools are now one finding per trade group'
                           else 'no recruiting gap in this trade group has an empty pool' end
   where fi.issue_key like 'recruitment:pool_empty:%' and fi.closed_at is null and not (fi.issue_key = any(v_keys));

  return jsonb_build_object('gaps_recruiting', v_rows, 'empty_pools', v_empty, 'empty_pool_findings', cardinality(v_keys),
    'totals', (select jsonb_build_object('pool', sum(pool), 'invited', sum(invited), 'registered', sum(registered), 'approved', sum(approved), 'quoting', sum(quoting))
                 from public.supplier_recruitment_funnel where day = v_day),
    -- which stage lost them, filed to the CEO when a channel has N invited and 0 registered (#1012)
    'diagnosis', public.fn_marketing_funnel_diagnosis(false, true));
end $fn$;
revoke execute on function public.fn_marketing_recruitment_funnel() from public, anon, authenticated;
grant execute on function public.fn_marketing_recruitment_funnel() to service_role;

