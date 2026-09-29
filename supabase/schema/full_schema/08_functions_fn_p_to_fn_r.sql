CREATE OR REPLACE FUNCTION public.fn_page_high_agent_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_founder text; v_kind text;
BEGIN
  IF lower(coalesce(NEW.risk,'')) IN ('high','critical')
     -- K21. Was: NEW.agent IN ('finance_ai','security_ai','operations_ai'). That set could never
     -- match a security action. a00_agent_action_resolve_addressee runs BEFORE this trigger and
     -- resolves the addressee through org_agents, so a row written as 'security_ai' arrives here
     -- as 'security'. Measured: inserting agent='security_ai' reads back as 'security', and
     -- notifications has 0 rows of type 'agent_escalation' in its entire history — the founder has
     -- never been paged by this trigger. A prefix match survives the resolver in both directions
     -- and does not need a keep-list that has to be remembered every time an agent is renamed.
     AND NEW.agent ~ '^(finance|security|operations)'
     AND lower(coalesce(NEW.status,'pending')) = 'pending' THEN
  -- 9 SEP 2026 -- PHASE MACHINERY REMOVED. An emit into the kernel source table stood here that
  -- declared this action the start of a W29 kernel run. The kernel, its source table and its
  -- W-numbered programme are all deleted in this sweep and nothing else consumed that event, so
  -- the emit is gone rather than re-pointed. Everything below it -- the founder_email lookup, the
  -- founder_mail_policy kind, the 24-hour dedupe and the notifications row -- is unchanged, and is
  -- now the whole of what this trigger does.
    v_founder := coalesce(
      (SELECT value FROM app_secrets WHERE key='founder_email'),
      nullif(split_part((SELECT value FROM app_secrets WHERE key='admin_emails'), ',', 1), ''),
      'management@quotesdone.com');
    -- 6 SEP 2026: the founder_mail_policy key is the action's own kind; a CRITICAL security action is
    -- the one security kind that may reach him (founder_mail_policy.security_critical).
    v_kind := CASE WHEN lower(coalesce(NEW.risk,'')) = 'critical' AND NEW.agent ~ '^security' THEN 'security_critical'
                   ELSE coalesce(nullif(NEW.kind,''), 'agent_escalation') END;
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE type='agent_escalation' AND body LIKE '%action #'||NEW.id||'%'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO notifications(type, kind, to_email, to_role, channel, status, subject, body)
      VALUES('agent_escalation', v_kind, v_founder, 'admin', 'email', 'queued',
        '['||upper(NEW.risk)||'] '||coalesce(NEW.title, NEW.kind, 'Agent escalation'),
        coalesce(NEW.recommendation, NEW.title, '')||E'\n\nAgent: '||coalesce(NEW.agent,'?')||' · action #'||NEW.id||' · open the OS to decide.');
    END IF;
  END IF;
  RETURN NEW;
END
$function$


CREATE OR REPLACE FUNCTION public.fn_paid_route_exception(p_route text, p_model text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r public.paid_route_exception%rowtype;
  v_spent numeric;
begin
  select * into r from public.paid_route_exception where route = p_route;
  if not found then
    return jsonb_build_object('allowed', false, 'rule', 'no_exception', 'reason', 'no paid_route_exception row for ' || coalesce(p_route, 'null'));
  end if;
  if not r.enabled then
    return jsonb_build_object('allowed', false, 'rule', 'exception_disabled', 'reason', 'the exception for ' || p_route || ' exists and is switched off');
  end if;
  if p_model is distinct from r.model_id then
    return jsonb_build_object('allowed', false, 'rule', 'exception_other_model', 'reason', 'the exception names ' || r.model_id || ', not ' || coalesce(p_model, 'null'));
  end if;
  select coalesce(sum(cost_aed), 0) into v_spent from public.ai_cost_log
   where task_class = p_route and occurred_at >= date_trunc('day', now());
  if v_spent >= r.daily_cap_aed then
    return jsonb_build_object('allowed', false, 'rule', 'exception_daily_cap', 'reason', 'spent AED ' || v_spent || ' of the AED ' || r.daily_cap_aed || ' daily cap');
  end if;
  return jsonb_build_object('allowed', true, 'rule', 'named_exception', 'route', p_route, 'model', r.model_id,
    'max_tokens', r.max_tokens_per_call, 'spent_today_aed', v_spent, 'daily_cap_aed', r.daily_cap_aed, 'authority_instruction_id', r.authority_instruction_id);
exception when others then
  return jsonb_build_object('allowed', false, 'rule', 'exception_unreadable', 'reason', sqlstate || ' ' || sqlerrm);
end $function$


CREATE OR REPLACE FUNCTION public.fn_phase1_rollback_log_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  raise exception 'phase1_rollback_log is append-only; % is not permitted', TG_OP
    using errcode = '42501';
end $function$


CREATE OR REPLACE FUNCTION public.fn_pick_reviewer(p_dept_key text, p_author text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_head text; v_ok boolean; v_delegate text; v_basis text;
        v_head_tier text; v_head_score numeric; v_score numeric; v_up text;
begin
  -- THE AUTHOR ARRIVES UNDER WHATEVER NAME THE CALLER HAD (14 Aug 2026).
  -- Every comparison below is a raw string test - p_author = v_head, and three
  -- "a.agent_key is distinct from p_author" filters. All ten department heads carry aliases, so
  -- an author passed as 'finance_ai', 'marketplace_director' or 'CEO AI' was not equal to 'ceo',
  -- 'procurement' or 'ceo', the guard did not fire, and this function returned the author as its
  -- own reviewer. Measured on production before this line: 10 of 10 departments.
  -- Resolving once here fixes every comparison at the same time, because they all read p_author.
  p_author := coalesce(public.fn_org_agent_resolve(p_author), p_author);

  select lead_agent into v_head from org_departments where dept_key = p_dept_key;

  if v_head is null then
    return jsonb_build_object('reviewer', null, 'available', false,
      'basis', 'no lead_agent recorded for department ' || p_dept_key);
  end if;

  -- THE AUTHOR IS THE HEAD. Measured 14 Aug 2026: 285 of 1,882 review_chain rows had
  -- author_agent = reviewer_agent and 182 of those were approvals, because this function was only
  -- ever told the department and answered with its head. When the head wrote the work, review
  -- climbs: first to an independent reviewer inside the same department, then to the head's own
  -- manager. It never returns the author.
  if p_author is not null and p_author = v_head then
    select a.agent_key into v_delegate
      from org_agents a
      join org_role r on r.runtime_agent_key = a.agent_key and r.status = 'active'
     where a.department = p_dept_key and a.agent_key <> p_author
       and r.runtime_mode = 'independent_reviewer'
       and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
     order by a.agent_key limit 1;

    if v_delegate is not null then
      return jsonb_build_object('reviewer', v_delegate, 'available', true, 'delegated_from', v_head,
        'basis', 'the department head authored this work; review routed to the department''s '
                 || 'independent reviewer, which never approves its own output');
    end if;

    select m.agent_key into v_up
      from org_agents o join org_agents m on m.agent_key = o.manager_key and m.active
     where o.agent_key = v_head
       and m.available and (m.unavailable_until is null or m.unavailable_until < current_date);

    if v_up is not null and v_up <> p_author then
      return jsonb_build_object('reviewer', v_up, 'available', true, 'delegated_from', v_head,
        'basis', 'the department head authored this work and the department has no independent '
                 || 'reviewer available; review escalated one level up the reporting chain');
    end if;

    return jsonb_build_object('reviewer', null, 'available', false, 'delegated_from', v_head,
      'basis', 'the department head authored this work and no independent reviewer or manager is '
               || 'available - escalate rather than approve it');
  end if;

  select (a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date))
    into v_ok from org_agents a where a.agent_key = v_head;

  select p.tier, p.score into v_head_tier, v_head_score
    from agent_reputation p where p.agent_key = v_head;

  if coalesce(v_ok, false) then
    if coalesce(v_head_tier, '') = 'probation' then
      select a.agent_key, p.score into v_delegate, v_score
        from org_agents a
        join agent_reputation p on p.agent_key = a.agent_key
       where a.department = p_dept_key and a.agent_key <> v_head
         and a.agent_key is distinct from p_author
         and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
         and p.tier <> 'probation' and p.score > coalesce(v_head_score, 0)
       order by p.score desc, a.agent_key
       limit 1;

      if v_delegate is not null then
        return jsonb_build_object('reviewer', v_delegate, 'available', true, 'delegated_from', v_head,
          'basis', 'department head ' || v_head || ' is on the probation reputation tier ('
                   || coalesce(v_head_score::text, '?') || '); review routed to the highest-scoring '
                   || 'available employee in ' || p_dept_key || ' (' || coalesce(v_score::text, '?') || ')');
      end if;
    end if;

    return jsonb_build_object('reviewer', v_head, 'available', true, 'delegated_from', null,
      'basis', 'department head (reputation ' || coalesce(v_head_score::text, 'unscored')
               || ', tier ' || coalesce(v_head_tier, 'unscored') || ')');
  end if;

  select d.delegate_to, d.basis into v_delegate, v_basis
  from delegation_rule d
  join org_agents a on a.agent_key = d.delegate_to
  where d.active and d.dept_key = p_dept_key and d.when_agent = v_head
    and a.agent_key is distinct from p_author
    and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
  order by d.rank limit 1;

  if v_delegate is null then
    select a.agent_key,
           'highest-scoring available employee in ' || p_dept_key
             || ' (reputation ' || coalesce(p.score::text, 'unscored') || ')'
      into v_delegate, v_basis
    from org_agents a
    left join agent_reputation p on p.agent_key = a.agent_key
    where a.department = p_dept_key and a.agent_key <> v_head
      and a.agent_key is distinct from p_author
      and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
      and coalesce(p.tier, 'standard') <> 'probation'
    order by p.score desc nulls last, fn_seniority_rank(a.seniority), a.agent_key
    limit 1;
  end if;

  if v_delegate is null then
    return jsonb_build_object('reviewer', null, 'available', false, 'delegated_from', v_head,
      'basis', 'department head unavailable and no delegate available - escalate');
  end if;

  return jsonb_build_object('reviewer', v_delegate, 'available', true,
    'delegated_from', v_head, 'basis', coalesce(v_basis, 'delegation'));
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_po_approve(p_po bigint, p_by text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare st text;
begin
  select status into st from public.po_orders where id=p_po;
  if st is null then raise exception 'PO % not found', p_po; end if;
  if st <> 'draft' then raise exception 'PO % is % (only draft can be approved)', p_po, st; end if;
  update public.po_orders set status='approved', approved_by=p_by, approved_at=now() where id=p_po;
  return p_po;
end $function$


CREATE OR REPLACE FUNCTION public.fn_po_orders_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  if new.quote_id is not null and new.inquiry_id is null then
    select q.inquiry_id into new.inquiry_id from public.quotes q where q.id = new.quote_id;
  end if;
  if new.inquiry_id is not null and (new.customer_id is null or new.project_id is null) then
    select coalesce(new.customer_id, i.customer_id), coalesce(new.project_id, i.project_id)
      into new.customer_id, new.project_id
      from public.inquiries i where i.id = new.inquiry_id;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_policy_int_array(p_key text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(array_agg(e::int order by e::int), '{}')
    from public.decision_policy d, jsonb_array_elements_text(d.value) e where d.key = p_key and jsonb_typeof(d.value) = 'array';
$function$


CREATE OR REPLACE FUNCTION public.fn_price_benchmark_flags_for_inquiry(p_inquiry_id uuid, p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with b as (select * from public.fn_price_benchmarks(p_include_demo, p_inquiry_id)),
  lines as (
    select q.id as quote_id, qi.line_no, qi.description, lower(i.category) as trade,
           public.fn_price_benchmark_key(qi.description, qi.specification) as item_key,
           public.fn_price_benchmark_unit(qi.unit) as unit,
           coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0)) as price
      from public.quotes q
      join public.inquiries i on i.id = q.inquiry_id
      join public.quote_items qi on qi.quote_id = q.id::text
     where q.inquiry_id = p_inquiry_id and coalesce(q.status, 'submitted') <> 'draft')
  select coalesce(jsonb_agg(jsonb_build_object('quote_id', l.quote_id, 'line_no', l.line_no, 'description', l.description, 'unit', l.unit)
           || public.fn_price_benchmark_judge(round(l.price, 2), b.median, b.p25, b.p75, b.quote_count, b.supplier_count, l.unit)
           || case when b.median is null then '{}'::jsonb else jsonb_build_object('benchmark',
                jsonb_build_object('median', b.median, 'p25', b.p25, 'p75', b.p75, 'iqr', b.iqr, 'count', b.quote_count, 'last_seen', b.last_seen)) end
           order by l.quote_id, l.line_no), '[]'::jsonb)
    from lines l
    left join b on b.trade = l.trade and b.item_key = l.item_key and b.unit = l.unit
$function$


CREATE OR REPLACE FUNCTION public.fn_price_benchmark_judge(p_price numeric, p_median numeric, p_p25 numeric, p_p75 numeric, p_count integer, p_suppliers integer, p_unit text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_iqr numeric; v_hi numeric; v_lo numeric; v_range text;
begin
  if p_median is null then
    return jsonb_build_object('status', 'no_benchmark_yet', 'reason', 'No benchmark yet: fewer than 5 quotes from 3 or more suppliers have priced this item.');
  end if;
  if p_price is null or p_price <= 0 then
    return jsonb_build_object('status', 'unpriced', 'reason', 'This line states no unit price, so it cannot be compared with the market range.');
  end if;
  v_iqr := greatest(p_p75 - p_p25, 0.10 * p_median);
  v_hi := p_p75 + 1.5 * v_iqr;  v_lo := greatest(p_p25 - 1.5 * v_iqr, 0);
  v_range := 'AED ' || to_char(p_p25, 'FM999,999,990.00') || ' to ' || to_char(p_p75, 'FM999,999,990.00')
          || ' per ' || p_unit || ' (middle half of ' || p_count || ' quotes from ' || p_suppliers
          || ' suppliers; median AED ' || to_char(p_median, 'FM999,999,990.00') || ')';
  if p_price > v_hi then
    return jsonb_build_object('status', 'well_above', 'pct_vs_median', round(100 * (p_price / p_median - 1)),
      'reason', 'Well above the UAE market range: AED ' || to_char(p_price, 'FM999,999,990.00') || ' is '
        || round(100 * (p_price / p_median - 1)) || '% over the median. Usual range ' || v_range
        || '. Ask the supplier what justifies it (brand, grade, scope or delivery).');
  elsif p_price < v_lo then
    return jsonb_build_object('status', 'well_below', 'pct_vs_median', round(100 * (p_price / p_median - 1)),
      'reason', 'Well below the UAE market range: AED ' || to_char(p_price, 'FM999,999,990.00') || ' is '
        || round(100 * (1 - p_price / p_median)) || '% under the median. Usual range ' || v_range
        || '. Check the specification, quantity and what is excluded before relying on it.');
  end if;
  return jsonb_build_object('status', 'within', 'pct_vs_median', round(100 * (p_price / p_median - 1)),
    'reason', 'Within the UAE market range. Usual range ' || v_range || '.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_price_benchmark_key(p_description text, p_specification text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select nullif(btrim(regexp_replace(lower(coalesce(p_description, '') || ' ' || coalesce(p_specification, '')),
                                     '[^a-z0-9؀-ۿ.]+', ' ', 'g')), '')
$function$


CREATE OR REPLACE FUNCTION public.fn_price_benchmark_observations(p_include_demo boolean DEFAULT false, p_exclude_inquiry uuid DEFAULT NULL::uuid)
 RETURNS TABLE(trade text, item_key text, unit text, unit_price numeric, quote_id uuid, supplier_id bigint, accepted boolean, seen_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select lower(i.category), public.fn_price_benchmark_key(qi.description, qi.specification),
         public.fn_price_benchmark_unit(qi.unit),
         avg(coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0))),
         q.id, q.supplier_id, bool_or(q.status in ('accepted', 'won', 'revealed')), max(coalesce(qi.created_at, q.created_at))
    from public.quote_items qi
    join public.quotes q on q.id::text = qi.quote_id
    join public.inquiries i on i.id = q.inquiry_id
    left join public.leads l on l.id = q.supplier_id
   where coalesce(q.status, 'submitted') not in ('draft', 'withdrawn', 'cancelled')
     and q.supplier_id is not null
     and i.category is not null
     and coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0)) > 0
     and public.fn_price_benchmark_key(qi.description, qi.specification) is not null
     and (p_exclude_inquiry is null or q.inquiry_id <> p_exclude_inquiry)
     and (p_include_demo or not (public.fn_inquiry_is_demo(q.inquiry_id)
                                 or coalesce(l.is_demo, false)
                                 or coalesce(l.company_name, '') ilike 'ZZ DEMO%'))
   group by 1, 2, 3, q.id, q.supplier_id
$function$


CREATE OR REPLACE FUNCTION public.fn_price_benchmark_unit(p_unit text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(nullif(btrim(regexp_replace(lower(coalesce(p_unit, '')), '[^a-z0-9]+', '', 'g')), ''), 'each')
$function$


CREATE OR REPLACE FUNCTION public.fn_price_benchmarks(p_include_demo boolean DEFAULT false, p_exclude_inquiry uuid DEFAULT NULL::uuid)
 RETURNS TABLE(trade text, item_key text, unit text, median numeric, p25 numeric, p75 numeric, iqr numeric, quote_count integer, supplier_count integer, accepted_count integer, last_seen timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select o.trade, o.item_key, o.unit,
         round((percentile_cont(0.5)  within group (order by o.unit_price))::numeric, 2),
         round((percentile_cont(0.25) within group (order by o.unit_price))::numeric, 2),
         round((percentile_cont(0.75) within group (order by o.unit_price))::numeric, 2),
         round((percentile_cont(0.75) within group (order by o.unit_price)
              - percentile_cont(0.25) within group (order by o.unit_price))::numeric, 2),
         count(distinct o.quote_id)::int, count(distinct o.supplier_id)::int,
         count(distinct o.quote_id) filter (where o.accepted)::int, max(o.seen_at)
    from public.fn_price_benchmark_observations(p_include_demo, p_exclude_inquiry) o
   group by 1, 2, 3
  having count(distinct o.quote_id) >= 5 and count(distinct o.supplier_id) >= 3
$function$


CREATE OR REPLACE FUNCTION public.fn_price_confidence(p_category text, p_amount numeric, p_quantity numeric, p_unit text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s          record;
  iqr        numeric;
  z          numeric;
  conf       int;
  band       text;
  v_basis    text;
  v_unit     text;
  v_rate     numeric;
  v_n        int;
  v_p25      numeric;
  v_med      numeric;
  v_p75      numeric;
  v_srcs     jsonb;
  v_asof     date;
  v_ref      jsonb;
  v_items    jsonb;
  v_conf_lbl text;
begin
  -- Always available, whatever happens below: what this trade's per-unit bands actually look like.
  select coalesce(jsonb_agg(jsonb_build_object(
           'unit', r.unit, 'low', r.lo, 'high', r.hi, 'n', r.n, 'source', r.src) order by r.n desc), '[]'::jsonb)
    into v_ref
    from (select pb.unit, min(pb.low) lo, max(pb.high) hi, count(*) n,
                 case when bool_or(pb.source_kind = 'blog_post') then 'quotesdone_cost_guide' else 'estate_extract' end src
            from public.price_benchmark pb
           where pb.category = p_category and pb.source_kind <> 'gap' and pb.basis_kind = 'per_unit'
           group by pb.unit) r;

  -- THE NAMED BANDS. A category-wide answer is necessarily wide, because one category legitimately
  -- holds a plain gypsum ceiling at AED 35-70/m2 and a demountable modular partition at AED
  -- 900-2,000/m2. Widening the IQR is the honest response to that -- but it is not a judgement, and
  -- the judgement lives in the item name. So every answer also carries the individual named bands,
  -- which is the row a sales engineer actually reads before saying a quote is high.
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', i.item, 'unit', i.unit, 'low', i.low, 'high', i.high,
           'source', i.source_kind || ':' || i.source_ref, 'as_of', i.as_of)
           order by i.low), '[]'::jsonb)
    into v_items
    from (select distinct on (pb.item, pb.unit) pb.item, pb.unit, pb.low, pb.high,
                 pb.source_kind, pb.source_ref, pb.as_of
            from public.price_benchmark pb
           where pb.category = p_category and pb.source_kind <> 'gap' and pb.item is not null
           order by pb.item, pb.unit, (case when pb.source_kind = 'blog_post' then 0 else 1 end)
           limit 40) i;

  -- ---------------------------------------------------------------------------------------------
  -- 1. LIVE QUOTES FIRST. What the company actually transacted outranks anything published.
  -- ---------------------------------------------------------------------------------------------
  select * into s from public.category_price_stats where category = p_category;
  if s is not null and s.n >= 4 then
    iqr := nullif(s.p75 - s.p25, 0);
    if iqr is null then iqr := nullif(s.sd, 0); end if;
    if iqr is not null then
      z := abs(p_amount - s.median) / iqr;
      conf := greatest(5, least(99, round(100 * exp(-0.6 * z))::int));
      if    p_amount < s.p25 - 1.5 * iqr           then band := 'suspiciously_low';
      elsif p_amount > s.p75 + 1.5 * iqr           then band := 'suspiciously_high';
      elsif p_amount between s.p25 and s.p75       then band := 'fair';
      else                                              band := 'within_range';
      end if;
      return jsonb_build_object(
        'confidence', conf, 'band', band, 'median', s.median, 'p25', s.p25, 'p75', s.p75,
        'n', s.n, 'n_quotes', s.n, 'basis', 'live_quotes', 'reference_bands', v_ref, 'item_bands', v_items);
    end if;
  end if;

  -- ---------------------------------------------------------------------------------------------
  -- 2. THE BENCHMARKS. Published company cost guides preferred over machine-extracted estate text;
  --    a category never mixes the two, so the caller always knows which grade of evidence answered.
  -- ---------------------------------------------------------------------------------------------
  if p_quantity is not null and p_quantity > 0 then
    -- A quantity was supplied, so the comparison is a UNIT RATE against per-unit benchmarks.
    select coalesce(p_unit, (select pb.unit from public.price_benchmark pb
                              where pb.category = p_category and pb.source_kind <> 'gap'
                                and pb.basis_kind = 'per_unit'
                              group by pb.unit order by count(*) desc limit 1))
      into v_unit;
    v_rate := p_amount / p_quantity;
    v_basis := 'published_range_midpoint_per_unit';
  else
    v_unit  := null;
    v_rate  := p_amount;
    v_basis := 'published_range_midpoint_per_job';
  end if;

  -- count(*) = 0 FIRST, and it is not defensive noise. bool_or over an empty set returns NULL, and
  -- `case when NULL then 'blog_post' else 'kb_chunk' end` is 'kb_chunk' -- so without this guard a
  -- category with NO benchmark at all reports that it has kb_chunk evidence, and the refusal that
  -- should say "the estate holds no price for this trade" never fires. Measured: elevators, a trade
  -- whose gap row this file's sibling deliberately recorded, came back 'benchmark_has_no_spread'
  -- instead of the gap refusal. Same family as least(100.0, NULL) = 100.0.
  select case when count(*) = 0 then null
              when bool_or(pb.source_kind = 'blog_post') then 'blog_post'
              else 'kb_chunk' end
    into v_conf_lbl
    from public.price_benchmark pb
   where pb.category = p_category and pb.source_kind <> 'gap'
     and (case when v_unit is null then pb.basis_kind = 'job' else pb.basis_kind = 'per_unit' and pb.unit = v_unit end);

  if v_conf_lbl is null then
    return jsonb_build_object(
      'confidence', null,
      'band', case when v_ref = '[]'::jsonb then 'insufficient_data' else 'benchmark_is_per_unit' end,
      'n', 0, 'n_quotes', 0, 'basis', 'no_matching_benchmark',
      'refusal', case
        when v_ref = '[]'::jsonb then
          'No AED evidence for this trade exists anywhere in the estate, and a figure was deliberately not guessed. See price_benchmark where source_kind = ''gap''.'
        else
          'This trade is priced per unit in every piece of evidence the estate holds, and no quantity was supplied, so a whole-job amount cannot be judged against it. Pass p_quantity (and optionally p_unit), or read reference_bands.' end,
      'reference_bands', v_ref, 'item_bands', v_items);
  end if;

  select count(*),
         percentile_cont(0.25) within group (order by v.x)::numeric,
         percentile_cont(0.50) within group (order by v.x)::numeric,
         percentile_cont(0.75) within group (order by v.x)::numeric,
         max(v.as_of),
         coalesce(jsonb_agg(distinct v.src), '[]'::jsonb)
    into v_n, v_p25, v_med, v_p75, v_asof, v_srcs
    from (
      select unnest(array[pb.low, pb.high]) as x, pb.as_of,
             pb.source_kind || ':' || pb.source_ref as src
        from public.price_benchmark pb
       where pb.category = p_category
         and pb.source_kind = v_conf_lbl
         and (case when v_unit is null then pb.basis_kind = 'job'
                   else pb.basis_kind = 'per_unit' and pb.unit = v_unit end)
    ) v;

  -- v_n counts low/high endpoints, two per band. Report the number of BANDS, which is what a reader
  -- means by "how much evidence is behind this".
  v_n := v_n / 2;

  iqr := nullif(v_p75 - v_p25, 0);
  if iqr is null then
    return jsonb_build_object('confidence', null, 'band', 'insufficient_data', 'n', v_n, 'n_quotes', 0,
      'basis', 'benchmark_has_no_spread', 'reference_bands', v_ref, 'item_bands', v_items);
  end if;

  z := abs(v_rate - v_med) / iqr;
  conf := greatest(5, least(99, round(100 * exp(-0.6 * z))::int));
  if    v_rate < v_p25 - 1.5 * iqr       then band := 'suspiciously_low';
  elsif v_rate > v_p75 + 1.5 * iqr       then band := 'suspiciously_high';
  elsif v_rate between v_p25 and v_p75   then band := 'fair';
  else                                        band := 'within_range';
  end if;

  return jsonb_build_object(
    'confidence', conf,
    'band', band,
    'median', round(v_med, 0), 'p25', round(v_p25, 0), 'p75', round(v_p75, 0),
    'n', v_n,
    -- 0, always, on this path. A benchmark is published evidence, never a sample of this company's
    -- own quotes, and a caller that gates on real trading history must be able to see the difference.
    'n_quotes', 0,
    'basis', v_basis,
    'evidence_grade', case when v_conf_lbl = 'blog_post' then 'published_by_quotesdone' else 'extracted_from_estate' end,
    'unit', coalesce(v_unit, 'job'),
    'compared_rate', round(v_rate, 2),
    'as_of', v_asof,
    'sources', v_srcs,
    'reference_bands', v_ref, 'item_bands', v_items);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_price_confidence(p_category text, p_amount numeric)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_price_confidence(p_category, p_amount, null::numeric, null::text);
$function$


CREATE OR REPLACE FUNCTION public.fn_price_guidance(p_trade text, p_limit integer DEFAULT 6, p_asked_item text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_gap text; v_items jsonb; v_lim int := greatest(1, coalesce(p_limit, 6));
begin
  -- No trade: the caller has not reasoned yet. Hand it the trades we publish for, never a guess.
  if p_trade is null then
    return jsonb_build_object('ok', false, 'reason', 'needs_reasoning',
      'trades', (select coalesce(jsonb_agg(distinct pb.category order by pb.category), '[]'::jsonb) from public.price_benchmark pb),
      'note', 'Decide by reasoning whether the question asks what something costs and which of these trades it is about.');
  end if;
  if not exists (select 1 from public.price_benchmark pb where pb.category = p_trade) then
    return jsonb_build_object('ok', false, 'reason', 'no_trade_matched', 'trade', p_trade,
      'note', 'QuotesDone publishes no range for this trade. Say so plainly and offer to collect quotes; never substitute a nearby trade.');
  end if;
  select pb.gap_reason into v_gap from public.price_benchmark pb where pb.category = p_trade and pb.source_kind = 'gap' limit 1;
  if v_gap is not null then
    return jsonb_build_object('ok', false, 'reason', 'trade_has_a_recorded_gap', 'trade', p_trade, 'gap_reason', v_gap,
      'note', 'Tell the visitor plainly that we publish no range for this trade rather than estimating one, and offer to put it out to suppliers.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', i.item, 'unit', i.unit, 'basis', i.basis_kind, 'low', i.low, 'high', i.high,
           'currency', coalesce(i.currency, 'AED'), 'evidence', left(i.evidence, 180),
           'source', i.source_kind || coalesce(':' || i.source_ref, ''), 'as_of', i.as_of) order by i.low), '[]'::jsonb)
    into v_items
    from (
      select distinct on (pb.item, pb.unit) pb.item, pb.unit, pb.basis_kind, pb.low, pb.high, pb.currency, pb.evidence,
             pb.source_kind, pb.source_ref, pb.as_of
        from public.price_benchmark pb
       where pb.category = p_trade and pb.source_kind <> 'gap' and pb.item is not null
       -- the same tiebreak as before: the same question always gets the same band, auditable to one row
       order by pb.item, pb.unit, (case when pb.source_kind = 'blog_post' then 0 else 1 end), pb.as_of desc nulls last, pb.id
    ) i;
  return jsonb_build_object(
    'ok', true, 'trade', p_trade, 'resolved_via', 'reasoning',
    'asked_item', nullif(btrim(coalesce(p_asked_item, '')), ''),
    'band_count', jsonb_array_length(v_items),
    'bands', case when jsonb_array_length(v_items) > v_lim
                  then (select jsonb_agg(s.e) from (select e from jsonb_array_elements(v_items) e limit v_lim) s)
                  else v_items end,
    'how_to_use', 'These are PUBLISHED GUIDE RANGES in AED for the UAE market, for the trade as a whole, with their source '
               || 'and date. They are orientation, never a quotation. QuotesDone does not price the work - suppliers do. '
               || 'Give the range, name it as a guide, and offer to collect real quotes. Never present a single figure as '
               || 'the price, never average a band into one number, and never state a figure that is not in bands above. '
               || 'If asked_item is set and no band is for that item, say plainly that the platform publishes no range for '
               || 'it rather than letting the trade bands stand in for it.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_priority_backlog_reorder()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_rank smallint; v_n int;
begin
  v_rank := case new.payload->>'max_severity' when 'high' then 2 when 'medium' then 1 else 0 end;
  if v_rank = 0 or new.correlation_id is null then return new; end if;
  update public.org_tasks t
     set priority = greatest(t.priority, v_rank), updated_at = now()
   where t.status not in ('done','closed','cancelled')
     and t.priority < v_rank
     and t.id in (select d.task_id from public.event_delivery d
                    join public.company_event e on e.id = d.event_id
                   where e.correlation_id = new.correlation_id and d.task_id is not null);
  get diagnostics v_n = row_count;
  if v_n > 0 then
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('priority_backlog_reorder', now(), now(), 'ok',
            jsonb_build_object('event_id', new.id, 'correlation_id', new.correlation_id, 'rank', v_rank, 'tasks_moved', v_n),
            'priority.updated (' || coalesce(new.payload->>'max_severity','?') || ') moved ' || v_n
            || ' open task(s) of the episode ahead of the created_at queue.');
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_procurement_analysis(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare minp numeric; maxp numeric; medp numeric; nq int;
        matrix jsonb := '[]'::jsonb; r record; rec jsonb := null; best numeric := -1;
        price_score numeric; qual numeric; rep numeric; warr_m int; warr_score numeric;
        lead_w int; lead_score numeric; comp numeric; value numeric; risks text[]; letter text; idx int := 0;
begin
  select count(*), min(quote_amount), max(quote_amount), percentile_cont(0.5) within group (order by quote_amount)
    into nq, minp, maxp, medp
  from public.quotes where inquiry_id=p_id and coalesce(quote_amount,0) > 0
    and coalesce(status,'') not in ('withdrawn','rejected','expired');
  if nq = 0 then return jsonb_build_object('ready',false,'quote_count',0,'note','No priced quotes yet.'); end if;

  for r in
    select q.*, l.company_name,
           rp.reputation_index, rp.review_count as rep_reviews, rp.dispute_rate_pct
    from public.quotes q
    left join public.leads l on l.id=q.supplier_id
    left join public.supplier_reputation rp on rp.supplier_id=q.supplier_id
    where q.inquiry_id=p_id and coalesce(q.quote_amount,0) > 0
      and coalesce(q.status,'') not in ('withdrawn','rejected','expired')
    order by q.quote_amount asc
  loop
    idx := idx + 1; letter := chr(64+idx);  -- A, B, C...
    price_score := case when maxp=minp then 100 else round((maxp - r.quote_amount)/(maxp-minp)*100) end;
    qual := coalesce((r.quality->>'score')::numeric, 0);
    rep := case when coalesce(r.rep_reviews,0) > 0 then r.reputation_index else null end;
    warr_m := coalesce((regexp_match(coalesce(r.warranty,''),'(\d+)'))[1]::int, 0);
    warr_score := case when r.warranty is null then 0 else least(100, warr_m::numeric/24*100) end;
    lead_w := coalesce((regexp_match(coalesce(r.lead_time,''),'(\d+)'))[1]::int, null);
    lead_score := case when lead_w is null then 50 else greatest(0, 100 - lead_w*8) end;
    comp := case when (r.quality->>'mandatory_total') is not null and (r.quality->>'mandatory_total')::numeric>0
                 then round((r.quality->>'mandatory_present')::numeric/(r.quality->>'mandatory_total')::numeric*100) else qual end;
    value := case when rep is null
                  then round((0.35*qual + 0.30*price_score + 0.10*warr_score + 0.10*lead_score)/0.85)
                  else round(0.35*qual + 0.30*price_score + 0.15*rep + 0.10*warr_score + 0.10*lead_score) end;

    risks := '{}';
    if qual < 50 then risks := array_append(risks,'Quote incomplete — low quality score ('||qual||'/100)'); end if;
    if r.expires_at is not null and r.expires_at < now() then risks := array_append(risks,'Quote has expired'); end if;
    if medp>0 and r.quote_amount < 0.75*medp then risks := array_append(risks,'Price well below median — verify the scope is not under-quoted'); end if;
    if r.warranty is null then risks := array_append(risks,'No warranty stated'); end if;
    if coalesce(r.payment_terms,'')='' then risks := array_append(risks,'No payment terms stated'); end if;
    if coalesce(r.dispute_rate_pct,0) > 10 then risks := array_append(risks,'Supplier has a dispute history ('||round(r.dispute_rate_pct)||'%)'); end if;
    if array_length(risks,1) is null then risks := array_append(risks,'No major risks flagged'); end if;

    matrix := matrix || jsonb_build_object(
      'label','Supplier '||letter, 'quote_id',r.id, 'supplier_id',r.supplier_id, 'company_name',r.company_name,
      'price', r.quote_amount, 'price_vs_low_pct', case when minp>0 then round((r.quote_amount-minp)/minp*100,1) else 0 end,
      'lead_time', r.lead_time, 'warranty', r.warranty, 'payment_terms', r.payment_terms, 'validity', r.validity,
      'quality_score', qual, 'completeness_pct', comp, 'reputation', round(rep), 'reputation_basis', case when rep is null then 'not yet rated on QuotesDone' else 'QuotesDone reviews' end,
      'value_score', value, 'risks', to_jsonb(risks));

    if value > best then best := value;
      rec := jsonb_build_object('label','Supplier '||letter,'supplier_id',r.supplier_id,'company_name',r.company_name,
        'value_score',value,'price',r.quote_amount,
        'why','Best overall value: quality '||qual||'/100, price score '||price_score||'/100'
          ||case when qual>=70 then ', well-documented' else ', but confirm the missing quote details' end
          ||case when r.quote_amount=minp then ', and it is the lowest price' else '' end||'.');
    end if;
  end loop;

  return jsonb_build_object(
    'ready', nq>=2, 'quote_count', nq,
    'price_range', jsonb_build_object('low',minp,'median',medp,'high',maxp,'spread_pct',case when minp>0 then round((maxp-minp)/minp*100,1) else 0 end),
    'matrix', matrix,
    'recommendation', rec,
    'note', case when nq=1 then 'Only one quote so far — comparison needs at least two.' else null end
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_prompt_approve_draft(p_key text, p_version integer, p_by text DEFAULT 'founder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not exists(select 1 from prompt_versions where prompt_key=p_key and version=p_version and status='draft') then
    return jsonb_build_object('error','draft_not_found'); end if;
  update prompt_versions set status='deprecated' where prompt_key=p_key and status='active';
  update prompt_versions set status='active', rollout_pct=100, approved_by=p_by where prompt_key=p_key and version=p_version;
  update prompts set active_version=p_version, updated_at=now() where key=p_key;
  update agent_actions set status='approved', decided_at=now(), decided_by=p_by
    where kind='prompt_approval' and detail->>'key'=p_key and (detail->>'version')::int=p_version and status in ('pending','needs_review');
  return jsonb_build_object('ok',true,'active_version',p_version);
end $function$


CREATE OR REPLACE FUNCTION public.fn_prompt_reject_draft(p_key text, p_version integer, p_by text DEFAULT 'founder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update prompt_versions set status='discarded' where prompt_key=p_key and version=p_version and status='draft';
  update agent_actions set status='rejected', decided_at=now(), decided_by=p_by
    where kind='prompt_approval' and detail->>'key'=p_key and (detail->>'version')::int=p_version and status in ('pending','needs_review');
  return jsonb_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.fn_prompt_rollback(p_key text, p_to_version integer, p_by text DEFAULT 'agent'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_status text; v_approved text;
begin
  select status, approved_by into v_status, v_approved
    from prompt_versions where prompt_key = p_key and version = p_to_version;

  if v_status is null then
    return jsonb_build_object('error', 'version not found');
  end if;

  -- ROLLBACK RESTORES TRUST, IT DOES NOT CONFER IT.
  if v_approved is null or v_status not in ('deprecated', 'active') then
    return jsonb_build_object(
      'error', 'refused',
      'reason', format(
        'version %s of %s is %s and was approved by %s, so it has never been trusted in '
        || 'production. Rollback restores a version that was previously approved; it is not a '
        || 'route to activate one that was not. Use fn_prompt_approve_draft to approve it first.',
        p_to_version, p_key, v_status, coalesce(v_approved, 'nobody')),
      'status', v_status, 'approved_by', v_approved);
  end if;

  update prompt_versions set status = 'deprecated'
   where prompt_key = p_key and status = 'active';

  -- approved_by is NOT touched: it records who approved this version, not who restored it.
  -- rollout_pct is set, or a version cut off mid-rollout returns to serving that fraction.
  update prompt_versions set status = 'active', rollout_pct = 100
   where prompt_key = p_key and version = p_to_version;

  update prompts set active_version = p_to_version, updated_at = now() where key = p_key;

  return jsonb_build_object('ok', true, 'active_version', p_to_version,
    'approved_by', v_approved, 'rolled_back_by', p_by);
end $function$


CREATE OR REPLACE FUNCTION public.fn_protect_app_secret()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  protected text[] := array['inbound_secret','deploy_secret','stripe_secret_key','service_role_key','resend_api_key'];
  k text := coalesce(old.key, new.key);
begin
  if tg_op = 'DELETE' then
    if old.key = any(protected) then
      raise exception 'app_secrets.% is load-bearing for edge-function authentication and cannot be deleted; rotate the value instead', old.key
        using errcode = 'raise_exception';
    end if;
    return old;
  end if;
  if new.key = any(protected) then
    if new.value is null or length(btrim(new.value)) < 24 then
      raise exception 'app_secrets.% must stay a non-empty secret of at least 24 characters (got %); an empty value would make every __secret guard pass',
        new.key, coalesce(length(btrim(new.value)), 0)
        using errcode = 'raise_exception';
    end if;
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_prune_website_error_events(p_limit integer DEFAULT 2000)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_deleted int;
begin
  if p_limit is null or p_limit < 1 or p_limit > 5000 then
    raise exception 'fn_prune_website_error_events: p_limit must be between 1 and 5000, got %', p_limit;
  end if;
  with doomed as (
    select id from public.error_events
     where source = 'website'
       and created_at < now() - interval '8 days'           -- nothing younger can be expired
       and ((kind = 'site_report_ready' and created_at < now() - interval '8 days')
         or (kind is distinct from 'site_report_ready' and created_at < now() - interval '14 days'))
     order by created_at                                    -- oldest first: walks the index and stops
     limit p_limit)
  delete from public.error_events e using doomed d where e.id = d.id;
  get diagnostics v_deleted = row_count;
  -- No count of what is LEFT: that was an unconditional count(*) over every website row on every
  -- tick — an unbounded read to produce a number nobody reads (review of #852). `more` is what the
  -- caller needs, and it costs nothing.
  return jsonb_build_object('deleted', v_deleted, 'limit', p_limit, 'more', v_deleted = p_limit);
end $function$


CREATE OR REPLACE FUNCTION public.fn_public_holiday_moves_the_posts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.marketing_post set scheduled_at = scheduled_at, updated_at = now()
   where status in ('draft', 'scheduled') and (scheduled_at at time zone 'Asia/Dubai')::date = new.holiday_date;
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_public_site_counters()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with sup as (
  select l.id, sc.trades
    from leads l
    join supplier_capabilities sc on sc.supplier_id = l.id
   where sc.confirmed_at is not null
     and fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status,
                         l.permanently_closed, l.chat_strikes)
     and coalesce(l.company_name, '') not ilike 'ZZ DEMO%'
),
real_inq as (
  select i.id, i.created_at, i.status
    from inquiries i
   where coalesce(i.status, '') not in ('draft', 'cancelled')
     and not exists (select 1 from customers c
                      where c.id = i.customer_id and c.email ilike '%example.invalid')
),
firstq as (
  select i.id, extract(epoch from (min(q.created_at) - i.created_at)) / 3600.0 as h
    from real_inq i
    join quotes q on q.inquiry_id = i.id
   where i.created_at >= now() - interval '30 days'
   group by i.id, i.created_at
),
per as (
  select t, count(distinct sup.id) as n from sup, unnest(sup.trades) as t group by t
),
k as (
  select (select count(*) from sup) as suppliers,
         (select count(*) from real_inq
           where created_at >= (date_trunc('month', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai')) as jobs,
         (select count(*) from firstq) as quoted_jobs,
         (select percentile_cont(0.5) within group (order by h) from firstq) as median_h,
         (select count(*) from per) as trades
)
select jsonb_build_object(
  'licence_verified_suppliers', case when k.suppliers >= 10 then k.suppliers end,
  'jobs_this_month',            case when k.jobs >= 5 then k.jobs end,
  'median_hours_to_first_quote', case when k.quoted_jobs >= 5 then round(k.median_h::numeric, 1) end,
  'median_basis_jobs',          case when k.quoted_jobs >= 5 then k.quoted_jobs end,
  'categories_covered',         case when k.trades >= 3 then k.trades end,
  'per_trade',                  coalesce((select jsonb_object_agg(t, n) from per), '{}'::jsonb),
  'floors', jsonb_build_object('suppliers', 10, 'jobs_this_month', 5, 'quoted_jobs_30d', 5, 'categories', 3),
  'measured_at', now())
from k;
$function$


CREATE OR REPLACE FUNCTION public.fn_public_worked_case()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with deal as (
  select t.inquiry_id, t.quote_id, t.revealed_at, i.category, i.emirate, i.created_at
    from transactions t
    join inquiries i on i.id = t.inquiry_id
    join leads l on l.id = t.supplier_id
   where t.fee_status = 'paid'
     and t.refund_status is null
     and i.completed_at is not null
     and coalesce(l.company_name, '') not ilike 'ZZ DEMO%'
     and not exists (select 1 from customers c
                      where c.id = i.customer_id and c.email ilike '%example.invalid')
   order by t.revealed_at desc nulls last
   limit 1
)
select case when d.inquiry_id is null then null else jsonb_build_object(
  'category', d.category,
  'emirate', d.emirate,
  'posted_month', to_char(d.created_at at time zone 'Asia/Dubai', 'YYYY-MM'),
  'days_to_reveal', case when d.revealed_at is not null
                         then round(extract(epoch from d.revealed_at - d.created_at) / 86400.0)::int end,
  'quotes', (
    select jsonb_agg(jsonb_build_object(
             'amount', round(q.quote_amount / 100.0) * 100,
             'chosen', q.id = d.quote_id,
             'licence_verified', coalesce(l.verified, false) and l.approval_status = 'approved',
             'response_rate', l.rv_response_rate,
             'jobs_completed', (select count(*) from inquiries x
                                 where x.hired_supplier_id = l.id and x.completed_at is not null),
             'rating', l.app_rating)
           order by q.quote_amount)
      from quotes q join leads l on l.id = q.supplier_id
     where q.inquiry_id = d.inquiry_id and q.quote_amount > 0)
) end
from (select 1) one left join deal d on true;
$function$


CREATE OR REPLACE FUNCTION public.fn_quality_snapshot_resolve_agent()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_key text;
begin
  if new.agent is null then return new; end if;
  if exists (select 1 from public.org_agents o where o.agent_key = new.agent and o.active) then
    return new;
  end if;
  v_key := public.fn_org_agent_resolve(new.agent);
  if v_key is not null then new.agent := v_key; end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_query_platform(p_topic text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb;
begin
  case lower(coalesce(p_topic,''))
    when 'topics' then
      v := jsonb_build_object('topics', jsonb_build_array(
        'knowledge','agents','agent_ops','ai','analytics','company','customers','documents',
        'ea','exec','finance','fraud','governance','marketing','marketplace','operations',
        'refunds','reports','strategy','suppliers','supplier_360','customer_360','rfq_360','funnel'));
    when 'knowledge'   then v := to_jsonb(fn_ws_knowledge());
    when 'agents'      then v := to_jsonb(fn_ws_agents());
    when 'agent_ops'   then v := to_jsonb(fn_ws_agent_ops(coalesce(p_args->>'agent','')));
    when 'ai'          then v := to_jsonb(fn_ws_ai());
    when 'analytics'   then v := to_jsonb(fn_ws_analytics());
    when 'company'     then v := to_jsonb(fn_ws_company());
    when 'customers'   then v := to_jsonb(fn_ws_customers());
    when 'documents'   then v := to_jsonb(fn_ws_documents());
    when 'ea'          then v := to_jsonb(fn_ws_ea());
    when 'exec'        then v := to_jsonb(fn_ws_exec());
    when 'finance'     then v := to_jsonb(fn_ws_finance());
    when 'fraud'       then v := to_jsonb(fn_ws_fraud());
    when 'governance'  then v := to_jsonb(fn_ws_governance());
    when 'marketing'   then v := to_jsonb(fn_ws_marketing());
    when 'marketplace' then v := to_jsonb(fn_ws_marketplace());
    when 'operations'  then v := to_jsonb(fn_ws_operations());
    when 'refunds'     then v := to_jsonb(fn_ws_refunds());
    when 'reports'     then v := to_jsonb(fn_ws_reports());
    when 'strategy'    then v := to_jsonb(fn_ws_strategy());
    when 'suppliers'   then v := to_jsonb(fn_ws_suppliers(coalesce(p_args,'{}'::jsonb)));
    when 'supplier_360' then v := to_jsonb(fn_ws_supplier_360((p_args->>'id')::bigint));
    when 'customer_360' then v := to_jsonb(fn_ws_customer_360((p_args->>'id')::uuid));
    when 'rfq_360'      then v := to_jsonb(fn_ws_rfq_360((p_args->>'id')::uuid));
    when 'funnel'       then v := to_jsonb(funnel_metrics(coalesce((p_args->>'days')::int,30)));
    else v := jsonb_build_object('error','unknown_topic','hint','call with topic=topics to list valid topics');
  end case;
  return coalesce(v,'{}'::jsonb);
exception when others then
  return jsonb_build_object('error','query_failed','topic',p_topic,'detail',sqlerrm);
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_aspect_reading_record(p_quote_id uuid, p_content_md5 text, p_present text[], p_held_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_status text := case when p_present is null then 'needs_reasoning' else 'reasoned' end; v_bad text[]; q public.quotes; v_rescored boolean := false;
begin
  select * into q from public.quotes where id = p_quote_id;
  if not found then raise exception 'no quote %', p_quote_id using errcode = 'P0002'; end if;
  select array_agg(x) into v_bad from unnest(coalesce(p_present, '{}'::text[])) x
   where not exists (select 1 from public.category_quote_specs c
                      where c.aspect = x and c.spec_group = public.fn_quote_spec_group(coalesce((select category from public.inquiries where id = q.inquiry_id), '')));
  if v_bad is not null then raise exception 'not an aspect of this quote''s group: %', v_bad using errcode = '22023'; end if;
  insert into public.quote_aspect_reading as a (quote_id, content_md5, present, status, held_id, reasoned_at, updated_at)
  values (p_quote_id, p_content_md5, p_present, v_status, p_held_id, case when p_present is null then null else now() end, now())
  on conflict (quote_id) do update set content_md5 = excluded.content_md5, present = excluded.present, status = excluded.status,
    held_id = coalesce(excluded.held_id, a.held_id), reasoned_at = excluded.reasoned_at, updated_at = now()
  where not (excluded.status = 'needs_reasoning' and a.status = 'reasoned' and a.content_md5 = excluded.content_md5);
  if v_status = 'reasoned' and p_content_md5 = md5(coalesce(public.fn_quote_aspect_text(q), '')) then
    update public.quotes set quality = quality where id = p_quote_id;   -- re-fires trg_quote_quality
    v_rescored := true;
  end if;
  return jsonb_build_object('quote_id', p_quote_id, 'status', v_status, 'rescored', v_rescored,
                            'quality', (select quality from public.quotes where id = p_quote_id));
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_aspect_text(p_q quotes)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select concat_ws(E'\n', p_q.scope, p_q.conditions, p_q.exclusions, p_q.notes, p_q.warranty, p_q.payment_terms,
                   p_q.lead_time, p_q.validity,
                   (select string_agg(concat_ws(' ', qi.description, qi.brand, qi.model, qi.specification), E'\n' order by qi.id)
                      from public.quote_items qi where qi.quote_id = p_q.id::text))
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_aspects_due(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q public.quotes; v_grp text; v_text text;
begin
  select * into q from public.quotes where id = p_quote_id;
  if not found then return null; end if;
  v_grp := public.fn_quote_spec_group(coalesce((select category from public.inquiries where id = q.inquiry_id), ''));
  if v_grp is null or not exists (select 1 from public.category_quote_specs where spec_group = v_grp) then return null; end if;
  v_text := coalesce(public.fn_quote_aspect_text(q), '');
  if exists (select 1 from public.quote_aspect_reading a where a.quote_id = p_quote_id and a.content_md5 = md5(v_text)) then return null; end if;
  return jsonb_build_object('quote_id', p_quote_id, 'content_md5', md5(v_text), 'text', left(v_text, 8000), 'spec_group', v_grp,
    'aspects', (select jsonb_agg(jsonb_build_object('aspect', c.aspect, 'label', c.label, 'mandatory', c.mandatory, 'note', c.note)
                                 order by c.mandatory desc, c.aspect)
                  from public.category_quote_specs c where c.spec_group = v_grp));
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_coach(p_quote uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare sc jsonb; lbls text[]; miss text; sup record; co text; subject text; msg text;
begin
  sc := public.fn_quote_structured_score(p_quote::text);
  if (sc->>'submittable')::boolean then return jsonb_build_object('ok',true,'submittable',true); end if;
  lbls := '{}';
  for miss in select jsonb_array_elements_text(sc->'missing') loop
    lbls := array_append(lbls, case miss
      when 'line_items' then 'an itemised breakdown — add each item as a line'
      when 'unit_prices_on_all_items' then 'a unit price on every line item'
      when 'brand_model_per_item' then 'the brand and model for each item'
      when 'specifications' then 'technical specifications for the items'
      when 'labour_or_installation' then 'labour / installation cost'
      when 'warranty' then 'the warranty offered'
      when 'lead_time' then 'the lead time / delivery timeline'
      when 'payment_terms' then 'your payment terms'
      when 'exclusions' then 'what is excluded from the quote'
      when 'validity' then 'how long the quote is valid'
      else miss end);
  end loop;
  select l.company_name, l.claimed_by, l.email into sup
    from public.quotes q join public.leads l on l.id=q.supplier_id where q.id=p_quote;
  co := coalesce(sup.company_name,'there');
  if not exists (select 1 from public.notifications n where n.type='quote_coaching'
                   and n.to_email=coalesce(sup.claimed_by,sup.email) and n.created_at > now()-interval '24 hours'
                   and n.body like '%'||p_quote::text||'%') then
    subject := 'Your quote needs a few more details before we can send it';
    msg := 'Hi '||co||','||E'\n\n'||'Thanks for your quote. To make it competitive and send it to the customer, please add the following in your supplier portal:'||E'\n\n'
      ||'• '||array_to_string(lbls, E'\n• ')||E'\n\n'
      ||'Detailed quotes (with brands, specifications and a clear itemised breakdown) win far more often. Open your portal, complete these, and we will send it to the customer right away.'||E'\n\n'||'(ref '||p_quote::text||')';
    insert into public.notifications(type,to_email,to_role,channel,subject,body,status)
      values('quote_coaching', coalesce(sup.claimed_by,sup.email), 'supplier','email',subject,msg,'queued');
  end if;
  return jsonb_build_object('ok',true,'submittable',false,'missing',lbls,'score',sc->>'score');
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_comparison_publication_stamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.publication_state = 'PUBLISHED' and NEW.published_at is null then
    NEW.published_at := now();
  end if;
  -- Leaving PUBLISHED does not erase when it was published; that is a fact about the past.
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_holds_close_at_decision(p_inquiry uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_n int := 0; v_seen bigint[] := '{}';
begin
  for r in select h.id, h.quote_id, h.supplier_id from public.quote_spec_hold h join public.quotes q on q.id = h.quote_id
            where q.inquiry_id = p_inquiry and h.state in ('open', 'awaiting_approval') order by h.id
  loop
    update public.quote_spec_hold set state = 'unresolved_at_decision', decided_at = now(), updated_at = now() where id = r.id;
    v_n := v_n + 1;
    if r.supplier_id is not null and not (r.supplier_id = any (v_seen)) then
      v_seen := v_seen || r.supplier_id;
      perform public.fn_supplier_collaboration_incident(r.supplier_id, p_inquiry, r.quote_id, r.id);
    end if;
  end loop;
  return v_n;
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_quality_compose(p_kind text, p_lang text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_ar boolean := p_kind = 'customer' and coalesce(p_lang, '') like 'ar%';
  v_lang text := case when p_kind = 'customer' and coalesce(p_lang, '') like 'ar%' then 'ar' else 'en' end;
  v_name text := nullif(btrim(coalesce(p->>'name', '')), '');
  v_site text; v_link text; v_trade text; v_trade_ar text; v_em text; v_em_ar text; v_where text; v_where_ar text;
  v_ref text := coalesce('QD-' || nullif(p->>'job_no', ''), 'your request');
  v_hours int := coalesce((p->>'hours')::numeric, 24)::int;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select t.label, coalesce(t.label_ar, t.label) into v_trade, v_trade_ar
    from public.taxonomy_trade t
   where t.code = (public.fn_taxonomy_trades_for(array[coalesce(p->>'category', '')]))[1];
  v_trade := coalesce(v_trade, nullif(p->>'category', ''), 'your trade');
  v_trade_ar := coalesce(v_trade_ar, nullif(p->>'category', ''), 'تخصصكم');
  v_em := nullif(btrim(coalesce(p->>'emirate', '')), '');
  v_em_ar := case lower(coalesce(v_em, '')) when 'dubai' then 'دبي' when 'abu dhabi' then 'أبوظبي' when 'sharjah' then 'الشارقة'
               when 'ajman' then 'عجمان' when 'umm al quwain' then 'أم القيوين' when 'ras al khaimah' then 'رأس الخيمة'
               when 'fujairah' then 'الفجيرة' else v_em end;
  v_where := v_trade || coalesce(' in ' || v_em, '');
  v_where_ar := v_trade_ar || coalesce(' في ' || v_em_ar, '');

  if p_kind = 'supplier' then
    -- an Arabic-script company name is not written into an English letter (#1070's guard)
    if v_name ~ '[؀-ۿ]' then v_name := null; end if;
    v_subj := 'Action needed: your quotation for ' || v_ref || ' is on hold — ' || v_where;
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Sir or Madam,') || E'\n\n'
      || 'Your quotation for request ' || v_ref || ' (' || v_where || ') has not been shown to the customer yet. '
      || 'Our quality check found the points below. Please correct them in your supplier portal:'
      || E'\n\n' || coalesce(p->>'fixes', '') || E'\n\n'
      || 'If the quotation is not corrected by ' || coalesce(p->>'due', 'the end of the hold') || ' (Dubai time), '
      || 'it will be shown to the customer as it stands, with these points noted beside it.'
      || E'\n\n' || v_link;
  elsif v_ar then
    v_subj := 'عرض سعر جديد لطلبكم — ' || v_where_ar;
    v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
      || 'نفيدكم بأن أحد الموردين قدّم عرض سعر لطلبكم في مجال ' || v_where_ar || '. '
      || case when coalesce((p->>'waited')::boolean, false)
           then 'وقد وجد فحص الجودة لدينا ملاحظات لم يصحّحها المورّد خلال ' || v_hours || ' ساعة، وهي معروضة بجانب هذا العرض في المقارنة. '
           else '' end
      || 'ويمكنكم الاطلاع عليه ومقارنته بالعروض الأخرى عبر بوابتكم:'
      || E'\n\n' || v_link
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_subj := 'A new quotation for your request — ' || v_where;
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
      || 'A supplier has submitted a quotation for your request for ' || v_where || '. '
      || case when coalesce((p->>'waited')::boolean, false)
           then 'Our quality check found points the supplier did not correct within ' || v_hours || ' hours; they are shown beside this quotation in your comparison. '
           else '' end
      || 'You can view it and compare it with the others in your portal:'
      || E'\n\n' || v_link;
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_quality_content_md5(p_quote quotes)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select md5(jsonb_build_array(p_quote.quote_amount, p_quote.price_ex_vat, p_quote.vat_treatment, p_quote.vat_amount,
               p_quote.validity, p_quote.lead_time, p_quote.warranty, p_quote.payment_terms, p_quote.scope, p_quote.conditions,
               p_quote.exclusions, p_quote.notes, p_quote.terms_spec, p_quote.option_no, p_quote.original_file_path)::text
             || coalesce((select jsonb_agg(to_jsonb(qi) - 'id' - 'created_at' - 'updated_at' order by qi.line_no, qi.description)::text
                            from public.quote_items qi where qi.quote_id = p_quote.id::text), '[]'))
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_quality_fixes_en(p_flags jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select string_agg(n || '. ' || line, E'\n' order by n)
    from (select row_number() over (order by o) as n,
                 case f->>'code'
                   when 'missing_spec' then
                     'State these specifications on the lines you quote'
                     || coalesce(' (' || nullif(regexp_replace(f->>'topic', '^[Ss]pec checklist:\s*', ''), '') || ')', '') || ': '
                     || (select string_agg(s->>'label', '; ' order by k) from jsonb_array_elements(f->'specs') with ordinality e(s, k))
                     || '. If one does not apply to what you quote, write "not applicable" and why.'
                   when 'price_above' then
                     'Line ' || (f->>'line_no') || ' "' || left(coalesce(f->>'description', ''), 80) || '": AED '
                     || to_char((f->>'price')::numeric, 'FM999,999,990.00') || ' per ' || (f->>'unit') || ' is '
                     || (f->>'pct_vs_median') || '% above the usual UAE price for this item (AED '
                     || to_char((f->>'p25')::numeric, 'FM999,999,990.00') || ' to ' || to_char((f->>'p75')::numeric, 'FM999,999,990.00')
                     || ' per ' || (f->>'unit') || ', from ' || (f->>'quotes') || ' quotations by ' || (f->>'suppliers')
                     || ' suppliers). Correct the price, or state on the line what justifies it (brand, grade, scope or delivery).'
                   when 'price_below' then
                     'Line ' || (f->>'line_no') || ' "' || left(coalesce(f->>'description', ''), 80) || '": AED '
                     || to_char((f->>'price')::numeric, 'FM999,999,990.00') || ' per ' || (f->>'unit') || ' is '
                     || abs((f->>'pct_vs_median')::numeric) || '% below the usual UAE price for this item (AED '
                     || to_char((f->>'p25')::numeric, 'FM999,999,990.00') || ' to ' || to_char((f->>'p75')::numeric, 'FM999,999,990.00')
                     || ' per ' || (f->>'unit') || ', from ' || (f->>'quotes') || ' quotations by ' || (f->>'suppliers')
                     || ' suppliers). Check the quantity, the specification and what is excluded, then correct the line or state what it covers.'
                   when 'no_validity' then 'State how long the quotation is valid (for example, 30 days).'
                   when 'no_delivery_time' then 'State the delivery or lead time (a date, or a number of days from the order).'
                   when 'no_vat_treatment' then 'State whether your price includes or excludes VAT, or that you are not registered for VAT.'
                 end as line
            from jsonb_array_elements(coalesce(p_flags, '[]'::jsonb)) with ordinality a(f, o)) x
   where line is not null
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_quality_flags(p_quote quotes)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cat text; v_demo boolean; v_reader boolean; v_spec jsonb; v_price jsonb; v_terms jsonb := '[]'::jsonb;
begin
  select i.category into v_cat from public.inquiries i where i.id = p_quote.inquiry_id;
  v_demo := public.fn_inquiry_is_demo(p_quote.inquiry_id);

  -- (1) the pack checklist, unless a line reader already read these lines
  select exists (select 1 from public.quote_items qi, jsonb_object_keys(coalesce(qi.spec, '{}'::jsonb)) k
                  where qi.quote_id = p_quote.id::text and k !~ '^spec_') into v_reader;
  if not v_reader then
    with lists as (
      select c.topic_id, c.topic, c.specs from public.trade_spec_checklist c
       where c.trade_code = v_cat or c.trade_code = any(coalesce(public.fn_taxonomy_trades_for(array[v_cat]), '{}'::text[]))
    ), specs as (
      select l.topic_id, l.topic, s.x->>'code' as code, s.x->>'label_en' as label, s.ord
        from lists l, jsonb_array_elements(l.specs) with ordinality s(x, ord)
    ), judged as (
      select sp.*, exists (select 1 from public.quote_items qi
                            where qi.quote_id = p_quote.id::text and nullif(btrim(qi.spec->>sp.code), '') is not null) as stated
        from specs sp
    ), per_list as (
      select j.topic_id, j.topic, count(*) filter (where j.stated) as n_stated, count(*) filter (where not j.stated) as n_missing,
             jsonb_agg(jsonb_build_object('code', j.code, 'label', j.label) order by j.ord) filter (where not j.stated) as missing
        from judged j group by j.topic_id, j.topic
    ), chosen as (
      select * from per_list order by (n_missing = 0) desc, n_stated desc, n_missing, topic_id limit 1
    )
    select case
             when not exists (select 1 from per_list) then null                        -- no checklist for this trade
             when (select n_missing from chosen) = 0 then null                         -- one list fully stated
             when (select n_stated from chosen) > 0 or (select count(*) from per_list) = 1
               then jsonb_build_object('code', 'missing_spec', 'topic', (select topic from chosen), 'specs', (select missing from chosen))
             else jsonb_build_object('code', 'missing_spec', 'topic', null, 'specs',
                    (select jsonb_agg(jsonb_build_object('code', u.code, 'label', u.label) order by u.first_topic, u.ord)
                       from (select distinct on (j.code) j.code, j.label, j.topic_id as first_topic, j.ord
                               from judged j order by j.code, j.topic_id, j.ord) u))
           end
      into v_spec;
  end if;

  -- (2) each priced line against the UAE range for the same item; no benchmark, no flag
  with b as (select * from public.fn_price_benchmarks(v_demo, p_quote.inquiry_id)),
  lines as (
    select qi.line_no, qi.description,
           public.fn_price_benchmark_key(qi.description, qi.specification) as item_key,
           public.fn_price_benchmark_unit(qi.unit) as unit,
           round(coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0)), 2) as price
      from public.quote_items qi where qi.quote_id = p_quote.id::text
  ), judged as (
    select l.*, b.median, b.p25, b.p75, b.quote_count, b.supplier_count,
           public.fn_price_benchmark_judge(l.price, b.median, b.p25, b.p75, b.quote_count, b.supplier_count, l.unit) as j
      from lines l join b on b.trade = lower(v_cat) and b.item_key = l.item_key and b.unit = l.unit
     where l.price > 0
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', case when j->>'status' = 'well_above' then 'price_above' else 'price_below' end,
           'line_no', line_no, 'description', description, 'unit', unit, 'price', price,
           'pct_vs_median', (j->>'pct_vs_median')::numeric, 'median', median, 'p25', p25, 'p75', p75,
           'quotes', quote_count, 'suppliers', supplier_count) order by line_no), '[]'::jsonb)
    into v_price
    from judged where j->>'status' in ('well_above', 'well_below');

  -- (3) the terms a customer cannot compare without
  if nullif(btrim(coalesce(p_quote.validity, '')), '') is null then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_validity')); end if;
  if nullif(btrim(coalesce(p_quote.lead_time, '')), '') is null
     and nullif(btrim(coalesce(p_quote.terms_spec #>> '{delivery,value}', '')), '') is null then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_delivery_time')); end if;
  if coalesce(p_quote.vat_treatment, 'not_stated') = 'not_stated' then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_vat_treatment')); end if;

  return (case when v_spec is null then '[]'::jsonb else jsonb_build_array(v_spec) end) || coalesce(v_price, '[]'::jsonb) || v_terms;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_quality_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_flags jsonb; h public.quote_quality_hold; v_live boolean; v_open boolean;
  v_hours numeric := public.fn_seat_clock_policy('quote_quality_hold_hours', 24);
begin
  -- a quote that is not (or not yet) in front of the customer is not checked here
  if coalesce(new.status, 'submitted') in ('draft', 'withdrawn', 'rejected', 'expired', 'cancelled', 'held') then return new; end if;
  -- going out now: a new row, or one leaving a state no customer surface shows
  v_live := tg_op = 'INSERT' or coalesce(old.status, 'draft') in ('draft', 'withdrawn', 'rejected', 'expired', 'cancelled', 'held');
  v_flags := public.fn_quote_quality_flags(new);
  select * into h from public.quote_quality_hold where quote_id = new.id;
  v_open := found and h.released_at is null and h.superseded_at is null;

  if not v_live or h.released_at is not null then
    -- already out, or already waited its hours once: never pulled back; the flags beside it are kept current
    if found and h.flags is distinct from v_flags then
      update public.quote_quality_hold
         set flags = v_flags, fixes_en = public.fn_quote_quality_fixes_en(v_flags),
             corrected_at = case when jsonb_array_length(v_flags) = 0 then coalesce(corrected_at, now()) else null end,
             updated_at = now()
       where quote_id = new.id;
    end if;
    return new;
  end if;

  if jsonb_array_length(v_flags) = 0 then
    if v_open then
      update public.quote_quality_hold
         set flags = v_flags, released_at = now(), release_reason = 'corrected', corrected_at = now(), updated_at = now()
       where quote_id = new.id;
    end if;
    return new;
  end if;

  -- flagged: it stays a draft, which every customer surface already hides, and the hold opens. An open hold keeps its
  -- clock (a resubmission never resets it) and takes the newly accepted version; a superseded one starts over.
  new.status := 'draft';
  insert into public.quote_quality_hold (quote_id, inquiry_id, supplier_id, fixture, flags, fixes_en, accepted_md5, held_at, release_due)
  values (new.id, new.inquiry_id, new.supplier_id, public.fn_inquiry_is_demo(new.inquiry_id), v_flags,
          public.fn_quote_quality_fixes_en(v_flags), public.fn_quote_quality_content_md5(new),
          now(), now() + make_interval(secs => (v_hours * 3600)::double precision))
  on conflict (quote_id) do update
    set flags = excluded.flags, fixes_en = excluded.fixes_en, accepted_md5 = excluded.accepted_md5, updated_at = now(),
        held_at = case when quote_quality_hold.superseded_at is null then quote_quality_hold.held_at else excluded.held_at end,
        release_due = case when quote_quality_hold.superseded_at is null then quote_quality_hold.release_due else excluded.release_due end,
        fixes_sent_md5 = case when quote_quality_hold.superseded_at is null then quote_quality_hold.fixes_sent_md5 end,
        superseded_at = null;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_reviews_follow_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.quote_reviews
     set owner_email = nullif(lower(btrim(coalesce(new.claimed_by, ''))), ''), updated_at = now()
   where supplier_id = new.id
     and owner_email is distinct from nullif(lower(btrim(coalesce(new.claimed_by, ''))), '');
  return null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_spec_group(p_category text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select cs.quote_spec_group from public.category_specs cs where cs.category = p_category;
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_spec_mismatches(p_quote_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'quote_id', p_quote_id,
    'pending', count(*) filter (where g.status = 'queued'),
    'unread', coalesce(sum(jsonb_array_length(g.input->'cells')) filter (where g.status = 'failed'), 0),
    'mismatches', coalesce(jsonb_agg(v) filter (where g.status = 'done' and (v->>'mismatch')::boolean), '[]'::jsonb),
    'meets', count(v) filter (where g.status = 'done' and not (v->>'mismatch')::boolean))
  from public.glm_judgement g
  left join lateral jsonb_array_elements(coalesce(g.result->'cells', '[]'::jsonb)) v on true
  where g.kind = 'quote_spec_match' and g.input->>'quote_id' = p_quote_id;
$function$


CREATE OR REPLACE FUNCTION public.fn_quote_structured_score(p_quote text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int; priced int; branded int; laboured int; spec_n int; q record; pts int:=0; miss text[]:='{}'; v_held boolean;
begin
  select count(*), count(*) filter (where unit_price is not null and unit_price>0),
         count(*) filter (where coalesce(brand,'')<>'' and coalesce(model,'')<>''),
         count(*) filter (where labour is not null or install is not null),
         count(*) filter (where coalesce(specification,'')<>'')
    into n, priced, branded, laboured, spec_n from public.quote_items where quote_id=p_quote;
  select * into q from public.quotes where id=p_quote::uuid;
  if n=0 then miss:=array_append(miss,'line_items');
  else pts:=pts+15; if priced=n then pts:=pts+20; else miss:=array_append(miss,'unit_prices_on_all_items'); end if; end if;
  if n>0 and branded=n then pts:=pts+15; else miss:=array_append(miss,'brand_model_per_item'); end if;
  if n>0 and spec_n>=greatest(1,n/2) then pts:=pts+10; else miss:=array_append(miss,'specifications'); end if;
  if laboured>0 then pts:=pts+10; else miss:=array_append(miss,'labour_or_installation'); end if;
  if coalesce(q.warranty,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'warranty'); end if;
  if coalesce(q.lead_time,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'lead_time'); end if;
  if coalesce(q.payment_terms,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'payment_terms'); end if;
  if coalesce(q.exclusions,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'exclusions'); end if;
  if coalesce(q.validity,'')<>'' then pts:=pts+6; else miss:=array_append(miss,'validity'); end if;
  v_held := coalesce(q.quality->'category'->>'status', '') = 'needs_reasoning';
  if v_held then miss := array_append(miss, 'category_reading'); end if;
  return jsonb_build_object('score',pts,'submittable',pts>=70 and not v_held,'held_for_reading',v_held,
                            'items',n,'priced_items',priced,'missing',to_jsonb(miss),'scored_at',now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_quote_supplier_is_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.supplier_id is not distinct from OLD.supplier_id then return NEW; end if;
  raise exception 'quotes %: this quotation belongs to supplier % and the write names supplier %. A quotation does not change hands; a correction is a new revision by its own author. (pd_object_cross_owner_write)',
    OLD.id, OLD.supplier_id, coalesce(NEW.supplier_id::text,'(none)') using errcode = '23514';
end $function$


CREATE OR REPLACE FUNCTION public.fn_rate_limit(p_bucket text, p_limit integer, p_window_seconds integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r ai_rate_limit%rowtype;
begin
  insert into ai_rate_limit (bucket, window_start, count) values (p_bucket, now(), 0)
    on conflict (bucket) do nothing;
  select * into r from ai_rate_limit where bucket = p_bucket for update;
  if r.window_start < now() - make_interval(secs => p_window_seconds) then
    update ai_rate_limit set window_start = now(), count = 1 where bucket = p_bucket;
    return jsonb_build_object('allowed', true, 'count', 1, 'limit', p_limit);
  end if;
  if r.count >= p_limit then
    return jsonb_build_object('allowed', false, 'count', r.count, 'limit', p_limit,
      'retry_after_seconds', greatest(1, p_window_seconds - extract(epoch from (now() - r.window_start))::int));
  end if;
  update ai_rate_limit set count = count + 1 where bucket = p_bucket;
  return jsonb_build_object('allowed', true, 'count', r.count + 1, 'limit', p_limit);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_accountant__bank_line(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_line bigint; v_kind text := p_result->'decision'->>'choice';
begin
  select (subject->>'line_id')::bigint into v_line from public.reasoning_held_question where id = p_id;
  if v_line is null or v_kind is null or v_kind not in ('bank_charge', 'owner_transfer', 'bank_interest', 'stripe_payout', 'other') then
    return null;          -- nothing to apply: the row stays 'reasoned', not 'applied'
  end if;
  return public.fn_accountant_bank_line_reasoned(v_line, v_kind, 'reasoning:held#' || p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_accountant__circumvention(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; f public.fraud_flags; v_rev jsonb;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('circumvention', 'benign', 'insufficient_evidence') then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into f from public.fraud_flags
   where kind = h.subject->>'kind' and subject_type = h.subject->>'subject_type' and subject_id = h.subject->>'subject_id' for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'the flag no longer exists'); end if;
  if f.status <> 'open' then return jsonb_build_object('applied', true, 'changed', false, 'reason', 'a person already closed the flag'); end if;
  update public.fraud_flags
     set detail = detail || jsonb_build_object('accountant_verdict', v_choice, 'verdict_model', p_result->>'model',
                                               'verdict_reasoning', left(p_result->>'answer', 4000), 'held_question_id', p_id),
         status = case v_choice when 'benign' then 'dismissed' when 'circumvention' then 'escalated' else 'open' end,
         updated_at = now()
   where kind = f.kind and subject_type = f.subject_type and subject_id = f.subject_id;
  if v_choice = 'circumvention' then
    v_rev := public.fn_seat_duty_cross_review('fee_circumvention', 'accountant', 'ceo',
      case when h.question like 'ZZ DEMO%' then 'ZZ DEMO ' else '' end
        || 'Review a reasoned verdict on a measured signal about a revealed job and the platform''s fee.',
      jsonb_build_object('signal', f.kind, 'subject_type', f.subject_type, 'subject_id', f.subject_id, 'facts', f.detail - 'raised_by'),
      jsonb_build_object('verdict', v_choice), p_result, 'fraud_flags', f.kind || ':' || f.subject_type || ':' || f.subject_id);
    update public.fraud_flags set detail = detail || jsonb_build_object('review', v_rev)
     where kind = f.kind and subject_type = f.subject_type and subject_id = f.subject_id;
  end if;
  return jsonb_build_object('applied', true, 'verdict', v_choice, 'review', v_rev);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_accountant__knowledge_exam(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_accountant__knowledge_refresh(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_accountant__root_cause(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_root_cause_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_category__key_for_slug(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_choice text := p_result->'decision'->>'choice';
begin
  if v_choice = 'none' or exists (select 1 from public.org_category_identity i where i.category_key = v_choice) then
    return jsonb_build_object('key', v_choice);
  end if;
  -- released for a later ask (fn_category_key_ask on the next category_specs insert), the invalid answer kept for the record
  update public.reasoning_held_question set dedupe_key = dedupe_key || ':invalid:' || p_id where id = p_id;
  return jsonb_build_object('key', null, 'invalid_choice', v_choice);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__challenge(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text; h record; m record;
  v_weight int := 0; v_stance text; v_conf numeric; v_reason text; v_alts jsonb := '[]'::jsonb;
  v_evidence jsonb := '[]'::jsonb; v_rank int; v_principle text; v_supply int; v_rev numeric; v_id bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_choice := p_result->'decision'->>'choice';
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    return jsonb_build_object('applied', false, 'reason', 'the choice is not one of the options filed');
  end if;
  if v_choice like 'h%' then
    select * into h from public.challenge_heuristic where id = substr(v_choice, 2)::bigint;
    if found then
      v_weight := case h.rank_touched when 1 then 3 when 2 then 2 else 1 end;
      v_rank := h.rank_touched; v_principle := h.principle; v_reason := h.concern;
      if h.alternative is not null then v_alts := jsonb_build_array(h.alternative); end if;
    end if;
  elsif v_choice like 'm%' then
    select * into m from public.institutional_memory where id = substr(v_choice, 2)::bigint;
    if found then
      v_evidence := jsonb_build_array(jsonb_build_object('type', 'prior_outcome', 'verdict', m.outcome, 'lesson', left(m.detail, 240)));
      if m.outcome = 'worse' then v_weight := 3; v_reason := 'A prior attempt on record ended worse: ' || left(coalesce(m.detail, m.headline), 200) || '.'; end if;
    end if;
  end if;

  select count(*) into v_supply from public.leads where approval_status = 'approved';
  select coalesce(sum(coalesce(reveal_fee, app_fee, 0)), 0) into v_rev from public.transactions where revealed_at > now() - interval '30 days';
  v_evidence := v_evidence || jsonb_build_array(jsonb_build_object('type', 'current_state', 'onboarded_suppliers', v_supply, 'revenue_30d_aed', v_rev),
                              jsonb_build_object('type', 'reasoning', 'held_id', p_id, 'answer', left(coalesce(p_result->>'answer', ''), 600)));

  if v_weight >= 3 then v_stance := 'recommend_against'; v_conf := least(0.95, 0.60 + v_weight * 0.05);
  elsif v_weight >= 1 then v_stance := 'concern'; v_conf := 0.65;
  else v_stance := 'support'; v_conf := 0.6;
       v_reason := 'Reasoned: no conflict with the priority hierarchy and no contrary prior outcome on record.'; end if;
  v_reason := coalesce(v_reason, left(coalesce(p_result->>'answer', ''), 600));
  if v_alts = '[]'::jsonb and v_stance <> 'support' then
    v_alts := jsonb_build_array('Run it as a bounded test with a named metric and a captured baseline, so it can be graded and reversed.');
  end if;

  insert into public.challenge_record (proposal, proposed_by, challenged_by, stance, confidence, reasoning,
                                       violates_rank, violates_principle, evidence, alternatives)
  values (r.subject->>'proposal', r.subject->>'proposed_by', r.subject->>'challenger', v_stance, v_conf, v_reason,
          v_rank, v_principle, v_evidence, v_alts)
  returning id into v_id;
  return jsonb_build_object('challenge_record_id', v_id, 'stance', v_stance, 'choice', v_choice);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__escalation_meaning(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if r.subject is null or coalesce(r.subject->>'kind', '') = '' then return null; end if;
  return jsonb_build_object('choice', p_result->'decision'->>'choice',
    'decided', public.fn_decide(r.subject->>'kind', coalesce(r.subject->'ctx', '{}'::jsonb), coalesce(r.subject->>'actor', 'agent')));
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__experiment_approval(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; e public.ceo_experiment; v_choice text; v_f jsonb; v_review jsonb; v_owner text; v_days int;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  select * into e from public.ceo_experiment where id = (r.subject->>'experiment_id')::bigint for update;
  if not found or e.status <> 'proposed' or e.iteration <> (r.subject->>'iteration')::int then
    return jsonb_build_object('applied', true, 'already', 'the experiment moved on');
  end if;
  v_f := public.fn_ambition_fields(p_result);
  v_owner := case when exists (select 1 from public.org_role where role_id = v_f->>'owner_seat' and status = 'active' and role_id <> 'ceo')
                  then v_f->>'owner_seat' else e.proposed_by end;
  v_days := case when coalesce(v_f->>'days', '') ~ '^\d{1,3}$' and (v_f->>'days')::int between 7 and 365 then (v_f->>'days')::int else e.days end;

  -- THE CHALLENGE: the accountant reviews every approval call on a model of another family.
  v_review := public.fn_seat_duty_cross_review('ceo.experiment_approval', 'ceo', 'accountant',
    'Challenge the chief executive''s call on this experiment before it runs.',
    jsonb_build_object('experiment', to_jsonb(e) - 'approval'),
    jsonb_build_object('call', v_choice, 'fields', v_f, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000)),
    p_result, 'ceo_experiment', e.id::text || ':' || e.iteration);

  update public.ceo_experiment
     set approval = jsonb_build_object('decision', v_choice, 'fields', v_f, 'reasoning', left(coalesce(p_result->>'answer', ''), 6000),
                                       'model', p_result->>'model', 'review', v_review, 'decided_at', now()),
         status = case v_choice when 'approve' then case when e.starts_on <= v_today then 'running' else 'approved' end
                                when 'reject' then 'rejected' else 'proposed' end,
         owner_seat = case when v_choice = 'approve' then v_owner else owner_seat end,
         days = v_days,
         starts_on = case when v_choice = 'approve' then greatest(e.starts_on, v_today) else starts_on end,
         ends_on = case when v_choice = 'approve' then greatest(e.starts_on, v_today) + v_days end,
         closed_at = case when v_choice = 'reject' then now() end,
         updated_at = now()
   where id = e.id;
  return jsonb_build_object('applied', true, 'experiment', e.key, 'choice', v_choice, 'owner', v_owner, 'review', v_review);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__experiment_verdict(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; e public.ceo_experiment; v public.ceo_experiment_verdict; v_choice text; v_f jsonb;
  v_final boolean; v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  select * into e from public.ceo_experiment where id = (r.subject->>'experiment_id')::bigint for update;
  select * into v from public.ceo_experiment_verdict where experiment_id = e.id and week = (r.subject->>'week')::date for update;
  if v.decided_at is not null or e.status <> 'running' then return jsonb_build_object('applied', true, 'already', 'decided'); end if;
  v_f := public.fn_ambition_fields(p_result);
  v_final := v_choice = 'killed' or (v_choice = 'kept' and v_today >= e.ends_on);

  update public.ceo_experiment_verdict set decision = v_choice, fields = v_f, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', decided_at = now()
   where experiment_id = e.id and week = v.week;
  update public.ceo_experiment
     set status = case when v_choice = 'killed' then 'killed' when v_final then 'kept' else 'running' end,
         iteration = iteration + case when v_choice = 'iterated' then 1 else 0 end,
         approach = case when v_choice = 'iterated' and coalesce(v_f->>'next_step', '') <> '' then v_f->>'next_step' else approach end,
         closed_at = case when v_final then now() end, updated_at = now()
   where id = e.id;

  -- THE CASE MEMORY: every verdict is a case the owner seat (and the CEO) recall next time; final ones carry the outcome.
  insert into public.seat_case_memory (seat, case_kind, source_table, source_id, trade, situation, decision, reasoning, outcome,
                                       finalised, finalised_at, lessons, opened_at)
  values (coalesce(e.owner_seat, e.proposed_by), 'experiment', 'ceo_experiment_verdict', e.id || ':' || v.week,
          null,
          left(format('Experiment %s (iteration %s): %s Metric %s, baseline %s, target %s (%s). Reading %s over %s to %s.',
                      e.key, e.iteration, e.hypothesis, e.metric_key, coalesce(e.baseline::text, 'not measured'), e.target, e.direction,
                      coalesce(v.reading::text, 'not measurable'), v.reading_from::date, v.reading_to::date), 4000),
          v_choice, left(coalesce(p_result->>'answer', ''), 4000),
          case when v_final then format('%s: the hypothesis %s at a reading of %s against a target of %s.', v_choice,
                                        case when v_choice = 'kept' then 'held' else 'failed' end, coalesce(v.reading::text, 'unmeasured'), e.target) end,
          v_final, case when v_final then now() end,
          case when coalesce(v_f->>'lesson', '') <> '' then array[v_f->>'lesson'] else '{}'::text[] end, v.created_at)
  on conflict (source_table, source_id) do update set decision = excluded.decision, reasoning = excluded.reasoning,
    outcome = excluded.outcome, finalised = excluded.finalised, finalised_at = excluded.finalised_at, lessons = excluded.lessons,
    updated_at = now();
  return jsonb_build_object('applied', true, 'experiment', e.key, 'choice', v_choice, 'final', v_final);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__kb_jurisdiction(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_choice := p_result->'decision'->>'choice';
  if v_choice is null or v_choice not in ('quotesdone', 'uae', 'gcc', 'international', 'us', 'other_foreign')
     or (r.subject->>'citation_md5') is null then
    return jsonb_build_object('applied', false, 'reason', 'no valid jurisdiction in the answer');
  end if;
  insert into public.kb_citation_jurisdiction (citation_md5, citation, jurisdiction, held_id)
  values (r.subject->>'citation_md5', r.subject->>'citation', v_choice, p_id)
  on conflict (citation_md5) do update set jurisdiction = excluded.jurisdiction, held_id = excluded.held_id, reasoned_at = now();
  return jsonb_build_object('citation_md5', r.subject->>'citation_md5', 'jurisdiction', v_choice);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__knowledge_exam(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__knowledge_refresh(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__management_review(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_review_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__pricing_monitor(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_review_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__refund_off_platform(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_rid bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_rid := nullif(r.subject->>'refund_id', '')::bigint;
  if v_rid is null or not exists (select 1 from public.refunds f where f.id = v_rid and f.status = 'requested') then
    return jsonb_build_object('refund_id', v_rid, 'choice', p_result->'decision'->>'choice', 'review', 'not_open');
  end if;
  return jsonb_build_object('refund_id', v_rid, 'choice', p_result->'decision'->>'choice',
                            'review', public.fn_ceo_refund_review(v_rid, 'reasoned'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__root_cause(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_root_cause_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__sales_escalation(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_hid bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  v_hid := (r.subject->>'handoff_id')::bigint;
  perform set_config('qd.handoff_closer', 'ceo', true);
  perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('decided_by', 'ceo', 'escalation', r.subject->>'escalation',
    'choice', v_choice, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000), 'model', p_result->>'model', 'held_question', p_id));
  perform set_config('qd.handoff_closer', '', true);
  return jsonb_build_object('applied', true, 'handoff_id', v_hid, 'choice', v_choice);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__target_forecast(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_review_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__task_collaboration_rule(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; c public.collaboration_rule; v_text text; v_dept text; v_ch jsonb; v_n int := 0;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  select * into c from public.collaboration_rule where id::text = r.subject->>'rule_id';
  if c.id is null or coalesce(p_result->'decision'->>'choice', '') <> 'applies' then
    update public.org_tasks set status = 'assigned', updated_at = now(),
           result = coalesce(result, '{}'::jsonb) || jsonb_build_object('unparked', jsonb_build_object('at', now(), 'by', 'reasoning', 'held_id', p_id))
     where id::text = r.subject->>'task_id' and status = 'blocked' and (result ? 'parked');
    return jsonb_build_object('rule_id', r.subject->>'rule_id', 'applies', false);
  end if;
  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage, decision, reason, confidence)
  select 'org_task', r.subject->>'task_id', r.subject->>'dept_key', r.subject->>'author',
         coalesce((c.must_review)[1], 'exec'), 'collaboration', case when c.blocking then 'required' else 'advisory' end,
         'collaboration_rule #' || c.id || ' applies ("' || c.situation || '", reasoned by the CEO seat): '
           || 'involve ' || coalesce(array_to_string(c.must_involve, ', '), '(none)')
           || '; review by ' || coalesce(array_to_string(c.must_review, ', '), '(none)')
           || '. Why this rule exists: ' || c.reason, 1.0
;
  -- Each department the rule permits to challenge challenges, as fn_task_review does; never the author, once.
  select coalesce(o.title,'') || ' ' || coalesce(o.detail,'') || ' ' || coalesce(o.action_class,'') into v_text
    from org_tasks o where o.id::text = r.subject->>'task_id';
  foreach v_dept in array coalesce(c.may_challenge, array[]::text[]) loop
    continue when v_dept is not distinct from r.subject->>'author'
      or exists (select 1 from review_chain rc where rc.subject_type = 'org_task' and rc.subject_id = r.subject->>'task_id'
                   and rc.stage = 'challenge' and rc.reviewer_agent = v_dept);
    v_ch := fn_challenge(coalesce(v_text, ''), r.subject->>'dept_key', v_dept);
    if (v_ch->>'stance') <> 'support' then
      insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage, decision, reason, violated_rule, confidence)
      values ('org_task', r.subject->>'task_id', r.subject->>'dept_key', r.subject->>'author', v_dept, 'challenge',
              case when c.blocking and (v_ch->>'stance') = 'recommend_against' then 'reject' else 'dissent' end,
              upper(v_ch->>'stance') || ' from ' || v_dept || ': ' || coalesce(v_ch->>'reasoning',''),
              v_ch->>'conflicts_with', (v_ch->>'confidence')::numeric);
      v_n := v_n + 1;
    end if;
  end loop;
  update public.org_tasks set status = 'assigned', updated_at = now(),
         result = coalesce(result, '{}'::jsonb) || jsonb_build_object('unparked', jsonb_build_object('at', now(), 'by', 'reasoning', 'held_id', p_id))
   where id::text = r.subject->>'task_id' and status = 'blocked' and (result ? 'parked');
  return jsonb_build_object('rule_id', c.id, 'applies', true, 'task_id', r.subject->>'task_id', 'challenges', v_n);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__task_responsibility(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if nullif(r.subject->>'task_id', '') is null then return null; end if;
  return public.fn_task_ownership_record((r.subject->>'task_id')::bigint, r.subject->>'dept_key', r.subject->>'author',
                                         nullif(p_result->'decision'->>'choice', 'none'));
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_ceo__what_if(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text; v jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_choice := p_result->'decision'->>'choice';
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    return jsonb_build_object('applied', false, 'reason', 'the choice is not one of the options filed');
  end if;
  v := public.fn_what_if(r.subject->>'question', coalesce(r.subject->'change', '{}'::jsonb), v_choice);
  return jsonb_build_object('simulation_id', v->'id', 'scenario', v_choice);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_customer_support__dispute_intake(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice';
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('dispute', 'not_dispute') then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  if v_choice = 'not_dispute' then return jsonb_build_object('applied', true, 'opened', false); end if;
  return public.fn_customer_support_dispute_open((h.subject->>'transaction_id')::uuid, h.subject->>'party',
                                                 h.subject->>'statement', p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_customer_support__knowledge_exam(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_customer_support__knowledge_refresh(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_customer_support__root_cause(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_root_cause_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_customer_support__stalled_request(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; r record; v_ar boolean; v_name text;
  v_en text; v_arb text;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if not exists (select 1 from jsonb_array_elements(h.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select i.id, i.created_at, c.id as cid, c.full_name, c.email, c.locale into r
    from public.inquiries i join public.customers c on c.id = i.customer_id where i.id::text = h.subject->>'inquiry_id';
  if not found then return jsonb_build_object('applied', false, 'reason', 'the request no longer exists'); end if;
  if exists (select 1 from public.quotes q where q.inquiry_id = r.id) then
    return jsonb_build_object('applied', true, 'sent', false, 'reason', 'a quote arrived while the question was held');
  end if;
  v_ar := r.locale = 'ar'; v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
  v_en := case v_choice
    when 'add_details' then 'Suppliers have looked at your request but need more to price it. Please add the scope of work, the quantities and, if you have one, a drawing or bill of quantities from your account: https://quotesdone.com/me'
    when 'widen_scope' then 'Few suppliers cover this request exactly as it stands. Widening it, for example to a neighbouring emirate, a related trade or a later delivery date, usually brings quotes in. You can change it from your account: https://quotesdone.com/me'
    else 'Your request is complete and is still with suppliers in this trade. We will write as soon as the first quote arrives; nothing is needed from you now.' end;
  v_arb := case v_choice
    when 'add_details' then 'اطّلع الموردون على طلبكم، ويحتاجون إلى تفاصيل أكثر لتسعيره. نرجو إضافة نطاق العمل والكميات، والمخطط أو جدول الكميات إن توفّر، من حسابكم: https://quotesdone.com/ar/me'
    when 'widen_scope' then 'عدد الموردين الذين يغطّون طلبكم بصيغته الحالية محدود، وتوسيعه عادةً يجلب العروض، كأن يشمل إمارة مجاورة أو تخصصًا قريبًا أو موعد تسليم لاحقًا. ويمكنكم تعديله من حسابكم: https://quotesdone.com/ar/me'
    else 'طلبكم مكتمل، وما زال لدى الموردين العاملين في هذا المجال. سنبلغكم فور وصول أول عرض سعر، ولا يلزمكم أي إجراء الآن.' end;
  return jsonb_build_object('applied', true, 'choice', v_choice, 'send',
    public.fn_customer_support_duty_send('activation.stalled', r.id::text, 'customer', r.email, case when v_ar then 'ar' else 'en' end,
      case when v_ar then 'مستجدات طلبكم على QuotesDone' else 'An update on your QuotesDone request' end,
      case when v_ar then 'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10) || v_arb
                          || chr(10) || chr(10) || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
           else 'Dear ' || v_name || ',' || chr(10) || chr(10) || v_en end,
      r.cid, null, r.id));
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_documents__boq_arabic(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_key text; v_choice text;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  v_key := nullif(btrim(r.subject ->> 'section_key'), '');
  v_choice := nullif(p_result #>> '{decision,choice}', '');
  if v_key is null or v_choice is null or v_choice !~ '^[a-z_]+$' then
    return jsonb_build_object('applied', false, 'reason', 'no section key or no reasoned choice');
  end if;
  insert into public.boq_section_reading (section_key, section, reading, reasoned_by, held_id)
  values (left(v_key, 200), left(coalesce(r.subject ->> 'section', v_key), 200), v_choice, 'replay', p_id)
  on conflict (section_key) do update set reading = excluded.reading, reasoned_by = 'replay', held_id = excluded.held_id, reasoned_at = now();
  return jsonb_build_object('applied', true, 'section_key', v_key, 'reading', v_choice);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_inbound_email__infer_sector(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_n integer := 0;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if not found or (r.subject->>'lead_id') is null then return null; end if;
  if v_choice is not null and exists (select 1 from public.category_specs cs where cs.category = v_choice) then
    update public.leads l set sector = v_choice
     where l.id = (r.subject->>'lead_id')::bigint and l.sector is null;
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('lead_id', (r.subject->>'lead_id')::bigint, 'sector', v_choice, 'set', v_n = 1);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_inquiry__same_request(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_n int := 0;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if coalesce(p_result->'decision'->>'choice', '') = 'same_request' then
    update public.inquiries
       set plausibility = coalesce(plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true,
             'duplicate_of', r.subject->>'earlier_id', 'duplicate_by', 'reasoning', 'held_id', p_id)
     where id::text = r.subject->>'inquiry_id';
    get diagnostics v_n = row_count;
  end if;
  return jsonb_build_object('inquiry_id', r.subject->>'inquiry_id', 'choice', p_result->'decision'->>'choice', 'flagged', v_n > 0);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_it_engineer__knowledge_exam(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_it_engineer__knowledge_grade(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice';
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns (even null), so an answer that is not one of
    -- the options RAISES: the resolve rolls back and the grade is reasoned again on a later replay.
    raise exception 'CHOICE_NOT_AN_OPTION: % is not a grade (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  update public.seat_knowledge_exam set verdict = v_choice, grade_reason = left(coalesce(p_result->>'answer', ''), 1000), graded_at = now()
   where id = (r.subject->>'exam_id')::bigint and graded_at is null;
  return jsonb_build_object('applied', true, 'exam_id', r.subject->>'exam_id', 'verdict', v_choice);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_it_engineer__knowledge_refresh(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_it_engineer__postmortem(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_inc bigint; v_ans text := btrim(coalesce(p_result->>'answer', ''));
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_inc := (r.subject->>'incident_id')::bigint;
  if v_ans = '' then raise exception 'EMPTY_ANSWER: postmortem question % came back empty', p_id; end if;
  update public.it_incident set cause = coalesce(nullif(btrim(cause), ''), left(v_ans, 2000)),
         recorded_by = coalesce(recorded_by, 'it_engineer.postmortem (' || coalesce(p_result->>'model', 'model') || ')'), updated_at = now()
   where id = v_inc;
  return jsonb_build_object('applied', found, 'incident_id', v_inc);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_it_engineer__root_cause(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_root_cause_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_lead_trade__classify(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_code text; v_conf numeric;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if nullif(r.subject->>'lead_id', '') is null or coalesce(v_choice, '') = '' then return null; end if;
  select t.code into v_code from public.taxonomy_trade t where t.code = v_choice;
  if v_code is null and v_choice <> 'none' then
    -- an option that does not exist is not stored. The row keeps its (invalid) result for the record, and its dedupe
    -- key is released so the next tick asks again, within the daily cap.
    update public.reasoning_held_question set dedupe_key = dedupe_key || ':invalid:' || p_id where id = p_id;
    return jsonb_build_object('lead_id', (r.subject->>'lead_id')::bigint, 'stored', false, 'invalid_choice', v_choice);
  end if;
  begin v_conf := least(1, greatest(0, (p_result->>'confidence')::numeric)); exception when others then v_conf := null; end;
  insert into public.lead_trade_class (lead_id, trade_code, confidence, evidence, shortlist, shortlist_agreed, held_id)
  values ((r.subject->>'lead_id')::bigint, v_code, v_conf,
          left(coalesce(nullif(btrim(p_result->>'answer'), ''), 'reasoned without a stated reason'), 2000),
          coalesce(r.subject->'shortlist', '[]'::jsonb),
          case when v_code is null or jsonb_array_length(coalesce(r.subject->'shortlist', '[]'::jsonb)) = 0 then null
               else r.subject->'shortlist' ? v_code end, p_id)
  on conflict (lead_id) do update set trade_code = excluded.trade_code, confidence = excluded.confidence, evidence = excluded.evidence,
        shortlist = excluded.shortlist, shortlist_agreed = excluded.shortlist_agreed, held_id = excluded.held_id, decided_at = now();
  return jsonb_build_object('lead_id', (r.subject->>'lead_id')::bigint, 'trade_code', v_code);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_learning__distil(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_subject jsonb; c public.seat_lesson_cluster; v_answer text; v_ver text; v_by text; v_status text; v_cand bigint; v_ak bigint;
begin
  select subject into v_subject from public.reasoning_held_question where id = p_id;
  v_subject := coalesce(v_subject, p_result->'subject');
  select * into c from public.seat_lesson_cluster where cluster_key = v_subject->>'cluster_key';
  if c.cluster_key is null then return jsonb_build_object('applied', false, 'reason', 'no such cluster'); end if;
  v_answer := btrim(coalesce(p_result->>'answer', ''));
  if v_answer = '' or p_result->>'status' <> 'answered' then return jsonb_build_object('applied', false, 'reason', 'no lesson'); end if;
  v_ver := coalesce(p_result->'verified'->>'status', 'not_run');
  v_by := p_result->'verified'->>'by';
  v_status := case when v_ver = 'agreed' and v_by is not null then 'approved' when v_ver = 'disagreed' then 'rejected' else 'pending_review' end;
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, status, reviewed_by, reviewed_at)
  values (c.seat, 'What do ' || cardinality(c.case_ids) || ' similar ' || c.seat || ' cases with known outcomes teach?', left(v_answer, 4000),
          (select jsonb_agg(jsonb_build_object('kind', 'case', 'case_id', x, 'cluster_key', c.cluster_key)) from unnest(c.case_ids) x),
          v_status, case when v_status <> 'pending_review' then 'cross_family:' || coalesce(v_by, 'unknown') end,
          case when v_status <> 'pending_review' then now() end)
  on conflict (finding_sha) do nothing
  returning id into v_cand;
  -- The same lesson text from another group is the same lesson: link this group to it, never to nothing.
  if v_cand is null then
    select id into v_cand from public.reasoning_knowledge_candidate where finding_sha = md5(lower(btrim(left(v_answer, 4000))));
  end if;
  update public.seat_lesson_cluster set candidate_id = v_cand, verdict = v_ver where cluster_key = c.cluster_key;
  if v_status = 'approved' and v_cand is not null
     and not exists (select 1 from public.agent_knowledge a where a.source_ref = 'lesson:' || v_cand) then
    insert into public.agent_knowledge (agent_key, topic, content, layer, source_ref, owner_agent, version, validation_status, supporting_evidence)
    values (c.seat, 'Lesson from ' || cardinality(c.case_ids) || ' cases [lesson#' || v_cand || ']', left(v_answer, 4000), 'experience',
            'lesson:' || v_cand, c.seat, 1, 'author_verified',
            'Distilled from cases ' || array_to_string(c.case_ids, ', ') || '; verified by a model of another family (' || v_by || ')')
    returning id into v_ak;
    update public.seat_case_memory set lessons = lessons || left(v_answer, 600), updated_at = now()
     where id = any(c.case_ids) and not (left(v_answer, 600) = any(lessons));
  end if;
  return jsonb_build_object('applied', true, 'candidate_id', v_cand, 'status', v_status, 'agent_knowledge_id', v_ak);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_marketing__competitor_change(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; s public.competitor_scan; c public.competitor; v_choice text; v_f jsonb; v_task bigint;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  select * into s from public.competitor_scan where id = (r.subject->>'scan_id')::bigint for update;
  if s.decided_at is not null then return jsonb_build_object('applied', true, 'already', s.decision); end if;
  select * into c from public.competitor where id = s.competitor_id;
  v_f := public.fn_ambition_fields(p_result);
  if v_choice = 'changed' then
    v_task := public.fn_ceo_task_open('Competitor change: ' || c.name || ' (' || s.page_kind || ' page)',
      format(E'Marketing read %s on %s and judged that it changed in a way that matters to us.\n\nWhat changed: %s\nPricing: %s\nPositioning: %s\nFeatures: %s\n\nMarketing''s reasoning: %s\n\nDecide the company''s response: pricing is proposed to the founder only through the weekly pricing monitor.',
             s.url, s.requested_at::date, coalesce(v_f->>'what_changed', '?'), coalesce(v_f->>'pricing', '?'), coalesce(v_f->>'positioning', '?'),
             coalesce(v_f->>'features', '?'), left(coalesce(p_result->>'answer', ''), 2000)));
  end if;
  update public.competitor_scan set status = 'reasoned', decision = v_choice, fields = v_f, reasoning = left(coalesce(p_result->>'answer', ''), 6000),
         model = p_result->>'model', task_id = v_task, decided_at = now()
   where id = s.id;
  if v_choice in ('profiled', 'changed', 'no_material_change') then
    update public.competitor set verified_at = (now() at time zone 'Asia/Dubai')::date,
           watch = coalesce(watch, '{}'::jsonb) || jsonb_build_object(s.page_kind, jsonb_build_object('read_at', now(), 'decision', v_choice) || v_f)
     where id = c.id;
  end if;
  return jsonb_build_object('applied', true, 'competitor', c.name, 'choice', v_choice, 'ceo_task', v_task);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_marketing__knowledge_exam(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_marketing__knowledge_refresh(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_marketing__root_cause(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_root_cause_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sales_engineer__dispute_fault(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; d public.post_reveal_dispute; v_rev jsonb;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault') then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns, so a non-answer RAISES and is reasoned again.
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into d from public.post_reveal_dispute where id = (h.subject->>'dispute_id')::bigint and stage = 'review' for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'the dispute is not awaiting a finding'); end if;
  update public.post_reveal_dispute
     set stage = 'ceo_decision', finding = v_choice, finding_reasoning = left(p_result->>'answer', 8000),
         finding_model = p_result->>'model', decision_due = public.fn_add_working_days(now(), 3)
   where id = d.id;
  -- the question and evidence are abstract and factual; the finding travels only in the proposal
  v_rev := public.fn_seat_duty_cross_review('post_reveal_dispute', 'sales_engineer', 'ceo',
    case when h.question like 'ZZ DEMO%' then 'ZZ DEMO ' else '' end
      || 'Review a finding on a post-reveal dispute between a customer and a supplier.',
    jsonb_build_object('dispute_id', d.id, 'raised_by', d.raised_by, 'customer', d.customer_evidence, 'supplier', d.supplier_evidence),
    jsonb_build_object('finding', v_choice), p_result, 'post_reveal_dispute', d.id::text);
  update public.post_reveal_dispute set review = v_rev where id = d.id;
  return jsonb_build_object('applied', true, 'dispute_id', d.id, 'finding', v_choice, 'review', v_rev);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sales_engineer__document_arabic(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_ans jsonb; v_pairs jsonb := '{}'::jsonb; i integer; v_src text; v_ar text;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  begin
    v_ans := regexp_replace(btrim(coalesce(p_result->>'answer', '')), '^```(json)?\s*|\s*```$', '', 'g')::jsonb;
  exception when others then
    return jsonb_build_object('applied', false, 'reason', 'the answer is not one JSON object');
  end;
  if jsonb_typeof(v_ans) is distinct from 'object' or jsonb_typeof(r.subject->'sources') is distinct from 'array' then
    return jsonb_build_object('applied', false, 'reason', 'no sources or no object');
  end if;
  for i in 0 .. jsonb_array_length(r.subject->'sources') - 1 loop
    v_src := r.subject->'sources'->>i;
    v_ar := v_ans->>((i + 1)::text);
    if v_src is not null and v_ar is not null then v_pairs := v_pairs || jsonb_build_object(v_src, v_ar); end if;
  end loop;
  return jsonb_build_object('stored', public.fn_arabic_translation_store(v_pairs, p_id));
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sales_engineer__knowledge_exam(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sales_engineer__knowledge_refresh(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sales_engineer__root_cause(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ select public.fn_ceo_root_cause_applies(p_id, p_result) $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sales_engineer__supply_gap(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; g public.supply_gap; v_review jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('recruit', 'defer') then
    -- Not an answer to the question asked. fn_reason_held_resolve marks a row applied whenever its apply returns, even
    -- null, so this RAISES: the resolve rolls back, the row stays held and is reasoned again on a later replay.
    raise exception 'CHOICE_NOT_AN_OPTION: % is not recruit or defer (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into g from public.supply_gap where trade = r.subject->>'trade' and emirate = r.subject->>'emirate' for update;
  if not found or g.status <> 'deciding' then return jsonb_build_object('applied', false, 'reason', 'the gap moved on: ' || coalesce(g.status, 'gone')); end if;
  if v_choice = 'recruit' then
    v_review := public.fn_seat_duty_cross_review('sales_engineer.supply_gap', 'sales_engineer', 'marketing',
      'Review the sales engineer''s call on where marketing should recruit suppliers next.',
      jsonb_build_object('trade', g.trade, 'area', g.emirate, 'matchable_suppliers', g.matchable, 'needed', g.target,
                         'uninvited_leads', g.uninvited_pool, 'requests_90d', g.demand_90d),
      jsonb_build_object('call', 'recruit now', 'reasoning', left(coalesce(p_result->>'answer', ''), 2000)),
      p_result, 'supply_gap', g.trade || ':' || g.emirate);
  end if;
  update public.supply_gap set status = case when v_choice = 'recruit' then 'recruit' else 'deferred' end,
         decided_by = 'reasoning', decided_at = now(), review = v_review
   where trade = g.trade and emirate = g.emirate;
  return jsonb_build_object('applied', true, 'trade', g.trade, 'emirate', g.emirate, 'choice', v_choice, 'review', v_review);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sql__fn_org_task_consume_tick(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'task_id') is null or (r.subject->>'question_md5') is null then return jsonb_build_object('skipped', 'no subject'); end if;
  if not exists (select 1 from public.org_tasks o where o.id = (r.subject->>'task_id')::bigint
                   and md5(nullif(btrim(coalesce(substring(o.detail from 'QUESTION: ([^\n]+)'), '')), '')) = r.subject->>'question_md5') then
    return jsonb_build_object('skipped', 'stale');
  end if;
  return public.fn_org_task_question_reading_record((r.subject->>'task_id')::bigint, r.subject->>'question_md5',
    coalesce(p_result->'decision'->>'choice', 'neither'), true, p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sql__fn_supplier_portfolio_gaps(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice';
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'supplier_id') is null or (r.subject->>'word') is null then return jsonb_build_object('skipped', 'no subject'); end if;
  return public.fn_supplier_own_word_reading_record((r.subject->>'supplier_id')::bigint, r.subject->>'word',
    case when v_choice is null or v_choice = 'none' then null else v_choice end, true, p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sql__fn_supplier_twin(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; f jsonb := coalesce(p_result->'decision'->'fields', '{}'::jsonb);
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'lead_id') is null or (r.subject->>'summary_md5') is null then return jsonb_build_object('skipped', 'no subject'); end if;
  -- A reading of a summary that has since been edited is stale: it must not replace the reading of the current one.
  if not exists (select 1 from public.leads l where l.id = (r.subject->>'lead_id')::bigint
                   and md5(nullif(btrim(coalesce(l.capability_summary, '')), '')) = r.subject->>'summary_md5') then
    return jsonb_build_object('skipped', 'stale');
  end if;
  return public.fn_supplier_capability_reading_record((r.subject->>'lead_id')::bigint, r.subject->>'summary_md5',
    jsonb_build_object('manufacturing', public.fn_reason_field_stated(f->'manufacturing'),
                       'installation',  public.fn_reason_field_stated(f->'installation'),
                       'maintenance',   public.fn_reason_field_stated(f->'maintenance'),
                       'design',        public.fn_reason_field_stated(f->'design')), p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_apply_sql__trg_quote_quality(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_present text[];
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'quote_id') is null or (r.subject->>'content_md5') is null then return jsonb_build_object('skipped', 'no subject'); end if;
  if not exists (select 1 from public.quotes where id = (r.subject->>'quote_id')::uuid) then return jsonb_build_object('skipped', 'quote gone'); end if;
  -- A reading of text the supplier has since changed is stale: it must not replace the reading of the current text.
  if (select md5(coalesce(public.fn_quote_aspect_text(q), '')) from public.quotes q where q.id = (r.subject->>'quote_id')::uuid) <> r.subject->>'content_md5' then
    return jsonb_build_object('skipped', 'stale');
  end if;
  select coalesce(array_agg(k order by k), '{}'::text[]) into v_present
    from jsonb_each(coalesce(p_result->'decision'->'fields', '{}'::jsonb)) as e(k, v)
   where public.fn_reason_field_stated(v);
  return public.fn_quote_aspect_reading_record((r.subject->>'quote_id')::uuid, r.subject->>'content_md5', v_present, p_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_field_stated(p_field jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(btrim(p_field->>'value'), '') <> '' and coalesce(btrim(p_field->>'evidence'), '') <> ''
$function$


CREATE OR REPLACE FUNCTION public.fn_reason_held_delivered(p_id bigint, p_delivery jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.reasoning_held_question
     set result = coalesce(result, '{}'::jsonb) || jsonb_build_object('delivery', p_delivery),
         status = case when coalesce((p_delivery->>'delivered')::boolean, false) or p_delivery->>'via' = 'none' then 'applied' else status end,
         applied_at = case when coalesce((p_delivery->>'delivered')::boolean, false) or p_delivery->>'via' = 'none' then now() else applied_at end
   where id = p_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_held_due(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_gate jsonb; v jsonb;
begin
  update public.reasoning_held_question set status = 'failed' where status = 'held' and attempts >= 3;
  -- A fixture row is never replayed (a replay would pay for a test question): the estate's fixture convention in the
  -- question or request, or a caller's subject.fixture flag. Same criteria as the one-off expiry at the end of this file.
  update public.reasoning_held_question
     set status = 'expired', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('expired_by', 'fn_reason_held_due', 'why', 'fixture, never paid for')
   where status = 'held'
     and (question ~ 'ZZ DEMO|@example\.invalid' or request::text ~ 'ZZ DEMO|@example\.invalid' or subject->>'fixture' = 'true');
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with due as (
    select id from public.reasoning_held_question
     where status = 'held' and attempts < 3
       and (last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     order by last_attempt_at nulls first, created_at
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now()
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_held_escalate(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb;
begin
  with stale as (
    select id from public.reasoning_held_question
     where escalated_at is null
       and (status = 'failed' or (status = 'held' and created_at <= now() - interval '48 hours'))
     order by created_at
     limit greatest(1, least(coalesce(p_limit, 20), 100))
     for update skip locked
  ), marked as (
    update public.reasoning_held_question h set escalated_at = now()
      from stale where h.id = stale.id
    returning h.id, h.seat, h.surface, h.question, h.subject, h.status, h.created_at
  ), filed as (
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    select m.seat, 'held_question', 'pending', 'low',
           left('A question held ' || case when m.status = 'failed' then 'after 5 failed reasonings' else 'for 48 hours' end
                || ' on ' || m.surface || ' needs you', 200),
           jsonb_build_object('held_id', m.id, 'surface', m.surface, 'question', left(m.question, 1000), 'subject', m.subject,
                              'held_since', m.created_at, 'status', m.status,
                              'waiting_for', m.seat || ' to answer or act on it; it is also replayed the moment the model hold lifts'),
           'reasoning_held_question', m.id::text
      from marked m
    returning id
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'seat', m.seat, 'surface', m.surface, 'question', left(m.question, 500),
                                              'subject', m.subject, 'status', m.status)), '[]'::jsonb)
    into v from marked m where (select count(*) from filed) >= 0;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_held_notice_due(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb; v_dead int;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'seat', h.seat, 'surface', h.surface, 'question', left(h.question, 500),
                                               'subject', h.subject, 'attempts', h.notice_attempts) order by h.escalated_at), '[]'::jsonb)
    into v
    from (select * from public.reasoning_held_question
           where escalated_at is not null and notice_delivered_at is null
             and coalesce(subject->>'phone', '') <> '' and notice_attempts < 8
             and (notice_last_at is null or notice_last_at < now() - interval '30 minutes')
           order by escalated_at
           limit greatest(1, least(coalesce(p_limit, 20), 100))) h;

  select count(*) into v_dead from public.reasoning_held_question
   where escalated_at is not null and notice_delivered_at is null and coalesce(subject->>'phone', '') <> '' and notice_attempts >= 8;
  if v_dead > 0 then
    perform public.fn_it_engineer_finding_upsert('held_notice:undelivered',
      v_dead || ' WhatsApp customer(s) were never told their held question is with a person (8 failed attempts each)',
      'public.reasoning_held_question / resilience_ping reasoning_escalate', 'customer_facing', v_dead,
      jsonb_build_object('owner_seat', 'customer_support'), '{}'::text[], array['what the channel refused (notice_detail)'], 'customer_support');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'every owed holding notice was delivered'
     where issue_key = 'held_notice:undelivered' and closed_at is null;
  end if;
  return v;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_held_notice_record(p_id bigint, p_delivery jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ok boolean := coalesce((p_delivery->>'delivered')::boolean, false);
begin
  update public.reasoning_held_question
     set notice_attempts = notice_attempts + 1, notice_last_at = now(), notice_detail = p_delivery,
         notice_delivered_at = case when v_ok then now() else notice_delivered_at end
   where id = p_id and notice_delivered_at is null;
  return jsonb_build_object('id', p_id, 'delivered', v_ok, 'recorded', found);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_held_resolve(p_id bigint, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.reasoning_held_question; v_effect jsonb := null; v_fn text;
begin
  select * into r from public.reasoning_held_question where id = p_id for update;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  if coalesce(p_result->>'status', '') <> 'answered' then
    if coalesce(p_result->>'reason', '') = 'model_hold' then
      update public.reasoning_held_question
         set result = p_result, status = 'held', attempts = greatest(attempts - 1, 0)
       where id = p_id;
      return jsonb_build_object('id', p_id, 'status', 'still_held', 'attempt_returned', true);
    end if;
    update public.reasoning_held_question
       set result = p_result, status = case when attempts >= 3 then 'failed' else 'held' end
     where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'still_held');
  end if;
  update public.reasoning_held_question set result = p_result, status = 'reasoned', reasoned_at = now() where id = p_id;
  if r.surface = 'ceo.command_intent' and (r.subject->>'command_id') is not null then
    v_effect := public.fn_ceo_command_interpret((r.subject->>'command_id')::bigint, p_result->'decision'->>'choice',
                  left(coalesce(p_result->>'answer', ''), 1000));
  elsif r.surface = 'inquiry_intake.trade' and (r.subject->>'intake_id') is not null then
    update public.inquiry_intake i
       set category = p_result->'decision'->>'choice', status = 'needs_info', updated_at = now(),
           brief = coalesce(i.brief, '{}'::jsonb) || jsonb_build_object('category_by', 'reasoning', 'held_id', p_id)
     where i.id::text = r.subject->>'intake_id' and i.status = 'held'
       and exists (select 1 from public.category_specs cs where cs.category = p_result->'decision'->>'choice');
    v_effect := jsonb_build_object('intake_id', r.subject->>'intake_id', 'category', p_result->'decision'->>'choice', 'reopened', found);
  else
    v_fn := 'fn_reason_apply_' || replace(r.surface, '.', '__');
    if length(v_fn) <= 63 and to_regprocedure(format('public.%I(bigint,jsonb)', v_fn)) is not null then
      execute format('select public.%I($1, $2)', v_fn) into v_effect using p_id, p_result;
      v_effect := coalesce(v_effect, jsonb_build_object('applied_by', v_fn));
    end if;
  end if;
  if v_effect is not null then
    update public.reasoning_held_question set status = 'applied', applied_at = now() where id = p_id;
  end if;
  return jsonb_build_object('id', p_id, 'status', case when v_effect is null then 'reasoned' else 'applied' end, 'effect', v_effect);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_hold(p_seat text, p_surface text, p_question text, p_request jsonb, p_plan jsonb, p_subject jsonb, p_reason text, p_dedupe_key text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values (p_seat, p_surface, left(p_question, 8000), p_request, coalesce(p_plan, '{}'::jsonb), p_subject, p_reason, p_dedupe_key)
  on conflict (dedupe_key) do update set reason = excluded.reason, plan = excluded.plan,
    status = case when reasoning_held_question.status in ('failed', 'expired') then 'held' else reasoning_held_question.status end,
    attempts = case when reasoning_held_question.status in ('failed', 'expired') then 0 else reasoning_held_question.attempts end,
    escalated_at = case when reasoning_held_question.status in ('failed', 'expired') then null else reasoning_held_question.escalated_at end,
    -- the 48-hour escalation clock restarts with the reopen, or fn_reason_held_escalate would fire on the next tick
    created_at = case when reasoning_held_question.status in ('failed', 'expired') then now() else reasoning_held_question.created_at end,
    expires_at = null
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_propose_knowledge(p_seat text, p_question text, p_finding text, p_sources jsonb, p_embedding vector)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint;
begin
  if jsonb_typeof(p_sources) <> 'array' or jsonb_array_length(p_sources) = 0
     or exists (select 1 from jsonb_array_elements(p_sources) s where coalesce(s->>'url', '') !~ '^https://') then
    raise exception 'a research finding needs at least one https source' using errcode = '22023';
  end if;
  insert into public.reasoning_knowledge_candidate (seat, question, finding, sources, embedding_gte)
  values (p_seat, left(p_question, 2000), left(p_finding, 4000), p_sources, p_embedding)
  on conflict (finding_sha) do nothing
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_retrieve(p_seat text, p_embedding vector, p_k integer DEFAULT 6, p_trade text DEFAULT NULL::text, p_kind text DEFAULT NULL::text, p_area text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET "hnsw.iterative_scan" TO 'relaxed_order'
 SET "hnsw.ef_search" TO '100'
AS $function$
declare
  k   integer := greatest(1, least(coalesce(p_k, 6), 12));
  out jsonb := '[]'::jsonb;
  v_trade text[];  -- 'trade:<code>' of the resolved trade; NULL = no trade resolved
  v_kind  text;    -- the trade's resolved topic: a kind one of its entries carries; NULL = any kind
  v_area  text;    -- the seat's resolved area: an area one of its own rows carries; NULL = every area
begin
  -- 1. RESOLVE, exactly or not at all. The trade through the estate's exact resolver; the kind and the area only
  --    when a row of this trade / of this seat's own table is tagged with exactly that value. No word is read.
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.sales_knowledge x
       where x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
  v_area := nullif(lower(btrim(coalesce(p_area, ''))), '');
  if v_area is not null and not exists (
       select 1 from public.sales_knowledge x        where p_seat = 'sales_engineer'   and x.tags @> array['area:' || v_area]
       union all select 1 from public.accountant_knowledge x  where p_seat = 'accountant'       and x.tags @> array['area:' || v_area]
       union all select 1 from public.it_engineer_knowledge x where p_seat = 'it_engineer'      and x.tags @> array['area:' || v_area]
       union all select 1 from public.support_knowledge x     where p_seat = 'customer_support' and x.tags @> array['area:' || v_area]
       union all select 1 from public.ceo_knowledge x         where p_seat = 'ceo'              and x.tags @> array['area:' || v_area]
       union all select 1 from public.marketing_knowledge x   where p_seat = 'marketing'        and x.tags @> array['area:' || v_area]) then
    v_area := null;
  end if;
  -- 2. FILTER BEFORE RANKING (the TRADE and AREA predicates below). 3. Nothing resolved: exactly the ranking before.
  if p_embedding is null then return out; end if;

  with hits as (
    (select 'kb_chunks' src, c.id::text id, c.title, left(c.content, 1200) excerpt, c.citation,
            1 - (c.embedding_gte <=> p_embedding) sim, 'reviewed' trust
       from public.kb_chunks c where c.embedding_gte is not null
      order by c.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ops_knowledge', o.record_id, o.title, left(o.content, 1200), o.source_path,
            1 - (o.embedding_gte <=> p_embedding), 'reviewed'
       from public.ops_knowledge o
      where o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
        and o.scope_type in ('company', 'external_source', 'category')
      order by o.embedding_gte <=> p_embedding limit k)
    union all
    (select 'agent_knowledge', a.id::text, a.topic, left(a.content, 1200), a.source_ref,
            1 - (a.embedding_gte <=> p_embedding), 'reviewed'
       from public.agent_knowledge a
      where a.embedding_gte is not null and a.agent_key in (p_seat, '_global')
      order by a.embedding_gte <=> p_embedding limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id,
            1 - (f.embedding_gte <=> p_embedding), 'reviewed'
       from public.company_faq f where f.embedding_gte is not null and f.status = 'approved'
      order by f.embedding_gte <=> p_embedding limit k)
    union all
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.sales_knowledge s
      where s.embedding_gte is not null and s.runtime_index_eligible
        and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and s.pack_id like 'verified:trade:%'))
        and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind])))
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%'))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.accountant_knowledge s
      where p_seat = 'accountant' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%'))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.it_engineer_knowledge s
      where p_seat = 'it_engineer' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%'))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 1200), coalesce(s.source_path, s.pack_id),
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.support_knowledge s
      where p_seat = 'customer_support' and s.embedding_gte is not null and coalesce(s.runtime_index_eligible, true)
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%'))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'ceo_knowledge', s.record_id, s.title, left(s.body, 1200), coalesce(s.source_path, s.pack_fingerprint),
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.ceo_knowledge s
      where p_seat = 'ceo' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%'))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'marketing_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id,
            1 - (s.embedding_gte <=> p_embedding), 'reviewed'
       from public.marketing_knowledge s
      where p_seat = 'marketing' and s.embedding_gte is not null and s.runtime_index_eligible
        and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%'))
      order by s.embedding_gte <=> p_embedding limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url',
            1 - (r.embedding_gte <=> p_embedding), case when r.status = 'approved' then 'reviewed' else 'pending_review' end
       from public.reasoning_knowledge_candidate r
      where r.embedding_gte is not null and r.status <> 'rejected'
      order by r.embedding_gte <=> p_embedding limit k)
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(sim::numeric, 4), 'trust', trust) order by sim desc), '[]'::jsonb)
    into out
    from (select * from hits order by sim desc limit k * 2) t;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_retrieve_ml(p_seat text, p_embedding vector, p_embedding_gte vector DEFAULT NULL::vector, p_k integer DEFAULT 6, p_own integer DEFAULT 3, p_trade text DEFAULT NULL::text, p_kind text DEFAULT NULL::text, p_area text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
 SET "hnsw.iterative_scan" TO 'relaxed_order'
 SET "hnsw.ef_search" TO '100'
AS $function$
declare
  k    integer := greatest(1, least(coalesce(p_k, 6), 12));
  own  integer := greatest(0, least(coalesce(p_own, 3), 2 * k));
  n    constant integer := 20;
  g    vector(384) := p_embedding_gte;
  m    vector(384) := p_embedding;
  out  jsonb := '[]'::jsonb;
  v_trade text[];  -- 'trade:<code>' of the resolved trade; NULL = no trade resolved
  v_kind  text;    -- the trade's resolved topic: a kind one of its entries carries; NULL = any kind
  v_area  text;    -- the seat's resolved area: an area one of its own rows carries; NULL = every area
begin
  -- 1. RESOLVE, exactly or not at all. The trade through the estate's exact resolver; the kind and the area only
  --    when a row of this trade / of this seat's own table is tagged with exactly that value. No word is read.
  select array_agg('trade:' || c) into v_trade from unnest(public.fn_norm_trades(p_trade)) c;
  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  if v_trade is null or (v_kind is not null and not exists (select 1 from public.sales_knowledge x
       where x.tags && v_trade and x.tags @> array['kind:' || v_kind])) then v_kind := null; end if;
  v_area := nullif(lower(btrim(coalesce(p_area, ''))), '');
  if v_area is not null and not exists (
       select 1 from public.sales_knowledge x        where p_seat = 'sales_engineer'   and x.tags @> array['area:' || v_area]
       union all select 1 from public.accountant_knowledge x  where p_seat = 'accountant'       and x.tags @> array['area:' || v_area]
       union all select 1 from public.it_engineer_knowledge x where p_seat = 'it_engineer'      and x.tags @> array['area:' || v_area]
       union all select 1 from public.support_knowledge x     where p_seat = 'customer_support' and x.tags @> array['area:' || v_area]
       union all select 1 from public.ceo_knowledge x         where p_seat = 'ceo'              and x.tags @> array['area:' || v_area]
       union all select 1 from public.marketing_knowledge x   where p_seat = 'marketing'        and x.tags @> array['area:' || v_area]) then
    v_area := null;
  end if;
  -- 2. FILTER BEFORE RANKING (the TRADE and AREA predicates below). 3. Nothing resolved: exactly the ranking before.
  if m is null then return out; end if;
  with cand as (
    -- kb_chunks: both spaces through their HNSW indexes
    (select 'kb_chunks' src, v.row_id from public.knowledge_vector_ml v where v.src = 'kb_chunks' order by v.embedding <=> m limit n)
    union (select 'kb_chunks', c.id::text from public.kb_chunks c where g is not null and c.embedding_gte is not null order by c.embedding_gte <=> g limit n)
    union (select 'ops_knowledge', o.record_id from public.knowledge_vector_ml v join public.ops_knowledge o on v.src = 'ops_knowledge' and o.record_id = v.row_id
            where o.runtime_eligible and o.supersession_state = 'current' and o.scope_type in ('company', 'external_source', 'category')
            order by v.embedding <=> m limit n)
    union (select 'ops_knowledge', o.record_id from public.ops_knowledge o
            where g is not null and o.embedding_gte is not null and o.runtime_eligible and o.supersession_state = 'current'
              and o.scope_type in ('company', 'external_source', 'category') order by o.embedding_gte <=> g limit n)
    union (select 'agent_knowledge', a.id::text from public.knowledge_vector_ml v join public.agent_knowledge a on v.src = 'agent_knowledge' and a.id::text = v.row_id
            where a.agent_key in (p_seat, '_global') order by v.embedding <=> m limit n)
    union (select 'agent_knowledge', a.id::text from public.agent_knowledge a
            where g is not null and a.embedding_gte is not null and a.agent_key in (p_seat, '_global') order by a.embedding_gte <=> g limit n)
    union (select 'company_faq', f.id::text from public.knowledge_vector_ml v join public.company_faq f on v.src = 'company_faq' and f.id::text = v.row_id
            where f.status = 'approved' order by v.embedding <=> m limit n)
    union (select 'company_faq', f.id::text from public.company_faq f
            where g is not null and f.embedding_gte is not null and f.status = 'approved' order by f.embedding_gte <=> g limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text from public.knowledge_vector_ml v
             join public.reasoning_knowledge_candidate r on v.src = 'reasoning_knowledge_candidate' and r.id::text = v.row_id
            where r.status <> 'rejected' order by v.embedding <=> m limit n)
    union (select 'reasoning_knowledge_candidate', r.id::text from public.reasoning_knowledge_candidate r
            where g is not null and r.embedding_gte is not null and r.status <> 'rejected' order by r.embedding_gte <=> g limit n)
    -- sales_knowledge: the sales engineer reads all of it; customer_support reads the TRADE packs (what a trade
    -- needs), never the sales seat's own playbook
    union (select 'sales_knowledge', s.record_id from public.knowledge_vector_ml v join public.sales_knowledge s on v.src = 'sales_knowledge' and s.record_id = v.row_id
            where s.runtime_index_eligible and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and (s.pack_id like 'verified:trade:%' or exists (select 1 from unnest(s.tags) t where t like 'trade:%'))))
            and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind])))
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%'))
            order by v.embedding <=> m limit n)
    union (select 'sales_knowledge', s.record_id from public.sales_knowledge s
            where g is not null and s.embedding_gte is not null and s.runtime_index_eligible
              and (p_seat = 'sales_engineer' or (p_seat = 'customer_support' and (s.pack_id like 'verified:trade:%' or exists (select 1 from unnest(s.tags) t where t like 'trade:%'))))
            and (v_trade is null or not exists (select 1 from unnest(s.tags) t where t like 'trade:%')
             or (s.tags && v_trade and (v_kind is null or s.tags @> array['kind:' || v_kind])))
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%'))
            order by s.embedding_gte <=> g limit n)
    union (select 'accountant_knowledge', s.record_id from public.knowledge_vector_ml v join public.accountant_knowledge s on v.src = 'accountant_knowledge' and s.record_id = v.row_id
            where p_seat = 'accountant' and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by v.embedding <=> m limit n)
    union (select 'accountant_knowledge', s.record_id from public.accountant_knowledge s
            where p_seat = 'accountant' and g is not null and s.embedding_gte is not null and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by s.embedding_gte <=> g limit n)
    union (select 'it_engineer_knowledge', s.record_id from public.knowledge_vector_ml v join public.it_engineer_knowledge s on v.src = 'it_engineer_knowledge' and s.record_id = v.row_id
            where p_seat = 'it_engineer' and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by v.embedding <=> m limit n)
    union (select 'it_engineer_knowledge', s.record_id from public.it_engineer_knowledge s
            where p_seat = 'it_engineer' and g is not null and s.embedding_gte is not null and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by s.embedding_gte <=> g limit n)
    union (select 'marketing_knowledge', s.record_id from public.knowledge_vector_ml v join public.marketing_knowledge s on v.src = 'marketing_knowledge' and s.record_id = v.row_id
            where p_seat = 'marketing' and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by v.embedding <=> m limit n)
    union (select 'marketing_knowledge', s.record_id from public.marketing_knowledge s
            where p_seat = 'marketing' and g is not null and s.embedding_gte is not null and s.runtime_index_eligible
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by s.embedding_gte <=> g limit n)
    union (select 'ceo_knowledge', v.row_id from public.knowledge_vector_ml v join public.ceo_knowledge s on v.src = 'ceo_knowledge' and s.record_id = v.row_id
            where p_seat = 'ceo' and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by v.embedding <=> m limit n)
    union (select 'ceo_knowledge', s.record_id from public.ceo_knowledge s
            where p_seat = 'ceo' and g is not null and s.embedding_gte is not null
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by s.embedding_gte <=> g limit n)
    union (select 'support_knowledge', v.row_id from public.knowledge_vector_ml v join public.support_knowledge s on v.src = 'support_knowledge' and s.record_id = v.row_id
            where p_seat = 'customer_support' and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by v.embedding <=> m limit n)
    union (select 'support_knowledge', s.record_id from public.support_knowledge s
            where p_seat = 'customer_support' and g is not null and s.embedding_gte is not null
            and (v_area is null or s.tags @> array['area:' || v_area] or not exists (select 1 from unnest(s.tags) t where t like 'area:%')) order by s.embedding_gte <=> g limit n)
  ), sims as (
    -- both similarities for every candidate; a CASE evaluates only its own branch, so a text key is never cast
    select c.src, c.row_id,
           (select 1 - (v.embedding <=> m) from public.knowledge_vector_ml v where v.src = c.src and v.row_id = c.row_id) s_ml,
           case when g is null then null else case c.src
             when 'kb_chunks' then (select 1 - (x.embedding_gte <=> g) from public.kb_chunks x where x.id = c.row_id::bigint)
             when 'ops_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.ops_knowledge x where x.record_id = c.row_id)
             when 'agent_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.agent_knowledge x where x.id = c.row_id::bigint)
             when 'company_faq' then (select 1 - (x.embedding_gte <=> g) from public.company_faq x where x.id = c.row_id::bigint)
             when 'reasoning_knowledge_candidate' then (select 1 - (x.embedding_gte <=> g) from public.reasoning_knowledge_candidate x where x.id = c.row_id::bigint)
             when 'sales_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.sales_knowledge x where x.record_id = c.row_id)
             when 'accountant_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.accountant_knowledge x where x.record_id = c.row_id)
             when 'it_engineer_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.it_engineer_knowledge x where x.record_id = c.row_id)
             when 'marketing_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.marketing_knowledge x where x.record_id = c.row_id)
             when 'ceo_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.ceo_knowledge x where x.record_id = c.row_id)
             when 'support_knowledge' then (select 1 - (x.embedding_gte <=> g) from public.support_knowledge x where x.record_id = c.row_id)
           end end s_gte
      from cand c
  ), ranked as (
    select s.*,
           case when s_ml is not null then row_number() over (order by s_ml desc nulls last) end r_ml,
           case when s_gte is not null then row_number() over (order by s_gte desc nulls last) end r_gte
      from sims s
  ), gaps as (
    -- decisiveness: best minus 21st (or the last, when there are fewer candidates)
    select coalesce(max(s_ml) - coalesce(max(s_ml) filter (where r_ml = n + 1), min(s_ml)), 0) d_ml,
           coalesce(max(s_gte) - coalesce(max(s_gte) filter (where r_gte = n + 1), min(s_gte)), 0) d_gte
      from ranked
  ), scored as (
    select r.*,
           coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_ml / (gp.d_ml + gp.d_gte) else 1 end / (60 + r.r_ml), 0)
         + coalesce(case when gp.d_ml + gp.d_gte > 0 then gp.d_gte / (gp.d_ml + gp.d_gte) else 0 end / (60 + r.r_gte), 0) score
      from ranked r cross join gaps gp
  ), hits as (
    -- a bigint key is cast only inside its own source's rows (scored is materialised; the filter runs first)
    (select 'kb_chunks' src, c.id::text id, c.title, left(c.content, 1200) excerpt, c.citation, sc.s_ml, sc.score, 'reviewed' trust, false mine
       from (select *, row_id::bigint key from scored where src = 'kb_chunks') sc join public.kb_chunks c on c.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'ops_knowledge', o.record_id, o.title, left(o.content, 1200), o.source_path, sc.s_ml, sc.score, 'reviewed', false
       from scored sc join public.ops_knowledge o on sc.src = 'ops_knowledge' and o.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'agent_knowledge', a.id::text, a.topic, left(a.content, 1200), a.source_ref, sc.s_ml, sc.score, 'reviewed', a.agent_key = p_seat
       from (select *, row_id::bigint key from scored where src = 'agent_knowledge') sc join public.agent_knowledge a on a.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'company_faq', f.id::text, f.question, left(f.answer, 1200), 'FAQ ' || f.id, sc.s_ml, sc.score, 'reviewed', false
       from (select *, row_id::bigint key from scored where src = 'company_faq') sc join public.company_faq f on f.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'research', r.id::text, left(r.question, 200), r.finding, r.sources->0->>'url', sc.s_ml, sc.score,
            case when r.status = 'approved' then 'reviewed' else 'pending_review' end, false
       from (select *, row_id::bigint key from scored where src = 'reasoning_knowledge_candidate') sc join public.reasoning_knowledge_candidate r on r.id = sc.key
      order by sc.score desc limit k)
    union all
    (select 'sales_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.sales_knowledge s on sc.src = 'sales_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'accountant_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.accountant_knowledge s on sc.src = 'accountant_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'it_engineer_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.it_engineer_knowledge s on sc.src = 'it_engineer_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'marketing_knowledge', s.record_id, s.title, left(s.content, 1200), s.pack_id, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.marketing_knowledge s on sc.src = 'marketing_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'ceo_knowledge', s.record_id, s.title, left(s.body, 1200), s.source_path, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.ceo_knowledge s on sc.src = 'ceo_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
    union all
    (select 'support_knowledge', s.record_id, s.title, left(s.body, 1200), s.source_path, sc.s_ml, sc.score, 'reviewed', true
       from scored sc join public.support_knowledge s on sc.src = 'support_knowledge' and s.record_id = sc.row_id
      order by sc.score desc limit k)
  ), own_rows as (
    select * from hits where mine order by score desc limit own
  ), chosen as (
    select o.*, true reserved from own_rows o
    union all
    select *, false from (select h.* from hits h where not exists (select 1 from own_rows o where o.src = h.src and o.id = h.id)
                    order by h.score desc limit greatest(k * 2 - (select count(*) from own_rows), 0)) rest
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', src, 'id', id, 'title', title, 'excerpt', excerpt,
           'citation', citation, 'similarity', round(coalesce(s_ml, 0)::numeric, 4), 'score', round(score::numeric, 6),
           'trust', trust, 'own', mine) order by reserved desc, score desc), '[]'::jsonb)
    into out
    from chosen;
  return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reason_route_answer(p_dedupe_key text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select h.result->'decision'->>'choice' from public.reasoning_held_question h
   where h.dedupe_key = p_dedupe_key and h.status in ('reasoned', 'applied')
     and coalesce(h.result->'decision'->>'choice', '') <> '';
$function$


CREATE OR REPLACE FUNCTION public.fn_reason_route_ask(p_seat text, p_surface text, p_question text, p_options jsonb, p_subject jsonb, p_dedupe_key text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_q text := left(btrim(coalesce(p_question, '')), 8000);
begin
  -- Nothing to reason about (no text, or fewer than two options): no question, and the caller says so.
  if v_q = '' or coalesce(btrim(p_dedupe_key), '') = '' or jsonb_typeof(p_options) is distinct from 'array'
     or jsonb_array_length(p_options) < 2 then
    return null;
  end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, expires_at)
  values (p_seat, p_surface, v_q,
          jsonb_build_object('seat', p_seat, 'surface', p_surface, 'question', v_q,
                             'context', jsonb_build_object('audience', 'internal'),
                             'decision', jsonb_build_object('name', p_surface, 'options', p_options),
                             'subject', p_subject, 'dedupeKey', p_dedupe_key),
          jsonb_build_object('pending', jsonb_build_array('decompose', 'resolve', 'retrieve', 'decide'), 'filed_by', 'sql'),
          p_subject, 'awaiting_reasoning', p_dedupe_key, null)
  on conflict (dedupe_key) do update set status = 'held', attempts = 0, last_attempt_at = null, expires_at = null
   where reasoning_held_question.status = 'expired'
      -- a failed question (five model failures) reopens at most once a day, so a broken model is not paid for on every tick
      or (reasoning_held_question.status = 'failed' and coalesce(reasoning_held_question.last_attempt_at, reasoning_held_question.created_at) < now() - interval '24 hours')
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.reasoning_held_question where dedupe_key = p_dedupe_key;
  end if;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_receipt_hand_to_bookkeeper(p_inbound_id bigint, p_review_ids bigint[], p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare m record; v_owner text; v_task bigint;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then return null; end if;

  -- one task per inbound email, however many times the email is redelivered
  select t.id into v_task from public.org_tasks t
   where t.detail like '[inbound_message:' || p_inbound_id || ']%'
     and t.status not in ('done', 'cancelled')
   order by t.id limit 1;

  if v_task is null then
    -- 9 SEP 2026: 'bookkeeper' has never been a row in org_agents, so every held receipt became an
    -- UNOWNED task. The accountant seat now exists and this is its named work; the old key is kept
    -- first so nothing changes if that seat is ever created.
    select o.agent_key into v_owner from public.org_agents o
     where o.agent_key in ('bookkeeper','accountant') and o.active and coalesce(o.available, true)
     order by case o.agent_key when 'bookkeeper' then 0 else 1 end limit 1;

    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, decided_by,
                                  action_class, assigned_agent, priority, result)
    values ('finance',
            left('Book a forwarded receipt the parser could not read: ' || coalesce(m.subject, '(no subject)'), 200),
            '[inbound_message:' || p_inbound_id || '] ' || coalesce(p_reason, 'no amount could be read from the text')
              || E'\n\nFrom ' || coalesce(m.from_email, '?') || ' to ' || coalesce(m.to_email, '?') || ' at ' || m.created_at
              || '. Stored documents: doc_reviews ' || coalesce(array_to_string(p_review_ids, ', '), '(none)')
              || '. Read the document, book the expense in expense_entries (source ''receipt''), close the doc_reviews rows '
              || 'as auto_applied and the inbound row as replied. Only a Stripe refund reaches the founder.',
            'assigned', 'advisory', false, 'fn_receipt_hand_to_bookkeeper',
            'analysis', v_owner, 1,
            jsonb_build_object('source', jsonb_build_object('inbound_message_id', p_inbound_id,
                               'doc_review_ids', to_jsonb(coalesce(p_review_ids, '{}'::bigint[])),
                               'reason', p_reason, 'handed_at', now())))
    returning id into v_task;
  end if;

  update public.inbound_messages set owner_role = coalesce(v_owner, 'accountant') where id = p_inbound_id and owner_role is null;
  update public.doc_reviews set owner_role = coalesce(v_owner, 'accountant')
   where id = any(coalesce(p_review_ids, '{}'::bigint[])) and owner_role is null;
  return v_task;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_recommend_deterministic(p_step_run_id bigint DEFAULT NULL::bigint, p_record boolean DEFAULT true)
 RETURNS TABLE(determination text, employee text, department text, workflow_key text, step_no integer, step text, outcome text, deliverable text, inputs jsonb, recommendations jsonb, used_llm boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sid bigint := p_step_run_id;
  v_actor text; v_employee text; v_dept text; v_wf text; v_wfname text; v_step_no int; v_step text;
  v_run uuid; v_ctx jsonb := '{}'::jsonb; v_located text := 'p_step_run_id';
  v_framing text;
  v_kpis jsonb; v_kpi_rows int := 0; v_kpi_measured int := 0; v_kpi_missed int := 0; v_kpi_met int := 0;
  v_sc jsonb; v_sc_rows int := 0; v_sc_off int := 0;
  v_meta jsonb; v_meta_rows int := 0;
  v_recs jsonb; v_n int := 0;
  v_text text; v_one text; rec record;
  v_old_depts text[];
begin
  used_llm := false;
  -- 1. WHO IS ASKING. The step, or the queued action_execution row this invocation is running.
  if v_sid is null then
    select x.workflow_step_run_id, x.request->>'actor'
      into v_sid, v_actor
      from public.action_execution x
      join public.org_action_executor e on e.action_class = x.action_class and e.kind = 'rpc'
     where x.action_class = 'recommend' and x.status = 'queued'
     order by x.created_at limit 1;
    v_located := case when v_sid is not null then 'action_execution.workflow_step_run_id'
                      when v_actor is not null then 'action_execution.request.actor' else 'nothing queued' end;
  end if;
  if v_sid is not null then
    select s.actor, s.step_no, s.input->>'step', s.workflow_run_id, r.workflow_key, coalesce(r.context,'{}'::jsonb), w.name
      into v_actor, v_step_no, v_step, v_run, v_wf, v_ctx, v_wfname
      from public.workflow_step_run s
      join public.workflow_run r on r.id = s.workflow_run_id
      left join public.workflow w on w.workflow_key = r.workflow_key
     where s.id = v_sid;
    v_employee := public.fn_workflow_actor_resolve(v_run, v_actor);
  elsif v_actor is not null then
    v_employee := public.fn_org_agent_resolve(v_actor);
  end if;
  select o.department into v_dept from public.org_agents o where o.agent_key = v_employee and o.active;
  if v_dept is null then
    determination := 'no_scope'; employee := v_employee; department := null; workflow_key := v_wf; step_no := v_step_no; step := v_step;
    outcome := 'no determination: the caller resolves to no active employee, so there is no department whose numbers to read';
    deliverable := outcome;
    inputs := jsonb_build_object('located_by', v_located, 'step_run_id', v_sid, 'actor', v_actor, 'employee', v_employee);
    recommendations := null;
    return next; return;
  end if;
  -- metric_definition.owner_dept still speaks the pre-merge vocabulary (marketing, it, knowledge ...);
  -- org_departments.merged_into is the crosswalk, so a growth step also reads 'marketing' metrics.
  select coalesce(array_agg(d.dept_key), '{}') into v_old_depts
    from public.org_departments d where d.merged_into = v_dept or d.dept_key = v_dept;

  -- 2. THE STEP'S OWN WORDS choose the framing; the numbers are the same engine.
  v_framing := case
    when v_step ilike '%variance%' then 'variance'
    when v_step ilike '%root cause%' then 'root_cause'
    when v_step ilike '%revise%' or v_step ilike '%retire%' then 'revise_or_retire'
    when v_step ilike '%option%' then 'options'
    when v_step ilike '%grade%' or v_step ilike '%monitor%' then 'grade'
    when v_step ilike '%baseline%' then 'baseline'
    when v_step ilike '%define the metric%' then 'define'
    else 'recommend' end;

  -- 3. THE DEPARTMENT'S KPIs, with yesterday's (or the last recorded) value beside today's.
  with k as (
    select k.id, k.agent_key, k.metric, k.kpi, k.unit, k.cadence, k.target_value t, k.actual_value v,
           k.measured_at, k.no_measure_reason, k.serves_goal,
           (select h.actual_value from public.employee_kpi_history h
             where h.kpi_id = k.id and (k.measured_at is null or h.measured_at < k.measured_at - interval '1 hour')
             order by h.measured_at desc limit 1) prev,
           (select h.measured_on from public.employee_kpi_history h
             where h.kpi_id = k.id and (k.measured_at is null or h.measured_at < k.measured_at - interval '1 hour')
             order by h.measured_at desc limit 1) prev_on,
           (select count(*) from public.employee_kpi_history h
             where h.kpi_id = k.id and h.verdict = 'MISSED' and h.measured_on >= current_date - 14) missed_14d
      from public.employee_kpi k join public.org_agents a on a.agent_key = k.agent_key
     where k.active and a.department = v_dept
  ), s as (
    select k.*,
      case when v is null or t is null then null
           when t = 0 then case when v <= 0 then 100.0 else 0.0 end
           when unit = 'percent_max' then round(least(100.0, 100.0 * t / nullif(v,0)), 1)
           else round(100.0 * v / t, 1) end attainment
      from k
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'kpi_id', id, 'agent', agent_key, 'metric', metric, 'unit', unit, 'cadence', cadence,
           'target', t, 'actual', v, 'attainment', attainment,
           'verdict', case when v is null then 'NO DATA' when attainment is null then 'NO TARGET'
                           when attainment >= 100 then 'MET' when attainment >= 90 then 'NEAR' else 'MISSED' end,
           'measured_at', measured_at, 'previous', prev, 'previous_on', prev_on,
           'delta', case when v is not null and prev is not null then round(v - prev, 2) end,
           'missed_days_14d', missed_14d, 'no_measure_reason', no_measure_reason, 'serves_goal', serves_goal)
           order by (v is null), attainment nulls last, id), '[]'::jsonb),
         count(*), count(*) filter (where v is not null),
         count(*) filter (where v is not null and attainment is not null and attainment < 90),
         count(*) filter (where attainment >= 100)
    into v_kpis, v_kpi_rows, v_kpi_measured, v_kpi_missed, v_kpi_met
    from s;

  -- 4. THE COMPANY SCORECARD rows this department owns, with the prior snapshot beside the latest.
  select coalesce(jsonb_agg(jsonb_build_object(
           'metric_key', b.metric_key, 'label', b.label, 'owner_dept', b.owner_dept, 'value', b.value,
           'target', b.target, 'direction', b.direction, 'state', b.state, 'taken_at', b.taken_at,
           'previous', (select m.value from public.metric_snapshot m where m.metric_key = b.metric_key
                          and m.taken_at < b.taken_at - interval '20 hours' and m.error is null
                          order by m.taken_at desc limit 1),
           'delta', case when b.value is not null then round(b.value - (select m.value from public.metric_snapshot m
                          where m.metric_key = b.metric_key and m.taken_at < b.taken_at - interval '20 hours' and m.error is null
                          order by m.taken_at desc limit 1), 2) end)
           order by case b.state when 'OFF_TARGET' then 0 when 'BEHIND' then 1 when 'ERROR' then 2 when 'UNMEASURED' then 3 else 4 end, b.metric_key), '[]'::jsonb),
         count(*), count(*) filter (where b.state in ('OFF_TARGET','BEHIND'))
    into v_sc, v_sc_rows, v_sc_off
    from public.v_bi_scorecard b
   where b.owner_dept = any (v_old_depts);

  -- 5. AD DATA, when the sync has written any. Only the growth scope reads it; it is that department's.
  if v_dept = 'growth' then
    select coalesce(jsonb_agg(jsonb_build_object('campaign', m.campaign_name, 'status', m.effective_status,
             'window', m.time_window, 'spend', m.spend, 'currency', m.currency, 'impressions', m.impressions,
             'clicks', m.clicks, 'ctr', m.ctr, 'cpc', m.cpc, 'results', m.results, 'synced_at', m.synced_at,
             'synced_via', m.synced_via) order by m.synced_at desc), '[]'::jsonb), count(*)
      into v_meta, v_meta_rows
      from (select distinct on (campaign_id, time_window) * from public.meta_insights order by campaign_id, time_window, synced_at desc) m;
  end if;

  inputs := jsonb_build_object(
    'located_by', v_located, 'step_run_id', v_sid, 'actor', v_actor, 'employee', v_employee, 'department', v_dept,
    'scorecard_owner_depts', to_jsonb(v_old_depts), 'framing', v_framing,
    'kpi_rows', v_kpi_rows, 'kpi_measured', v_kpi_measured, 'kpi_missed', v_kpi_missed, 'kpi_met', v_kpi_met,
    'scorecard_rows', v_sc_rows, 'scorecard_off_target', v_sc_off, 'meta_rows', v_meta_rows,
    'kpis', v_kpis, 'scorecard', v_sc, 'meta', coalesce(v_meta, '[]'::jsonb),
    'run_context', case when v_ctx ? 'failing_metrics' or v_ctx ? 'goals_at_risk' or v_ctx ? 'title'
                        then v_ctx - 'at' - 'ref' - 'functions' else null end,
    'measured_at', now());

  employee := v_employee; department := v_dept; workflow_key := v_wf; step_no := v_step_no; step := v_step;

  -- 6. NO DATA is its own answer, in its own shape.
  if v_kpi_measured = 0 and v_sc_rows = 0 and v_meta_rows = 0 then
    determination := 'no_data';
    outcome := format('no determination for %s: %s KPI row(s) in scope and %s of them measured, %s scorecard metric(s) owned, %s ad-insight row(s)',
                      v_dept, v_kpi_rows, v_kpi_measured, v_sc_rows, v_meta_rows);
    deliverable := outcome || case when v_kpi_rows > 0 then '. The KPIs exist but carry no measurement: '
        || (select string_agg(x->>'metric' || coalesce(' (' || (x->>'no_measure_reason') || ')', ''), '; ') from jsonb_array_elements(v_kpis) x)
        || '. Instrument the measure before asking for a recommendation.' else '.' end;
    recommendations := null;
    return next; return;
  end if;

  -- 7. THE RANKED MOVERS. Missed KPIs by attainment, off-target company metrics, then anything worsening.
  with cand as (
    select 'kpi' src, x->>'metric' metric, x->>'agent' owner, (x->>'actual')::numeric actual, (x->>'target')::numeric target,
           x->>'unit' unit, (x->>'attainment')::numeric attainment, x->>'verdict' verdict,
           (x->>'previous')::numeric previous, (x->>'delta')::numeric delta, x->>'measured_at' measured_at,
           (x->>'missed_days_14d')::int missed_14d, x->>'serves_goal' goal,
           case x->>'verdict' when 'MISSED' then 0 when 'NEAR' then 1 when 'NO TARGET' then 3 else 4 end sev
      from jsonb_array_elements(v_kpis) x where x->>'verdict' <> 'NO DATA'
    union all
    select 'scorecard', x->>'label', x->>'owner_dept', (x->>'value')::numeric, (x->>'target')::numeric, x->>'direction',
           case when (x->>'target')::numeric is null or (x->>'value')::numeric is null then null
                when (x->>'direction') = 'down' then round(least(100.0, 100.0 * (x->>'target')::numeric / nullif((x->>'value')::numeric,0)), 1)
                else round(100.0 * (x->>'value')::numeric / nullif((x->>'target')::numeric,0), 1) end,
           x->>'state', (x->>'previous')::numeric, (x->>'delta')::numeric, x->>'taken_at', null, null,
           case x->>'state' when 'OFF_TARGET' then 0 when 'BEHIND' then 1 when 'ERROR' then 2 else 4 end
      from jsonb_array_elements(v_sc) x where x->>'state' not in ('UNMEASURED')
  ), ranked as (
    select c.*, row_number() over (order by sev, attainment nulls last, delta nulls last, metric) rk from cand c
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'rank', rk, 'source', src, 'metric', metric, 'owner', owner, 'actual', actual, 'target', target, 'unit', unit,
           'attainment_pct', attainment, 'verdict', verdict, 'previous', previous, 'delta', delta, 'measured_at', measured_at,
           'missed_days_14d', missed_14d, 'serves_goal', goal,
           'trend', case when delta is null then 'no prior measurement' when delta > 0 then 'up ' || delta when delta < 0 then 'down ' || abs(delta) else 'flat' end,
           'determination', case v_framing
             when 'variance' then case when verdict in ('MISSED','OFF_TARGET','BEHIND')
                 then format('variance: %s at %s against target %s (%s%% attainment); %s',
                             metric, actual, target, attainment, case when delta is null then 'no prior point to trend' when delta < 0 then 'worsened by ' || abs(delta) || ' since the previous measurement' when delta > 0 then 'improved by ' || delta || ' but still short' else 'unchanged' end)
                 else format('within tolerance: %s at %s against target %s (%s%%)', metric, actual, target, attainment) end
             when 'root_cause' then case
                 when verdict in ('MET','ON_TARGET','NEAR') then format('%s is at %s%% of target: no gap to explain', metric, attainment)
                 when coalesce(missed_14d, 0) >= 10 and coalesce(delta, 0) <= 0 then format('the TARGET: %s missed on %s of the last 14 measured days with no improving trend (actual %s vs target %s); propose a revised target with the run of actuals as evidence', metric, missed_14d, actual, target)
                 when delta is not null and delta > 0 then format('the WORK: %s is moving toward target (%s -> %s, target %s); keep the current plan and re-measure on cadence', metric, previous, actual, target)
                 else format('the WORK: %s at %s vs target %s (%s%%) with %s missed day(s) in 14; the gap is recent enough to be closed by the owner %s', metric, actual, target, attainment, coalesce(missed_14d,0), owner) end
             when 'revise_or_retire' then case
                 when coalesce(missed_14d, 0) >= 14 then format('REVISE: %s missed every one of the last 14 measured days (actual %s vs target %s); the target does not describe this business yet', metric, actual, target)
                 when verdict in ('MET','ON_TARGET') and coalesce(missed_14d, 0) = 0 then format('KEEP: %s met at %s against %s and never missed in 14 days', metric, actual, target)
                 else format('KEEP and watch: %s at %s%% attainment, %s missed day(s) in 14', metric, attainment, coalesce(missed_14d,0)) end
             when 'options' then format('option: close the gap on %s (actual %s, target %s, gap %s %s); cost proxy = gap size, risk = %s', metric, actual, target, round(abs(coalesce(target,0) - coalesce(actual,0)), 2), coalesce(unit,''), case when attainment is null then 'unknown' when attainment < 50 then 'high (below half of target)' when attainment < 90 then 'medium' else 'low' end)
             when 'grade' then format('grade: %s %s (%s -> %s against target %s)', metric, case when delta is null then 'UNGRADED, no prior measurement' when (unit = 'percent_max' or unit = 'down') and delta < 0 then 'BETTER' when (unit = 'percent_max' or unit = 'down') and delta > 0 then 'WORSE' when delta > 0 then 'BETTER' when delta < 0 then 'WORSE' else 'FLAT' end, previous, actual, target)
             when 'baseline' then format('baseline captured: %s = %s (%s) measured %s, target %s', metric, actual, coalesce(unit,''), measured_at, target)
             else format('%s: %s at %s against target %s (%s%%), owner %s', verdict, metric, actual, target, attainment, owner) end)
           order by rk), '[]'::jsonb), count(*)
    into v_recs, v_n
    from ranked where rk <= 5;

  determination := 'recommendation';
  recommendations := v_recs;
  v_one := coalesce((select x->>'determination' from jsonb_array_elements(v_recs) x order by (x->>'rank')::int limit 1), 'nothing in scope moved');
  outcome := left(format('%s: %s of %s KPIs measured, %s missed, %s met; %s of %s owned scorecard metrics off target%s. Top mover: %s',
                    v_dept, v_kpi_measured, v_kpi_rows, v_kpi_missed, v_kpi_met, v_sc_off, v_sc_rows,
                    case when v_meta_rows > 0 then format('; %s ad-insight row(s) read', v_meta_rows) else '' end, v_one), 600);
  v_text := format(E'%s\nWorkflow %s step %s (%s), worked by %s for %s on %s.\nInputs: %s KPI rows (%s measured, %s missed, %s met), %s scorecard metrics (%s off target), %s ad-insight rows.\n',
                   case v_framing when 'variance' then 'VARIANCE AGAINST TARGET' when 'root_cause' then 'ROOT CAUSE: THE WORK OR THE TARGET' when 'revise_or_retire' then 'REVISE OR RETIRE' when 'options' then 'OPTIONS WITH COST AND RISK' when 'grade' then 'GRADE AGAINST BASELINE' when 'baseline' then 'BASELINE' when 'define' then 'METRIC DEFINITION REVIEW' else 'RECOMMENDATION' end,
                   coalesce(v_wfname, v_wf, '(no workflow)'), coalesce(v_step_no::text, '-'), coalesce(v_step, 'direct call'), v_employee, v_dept, to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI') || ' UTC',
                   v_kpi_rows, v_kpi_measured, v_kpi_missed, v_kpi_met, v_sc_rows, v_sc_off, v_meta_rows);
  for rec in select x from jsonb_array_elements(v_recs) x order by (x->>'rank')::int loop
    v_text := v_text || format(E'%s. %s [%s; trend %s; measured %s]\n', rec.x->>'rank', rec.x->>'determination', rec.x->>'source', rec.x->>'trend', coalesce(left(rec.x->>'measured_at', 16), '?'));
  end loop;
  if v_meta_rows > 0 then
    v_text := v_text || 'Ad data: ' || (select string_agg(format('%s [%s] %s: spend %s %s, %s impressions, %s clicks, ctr %s, cpc %s (synced %s via %s)',
        m->>'campaign', m->>'status', m->>'window', m->>'spend', m->>'currency', m->>'impressions', m->>'clicks', coalesce(m->>'ctr','-'), coalesce(m->>'cpc','-'), left(m->>'synced_at',10), m->>'synced_via'), '; ')
        from jsonb_array_elements(v_meta) m) || E'\n';
  end if;
  if v_ctx ? 'failing_metrics' then
    v_text := v_text || 'Trigger context named failing metrics ' || (v_ctx->'failing_metrics')::text || coalesce(' and goals at risk ' || (v_ctx->'goals_at_risk')::text, '') || E'.\n';
  end if;
  v_text := v_text || 'Basis: employee_kpi actual/target as measured, employee_kpi_history for the previous point and the 14-day miss count, v_bi_scorecard + metric_snapshot for company metrics' || case when v_dept = 'growth' then ', meta_insights for ad data' else '' end || '. No model call.';
  deliverable := v_text;

  if p_record then
    insert into public.org_memory(scope, kind, content, source)
    values ('analytics', 'insight', left(coalesce(v_wf,'direct') || ' step ' || coalesce(v_step_no::text,'-') || ' — ' || outcome, 500) || E'\n\n' || left(v_text, 3000), 'fn_recommend_deterministic');
  end if;
  return next;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reconcile_doc_blocks(p_grace_days integer DEFAULT 0)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_lic_susp int := 0; v_ins_susp int := 0; v_restored int := 0;
  v_cut date := current_date - make_interval(days => p_grace_days);
  rec record;
begin
  -- ---- SUSPEND: trade licence expired -------------------------------------------------
  -- Only touches rows that are unblocked or already blocked for a document reason, so a
  -- manual block set by the team is never overwritten or silently cleared.
  for rec in
    select id, company_name, claimed_by, email, phone, whatsapp, license_expiry
      from leads
     where approval_status = 'approved' and coalesce(banned,false) = false
       and license_expiry is not null and license_expiry < v_cut
       and (coalesce(matching_blocked,false) = false
            or matching_block_reason in ('licence_expired','insurance_expired'))
       and coalesce(matching_block_reason,'') is distinct from 'licence_expired'
  loop
    update leads set matching_blocked = true, matching_block_reason = 'licence_expired'
     where id = rec.id;
    v_lic_susp := v_lic_susp + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_suspended', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is paused - trade licence expired',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your trade licence expired on ' || rec.license_expiry || ', so your account has been temporarily paused and you will not receive new customer requests until it is renewed.' || chr(10) || chr(10) ||
      'To restore your account: reply to this email with the renewed licence attached, or upload it in the Documents tab of your supplier portal. Your account is restored automatically as soon as we have a valid copy - nothing else is needed and no fee applies.',
      'queued');
  end loop;

  -- ---- SUSPEND: insurance expired -----------------------------------------------------
  for rec in
    select id, company_name, claimed_by, email, insurance_expiry
      from leads
     where approval_status = 'approved' and coalesce(banned,false) = false
       and insurance_expiry is not null and insurance_expiry < v_cut
       and (coalesce(matching_blocked,false) = false
            or matching_block_reason in ('licence_expired','insurance_expired'))
       and coalesce(matching_block_reason,'') is distinct from 'insurance_expired'
       -- a licence block is the more serious of the two, so do not downgrade its reason
       and coalesce(matching_block_reason,'') is distinct from 'licence_expired'
  loop
    update leads set matching_blocked = true, matching_block_reason = 'insurance_expired'
     where id = rec.id;
    v_ins_susp := v_ins_susp + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_suspended', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is paused - insurance expired',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Your insurance certificate expired on ' || rec.insurance_expiry || ', so your account has been temporarily paused and you will not receive new customer requests until it is renewed.' || chr(10) || chr(10) ||
      'To restore your account: reply to this email with the renewed certificate attached, or upload it in the Documents tab of your supplier portal. Your account is restored automatically as soon as we have a valid copy.',
      'queued');
  end loop;

  -- ---- RESTORE: the blocking document is valid again -----------------------------------
  -- Only clears blocks this job set. A manual block stays put.
  for rec in
    select id, company_name, claimed_by, email, matching_block_reason
      from leads
     where matching_block_reason in ('licence_expired','insurance_expired')
       and ((matching_block_reason = 'licence_expired'
             and (license_expiry is null or license_expiry >= v_cut))
         or (matching_block_reason = 'insurance_expired'
             and (insurance_expiry is null or insurance_expiry >= v_cut)))
  loop
    update leads set matching_blocked = false, matching_block_reason = null where id = rec.id;
    v_restored := v_restored + 1;
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('doc_restored', coalesce(rec.claimed_by, rec.email), 'supplier', rec.id, 'email',
      'Your QuotesDone account is active again',
      'Dear ' || coalesce(rec.company_name,'supplier') || ',' || chr(10) || chr(10) ||
      'Thank you - your documents are up to date and your account is active again. You will start receiving matching customer requests immediately.',
      'queued');
  end loop;

  return json_build_object('licence_suspended', v_lic_susp, 'insurance_suspended', v_ins_susp,
                           'restored', v_restored, 'grace_days', p_grace_days, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_record_llm_attempt(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_req      uuid    := coalesce(nullif(p->>'request_id','')::uuid, gen_random_uuid());
  v_model    text    := nullif(p->>'model_route','');
  v_ok       boolean := coalesce((p->>'ok')::boolean, false);
  v_no       integer;
  v_cls      jsonb;
  v_key      text;
  v_trips    boolean;
  v_first    boolean;
  v_thresh   integer;
  v_cool     integer;
  v_conseq   integer;
  v_state    text := 'closed';
  v_id       uuid;
  v_in       integer := nullif(p->>'prompt_tokens','')::integer;
  v_out      integer := nullif(p->>'output_tokens','')::integer;
  v_cached   integer := coalesce(nullif(p->>'cached_in_tokens','')::integer, 0);
  v_cost     numeric := nullif(p->>'cost_aed','')::numeric;
begin
  if v_model is null then
    raise exception 'fn_record_llm_attempt requires model_route: the route is what the breaker keys on';
  end if;

  if not v_ok then
    v_cls := fn_classify_llm_failure(p->>'err_excerpt',
                                     nullif(p->>'http_status','')::integer,
                                     p->>'finish_reason', v_model,
                                     nullif(p->>'latency_ms','')::integer);
    v_key := v_cls->>'class_key';
  end if;

  -- attempt_no is assigned HERE, never accepted from the caller. A caller cannot claim to be
  -- attempt 1 twice, and cannot renumber an earlier attempt out of the way.
  select coalesce(max(attempt_no), 0) + 1 into v_no from llm_attempt where request_id = v_req;

  insert into llm_route_health (model_id) values (v_model) on conflict (model_id) do nothing;
  select failure_threshold, cooldown_seconds into v_thresh, v_cool
    from llm_route_health where model_id = v_model;

  if v_ok then
    update llm_route_health
       set consecutive_failures = 0, open_until = null, opened_reason = null, opened_class = null,
           last_ok_at = now(), total_attempts = total_attempts + 1, total_ok = total_ok + 1,
           updated_at = now()
     where model_id = v_model;
  else
    select trips_breaker, opens_on_first into v_trips, v_first
      from llm_failure_class where class_key = v_key;
    update llm_route_health
       set consecutive_failures = case when coalesce(v_trips,false)
                                       then consecutive_failures + 1 else consecutive_failures end,
           last_failure_at = now(), total_attempts = total_attempts + 1, updated_at = now()
     where model_id = v_model
     returning consecutive_failures into v_conseq;

    if coalesce(v_trips,false) and (coalesce(v_first,false) or v_conseq >= v_thresh) then
      update llm_route_health
         set open_until = now() + make_interval(secs => v_cool),
             opened_reason = case when coalesce(v_first,false)
                             then 'opened on first occurrence of ' || v_key
                             else v_conseq || ' consecutive failures, threshold ' || v_thresh end,
             opened_class = v_key
       where model_id = v_model;
      v_state := 'opened_by_this';
    end if;
  end if;

  -- DERIVE THE MONEY HERE, from the same pricing source ai_cost_log uses, rather than trusting a
  -- caller to convert. A caller that computes its own AED is a second pricing implementation, and
  -- two of those drift. An explicit cost_aed in the payload still wins, so a provider that reports
  -- its own charge can be recorded verbatim.
  --
  -- Deliberately only when tokens are present: a failed attempt that produced no usage block has
  -- no measurable cost, and inventing 0 there would make "this retry was free" indistinguishable
  -- from "nobody recorded what this retry cost".
  if v_cost is null and (v_in is not null or v_out is not null) then
    begin
      v_cost := public.fn_model_cost_usd(v_model, coalesce(v_in,0), coalesce(v_out,0), v_cached)
                * public.fn_usd_to_aed();
    exception when others then v_cost := null;   -- pricing is reporting, never a gate
    end;
  end if;

  insert into llm_attempt (request_id, attempt_no, fn, agent_key, task_class, model_route, tier,
                           ok, class_key, http_status, finish_reason, err_excerpt,
                           evidence_truncated, latency_ms, prompt_tokens, output_tokens, cost_aed,
                           breaker_state)
  values (v_req, v_no, p->>'fn', p->>'agent_key', p->>'task_class', v_model, p->>'tier',
          v_ok, v_key, nullif(p->>'http_status','')::integer, p->>'finish_reason',
          left(coalesce(p->>'err_excerpt',''), 4000),
          coalesce((v_cls->>'evidence_truncated')::boolean, false),
          nullif(p->>'latency_ms','')::integer, v_in, v_out, v_cost,
          v_state)
  returning attempt_id into v_id;

  return jsonb_build_object(
    'attempt_id', v_id, 'request_id', v_req, 'attempt_no', v_no,
    'class_key', v_key, 'breaker', v_state,
    'cost_aed', v_cost,
    'retry_allowed', case when v_ok then false
                          when v_state = 'opened_by_this' then false   -- fail closed, do not retry into a wall
                          else fn_llm_retry_allowed(v_key, v_no) end,
    'retry_backoff_ms', coalesce((v_cls->>'retry_backoff_ms')::integer, 0),
    'evidence_truncated', coalesce((v_cls->>'evidence_truncated')::boolean, false));
end $function$


CREATE OR REPLACE FUNCTION public.fn_record_routine_change()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record;
begin
  for r in select * from pg_event_trigger_ddl_commands()
            where object_type in ('function', 'procedure') and schema_name = 'public'
  loop
      insert into public.routine_change_log (application_name, client_addr, command_tag, object_identity, statement_head)
      values (current_setting('application_name', true), inet_client_addr(), r.command_tag, r.object_identity,
              regexp_replace(regexp_replace(left(current_query(), 2000),
                '((key|secret|password|passwd|token|bearer|authorization)[a-z_]*\s*(=|:)\s*)(''[^'']*''|"[^"]*"|\S{8,})', '\1[REDACTED]', 'gi'),
                '\m((sk|rk|pk)_(live|test)_|whsec_|sbp_|eyJ)[A-Za-z0-9_\-\.]{8,}', '[REDACTED]', 'g'));
  end loop;
exception when others then null;  -- recording must never block the change it records, including a failure to read the event
end $function$


CREATE OR REPLACE FUNCTION public.fn_record_routine_drop()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record;
begin
  for r in select * from pg_event_trigger_dropped_objects()
            where object_type in ('function', 'procedure') and schema_name = 'public'
  loop
      insert into public.routine_change_log (application_name, client_addr, command_tag, object_identity, statement_head)
      values (current_setting('application_name', true), inet_client_addr(), 'DROP FUNCTION', r.object_identity,
              regexp_replace(regexp_replace(left(current_query(), 2000),
                '((key|secret|password|passwd|token|bearer|authorization)[a-z_]*\s*(=|:)\s*)(''[^'']*''|"[^"]*"|\S{8,})', '\1[REDACTED]', 'gi'),
                '\m((sk|rk|pk)_(live|test)_|whsec_|sbp_|eyJ)[A-Za-z0-9_\-\.]{8,}', '[REDACTED]', 'g'));
  end loop;
exception when others then null;
end $function$


CREATE OR REPLACE FUNCTION public.fn_record_tool_call(p_correlation uuid, p_agent_key text, p_role_id text, p_tool_id text, p_args jsonb, p_status text, p_result_hash text, p_result_rows integer, p_result_bytes integer, p_error text, p_attempt integer, p_latency_ms integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  insert into agent_tool_call (correlation_id, agent_key, role_id, tool_id, args, status,
                               result_hash, result_rows, result_bytes, error, attempt, latency_ms)
  values (p_correlation, p_agent_key, p_role_id, p_tool_id, coalesce(p_args,'{}'::jsonb), p_status,
          p_result_hash, p_result_rows, p_result_bytes, left(p_error, 500),
          coalesce(p_attempt,1), p_latency_ms)
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_amount_aed(p_paid_aed numeric, p_paid_at timestamp with time zone, p_refund_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_paid numeric; v_admin numeric; v_pct numeric; v_days integer; v_interest numeric;
  v_min integer; v_max integer;
begin
  -- The customer's refund is the fee actually paid, in full: the published Refund Policy promises no
  -- administrative deduction and fn_refund_amount_is_the_fee_paid enforces it on the refunds row.
  v_paid  := round(coalesce(p_paid_aed, 0), 2);
  -- 24 SEP 2026 (ceo): REFERENCE figures for the knowledge texts only; the charge a supplier actually owes is
  -- fn_accountant_nonresponse_charge, by the Supplier Agreement version it had signed (v14: + processor fee, agreed 12%).
  -- The administrative fee and the annual rate (decision_policy) are what the SUPPLIER whose
  -- silence caused the refund owes on top of the fee: founder decision 6 Sep 2026, verbatim in
  -- decision_policy.refund_policy_founder_decision_2026_09_06.
  v_admin := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_admin_fee_aed'), 250);
  v_pct   := coalesce((select (d.value #>> '{}')::numeric from public.decision_policy d where d.key = 'refund_late_fee_annual_pct'), 9);
  select bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_min, v_max from public.pricing_config order by id limit 1;
  -- simple interest, pro-rated by CALENDAR days (Dubai dates) between the two instants
  v_days := greatest(0, (coalesce(p_refund_at, now()) at time zone 'Asia/Dubai')::date
                      - (coalesce(p_paid_at, coalesce(p_refund_at, now())) at time zone 'Asia/Dubai')::date);
  v_interest := round(v_paid * v_pct / 100.0 * v_days / 365.0, 2);
  return jsonb_build_object(
    'paid_aed', v_paid,
    'customer_refund_aed', v_paid,
    'admin_fee_aed', v_admin,
    'interest_pct_pa', v_pct,
    'interest_days', v_days,
    'interest_aed', v_interest,
    'supplier_charge_aed', round(v_paid + v_admin + v_interest, 2),
    'bank_settlement_working_days', coalesce(v_min, 7)::text || '-' || coalesce(v_max, 14)::text,
    'basis', 'customer: the reveal fee paid, refunded in full, no deduction; supplier (reference, current version; the exact charge is fn_accountant_nonresponse_charge): that fee + from v14 the processor fee not recovered + AED '
             || v_admin::text || ' administrative fee + ' || v_pct::text
             || '% p.a. simple interest for ' || v_days::text || ' calendar day(s)');
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_amount_is_the_fee_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions%rowtype;
  v_expected bigint;
  -- A refund Stripe already issued is a fact to be recorded, not a request to be approved.
  v_external constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
begin
  if lower(coalesce(NEW.requested_by,'')) = any(v_external) then
    return NEW;
  end if;

  if NEW.transaction_id is null then
    raise exception 'refunds: a refund must name the transaction it reverses. transaction_id is null, so this row asserts money is owed without saying which payment it came from. (refund_names_no_payment)'
      using errcode = '23514',
            hint = 'Set transaction_id to the public.transactions row whose reveal_fee is being returned. A refund this platform did not issue is recorded through fn_refund_settle with requested_by stripe_webhook, and that path is exempt.';
  end if;

  select * into t from public.transactions where id = NEW.transaction_id;
  if not found then
    raise exception 'refunds: transaction % does not exist. (refund_transaction_absent)',
      NEW.transaction_id using errcode = '23503';
  end if;

  if coalesce(t.total_charged, t.reveal_fee) is null or coalesce(t.total_charged, t.reveal_fee) <= 0 then
    raise exception 'refunds: transaction % records no reveal fee (reveal_fee %), so there is nothing to give back. A refund of an unpaid reveal is a payment, not a refund. (refund_no_fee_was_paid)',
      NEW.transaction_id, coalesce(t.reveal_fee::text,'null') using errcode = '23514';
  end if;

  if t.refund_deadline is null then
    raise exception 'refunds: transaction % has no refund window. trg_reveal_window opens one at reveal, so a transaction without it was never revealed and no refund can be due yet. (refund_window_not_open)',
      NEW.transaction_id using errcode = '23514';
  end if;
  -- THE WINDOW GOVERNS THE DECISION, NOT THE REQUEST (14 Sep 2026). The terms let the customer
  -- complain "at any time"; what waits for the fifth working day and the CEO's final call is the
  -- approval. So a row at 'requested' is recorded whenever it arrives, and only the move to money
  -- (approved, processing, succeeded) is refused before refund_deadline.
  if NEW.status in ('approved', 'processing', 'succeeded') and now() < t.refund_deadline then
    raise exception 'refunds: transaction % may not be approved or paid before % (it is now %). The supplier has five working days from the payment and the CEO''s final call before a refund is decided; the request itself is recorded at any time. (refund_window_not_yet_open)',
      NEW.transaction_id, t.refund_deadline, now() using errcode = '23514';
  end if;

  -- ── THE STRIPE REFERENCE, ADDED 9 SEP 2026 ───────────────────────────────────────────────────
  -- The founder: "it's issued against that exact invoice reference... It has an ID." The reference
  -- Stripe gave us when the customer paid is transactions.payment_ref (stripe_webhook writes the
  -- payment_intent, falling back to the checkout session id). Until now stripe_payment_intent on a
  -- refund was a nullable text column nothing checked, so a refund could name transaction A and
  -- cite the payment of transaction B -- or name no payment at all -- and still move money.
  if coalesce(btrim(t.payment_ref), '') = '' then
    raise exception 'refunds: transaction % carries no Stripe payment reference, so there is no payment of record to reverse. (refund_payment_has_no_reference)',
      NEW.transaction_id using errcode = '23514',
            hint = 'transactions.payment_ref is written by stripe_webhook when the reveal fee settles. A transaction without one was never paid through Stripe, and money must not be returned against a payment nobody can point at.';
  end if;
  if coalesce(btrim(NEW.stripe_payment_intent), '') = '' then
    raise exception 'refunds: this refund names no Stripe payment. Transaction % was paid under reference %, and a refund is issued against that exact reference. (refund_names_no_stripe_reference)',
      NEW.transaction_id, t.payment_ref using errcode = '23514',
            hint = 'Set stripe_payment_intent to the payment_ref of the transaction being reversed. Founder ruling, 9 Sep 2026.';
  end if;
  if btrim(NEW.stripe_payment_intent) <> btrim(t.payment_ref) then
    raise exception 'refunds: this refund cites Stripe payment %, but transaction % was paid under %. A refund is issued against the exact reference of the payment it reverses, never another one. (refund_cites_the_wrong_stripe_payment)',
      NEW.stripe_payment_intent, NEW.transaction_id, t.payment_ref using errcode = '23514';
  end if;

  -- AND THE AMOUNT IS READ OFF THAT PAYMENT. Equality, not a ceiling: the reveal fee is refunded
  -- whole or not at all, so "cannot exceed what the payment took" is enforced by the stricter rule
  -- that it must EQUAL it. A platform refund with no amount is refused outright -- an unstated
  -- figure is not a smaller figure, it is an unbounded one.
  v_expected := round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint;
  -- A TOP-UP (topup_of set) completes a case on THIS payment and carries only the part still owed, so
  -- it is exempt from equality; a01 caps it, and every live refund on the payment together, at
  -- total_charged (PR #640 re-review, 14 Sep 2026).
  if NEW.topup_of is not null then
    if not exists (select 1 from public.refunds c where c.id = NEW.topup_of and c.transaction_id = NEW.transaction_id and c.topup_of is null) then
      raise exception 'refunds: a top-up must name a refund case on the same payment; % is not one for transaction %. (refund_topup_names_no_case)',
        NEW.topup_of, NEW.transaction_id using errcode = '23514';
    end if;
    if NEW.amount_fils is null or NEW.amount_fils <= 0 then
      raise exception 'refunds: a top-up must state a positive amount. (refund_states_no_amount)' using errcode = '23514';
    end if;
    return NEW;
  end if;
  if NEW.amount_fils is null then
    raise exception 'refunds: a platform refund must state its amount. Transaction % took % fils (AED %), and that is the only figure this refund may carry. (refund_states_no_amount)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2) using errcode = '23514';
  end if;
  if NEW.amount_fils <> v_expected then
    raise exception 'refunds: the amount must equal what the customer actually paid, the 3%% and the processing part together (total_charged), on transaction % — expected % fils (AED %), got % fils (AED %). A refund figure is read off the payment, never typed. (refund_amount_is_not_the_fee_paid)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2), NEW.amount_fils, round(NEW.amount_fils/100.0,2)
      using errcode = '23514';
  end if;

  return NEW;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_refund_attach_receipt(p_refund_id bigint, p_receipt_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_existing text; v_ok boolean;
begin
  if p_refund_id is null or p_refund_id <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'no refund id');
  end if;
  if coalesce(btrim(p_receipt_url), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no receipt url');
  end if;
  -- Stripe's hosted receipts live on stripe.com. A column the founder and the CEO open as "the
  -- document behind this refund" may not be made to point somewhere else by a spoofed payload.
  if p_receipt_url !~ '^https://[a-z0-9.-]*\.?stripe\.com/' then
    return jsonb_build_object('ok', false, 'reason', 'not a stripe.com receipt url', 'given', left(p_receipt_url, 120));
  end if;

  select stripe_receipt_url into v_existing from public.refunds where id = p_refund_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', format('no refund %s', p_refund_id));
  end if;
  if coalesce(v_existing, '') <> '' then
    return jsonb_build_object('ok', true, 'unchanged', true, 'reason', 'a receipt is already recorded; the first one is the one the money moved under');
  end if;

  update public.refunds set stripe_receipt_url = p_receipt_url
   where id = p_refund_id and stripe_receipt_url is null;
  get diagnostics v_ok = row_count;
  return jsonb_build_object('ok', v_ok, 'refund_id', p_refund_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_ceo_approval_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.status <> 'approved' then return new; end if;
  if exists (select 1 from public.ceo_identity c
              where c.active and lower(c.identity) = lower(btrim(coalesce(new.decided_by, '')))) then
    return new;
  end if;
  raise exception 'refund %: approved by %, who is not an active CEO identity.',
    coalesce(new.id::text, '(new)'), coalesce(nullif(btrim(new.decided_by), ''), '(nobody)')
    using errcode = '42501',
          hint = 'Refunds belong to the CEO — the founder''s ruling of 8 Sep 2026, replacing his '
              || '17 Aug rule that every refund needed him. A refund reaches ''approved'' only with '
              || 'a decided_by that is an active row in public.ceo_identity. decided_by is checked '
              || 'against that table and never trusted as supplied: the hole this closes is a refund '
              || 'that approved itself as ''policy:auto_window''.';
end
$function$


CREATE OR REPLACE FUNCTION public.fn_refund_decide(p_refund_id bigint, p_approve boolean, p_decided_by text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r public.refunds; v_app public.ceo_approval; v_new text; v_gate jsonb;
begin
  select * into r from public.refunds where id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'requested' then return jsonb_build_object('ok', false, 'error', 'not_decidable', 'status', r.status); end if;
  if coalesce(btrim(p_decided_by), '') = '' then return jsonb_build_object('ok', false, 'error', 'decider_required'); end if;
  if lower(btrim(p_decided_by)) like 'policy:%' then
    return jsonb_build_object('ok', false, 'error', 'automatic_decider_refused',
      'hint', 'A refund is decided by an actor, not by a rule. Approvals are the CEO''s.');
  end if;

  if p_approve then
    select * into v_app from public.ceo_approval a
     where a.subject_kind = 'refund' and a.subject_id = p_refund_id::text and a.decision = 'approved' and a.superseded_by is null
     order by a.decision_id desc limit 1;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'no_ceo_approval',
        'hint', 'A refund is approved only by a CEO approval that passed the process checklist (fn_ceo_refund_review, or ceo_agent decide). This routine records that decision; it cannot make one.');
    end if;
    -- A REFUND IS HIGH STAKES (29 Sep 2026, instruction 1009): a second seat on another family must agree first. While
    -- the model hold is on the refund proceeds and the review is owed; a later disagreement opens a finding.
    v_gate := public.fn_high_stakes_gate('refund', 'ceo', 'refunds', p_refund_id::text,
      'Should this refund be approved as the CEO decided?',
      jsonb_build_object('refund', jsonb_build_object('amount_fils', r.amount_fils, 'currency', r.currency, 'reason_code', r.reason_code,
        'reason_note', left(r.reason_note, 1000), 'requested_by', r.requested_by, 'within_auto_window', r.within_auto_window)),
      jsonb_build_object('decision', 'approve', 'ceo_rationale', left(v_app.rationale, 3000), 'amount_aed', v_app.amount_aed));
    if not coalesce((v_gate->>'proceed')::boolean, false) then
      return jsonb_build_object('ok', false, 'error', 'awaiting_second_seat', 'clearance', v_gate);
    end if;
    update public.refunds set status = 'approved', decided_by = v_app.decided_by, decided_at = now(),
           decision_note = coalesce(p_note, v_app.rationale), refund_decision_id = v_app.decision_id
     where id = p_refund_id;
    v_new := 'approved';
  else
    update public.refunds set status = 'rejected', decided_by = p_decided_by, decided_at = now(), decision_note = p_note where id = p_refund_id;
    v_new := 'rejected';
  end if;
  if r.transaction_id is not null then
    update public.transactions set refund_status = v_new, refund_resolved_at = now(), refund_note = coalesce(p_note, refund_note)
     where id = r.transaction_id;
  end if;
  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'status', v_new, 'decided_by', coalesce(v_app.decided_by, p_decided_by));
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_document(p_refund_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select jsonb_build_object(
       'ok',              v.doc_path is not null,
       'refund_id',       v.id,
       'transaction_id',  v.transaction_id,
       'status',          v.status,
       'amount_fils',     v.amount_fils,
       'currency',        v.currency,
       'stripe_payment_intent', v.stripe_payment_intent,
       'stripe_charge_id',      v.stripe_charge_id,
       'stripe_refund_id',      v.stripe_refund_id,
       'stripe_receipt_url',    v.stripe_receipt_url,
       'stripe_binding',  v.stripe_binding,
       'bucket',          v.doc_bucket,
       'path',            v.doc_path,
       'name',            v.doc_name,
       'content_type',    v.doc_content_type,
       'kind',            v.doc_kind,
       'note',            v.doc_note,
       'state',           v.document_state,
       'reason',          case
                            when v.doc_path is not null then null
                            when v.stripe_receipt_url is not null
                              then 'No file is stored for this refund yet. Stripe''s own hosted '
                                || 'receipt for the payment is known and is returned as '
                                || 'stripe_receipt_url; it has not been fetched into finance-docs.'
                            else 'This refund has no stored document and no Stripe receipt reference. '
                              || 'The reveal fee was taken through a mode=payment Checkout, which '
                              || 'produces no Stripe invoice, so the receipt reference has to be read '
                              || 'off the charge before anything can be stored.'
                          end)
     from public.v_refund_documents v where v.id = p_refund_id),
    jsonb_build_object('ok', false, 'refund_id', p_refund_id, 'state', 'no_such_refund',
                       'reason', 'There is no public.refunds row with that id.'));
$function$


CREATE OR REPLACE FUNCTION public.fn_refund_document_coverage()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'refunds',          count(*),
    'openable',         count(*) filter (where is_openable),
    'reference_only',   count(*) filter (where document_state = 'reference_only'),
    'unclassified',     count(*) filter (where document_state = 'unclassified'),
    'missing',          count(*) filter (where document_state = 'missing'),
    'missing_ids',      coalesce(jsonb_agg(id order by id) filter (where document_state = 'missing'), '[]'::jsonb),
    'stripe_bound',     count(*) filter (where stripe_binding = 'bound'),
    'stripe_unbound_ids', coalesce(jsonb_agg(id order by id)
                            filter (where stripe_binding in ('no_reference','mismatched','no_transaction')), '[]'::jsonb),
    'by_kind',          (select coalesce(jsonb_object_agg(document_state, n), '{}'::jsonb)
                         from (select document_state, count(*) n
                               from public.v_refund_documents group by 1) s))
  from public.v_refund_documents;
$function$


CREATE OR REPLACE FUNCTION public.fn_refund_execute_authorized(p_refund_id bigint, p_expect_amount numeric, p_expect_currency text, p_provider_ref text, p_provider_outcome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; t record; v_dest text; v_basis text; v_state text;
begin
  select * into r from public.refund_case where refund_id = p_refund_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund case'); end if;

  -- THE SERVER-SIDE DECISION, read here rather than accepted from the caller. There is no parameter
  -- for "the CEO approved this", so a model cannot supply one.
  if r.state <> 'ceo_authorized' then
    return jsonb_build_object('ok', false, 'reason',
      format('this refund is %L, not ceo_authorized. Execution reads the decision from the record; it is not something a caller can assert.', r.state));
  end if;

  -- EXACT RESOURCE, AMOUNT AND CURRENCY. A mismatch is refused rather than rounded to the nearer of
  -- the two: "close enough" on money is the whole class of defect.
  if p_expect_amount is distinct from r.amount_aed then
    return jsonb_build_object('ok', false, 'reason',
      format('amount mismatch: the authorised refund is %s, the caller expected %s. Refusing rather than paying the difference in either direction.', r.amount_aed, p_expect_amount));
  end if;
  if upper(coalesce(p_expect_currency,'')) <> upper(r.currency) then
    return jsonb_build_object('ok', false, 'reason',
      format('currency mismatch: authorised in %s, caller expected %s.', r.currency, coalesce(p_expect_currency,'(none)')));
  end if;

  if r.attempts >= 5 then
    return jsonb_build_object('ok', false, 'reason',
      'retry policy exhausted at 5 attempts. The refund stays authorised and unpaid, which is a visible blocked state -- not a silent success and not an infinite retry against a provider that is down.');
  end if;

  -- THE DESTINATION IS DERIVED, NEVER PASSED. "Do not refund to an arbitrary new destination."
  select id, fee_status, reveal_fee, payment_ref into t
    from public.transactions where id = r.transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'the settled payment behind this refund no longer exists; there is no destination of record to return money to.');
  end if;
  v_dest := t.payment_ref;
  v_basis := 'the original settled payment on transaction ' || r.transaction_id::text
          || '. Money returns the way it came; this function has no parameter for anywhere else.';
  if coalesce(v_dest,'') = '' then
    update public.refund_case set attempts = r.attempts + 1, last_attempt_at = now(),
      failure_reason = 'no payment reference on the settled transaction, so no destination of record.', updated_at = now()
     where refund_id = p_refund_id;
    return jsonb_build_object('ok', false, 'reason',
      'the settled payment carries no reference, so there is no destination of record. Held as authorised-and-blocked rather than sent somewhere plausible.');
  end if;

  v_state := case lower(coalesce(p_provider_outcome,''))
    when 'succeeded' then 'succeeded'
    when 'pending'   then 'provider_pending'
    when 'failed'    then 'failed'
    else 'submitted' end;

  update public.refund_case
     set state = v_state, destination_ref = v_dest, destination_basis = v_basis,
         provider_ref = p_provider_ref, provider_status = p_provider_outcome,
         submitted_at = coalesce(submitted_at, now()),
         settled_at = case when v_state = 'succeeded' then now() else settled_at end,
         failure_reason = case when v_state = 'failed' then coalesce(p_provider_outcome,'provider reported failure') else failure_reason end,
         attempts = r.attempts + 1, last_attempt_at = now(), updated_at = now()
   where refund_id = p_refund_id;

  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'state', v_state,
    'destination_ref', v_dest, 'destination_basis', v_basis, 'attempt', r.attempts + 1,
    'note', case v_state
      when 'succeeded' then 'Settled at the provider. The customer still has to be TOLD -- succeeded is not communicated.'
      when 'failed' then 'The provider refused it. This stays visible and retriable within policy; it is not a closed case.'
      else 'Submitted. Submitted is not settled, and the status tool reads the provider, not this row''s optimism.' end);
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_execution_requires_ceo_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_money_moved constant text[] := array['approved','processing','succeeded'];
  -- A refund Stripe already issued is a FACT to be recorded, not a request to be approved. Refusing
  -- the row would delete our only record of real money leaving, which is worse than admitting it.
  v_external    constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
  d public.ceo_approval%rowtype;
begin
  if not (new.status = any(v_money_moved)) then return new; end if;
  if tg_op = 'UPDATE' and old.status = any(v_money_moved)
     and new.refund_decision_id is not distinct from old.refund_decision_id then
    return new;   -- already past this boundary and not changing which decision it cites
  end if;
  if lower(coalesce(new.requested_by, '')) = any(v_external) then
    return new;
  end if;

  if new.refund_decision_id is null then
    raise exception 'refunds %: a platform-originated refund may not reach status % without naming the CEO decision that authorised it.',
      coalesce(new.id::text, '(new)'), new.status
      using errcode = '23514',
            hint = 'Record one in public.ceo_approval (subject_kind = ''refund'', subject_id = this '
                || 'refund''s id) and cite its decision_id. Founder ruling, 8 Sep 2026: all '
                || 'approvals are the CEO''s.';
  end if;

  select * into d from public.ceo_approval where decision_id = new.refund_decision_id;
  if not found then
    raise exception 'refunds %: refund_decision_id % names no CEO decision',
      coalesce(new.id::text, '(new)'), new.refund_decision_id using errcode = '23503';
  end if;
  if d.subject_kind <> 'refund' then
    raise exception 'refunds %: decision % is a % decision, not a refund decision',
      coalesce(new.id::text, '(new)'), d.decision_id, d.subject_kind using errcode = '23514';
  end if;

  -- THE BINDING THIS ROUTINE WAS MISSING UNTIL 9 SEP 2026. Everything above this line was already
  -- checked; subject_id was read and never compared, so one approved decision could authorise every
  -- refund in the table. ONE APPROVAL, ONE REFUND, ALWAYS.
  -- A TOP-UP (topup_of) completes the amount the CEO approved for its case, so it cites THAT decision
  -- (PR #640 re-review, 14 Sep 2026). Any other row still needs a decision naming itself.
  if d.subject_id is distinct from new.id::text
     and not (new.topup_of is not null and d.subject_id = new.topup_of::text) then
    raise exception 'refunds %: decision % approved refund %, not this one. One approval authorises one refund.',
      coalesce(new.id::text, '(new)'), d.decision_id, coalesce(d.subject_id, '(nothing)')
      using errcode = '23514',
            hint = 'The CEO decides each refund on its own facts. Reusing another refund''s approval '
                || 'would move money nobody approved. Record a ceo_approval row whose subject_id is '
                || 'this refund''s id, and cite that.';
  end if;

  if d.decision <> 'approved' then
    raise exception 'refunds %: decision % refused this refund; it may not reach %',
      coalesce(new.id::text, '(new)'), d.decision_id, new.status using errcode = '23514';
  end if;
  if d.superseded_by is not null then
    raise exception 'refunds %: decision % was superseded by %; cite the decision that stands',
      coalesce(new.id::text, '(new)'), d.decision_id, d.superseded_by using errcode = '23514';
  end if;
  return new;
end
$function$


CREATE OR REPLACE FUNCTION public.fn_refund_ladder_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t record; st jsonb; v_window int; v_chase int; v_refund bigint;
  n_seen int := 0; n_chased int := 0; n_final int := 0; v_ids jsonb := '[]'::jsonb; v_watch jsonb; v_loop jsonb;
begin
  select refund_window_working_days, chase_after_working_days into v_window, v_chase from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);

  for t in
    select x.* from public.transactions x
     where x.revealed_at is not null and coalesce(x.total_charged, x.reveal_fee, 0) > 0
       and coalesce(x.refund_status, '') not in ('approved', 'refunded', 'processing', 'succeeded', 'rejected', 'cancelled', 'failed')
       and x.revealed_at > now() - interval '120 days'
     order by x.revealed_at
  loop
    n_seen := n_seen + 1;
    st := public.fn_refund_state(t.id);
    continue when st ? 'error' or coalesce((st->>'supplier_responded')::boolean, false);
    continue when st->>'state' not in ('chase_due', 'final_call_due');

    if st->>'state' = 'chase_due' then
      perform public.fn_sales_engineer_ladder_step(t.id, 'chase', null, null);
      n_chased := n_chased + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'chase');
    else
      -- DAY 5: the refund is filed through the one door (fn_refund_request; the CEO decides, the guards
      -- on refunds refuse money moving any other way) and the sales engineer makes the final call.
      if not exists (select 1 from public.refunds r where r.transaction_id = t.id) then
        perform public.fn_refund_request(
          round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint, 'supplier_unresponsive', 'refund_ladder_sweep',
          t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id, t.payment_ref, null,
          'Day ' || v_window || ' of the refund ladder: the supplier responded neither to the customer nor to the day-' || v_chase
            || ' chase. Filed by the ladder; the sales engineer makes the final call through support and the CEO decides on what comes back.',
          t.id);
      end if;
      select r.id into v_refund from public.refunds r where r.transaction_id = t.id order by r.id desc limit 1;
      perform public.fn_sales_engineer_ladder_step(t.id, 'final_call', v_refund, null);
      n_final := n_final + 1;
      v_ids := v_ids || jsonb_build_object('transaction_id', t.id, 'step', 'final_call', 'refund_id', v_refund);
    end if;
  end loop;

  v_watch := public.fn_customer_support_delivery_watch(null);
  v_loop  := public.fn_ceo_refund_loop_sweep();
  return jsonb_build_object('ok', true, 'seen', n_seen, 'chased', n_chased, 'final_calls', n_final,
                            'window_working_days', v_window, 'chase_after_working_days', v_chase,
                            'owner_agent', 'sales_engineer writes, customer_support delivers, ceo decides',
                            'cases', v_ids, 'support_watch', v_watch, 'ceo_loop', v_loop, 'ran_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_nonresponse_eligibility(p_transaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  w public.supplier_response_watch; c public.pricing_config;
  v_wd int; v_att int; v_ch int; v_reasons text[] := '{}';
begin
  select * into w from public.supplier_response_watch where transaction_id = p_transaction_id;
  select * into c from public.pricing_config limit 1;

  if w.id is null then
    return jsonb_build_object('eligible', false, 'basis', 'no_watch',
      'detail', 'Support has not recorded contacting this supplier at all, so there is no evidence of silence to decide on.');
  end if;

  -- WORKING days between the first attempt and now: Friday and Saturday are the UAE weekend.
  select count(*) into v_wd
    from generate_series((w.opened_at at time zone 'Asia/Dubai')::date,
                         (now()      at time zone 'Asia/Dubai')::date, interval '1 day') d
   where extract(isodow from d) not in (5, 6);
  v_wd := greatest(v_wd - 1, 0);   -- the opening day itself is not an elapsed day

  select count(*), count(distinct a->>'channel')
    into v_att, v_ch
    from jsonb_array_elements(w.attempts) a;

  if w.first_response_at is not null then
    v_reasons := v_reasons || ('the supplier replied on ' || w.first_response_at::text || ' via ' || coalesce(w.response_channel,'?'));
  end if;
  if v_wd < c.refund_window_working_days then
    v_reasons := v_reasons || (v_wd || ' working day(s) have passed of the ' || c.refund_window_working_days || ' the terms allow');
  end if;
  if v_att < c.supplier_nonresponse_min_attempts then
    v_reasons := v_reasons || ('support made ' || v_att || ' attempt(s), fewer than the ' || c.supplier_nonresponse_min_attempts || ' required');
  end if;
  if v_ch < c.supplier_nonresponse_min_channels then
    v_reasons := v_reasons || ('support used ' || v_ch || ' channel(s), fewer than the ' || c.supplier_nonresponse_min_channels || ' required');
  end if;

  return jsonb_build_object(
    'eligible', array_length(v_reasons,1) is null,
    'basis', 'measured',
    'transaction_id', p_transaction_id,
    'working_days_elapsed', v_wd,
    'working_days_required', c.refund_window_working_days,
    'attempts', v_att, 'attempts_required', c.supplier_nonresponse_min_attempts,
    'channels', v_ch, 'channels_required', c.supplier_nonresponse_min_channels,
    'supplier_replied', w.first_response_at is not null,
    'first_response_at', w.first_response_at,
    'blocking_reasons', coalesce(to_jsonb(v_reasons), '[]'::jsonb),
    'evidence', w.attempts);
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_nonresponse_needs_silence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  if new.decision is distinct from 'approved' then return new; end if;
  if coalesce(new.eligibility,'') is distinct from 'supplier_nonresponse' then return new; end if;

  v := public.fn_refund_nonresponse_eligibility(new.transaction_id);
  if (v->>'eligible')::boolean is not true then
    raise exception 'this refund is approved on supplier non-response, and the record does not show non-response: %',
      coalesce(v->>'blocking_reasons', v->>'detail');
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_open_from_customer(p_transaction_id uuid, p_requested_by text, p_reason_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; c record; v_id bigint; v_open bigint; v_locale text; v_code text; v_en text; v_ar text;
  v_later boolean := false; v_paid text; v_decide text; v_req bigint; v_amt numeric;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'no_such_transaction', 'locale', 'en', 'can_claim_later', false,
      'message_en', 'We could not find that reveal on your account.', 'message_ar', 'لم نعثر على عملية الكشف هذه في حسابكم.');
  end if;
  select id, email into c from public.customers where id = t.customer_id;
  v_locale := coalesce(public.fn_registered_locale('customer', t.customer_id, null, c.email), 'en');
  v_amt := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);
  v_paid := to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
  v_decide := to_char(t.refund_deadline at time zone 'Asia/Dubai', 'DD Mon YYYY');

  -- ONE CLAIM PER PAYMENT: a second press, or a retry, returns the case already open.
  select id into v_open from public.refunds
   where transaction_id = t.id and status not in ('rejected', 'failed', 'cancelled')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')
   order by id limit 1;
  if v_open is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'refund_id', v_open, 'locale', v_locale, 'decision_after', t.refund_deadline,
      'message_en', 'Your refund case QD-RF-' || v_open || ' is already open. Our chief executive decides it after ' || coalesce(v_decide, 'the fifth working day') || '; you do not need to do anything else.',
      'message_ar', 'حالة الاسترداد QD-RF-' || v_open || ' مفتوحة بالفعل، وسيبتّ فيها رئيسنا التنفيذي بعد ' || coalesce(v_decide, 'يوم العمل الخامس') || '، ولا يلزمكم أي إجراء آخر.');
  end if;

  -- THE REFUSALS, each with the reason and whether a claim can come later.
  if t.revealed_at is null then
    v_code := 'not_revealed'; v_later := true;
    v_en := 'This reveal has not completed yet. You can ask for a refund once the payment has gone through and the supplier''s details are shown to you.';
    v_ar := 'لم تكتمل عملية الكشف بعد. يمكنكم طلب الاسترداد بعد إتمام الدفع وظهور بيانات المورّد لكم.';
  elsif coalesce(btrim(t.payment_ref), '') = '' then
    v_code := 'no_payment'; v_later := true;
    v_en := 'We have no recorded payment for this reveal yet, so there is nothing to refund. If you were charged, reply to your payment receipt and we will match it; you can ask again once it is recorded.';
    v_ar := 'لا يوجد لدينا دفع مسجّل لعملية الكشف هذه حتى الآن، فلا مبلغ يُسترد. وإن خُصم منكم أي مبلغ، فيُرجى الرد على إيصال الدفع لنطابقه، ويمكنكم تقديم الطلب مجددًا بعد تسجيله.';
  elsif coalesce(t.refund_status, '') in ('approved', 'refunded', 'processing', 'succeeded') then
    v_code := 'already_refunded';
    v_en := 'This reveal has already been refunded (AED ' || coalesce(t.refund_amount_aed, v_amt) || '). Banks take 7 to 14 working days to show it.';
    v_ar := 'سبق أن استُردّت رسوم عملية الكشف هذه (' || coalesce(t.refund_amount_aed, v_amt) || ' درهم)، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهار المبلغ.';
  elsif exists (select 1 from public.refunds r where r.transaction_id = t.id and r.status = 'rejected'
                  and lower(coalesce(r.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')) then
    v_code := 'already_declined';
    v_en := 'Our chief executive has already decided this case and declined it; the reason is shown on your refund case. Under section 5 of the Terms a decided case is not reopened by a new request. If you think the record is wrong, reply to the decision email.';
    v_ar := 'سبق أن بتّ رئيسنا التنفيذي في هذه الحالة ورفضها، والسبب مبيّن في حالة الاسترداد. ووفق البند 5 من الشروط، لا يُعاد فتح حالة بُتّ فيها بطلب جديد. وإن رأيتم أن السجل غير صحيح، فيُرجى الرد على رسالة القرار.';
  elsif exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id) then
    v_code := 'job_completed';
    v_en := 'This job is marked as completed with this supplier, so the supplier responded and the reveal fee is not refundable (Terms, section 5).';
    v_ar := 'هذا العمل مسجّل مكتملًا مع هذا المورّد، ما يعني أنه استجاب، لذا لا تُسترد رسوم الكشف (الشروط، البند 5).';
  elsif exists (select 1 from public.reviews v where v.transaction_id = t.id) then
    v_code := 'supplier_rated';
    v_en := 'You have rated this supplier, which records that you dealt with them, so the reveal fee is not refundable (Terms, section 5).';
    v_ar := 'قيّمتم هذا المورّد، وهو ما يُثبت تعاملكم معه، لذا لا تُسترد رسوم الكشف (الشروط، البند 5).';
  end if;
  if v_code is not null then
    -- Recorded, so a refusal is as visible to the seats as a case: who asked, when, and why not.
    perform public.fn_emit('refund.request_refused', 'transaction', t.id::text, coalesce(p_requested_by, 'customer'),
      jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'code', v_code, 'can_claim_later', v_later, 'reason', v_en));
    return jsonb_build_object('ok', false, 'code', v_code, 'can_claim_later', v_later, 'locale', v_locale, 'message_en', v_en, 'message_ar', v_ar);
  end if;

  -- THE CASE. The amount is what the customer paid (total_charged); a00 holds it to that figure and to
  -- the payment's own Stripe reference. trg_emit_refund_requested and z30 put it on the bus and hand
  -- it to the accountant.
  insert into public.refunds
    (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id,
     stripe_payment_intent, amount_fils, currency, reason_code, reason_note,
     status, requested_by, requested_at, amount_source)
  values
    (t.id, t.quote_id, t.inquiry_id, t.customer_id, t.supplier_id,
     t.payment_ref, round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint, 'AED',
     'supplier_unresponsive',
     coalesce(p_reason_note, 'The customer reported that the revealed supplier has not responded.'),
     'requested', coalesce(p_requested_by, 'customer'), now(), 'in_platform_request')
  returning id into v_id;

  -- The sale follows the case, never the other way round. The refunds row already exists, so
  -- trg_emit_refund_requested_tx sees it and does not emit a second refund.requested.
  update public.transactions
     set refund_status = 'requested', refund_requested_at = coalesce(refund_requested_at, now())
   where id = t.id;

  -- The confirmation: the sales engineer writes it, customer support delivers it in the customer's
  -- registered language (fn_sales_engineer_writes -> delivery.request).
  v_req := public.fn_sales_engineer_writes('refund_request_received', 'customer', c.email, null, t.customer_id, t.inquiry_id, t.quote_id,
    'Your refund case QD-RF-' || v_id || ' is open',
    'We have opened refund case QD-RF-' || v_id || ' for the supplier you revealed on ' || coalesce(v_paid, 'your payment date') || '. You do not need to do anything else.' || E'\n\n'
      || 'The supplier has until ' || coalesce(v_decide, 'the fifth working day after your payment') || ' to respond. We chase them on the third working day and copy you. '
      || 'If there is still no response, our chief executive makes a final call and then decides your case on the record. '
      || 'If the refund is due, everything you paid (AED ' || v_amt || ') is returned to your original payment method; banks take 7 to 14 working days to show it.',
    'فتحنا حالة الاسترداد QD-RF-' || v_id,
    'فتحنا حالة الاسترداد QD-RF-' || v_id || ' بشأن المورّد الذي كشفتم عنه في ' || coalesce(v_paid, 'تاريخ الدفع') || '. لا يلزمكم أي إجراء آخر.' || E'\n\n'
      || 'أمام المورّد حتى ' || coalesce(v_decide, 'يوم العمل الخامس بعد الدفع') || ' للرد، وسنتابعه في يوم العمل الثالث مع نسخة إليكم، '
      || 'فإن لم يردّ، فسيوجّه إليه رئيسنا التنفيذي نداءً أخيرًا ثم يبتّ في حالتكم استنادًا إلى السجل. '
      || 'وإن ثبت استحقاق الاسترداد، فسيُردّ إليكم كامل ما دفعتموه (' || v_amt || ' درهم) إلى وسيلة الدفع الأصلية، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره.',
    '{}', 'refund_request_received:' || t.id, null,
    jsonb_build_object('step', 'customer_request', 'transaction_id', t.id, 'refund_id', v_id));

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'status', 'requested', 'locale', v_locale,
    'decision_after', t.refund_deadline, 'delivery_request', v_req,
    'message_en', 'Refund case QD-RF-' || v_id || ' is open. Our chief executive decides it after ' || coalesce(v_decide, 'the fifth working day') || ', and if it is due everything you paid is refunded. We have emailed you the details.',
    'message_ar', 'فتحنا حالة الاسترداد QD-RF-' || v_id || '، وسيبتّ فيها رئيسنا التنفيذي بعد ' || coalesce(v_decide, 'يوم العمل الخامس') || '، وإن ثبت استحقاق الاسترداد فسيُردّ إليكم كامل ما دفعتموه. وقد أرسلنا إليكم التفاصيل بالبريد الإلكتروني.');
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_quarantine(p_stripe_refund_id text, p_event_type text, p_reason text, p_payload jsonb DEFAULT NULL::jsonb, p_stripe_event_id text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into public.refund_event_quarantine (stripe_refund_id, stripe_event_id, event_type, reason, payload)
  values (nullif(btrim(coalesce(p_stripe_refund_id,'')),''), nullif(btrim(coalesce(p_stripe_event_id,'')),''),
          p_event_type, p_reason, p_payload)
  returning id;
$function$


CREATE OR REPLACE FUNCTION public.fn_refund_read_status(p_refund_id bigint, p_mark_reported boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_say text;
begin
  select * into r from public.refund_case where refund_id = p_refund_id;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such refund case'); end if;

  -- THE CUSTOMER-FACING SENTENCE IS DERIVED FROM THE STATE, not composed. "Support sends accurate
  -- pending/failed/succeeded updates" -- accurate meaning the words cannot drift from the row.
  v_say := case r.state
    when 'requested'      then 'I have your refund request and I am looking into it now.'
    when 'investigating'  then 'I am still checking the payment and the delivery on your inquiry.'
    when 'eligible'       then 'I have finished checking and your request is going for a decision.'
    when 'ineligible'     then 'I have checked this and it is not eligible for a refund. ' || coalesce(r.eligibility_reason,'')
    when 'ceo_authorized' then 'Your refund has been approved. It has not left us yet -- I will tell you the moment it is sent.'
    when 'ceo_declined'   then 'Your refund was not approved. ' || coalesce(r.decision_rationale,'')
    when 'submitted'      then 'Your refund has been sent to the payment provider. It is not settled yet.'
    when 'provider_pending' then 'Your refund is with the payment provider and is still processing.'
    when 'succeeded'      then 'Your refund has been paid back to the card or account you originally paid from.'
    when 'failed'         then 'The refund did not go through at the payment provider. It is not lost -- I am on it and will come back to you.'
    when 'canceled'       then 'This refund was cancelled before it was sent.'
    when 'reconciled'     then 'Your refund is complete and reconciled on our side.'
    when 'communicated'   then 'Your refund is complete and you have been notified.'
    else 'I am checking the current state of your refund.' end;

  if p_mark_reported then
    update public.refund_case
       set status_reported_at = now(), status_reported_state = r.state, updated_at = now()
     where refund_id = p_refund_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', p_refund_id, 'state', r.state,
    'amount_aed', r.amount_aed, 'currency', r.currency, 'attempts', r.attempts,
    'provider_status', r.provider_status, 'destination_basis', r.destination_basis,
    'customer_message', v_say,
    -- A SUCCEEDED REFUND THE CUSTOMER HAS NOT BEEN TOLD ABOUT is an unfinished case, and this names it.
    'follow_through_owed', r.state in ('succeeded','failed','ceo_declined')
                           and (r.status_reported_state is distinct from r.state));
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_request(p_amount_fils bigint, p_reason_code text, p_requested_by text, p_inquiry_id uuid DEFAULT NULL::uuid, p_customer_id uuid DEFAULT NULL::uuid, p_supplier_lead_id bigint DEFAULT NULL::bigint, p_quote_id uuid DEFAULT NULL::uuid, p_payment_intent text DEFAULT NULL::text, p_charge_id text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_transaction_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; v_task bigint; v_in_window boolean := false; t public.transactions;
begin
  if p_amount_fils is null or p_amount_fils <= 0 then
    return jsonb_build_object('ok', false, 'error', 'amount_required');
  end if;

  select * into t from public.transactions
   where (p_transaction_id is not null and id = p_transaction_id)
      or (p_transaction_id is null and p_quote_id is not null and quote_id = p_quote_id)
      or (p_transaction_id is null and p_quote_id is null and p_payment_intent is not null and payment_ref = p_payment_intent)
   order by revealed_at desc nulls last limit 1;

  -- Recorded, never acted on. Whether the request arrived inside the window promised at reveal is
  -- exactly the kind of thing the decider wants in front of them, and exactly the kind of thing that
  -- must not decide for them.
  if t.id is not null and t.refund_deadline is not null and t.refund_deadline >= now() then
    v_in_window := true;
  end if;

  insert into public.refunds (transaction_id, inquiry_id, customer_id, supplier_lead_id, quote_id,
                              stripe_payment_intent, stripe_charge_id,
                              amount_fils, reason_code, reason_note, requested_by,
                              within_auto_window, status, reconciliation_note)
  values (t.id, coalesce(p_inquiry_id, t.inquiry_id), coalesce(p_customer_id, t.customer_id),
          coalesce(p_supplier_lead_id, t.supplier_id), coalesce(p_quote_id, t.quote_id),
          coalesce(p_payment_intent, t.payment_ref), p_charge_id,
          p_amount_fils, p_reason_code, p_note, p_requested_by,
          v_in_window, 'requested',
          'ROUTED TO THE CEO. Every refund waits for the CEO seat''s decision, whatever the amount '
       || 'and whether or not it is inside the promised window — founder ruling, 8 Sep 2026, '
       || 'replacing his 17 Aug rule that every refund needed him personally. This one is '
       || round(p_amount_fils / 100.0, 2) || ' AED and is '
       || case when v_in_window then 'inside' else 'outside' end || ' the window promised at reveal.')
  returning id into v_id;

  if t.id is not null then
    update public.transactions
       set refund_status = 'requested',
           refund_reason = coalesce(refund_reason, p_reason_code),
           refund_requested_at = coalesce(refund_requested_at, now()),
           refund_note = coalesce(p_note, refund_note)
     where id = t.id;
  end if;

  -- THE ROUTE. Without this the request is recorded and nothing is asked of anyone.
  insert into public.ceo_task (title, detail)
  values (
    'Decide refund ' || v_id || ' — AED ' || round(p_amount_fils / 100.0, 2),
    'Refund ' || v_id || ' requested by ' || coalesce(nullif(btrim(p_requested_by), ''), '(unknown)')
      || ' for ' || round(p_amount_fils / 100.0, 2) || ' AED, reason ' || coalesce(p_reason_code, '(none)')
      || '. Transaction ' || coalesce(t.id::text, '(none matched)')
      || '. The request arrived ' || case when v_in_window then 'INSIDE' else 'OUTSIDE' end
      || ' the refund window promised at reveal — a fact, not a decision.'
      || coalesce(chr(10) || 'Customer note: ' || nullif(btrim(p_note), ''), '')
      || chr(10) || chr(10)
      || 'To approve: write a row in public.ceo_approval (subject_kind = ''refund'') and set '
      || 'refunds.refund_decision_id to it. The guards on public.refunds will refuse the money moving '
      || 'any other way.')
  returning task_id into v_task;

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'transaction_id', t.id,
                            'status', 'requested',
                            'within_auto_window', v_in_window,
                            'auto_approved', false,
                            'ceo_task_id', v_task,
                            'awaiting', 'ceo');
end
$function$


CREATE OR REPLACE FUNCTION public.fn_refund_request_hands_to_accountant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.transaction_id is not null and NEW.status = 'requested'
     and lower(coalesce(NEW.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') then
    perform public.fn_seat_handoff('sales_engineer', 'accountant', 'refund.requested', 'refunds', NEW.id::text,
      jsonb_build_object('refund_id', NEW.id, 'transaction_id', NEW.transaction_id, 'customer_id', NEW.customer_id,
                         'inquiry_id', NEW.inquiry_id, 'quote_id', NEW.quote_id));
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_settle(p_stripe_refund_id text, p_status text, p_amount_fils bigint DEFAULT NULL::bigint, p_payment_intent text DEFAULT NULL::text, p_charge_id text DEFAULT NULL::text, p_failure_reason text DEFAULT NULL::text, p_amount_source text DEFAULT 'webhook_event'::text, p_stripe_event_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.refunds; v_status text; v_amount bigint; v_src text; v_q bigint;
begin
  if coalesce(btrim(p_stripe_refund_id),'') = '' then
    v_q := public.fn_refund_quarantine(null, 'refund', 'event carried no refund id',
             jsonb_build_object('status', p_status, 'payment_intent', p_payment_intent), p_stripe_event_id);
    return jsonb_build_object('ok', false, 'error', 'stripe_refund_id_required', 'quarantined', v_q);
  end if;

  v_status := case lower(coalesce(p_status,''))
                when 'succeeded' then 'succeeded' when 'failed' then 'failed'
                when 'canceled' then 'cancelled'  when 'cancelled' then 'cancelled'
                else 'processing' end;
  v_amount := nullif(coalesce(p_amount_fils, 0), 0);
  v_src    := case when v_amount is null then null else coalesce(p_amount_source, 'webhook_event') end;

  select * into r from public.refunds where stripe_refund_id = p_stripe_refund_id for update;

  if not found then
    select * into r from public.refunds
     where stripe_refund_id is null and p_payment_intent is not null
       and stripe_payment_intent = p_payment_intent and status in ('approved','processing','requested')
     order by created_at limit 1 for update;

    if found then
      update public.refunds set stripe_refund_id = p_stripe_refund_id,
             stripe_charge_id = coalesce(p_charge_id, stripe_charge_id) where id = r.id;
    else
      -- Issued outside the platform. Recorded with whatever is actually known, and NOTHING invented:
      -- if the amount is unknown it stays NULL and the row is marked unreconciled.
      insert into public.refunds (stripe_refund_id, stripe_payment_intent, stripe_charge_id,
                                  amount_fils, amount_source, reason_code, reason_note, requested_by, status,
                                  decided_by, decided_at, decision_note, reconciliation_note)
      values (p_stripe_refund_id, p_payment_intent, p_charge_id, v_amount,
              coalesce(v_src, 'unknown'), 'other',
              'Issued outside QuotesDone (Stripe dashboard or API). Recorded by the webhook.',
              'stripe_webhook', coalesce(v_status, 'processing'), 'stripe_dashboard', now(),
              'No in-platform request existed for this refund.',
              case when v_amount is null
                   then 'AMOUNT UNKNOWN - the event carried none and Stripe could not be read. Excluded from all financial totals until resolved.'
                   else null end)
      returning * into r;

      if v_amount is null then
        perform public.fn_refund_quarantine(p_stripe_refund_id, 'refund',
          'amount unknown: absent from the event and not retrievable from Stripe',
          jsonb_build_object('status', v_status, 'payment_intent', p_payment_intent, 'refund_row', r.id),
          p_stripe_event_id);
      end if;

      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'applied', true,
                                'created', true, 'amount_known', v_amount is not null);
    end if;
  end if;

  -- Duplicate delivery: same state twice. Cheap, silent, correct - but still take the chance to fill
  -- in an amount we did not have before.
  if r.status = v_status then
    if r.amount_fils is null and v_amount is not null then
      update public.refunds
         set amount_fils = v_amount, amount_source = v_src,
             reconciliation_note = 'amount resolved from a later ' || coalesce(p_amount_source,'event'),
             updated_at = now()
       where id = r.id;
      return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                                'idempotent', true, 'applied', false, 'amount_resolved', true);
    end if;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status,
                              'idempotent', true, 'applied', false);
  end if;

  -- The matrix decides. Not a rank, not an ordering heuristic - a declared policy with a reason
  -- attached to every refusal.
  if not public.fn_refund_transition_allowed(r.status, v_status) then
    v_q := public.fn_refund_quarantine(p_stripe_refund_id, 'refund',
      'transition not permitted: ' || r.status || ' -> ' || v_status || '. '
      || coalesce((select note from public.refund_status_transition
                    where from_status = r.status and to_status = v_status), 'no rule declared for this pair'),
      jsonb_build_object('refund_row', r.id, 'from', r.status, 'to', v_status,
                         'amount_fils', p_amount_fils, 'payment_intent', p_payment_intent),
      p_stripe_event_id);
    update public.refunds
       set reconciliation_note = left(coalesce(reconciliation_note || ' | ', '')
           || 'refused ' || r.status || '->' || v_status || ' at ' || to_char(now(),'YYYY-MM-DD HH24:MI'), 500),
           updated_at = now()
     where id = r.id;
    return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', r.status, 'applied', false,
                              'refused_transition', r.status || '->' || v_status, 'quarantined', v_q);
  end if;

  update public.refunds
     set status = v_status,
         amount_fils   = coalesce(v_amount, amount_fils),
         amount_source = case when v_amount is not null then v_src else amount_source end,
         stripe_charge_id = coalesce(p_charge_id, stripe_charge_id),
         stripe_payment_intent = coalesce(p_payment_intent, stripe_payment_intent),
         settled_at = case when v_status = 'succeeded' then coalesce(settled_at, now()) else settled_at end,
         failure_reason = case when v_status = 'failed' then p_failure_reason else failure_reason end,
         reconciliation_note = case
             when v_status = 'succeeded' and coalesce(v_amount, amount_fils) is null
             then 'AMOUNT UNKNOWN on a settled refund - excluded from all financial totals until resolved.'
             else reconciliation_note end,
         updated_at = now()
   where id = r.id;

  if r.transaction_id is not null then
    update public.transactions
       set refund_status = v_status, refund_stripe_id = p_stripe_refund_id,
           refund_amount_aed = case when v_amount is not null then round(v_amount/100.0, 2) else refund_amount_aed end,
           refund_confirmed_at = case when v_status = 'succeeded' then coalesce(refund_confirmed_at, now())
                                      else refund_confirmed_at end
     where id = r.transaction_id;
  end if;

  return jsonb_build_object('ok', true, 'refund_id', r.id, 'status', v_status, 'applied', true,
                            'amount_known', coalesce(v_amount, r.amount_fils) is not null);
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_state(p_transaction uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; v_window int; v_chase int; v_notify_days int; v_min int; v_max int;
        v_responded boolean; v_chase_at timestamptz; v_final_at timestamptz; v_notify_at timestamptz;
        v_chased_at timestamptz; v_final_sent_at timestamptz; v_state text;
begin
  select * into t from transactions where id = p_transaction;
  if not found then return jsonb_build_object('error','transaction_not_found'); end if;

  -- THE LADDER (founder, 6 Sep 2026): the clock starts when the customer PAYS (revealed_at), never at
  -- a nudge or a notice. Day 3 without a supplier response: the owning employee chases. Day 5: the
  -- founder is notified for the final call and the refund becomes approvable. All from pricing_config.
  select refund_window_working_days, chase_after_working_days,
         bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  v_notify_days := coalesce((select value::text::int from decision_policy where key='refund_notify_after_working_days'),1);

  v_responded := t.supplier_ack_at is not null
    or exists (select 1 from messages m
               where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id
                 and m.sender = 'supplier' and coalesce(m.blocked,false) = false
                 and m.created_at > t.revealed_at);

  v_chase_at  := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_chase) end;
  v_final_at  := case when t.revealed_at is null then null
                      else coalesce(t.refund_deadline, public.fn_add_working_days(t.revealed_at, v_window)) end;
  v_notify_at := case when t.revealed_at is null then null else public.fn_add_working_days(t.revealed_at, v_notify_days) end;

  select min(n.created_at) into v_chased_at from notifications n
   where n.type = 'supplier_no_response_chase' and n.channel = 'email'
     and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
     and t.revealed_at is not null and n.created_at > t.revealed_at;
  -- The day-5 final call is the sales engineer's notice delivered by support (type refund_final_notice).
  -- The founder_alerts marker the ladder wrote before 14 Sep is still honoured for cases already on it.
  select least((select min(n.created_at) from notifications n
                 where n.type = 'refund_final_notice' and n.inquiry_id = t.inquiry_id and n.lead_id = t.supplier_id
                   and t.revealed_at is not null and n.created_at > t.revealed_at),
               (select min(f.created_at) from founder_alerts f where f.dedupe_key = 'refund_final_call:' || t.id::text))
    into v_final_sent_at;

  v_state := case
    when t.revealed_at is null                                                          then 'not_revealed'
    when v_responded                                                                    then 'supplier_responded'
    when coalesce(t.refund_status,'') in ('approved','refunded','processing','succeeded') then 'refunded'
    when coalesce(t.refund_status,'') = 'rejected'                                      then 'refund_rejected'
    when now() < v_chase_at                                                             then 'waiting'
    when now() < v_final_at then case when v_chased_at is null then 'chase_due' else 'chased' end
    else case when v_final_sent_at is null then 'final_call_due' else 'final_call_sent' end end;

  return jsonb_build_object(
    'transaction_id', t.id,
    'state', v_state,
    'revealed_at', t.revealed_at,
    'supplier_responded', v_responded,
    'refund_window_working_days', v_window,
    'chase_after_working_days', v_chase,
    'chase_due_at', v_chase_at,
    'chased_at', v_chased_at,
    'founder_call_due_at', v_final_at,
    'final_call_sent_at', v_final_sent_at,
    'refund_deadline', t.refund_deadline,
    'notify_available_at', v_notify_at,
    'can_notify', (t.revealed_at is not null and not v_responded and t.customer_notified_at is null
                   and now() >= v_notify_at and v_state not in ('refunded','refund_rejected')),
    'notified_at', t.customer_notified_at,
    'auto_nudged_at', t.nudged_24_at,
    'refund_approvable', v_state in ('final_call_due','final_call_sent'),
    'refund_status', t.refund_status,
    'working_days_since_reveal', case when t.revealed_at is null then 0
                                      else public.fn_working_days_between(t.revealed_at, now()) end,
    'working_days_since_notice', case when t.customer_notified_at is null then 0
                                      else public.fn_working_days_between(t.customer_notified_at, now()) end,
    'bank_settlement_working_days', coalesce(v_min,7)::text || '-' || coalesce(v_max,14)::text
  );
end $function$


CREATE OR REPLACE FUNCTION public.fn_refund_transition_allowed(p_from text, p_to text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select allowed from public.refund_status_transition
                    where from_status = p_from and to_status = p_to), false);
$function$


CREATE OR REPLACE FUNCTION public.fn_refunds_never_return_more_than_was_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.transactions; v_cap bigint; v_other bigint;
begin
  -- EVERY WRITER LOCKS THE PAYMENT FIRST (PR #640 re-review, 14 Sep 2026). A reservation, a case, a
  -- retry and a refund Stripe reported (fn_refund_settle writes those with no transaction_id, only the
  -- payment reference) all serialise on the same transactions row, so a webhook row cannot slip in
  -- between a reservation's sum and its insert. The lock is taken BEFORE any exemption.
  if NEW.transaction_id is not null then
    select * into t from public.transactions where id = NEW.transaction_id for update;
  elsif coalesce(btrim(NEW.stripe_payment_intent), '') <> '' then
    select * into t from public.transactions where payment_ref = NEW.stripe_payment_intent
     order by revealed_at desc nulls last limit 1 for update;
  end if;
  -- A refund Stripe already issued is a fact to record, never refused; it is counted below for
  -- every later writer (rows are matched by transaction OR by the payment's Stripe reference).
  if lower(coalesce(NEW.requested_by, '')) in ('stripe_webhook', 'stripe_dashboard', 'stripe') then return NEW; end if;
  if t.id is null or NEW.status in ('failed', 'rejected', 'cancelled') then return NEW; end if;   -- a00 refuses a missing transaction with its own reason
  v_cap := round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint;
  select coalesce(sum(r.amount_fils), 0) into v_other
    from public.refunds r
   where r.id is distinct from NEW.id and r.status not in ('failed', 'rejected', 'cancelled')
     and (r.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and r.stripe_payment_intent = t.payment_ref));
  if v_other + coalesce(NEW.amount_fils, 0) > v_cap then
    raise exception 'refunds: transaction % took % fils and % fils are already refunded or on their way, so % more would return more than the customer paid. (refund_exceeds_what_was_paid)',
      t.id, v_cap, v_other, coalesce(NEW.amount_fils, 0) using errcode = '23514';
  end if;
  return NEW;
end $function$


CREATE OR REPLACE FUNCTION public.fn_refunds_paused()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select (d.value #>> '{}')::boolean from public.decision_policy d
                    where d.key = 'refunds_and_supplier_charges_paused'), false);
$function$


CREATE OR REPLACE FUNCTION public.fn_refunds_settled_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.status = 'succeeded' and new.settled_at is null then new.settled_at := now(); end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.fn_register_document(p_bucket text, p_path text, p_kind text, p_ref_table text, p_ref_id text, p_file_name text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_kind text;
begin
  if p_path is null or p_path = '' then return; end if;
  v_kind := lower(btrim(coalesce(p_kind, '')));
  v_kind := case v_kind
    when 'quotation'      then 'quote'
    when 'quotations'     then 'quote'
    when 'quotes'         then 'quote'
    when 'agreement'      then 'contract'
    when 'agreements'     then 'contract'
    when 'contracts'      then 'contract'
    when 'bill'           then 'invoice'
    when 'bills'          then 'invoice'
    when 'invoices'       then 'invoice'
    when 'license'        then 'licence'
    when 'licenses'       then 'licence'
    when 'licences'       then 'licence'
    when 'cert'           then 'certificate'
    when 'certs'          then 'certificate'
    when 'certificates'   then 'certificate'
    when 'dwg'            then 'drawing'
    when 'drawings'       then 'drawing'
    when 'plan'           then 'drawing'
    when 'plans'          then 'drawing'
    when 'boq'            then 'drawing'
    when 'po'             then 'purchase_order'
    when 'pos'            then 'purchase_order'
    when 'purchase order' then 'purchase_order'
    when 'purchase-order' then 'purchase_order'
    else v_kind
  end;
  if v_kind is null or v_kind = '' then v_kind := 'other'; end if;
  insert into public.documents(bucket, path, kind, ref_table, ref_id, file_name)
  values (p_bucket, p_path, v_kind, p_ref_table, p_ref_id,
          coalesce(p_file_name, split_part(p_path, '/', array_length(string_to_array(p_path, '/'), 1))))
  on conflict (bucket, path) do nothing;
end $function$


CREATE OR REPLACE FUNCTION public.fn_registered_locale(p_role text, p_customer uuid DEFAULT NULL::uuid, p_lead bigint DEFAULT NULL::bigint, p_email text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- null ONLY when nobody is registered under these keys (a sign-up in progress): the caller then uses
  -- the language of the page the person is registering on. A registered customer answers en or ar.
  -- A SUPPLIER IS ALWAYS 'en' (founder, 28 Sep 2026): every message to a supplier is English, whatever
  -- leads.locale says; leads.locale now decides only the language the supplier portal's screens open in.
  select case when p_role = 'supplier' then 'en'
              when x is null then null when lower(x) like 'ar%' then 'ar' else 'en' end
    from (select case
      when p_role = 'customer' then coalesce(
        (select c.locale from public.customers c where c.id = p_customer),
        (select c.locale from public.customers c
          where p_email is not null and lower(c.email) = lower(btrim(p_email)) limit 1))
    end as x) s
$function$


CREATE OR REPLACE FUNCTION public.fn_rehearsal_window_covers(p_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.rehearsal_window w
    where p_at >= w.started_at
      and p_at <= coalesce(w.ended_at, w.started_at + interval '6 hours')
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_render_template(p_text text, p_vars jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k text; v text; r text := p_text;
begin
  if r is null then return null; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(p_vars, '{}'::jsonb)) loop
    r := replace(r, '{{' || k || '}}', coalesce(v, ''));
  end loop;
  return r;
end $function$


CREATE OR REPLACE FUNCTION public.fn_report_drilldown(p_metric text, p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with b as (select coalesce(nullif(btrim(p_metric), ''), '~none~') m,
                    greatest(coalesce(p_days, 30), 1) d),
  series as (
    select s.taken_at, s.value from public.metric_snapshot s, b
     where s.metric_key ilike '%' || b.m || '%'
       and s.taken_at > now() - (b.d || ' days')::interval
     order by s.taken_at desc limit 60
  )
  select jsonb_build_object(
    'metric', (select m from b), 'window_days', (select d from b),

    -- WHY IT MOVED: the last two readings, and the change between them.
    'series', coalesce((select jsonb_agg(jsonb_build_object('at', taken_at, 'value', value) order by taken_at desc) from series), '[]'::jsonb),
    'latest', (select value from series order by taken_at desc limit 1),
    'previous', (select value from series order by taken_at desc offset 1 limit 1),
    'change', (select (select value from series order by taken_at desc limit 1)
                    - (select value from series order by taken_at desc offset 1 limit 1)),
    'readings', (select count(*) from series),

    'index', (select jsonb_build_object('index_name', c.index_name, 'score', c.score, 'band', c.band,
                'measured_on', c.measured_on, 'dimensions', c.dimensions)
                from public.company_index c, b
               where c.index_name ilike '%' || b.m || '%'
               order by c.measured_on desc limit 1),

    -- THE TARGET it is measured against.
    'target', (select jsonb_build_object('goal_key', g.goal_key, 'horizon', g.horizon,
                 'period_label', g.period_label, 'target_value', g.target_value,
                 'actual_value', g.actual_value, 'status', g.status,
                 'gap', g.target_value - g.actual_value, 'updated_at', g.updated_at)
                from public.goal_period g, b
               where g.goal_key ilike '%' || b.m || '%'
               order by g.updated_at desc limit 1),

    -- WHO CONTRIBUTED: the decisions that named this metric in the window.
    'contributors', coalesce((select jsonb_agg(jsonb_build_object(
          'actor', l.actor, 'os', public.fn_owning_os(l.actor), 'kind', l.kind,
          'decision', l.decision, 'confidence', l.confidence, 'at', l.created_at)
        order by l.created_at desc)
      from (select l.* from public.decision_log l, b
             where l.created_at > now() - (b.d || ' days')::interval
               and (l.decision ilike '%' || b.m || '%' or l.ctx::text ilike '%' || b.m || '%')
             order by l.created_at desc limit 10) l), '[]'::jsonb),
    'generated_at', now()
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_report_recommendation_approve(p_report_id bigint, p_index integer, p_by text, p_source text DEFAULT 'exec_reports'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_rec jsonb; v_title text; v_id bigint; v_officer text; v_dept text; v_task bigint;
begin
  if p_source = 'exec_reports' then
    select r.recommendations -> p_index, r.officer into v_rec, v_officer
      from public.exec_reports r where r.id = p_report_id;
  else
    select r.kpis -> p_index, 'board' into v_rec, v_officer
      from public.board_reports r where r.id = p_report_id;
  end if;
  if v_rec is null then
    return jsonb_build_object('ok', false, 'error', 'no recommendation at that index');
  end if;
  v_title := coalesce(v_rec ->> 'title', v_rec ->> 'recommendation', left(v_rec::text, 160));

  insert into public.agent_actions(agent, kind, status, risk, title, recommendation,
      target_table, target_id, decided_by, decided_at, detail)
    values (coalesce(v_officer, 'exec'), 'report_recommendation', 'approved',
      coalesce(v_rec ->> 'risk', 'medium'), v_title, v_rec::text,
      p_source, p_report_id::text, p_by, now(),
      jsonb_build_object('report_id', p_report_id, 'index', p_index, 'source', p_source, 'recommendation', v_rec))
    returning id into v_id;

  -- ROUTE IT AS REAL WORK. The department is the accountable officer's; a05_org_task_fill_ownership
  -- gives it an owner and, when the recommendation names a goal, ties it to that objective. Idempotent
  -- on the report+index marker, so approving the same recommendation twice does not double the work.
  v_dept := coalesce((select department from public.org_agents
                        where agent_key = coalesce(public.fn_org_agent_resolve(v_officer), v_officer)), 'exec');
  select id into v_task from public.org_tasks t
   where t.action_class = 'report_recommendation'
     and t.detail like '%report #'||p_report_id||' rec '||p_index||' by %'
     and t.status <> 'done'
   order by id limit 1;
  if v_task is null then
    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    values (v_dept, v_title,
      coalesce(v_rec ->> 'why', v_rec ->> 'recommendation', v_title)
        ||'  [Approved from the '||p_source||' report #'||p_report_id||' rec '||p_index||' by '||p_by
        ||'. Do it, or bring evidence the standard is wrong.]',
      'assigned', 'advisory', false, 'report_recommendation')
    returning id into v_task;
    update public.agent_actions set detail = detail || jsonb_build_object('org_task_id', v_task) where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'action_id', v_id, 'org_task_id', v_task,
                            'title', v_title, 'report_id', p_report_id);
end $function$


CREATE OR REPLACE FUNCTION public.fn_reputation_recompute()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record; n int := 0; v_score numeric; v_tier text;
  v_gated int := 0; v_restored int := 0; v_unmeasured int := 0; v_provisional int := 0;
  v_hold record;
  k_prior constant numeric := 5;    -- weight of the neutral prior, in observations
  k_mid   constant numeric := 50;   -- the prior itself
  k_floor constant numeric := 10;   -- observations needed before a tier other than standard is assigned
  -- per-dimension (hits, n)
  c_hit numeric; c_n numeric;  q_hit numeric; q_n numeric;  l_hit numeric; l_n numeric;
  e_hit numeric; e_n numeric;  b_hit numeric; b_n numeric;  y_hit numeric; y_n numeric;
  v_corr numeric; v_decq numeric; v_learn numeric; v_cost numeric; v_collab numeric; v_rel numeric;
  v_total numeric; v_dims int; v_provisional_row boolean;
  post constant text := 'posterior';
begin
  -- A hold the founder actually holds open still pauses scoring; authority must not move under it.
  select s.id, s.stood_down_at into v_hold
    from public.company_stand_down s where s.resumed_at is null
   order by s.stood_down_at desc limit 1;
  if v_hold.id is not null then
    return jsonb_build_object('ok', false, 'status', 'PAUSED_BY_FOUNDER_STANDDOWN',
      'scored', 0, 'gated', 0, 'restored', 0, 'unmeasured', 0,
      'stand_down_id', v_hold.id, 'since', v_hold.stood_down_at,
      'note', 'No employee is scored, promoted or demoted while a stand-down is open.');
  end if;

  for r in select a.agent_key from public.org_agents a order by a.agent_key loop
    -- correctness: graded outcomes of its actions + review verdicts on work it authored
    select count(*) filter (where verdict = 'improved'),
           count(*) filter (where verdict in ('improved','no_change','worse'))
      into c_hit, c_n from public.outcome_record where actor = r.agent_key;
    select c_hit + count(*) filter (where decision = 'approve'),
           c_n + count(*)
      into c_hit, c_n from public.review_chain
     where author_agent = r.agent_key and decision in ('approve','reject','request_revision');

    -- decision quality: decisions a human could review (confidence + source + reason)
    select count(*) filter (where l.confidence is not null
                              and l.sources is not null and l.sources::text not in ('null','[]','{}','""')
                              and l.reasons is not null and l.reasons::text not in ('null','[]','{}','""')),
           count(*)
      into q_hit, q_n from public.decision_log l where l.actor = r.agent_key;

    -- learning speed: graded training attempts it passed
    select count(*) filter (where passed), count(*)
      into l_hit, l_n from public.agent_training_attempt
     where agent_key = r.agent_key and passed is not null;

    -- cost efficiency: calls a cheaper model could NOT have served
    select count(*) filter (where not coalesce(could_be_cheaper, false)), count(*)
      into e_hit, e_n from public.ai_cost_log where agent_key = r.agent_key;

    -- collaboration: reviews it gave as reviewer that carry a reason
    select count(*) filter (where nullif(btrim(coalesce(reason,'')), '') is not null), count(*)
      into b_hit, b_n from public.review_chain
     where reviewer_agent = r.agent_key and decision in ('approve','reject','request_revision','hold');

    -- reliability: assigned tasks that reached done (escalated counts against; cancelled excluded)
    -- + runs under its own key that did not error
    select count(*) filter (where status = 'done'), count(*)
      into y_hit, y_n from public.org_tasks
     where assigned_agent = r.agent_key and status in ('done','escalated');
    select y_hit + count(*) filter (where status <> 'error'), y_n + count(*)
      into y_hit, y_n from public.agent_runs where agent = r.agent_key;

    v_corr  := round((k_mid*k_prior + 100.0*c_hit) / (k_prior + c_n), 1);
    v_decq  := round((k_mid*k_prior + 100.0*q_hit) / (k_prior + q_n), 1);
    v_learn := round((k_mid*k_prior + 100.0*l_hit) / (k_prior + l_n), 1);
    v_cost  := round((k_mid*k_prior + 100.0*e_hit) / (k_prior + e_n), 1);
    v_collab:= round((k_mid*k_prior + 100.0*b_hit) / (k_prior + b_n), 1);
    v_rel   := round((k_mid*k_prior + 100.0*y_hit) / (k_prior + y_n), 1);
    v_total := c_n + q_n + l_n + e_n + b_n + y_n;
    v_dims  := (c_n > 0)::int + (q_n > 0)::int + (l_n > 0)::int + (e_n > 0)::int + (b_n > 0)::int + (y_n > 0)::int;
    v_provisional_row := false;

    if v_total = 0 then
      v_score := null; v_tier := 'unmeasured'; v_unmeasured := v_unmeasured + 1;
    else
      v_score := round(v_corr*0.30 + v_rel*0.30 + v_cost*0.15 + v_learn*0.15 + v_collab*0.10, 1);
      if v_total < k_floor or v_dims < 2 then
        v_tier := 'standard'; v_provisional_row := true; v_provisional := v_provisional + 1;
      else
        v_tier := case when v_score >= 85 then 'senior_trusted'
                       when v_score >= 70 then 'trusted'
                       when v_score >= 50 then 'standard' else 'probation' end;
      end if;
    end if;

    insert into public.agent_reputation
      (agent_key, correctness, reliability, cost_efficiency, learning_speed, collaboration,
       decision_quality, score, tier, computed_at, evidence)
    values (r.agent_key, v_corr, v_rel, v_cost, v_learn, v_collab, v_decq, v_score, v_tier, now(),
            jsonb_build_object('method', post, 'prior', k_mid, 'prior_weight', k_prior,
              'tier_floor', k_floor, 'provisional', v_provisional_row, 'dimensions_with_evidence', v_dims,
              'correctness', c_n, 'decision_quality', q_n, 'learning_speed', l_n,
              'cost_efficiency', e_n, 'collaboration', b_n, 'reliability', y_n, 'total', v_total))
    on conflict (agent_key) do update set
      correctness = excluded.correctness, reliability = excluded.reliability,
      cost_efficiency = excluded.cost_efficiency, learning_speed = excluded.learning_speed,
      collaboration = excluded.collaboration, decision_quality = excluded.decision_quality,
      score = excluded.score, tier = excluded.tier, computed_at = now(), evidence = excluded.evidence;
    n := n + 1;
  end loop;

  -- probation is a real consequence: any agent below the floor loses autonomous authority.
  with demoted as (
    update public.employee_authority a set max_tier = 'gated'
      from public.agent_reputation p
     where p.agent_key = a.agent_key and p.tier = 'probation' and a.max_tier = 'autonomous'
    returning a.agent_key, a.action_class)
  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:' || agent_key || '/' || action_class, 'reputation_demote', 'tighten',
         'autonomous', 'gated', 'reputation tier fell to probation'
    from demoted;
  get diagnostics v_gated = row_count;

  -- ...and recovery is a real consequence too: a grant this routine demoted comes back when the
  -- tier is no longer probation, and an advisory-safe grant comes back on any earned tier.
  with restored as (
    update public.employee_authority a set max_tier = 'autonomous'
      from public.agent_reputation p
     where p.agent_key = a.agent_key
       and a.max_tier = 'gated'
       and p.tier in ('standard','trusted','senior_trusted')
       and (a.note = 'Advisory-safe action, may run autonomously'
            or exists (select 1 from public.autonomy_control_audit u
                        where u.op = 'reputation_demote'
                          and u.object = 'employee_authority:' || a.agent_key || '/' || a.action_class
                          and not exists (select 1 from public.autonomy_control_audit v
                                           where v.op = 'reputation_restore' and v.object = u.object and v.at > u.at)))
    returning a.agent_key, a.action_class)
  insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:' || agent_key || '/' || action_class, 'reputation_restore', 'loosen',
         'gated', 'autonomous',
         'reputation tier is no longer probation (a tier below standard needs 10 observations on two dimensions); a demotion this routine made is lifted'
    from restored;
  get diagnostics v_restored = row_count;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('reputation', now(), now(), 'ok',
    jsonb_build_object('scored', n, 'gated', v_gated, 'restored', v_restored, 'unmeasured', v_unmeasured, 'provisional', v_provisional),
    'Reputation recomputed for ' || n || ' employee(s) on six dimensions from recorded facts '
    || '(posterior mean, prior 50 with weight 5; evidence counts stored per dimension). '
    || v_unmeasured || ' have no evidence on any dimension and carry a NULL score; ' || v_provisional
    || ' are provisional standard with fewer than 10 observations or evidence on one dimension only. '
    || 'Probation demoted ' || v_gated || ' autonomous grant(s) to gated; recovery restored ' || v_restored || '.');
  return jsonb_build_object('ok', true, 'scored', n, 'gated', v_gated, 'restored', v_restored,
                            'unmeasured', v_unmeasured, 'provisional', v_provisional);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_resilience_orphan_steps_due()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    -- coalesce, not '<>': a missing row must read as "not enabled", which is the state that needs
    -- reporting. A gate that opens only when a key is present and wrong is a gate that a deleted key
    -- switches off silently.
    'email_cron',   coalesce((select value from public.app_secrets where key = 'email_enabled'), '') is distinct from 'true',

    -- THE FLAG ARM, unchanged: an estate that has never had an approved set polls until it does.
    -- THE WORK ARM, added 22 Sep 2026: something is still pending and nobody has asked about it
    -- today. 'received' is Twilio's word for submitted-and-undecided; anything that is neither
    -- approved nor rejected is undecided, so the condition is written as the absence of a verdict
    -- rather than as a list of the words Twilio currently uses for waiting.
    -- THE RE-CHECK ARM, added 29 Sep 2026: the same 20 hours now applies to APPROVED rows too, so the
    -- predicate is "not rejected" rather than "neither approved nor rejected". Meta can pause or
    -- reject a template after approving it, and only asking again notices.
    'wa_templates', coalesce((select value from public.app_secrets where key = 'wa_templates_ready'), '') is distinct from 'true'
      or exists (
        select 1 from public.messaging_template
         where channel = 'whatsapp'
           and status <> 'rejected'
           and (last_checked_at is null or last_checked_at < now() - interval '20 hours')),

    -- The queue is the gate. No flag, because nothing here costs a model call and a queued SMS has a
    -- person at the end of it.
    'send_sms', exists (
      select 1 from public.notifications where channel = 'sms' and status = 'queued'),

    -- Both halves must hold: the switch is on AND there is work. Either alone would be a step that runs
    -- for nothing 96 times a day.
    'doc_extract', coalesce((select value from public.app_secrets where key = 'doc_extract_drain_enabled'), '') = 'true'
      and exists (
        select 1 from public.documents
         where status in ('pending', 'error') and coalesce(attempts, 0) < 3),

    'email_triage', coalesce((select value from public.app_secrets where key = 'email_triage_enabled'), '') = 'true'
      and exists (
        select 1 from public.inbound_messages
         where needs_review and triaged_at is null and replied_at is null),

    -- WEEKLY, MEASURED OFF THE WORK ITSELF rather than a schedule string, AND PER SOURCE. Due while
    -- EITHER list lacks a recent enough attempt: an `ok` run holds that source for 6 days (the founder
    -- asked for a weekly check, and 6 not 7 so a slow week never skips one), a failed or unparseable one
    -- for 6 hours — a transient UN or UAE outage is retried a few times a day, never every 15 minutes.
    --
    -- PER SOURCE IS NOT A DETAIL (found in independent review before this was applied). Written as one
    -- ungrouped NOT EXISTS over the whole table, a healthy UN fetch would hold the gate shut for six days
    -- and the UAE list — failing every time — would be retried once a week instead of every six hours,
    -- with the documented back-off silently never applying to the source that actually needed it. That is
    -- the estate's "guarded by a condition that cannot occur" shape: the failure branch exists and can
    -- never be reached. The cost of the correct version is that a broken source re-opens the gate every
    -- 6 hours and the healthy list is downloaded again with it, ~4 times a day instead of once a week.
    -- That is the right way round: bandwidth is cheap and an unscreened sanctions source is not.
    --
    -- Every attempt writes a screening_run row whatever happened, which is what makes this a measurement
    -- and not a hope; a zero-run history reads as due, which is correct, because it has never run.
    'sanctions', coalesce((select value from public.app_secrets where key = 'sanctions_screen_enabled'), '') = 'true'
      and exists (
        select 1 from (values ('un_consolidated'), ('uae_local_terrorist_list')) as s(source)
         where not exists (
           select 1 from public.screening_run r
            where r.source = s.source
              and r.fetched_at > now() - case when r.status = 'ok' then interval '6 days' else interval '6 hours' end))
  )
$function$


CREATE OR REPLACE FUNCTION public.fn_resilience_step_board()
 RETURNS TABLE(step text, every interval, overdue_ratio numeric, last_started_at timestamp with time zone, last_ok_at timestamp with time zone, ewma_ms integer, deferrals integer, deferred_since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select s.step, s.every,
         round((extract(epoch from (now() - coalesce(s.last_started_at, now() - s.every - interval '365 days')))
                / greatest(extract(epoch from s.every), 1))::numeric, 2),
         s.last_started_at, s.last_ok_at, s.ewma_ms, s.deferrals, s.deferred_since
    from public.resilience_step s
   order by 3 desc, s.step;
$function$


CREATE OR REPLACE FUNCTION public.fn_resilience_step_record(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_seen integer := 0;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'p_rows must be a jsonb array');
  end if;

  -- EVERY FIELD IS READ DEFENSIVELY, AND THE ARRAY IS DE-DUPLICATED (independent review,
  -- ecc:database-reviewer, 18 Sep 2026). Two findings, both about one bad element taking the whole call
  -- down or silently winning:
  --   * a malformed `ms` or `ok` ("12.5", 2) would raise a cast error, and because this is ONE
  --     `update … from` that aborts the whole batch — so no step gets its attempt stamped, every
  --     staleness ratio keeps rising, and the next plan is computed from a lie. A bad field now degrades
  --     to its default instead of taking the tick's whole record with it.
  --   * `update … from` with the same step twice picks an arbitrary source row, with no error and a
  --     row_count that still looks complete. `distinct on` makes the winner a decision: a step that RAN
  --     beats the same step reported deferred, because a stamped attempt is the truthful one.
  with parsed as (
    select e->>'step'                                                           as step,
           coalesce(e->>'deferred' = 'true', false)                             as deferred,
           coalesce(e->>'ok' = 'true', false)                                   as ok,
           case when e->>'ms' ~ '^[0-9]{1,9}$' then (e->>'ms')::integer end      as ms
      from jsonb_array_elements(p_rows) e
     where jsonb_typeof(e) = 'object' and e->>'step' is not null
  ), rows as (
    select distinct on (step) * from parsed order by step, deferred asc, ok desc, ms desc nulls last
  )
  update public.resilience_step s
     set last_started_at = case when r.deferred then s.last_started_at else now() end,
         last_ok_at      = case when not r.deferred and r.ok then now() else s.last_ok_at end,
         last_ms         = case when r.deferred then s.last_ms else coalesce(r.ms, s.last_ms) end,
         -- 0.7 old + 0.3 new: a single slow pass moves the estimate without owning it.
         ewma_ms         = case
                             when r.deferred or r.ms is null then s.ewma_ms
                             when s.ewma_ms is null then r.ms
                             else round(0.7 * s.ewma_ms + 0.3 * r.ms)::integer
                           end,
         deferrals       = case when r.deferred then s.deferrals + 1 else 0 end,
         deferred_since  = case when r.deferred then coalesce(s.deferred_since, now()) else null end
    from rows r
   where r.step = s.step;
  get diagnostics v_seen = row_count;

  return jsonb_build_object('ok', true, 'updated', v_seen);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_resilience_tick_plan(p_budget_ms integer DEFAULT 70000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with due as (
    select step, coalesce(ewma_ms, budget_ms) as cost, deferrals,
           extract(epoch from (now() - coalesce(last_started_at, now() - every - interval '365 days')))
             / greatest(extract(epoch from every), 1) as ratio
      from public.resilience_step
     where place = 'plan'
       -- A TICK IS NEVER EXACTLY ON THE BEAT, SO THE DUE TEST HAS TWO MINUTES OF TOLERANCE
       -- (22 Sep 2026, it_engineer, SEATS-04). `now() - last_started_at >= every` asks for the full
       -- interval to have elapsed at the moment the tick looks. Ticks jitter by seconds, so a 30-minute
       -- step whose last attempt was 29 min 58 s ago is not due on this tick and waits for the next one:
       -- its real cadence becomes one tick longer, and measured across the estate the scheduled steps
       -- were running about 1.5x their declared interval.
       -- SAID PRECISELY, because the loose version of this sentence was wrong: the effective floor is
       -- `every - 2 min`, so a 15-minute step can now run as often as every 13 minutes and TWICE inside
       -- some 15-minute windows. That is the intended trade — two runs 13 minutes apart cost one extra
       -- pass of a step that already gates itself, where a missed beat costs a whole interval — and it is
       -- not a lock: nothing here reserves a step. `last_started_at` is stamped by
       -- fn_resilience_step_record when the tick REPORTS, i.e. at the end, so two ticks overlapping in
       -- time can both plan the same step. That was already true before this change; the tolerance does
       -- not create it and does not fix it. Each step's own `fn_*_due` gate and claim-style queries are
       -- what make a double run harmless.
       and (last_started_at is null or now() - last_started_at >= every - interval '2 minutes')
  ), ranked as (
    select *, row_number() over (order by ratio desc, step) as rn from due
  ), filled as (
    -- ponytail: prefix cut, not a knapsack. A large step near the front can leave budget unused; the
    -- staleness order still admits it next tick, so the cost is a beat, never a starved step. Swap in a
    -- fitting pass only if the measured deferral rate says the waste matters.
    select *, sum(cost) over (order by rn rows between unbounded preceding and current row) as cum
      from ranked
  ), decided as (
    select *, (rn = 1 or cum <= p_budget_ms) as admitted from filled
  )
  select jsonb_build_object(
    'budget_ms',  p_budget_ms,
    'planned_ms', coalesce((select sum(cost) from decided where admitted), 0),
    'run',        coalesce((select jsonb_agg(step order by rn) from decided where admitted), '[]'::jsonb)
                  || coalesce((select jsonb_agg(step order by rank, step) from public.resilience_step where place = 'last'), '[]'::jsonb),
    'deferred',   coalesce((select jsonb_agg(step order by rn) from decided where not admitted), '[]'::jsonb),
    -- A step that has been passed over four ticks running (an hour) is no longer "a beat late". It is
    -- returned so the tick raises it as an IT engineer finding, which is the alarm on the guarantee
    -- above: if the bound is ever not holding, this says so instead of the silence that cost the
    -- sanctions screen its run.
    'starved',    coalesce((select jsonb_agg(step order by deferrals desc, step)
                              from decided where not admitted and deferrals >= 4), '[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_resolve_cat_agent(cat text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k text; c text := lower(trim(coalesce(cat,'')));
begin
  if c = '' then return null; end if;

  -- Hop 1 and 2, unchanged: the caller already holds a catalogue slug.
  if exists(select 1 from category_agents where slug=c and coalesce(active,true)) then return 'cat:'||c; end if;
  if exists(select 1 from agent_knowledge where agent_key='cat:'||c limit 1) then return 'cat:'||c; end if;

  -- Hop 3, NEW: the declared trade -> catalogue bridge, the same one fn_category_knowledge walks.
  -- Before the name LIKE, because a mapping somebody decided beats a substring that happens to hit.
  select 'cat:'||m.catalog_slug into k
    from lead_trade_map m
   where m.trade_key = c
     and exists (select 1 from agent_knowledge a where a.agent_key = 'cat:'||m.catalog_slug)
   limit 1;
  if k is not null then return k; end if;

  -- Hop 4: the catalogue's own display name, EXACTLY (23 Sep 2026, founder_instruction 886-903). This was
  -- a substring match both ways (name contains the category, or the category contains a slug), which
  -- decided the desk by which letters happened to overlap: 'tile' found 'textile', 'ac' found every name
  -- with those two letters. A category nothing declares resolves to NO desk (null); every caller already
  -- reads null as unmatched (fn_decide 'unmatched', trg_ingest_case_lessons '_global'). Nothing is guessed.
  select 'cat:'||slug into k from category_agents
    where coalesce(active,true) and lower(btrim(name)) = c
    order by slug limit 1;
  return k;
end $function$


CREATE OR REPLACE FUNCTION public.fn_reveal_outcome_check_tick(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_days numeric := public.fn_seat_clock_policy('reveal_outcome_check_days', 7);
  v_rating int; d record; v jsonb; v_asked int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g'), '')::int into v_rating
    from public.app_secrets where key = 'rating_request_days_after_reveal';
  v_rating := coalesce(v_rating, 21);

  for d in
    select t.id as tx_id, t.quote_id, t.inquiry_id, t.supplier_id, c.email as cemail, c.locale as clocale,
           c.full_name as cname, public.fn_seat_clock_customer_is_fixture(c) as fixture,
           l.company_name, i.category
      from public.transactions t
      join public.customers c on c.id = t.customer_id
      left join public.leads l on l.id = t.supplier_id
      left join public.inquiries i on i.id = t.inquiry_id
     where t.revealed_at is not null and t.quote_id is not null
       and t.revealed_at <= now() - make_interval(days => v_days::int)
       -- the rating ask owns day 21 onwards; the outcome check never lands on or after it
       and t.revealed_at >  now() - make_interval(days => v_rating)
       -- the same allowlist as fn_support_request_ratings_due: never a refunded or disputed reveal
       and coalesce(t.refund_status, 'none') in ('none', 'window_open', 'declined')
       and coalesce(i.outcome, '') = '' and coalesce(i.status, '') <> 'completed'
       and (p_include_fixtures or not public.fn_seat_clock_customer_is_fixture(c))
       and not public.fn_seat_clock_asked('reveal_outcome_check:' || t.quote_id)
     order by t.revealed_at
  loop
    -- 24 Sep 2026: the sales_engineer asks (it owns reveals); customer_support delivers through its door.
    v := public.fn_seat_clock_deliver('sales_engineer', 'reveal_outcome_check', 'customer', d.cemail, d.fixture, d.clocale,
           'reveal_outcome_check',
           jsonb_build_object('name', d.cname, 'supplier', d.company_name, 'category', d.category),
           'reveal_outcome_check:' || d.quote_id, d.inquiry_id, d.quote_id, d.supplier_id);
    if coalesce((v->>'ok')::boolean, false) then v_asked := v_asked + 1;
    else v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('transaction_id', d.tx_id, 'reason', v->>'reason'));
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'asked', v_asked, 'not_written', v_skipped, 'days_after_reveal', v_days,
                            'rating_ask_day', v_rating);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_revenue_document(p_transaction_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select jsonb_build_object(
       'ok',              v.doc_path is not null,
       'transaction_id',  v.id,
       'quote_id',        v.quote_id,
       'revealed_at',     v.revealed_at,
       'reveal_fee',      v.reveal_fee,
       'payment_ref',     v.payment_ref,
       'invoice_id',      v.stripe_invoice_id,
       'invoice_number',  v.stripe_invoice_number,
       'invoice_status',  v.stripe_invoice_status,
       'invoice_total_fils', v.stripe_invoice_total_fils,
       'invoice_currency',   v.stripe_invoice_currency,
       'invoice_pdf_url',    v.stripe_invoice_pdf_url,
       'invoice_hosted_url', v.stripe_invoice_hosted_url,
       'invoice_agrees_with_fee', v.invoice_agrees_with_fee,
       'bucket',          v.doc_bucket,
       'path',            v.doc_path,
       'name',            v.doc_name,
       'content_type',    v.doc_content_type,
       'kind',            v.doc_kind,
       'note',            v.doc_note,
       'state',           v.document_state,
       'reason',          case
                            when v.doc_path is not null then null
                            when v.stripe_invoice_id is not null
                              then 'Stripe issued invoice ' || coalesce(v.stripe_invoice_number, v.stripe_invoice_id)
                                || ' for this sale, but its PDF has not been fetched into finance-docs yet.'
                            else 'This sale has no Stripe invoice on record. Reveal fees paid before '
                              || 'invoice_creation was enabled on 9 Sep 2026 produced no Invoice '
                              || 'object at all, so there is nothing to fetch for those.'
                          end)
     from public.v_revenue_documents v where v.id = p_transaction_id),
    jsonb_build_object('ok', false, 'transaction_id', p_transaction_id, 'state', 'no_such_transaction',
                       'reason', 'There is no public.transactions row with that id.'));
$function$


CREATE OR REPLACE FUNCTION public.fn_revenue_document_coverage()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'sales',              count(*),
    'fees_taken',         count(*) filter (where fee_was_taken),
    'invoiced',           count(*) filter (where fee_was_taken and stripe_invoice_id is not null),
    'openable',           count(*) filter (where fee_was_taken and is_openable),
    'reference_only',     count(*) filter (where fee_was_taken and document_state = 'reference_only'),
    'unclassified',       count(*) filter (where fee_was_taken and document_state = 'unclassified'),
    'missing',            count(*) filter (where fee_was_taken and document_state = 'missing'),
    'missing_ids',        coalesce(jsonb_agg(id order by revealed_at)
                            filter (where fee_was_taken and document_state = 'missing'), '[]'::jsonb),
    'reference_only_ids', coalesce(jsonb_agg(id order by revealed_at)
                            filter (where fee_was_taken and document_state = 'reference_only'), '[]'::jsonb),
    'total_disagrees_ids', coalesce(jsonb_agg(id order by revealed_at)
                            filter (where fee_was_taken and invoice_agrees_with_fee = 'disagrees'), '[]'::jsonb),
    'by_state',           (select coalesce(jsonb_object_agg(document_state, n), '{}'::jsonb)
                           from (select document_state, count(*) n
                                 from public.v_revenue_documents
                                 where fee_was_taken group by 1) s))
  from public.v_revenue_documents;
$function$


CREATE OR REPLACE FUNCTION public.fn_review_decide(p_kind text, p_ref_id bigint, p_decision text, p_comment text DEFAULT NULL::text, p_by text DEFAULT 'founder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare dec text := lower(coalesce(p_decision,'')); ok boolean := false;
begin
  if dec not in ('approve','changes','reject') then return jsonb_build_object('error','decision must be approve|changes|reject'); end if;

  if p_kind = 'marketing_post' then
    update content_drafts set
      review_status = case dec when 'approve' then 'approved' when 'changes' then 'changes_requested' else 'rejected' end,
      founder_comment = coalesce(p_comment, founder_comment), reviewed_at = now()
    where id = p_ref_id and status='draft';
    ok := found;
    -- On approve, social_stage will publish it live (gated by marketing_golive). On changes, the marketing loop revises it.

  elsif p_kind = 'refund' then
    update transactions set
      refund_status = case dec when 'approve' then 'approved' when 'reject' then 'declined' else 'requested' end,
      refund_note = coalesce(p_comment, refund_note),
      refund_resolved_at = case when dec in ('approve','reject') then now() else refund_resolved_at end
    where id = p_ref_id and refund_status='requested';
    ok := found;

  elsif p_kind = 'boost_budget' then
    update review_queue set
      status = case dec when 'approve' then 'approved' when 'changes' then 'changes_requested' else 'rejected' end,
      founder_comment = coalesce(p_comment, founder_comment), decided_at = now(), decided_by = p_by
    where id = p_ref_id and status='pending';
    ok := found;
  else
    return jsonb_build_object('error','unknown kind '||p_kind);
  end if;

  return jsonb_build_object('ok', ok, 'kind', p_kind, 'ref_id', p_ref_id, 'decision', dec);
end $function$


CREATE OR REPLACE FUNCTION public.fn_review_hold_record(p_task_class text, p_fn text, p_agent_key text, p_counterpart_model text, p_why text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id bigint; v_cp text;
begin
  select coalesce(nullif(string_agg(distinct btrim(x), ',' order by btrim(x)), ''), '(none)') into v_cp
    from unnest(string_to_array(coalesce(p_counterpart_model, ''), ',')) x where btrim(x) <> '';
  insert into public.review_hold (task_class, fn, agent_key, counterpart_model, why)
  values (coalesce(p_task_class, '(unresolved)'), p_fn, p_agent_key, v_cp, left(coalesce(p_why, 'no independent reviewer'), 2000))
  on conflict (task_class, coalesce(fn, ''), counterpart_model) where closed_at is null
  do update set last_held_at = now(), times_held = review_hold.times_held + 1, why = excluded.why
  returning id into v_id;
  return v_id;
end $function$


CREATE OR REPLACE FUNCTION public.fn_review_pending()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'marketing_posts', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','marketing_post','ref_id',c.id,'title',c.title,'channel',c.channel,'body',c.body,'image_url',c.image_url,
        'media_missing', case when c.image_url is null then 'no media designed yet' end,
        'created_at',c.created_at)
        order by c.created_at desc)
      from content_drafts c where c.status='draft' and coalesce(c.review_status,'pending')='pending'), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','refund','ref_id',t.id,'customer_id',t.customer_id,'reason',t.refund_reason,'requested_at',t.refund_requested_at)
        order by t.refund_requested_at desc)
      from transactions t where t.refund_status='requested'), '[]'::jsonb),
    'boost_budgets', coalesce((select jsonb_agg(jsonb_build_object(
        'kind','boost_budget','ref_id',r.id,'title',r.title,'summary',r.summary,'payload',r.payload,'created_at',r.created_at)
        order by r.created_at desc)
      from review_queue r where r.kind='boost_budget' and r.status='pending'), '[]'::jsonb)
  );
$function$


CREATE OR REPLACE FUNCTION public.fn_review_submit(p_subject_type text, p_subject_id text, p_dept_key text, p_author text, p_content text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_crit        jsonb;
  v_rule        jsonb;
  v_violations  jsonb := '[]'::jsonb;
  v_unenforced  jsonb := '[]'::jsonb;
  v_critical    int := 0;
  v_major       int := 0;
  v_pick        jsonb;
  v_head        text;
  v_deleg_from  text;
  v_deleg_basis text;
  v_cos         text := 'brief';
  v_decision    text;
  v_reason      text;
  v_conf        numeric;
  v_first_rule  text;
  v_res         jsonb;
begin
  -- CANONICAL AUTHOR, OR THE LEDGER CANNOT SEE ITS OWN SELF-REVIEWS.
  -- review_chain.author_agent was written with whatever string the caller passed while
  -- reviewer_agent was always resolved. A head authoring under an alias therefore produced a row
  -- whose author and reviewer were the SAME employee under two names - and every self-review
  -- count in this system is "author_agent = reviewer_agent", which such a row passes.
  -- So the reported zero was a property of the spelling, not of the behaviour.
  p_author := coalesce(public.fn_org_agent_resolve(p_author), p_author);

  -- Who is actually able to approve for this department right now, GIVEN WHO WROTE IT.
  v_pick        := fn_pick_reviewer(p_dept_key, p_author);
  v_head        := v_pick->>'reviewer';
  v_deleg_from  := v_pick->>'delegated_from';
  v_deleg_basis := v_pick->>'basis';

  -- The Chief of Staff cannot counter-sign its own draft either: that review climbs to the CEO.
  if p_author = coalesce(public.fn_org_agent_resolve(v_cos), v_cos) then v_cos := 'ceo'; end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, stage, decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, 'drafted', null,
          'Draft submitted for department review', null);

  if v_head is null then
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                              decision, reason, confidence, delegated_from, delegation_basis)
    values (p_subject_type, p_subject_id, p_dept_key, p_author, null, 'dept_review',
            'escalate', 'No available approver in ' || p_dept_key || ': ' || coalesce(v_deleg_basis,''), 1.0,
            v_deleg_from, v_deleg_basis);
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'escalate',
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'reason', coalesce(v_deleg_basis,''));
  end if;

  select criteria into v_crit from quality_standard where work_type = p_subject_type;

  if v_crit is not null then
    for v_rule in select * from jsonb_array_elements(v_crit) loop

      if (v_rule ? 'check_fn') then
        begin
          execute format('select %I($1,$2)', v_rule->>'check_fn')
            into v_res using p_subject_id, p_content;
        exception when others then
          v_res := jsonb_build_object('passed', false, 'detail', 'check ' || (v_rule->>'check_fn') || ' errored: ' || sqlerrm);
        end;
        if not coalesce((v_res->>'passed')::boolean, false) then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity',
            'why', v_rule->>'why', 'detail', v_res->>'detail');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      elsif (v_rule ? 'pattern') and (v_rule ? 'fails_when') then
        if (v_rule->>'fails_when') = 'match' and p_content ~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        elsif (v_rule->>'fails_when') = 'no_match' and p_content !~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      else
        v_unenforced := v_unenforced || jsonb_build_object(
          'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
      end if;

    end loop;
  end if;

  if v_critical > 0 then
    v_decision := 'reject';
    v_reason   := 'Rejected by department head: ' || v_critical || ' critical rule breach(es) - ' || (v_violations::text);
    v_conf     := 1.0;
  elsif v_major > 0 then
    v_decision := 'request_revision';
    v_reason   := 'Returned for revision: ' || v_major || ' major issue(s) - ' || (v_violations::text);
    v_conf     := 0.9;
  elsif jsonb_array_length(v_unenforced) > 0
        and exists (select 1 from jsonb_array_elements(v_unenforced) u where u->>'severity' = 'critical') then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no executable check exists for critical criteria - ' || (v_unenforced::text);
    v_conf     := 1.0;
    v_first_rule := (select u->>'rule' from jsonb_array_elements(v_unenforced) u where u->>'severity'='critical' limit 1);
  elsif v_crit is null then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no quality standard is defined for work type "' || p_subject_type || '"';
    v_conf     := 1.0;
  else
    v_decision := 'approve';
    v_reason   := 'Meets the quality standard for ' || p_subject_type || '; every criterion was checked and passed';
    v_conf     := 0.95;
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, violated_rule, confidence, delegated_from, delegation_basis)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_head, 'dept_review',
          v_decision, v_reason, v_first_rule, v_conf, v_deleg_from,
          case when v_deleg_from is not null then v_deleg_basis else null end);

  if v_decision <> 'approve' then
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', v_decision,
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'unenforceable', v_unenforced,
                              'reviewer', v_head, 'delegated_from', v_deleg_from);
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'cos_review',
          'approve', 'Approved by Chief of Staff: brand-compliant and serves a company goal', 0.9);

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'published',
          'approve', 'Published after full approval chain', 1.0);

  -- 4 Sep 2026: the content.published emit that stood here is retired. It fired on every approved
  -- review of any subject (org_tasks, posts, documents) — 360 events, 1,003 deliveries, 163 tasks
  -- minted and 87 still open for two subscribers who wanted campaign.published. The 'published'
  -- review_chain row above is the log; the real publish path emits campaign.published from
  -- content_drafts.status = 'posted' (fn_emit_campaign_published_from_content).

  return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'published',
                            'stopped_at', 'published', 'violations', v_violations,
                            'unenforceable', v_unenforced,
                            'reviewer', v_head, 'delegated_from', v_deleg_from);
end;
$function$


CREATE OR REPLACE FUNCTION public.fn_rfq_board(p_search text DEFAULT ''::text, p_limit integer DEFAULT 80, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb;
begin
  with base as (
    select i.id, coalesce(nullif(trim(i.category),''),'general') as category,
      coalesce(nullif(trim(i.emirate),''),'—') as emirate,
      left(coalesce(nullif(trim(i.summary),''), i.raw_input, ''),140) as summary,
      i.expected_value as value, nullif(btrim(i.budget),'') as budget, i.urgency, i.status, i.outcome, i.created_at,
      case lower(coalesce(i.pipeline_stage, i.status, ''))
        when 'won' then 'won' when 'revealed' then 'revealed' when 'quoted' then 'quoted' when 'matched' then 'matched'
        else (case when i.outcome='won' then 'won' else 'new' end) end as stage
    from inquiries i
    where coalesce(p_search,'')='' or i.category ilike '%'||p_search||'%' or i.summary ilike '%'||p_search||'%' or i.emirate ilike '%'||p_search||'%'
  ), ranked as (select *, row_number() over (partition by stage order by created_at desc, id desc) rn from base),
  sc as (select stage, count(*) c from base group by stage)
  select jsonb_build_object(
    'total',(select count(*) from base),
    'stages',(select jsonb_agg(jsonb_build_object('key',s.key,'label',s.label,'count',coalesce((select c from sc where sc.stage=s.key),0),
      'cards',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'category',r.category,'emirate',r.emirate,'summary',r.summary,'value',r.value,'budget',r.budget,'urgency',r.urgency,'status',r.status) order by r.rn) from ranked r where r.stage=s.key and r.rn<=12),'[]'::jsonb))
      order by s.ord)
      from (values ('new','New',1),('matched','Matched',2),('quoted','Quoted',3),('revealed','Revealed',4),('won','Won',5)) s(key,label,ord)),
    'rows',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'category',b.category,'emirate',b.emirate,'summary',b.summary,'value',b.value,'budget',b.budget,'urgency',b.urgency,'status',b.status,'stage',b.stage,'created_at',b.created_at) order by b.created_at desc, b.id desc),'[]'::jsonb)
             from (select * from base order by created_at desc, id desc limit greatest(1,least(p_limit,200)) offset greatest(0,p_offset)) b)
  ) into out; return out;
end $function$


CREATE OR REPLACE FUNCTION public.fn_rfq_required_check(i inquiries)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  spec_fields jsonb; f jsonb; bag jsonb := '{}'::jsonb;
  k text; v text; bk text; tok text;
  reqn int := 0; have text[] := '{}';
  miss jsonb := '[]'::jsonb; advisory jsonb := '[]'::jsonb; found boolean;
begin
  select cs.fields into spec_fields
    from public.category_specs cs
   where lower(cs.category) = lower(coalesce(i.category,''))
   limit 1;

  if spec_fields is null or jsonb_typeof(spec_fields) <> 'array' then
    return jsonb_build_object('applicable', false, 'reason', 'no category_specs row',
      'category', i.category, 'required_ok', true, 'required_total', 0,
      'present','[]'::jsonb, 'missing','[]'::jsonb, 'advisory_missing','[]'::jsonb, 'checked_at', now());
  end if;

  if i.spec is not null and jsonb_typeof(i.spec) = 'object' then
    for k, v in
      select e.key, case when jsonb_typeof(e.value) in ('object','array')
                         then e.value::text else coalesce(e.value #>> '{}','') end
        from jsonb_each(i.spec) e
    loop
      bag := bag || jsonb_build_object(lower(k), v);
    end loop;

    for k, v in
      select e2.key, case when jsonb_typeof(e2.value) in ('object','array')
                          then e2.value::text else coalesce(e2.value #>> '{}','') end
        from jsonb_each(i.spec) e1
        join lateral jsonb_each(case when jsonb_typeof(e1.value)='object'
                                     then e1.value else '{}'::jsonb end) e2 on true
    loop
      if not public._rfq_answered(bag->>lower(k)) then
        bag := bag || jsonb_build_object(lower(k), v);
      end if;
    end loop;
  end if;

  bag := bag
    || case when coalesce(i.emirate,'') <> '' then
            jsonb_build_object('emirate', i.emirate,
              'location', coalesce(nullif(bag->>'location',''), i.emirate)) else '{}'::jsonb end
    || case when coalesce(i.scope_type,'') <> '' then
            jsonb_build_object('scope', coalesce(nullif(bag->>'scope',''), i.scope_type)) else '{}'::jsonb end
    || case when coalesce(i.budget,'') <> '' then jsonb_build_object('budget', i.budget) else '{}'::jsonb end
    || case when coalesce(array_length(i.trades,1),0) > 0 then
            jsonb_build_object('trades', array_to_string(i.trades,', ')) else '{}'::jsonb end
    || case when coalesce(i.drawing_file_path,'') <> '' or i.boq is not null then
            jsonb_build_object('drawing','provided') else '{}'::jsonb end;

  for f in select value from jsonb_array_elements(spec_fields)
            where coalesce((value->>'required')::boolean, false)
  loop
    k := nullif(btrim(lower(coalesce(f->>'key',''))), '');

    -- Keyless required field: unaddressable, so ADVISORY ONLY (never blocks dispatch).
    if k is null then
      advisory := advisory || jsonb_build_object(
        'question', f->>'question', 'reason', 'category_specs field has no key - cannot be gated');
      continue;
    end if;

    reqn := reqn + 1; found := false;

    if public._rfq_answered(bag->>k) then found := true; end if;

    -- A KEY of ours that names the same field under another spelling (the concept map, or the key's own
    -- parts): our schema against our schema, a format reconciliation — not a reading of the customer's words.
    if not found then
      for bk in select key from jsonb_each_text(bag) loop
        if public._rfq_answered(bag->>bk) then
          if public._rfq_concept(k) is not null
             and public._rfq_concept(k) = public._rfq_concept(bk) then
            found := true;
          else
            foreach tok in array coalesce(string_to_array(k,'_'), '{}'::text[]) loop
              if length(coalesce(tok,'')) >= 4
                 and (bk = tok or bk like '%'||tok||'%' or tok like '%'||bk||'%') then
                found := true;
              end if;
            end loop;
          end if;
        end if;
        exit when found;
      end loop;
    end if;

    -- NO free-text scan. Whether the customer's own words state this field is reasoned in inquiry_intake
    -- (think(), surface 'inquiry_intake.exact_spec') and arrives here as a keyed answer, or not at all.

    if found then
      have := array_append(have, k);
    else
      miss := miss || jsonb_build_object('key', k, 'question', f->>'question', 'type', f->>'type');
    end if;
  end loop;

  return jsonb_build_object(
    'applicable', true, 'category', i.category,
    'required_total', reqn,
    'required_ok', (jsonb_array_length(miss) = 0),
    'present', to_jsonb(have),
    'missing', miss,
    'advisory_missing', advisory,
    'checked_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_rfq_score(i inquiries)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare pts int:=0; miss text[]:='{}'; have text[]:='{}'; spectxt text;
        catchk jsonb; catmiss text[]:='{}'; m jsonb; gready boolean; catok boolean;
begin
  spectxt := coalesce(i.spec::text,'');
  if coalesce(i.category,'')<>'' then pts:=pts+20; have:=array_append(have,'category'); else miss:=array_append(miss,'category'); end if;
  if coalesce(i.emirate,'')<>'' then pts:=pts+10; have:=array_append(have,'emirate'); else miss:=array_append(miss,'emirate'); end if;
  if length(regexp_replace(spectxt,'[^a-zA-Z0-9]','','g')) > 20 then pts:=pts+25; have:=array_append(have,'scope_detail'); else miss:=array_append(miss,'scope_detail'); end if;
  if coalesce(i.scope_type,'')<>'' then pts:=pts+15; have:=array_append(have,'scope_type'); else miss:=array_append(miss,'scope_type'); end if;
  if i.budget is not null then pts:=pts+15; have:=array_append(have,'budget'); else miss:=array_append(miss,'budget'); end if;
  if coalesce(array_length(i.trades,1),0)>0 or coalesce(i.drawing_file_path,'')<>'' or i.boq is not null then
     pts:=pts+15; have:=array_append(have,'supporting_detail'); else miss:=array_append(miss,'supporting_detail'); end if;

  gready := pts >= 70;

  catchk := public.fn_rfq_required_check(i);
  catok  := coalesce((catchk->>'required_ok')::boolean, true);

  if coalesce((catchk->>'applicable')::boolean,false) then
    for m in select value from jsonb_array_elements(coalesce(catchk->'missing','[]'::jsonb)) loop
      catmiss := array_append(catmiss, coalesce(nullif(m->>'question',''), m->>'key'));
    end loop;
  end if;

  return jsonb_build_object(
    'score', pts,
    'generic_ready', gready,
    'category_required_ok', catok,
    'ready', (gready and catok),
    'have', to_jsonb(have),
    'missing', to_jsonb(miss || catmiss),
    'category_missing', coalesce(catchk->'missing','[]'::jsonb),
    'category_check', catchk,
    'scored_at', now());
end $function$


CREATE OR REPLACE FUNCTION public.fn_rfq_short_of_quotes_tick(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- the top-3 rule: the comparison report is the top 3 (founder rule). A constant, not a setting.
  c_target constant int := 3;
  v_window numeric; v_lead numeric := public.fn_seat_clock_policy('rfq_short_sweep_hours_before_deadline', 8);
  v_fanout int := coalesce(public.fn_seat_clock_policy('match_max_fanout', 5), 5)::int;
  r record; s record; l public.leads; v jsonb; v_codes text[]; v_need text; v_value numeric; v_new int;
  v_swept int := 0; v_invited int := 0; v_reminded int := 0; v_told int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric into v_window
    from public.app_secrets where key = 'sla_quote_hours';
  v_window := coalesce(v_window, 24);

  for r in
    with open_rfq as (
      select i.*, c.email as cemail, coalesce(i.lang, c.locale) as clocale,   -- the customer: the inquiry's own language (founder, 28 Sep 2026)
             c.full_name as cname,
             public.fn_seat_clock_customer_is_fixture(c) as fixture,
             (select min(m.sent_at) from public.inquiry_matches m where m.inquiry_id = i.id) as first_sent,
             (select count(*) from public.quotes q where q.inquiry_id = i.id
                and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
                and q.stale_at is null)::int as live_quotes
        from public.inquiries i
        join public.customers c on c.id = i.customer_id
       where i.status in ('sent', 'quoted')
    )
    select o.*, o.first_sent + make_interval(secs => (v_window * 3600)::double precision) as deadline
      from open_rfq o
     where o.first_sent is not null
       and o.live_quotes < c_target
       and now() >= o.first_sent + make_interval(secs => ((v_window - v_lead) * 3600)::double precision)
       and now() <  o.first_sent + interval '14 days'
       and (p_include_fixtures or not o.fixture)
     order by o.first_sent
  loop
    v_swept := v_swept + 1;

    -- (a) widen ONCE, from the same matcher, same-kind suppliers only.
    if not coalesce(r.routing ? 'short_sweep', false) then
      v_new := 0;
      v_codes := public.fn_taxonomy_trades_for(case when coalesce(cardinality(r.trades), 0) > 0 then r.trades
                                                    else array[coalesce(r.category, '')] end);
      if coalesce(cardinality(v_codes), 0) > 0 then
        -- KEYED, NOT READ: scope_type is customer_api's own set (single | multi | turnkey) and role_needed is
        -- one of fn_match_capability's needs when the request carried one.
        v_need := case when r.scope_type = 'turnkey' then 'whole_scope'
                       when r.role_needed in ('whole_scope', 'supplies', 'executes') then r.role_needed
                       else 'executes' end;
        v_value := coalesce(r.expected_value, nullif(regexp_replace(coalesce(r.budget, ''), '[^0-9.]', '', 'g'), '')::numeric);
        if v_value is not null and v_value <= 0 then v_value := null; end if;
        for s in select m.supplier_id, m.score, m.why
                   from public.fn_match_capability(v_codes, v_need, '{}'::text[], '{}'::text[], r.scope_type, v_value, r.emirate, 60) m
                   join public.leads ld on ld.id = m.supplier_id
                  where not exists (select 1 from public.inquiry_matches x where x.inquiry_id = r.id and x.supplier_id = m.supplier_id)
                    and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture
                  order by m.score desc
                  limit v_fanout loop
          insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
          values (r.id, s.supplier_id, least(1, greatest(0, round(s.score / 100, 3))),
                  left('short-of-quotes sweep (fn_rfq_short_of_quotes_tick): ' || coalesce(s.why, ''), 400))
          on conflict (inquiry_id, supplier_id) do nothing;
          if found then
            v_new := v_new + 1;
            select * into l from public.leads where id = s.supplier_id;
            v := public.fn_seat_clock_deliver('sales_engineer', 'supplier_rfq_widened_invite', 'supplier',
                   lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, 'en', 'rfq_invite',   -- suppliers are always written in English (founder, 28 Sep 2026)
                  
                   jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate),
                   'rfq_invite:' || r.id || ':' || l.id, r.id, null, l.id);
          end if;
        end loop;
      end if;
      update public.inquiries
         set routing = coalesce(routing, '{}'::jsonb) || jsonb_build_object('short_sweep', jsonb_build_object(
               'at', now(), 'quotes_then', r.live_quotes, 'invited', v_new, 'trades', to_jsonb(v_codes),
               'by', 'sales_engineer (fn_rfq_short_of_quotes_tick)'))
       where id = r.id;
      v_invited := v_invited + v_new;
    end if;

    -- (b) remind each invited supplier who has not quoted, once. Not one invited in the last 2 hours.
    for l in select ld.* from public.inquiry_matches m join public.leads ld on ld.id = m.supplier_id
              where m.inquiry_id = r.id and m.sent_at < now() - interval '2 hours'
                and not exists (select 1 from public.quotes q where q.inquiry_id = r.id and q.supplier_id = m.supplier_id)
                and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture loop
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_quote_reminder', 'supplier',
             lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, 'en', 'rfq_quote_reminder',   -- suppliers are always written in English (founder, 28 Sep 2026)
             
             jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate, 'deadline', r.deadline),
             'rfq_quote_reminder:' || r.id || ':' || l.id, r.id, null, l.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_reminded := v_reminded + 1; end if;
    end loop;

    -- (c) at the deadline, tell the customer once.
    if now() >= r.deadline then
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_short_of_quotes', 'customer', r.cemail, r.fixture, r.clocale,
             'rfq_short_of_quotes',
             jsonb_build_object('name', r.cname, 'category', r.category, 'emirate', r.emirate, 'quotes', r.live_quotes),
             'rfq_short_of_quotes:' || r.id, r.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_told := v_told + 1;
      elsif not coalesce((v->>'ok')::boolean, false) then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'reason', v->>'reason'));
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'swept', v_swept, 'invited', v_invited, 'reminded', v_reminded,
                            'customers_told', v_told, 'not_written', v_skipped,
                            'deadline_hours', v_window, 'sweep_from_hours_before', v_lead);
end
$function$


CREATE OR REPLACE FUNCTION public.fn_role_identity_isolation_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_other text;
begin
  select string_agg(o.packaged_role_id || ' (' || o.archetype || ')', ', '
                    order by o.packaged_role_id)
    into v_other
    from public.org_role_identity o
   where o.agent_key = new.agent_key
     and o.packaged_department = new.packaged_department
     and o.packaged_role_id <> new.packaged_role_id
     and ( (    new.archetype = 'reviewer-auditor'
            and o.archetype in ('director','operations-specialist','analyst-controller'))
        or (    o.archetype = 'reviewer-auditor'
            and new.archetype in ('director','operations-specialist','analyst-controller')) );

  if v_other is null then
    return new;
  end if;

  -- The conflict may exist, but only as a decision somebody signed for — and signed for THIS
  -- archetype.  Matching on (agent_key, packaged_role_id) alone was tried and probed: it let
  -- payments-and-revenue-operations-analyst-controller be redefined to reviewer-auditor on the
  -- strength of a decision that had been recorded about the analyst-controller identity.  A
  -- decision about one identity is not consent for a different one.
  if exists (select 1 from public.role_isolation_decision d
              where d.agent_key = new.agent_key
                and d.packaged_role_id = new.packaged_role_id
                and d.archetype = new.archetype) then
    return new;
  end if;

  raise exception
    'agent % would be both producer and independent reviewer of % (this row: % as %; also holds: %)',
    new.agent_key, new.packaged_department, new.packaged_role_id, new.archetype, v_other
    using errcode = '23514',
          hint = 'record the call in role_isolation_decision first: '
                 'isolate | split | restrict_to_advisory | block';
end $function$


CREATE OR REPLACE FUNCTION public.fn_role_of(p_email text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  e text := lower(trim(coalesce(p_email,'')));
  v_role text;
  v_from date;
  v_on boolean;
begin
  if e = '' then return 'guest'; end if;

  -- Human identities first: unchanged behaviour, still wins over everything.
  select ur.role into v_role from user_roles ur
   where ur.email = e
   order by array_position(array['owner','admin','ops','finance','support','agent'], ur.role)
   limit 1;
  if v_role is not null then return v_role; end if;

  if e = any (string_to_array(lower(coalesce((select value from app_secrets where key='admin_emails'),'')), ','))
    then return 'owner'; end if;

  -- AGENT IDENTITY. Only for values that are not email addresses, so a real
  -- person can never be mistaken for an employee record.
  if position('@' in e) = 0 then
    if exists (select 1 from org_agents where lower(agent_key) = e and active) then
      v_on := lower(coalesce((select value from app_secrets where key='agent_autonomy_enabled'),'true')) = 'true';
      begin
        v_from := coalesce((select value from app_secrets where key='agent_autonomy_from'),'2026-07-30')::date;
      exception when others then v_from := date '2026-07-30';
      end;
      if v_on and current_date >= v_from then
        return 'agent';
      else
        return 'guest';   -- pre-arming: behaviour identical to today
      end if;
    end if;
  end if;

  if exists (select 1 from leads where lower(coalesce(claimed_by,'')) = e) then return 'supplier'; end if;
  if exists (select 1 from customers where lower(coalesce(email,'')) = e) then return 'customer'; end if;
  return 'guest';
end
$function$


CREATE OR REPLACE FUNCTION public.fn_route_party(p_name text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(
    (select a.agent_key from public.org_agents a
      where a.active and a.agent_key = nullif(btrim(coalesce(p_name, '')), '') limit 1),
    (select d.dept_key from public.org_departments d
      where d.dept_key = nullif(btrim(coalesce(p_name, '')), '')
        and exists (select 1 from public.org_agents a2
                     where a2.department = d.dept_key and a2.active) limit 1));
$function$


CREATE OR REPLACE FUNCTION public.fn_routing_tier_model(p_agent_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when a.routing_tier is null then null else jsonb_build_object(
      'routing_tier', a.routing_tier,
      'registry_tier', t.rt,
      'model', (select r.model_id from model_registry r
                 where r.active and r.approved and r.tier = t.rt
                 order by r.in_per_mtok_usd limit 1)) end
    from org_agents a
    cross join lateral (select case a.routing_tier
                                 when 'reviewer_auditor'      then 'large'
                                 when 'operations_specialist' then 'small'
                                 else 'medium' end as rt) t
   where a.agent_key = coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key)
     and coalesce(a.active, true)
   limit 1;
$function$


CREATE OR REPLACE FUNCTION public.fn_run_seat(p_agent text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce((select fo.owner from public.function_owner fo
                    where fo.function_slug = regexp_replace(coalesce(p_agent, ''), '^fn:', '')),
                  regexp_replace(coalesce(p_agent, ''), '^fn:', ''));
$function$


CREATE OR REPLACE FUNCTION public.fn_runner_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_run bigint; n_alert int := 0; n_watched int := 0; v_email text;
begin
  insert into agent_runs(agent, started_at) values ('runner_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  -- RE-DERIVE, NEVER SEED. One pass over 30 days of runs gives every runner its own observed
  -- cadence. A runner seen fewer than 5 times has no cadence worth calling regular and is recorded
  -- as on-demand rather than alerted on — which is what stops this becoming the noise generator the
  -- 18 July snapshot would have been if anything had ever read it.
  with runs as (
    select agent, started_at, counts,
           started_at - lag(started_at) over (partition by agent order by started_at) gap
      from agent_runs
     where started_at > now() - interval '30 days'
       -- 9 SEP 2026: `fn:<slug>` rows are edge-function REQUESTS, written by _shared/observe.ts.
       -- An HTTP endpoint has no cadence — its gaps measure how often somebody called it, not
       -- whether it is working — so learning one here would page about a quiet weekend.
       and agent not like 'fn:%'),
  agg as (
    select agent,
           count(*) as n,
           -- A CADENCE IS NOT A BURST. Measured on the first run: doc_extract, match, quote_compare,
           -- inquiry_intake and stripe_webhook all showed a "median gap" of 0.00-0.08 hours, because
           -- they are EVENT-DRIVEN and fire in clusters when work arrives. Treating a cluster as a
           -- schedule makes every quiet day an alert. A real cadence shows up on separate DAYS, so
           -- that is what is counted.
           count(distinct started_at::date) as active_days,
           -- A RUNNER LOGGED ONLY ON EXCEPTIONS HAS NO CADENCE EITHER. cos_execute writes an
           -- agent_runs row under its own name ONLY when it has a throttled signal to report (a
           -- refused task start); its ordinary hourly work is logged under 'ceo'. So its
           -- rows stop the moment it stops having a PROBLEM, and the first version of this watch
           -- read that as the runner going silent -- alerting daily on a loop that was working.
           count(*) filter (where coalesce(counts ? 'signal', false)) as signal_rows,
           max(started_at) as last_seen,
           percentile_cont(0.5) within group (order by extract(epoch from gap)/3600.0) as median_gap_h
      from runs group by agent)
  insert into agent_expectations (agent, kind, max_silence_hours, on_demand, median_gap_hours,
                                  runs_observed, last_seen, note, updated_at)
  select a.agent,
         case when exists (select 1 from org_agents o where o.agent_key = a.agent) then 'employee' else 'code' end,
         -- Three times its own median, floored at 6 hours and capped at two weeks. Derived from the
         -- runner rather than from its schedule, because the schedule is what fn_agent_silence_watch
         -- already checks and is exactly what stayed green while the work stopped.
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows
              then least(336, greatest(6, ceil(a.median_gap_h * 3)))
              else 999999 end,
         not (a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows),
         round(a.median_gap_h::numeric, 2),
         a.n,
         a.last_seen,
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows
              then 'cadence learned from '||a.n||' run(s) across '||a.active_days||' day(s) in 30d, median gap '||round(a.median_gap_h::numeric,2)||'h'
              else 'no steady cadence ('||a.n||' run(s) across '||a.active_days||' day(s), median gap '
                   ||coalesce(round(a.median_gap_h::numeric,2)::text,'n/a')||'h) — event-driven or on-demand, not watched' end,
         now()
    from agg a
  on conflict (agent) do update set
    kind = excluded.kind, max_silence_hours = excluded.max_silence_hours,
    on_demand = excluded.on_demand, median_gap_hours = excluded.median_gap_hours,
    runs_observed = excluded.runs_observed, last_seen = excluded.last_seen,
    note = excluded.note, updated_at = now();

  select count(*) into n_watched from agent_expectations where not on_demand;

  -- EVERY row, not just the watched ones. Scoping this to `not on_demand` left a stale silent=true
  -- on any runner that moved INTO on_demand — measured on the first run: five event-driven runners
  -- kept a silent flag they could no longer clear.
  update agent_expectations e
     set silent = (not e.on_demand
                   and e.last_seen is not null
                   and e.last_seen < now() - (e.max_silence_hours || ' hours')::interval);

  -- ONCE PER SILENCE EPISODE, ONE EMAIL PER RUN (3 Sep 2026). This loop paged the founder once per
  -- silent employee per DAY — 21 "Employee has stopped working" emails in the 24 hours measured on
  -- 3 Sep, 59 all-time — for runners whose schedules were switched off by his own 16 Aug stand-down
  -- and re-enabled on 2-3 Sep. A silence is one fact, not a daily one: an episode is (runner,
  -- last_seen); it is paged the first time it is seen and never again until the runner has run
  -- (a new last_seen is a new episode). And the employees newly silent in one pass go into ONE
  -- email, never one email each. Nothing is hidden: every silent runner is still in
  -- agent_expectations.silent and in the company snapshot.
  declare v_new text := ''; v_new_n int := 0;
  begin
  for r in select agent, kind, last_seen, max_silence_hours, median_gap_hours
             from agent_expectations where silent and not on_demand order by agent
  loop
    if not exists (select 1 from founder_alerts
                    where event='runner_silent'
                      and detail like '%"runner": "'||r.agent||'"%'
                      and detail like '%"last_run": "'||coalesce(r.last_seen::text,'')||'"%') then
      insert into founder_alerts(level, event, detail, channel)
      values (case when r.kind='employee' then 'high' else 'warn' end, 'runner_silent',
        jsonb_build_object('runner', r.agent, 'kind', r.kind,
          'last_run', r.last_seen::text,
          'silent_hours', round(extract(epoch from (now()-r.last_seen))/3600),
          'own_median_gap_hours', r.median_gap_hours,
          'expected_within_hours', r.max_silence_hours)::text, 'email');
      if r.kind = 'employee' then
        v_new_n := v_new_n + 1;
        v_new := v_new || '- ' || r.agent || ': last did anything at ' || coalesce(r.last_seen::text,'unknown')
              || ' (own cadence one run every ' || coalesce(r.median_gap_hours::text,'?') || ' hours)' || E'\n';
      end if;
      n_alert := n_alert + 1;
    end if;
  end loop;
  if v_new_n > 0 then
    -- 6 SEP 2026: routed to the COO as one org_task per condition, never emailed
    -- (founder_mail_policy.runner_silence); this watcher's own founder_alerts rows are its ledger.
    perform public.fn_founder_mail_route('runner_silence',
      v_new_n || ' employee(s) have stopped working',
      'These runners went past their own observed cadence for the first time since they last ran:' || E'\n' || v_new ||
      E'\n' || 'Each is reported once per silence; it will be reported again only after it runs and stops again. ' ||
      'A scheduled job may still be succeeding — this watch looks at what the runner DID, not at whether its schedule fired.',
      'high');
  end if;
  end;

  update agent_runs set finished_at=clock_timestamp(), status='ok',
      counts=jsonb_build_object('runners', (select count(*) from agent_expectations),
                                'watched', n_watched, 'silent', (select count(*) from agent_expectations where silent),
                                'alerts', n_alert,
                                'employees', (select count(*) from agent_expectations where kind='employee'))
   where id=v_run;

  return jsonb_build_object('runners',(select count(*) from agent_expectations),
                            'watched',n_watched,'alerts',n_alert);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$


