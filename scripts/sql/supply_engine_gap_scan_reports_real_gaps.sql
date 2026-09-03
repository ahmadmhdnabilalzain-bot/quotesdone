-- THE COVERAGE SCAN REPORTS THE REAL GAPS (3 Sep 2026).
--
-- What the scorer found (s26-missing-suppliers): the newest supply_health_snapshots row was from
-- 2026-08-15 with coverage_gaps=[] and no_supply=0, while exactly ONE of 20,465 leads is an approved,
-- matchable supplier. Both numbers were true and both were about the wrong subject: fn_supply_health
-- measured DEMAND-side coverage (inquiries in 30d that got a quote, by category) and there are no
-- inquiries, so there were no gaps. fn_supply_gap_scan, the routine that does look at supply, wrote
-- org_tasks for a department ('procurement') that no longer exists and never touched the snapshot.
--
-- Now fn_supply_gap_scan is the daily writer of the supply snapshot and its numbers are about SUPPLY:
--   * coverage_gaps — one entry per catalogue category below the target of 10 matchable suppliers
--     (approved, not banned, not matching_blocked), with the matchable and sendable pool broken out
--     by emirate, so the number says where to recruit, not only that recruiting is needed.
--   * no_supply     — categories with ZERO matchable suppliers. (fn_supply_health used this key for
--     unmatched inquiries; that number is kept under inquiries_no_match_30d.)
--   * a gap ACTION per category, at most once a week, addressed to the supplier_coverage seat and
--     recorded as done, because the scan does not ask anyone to do something: discovery
--     (fn_supplier_discovery_promote, 02:50 UTC) and the invite plan (enqueue_supplier_invites,
--     09:00 UTC) already draw from these gaps, and the action row is the record of that.
--
-- leads.emirate is free text in 14 shapes ("Al Quoz Industrial Area 1", a P.O. box, ...), so the
-- per-emirate breakdown goes through fn_norm_emirate, which maps anything it can to one of the seven
-- emirates and everything else to 'unknown' rather than dropping it.
--
--   node scripts/apply_sql.mjs scripts/sql/supply_engine_gap_scan_reports_real_gaps.sql --apply --ddl

create or replace function public.fn_norm_emirate(p_text text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case
    when p_text is null or btrim(p_text) = '' then 'unknown'
    when p_text ~* '(abu ?dhabi|al ain|\mauh\M)' then 'Abu Dhabi'
    when p_text ~* '(dubai|jebel ali|al quoz|al qusais|deira|\mdxb\M)' then 'Dubai'
    when p_text ~* '(sharjah|\mshj\M)' then 'Sharjah'
    when p_text ~* '(ajman|\majm\M)' then 'Ajman'
    when p_text ~* '(ras al[ -]?khaimah|\mrak\M)' then 'Ras Al Khaimah'
    when p_text ~* '(fujairah|\mfuj\M)' then 'Fujairah'
    when p_text ~* '(umm al[ -]?quwain|\muaq\M)' then 'Umm Al Quwain'
    else 'unknown' end
$$;

create or replace function public.fn_supply_gap_scan()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_target int; v_total int; v_met int; v_no_supply int; v_matchable int; v_uncat int;
  v_gaps jsonb; v_actions int := 0;
  v_inq int; v_matched int; v_quoted int; v_nomatch int; v_fill numeric;
  s timestamptz := now() - interval '30 days';
begin
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key = 'invite_target_per_category'), 10);

  -- SUPPLY SIDE. Every catalogue category, its matchable suppliers and its recruitable pool.
  -- Fixtures (ZZ DEMO / @example.invalid, the rehearsal convention) are not supply: a committed demo
  -- scenario must not read as a category covered.
  drop table if exists tmp_cov;
  create temp table tmp_cov on commit drop as
  with real_leads as (
    select l.* from leads l
     where coalesce(l.company_name, '') not ilike 'ZZ DEMO%' and coalesce(l.email, '') not ilike '%@example.invalid')
  select c.slug, c.name, c.num,
         count(distinct lc.lead_id) filter (where l.approval_status = 'approved') as approved,
         count(distinct lc.lead_id) filter (where l.approval_status = 'approved'
                                              and coalesce(l.banned,false) = false
                                              and coalesce(l.matching_blocked,false) = false) as matchable,
         count(distinct lc.lead_id) filter (where l.email is not null and l.email <> ''
                                              and coalesce(l.banned,false) = false) as sendable,
         count(distinct lc.lead_id) filter (where l.invite_status is not null) as invited,
         count(distinct lc.lead_id) filter (where l.invited_at > now() - interval '30 days') as invited_30d,
         count(distinct lc.lead_id) filter (where l.source = 'yello_staging'
                                              and l.created_at > now() - interval '1 day') as discovered_24h,
         coalesce((select jsonb_object_agg(z.em, z.n) from (
             select public.fn_norm_emirate(l2.emirate) em, count(distinct l2.id) n
               from lead_category lc2 join real_leads l2 on l2.id = lc2.lead_id
              where lc2.slug = c.slug and l2.approval_status = 'approved'
                and coalesce(l2.banned,false) = false and coalesce(l2.matching_blocked,false) = false
              group by 1) z), '{}'::jsonb) as matchable_by_emirate,
         coalesce((select jsonb_object_agg(z.em, z.n) from (
             select public.fn_norm_emirate(l2.emirate) em, count(distinct l2.id) n
               from lead_category lc2 join real_leads l2 on l2.id = lc2.lead_id
              where lc2.slug = c.slug and l2.email is not null and l2.email <> ''
                and coalesce(l2.banned,false) = false
              group by 1) z), '{}'::jsonb) as pool_by_emirate
    from catalog_supplier_categories c
    left join lead_category lc on lc.slug = c.slug
    left join real_leads l on l.id = lc.lead_id
   group by c.slug, c.name, c.num;

  select count(*), count(*) filter (where matchable >= v_target), count(*) filter (where matchable = 0)
    into v_total, v_met, v_no_supply from tmp_cov;
  select count(*) into v_matchable from leads
   where approval_status = 'approved' and coalesce(banned,false) = false and coalesce(matching_blocked,false) = false
     and coalesce(company_name, '') not ilike 'ZZ DEMO%' and coalesce(email, '') not ilike '%@example.invalid';
  select count(*) into v_uncat from leads l
   where l.email is not null and l.email <> '' and coalesce(l.banned,false) = false
     and coalesce(l.company_name, '') not ilike 'ZZ DEMO%' and l.email not ilike '%@example.invalid'
     and not exists (select 1 from lead_category lc where lc.lead_id = l.id);

  select coalesce(jsonb_agg(jsonb_build_object(
           'slug', t.slug, 'name', t.name, 'num', t.num,
           'matchable', t.matchable, 'approved', t.approved, 'target', v_target,
           'gap', v_target - t.matchable,
           'sendable', t.sendable, 'invited', t.invited, 'invited_30d', t.invited_30d,
           'discovered_24h', t.discovered_24h,
           'matchable_by_emirate', t.matchable_by_emirate, 'pool_by_emirate', t.pool_by_emirate,
           'status', case when t.matchable = 0 and t.sendable = 0 then 'NO POOL - discovery must source it'
                          when t.matchable = 0 then 'NO SUPPLY - pool exists, nobody approved'
                          when t.sendable = 0 then 'POOL EXHAUSTED - below target with nothing left to invite'
                          else 'BELOW TARGET' end)
         order by t.matchable asc, t.sendable asc, t.num), '[]'::jsonb)
    into v_gaps
    from tmp_cov t where t.matchable < v_target;

  -- DEMAND SIDE, kept from fn_supply_health so the snapshot still answers "did requests get quotes".
  select count(*) into v_inq from inquiries where created_at >= s;
  select count(*) into v_matched from inquiries i where i.created_at >= s
     and exists (select 1 from inquiry_matches m where m.inquiry_id = i.id);
  select count(*) into v_quoted from inquiries i where i.created_at >= s
     and exists (select 1 from quotes q where q.inquiry_id = i.id);
  v_nomatch := v_inq - v_matched;
  v_fill := case when v_inq > 0 then round(v_quoted::numeric / v_inq, 3) else null end;

  insert into supply_health_snapshots (period_end, metrics)
  values (current_date, jsonb_build_object(
    'measured_by', 'fn_supply_gap_scan',
    'categories', v_total, 'target_per_category', v_target, 'target_met', v_met,
    'no_supply', v_no_supply, 'matchable_suppliers', v_matchable,
    'unclassified_sendable_leads', v_uncat,
    'coverage_gaps', v_gaps,
    'inquiries_30d', v_inq, 'matched', v_matched, 'quoted', v_quoted,
    'inquiries_no_match_30d', v_nomatch, 'fill_rate', v_fill));

  -- THE GAP ACTION. One per category per week, recorded as done by the seat that owns coverage: the
  -- work it names (discovery into the category, the invite plan drawing on its pool) is done by the
  -- crons either side of this one, and this row is the record, not a request.
  insert into agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id,
                             confidence, evidence, decided_by, decided_at, expected_impact, cost)
  select 'supplier_coverage', 'coverage_gap', 'auto_done', 'low',
         'Coverage gap: ' || (g->>'name') || ' — ' || (g->>'matchable') || ' of ' || v_target || ' matchable supplier(s)',
         case when (g->>'sendable')::int = 0
              then 'No sendable lead in this category: discovery (fn_supplier_discovery_promote, daily) promotes staged directory rows into it first; nothing can be invited until it does.'
              else 'The invite plan draws from this category''s ' || (g->>'sendable') || ' sendable lead(s); '
                   || (g->>'invited') || ' already invited. Real invitations stay held until the founder''s go (app_secrets.invite_enabled).' end,
         g || jsonb_build_object('acted', jsonb_build_object(
                'discovered_24h', (g->>'discovered_24h')::int,
                'pool_sendable', (g->>'sendable')::int,
                'invited_30d', (g->>'invited_30d')::int,
                'invite_gate', coalesce((select value from app_secrets where key = 'invite_enabled'), 'false'))),
         'catalog_supplier_categories', g->>'slug',
         1.0, jsonb_build_object('basis', 'lead_category x leads counted by fn_supply_gap_scan on ' || current_date,
                                 'snapshot_period_end', current_date),
         'supply_gap_scan', now(),
         'Every category that reaches ' || v_target || ' matchable suppliers can answer an RFQ with a top-3 report; below that the RFQ is refused or thin.',
         'No spend: discovery reads the staged directory rows already paid for; invitations are email.'
    from jsonb_array_elements(v_gaps) g
   where not exists (select 1 from agent_actions a
                      where a.kind = 'coverage_gap' and a.target_table = 'catalog_supplier_categories'
                        and a.target_id = g->>'slug' and a.created_at > now() - interval '7 days');
  get diagnostics v_actions = row_count;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('supply_gap_scan', now(), now(), 'ok',
          jsonb_build_object('categories', v_total, 'target_met', v_met, 'no_supply', v_no_supply,
                             'matchable_suppliers', v_matchable, 'gaps', jsonb_array_length(v_gaps),
                             'gap_actions_opened', v_actions, 'unclassified', v_uncat),
          'Supply gap scan: ' || v_met || ' of ' || v_total || ' categories at ' || v_target || ' matchable suppliers; '
          || v_no_supply || ' with none at all; ' || v_matchable || ' matchable supplier(s) in total; '
          || v_actions || ' gap action(s) opened this run.');

  return jsonb_build_object('categories', v_total, 'target_met', v_met, 'no_supply', v_no_supply,
                            'matchable_suppliers', v_matchable, 'gaps', jsonb_array_length(v_gaps),
                            'gap_actions_opened', v_actions, 'unclassified', v_uncat);
end $function$;
