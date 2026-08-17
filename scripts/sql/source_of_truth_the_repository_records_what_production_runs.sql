-- THE REPOSITORY RECORDS WHAT PRODUCTION RUNS.
--
-- Root cause 1 of the final Phase C acceptance. The parity mechanism was replaced with an explicit
-- apply order (scripts/sql/MANIFEST.txt read by scripts/checks/canonical_routine_manifest.mjs), and
-- the moment the order became honest it surfaced 74 routines whose current record in
-- this repository was missing or stale:
--
--   * some are defined only in supabase/schema/full_schema.sql, which is an attestation of the
--     deployed shape and not a change in the apply order, so nothing recorded HOW they got there;
--   * some have their newest change file in supabase/migrations_history and were changed again on
--     production afterwards by a path that never wrote a scripts/sql record.
--
-- Every body below was read back from production htdblwldjkcgjvmqkbeh with pg_get_functiondef on
-- 17 Aug 2026 and is committed verbatim. NOTHING HERE CHANGES PRODUCTION: applying this file is a
-- no-op against the state it was generated from. It exists so that "the newest file that defines a
-- routine matches what is live" is a true statement about every application routine rather than
-- about most of them, and so a later session editing an old migration cannot silently revert one.
--
-- These are records, not decisions. The reasoning behind each routine lives in whichever file
-- introduced it; this file only asserts the current text.

CREATE OR REPLACE FUNCTION public.canary_scan(haystack text)
 RETURNS TABLE(kind text, label text, fingerprint text, matched text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select c.kind, c.label, c.fingerprint,
    case
      when position(lower(c.fingerprint) in lower(haystack))>0 then 'fingerprint'
      when position(lower(c.label) in lower(haystack))>0 then 'company name'
      when c.honeytoken_email is not null and position(lower(c.honeytoken_email) in lower(haystack))>0 then 'honeytoken email'
    end as matched
  from canary_records c
  where position(lower(c.fingerprint) in lower(haystack))>0
     or position(lower(c.label) in lower(haystack))>0
     or (c.honeytoken_email is not null and position(lower(c.honeytoken_email) in lower(haystack))>0);
$function$;

CREATE OR REPLACE FUNCTION public.fn_autonomy_audit_run()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a jsonb; stalled int;
begin
  a := fn_autonomy_audit();
  stalled := coalesce((a->'summary'->>'stalled')::int, 0);
  insert into org_memory(scope,kind,content,source)
    values ('exec','audit','Autonomy self-audit: '||(a->'summary')::text||' — '||stalled||' department loop(s) stalled.', 'autonomy_audit');
  if stalled > 0 then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail)
    values ('brief','autonomy_stall','pending','medium',
      stalled||' department loop(s) have stalled',
      'One or more departments have not planned in 4+ days and have no open or recent work. Check fn_autonomy_audit().',
      a);
  end if;
  return a;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_autonomy_dispose()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare r record; n_appr int:=0; n_ack int:=0; n_queue int:=0; c text;
begin
  for r in select * from public.agent_actions
           where status in ('pending','held_for_review','proposed','open','needs_review')
  loop
    c := public.fn_autonomy_class(r.kind, r.target_table, r.recommendation);
    if c='clean_supplier' and r.target_id ~ '^\d+$' then
      update public.leads set approval_status='approved', approved_at=now(),
             approval_decided_by='chief_of_staff (auto)', lifecycle_stage='active'
       where id=r.target_id::bigint and approval_status='pending' and coalesce(banned,false)=false;
      update public.agent_actions set status='approved', decided_by='chief_of_staff (auto)', decided_at=now() where id=r.id;
      n_appr := n_appr+1;
    elsif c='ack' then
      update public.agent_actions set status='auto_done', decided_by='chief_of_staff (auto)', decided_at=now() where id=r.id;
      n_ack := n_ack+1;
    else  -- 'founder' or 'keep' → remains visible in the queue
      n_queue := n_queue+1;
    end if;
  end loop;
  return jsonb_build_object('approved_suppliers',n_appr,'auto_cleared_logged',n_ack,'in_your_queue',n_queue);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_cancel_inquiry(p_inquiry uuid, p_customer uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v inquiries%rowtype; v_paid boolean; v_cnt int; v_warned boolean:=false; v_email text;
begin
  select * into v from inquiries where id=p_inquiry;
  if not found then return jsonb_build_object('error','inquiry_not_found'); end if;
  if p_customer is not null and v.customer_id is distinct from p_customer then
    return jsonb_build_object('error','not_your_inquiry'); end if;
  if v.status='cancelled' or v.pipeline_stage='cancelled' then
    return jsonb_build_object('ok',true,'already_cancelled',true); end if;
  select exists(select 1 from transactions where inquiry_id=p_inquiry) into v_paid;
  if v_paid or v.status in ('revealed','completed') or v.pipeline_stage in ('revealed','won') then
    return jsonb_build_object('error','already_revealed',
      'message','This request already has an active revealed deal and cannot be cancelled. You can close it instead.'); end if;

  update inquiries set status='cancelled', pipeline_stage='cancelled', outcome='cancelled',
      lost_reason=coalesce(p_reason,'customer_cancelled'), completed_at=now(), stage_changed_at=now()
    where id=p_inquiry;
  insert into inquiry_cancellations(inquiry_id,customer_id,reason) values (p_inquiry, v.customer_id, p_reason);

  select count(*) into v_cnt from inquiry_cancellations where customer_id=v.customer_id and created_at > now()-interval '30 days';
  if v.customer_id is not null and v_cnt >= 3 then
    select email into v_email from customers where id=v.customer_id;
    if v_email is not null and position('@' in v_email)>1
       and not exists (select 1 from notifications where type='cancel_warning' and to_email=v_email and created_at > now()-interval '30 days') then
      insert into notifications(type,to_email,to_role,inquiry_id,subject,body,channel,status)
      values('cancel_warning', v_email, 'customer', p_inquiry,
        'A quick note about cancelled requests',
        'We noticed a few of your recent requests were cancelled. That is completely fine — but every request you post is prepared and quoted by suppliers who set aside real time for it. To keep things fair for them, we kindly ask that you post requests you intend to proceed with. If you would like help scoping a job before posting, our team is glad to assist.',
        'email','queued');
      v_warned:=true;
    end if;
  end if;
  return jsonb_build_object('ok',true,'cancelled',true,'cancellations_30d',v_cnt,'warned',v_warned);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_category_knowledge(p_category text)
 RETURNS TABLE(catalog_slug text, topic text, content text, priority integer, layer text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- THE KNOWLEDGE WAS COMPLETE AND UNREACHABLE.
  -- All 84 spec categories carry their 8 modules under agent_key 'cat:<catalogue-slug>', but the
  -- live intake assigns one of 56 LEGACY slugs whose overlap with the catalogue is exactly zero.
  -- lead_trade_map is the bridge; this is the first thing that walks it at read time.
  -- Accepts either vocabulary so callers do not need to know which one they hold.
  with resolved as (
    select coalesce(
      (select c.slug from public.catalog_supplier_categories c where c.slug = p_category),
      (select m.catalog_slug from public.lead_trade_map m
         join public.catalog_supplier_categories c2 on c2.slug = m.catalog_slug
        where m.trade_key = p_category)
    ) as slug
  )
  select r.slug, k.topic, k.content, k.priority, k.layer
    from resolved r
    join public.agent_knowledge k on k.agent_key = 'cat:' || r.slug
   where r.slug is not null
   order by k.priority desc nulls last, k.topic;
$function$;

CREATE OR REPLACE FUNCTION public.fn_category_knowledge_promote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_slug text; v_know text; v_name text; r jsonb;
begin
  if NEW.kind='category_knowledge' and NEW.status in ('approved','done')
     and coalesce(OLD.status,'') not in ('approved','done') then
    v_slug := NEW.detail->>'slug'; v_know := NEW.detail->>'knowledge'; v_name := NEW.detail->>'name';
    if v_slug is not null and v_know is not null then
      -- publish the quoting-knowledge blob live (full parity) if not already present
      if not exists (select 1 from agent_knowledge where agent_key='cat:'||v_slug) then
        insert into agent_knowledge(agent_key,topic,content,priority,created_at,updated_at)
        values ('cat:'||v_slug, coalesce(v_name,v_slug), v_know, 100, now(), now());
      else
        update agent_knowledge set content=v_know, updated_at=now() where agent_key='cat:'||v_slug;
      end if;
      -- apply the proposed regulation -> category mapping
      for r in select * from jsonb_array_elements(coalesce(NEW.detail->'reg_matches','[]'::jsonb)) loop
        update regulations
          set categories = array(select distinct e from unnest(coalesce(categories,'{}'::text[]) || array[v_slug]) e)
          where id::text = (r->>'id') and not (v_slug = any(coalesce(categories,'{}'::text[])));
      end loop;
    end if;
  end if;
  return NEW;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_category_questions(p_category text, p_lang text DEFAULT 'en'::text, p_limit integer DEFAULT 22)
 RETURNS TABLE(field_key text, question text, answer_type text, mandatory boolean, ask_order integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'kb_stage'
AS $function$
  -- THE SPEC'S "INQUIRY QUALIFICATION LOGIC", REACHABLE FOR THE FIRST TIME.
  -- 16,588 questions (4,117 distinct texts, 7,079 mandatory, 14,051 bilingual) live in kb_stage
  -- keyed by FAMILY slug. The intake speaks a legacy slug. The chain is
  --   intake slug -> lead_trade_map -> catalogue slug -> catalog_category_domain -> family
  -- and this walks all of it, accepting either vocabulary at the front.
  --
  -- field_key is NULL on every row; the real supplier-facing key and the ask-order live inside
  -- `activation`. Sorting by that order is the point - it is what makes this an ordered interview
  -- rather than the flat, unordered list category_specs.fields produces.
  --
  -- Deduplicated on question text: a family spans up to 465 subcategories which repeat the generic
  -- spine (emirate, exact need, scope, quantity, date), so without DISTINCT ON the first 20 rows
  -- would be the same question twenty times.
  with fam as (
    select d.domain_slug
      from public.catalog_category_domain d
     where d.catalog_slug = coalesce(
       (select c.slug from public.catalog_supplier_categories c where c.slug = p_category),
       (select m.catalog_slug from public.lead_trade_map m where m.trade_key = p_category))
  )
  select * from (
    select distinct on (q.question_en)
           coalesce(q.activation->>'supplier_facing_field', q.field_key) as field_key,
           case when p_lang = 'ar' and coalesce(q.question_ar,'') <> '' then q.question_ar else q.question_en end as question,
           q.answer_type,
           q.mandatory,
           coalesce((q.activation->>'order')::int, 999) as ask_order
      from kb_stage.questions q
      join fam on fam.domain_slug = q.category_slug
     where coalesce(q.question_en,'') <> ''
     order by q.question_en, q.mandatory desc
  ) x
  order by x.mandatory desc, x.ask_order, x.field_key
  limit greatest(p_limit, 1);
$function$;

CREATE OR REPLACE FUNCTION public.fn_chief_of_staff()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare disp jsonb; exec jsonb; health jsonb; ops jsonb; rev jsonb;
  n_pending int; n_aging int; n_depts int; brief text; recs text; dept_txt text; esc_txt text; owner text;
  prioritized jsonb; run_id bigint;
begin
  disp := public.fn_autonomy_dispose();
  exec := public.fn_ws_exec();
  health := exec->'command'->'health'; ops := exec->'command'->'ops'; rev := ops->'revenue';

  select count(*) into n_pending from public.agent_actions where status in ('pending','held_for_review','proposed','open','needs_review');
  select count(*) into n_aging from public.agent_actions
    where status in ('pending','held_for_review','proposed','open','needs_review') and created_at < now()-interval '3 days';
  select count(distinct agent) into n_depts from public.agent_runs where started_at > now()-interval '24 hours';

  select string_agg(line, E'\n' order by line) into dept_txt from (
    select '- '||agent||': '||count(*)||' runs'||
           case when count(*) filter (where status='error')>0 then ' ('||count(*) filter (where status='error')||' failed)' else '' end as line
    from public.agent_runs where started_at > now()-interval '24 hours' group by agent
  ) d;

  select string_agg('- ['||coalesce(risk,'?')||'] '||coalesce(title,kind)||' ('||agent||')', E'\n') into esc_txt from (
    select agent,risk,title,kind from public.agent_actions
     where status in ('pending','held_for_review','proposed','open','needs_review') order by created_at asc limit 10
  ) e;

  select coalesce(jsonb_agg(x order by cat asc),'[]'::jsonb) into prioritized from (
    select jsonb_build_object('id',id,'agent',agent,'risk',risk,'title',title,
             'age_days',round(extract(epoch from (now()-created_at))/86400)) x, created_at cat
    from public.agent_actions where status in ('pending','held_for_review','proposed','open','needs_review')
    order by created_at asc limit 15
  ) s;

  recs := '';
  if n_pending>0 then recs := recs||'1) '||n_pending||' item(s) in your queue (payments, deletions, flagged suppliers, marketing to post, BD to enable, to-dos).'||E'\n'; end if;
  if n_aging>0 then recs := recs||'2) '||n_aging||' waited >3 days — action or dismiss.'||E'\n'; end if;
  if (health->>'band') is not null and lower(health->>'band')<>'good'
     then recs := recs||'3) Health "'||(health->>'band')||'" ('||coalesce(health->>'index','?')||'/100).'||E'\n'; end if;
  if recs='' then recs := 'Queue clear. Everything auto-handled where safe.'; end if;

  brief := 'Chief of Staff — daily briefing ('||to_char(now(),'DD Mon YYYY')||')'||E'\n\n'
    ||'HEADLINE: auto-approved '||coalesce(disp->>'approved_suppliers','0')||' clean supplier(s), auto-cleared '
      ||coalesce(disp->>'auto_cleared_logged','0')||' logged alert(s). '||n_pending||' item(s) in your queue. Health '
      ||coalesce(health->>'index','?')||'/100 ('||coalesce(health->>'band','?')||').'||E'\n\n'
    ||'YOUR QUEUE:'||E'\n'||coalesce(esc_txt,'- Empty.')||E'\n\n'
    ||'DEPARTMENTS (24h):'||E'\n'||coalesce(dept_txt,'- No agent runs in the last 24h.')||E'\n\n'
    ||'KPIs: revenue month '||coalesce(rev->>'month_aed','0')||' AED, cash received '||coalesce(rev->>'cash_received_aed','0')
      ||' AED, pending fees '||coalesce(rev->>'pending_fees_aed','0')||' AED, active RFQs '||coalesce(ops->'marketplace'->>'active_rfqs','0')||'.'||E'\n\n'
    ||'RECOMMENDATIONS:'||E'\n'||recs;

  insert into public.agent_runs(agent,started_at,finished_at,status,counts,note)
    values('chief_of_staff',now(),now(),'ok',
      jsonb_build_object('approved_suppliers',disp->>'approved_suppliers','auto_cleared',disp->>'auto_cleared_logged',
        'in_queue',n_pending,'aging',n_aging,'departments',n_depts),'coordination + autonomy v2')
    returning id into run_id;

  insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,target_id,detail)
    values('chief_of_staff','exec_briefing','auto_done','low',
      'Chief of Staff briefing — '||n_pending||' in queue, '||coalesce(disp->>'auto_cleared_logged','0')||' auto-cleared',
      'Informational.', null, null,
      jsonb_build_object('briefing',brief,'prioritized',prioritized,'autonomy',disp,'health',health->>'index','in_queue',n_pending));

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from public.app_secrets where key='admin_emails';
  owner := coalesce(nullif(trim(owner),''),'management@quotesdone.com');
  insert into public.notifications(type,to_email,to_role,channel,subject,body)
    values('chief_of_staff', owner, 'admin','email',
      'Chief of Staff — '||n_pending||' in your queue, health '||coalesce(health->>'index','?')||'/100', brief);

  return jsonb_build_object('ok',true,'autonomy',disp,'in_queue',n_pending,'aging',n_aging,'departments',n_depts,'run_id',run_id);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_collections()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; v_reminded int:=0; r record;
begin
  insert into agent_runs(agent, started_at) values ('collections', now()) returning id into v_run;
  -- NO commission is charged on won jobs (founder policy: zero commission). This engine never creates dues.
  -- The only supplier charge is the non-response fine (= the refunded reveal fee), created by qd_on_refund_resolved,
  -- and enforced by a matching block until settled. Here we only send a gentle reminder; no extra fees are added.
  for r in select d.*, l.claimed_by, l.email as lead_email, l.company_name
           from supplier_dues d join leads l on l.id=d.supplier_id
           where d.status in ('due','pending','reminded')
             and (d.last_reminder_at is null or d.last_reminder_at < now()-interval '4 days')
             and d.reminders < 3
  loop
    update supplier_dues set status='reminded', reminders=reminders+1, last_reminder_at=now() where id=r.id;
    insert into notifications(type,to_email,to_role,channel,status,lead_id,subject,body)
      values ('nonresponse_reminder', coalesce(r.claimed_by,r.lead_email), 'supplier', 'portal', 'portal', r.supplier_id,
        'Reminder: outstanding non-response charge',
        'Reminder: a non-response charge of AED '||round(r.amount_due)||' is outstanding on your account. This equals the reveal fee that was refunded to a customer because a paid reveal was not responded to. Please settle it on the portal to lift the hold on new matches. QuotesDone charges no commission on won jobs.');
    v_reminded := v_reminded + 1;
  end loop;
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('reminders',v_reminded,'commission_charged',0) where id=v_run;
end;$function$;

CREATE OR REPLACE FUNCTION public.fn_company_brief(p_max_chars integer DEFAULT 1600)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s jsonb; out text; d jsonb;
begin
  s := fn_company_state();
  out := 'COMPANY SELF-KNOWLEDGE (authoritative org facts — you may answer any question about the company from this):'||E'\n'
       ||'Vision: '||(s->>'vision')||E'\n'
       ||'Totals: '||(s->'totals'->>'departments')||' departments, '||(s->'totals'->>'brain_agents')||' brain agents, '
       ||(s->'totals'->>'category_sales_agents')||' category sales agents, '||(s->'totals'->>'tools_wired')||' wired tools, '
       ||(s->'totals'->>'open_objectives')||' open objectives, '||(s->'totals'->>'open_tasks')||' open tasks.'||E'\n'
       ||'Departments (lead · brain agents · north star):'||E'\n';
  for d in select * from jsonb_array_elements(s->'departments') loop
    out := out || '- '||(d->>'name')||' ['||(d->>'dept')||']: lead '||coalesce(d->>'lead_agent','—')
                || ', '||(d->>'headcount')||' agent(s)';
    if jsonb_array_length(d->'brain_agents') > 0 then
      out := out || ' ('||replace(replace(replace((d->'brain_agents')::text,'"',''),'[',''),']','')||')';
    end if;
    out := out || ', north star: '||coalesce(d->>'north_star','—')||E'\n';
    exit when length(out) > p_max_chars;
  end loop;
  return left(out, greatest(p_max_chars, 400));
end $function$;

CREATE OR REPLACE FUNCTION public.fn_company_faq_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_body text; n int;
begin
  select count(*) into n from company_faq where status='approved';
  select 'QUOTESDONE COMPANY FAQ — canonical answers every agent must use verbatim-in-spirit (founder-approved). '||
         'If asked anything here, answer consistently with this. Do not contradict it or invent beyond it.'||E'\n\n'||
         coalesce(string_agg(
           '## ['||section||'] '||question||E'\n'||coalesce(answer,'(no answer yet)')||
           case when audience<>'all' then E'\n(Audience: '||audience||')' else '' end,
           E'\n\n' order by section, sort, id), '')
    into v_body
  from company_faq where status='approved';

  if n=0 then
    delete from agent_knowledge where agent_key='_global' and topic='Company FAQ (canonical answers)';
    return jsonb_build_object('synced',0);
  end if;
  if exists(select 1 from agent_knowledge where agent_key='_global' and topic='Company FAQ (canonical answers)') then
    update agent_knowledge set content=v_body, updated_at=now()
      where agent_key='_global' and topic='Company FAQ (canonical answers)';
  else
    insert into agent_knowledge(agent_key,topic,content,priority,created_at,updated_at)
      values('_global','Company FAQ (canonical answers)', v_body, 96, now(), now());
  end if;
  return jsonb_build_object('synced', n);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_company_state()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with depts as (
    select d.dept_key, d.name, d.charter, d.north_star, d.lead_agent, d.active,
           coalesce((select array_agg(a.agent_key order by a.agent_key) from org_agents a where a.department=d.dept_key and a.active), '{}') as brain_agents,
           (select count(*) from org_agents a where a.department=d.dept_key and a.active) as brain_count,
           (select count(*) from org_action_executor e where e.department=d.dept_key and e.active) as tool_count
    from org_departments d where d.active
  )
  select jsonb_build_object(
    'vision', (select vision from company_vision where id=1),
    'mission', (select mission from company_vision where id=1),
    'as_of', now(),
    'totals', jsonb_build_object(
      'departments', (select count(*) from depts),
      'brain_agents', (select count(*) from org_agents where active),
      'category_sales_agents', (select count(*) from category_agents),
      'tools_wired', (select count(*) from org_action_executor where active),
      'open_objectives', (select count(*) from org_objectives where status not in ('done','cancelled')),
      'open_tasks', (select count(*) from org_tasks where status in ('assigned','proposed','in_progress'))
    ),
    'departments', (select jsonb_agg(jsonb_build_object(
        'dept', dept_key, 'name', name, 'charter', charter, 'north_star', north_star,
        'lead_agent', lead_agent, 'brain_agents', brain_agents,
        'headcount', brain_count + case when dept_key='procurement' then (select count(*) from category_agents) else 0 end,
        'tools_wired', tool_count) order by dept_key) from depts)
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_control_mode_session_mfa_is_real()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v public.control_mode_challenge%rowtype;
begin
  select * into v from public.control_mode_challenge where id = new.mfa_ref;
  if not found then
    raise exception 'control mode: mfa_ref % is not a challenge', new.mfa_ref using errcode = '23514';
  end if;
  if lower(btrim(v.admin_email)) <> lower(btrim(new.actor_email)) then
    raise exception 'control mode: challenge belongs to %, not %', v.admin_email, new.actor_email using errcode = '23514';
  end if;
  if v.purpose <> 'control_mode' then
    raise exception 'control mode: challenge % was issued for %, not control_mode', v.id, v.purpose using errcode = '23514';
  end if;
  if v.consumed_at is null or coalesce(v.consumed_why,'') <> 'opened' then
    raise exception 'control mode: challenge % was not consumed by an open (consumed_why=%)',
      v.id, coalesce(v.consumed_why,'<null>') using errcode = '23514';
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_customer_stats(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb; v_inq int; v_open int; v_quotes int; v_deals int; v_spend numeric; v_list jsonb; v_hist jsonb;
begin
  select count(*) into v_inq from inquiries where customer_id=p_customer and parent_inquiry_id is null;
  select count(*) into v_open from inquiries where customer_id=p_customer and parent_inquiry_id is null and coalesce(status,'') not in ('completed','closed','cancelled','split');
  select count(*) into v_quotes from quotes q where q.status <> 'draft' and q.inquiry_id in (select id from inquiries where customer_id=p_customer);
  select count(*) into v_deals from transactions where customer_id=p_customer;
  select coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)),0) into v_spend from transactions where customer_id=p_customer and coalesce(refund_status,'')<>'approved';
  select jsonb_agg(x order by (x->>'created_at') desc) into v_list from (
    select jsonb_build_object(
      'id', i.id, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
      'created_at', i.created_at, 'pipeline_stage', i.pipeline_stage, 'outcome', i.outcome,
      'has_drawing', (i.drawing_file_path is not null), 'boq_confidence', i.boq_confidence,
      'quotes_count', (select count(*) from quotes q where q.inquiry_id=i.id and q.status <> 'draft'),
      'minutes_since', round(extract(epoch from (now()-i.created_at))/60.0)::int,
      'editable', (i.status='sent') and (now()-i.created_at) < interval '60 minutes',
      'edit_minutes_left', greatest(0, 60 - round(extract(epoch from (now()-i.created_at))/60.0)::int)
    ) x from inquiries i where i.customer_id=p_customer and i.parent_inquiry_id is null
  ) t;
  with months as (select date_trunc('month',(now()-(n||' month')::interval)) m from generate_series(0,11) n),
  ib as (select date_trunc('month',created_at) m, count(*) c from inquiries where customer_id=p_customer and parent_inquiry_id is null group by 1)
  select jsonb_agg(jsonb_build_object('month',to_char(months.m,'Mon YY'),'inquiries',coalesce(ib.c,0)) order by months.m)
    into v_hist from months left join ib on ib.m=months.m;
  v := jsonb_build_object(
    'customer_id', p_customer,'inquiries_total', v_inq,'open_inquiries', v_open,
    'quotes_received', v_quotes,'avg_quotes_per_inquiry', round(v_quotes::numeric/nullif(v_inq,0),1),
    'deals', v_deals,'total_spend', v_spend,
    'inquiries', coalesce(v_list,'[]'::jsonb),'history_12m', v_hist);
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_dropbox_list(p_prefix text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'prefix', p_prefix,
    'items', coalesce((
      select jsonb_agg(to_jsonb(t) order by t.is_folder desc, lower(t.name))
      from (
        select id, path, name, is_folder, size, server_modified
        from dropbox_files
        where substring(path, 1, length(path) - length(split_part(path,'/', -1)) - 1) = p_prefix
      ) t
    ), '[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_dues_to_escalate(p_days integer)
 RETURNS TABLE(due_id bigint, supplier_id bigint, principal numeric, currency text, reveal_date date, due_date date, days_overdue integer, company_name text, contact_name text, email text, phone text, trade_license_no text, emirate text, category text, signed_terms_path text, claimed_by text, accepted_terms_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select d.id, d.supplier_id, d.amount_due, coalesce(d.currency,'AED'), d.reveal_date, d.due_date::date,
         (current_date - d.due_date::date) as days_overdue,
         l.company_name, l.contact_name, coalesce(l.claimed_by,l.email) as email, coalesce(l.phone_e164,l.phone),
         l.trade_license_no, l.emirate,
         coalesce(nullif(btrim(split_part(coalesce(l.categories,''),',',1)),''), nullif(l.sector,''),'Uncategorized') as category,
         l.signed_terms_path, l.claimed_by, l.accepted_terms_at
  from public.supplier_dues d
  join public.leads l on l.id = d.supplier_id
  where d.status not in ('paid','waived','cancelled','legal')
    and d.legal_escalated_at is null
    and coalesce(d.amount_due,0) > 0
    and current_date >= add_working_days(d.due_date::date, p_days);
$function$;

CREATE OR REPLACE FUNCTION public.fn_emit_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_type text; v_entity text; v_id text; v_actor text;
begin
  v_entity := tg_argv[0];
  v_type   := tg_argv[1];
  begin v_id := (to_jsonb(new)->>'id'); exception when others then v_id := null; end;
  begin v_actor := coalesce(to_jsonb(new)->>'created_by', to_jsonb(new)->>'author_agent', to_jsonb(new)->>'actor', 'system'); exception when others then v_actor := 'system'; end;
  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values (v_type, v_entity, v_id, v_actor, to_jsonb(new));
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.fn_enable_dropbox_sync()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare jid int; begin
  select jobid into jid from cron.job where jobname='dropbox_sync_daily';
  if jid is not null then perform cron.alter_job(jid, active:=true); return 'enabled'; end if;
  return 'not_found';
end $function$;

CREATE OR REPLACE FUNCTION public.fn_expiring_docs(p_days integer DEFAULT 60)
 RETURNS TABLE(id bigint, company_name text, sector text, doc text, expiry date, days_left integer, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.company_name, l.sector, d.label, d.exp, (d.exp-current_date),
    case when d.exp<current_date then 'expired' when d.exp<=current_date+30 then 'expiring' else 'soon' end
  from leads l, lateral (values ('Trade license',l.license_expiry),('ISO certification',l.iso_expiry),
     ('Insurance',l.insurance_expiry),('Manufacturer authorization',l.manufacturer_auth_expiry)) d(label,exp)
  where d.exp is not null and d.exp <= current_date + p_days
    and coalesce(l.approval_status,'')='approved'
  order by d.exp asc;
$function$;

CREATE OR REPLACE FUNCTION public.fn_gl_sync_business()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb;
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

  -- 1) Reveal-fee revenue with Stripe fee split (refunded transactions excluded)
  for r in
    select id, reveal_fee, coalesce(revealed_at::date, current_date) as d
    from public.transactions
    where fee_status='paid' and coalesce(reveal_fee,0) > 0
      and coalesce(refund_status,'') not in ('refunded','refund_approved')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=transactions.id::text)
  loop
    gross := round(r.reveal_fee,2);
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;
    perform public.fn_gl_entry(r.d, 'Reveal fee (net of Stripe fee)', 'reveal_fee', r.id::text,
      case when fee > 0 then
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',net),
          jsonb_build_object('account','6100','debit',fee),
          jsonb_build_object('account','4000','credit',gross))
      else
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',gross),
          jsonb_build_object('account','4000','credit',gross))
      end, 'gl_sync');
    n := n + 1;
  end loop;

  -- 1b) REFUND PAID OUT TO THE CUSTOMER (previously never posted at all).
  -- If revenue was booked before the refund, this also reverses its effect on the P&L.
  for r in
    select t.id, coalesce(t.reveal_fee, t.app_fee, 0) as amt,
           coalesce(t.refund_resolved_at::date, t.revealed_at::date, current_date) as d
    from public.transactions t
    where coalesce(t.refund_status,'') in ('refunded','refund_approved')
      and coalesce(coalesce(t.reveal_fee, t.app_fee), 0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=t.id::text)
  loop
    gross := round(r.amt,2);
    perform public.fn_gl_entry(r.d, 'Reveal fee refunded to customer (paid from our balance)',
      'refund_paid', r.id::text,
      jsonb_build_array(jsonb_build_object('account','6900','debit',gross),
                        jsonb_build_object('account','1050','credit',gross)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 2) Clawback RAISED on the supplier. Credits 6900 (recovering the refund), NOT 4100.
  --    Any admin fee / interest assessed at the same time is genuine income -> 4400.
  for r in
    select id, amount_due,
           coalesce(admin_fee,0) + coalesce(interest_amount,0) as extra_owed,
           coalesce(reveal_date, created_at::date, current_date) as d
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and coalesce(status,'') not in ('waived','cancelled','reversed')
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    lines := jsonb_build_array(
      jsonb_build_object('account','1110','debit', round(r.amount_due,2) + extra),
      jsonb_build_object('account','6900','credit', round(r.amount_due,2)));
    if extra > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','4400','credit', extra)); end if;
    perform public.fn_gl_entry(r.d,
      'Refund clawback raised on supplier' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_accrue', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier SETTLES via Stripe.
  for r in
    select id, amount_due,
           coalesce(fine_amount,0) + coalesce(interest_amount,0) + coalesce(admin_fee,0) as extra_owed,
           paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    gross := round(r.amount_due,2) + extra;
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;

    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','1110','credit', gross));

    perform public.fn_gl_entry(r.d,
      'Refund clawback settled by supplier via Stripe' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_collect', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2c) SUBSCRIPTION revenue (RULE 1). Previously never posted - 4200 sat unused.
  for r in
    select l.id, l.registration_fee_due, l.registration_paid_at::date as d
    from public.leads l
    where l.registration_status = 'paid'
      and l.registration_paid_at is not null
      and coalesce(l.registration_fee_due,0) >= 0
      and coalesce(l.subscription_exempt,false) = false
      and not exists (select 1 from public.gl_journal g
                      where g.source='subscription' and g.source_ref = l.id::text || ':' || l.registration_paid_at::date)
  loop
    gross := round(coalesce(r.registration_fee_due,0),2);
    if gross <= 0 then continue; end if;
    fee := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net := gross - fee;
    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','4200','credit',gross));
    perform public.fn_gl_entry(r.d, 'Annual supplier subscription', 'subscription',
      r.id::text || ':' || r.d::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Expense charges, converted to AED (the ledger currency)
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
  loop
    if r.cur not in ('AED','USD') then
      begin
        insert into public.founder_alerts(level, event, detail, channel)
        values ('warn', 'gl_unconvertible_currency',
                'Expense #'||r.id||' from '||coalesce(r.vendor,'?')||' is in '||r.cur||
                ', which has no rate in gl_settings, so it was NOT posted. Expenses are understated by '||
                r.amount||' '||r.cur||' until a rate is added. Skipped rather than booked at 1:1.', 'system');
      exception when others then null; end;
      continue;
    end if;
    amt_aed := round(r.amount * case when r.cur='USD' then fx else 1 end, 2);
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'Expense: '||coalesce(r.category,'G&A')||case when r.cur='USD' then ' ('||r.amount||' USD @ '||fx||')' else '' end,
      'expense', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',amt_aed),
                        jsonb_build_object('account','1000','credit',amt_aed)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 3b) One-off FX correction for USD expenses posted at 1:1 before the 19 Jul 2026 fix.
  for r in
    select e.id, e.amount, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d,
           (select sum(jl.debit) from public.gl_journal g
              join public.gl_journal_lines jl on jl.journal_id = g.id
             where g.source='expense' and g.source_ref = e.id::text and jl.debit > 0) as posted_aed
    from public.expense_entries e
    where upper(coalesce(e.currency,'AED')) = 'USD'
      and coalesce(e.amount,0) > 0
      and exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not exists (select 1 from public.gl_journal g where g.source='expense_fx_adj' and g.source_ref=e.id::text)
  loop
    diff := round(r.amount * fx, 2) - coalesce(r.posted_aed, 0);
    if diff is null or diff = 0 then continue; end if;
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'FX correction: expense #'||r.id||' ('||coalesce(r.vendor,'?')||') was booked at 1:1; restated at USD/AED '||fx,
      'expense_fx_adj', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',diff),
                        jsonb_build_object('account','1000','credit',diff)), 'gl_fx_fix');
    n := n + 1;
  end loop;

  return n;
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_inquiry_workstream_activate(p_group_id bigint, p_trade_key text, p_actor text DEFAULT 'system'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ws_id bigint; v_route integer; v_reactivated boolean := false; v_reqs integer;
begin
  if not exists (select 1 from public.mep_trade where trade_key = p_trade_key) then
    return jsonb_build_object('ok', false, 'error', 'unknown_trade', 'trade_key', p_trade_key);
  end if;
  if not exists (select 1 from public.inquiry_workstream_group where id = p_group_id) then
    return jsonb_build_object('ok', false, 'error', 'unknown_group');
  end if;

  select catalog_num into v_route from public.mep_trade_route
   where trade_key = p_trade_key and is_primary order by catalog_num limit 1;

  select id into v_ws_id from public.inquiry_workstream
   where group_id = p_group_id and trade_key = p_trade_key;

  if v_ws_id is null then
    insert into public.inquiry_workstream (group_id, trade_key, route_catalog_num)
    values (p_group_id, p_trade_key, v_route) returning id into v_ws_id;
  else
    update public.inquiry_workstream
       set active = true, activated_at = now(), deactivated_at = null
     where id = v_ws_id and active = false;
    v_reactivated := found;
    update public.inquiry_workstream set active = true where id = v_ws_id;
  end if;

  insert into public.inquiry_workstream_requirement (workstream_id, question_id, field_id, mandatory)
  select v_ws_id, min(q.question_id), s.field_id, bool_or(q.mandatory)
    from public.mep_trade_route tr
    join public.kb_operational_route_map m on m.catalog_num = tr.catalog_num
    join kb_stage.questions q on q.subcategory_slug = m.subcategory_slug
    join public.field_definition_source s
      on s.subcategory_slug = q.subcategory_slug and s.source_field_key = q.field_key
    left join public.subcategory_trade_contribution c
      on c.subcategory_slug = m.subcategory_slug and c.catalog_num = tr.catalog_num
     and c.trade_key = tr.trade_key
   where tr.trade_key = p_trade_key and q.field_key is not null
     and coalesce(c.contribution, 'technical') <> 'excluded'
     and (coalesce(c.contribution, 'technical') <> 'regulatory'
          or q.field_key = any(coalesce(c.contributed_field_keys, '{}'::text[])))
     and not exists (select 1 from public.field_definition_reference r
                      where r.field_id = s.field_id and r.referencing_trade_key = p_trade_key)
   group by s.field_id
  on conflict (workstream_id, field_id) do update
     set mandatory = public.inquiry_workstream_requirement.mandatory or excluded.mandatory;

  get diagnostics v_reqs = row_count;

  insert into public.inquiry_state_audit (group_id, workstream_id, event, detail, actor)
  values (p_group_id, v_ws_id,
          case when v_reactivated then 'workstream_reactivated' else 'workstream_activated' end,
          jsonb_build_object('trade_key', p_trade_key, 'route_catalog_num', v_route,
                             'requirements', v_reqs), p_actor);

  return jsonb_build_object('ok', true, 'workstream_id', v_ws_id, 'trade_key', p_trade_key,
                            'reactivated', v_reactivated, 'requirements', v_reqs);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_intake_slug_for_catalog(p_catalog_slug text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- The reverse of fn_category_knowledge: catalogue slug -> the legacy intake slug that owns the
  -- checklist. It is 1-to-many (flooring-suppliers is reached by carpets, epoxy-flooring, flooring,
  -- marble-granite and tiling), so the choice has to be deterministic or the same customer wording
  -- would land on a different checklist run to run.
  --
  -- Prefer a key the catalogue slug actually BEGINS with - 'flooring' for flooring-suppliers,
  -- 'aluminium' for aluminium-and-glass-suppliers, 'mep' for mep-suppliers-electromechanical.
  -- That picks the base trade over a facet of it. Where none prefixes, the shortest wins, which
  -- also prefers the base ('carpentry' over 'carpentry-joinery', 'fitout' over
  -- 'commercial-retail-fitout'). Only keys that exist in category_specs are eligible, because the
  -- answer has to be something the checklist lookup can actually use.
  select m.trade_key
    from public.lead_trade_map m
    join (select distinct category from public.category_specs) cs on cs.category = m.trade_key
   where m.catalog_slug = p_catalog_slug
   order by (p_catalog_slug like m.trade_key || '%') desc, length(m.trade_key) asc, m.trade_key asc
   limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.fn_invite_week_activate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.kind = 'invite_campaign_week'
     and NEW.status in ('approved','done','auto_done','accepted','resolved','closed','completed')
     and coalesce(OLD.status,'') is distinct from NEW.status then
    update invite_schedule set status='approved' where status='pending' and day >= (now() at time zone 'UTC')::date;
    update app_secrets set value='true' where key in ('invite_enabled','supplier_emails_enabled');
    insert into founder_alerts(level,event,detail,channel)
      values('info','invite_week_approved','Supplier invite week approved in OS — schedule activated and sending enabled.','system');
  end if;
  return NEW;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_knowledge_gaps(p_stale_days integer DEFAULT 14, p_thin_min integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with base as (
    select ca.slug, ca.name, ca.emoji,
      (select count(*) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as items,
      (select max(updated_at) from agent_knowledge k where k.agent_key = ca.slug or k.agent_key = 'cat:'||ca.slug) as last_updated,
      (select min(d.os_key) from os_knowledge_domain d
        where d.domain_key = 'cat:'||ca.slug and d.ownership = 'owns') as owner_os
    from category_agents ca where coalesce(ca.active,true)
  ),
  scored as (
    select slug, name, emoji, items, last_updated, owner_os,
      case when last_updated is null then null else floor(extract(epoch from (now()-last_updated))/86400)::int end as days_stale,
      case when items = 0 then 'missing'
           when last_updated < now() - (p_stale_days||' days')::interval then 'stale'
           when items < p_thin_min then 'thin'
           else 'ok' end as status
    from base
  )
  select jsonb_build_object(
    'thresholds', jsonb_build_object('stale_days', p_stale_days, 'thin_min', p_thin_min),
    'summary', jsonb_build_object(
      'total', (select count(*) from scored),
      'ok', (select count(*) from scored where status='ok'),
      'stale', (select count(*) from scored where status='stale'),
      'thin', (select count(*) from scored where status='thin'),
      'missing', (select count(*) from scored where status='missing'),
      'unowned', (select count(*) from scored where owner_os is null),
      'coverage_pct', round(100.0 * (select count(*) from scored where status='ok') / nullif((select count(*) from scored),0), 1)
    ),
    'agents', coalesce((select jsonb_agg(jsonb_build_object(
        'slug', slug, 'name', name, 'emoji', emoji, 'items', items, 'owner_os', owner_os,
        'last_updated', last_updated, 'days_stale', days_stale, 'status', status
      ) order by case status when 'stale' then 0 when 'thin' then 1 when 'missing' then 2 else 3 end, days_stale desc nulls last, slug)
      from scored), '[]'::jsonb)
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_llm_drift_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v jsonb := '[]'::jsonb; v_off int; v_fb numeric; v_fail int; v_owner text; v_recent int;
begin
  select count(*) into v_recent from llm_calls where created_at > now() - interval '24 hours';
  if v_recent = 0 then
    return jsonb_build_object('checked_at', now(), 'calls_24h', 0, 'findings', 0,
                              'note','no llm traffic in 24h - nothing to judge');
  end if;

  -- 1. any model not on the approved list
  select count(*) into v_off from v_llm_offpolicy;
  if v_off > 0 then
    v := v || jsonb_build_object('issue','off_policy_model','severity','high',
         'detail',(select jsonb_agg(jsonb_build_object('fn',fn,'model',model,'calls',calls)) from v_llm_offpolicy));
  end if;

  -- 2. fallback rate: Opus answering when Sonnet was asked means Sonnet is failing
  select round(100.0 * count(*) filter (where fell_back) / nullif(count(*),0), 1)
    into v_fb from llm_calls where created_at > now() - interval '24 hours';
  if coalesce(v_fb,0) > 20 then
    v := v || jsonb_build_object('issue','high_fallback_rate','severity','high','pct',v_fb,
         'detail','the primary model is failing often - you are paying fallback prices silently');
  end if;

  -- 3. outright failures
  select count(*) into v_fail from llm_calls
   where created_at > now() - interval '24 hours' and not ok;
  if v_fail > 5 then
    v := v || jsonb_build_object('issue','llm_failures','severity','medium','count',v_fail);
  end if;

  if jsonb_array_length(v) > 0 then
    v_owner := split_part(coalesce((select value from app_secrets where key='admin_emails'),
                                   'management@quotesdone.com'), ',', 1);
    -- once per 24h only, so a standing problem does not spam (lesson from the smoke check)
    if not exists (select 1 from founder_alerts
                    where event='llm_drift' and created_at > now() - interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values ('warn','llm_drift','Model policy drift: '||v::text, 'system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values ('llm_drift', v_owner, 'admin', 'email', 'QuotesDone: AI model drift detected',
                'The model-policy watch found issues in the last 24h:'||chr(10)||chr(10)||
                jsonb_pretty(v)||chr(10)||chr(10)||
                'Check the AI Observability view (v_llm_model_mix / v_llm_offpolicy).', 'queued');
    end if;
  end if;

  return jsonb_build_object('checked_at', now(), 'calls_24h', v_recent,
                            'findings', jsonb_array_length(v), 'detail', v);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_memory_search(p_q text, p_kinds text[] DEFAULT NULL::text[], p_lim integer DEFAULT 20)
 RETURNS TABLE(kind text, ref text, snippet text, ts timestamp with time zone, score real)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with qy as (select plainto_tsquery('english', coalesce(p_q,'')) q)
  select s.kind, s.ref, s.snippet, s.ts, s.score from (
    select 'rfq'::text kind, i.id::text ref, left(coalesce(i.summary, i.raw_input, i.spec::text),220) snippet,
           i.created_at ts, ts_rank(to_tsvector('english', coalesce(i.summary,'')||' '||coalesce(i.raw_input,'')||' '||coalesce(i.spec::text,'')||' '||coalesce(i.category,'')), qy.q) score
    from inquiries i, qy where (p_kinds is null or 'rfq'=any(p_kinds))
      and to_tsvector('english', coalesce(i.summary,'')||' '||coalesce(i.raw_input,'')||' '||coalesce(i.spec::text,'')||' '||coalesce(i.category,'')) @@ qy.q
    union all
    select 'quote', q.id::text, left(coalesce(q.scope, q.notes),220), q.created_at,
           ts_rank(to_tsvector('english', coalesce(q.scope,'')||' '||coalesce(q.notes,'')||' '||coalesce(q.conditions,'')), qy.q)
    from quotes q, qy where (p_kinds is null or 'quote'=any(p_kinds))
      and to_tsvector('english', coalesce(q.scope,'')||' '||coalesce(q.notes,'')||' '||coalesce(q.conditions,'')) @@ qy.q
    union all
    select 'supplier', l.id::text, left(coalesce(l.company_name,'')||' — '||coalesce(l.capability_summary, l.description, l.services),220), l.created_at,
           ts_rank(to_tsvector('english', coalesce(l.company_name,'')||' '||coalesce(l.capability_summary,'')||' '||coalesce(l.services,'')||' '||coalesce(l.description,'')||' '||coalesce(l.categories,'')), qy.q)
    from leads l, qy where (p_kinds is null or 'supplier'=any(p_kinds))
      and to_tsvector('english', coalesce(l.company_name,'')||' '||coalesce(l.capability_summary,'')||' '||coalesce(l.services,'')||' '||coalesce(l.description,'')||' '||coalesce(l.categories,'')) @@ qy.q
    union all
    select 'customer', c.id::text, left(coalesce(c.full_name,'')||' '||coalesce(c.email,''),220), c.created_at,
           ts_rank(to_tsvector('english', coalesce(c.full_name,'')||' '||coalesce(c.email,'')), qy.q)
    from customers c, qy where (p_kinds is null or 'customer'=any(p_kinds))
      and to_tsvector('english', coalesce(c.full_name,'')||' '||coalesce(c.email,'')) @@ qy.q
    union all
    select 'case', a.rfq_id, left(coalesce(a.ai_summary->>'summary',''),220), a.created_at,
           ts_rank(to_tsvector('english', coalesce(a.ai_summary->>'summary','')||' '||coalesce(a.category,'')), qy.q)
    from rfq_archives a, qy where (p_kinds is null or 'case'=any(p_kinds))
      and to_tsvector('english', coalesce(a.ai_summary->>'summary','')||' '||coalesce(a.category,'')) @@ qy.q
    union all
    select 'knowledge', k.agent_key||' :: '||k.topic, left(k.content,220), k.created_at,
           ts_rank(to_tsvector('english', coalesce(k.topic,'')||' '||coalesce(k.content,'')), qy.q)
    from agent_knowledge k, qy where (p_kinds is null or 'knowledge'=any(p_kinds))
      and to_tsvector('english', coalesce(k.topic,'')||' '||coalesce(k.content,'')) @@ qy.q
    union all
    select 'decision', dl.id::text, left(dl.kind||' -> '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,''),220), dl.created_at,
           ts_rank(to_tsvector('english', coalesce(dl.kind,'')||' '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,'')), qy.q)
    from decision_log dl, qy where (p_kinds is null or 'decision'=any(p_kinds))
      and to_tsvector('english', coalesce(dl.kind,'')||' '||coalesce(dl.decision,'')||' '||coalesce(dl.reasons::text,'')) @@ qy.q
  ) s
  order by s.score desc, s.ts desc
  limit greatest(1, coalesce(p_lim,20));
$function$;

CREATE OR REPLACE FUNCTION public.fn_mep_full_scope(p_text_norm text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; v_re text; v_sep text := '[^[:alnum:].;,،؛' || chr(10) || ']+';
begin
  for r in select pattern_norm, lang from public.mep_trade_pattern where kind = 'mep_full_phrase' loop
    if public.fn_term_matches(p_text_norm, r.pattern_norm, r.lang) then
      return jsonb_build_object('matched', true, 'basis', 'explicit_full_mep_phrase',
                                'anchor', r.pattern_norm, 'modifier', null, 'modifier_kind', null);
    end if;
  end loop;

  for r in
    select a.pattern_norm as anchor, m.pattern_norm as modifier, m.kind as modifier_kind, a.lang
      from public.mep_trade_pattern a
      join public.mep_trade_pattern m on m.kind in ('scope_full','scope_container')
     where a.kind = 'mep_anchor'
  loop
    v_re := '(^|[^[:alnum:]])' || r.anchor || '(' || v_sep || '[[:alnum:]]+){0,2}' || v_sep
            || r.modifier || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'anchor_plus_modifier',
                                'anchor', r.anchor, 'modifier', r.modifier,
                                'modifier_kind', r.modifier_kind);
    end if;
    v_re := '(^|[^[:alnum:]])' || r.modifier || '(' || v_sep || '[[:alnum:]]+){0,2}' || v_sep
            || r.anchor || '($|[^[:alnum:]])';
    if p_text_norm ~ v_re then
      return jsonb_build_object('matched', true, 'basis', 'modifier_plus_anchor',
                                'anchor', r.anchor, 'modifier', r.modifier,
                                'modifier_kind', r.modifier_kind);
    end if;
  end loop;

  return jsonb_build_object('matched', false, 'basis', null);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_officer_recs(n integer DEFAULT 8)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select string_agg(line, E'\n') from (
    select '- ['||er.officer||'] '||left(coalesce(rec->>'action',''),150) as line
    from (select distinct on (officer) officer, recommendations from exec_reports order by officer, created_at desc) er,
         lateral jsonb_array_elements(er.recommendations) rec
    where coalesce(rec->>'action','')<>''
    limit n) z;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ops_knowledge_search(p_dept text, p_query text, p_limit integer DEFAULT 5)
 RETURNS TABLE(record_id text, title text, content text, record_type text, authority_tier text, implementation_status text, rank real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q_or tsquery; words text[];
begin
  words := array(select w from unnest(regexp_split_to_array(lower(regexp_replace(coalesce(p_query,''),'[^a-z0-9 ]',' ','g')),'\s+')) w where length(w)>2);
  if array_length(words,1) is null then return; end if;
  begin q_or := to_tsquery('english', array_to_string(words,' | ')); exception when others then return; end;
  return query
    select o.record_id, o.title, o.content, o.record_type, o.authority_tier,
           o.implementation_status, ts_rank(o.tsv, q_or) as rank
      from ops_knowledge o
     where (p_dept is null
            or o.dept_key = p_dept
            -- company principles and the UAE source registry apply to every department, and a
            -- cross-department workflow that names no single owner belongs to all of them by
            -- definition. Without these three branches 884 of 3,959 records were reachable by
            -- nothing at all — the same defect as the corpus itself, one level down.
            or o.scope_type in ('company','external_source')
            or (o.scope_type = 'workflow' and o.dept_key is null))
       and o.tsv @@ q_or
     order by ts_rank(o.tsv, q_or) desc, o.record_id
     limit greatest(1, least(coalesce(p_limit,5),20));
end $function$;

CREATE OR REPLACE FUNCTION public.fn_org_action_executor_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_scope text[];
begin
  if new.kind = 'edge' then
    select c.scope into v_scope
      from public.internal_credential c
     where c.context = 'fn.cos_execute'
       and c.active and c.retired_at is null
     limit 1;

    if v_scope is null then
      raise exception
        'org_action_executor: no live fn.cos_execute credential, so an edge executor target cannot be validated. Refusing the write rather than registering a callee nothing has authorised.'
        using errcode = 'check_violation';
    end if;

    if not (new.target = any (v_scope)) then
      raise exception
        'org_action_executor: edge target % is outside the fn.cos_execute credential scope. cos_execute would POST service-role authority to it. Widen the credential scope deliberately if this executor is intended; do not widen it to make an INSERT succeed.',
        new.target
        using errcode = 'check_violation';
    end if;

  elsif new.kind = 'rpc' then
    if not exists (select 1 from public.org_action_executor_rpc_allowed a where a.target = new.target) then
      raise exception
        'org_action_executor: rpc target % is not in org_action_executor_rpc_allowed. cos_execute runs rpc executors as service-role, so this is a grant of arbitrary database authority. Add it to the allow-list deliberately first.',
        new.target
        using errcode = 'check_violation';
    end if;

  else
    raise exception
      'org_action_executor: unknown kind %. cos_execute only understands edge and rpc, so a row with any other kind is either dead or a mistake. Refusing it rather than storing it.', new.kind
      using errcode = 'check_violation';
  end if;

  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_org_exec_knowledge_fill(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_gaps int; v_req bigint; v_recon jsonb;
begin
  -- self-heal the taxonomy every run (fast, synchronous)
  v_recon := public.fn_kb_reconcile();
  -- how many service categories still have zero knowledge chunks
  select count(*) into v_gaps from public.category_specs s
    where not exists (select 1 from public.kb_chunks k where k.category = s.category);
  -- trigger the (slow) generator in the background
  select net.http_post(
    url:='https://' || public.qd_project_ref() || '.supabase.co/functions/v1/kb_autofill_gaps',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret',(select value from public.app_secrets where key='cred_db_internal'),'limit',greatest(1,least(coalesce(p_limit,5),5))),
    timeout_milliseconds:=280000
  ) into v_req;
  return jsonb_build_object('empty_categories', v_gaps, 'autofill_triggered', true, 'reconcile', v_recon,
    'note', case when v_gaps=0 then 'Knowledge base complete: 0 empty categories. Taxonomy reconciled ('||coalesce(v_recon->>'cat_prefix_stripped','0')||' prefixes stripped, '||coalesce(v_recon->>'alias_remapped','0')||' aliased).'
                 else 'Triggered background gap-fill for '||v_gaps||' empty category(ies); taxonomy reconciled. Generation runs in the background and logs to agent_runs.' end);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_os_detail(p_entity text, p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_tbl text; v_idcol text := 'id'; v_row jsonb;
begin
  case p_entity
    when 'inquiries' then v_tbl:='inquiries';
    when 'quotes' then v_tbl:='quotes';
    when 'transactions' then v_tbl:='transactions';
    when 'customers' then v_tbl:='customers';
    when 'suppliers' then v_tbl:='leads';
    when 'agent_actions' then v_tbl:='agent_actions';
    when 'doc_reviews' then v_tbl:='doc_reviews';
    when 'kb_revisions' then v_tbl:='kb_revisions';
    when 'inbox' then v_tbl:='inbound_messages';
    when 'documents' then v_tbl:='documents';
    when 'dropbox' then v_tbl:='dropbox_files';
    when 'invoices' then v_tbl:='reveal_invoices'; v_idcol:='transaction_id';
    when 'notifications' then v_tbl:='notifications';
    when 'tasks' then v_tbl:='crm_tasks';
    when 'po' then v_tbl:='po_orders';
    when 'expenses' then v_tbl:='expenses';
    when 'agent_runs' then v_tbl:='agent_runs';
    when 'fraud' then v_tbl:='fraud_flags'; v_idcol:='subject_id';
    else return jsonb_build_object('error','unknown_entity');
  end case;
  execute format('select to_jsonb(t) from %I t where %I::text = %L limit 1', v_tbl, v_idcol, p_id) into v_row;
  if v_row is null then return jsonb_build_object('error','not_found'); end if;
  return jsonb_build_object('entity',p_entity,'record',v_row);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_os_incident_open(p_title text, p_kind text, p_severity text, p_detail jsonb, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE nid bigint;
BEGIN
  IF coalesce(p_title,'')='' THEN RETURN jsonb_build_object('ok',false,'error','title_required'); END IF;
  INSERT INTO public.os_incidents(title, kind, severity, detail, opened_by)
  VALUES (p_title, coalesce(nullif(p_kind,''),'other'), coalesce(nullif(p_severity,''),'medium'), coalesce(p_detail,'{}'::jsonb), coalesce(p_actor,'os'))
  RETURNING id INTO nid;
  INSERT INTO public.os_audit_log(actor,action,entity,entity_id,detail,ok)
  VALUES (coalesce(p_actor,'os'),'incident_open','incident',nid::text,jsonb_build_object('title',p_title,'severity',p_severity),true);
  BEGIN
    PERFORM net.http_post(
      url := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/alert_founder',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('__secret',(select value from public.app_secrets where key='cred_db_internal'),
                                 'event','OS incident #'||nid||' ('||coalesce(p_severity,'medium')||'): '||p_title,
                                 'detail',left(coalesce(p_detail->>'description',''),300),'level','action')
    );
  EXCEPTION WHEN others THEN /* notification is best-effort */ END;
  RETURN jsonb_build_object('ok',true,'id',nid);
END $function$;

CREATE OR REPLACE FUNCTION public.fn_os_list(p_entity text, p_params jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_tbl text; v_cols text; v_search text[]; v_status text; v_order text; v_idcol text := 'id';
  v_q text := coalesce(nullif(trim(p_params->>'q'),''), null);
  v_st text := coalesce(nullif(trim(p_params->>'status'),''), null);
  v_limit int := least(coalesce((p_params->>'limit')::int, 60), 300);
  v_offset int := greatest(coalesce((p_params->>'offset')::int, 0), 0);
  v_where text := ' where true'; v_rows jsonb; v_total bigint; v_sql text; v_fk text; v_fv text;
begin
  case p_entity
    when 'inquiries' then v_tbl:='inquiries'; v_cols:='id,category,emirate,status,pipeline_stage,scope_type,budget,expected_value,rfq_ready,customer_id,hired_supplier_id,outcome,created_at'; v_search:=array['category','emirate','summary','role_needed']; v_status:='status'; v_order:=' order by created_at desc';
    when 'quotes' then v_tbl:='quotes'; v_cols:='id,inquiry_id,supplier_id,quote_amount,customer_price,app_fee,status,review_status,lead_time,warranty,created_at,expires_at'; v_search:=array['notes','scope','payment_terms']; v_status:='status'; v_order:=' order by created_at desc';
    when 'transactions' then v_tbl:='transactions'; v_cols:='id,inquiry_id,supplier_id,customer_id,quote_amount,reveal_fee,app_fee,fee_status,refund_status,revealed_at,payment_ref'; v_search:=array['payment_ref','refund_reason']; v_status:='fee_status'; v_order:=' order by revealed_at desc nulls last';
    when 'customers' then v_tbl:='customers'; v_cols:='id,full_name,email,phone,email_verified,phone_verified,banned,chat_strikes,locale,created_at'; v_search:=array['full_name','email','phone']; v_status:=null; v_order:=' order by created_at desc';
    when 'suppliers' then v_tbl:='leads'; v_cols:='id,company_name,sector,emirate,city,approval_status,verification_status,verified,matching_blocked,banned,rating,app_rating,capability_score,registration_status,contact_name,email,phone,created_at'; v_search:=array['company_name','email','sector','phone']; v_status:='approval_status'; v_order:=' order by created_at desc';
    when 'agent_actions' then v_tbl:='agent_actions'; v_cols:='id,agent,kind,title,status,risk,confidence,target_table,target_id,escalated,created_at,decided_at,decided_by'; v_search:=array['title','recommendation','agent','kind']; v_status:='status'; v_order:=' order by (status=''pending'') desc, created_at desc';
    when 'doc_reviews' then v_tbl:='doc_reviews'; v_cols:='id,from_email,subject,file_name,ai_category,ai_suggested_field,ai_confidence,status,auto_applied,created_at,file_path'; v_search:=array['subject','from_email','file_name','ai_category']; v_status:='status'; v_order:=' order by created_at desc';
    when 'kb_revisions' then v_tbl:='kb_revisions'; v_cols:='id,entry_kind,entry_ref,version,status,author,reviewer,created_at,decided_at'; v_search:=array['entry_ref','entry_kind','author']; v_status:='status'; v_order:=' order by created_at desc';
    when 'inbox' then v_tbl:='inbound_messages'; v_cols:='id,from_email,to_email,subject,ai_category,needs_review,attachments_count,replied_at,created_at'; v_search:=array['subject','from_email','ai_summary']; v_status:='ai_category'; v_order:=' order by created_at desc';
    when 'documents' then v_tbl:='documents'; v_cols:='id,file_name,kind,ref_table,ref_id,mime,status,indexed,bucket,path,created_at'; v_search:=array['file_name','kind','ref_table']; v_status:='status'; v_order:=' order by created_at desc';
    when 'dropbox' then v_tbl:='dropbox_files'; v_cols:='id,path,name,is_folder,size,server_modified,synced_at'; v_search:=array['path','name']; v_status:=null; v_order:=' order by is_folder desc, name asc';
    when 'invoices' then v_tbl:='reveal_invoices'; v_cols:='transaction_id,invoice_no,bucket,path,created_at'; v_search:=array['invoice_no']; v_status:=null; v_order:=' order by created_at desc'; v_idcol:='transaction_id';
    when 'notifications' then v_tbl:='notifications'; v_cols:='id,type,to_email,to_role,subject,status,channel,created_at,sent_at,last_error'; v_search:=array['subject','to_email','type']; v_status:='status'; v_order:=' order by created_at desc';
    when 'tasks' then v_tbl:='crm_tasks'; v_cols:='id,title,status,priority,entity,entity_id,due_date,created_at,done_at'; v_search:=array['title','detail']; v_status:='status'; v_order:=' order by (status<>''done'') desc, due_date asc nulls last';
    when 'notes' then v_tbl:='crm_notes'; v_cols:='id,entity,entity_id,body,author,created_at'; v_search:=array['body','author']; v_status:=null; v_order:=' order by created_at desc';
    when 'po' then v_tbl:='po_orders'; v_cols:='id,po_no,vendor_id,status,subtotal,currency,order_date,expected_date,approved_by,approved_at,created_at'; v_search:=array['po_no','memo']; v_status:='status'; v_order:=' order by created_at desc';
    when 'expenses' then v_tbl:='expenses'; v_cols:='id,vendor,category,description,amount,currency,cadence,expense_date,active,created_at'; v_search:=array['vendor','description','category']; v_status:=null; v_order:=' order by expense_date desc nulls last';
    when 'agent_runs' then v_tbl:='agent_runs'; v_cols:='id,agent,status,started_at,finished_at,note'; v_search:=array['agent','note']; v_status:='status'; v_order:=' order by started_at desc nulls last';
    when 'fraud' then v_tbl:='fraud_flags'; v_cols:='kind,subject_type,subject_id,severity,status,detail,created_at'; v_search:=array['kind','subject_type','subject_id']; v_status:='status'; v_order:=' order by created_at desc'; v_idcol:='subject_id';
    else return jsonb_build_object('error','unknown_entity','entity',p_entity);
  end case;

  if v_st is not null and v_status is not null then v_where := v_where || format(' and %I = %L', v_status, v_st); end if;
  if v_q is not null then
    v_where := v_where || ' and (' || array_to_string(array(select format('coalesce(%I::text,'''') ilike %L', c, '%'||v_q||'%') from unnest(v_search) c), ' or ') || ')';
  end if;
  if p_params ? 'filters' then
    for v_fk, v_fv in select key, value from jsonb_each_text(p_params->'filters') loop
      if v_fk = any(array['inquiry_id','supplier_id','customer_id','quote_id','ref_table','ref_id','agent','entity','entity_id','category','emirate','lead_id','vendor_id','target_table','target_id']) and position(v_fk in v_cols) > 0 and v_fv is not null then
        v_where := v_where || format(' and %I::text = %L', v_fk, v_fv);
      end if;
    end loop;
  end if;

  execute format('select count(*) from %I%s', v_tbl, v_where) into v_total;
  v_sql := format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from (select %s from %I%s%s limit %s offset %s) t', v_cols, v_tbl, v_where, v_order, v_limit, v_offset);
  execute v_sql into v_rows;
  return jsonb_build_object('entity',p_entity,'id_col',v_idcol,'columns',string_to_array(v_cols, ','),'total',v_total,'rows',v_rows);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_os_nav()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'badges', jsonb_build_object(
      'approvals', (select count(*) from agent_actions where status='pending'),
      'tasks', (select count(*) from crm_tasks where coalesce(status,'') <> 'done'),
      'suppliers_review', (select count(*) from leads where coalesce(approval_status,'') in ('submitted','pending','under_review','pending_review')),
      'notifications', (select count(*) from notifications where coalesce(status,'') not in ('sent','delivered','read')),
      'knowledge_review', (select count(*) from kb_revisions where coalesce(status,'')='pending'),
      'documents_review', (select count(*) from doc_reviews where coalesce(status,'')='pending'),
      'disputes', (select count(*) from transactions where coalesce(refund_status,'') in ('requested','pending')),
      'fraud_open', (select count(*) from fraud_flags where coalesce(status,'open') not in ('dismissed','resolved','closed')),
      'rfqs_active', (select count(*) from inquiries where coalesce(status,'') not in ('completed','cancelled','closed'))
    ),
    'generated_at', now()
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_os_selftest()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare tests text[] := array[
  'select public.fn_os_command()',
  'select public.fn_os_nav()',
  'select public.fn_os_dashboard_viz()',
  'select public.fn_os_search(''glass'')',
  'select public.fn_inbox_list()',
  'select public.fn_ws_exec()','select public.fn_ws_marketplace()','select public.fn_ws_customers()',
  'select public.fn_ws_operations()','select public.fn_ws_ai()','select public.fn_ws_knowledge()',
  'select public.fn_ws_documents()','select public.fn_ws_analytics()','select public.fn_ws_company()',
  'select public.fn_ws_finance()','select public.fn_ws_agents()','select public.fn_ws_marketing()',
  'select public.fn_ws_ea()','select public.fn_ws_reports()','select public.fn_ws_strategy()',
  'select public.fn_ws_governance()','select public.fn_ws_fraud()','select public.fn_ws_refunds()',
  'select public.fn_ws_suppliers(''{}''::jsonb)',
  'select public.fn_ws_supplier_360(30305)',
  'select public.fn_ws_agent_ops(''security'')',
  'select public.fn_suppliers_board('''','''',5,0)',
  'select public.fn_rfq_board('''',5,0)',
  'select public.fn_customers_board('''',5,0)',
  'select public.fn_agents_board()',
  'select public.fn_os_record(''supplier'',''30305'')',
  'select public.fn_entity_files(''supplier'',''30372'')',
  'select public.fn_entity_activity(''supplier'',''4299'')',
  'select public.fn_os_health()',
  'select public.fn_os_reconcile()',
  'select public.fn_os_settings_list()',
  'select public.fn_os_automation_list()',
  'select public.fn_os_catalog_list()',
  'select public.fn_os_incident_list('''')',
  'select public.fn_os_runbooks()'
];
r jsonb := '[]'::jsonb; t text; ec text;
begin
  foreach t in array tests loop
    begin execute t; ec := null;
    exception when others then ec := SQLERRM; end;
    r := r || jsonb_build_object('test', split_part(split_part(t,'public.',2),'(',1), 'ok', ec is null, 'err', ec);
  end loop;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_p2c1_fixture_satisfy(p_group bigint, p_ws bigint, p_actor text DEFAULT 'selftest'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rec record; n integer := 0; v_val text;
begin
  for rec in
    select r.field_id, fd.scope, fd.allowed_values
      from public.inquiry_workstream_requirement r
      join public.field_definition fd on fd.field_id = r.field_id
     where r.workstream_id = p_ws and r.mandatory
  loop
    v_val := coalesce(rec.allowed_values[1], 'fixture-value');
    if rec.scope = 'shared' then
      perform public.fn_inquiry_answer_set(p_group, rec.field_id, v_val,
                'customer_confirmed', 'customer', p_actor);
    else
      perform public.fn_inquiry_answer_set(p_group, rec.field_id, v_val,
                'customer_confirmed', 'customer', p_actor, null, array[p_ws]);
    end if;
    n := n + 1;
  end loop;

  insert into public.inquiry_gate (group_id, workstream_id, gate_key, state, asserted_by)
  select p_group, p_ws, gr.gate_key, 'passed'::public.gate_state, p_actor
    from public.inquiry_gate_required gr where gr.level = 'workstream'
  on conflict do nothing;

  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_phase_b_change_request_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  raise exception
    'phase_b_change_request is append-only. % on % is refused. A change request is the audit trail '
    'for a frozen architecture; correcting one means raising the next change request that '
    'supersedes it, so both remain readable.',
    tg_op, coalesce(old.change_request_id, new.change_request_id);
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_phase_b_invariants()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with
-- ---------------------------------------------------------------- declared counts
counts(check_name, expected, actual) as (
  values
    ('count.workflows',            (select (b.counts->>'workflows')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_workflow)),
    ('count.steps',                (select (b.counts->>'steps')::text from public.org_phase_baseline b where b.phase = 'B'), (select count(*)::text from public.phase_b_workflow_step)),
    ('count.handoffs',             (select (b.counts->>'handoffs')::text from public.org_phase_baseline b where b.phase = 'B'), (select count(*)::text from public.phase_b_handoff)),
    ('count.business_objects',     (select (b.counts->>'business_objects')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_business_object)),
    ('count.business_rules',       (select (b.counts->>'business_rules')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_business_rule)),
    ('count.exceptions',           (select (b.counts->>'exceptions')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_exception)),
    ('count.sla_policies',         (select (b.counts->>'sla_policies')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_sla_policy)),
    ('count.gates',                (select (b.counts->>'gates')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_gate)),
    ('count.events',               (select (b.counts->>'events')::text from public.org_phase_baseline b where b.phase = 'B'), (select count(*)::text from public.phase_b_event)),
    ('count.workflow_states',      (select (b.counts->>'workflow_states')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_workflow_state)),
    ('count.workflow_transitions', (select (b.counts->>'workflow_transitions')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_workflow_transition)),
    ('count.step_states',          (select (b.counts->>'step_states')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_step_state)),
    ('count.step_transitions',     (select (b.counts->>'step_transitions')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_step_transition)),
    ('count.founder_boundaries',   (select (b.counts->>'founder_boundaries')::text from public.org_phase_baseline b where b.phase = 'B'),  (select count(*)::text from public.phase_b_founder_boundary)),
    ('count.cross_department_handoffs', (select (b.counts->>'cross_department_handoffs')::text from public.org_phase_baseline b where b.phase = 'B'),
      (select count(*)::text from public.phase_b_handoff where handoff_type = 'cross_department'))
),
-- ------------------------------------------------------------ identity and ownership
owners(check_name, expected, actual) as (
  values
    -- population first: a zero-violation count over an empty table proves nothing
    ('population.steps_with_owner', '257',
      (select count(*)::text from public.phase_b_workflow_step where accountable_role_id <> '')),
    ('identity.unknown_step_owners', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        where s.actor_kind = 'canonical_role'
          and public.fn_phase_b_resolve_role(s.accountable_role_id) is null)),
    ('identity.inactive_step_owners', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        join public.org_role r on r.role_id = s.accountable_role_id
        where s.actor_kind = 'canonical_role' and r.status <> 'active')),
    ('identity.steps_without_owner', '0',
      (select count(*)::text from public.phase_b_workflow_step where coalesce(accountable_role_id,'') = '')),
    -- step_id is the primary key, so a second accountable owner would need a second row
    ('identity.steps_with_multiple_owners', '0',
      (select count(*)::text from (
         select step_id from public.phase_b_workflow_step group by step_id having count(*) > 1) d)),
    ('identity.workflows_without_owner', '0',
      (select count(*)::text from public.phase_b_workflow where coalesce(accountable_role_id,'') = '')),
    ('identity.overlay_accountable_outside_scope', '0',
      (select count(*)::text from public.phase_b_workflow_step
        where actor_kind = 'category_overlay'
          and (workflow_id not in ('W05','W06','W07','W10','W14') or step_type <> 'analysis'))),
    ('identity.dynamic_actor_accountable', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        join public.phase_b_dynamic_actor a on a.actor_token = s.accountable_role_id
        where not a.may_be_accountable))
),
-- ------------------------------------------------------------------------ coverage
role_use as (
  select accountable_role_id role_id from public.phase_b_workflow_step
  union select independent_reviewer_role_id from public.phase_b_workflow_step where independent_reviewer_role_id is not null
  union select unnest(contributors) from public.phase_b_workflow_step
  union select accountable_role_id from public.phase_b_workflow
  union select independent_reviewer_role_id from public.phase_b_workflow where independent_reviewer_role_id is not null
  union select unnest(contributors) from public.phase_b_workflow
  union select detection_owner_role_id from public.phase_b_exception
  union select escalation_owner_role_id from public.phase_b_exception
  union select accountable_role_id from public.phase_b_business_object
),
coverage(check_name, expected, actual) as (
  values
    ('coverage.canonical_roles_total', '90',
      (select count(*)::text from public.org_role
        where status = 'active' and runtime_mode <> 'knowledge_overlay')),
    ('coverage.roles_unrepresented', '0',
      (select count(*)::text from public.org_role r
        where r.status = 'active' and r.runtime_mode <> 'knowledge_overlay'
          and r.role_id not in (select role_id from role_use where role_id is not null))),
    ('coverage.departments_unrepresented', '0',
      (select count(*)::text from public.org_departments d
        where d.active and not exists (
          select 1 from public.org_role r
          where r.primary_department_id = d.dept_key and r.status = 'active'
            and r.role_id in (select role_id from role_use where role_id is not null)))),
    ('coverage.category_overlays_governed', '86',
      (select count(*)::text from public.org_role
        where status = 'active' and runtime_mode = 'knowledge_overlay')),
    ('coverage.workflows_without_steps', '0',
      (select count(*)::text from public.phase_b_workflow w
        where not exists (select 1 from public.phase_b_workflow_step s where s.workflow_id = w.workflow_id))),
    ('coverage.workflows_without_closure_step', '0',
      (select count(*)::text from public.phase_b_workflow w
        where not exists (select 1 from public.phase_b_workflow_step s
                           where s.workflow_id = w.workflow_id and s.is_closure_step))),
    ('coverage.workflows_with_multiple_closure_steps', '0',
      (select count(*)::text from (
         select workflow_id from public.phase_b_workflow_step where is_closure_step
         group by workflow_id having count(*) > 1) d))
),
-- ------------------------------------------------------------------ graph and sequence
graph(check_name, expected, actual) as (
  values
    ('graph.duplicate_workflow_ids', '0',
      (select count(*)::text from (select workflow_id from public.phase_b_workflow group by 1 having count(*)>1) d)),
    ('graph.duplicate_step_ids', '0',
      (select count(*)::text from (select step_id from public.phase_b_workflow_step group by 1 having count(*)>1) d)),
    ('graph.impossible_next_step_references', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        where (s.next_step_if_pass not in ('WORKFLOW_COMPLETE','WORKFLOW_BLOCKED',
                'WORKFLOW_BLOCKED_OR_ESCALATED','CORRECTION_OR_REJECTION_PATH')
               and not exists (select 1 from public.phase_b_workflow_step t where t.step_id = s.next_step_if_pass))
           or (s.next_step_if_fail not in ('WORKFLOW_COMPLETE','WORKFLOW_BLOCKED',
                'WORKFLOW_BLOCKED_OR_ESCALATED','CORRECTION_OR_REJECTION_PATH')
               and not exists (select 1 from public.phase_b_workflow_step t where t.step_id = s.next_step_if_fail)))),
    ('graph.steps_without_inbound_path', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        where s.step_no > 1
          and not exists (select 1 from public.phase_b_workflow_step p
                           where p.workflow_id = s.workflow_id
                             and (p.next_step_if_pass = s.step_id or p.next_step_if_fail = s.step_id)))),
    ('graph.step_numbering_not_dense', '0',
      (select count(*)::text from (
         select workflow_id from public.phase_b_workflow_step
         group by workflow_id
         having max(step_no) <> count(*) or min(step_no) <> 1) d)),
    ('graph.transitions_to_unknown_state', '0', '0'),   -- foreign keys make this structurally impossible
    ('graph.terminal_state_reopened', '0',
      (select count(*)::text from public.phase_b_workflow_transition t
        join public.phase_b_workflow_state f on f.state = t.from_state
        join public.phase_b_workflow_state x on x.state = t.to_state
        where f.terminal and not x.terminal)),
    ('graph.step_state_refs_unknown', '0', '0')          -- foreign keys, as above
),
-- -------------------------------------------------------------------------- handoffs
handoffs(check_name, expected, actual) as (
  values
    ('handoff.owner_change_without_contract', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        join public.phase_b_workflow_step n on n.step_id = s.next_step_if_pass
        where s.accountable_role_id <> n.accountable_role_id
          and not exists (select 1 from public.phase_b_handoff h
                           where h.from_step_id = s.step_id and h.to_step_id = n.step_id))),
    ('handoff.incomplete_packet', '0',
      (select count(*)::text from public.phase_b_handoff
        where coalesce(required_packet,'') = '' or coalesce(receiving_acceptance_criteria,'') = ''
           or coalesce(rejection_condition,'') = '' or coalesce(return_owner_role_id,'') = ''
           or coalesce(closure_condition,'') = '' or coalesce(sla_policy_id,'') = '')),
    ('handoff.role_mismatch_with_steps', '0',
      (select count(*)::text from public.phase_b_handoff h
        join public.phase_b_workflow_step f on f.step_id = h.from_step_id
        join public.phase_b_workflow_step t on t.step_id = h.to_step_id
        where h.sending_role_id <> f.accountable_role_id
           or h.receiving_role_id <> t.accountable_role_id)),
    ('handoff.cross_department_without_sla', '0',
      (select count(*)::text from public.phase_b_handoff
        where handoff_type = 'cross_department' and coalesce(sla_policy_id,'') = '')),
    ('handoff.unknown_sla_reference', '0', '0')          -- foreign key
),
-- ---------------------------------------------------------------- review and authority
authority(check_name, expected, actual) as (
  values
    ('population.steps_with_reviewer', 'gt0',
      (case when (select count(*) from public.phase_b_workflow_step
                   where independent_reviewer_role_id is not null) > 0 then 'gt0' else '0' end)),
    ('authority.creator_reviewer_collisions', '0',
      (select count(*)::text from public.phase_b_workflow_step
        where independent_reviewer_role_id is not null
          and independent_reviewer_role_id = accountable_role_id)),
    ('authority.workflow_owner_reviewer_collisions', '0',
      (select count(*)::text from public.phase_b_workflow
        where independent_reviewer_role_id is not null
          and independent_reviewer_role_id = accountable_role_id)),
    ('authority.exception_escalates_to_its_own_detector', '0',
      (select count(*)::text from public.phase_b_exception
        where escalation_owner_role_id = detection_owner_role_id)),
    ('authority.overlay_with_dispatch_payment_reveal_release', '0',
      (select count(*)::text from public.phase_b_workflow_step
        where actor_kind = 'category_overlay' and workflow_id in ('W12','W15','W16','W17','W24'))),
    -- the supplier onboarding owner may not decide the supplier's own verification
    ('authority.onboarding_approving_own_supplier', '0',
      (select count(*)::text from public.phase_b_workflow_step s
        where s.workflow_id = 'W10' and s.step_type in ('decision','review')
          and s.accountable_role_id = (select accountable_role_id from public.phase_b_workflow where workflow_id = 'W09'))),
    -- the identity that moves the money may not be the identity that reconciles it
    ('authority.payment_executor_reconciles_own_action', '0',
      (select count(*)::text from public.phase_b_workflow_step r
        where r.workflow_id = 'W16' and r.step_type = 'review'
          and r.accountable_role_id in (
            select e.accountable_role_id from public.phase_b_workflow_step e
            where e.workflow_id = 'W16' and e.step_type in ('intake','execution','decision')
              and e.required_output ~* 'payment request|provider event|transaction state'))),
    -- whoever built the release may not issue its own go/no-go
    ('authority.release_decided_by_an_implementer', '0',
      (select count(*)::text from public.phase_b_workflow_step d
        where d.workflow_id = 'W24' and d.step_type = 'decision'
          and d.accountable_role_id in (
            select accountable_role_id from public.phase_b_workflow_step
            where workflow_id = 'W22' and step_type = 'execution'))),
    ('population.founder_boundaries_in_scope', '10',
      (select count(*)::text from public.phase_b_founder_boundary)),
    ('authority.founder_boundary_without_any_gate', '0',
      (select count(*)::text from public.phase_b_founder_boundary b
        where not exists (
          select 1 from public.phase_b_workflow_step s
          where s.founder_gate is not null and lower(s.founder_gate) <> 'none'
            and b.workflow_scope like '%' || s.workflow_id || '%')))
),
-- ------------------------------------------------------------------ business integrity
integrity(check_name, expected, actual) as (
  values
    -- W12 dispatch must sit behind quote readiness, an approved safe package and an approved
    -- supplier.  Readiness is DECIDED in W05 under GATE-011 and consumed by W12 through its
    -- start event, so a check that demanded a gate literally scoped to W12 was measuring
    -- something other than what it names.  What the invariant actually requires is that the
    -- dispatch workflow cannot start without readiness having been established upstream, and
    -- that the gate establishing it exists.  Both halves are asserted.
    ('integrity.dispatch_start_event_requires_quote_ready', '0',
      (select count(*)::text from public.phase_b_workflow
        where workflow_id = 'W12' and start_event !~* 'quote.?ready')),
    ('integrity.quote_readiness_gate_absent_upstream', '0',
      (case when exists (select 1 from public.phase_b_gate
                          where gate_name ~* 'quote.?read'
                            and (workflow_scope like '%W05%' or workflow_scope like '%W12%'))
            then '0' else '1' end)),
    ('integrity.dispatch_start_event_requires_safe_package', '0',
      (select count(*)::text from public.phase_b_workflow
        where workflow_id = 'W12' and start_event !~* 'supplier.?safe')),
    ('integrity.dispatch_without_safe_package_gate', '0',
      (case when exists (select 1 from public.phase_b_gate where workflow_scope like '%W12%'
                          and gate_name ~* 'safe') then '0' else '1' end)),
    ('integrity.dispatch_without_approved_supplier_gate', '0',
      (case when exists (select 1 from public.phase_b_gate where workflow_scope like '%W12%'
                          and gate_name ~* 'supplier') then '0' else '1' end)),
    ('integrity.dispatch_without_idempotency_gate', '0',
      (case when exists (select 1 from public.phase_b_gate where workflow_scope like '%W12%'
                          and gate_name ~* 'idempot') then '0' else '1' end)),
    -- every W12 step must declare an idempotency scope, or "duplicate assignment path = 0"
    -- is a promise nothing keeps
    ('integrity.dispatch_steps_without_idempotency_scope', '0',
      (select count(*)::text from public.phase_b_workflow_step
        where workflow_id = 'W12' and coalesce(idempotency_scope,'') = '')),
    ('integrity.reveal_without_reconciled_payment_gate', '0',
      (case when exists (select 1 from public.phase_b_gate where workflow_scope like '%W15%'
                          and (gate_name ~* 'payment|reveal')) then '0' else '1' end)),
    ('integrity.mutable_accepted_terms_record', '0',
      (select count(*)::text from public.phase_b_business_object
        where object_id ~* 'terms' and record_policy not in ('append_only','append_only_lifecycle','immutable'))),
    ('integrity.mutable_approved_safe_package', '0',
      (select count(*)::text from public.phase_b_business_object
        where object_id ~* 'safe' and record_policy not in ('immutable','immutable_after_approval','append_only'))),
    ('integrity.platform_rewrites_supplier_quotation', '0',
      (select count(*)::text from public.phase_b_business_object
        where object_id ~* 'quotation|quote' and mutation_rule ~* 'platform (may )?(rewrite|edit|alter)'))
),
-- ------------------------------------------------------------------- phase boundaries
boundaries(check_name, expected, actual) as (
  values
    ('phase_a.baseline_drift_rows', '0', (select count(*)::text from public.fn_phase_a_baseline_drift())),
    ('phase_a.organization_violations', '0',
      (select count(*)::text from public.fn_phase_a_organization_violations())),
    ('phase_b.crosswalk_rows_measured', 'gt0',
      (case when (select count(*) from public.phase_b_crosswalk) > 0 then 'gt0' else '0' end)),
    ('phase_b.crosswalk_unclassified', '0',
      (select count(*)::text from public.phase_b_crosswalk where coalesce(target_classification,'') = '')),
    -- Phase B activates nothing.  These read the live estate, not a Phase B table.
    -- the hold is an open circuit with open_until far in the future; 8 routes, all held.
    -- count(*)=0 would make bool_and(...) return null, which is not a pass, so the population
    -- is asserted separately rather than folded into the same expression.
    ('population.llm_routes', '8', (select count(*)::text from public.llm_route_health)),
    ('phase_b.openrouter_routes_still_held', 'true',
      (select case when bool_and(open_until > now()) then 'true' else 'false' end
         from public.llm_route_health)),
    ('phase_b.cron_jobs_created_by_phase_b', '0',
      (select count(*)::text from cron.job where jobname like 'phase_b%'))
)
select c.check_name, c.expected, c.actual,
       case when c.expected = 'gt0' then c.actual = 'gt0' else c.actual = c.expected end
from (
  select * from counts union all select * from owners union all select * from coverage
  union all select * from graph union all select * from handoffs union all select * from authority
  union all select * from integrity union all select * from boundaries
) c
order by 1;
$function$;

CREATE OR REPLACE FUNCTION public.fn_policy_consistency_check()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; f jsonb := '[]'::jsonb; n int := 0; v_admin text; v_crit int := 0;
begin
  for r in select * from policy_rules where active loop
    if r.scope in ('all','site') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','site','location',path))
             from qd_deploy_src where path not like '\_archive/%' and data ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','faq') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','company_faq','location','#'||id||' '||question))
             from company_faq where status='approved' and answer ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','email') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','email','location',key))
             from app_secrets where key in ('invite_body','invite_subject') and value ~* r.forbid_regex), '[]'::jsonb);
    end if;
    if r.scope in ('all','kb') then
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','agent_knowledge','location',agent_key||' / '||topic||' (#'||id||')'))
             from agent_knowledge where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','dept_library','location',department||' / '||title||' (#'||id||')'))
             from dept_library where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','agent_memory','location',agent_key||' / '||kind||' (#'||id||')'))
             from agent_memory where content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','org_memory','location',scope||' / '||kind||' (#'||id||')'))
             from org_memory where active and content ~* r.forbid_regex), '[]'::jsonb);
      f := f || coalesce((select jsonb_agg(jsonb_build_object('rule',r.name,'severity',r.severity,'source','kb_chunks','location',coalesce(category,'?')||' (#'||id||')'))
             from kb_chunks where content ~* r.forbid_regex), '[]'::jsonb);
    end if;
  end loop;
  n := jsonb_array_length(f);
  select count(*) into v_crit from jsonb_array_elements(f) e where e->>'severity'='critical';
  if n > 0 then
    v_admin := coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com');
    if not exists (select 1 from founder_alerts where event='policy_inconsistency' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values(case when v_crit>0 then 'crit' else 'warn' end,'policy_inconsistency',
          n||' policy contradiction(s) found across site, FAQ, email, agent knowledge, library, memories and retrieval chunks: '||left(f::text,600),'system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('policy_inconsistency', v_admin,'admin','email','Policy contradiction detected',
          n||' place(s) now contradict current QuotesDone policy. Scan covers 8 stores incl. kb_chunks retrieval. Details: '||left(f::text,1500),'queued');
    end if;
  end if;
  return json_build_object('findings', n, 'critical', v_crit, 'detail', f, 'checked_at', now());
end $function$;

CREATE OR REPLACE FUNCTION public.fn_policy_lint_kb_chunks()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 select jsonb_build_object('kb_chunks_dirty', count(*)) from kb_chunks k
 where exists (select 1 from policy_rules p where p.active and k.content ~* p.forbid_regex)
$function$;

CREATE OR REPLACE FUNCTION public.fn_provision_category_call(p_raw text, p_lead bigint, p_hint text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text;
begin
  if coalesce(trim(p_raw),'')='' then return; end if;
  select value into v_secret from app_secrets where key='cred_db_internal';
  perform net.http_post(
    url := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/category_provision',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('__secret',v_secret,'raw_category',p_raw,'lead_id',p_lead,'hint_services',coalesce(p_hint,''))
  );
end $function$;

CREATE OR REPLACE FUNCTION public.fn_quote_spec_group(p_category text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    when p_category ~* 'duct.?clean|ac.?duct' then 'acduct'
    when p_category ~* 'facade.?clean|facade cleaning' then 'facade'
    when p_category ~* 'water.?tank' then 'watertank'
    when p_category ~* 'cctv|surveillance|security|access.?control|intercom|alarm' then 'security'
    when p_category ~* 'fire|safety|sprinkler|extinguisher|civil.?defen' then 'fire'
    when p_category ~* 'scaffold' then 'scaffolding'
    when p_category ~* 'demolition|strip.?out' then 'demolition'
    when p_category ~* 'garage.?door|shutter|rolling' then 'shutters'
    when p_category ~* 'elevator|escalator|^lift|lifts' then 'elevators'
    when p_category ~* 'generator' then 'generators'
    when p_category ~* 'solar|photovolt|shams' then 'solar'
    when p_category ~* 'swimming|pool' then 'pools'
    when p_category ~* 'tent|shade|pergola|awning|gazebo' then 'shade'
    when p_category ~* 'landscap|garden|softscape|hardscape|irrigation' then 'landscaping'
    when p_category ~* 'pest' then 'pestcontrol'
    when p_category ~* 'mover|moving|relocation|packing' then 'movers'
    when p_category ~* 'upholstery|curtain|blind|sofa' then 'upholstery'
    when p_category ~* 'wallpaper|wall covering' then 'wallpaper'
    when p_category ~* 'carpet' then 'carpet'
    when p_category ~* 'tiling|tile|marble|granite' then 'tiling'
    when p_category ~* 'floor|spc|vinyl|lvt|epoxy.?floor|parquet|laminate' then 'flooring'
    when p_category ~* 'paint' then 'painting'
    when p_category ~* 'gypsum|false.?ceiling|ceiling|drywall|plasterboard|partition' then 'gypsum'
    when p_category ~* 'waterproof' then 'waterproofing'
    when p_category ~* 'insulation' then 'insulation'
    when p_category ~* 'roofing|^roof|roof ' then 'roofing'
    when p_category ~* 'steel|fabrication' then 'steel'
    when p_category ~* 'masonry|block|^plaster' then 'masonry'
    when p_category ~* 'smart.?home|home.?automation|automation|knx' then 'smarthome'
    when p_category ~* 'av.?system|audio.?visual|audio visual' then 'avsystems'
    when p_category ~* 'network|structured.?cabl' then 'networking'
    when p_category ~* 'signage|sign.?board|3d letter' then 'signage'
    when p_category ~* 'acrylic|perspex|plexiglass' then 'acrylic'
    when p_category ~* 'interior.?design' then 'interiordesign'
    when p_category ~* 'fit.?out' then 'fitout'
    when p_category ~* 'combined.?mep|^mep$|mep' then 'mep'
    when p_category ~* 'glass|glaz|alumin|curtain.?wall|shopfront|balustrad' then 'glazing'
    when p_category ~* 'joinery|kitchen|furniture|carpentr|cabinet|wardrobe|cupboard' then 'joinery'
    when p_category ~* 'hvac|^ac-|air.?con|duct|chiller|cooling|ac.?maintenance' then 'hvac'
    when p_category ~* 'electric|wiring|dewa' then 'electrical'
    when p_category ~* 'plumb|sanitary|drainage' then 'plumbing'
    when p_category ~* 'facade' then 'glazing'
    when p_category ~* 'clean|housekeep' then 'cleaning'
    when p_category ~* 'handyman' then 'handyman'
    when p_category ~* 'facilit|general.?service|miscellaneous|^other|^general' then 'general'
    else null end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_recert_rotate()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_agent text; v_secret text;
begin
  perform fn_onboarding_ingest_runs();
  select agent_key into v_agent from org_onboarding
    order by coalesce(greatest(l1_at,l2_at,l3_at,l4_at), 'epoch'::timestamptz) asc limit 1;
  if v_agent is null then return jsonb_build_object('skipped','no onboarding records'); end if;
  select value into v_secret from app_secrets where key='cred_db_internal';
  perform net.http_post(
    url:='https://' || public.qd_project_ref() || '.supabase.co/functions/v1/canon_eval',
    body:=jsonb_build_object('__secret', v_secret, 'agent', v_agent, 'limit', 8),
    headers:='{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds:=150000);
  return jsonb_build_object('examined', v_agent);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_reconcile_licence_blocks(p_grace_days integer DEFAULT 0)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_suspended int; v_restored int;
begin
  -- Suspend approved, non-banned suppliers whose trade licence is expired (beyond grace),
  -- WITHOUT clobbering manual blocks (only touch rows that are unblocked or already licence-blocked).
  update leads set matching_blocked=true, matching_block_reason='licence_expired'
   where approval_status='approved' and coalesce(banned,false)=false
     and license_expiry is not null
     and license_expiry < (current_date - make_interval(days => p_grace_days))
     and (coalesce(matching_blocked,false)=false or matching_block_reason='licence_expired');
  get diagnostics v_suspended = row_count;
  -- Restore suppliers we auto-blocked once their licence is valid again (renewal-by-reply updates license_expiry).
  update leads set matching_blocked=false, matching_block_reason=null
   where matching_block_reason='licence_expired'
     and (license_expiry is null or license_expiry >= (current_date - make_interval(days => p_grace_days)));
  get diagnostics v_restored = row_count;
  return json_build_object('suspended', v_suspended, 'restored', v_restored, 'grace_days', p_grace_days, 'ran_at', now());
end $function$;

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
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.fn_run_vt()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_secret text; v_files jsonb;
begin
  select value into v_secret from app_secrets where key='cred_db_internal';
  select coalesce(jsonb_agg(jsonb_build_object('bucket', o.bucket_id, 'path', o.name, 'size', coalesce((o.metadata->>'size')::bigint,0))), '[]'::jsonb)
    into v_files
  from (
    select bucket_id, name, metadata, created_at
    from storage.objects
    where bucket_id in ('quote-files','drawing-files','supplier-docs','receipt-files')
      and right(name,1) <> '/'
      and name not in (select path from vt_results where path is not null)
    order by created_at desc
    limit 4
  ) o;
  perform net.http_post(
    url := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/vt_scan',
    body := jsonb_build_object('__secret', v_secret, 'files', v_files),
    headers := '{"Content-Type":"application/json"}'::jsonb
  );
end;$function$;

CREATE OR REPLACE FUNCTION public.fn_scan_new_supplier_categories()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int:=0;
begin
  for r in
    select l.id, l.categories, l.services
    from leads l
    where l.source='self_registered'
      and coalesce(trim(l.categories),'')<>''
      and not exists (select 1 from category_agents a where a.active and a.slug=l.categories)
      -- not already handled: no provisioning card referencing this lead
      and not exists (
        select 1 from agent_actions aa
        where aa.kind='category_knowledge' and (aa.detail->>'lead_id')=l.id::text)
    limit 25
  loop
    perform public.fn_provision_category_call(r.categories, r.id, r.services);
    n := n + 1;
  end loop;
  return jsonb_build_object('ran_at',now(),'dispatched',n);
end $function$;

CREATE OR REPLACE FUNCTION public.fn_schema_export()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with t as (
  select c.relname as rel,
    'CREATE TABLE IF NOT EXISTS public.'||quote_ident(c.relname)||E' (\n'||
    string_agg('  '||quote_ident(a.attname)||' '||format_type(a.atttypid,a.atttypmod)||
      case a.attidentity when 'a' then ' GENERATED ALWAYS AS IDENTITY' when 'd' then ' GENERATED BY DEFAULT AS IDENTITY' else '' end||
      case when a.attgenerated='s' then ' GENERATED ALWAYS AS ('||pg_get_expr(ad.adbin,ad.adrelid)||') STORED'
           when ad.adbin is not null then ' DEFAULT '||pg_get_expr(ad.adbin,ad.adrelid) else '' end||
      case when a.attnotnull then ' NOT NULL' else '' end, E',\n' order by a.attnum)
    ||E'\n);' as tbl_ddl
  from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public'
  join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid=c.oid and ad.adnum=a.attnum
  where c.relkind='r' and not exists(select 1 from pg_depend d where d.objid=c.oid and d.deptype='e')
  group by c.relname
)
select
  '-- QuotesDone — FULL SCHEMA EXPORT (generated from the live database)'||E'\n'
  ||'-- Excludes: secret VALUES (key names listed below), and table ROW DATA (PII).'||E'\n'
  ||'-- Order is best-effort; this is a faithful reference mirror, not a guaranteed one-click restore.'||E'\n\n'
  ||'-- ===== EXTENSIONS =====' ||E'\n'|| coalesce((select string_agg('CREATE EXTENSION IF NOT EXISTS '||quote_ident(extname)||' WITH SCHEMA '||quote_ident(nx.nspname)||';', E'\n' order by extname) from pg_extension e join pg_namespace nx on nx.oid=e.extnamespace),'')
  ||E'\n\n-- ===== SEQUENCES =====\n'|| coalesce((select string_agg('CREATE SEQUENCE IF NOT EXISTS public.'||quote_ident(sequence_name)||';', E'\n' order by sequence_name) from information_schema.sequences where sequence_schema='public'),'')
  ||E'\n\n-- ===== TABLES ('||(select count(*) from t)||') =====\n'|| coalesce((select string_agg(tbl_ddl, E'\n\n' order by rel) from t),'')
  ||E'\n\n-- ===== CONSTRAINTS =====\n'|| coalesce((select string_agg('ALTER TABLE public.'||quote_ident(c.relname)||' ADD CONSTRAINT '||quote_ident(con.conname)||' '||pg_get_constraintdef(con.oid)||';', E'\n' order by case con.contype when 'p' then 1 when 'u' then 2 when 'c' then 3 else 9 end, c.relname) from pg_constraint con join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where con.contype in ('p','u','c','f')),'')
  ||E'\n\n-- ===== INDEXES =====\n'|| coalesce((select string_agg(pg_get_indexdef(i.indexrelid)||';', E'\n' order by ic.relname) from pg_index i join pg_class ic on ic.oid=i.indexrelid join pg_namespace n on n.oid=ic.relnamespace and n.nspname='public' where not exists(select 1 from pg_constraint con where con.conindid=i.indexrelid) and not exists(select 1 from pg_depend d where d.objid=ic.oid and d.deptype='e')),'')
  ||E'\n\n-- ===== VIEWS =====\n'|| coalesce((select string_agg('CREATE OR REPLACE VIEW public.'||quote_ident(viewname)||' AS '||definition, E'\n\n' order by viewname) from pg_views where schemaname='public'),'')
  ||E'\n\n-- ===== FUNCTIONS =====\n'|| coalesce((select string_agg(pg_get_functiondef(p.oid), E'\n\n' order by p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace and n.nspname='public' where p.prokind in ('f','p') and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')),'')
  ||E'\n\n-- ===== TRIGGERS =====\n'|| coalesce((select string_agg(pg_get_triggerdef(tg.oid)||';', E'\n' order by c.relname) from pg_trigger tg join pg_class c on c.oid=tg.tgrelid join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where not tg.tgisinternal),'')
  ||E'\n\n-- ===== ROW LEVEL SECURITY (enable) =====\n'|| coalesce((select string_agg('ALTER TABLE public.'||quote_ident(relname)||' ENABLE ROW LEVEL SECURITY;', E'\n' order by relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace and n.nspname='public' where relkind='r' and relrowsecurity),'')
  ||E'\n\n-- ===== POLICIES =====\n'|| coalesce((select string_agg('CREATE POLICY '||quote_ident(policyname)||' ON public.'||quote_ident(tablename)||' AS '||permissive||' FOR '||cmd||' TO '||array_to_string(roles,', ')||coalesce(' USING ('||qual||')','')||coalesce(' WITH CHECK ('||with_check||')','')||';', E'\n' order by tablename,policyname) from pg_policies where schemaname='public'),'')
  ||E'\n\n-- ===== CRON JOBS =====\n'|| coalesce((select string_agg('select cron.schedule('||quote_literal(jobname)||','||quote_literal(schedule)||',$CRON$'||command||'$CRON$);', E'\n' order by jobid) from cron.job),'')
  ||E'\n\n-- ===== APP_SECRETS KEY NAMES (values intentionally excluded) =====\n'|| coalesce((select string_agg('--   '||key, E'\n' order by key) from public.app_secrets),'')
  ||E'\n'
$function$;

CREATE OR REPLACE FUNCTION public.fn_scope_detect(p_group_id bigint, p_customer_text text, p_actor text DEFAULT 'system'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_norm text := public.fn_norm_text(p_customer_text);
  cl record; m record;
  v_exc_pos int; v_base text; v_base_marker text; v_base_res text; v_pos int;
  v_umbrella boolean; v_umb_pos int;
  v_comps text[]; v_comp text; v_n integer := 0;
  v_trades jsonb; v_tk text; v_tpos int; v_disp text; v_spec int;
  v_active_trades text[];
  v_party jsonb; v_supply jsonb; v_basis text;
  v_pty text; v_pcls text; v_prole text; v_pidx int;
  v_cdisp text; v_cbasis text; v_epty text; v_epcls text; v_eprole text;
  v_why text;
begin
  for cl in select * from public.fn_scope_clause_map(v_norm) loop
    v_exc_pos := null;
    for m in select pattern_norm, lang from public.scope_marker where marker_type = 'exception' loop
      v_pos := public.fn_term_position(cl.clause, m.pattern_norm, m.lang);
      if v_pos > 0 and (v_exc_pos is null or v_pos < v_exc_pos) then v_exc_pos := v_pos; end if;
    end loop;

    v_base := null; v_base_marker := null; v_base_res := 'fixed';
    for m in select disposition, pattern_norm, lang, priority, resolution from public.scope_marker
              where marker_type = 'disposition' order by priority, length(pattern_norm) desc loop
      v_pos := public.fn_term_position(cl.clause, m.pattern_norm, m.lang);
      if v_pos > 0 and (v_exc_pos is null or v_pos < v_exc_pos) then
        v_base := m.disposition; v_base_marker := m.pattern_norm; v_base_res := m.resolution; exit;
      end if;
    end loop;

    -- who, and whether material comes from the buying side. Clause-scoped, both of them.
    v_party  := public.fn_scope_party(cl.clause);
    v_supply := public.fn_scope_supply_attribution(cl.clause);
    v_pty := null; v_pcls := null; v_prole := null; v_pidx := null;
    if coalesce((v_party->>'identified')::boolean, false) then
      v_pty   := v_party->>'party';      v_pcls  := v_party->>'party_class';
      v_prole := v_party->>'role';       v_pidx  := cl.idx;
    end if;

    v_basis := 'fixed_marker';
    if v_base is not null and v_base_res = 'party_dependent' then
      if coalesce((v_party->>'identified')::boolean, false) then
        v_base := 'by_others'; v_basis := 'removal_attributed';
      else
        v_base := 'excluded';  v_basis := 'removal_unattributed';
      end if;
    elsif v_base = 'excluded' and coalesce((v_party->>'identified')::boolean, false) then
      v_base := 'by_others'; v_basis := 'excluded_upgraded_to_by_others';
    elsif v_base in ('by_others','client_supplied') and v_pty is null then
      v_prole := 'inline_marker';
    end if;

    select coalesce(array_agg(distinct m2.component), '{}') into v_comps
      from public.scope_marker m2
     where m2.marker_type = 'component'
       and public.fn_term_matches(cl.clause, m2.pattern_norm, m2.lang);

    -- "free issue by the employer" carries no component word, but it is unmistakably about supply.
    if coalesce((v_supply->>'matched')::boolean, false) and not ('supply' = any(v_comps)) then
      v_comps := array_append(v_comps, 'supply'::text);
    end if;

    select coalesce(bool_or(public.fn_term_position(cl.clause, p.pattern_norm, p.lang) > 0), false),
           min(nullif(public.fn_term_position(cl.clause, p.pattern_norm, p.lang), 0))
      into v_umbrella, v_umb_pos
      from public.mep_trade_pattern p where p.kind in ('mep_anchor','mep_full_phrase');

    select coalesce(jsonb_object_agg(z.tk, z.p), '{}'::jsonb) into v_trades
      from (
        select t.trade_key as tk, min(t.pos) as p
          from (
            select p.trade_key, public.fn_term_position(cl.clause, p.pattern_norm, p.lang) as pos
              from public.mep_trade_pattern p
             where p.kind in ('trade_name','trade_hint') and p.trade_key is not null
            union all
            select c.trade_key,
                   public.fn_term_position(cl.clause, public.fn_norm_text(e.matched_term), 'en')
              from public.inquiry_trade_candidate c
              join public.inquiry_trade_candidate_evidence e on e.candidate_id = c.id
             where c.group_id = p_group_id and e.matched_term is not null
               and e.evidence_source in ('alias','customer_text')
               and length(e.matched_term) >= 3
          ) t
         where t.pos > 0
         group by t.trade_key
      ) z;

    if v_base is null and (v_umbrella or v_trades <> '{}'::jsonb) then
      v_base := 'included'; v_basis := 'clause_default'; end if;
    if v_base is null then continue; end if;

    foreach v_comp in array (case when cardinality(v_comps) = 0
                                  then array['complete_trade_scope'] else v_comps end) loop
      if v_comp = 'supply' and coalesce((v_supply->>'matched')::boolean, false) then
        v_cdisp := 'client_supplied'; v_cbasis := 'supply_attributed_counterparty';
        v_epty  := v_supply->>'party'; v_epcls := v_supply->>'party_class';
        v_eprole := v_supply->>'role';
      else
        v_cdisp := null; v_cbasis := v_basis;
        v_epty  := v_pty; v_epcls := v_pcls; v_eprole := v_prole;
      end if;

      v_why := case v_cbasis
        when 'removal_unattributed' then ' The clause removes this scope from us and identifies no other responsible party, so it is excluded rather than by others.'
        when 'removal_attributed' then ' The clause removes this scope from us and identifies "' || coalesce(v_epty,'?') || '" (' || coalesce(v_epcls,'?') || ', ' || coalesce(v_eprole,'?') || ') as responsible, so it is by others.'
        when 'excluded_upgraded_to_by_others' then ' Exclusion language with an identified responsible party "' || coalesce(v_epty,'?') || '", so it is by others rather than excluded.'
        when 'supply_attributed_counterparty' then ' Supply is attributed to the counterparty "' || coalesce(v_epty,'?') || '" (' || coalesce(v_eprole,'?') || '), so the supply component is client supplied. Work retained by us on this trade is unaffected.'
        else '' end;

      for v_tk, v_tpos in select key, value::int from jsonb_each_text(v_trades) loop
        v_disp := coalesce(v_cdisp,
                    case when v_exc_pos is not null and v_tpos > v_exc_pos
                         then public.fn_scope_inverse(v_base) else v_base end);
        v_spec := 2 + (case when v_comp = 'complete_trade_scope' then 0 else 1 end);
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor,
           classification_basis, responsible_party, party_class, party_role, party_clause_index,
           sentence_index)
        values (p_group_id, v_tk, v_comp, v_disp, v_spec, 'customer_text', 'customer_text', 0.950,
                cl.idx, cl.clause, v_base_marker,
                'Clause ' || cl.idx || ' names this trade' ||
                  case when v_comp <> 'complete_trade_scope' then ' and the ' || v_comp || ' component' else '' end ||
                  case when v_cdisp is null and v_exc_pos is not null and v_tpos > v_exc_pos
                       then ', after an exception marker, so the clause disposition is inverted' else '' end ||
                  '. Marker: ' || coalesce(v_base_marker,'(none - default included)') || '.' || v_why,
                p_actor, v_cbasis, v_epty, v_epcls, v_eprole,
                case when v_epty is null then null else cl.idx end, cl.sentence_idx);
        v_n := v_n + 1;
      end loop;

      if v_umbrella then
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor,
           classification_basis, responsible_party, party_class, party_role, party_clause_index,
           sentence_index)
        select p_group_id, t.trade_key, v_comp,
               coalesce(v_cdisp,
                 case when v_exc_pos is not null and v_umb_pos > v_exc_pos
                      then public.fn_scope_inverse(v_base) else v_base end),
               (case when v_comp = 'complete_trade_scope' then 0 else 1 end),
               'customer_text','customer_text', 0.900, cl.idx, cl.clause, v_base_marker,
               'Clause ' || cl.idx || ' uses an MEP umbrella term' ||
                 case when v_comp <> 'complete_trade_scope' then ' with the ' || v_comp || ' component' else '' end ||
                 '. Applied to the core trades at umbrella specificity, so any named-trade instruction outranks it. Marker: '
                 || coalesce(v_base_marker,'(none - default included)') || '.' || v_why, p_actor,
               v_cbasis, v_epty, v_epcls, v_eprole,
               case when v_epty is null then null else cl.idx end, cl.sentence_idx
          from public.mep_trade t where t.is_core and not (v_trades ? t.trade_key);
        v_n := v_n + (select count(*) from public.mep_trade t where t.is_core and not (v_trades ? t.trade_key));
      end if;

      if not v_umbrella and v_trades = '{}'::jsonb and v_comp <> 'complete_trade_scope' then
        select coalesce(array_agg(distinct c.trade_key), '{}') into v_active_trades
          from public.inquiry_trade_candidate c
         where c.group_id = p_group_id and c.status in ('confirmed','proposed');
        insert into public.inquiry_scope_disposition
          (group_id, trade_key, scope_component, disposition, specificity, source_kind,
           evidence_source, evidence_score, clause_index, clause_text, matched_marker, reason, actor,
           classification_basis, responsible_party, party_class, party_role, party_clause_index,
           sentence_index)
        select p_group_id, t, v_comp, coalesce(v_cdisp, v_base), 1, 'customer_text','customer_text', 0.900,
               cl.idx, cl.clause, v_base_marker,
               'Clause ' || cl.idx || ' names the ' || v_comp || ' component with no trade, so it applies to the trades already in play.' || v_why,
               p_actor, v_cbasis, v_epty, v_epcls, v_eprole,
               case when v_epty is null then null else cl.idx end, cl.sentence_idx
          from unnest(v_active_trades) t;
        v_n := v_n + coalesce(cardinality(v_active_trades),0);
      end if;
    end loop;
  end loop;

  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_security_scan()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_run bigint; v_scanned int := 0; v_susp int := 0; v_high int := 0; v_viol int; v_banned int; v_owner text;
  r record; v_path text; v_sev text; v_why text; v_size bigint; v_mime text;
begin
  insert into agent_runs(agent, started_at) values ('security', now()) returning id into v_run;
  for r in
    select bucket_id, name, coalesce((metadata->>'size')::bigint,0) as size, coalesce(metadata->>'mimetype','') as mime
    from storage.objects
    where bucket_id in ('quote-files','drawing-files','supplier-docs')   -- receipt-files removed: system/owner-generated, not a threat surface
    order by created_at desc limit 400
  loop
    v_path := r.name; if v_path is null or v_path = '' or right(v_path,1) = '/' then continue; end if;
    v_scanned := v_scanned + 1; v_size := r.size; v_mime := r.mime; v_sev := null; v_why := null;
    if v_path ~* '\.[a-z0-9]{2,5}\.(exe|js|scr|bat|html?|svg|hta)$' then v_sev := 'high'; v_why := 'double extension';
    elsif v_path ~* '\.(exe|bat|cmd|com|scr|msi|ps1|vbs|js|jar|sh|apk|dll|hta|wsf|docm|xlsm|pptm|iso|img)$' then v_sev := 'high'; v_why := 'dangerous file type';
    elsif v_path ~* '\.(html?|svg)$' then v_sev := 'high'; v_why := 'active-content file';
    elsif v_size > 30*1024*1024 then v_sev := 'medium'; v_why := 'oversized';
    end if;
    -- dedupe: only flag a file the FIRST time it is seen
    if v_sev is not null and not exists (select 1 from security_events se where se.kind='suspicious_upload' and se.subject=left(v_path,200)) then
      v_susp := v_susp + 1;
      insert into security_events(kind,severity,source,subject,detail) values ('suspicious_upload',v_sev,r.bucket_id,left(v_path,200),jsonb_build_object('mime',v_mime,'size',v_size,'why',v_why));
      if v_sev = 'high' then
        v_high := v_high + 1;
        insert into agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
        values ('security','security_alert','pending','high','Suspicious upload ('||v_why||'): '||left(v_path,80),'inspect/remove the file in storage; do NOT open it directly','security_events',jsonb_build_object('bucket',r.bucket_id,'path',v_path,'why',v_why,'size',v_size));
      end if;
    end if;
  end loop;
  select count(*) into v_viol from chat_violations where created_at >= now()-interval '7 days';
  select (select count(*) from leads where banned=true)+(select count(*) from customers where banned=true) into v_banned;
  if v_viol > 0 then insert into security_events(kind,severity,source,subject,detail) values ('contact_disclosure','medium','chat',v_viol||' contact-sharing attempt(s) in 7d',jsonb_build_object('count',v_viol)); end if;
  if v_susp > 0 then
    select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
    insert into notifications(type,to_email,to_role,channel,subject,body) values ('security_alert',coalesce(v_owner,'management@quotesdone.com'),'admin','email','QuotesDone security: '||v_susp||' suspicious file(s) flagged','The Security agent flagged '||v_susp||' newly uploaded file(s) ('||v_high||' high-severity). Open the Security agent in admin. Do not open flagged files directly.');
  end if;
  update agent_runs set finished_at=now(), status='ok', counts=jsonb_build_object('scanned',v_scanned,'suspicious',v_susp,'high',v_high,'violations7d',v_viol,'banned',v_banned) where id=v_run;
end;$function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_autoapprove_clean(p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare v_ids bigint[]; v_approved int := 0; v_scanned int; r record;
begin
  -- how many genuine applicants are waiting a decision (for reporting)
  select count(*) into v_scanned from leads
    where approval_status in ('pending','submitted') and coalesce(banned,false)=false;

  -- pick the fully-clean ones
  select array_agg(id) into v_ids from (
    select id from leads
    where approval_status in ('pending','submitted')
      and coalesce(banned,false) = false
      and registration_submitted_at is not null
      and license_doc_path is not null          -- trade licence uploaded
      and doc_extracted_at is not null           -- OCR has run on the docs
      and trade_license_no is not null and length(trade_license_no) > 3   -- licence number extracted
      and license_expiry is not null and license_expiry > current_date + 30  -- valid, not near expiry
      and coalesce(owner_email_verified,false) = true                         -- verified contact
    order by registration_submitted_at
    limit greatest(1, coalesce(p_limit,25))
  ) z;

  if v_ids is null then
    return jsonb_build_object('approved',0,'candidates_scanned',v_scanned,'note','No licence-OCR-clean applicants to auto-approve; any remaining applicants need manual review.');
  end if;

  for r in select id, company_name, coalesce(claimed_by,email) as contact from leads where id = any(v_ids) loop
    update leads set approval_status='approved', verified=true, verification_status='verified',
      lifecycle_stage='active', approved_at=now(), approval_decided_by='chief_of_staff (auto)'
      where id = r.id;
    if r.contact is not null then
      insert into notifications(type,to_email,to_role,lead_id,channel,subject,body)
      values('registration_approved', r.contact, 'supplier', r.id, 'email',
        'You''re verified on QuotesDone',
        'Good news — '||coalesce(r.company_name,'your company')||' has been verified on QuotesDone (trade licence checks passed). You can now receive inquiries and quote: https://quotesdone.com/suppliers/');
    end if;
    v_approved := v_approved + 1;
  end loop;

  return jsonb_build_object('approved',v_approved,'candidates_scanned',v_scanned,'approved_ids',v_ids,
    'note','Auto-approved '||v_approved||' licence-OCR-clean supplier(s); '||(v_scanned - v_approved)||' applicant(s) left for manual review.');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_expiries(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with l as (select * from leads where id=p_supplier_id)
  select coalesce(jsonb_agg(e order by (e->>'days_left')::int), '[]'::jsonb) from (
    select jsonb_build_object('doc',d.label,'expiry',d.exp,
      'days_left',(d.exp - current_date),
      'status', case when d.exp < current_date then 'expired'
                     when d.exp <= current_date + 30 then 'expiring'
                     when d.exp <= current_date + 90 then 'soon' else 'ok' end) e
    from l, lateral (values
      ('Trade license', l.license_expiry),
      ('ISO certification', l.iso_expiry),
      ('Insurance', l.insurance_expiry),
      ('Manufacturer authorization', l.manufacturer_auth_expiry)
    ) as d(label,exp)
    where d.exp is not null
  ) q;
$function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_stats(p_supplier_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v jsonb; v_quotes int; v_reveals int; v_hired int; v_lost int;
  v_qd_rev numeric; v_deal_val numeric; v_avg_lead numeric;
  v_pos jsonb; v_hist jsonb; v_rating numeric; v_rating_pct numeric; v_resp numeric;
  v_pending_reviews int; v_active_rfqs int;
begin
  select count(*) into v_quotes from quotes where supplier_id=p_supplier_id;
  select count(*) into v_reveals from transactions where supplier_id=p_supplier_id;
  select count(*) into v_hired from inquiries where hired_supplier_id=p_supplier_id;
  select count(*) into v_lost from inquiries i
     where i.hired_supplier_id is not null and i.hired_supplier_id<>p_supplier_id
       and exists (select 1 from quotes q where q.inquiry_id=i.id and q.supplier_id=p_supplier_id);
  select coalesce(sum(coalesce(reveal_fee,0)+coalesce(app_fee,0)),0),
         coalesce(sum(coalesce(quote_amount,0)),0)
    into v_qd_rev, v_deal_val
    from transactions where supplier_id=p_supplier_id and coalesce(refund_status,'')<>'approved';
  select round(avg(nullif(regexp_replace(coalesce(lead_time,''),'[^0-9.]','','g'),'')::numeric),1)
    into v_avg_lead from quotes where supplier_id=p_supplier_id and lead_time ~ '[0-9]';
  select coalesce(app_rating,rating), rv_response_rate into v_rating, v_resp from leads where id=p_supplier_id;
  select round(100.0*(count(*) filter (where coalesce(l2.app_rating,l2.rating,0) <= coalesce(v_rating,0)))/nullif(count(*),0),0)
    into v_rating_pct
    from leads l2 where l2.sector = (select sector from leads where id=p_supplier_id) and coalesce(l2.app_rating,l2.rating) is not null;
  select count(*) into v_pending_reviews from quotes where supplier_id=p_supplier_id and coalesce(review_status,'')='pending';
  select count(distinct q.inquiry_id) into v_active_rfqs from quotes q join inquiries i on i.id=q.inquiry_id
    where q.supplier_id=p_supplier_id and coalesce(i.status,'') in ('open','active','collecting','live');
  with myq as (select inquiry_id, quote_amount from quotes where supplier_id=p_supplier_id and quote_amount is not null and quote_amount>0),
  peer as (select inquiry_id, min(quote_amount) lo, avg(quote_amount) av, count(*) n
             from quotes where quote_amount is not null and quote_amount>0 group by inquiry_id),
  pos as (select m.quote_amount, p.lo, p.av,
                 case when p.lo>0 then (m.quote_amount-p.lo)/p.lo*100 end pct_low,
                 case when p.av>0 then (m.quote_amount-p.av)/p.av*100 end pct_avg,
                 (m.quote_amount<=p.lo*1.0001) as is_lowest
            from myq m join peer p using(inquiry_id) where p.n>=2)
  select jsonb_build_object('competitive_rfqs', count(*),'times_lowest', count(*) filter (where is_lowest),
    'lowest_rate', round(100.0*count(*) filter (where is_lowest)/nullif(count(*),0),0),
    'avg_pct_above_lowest', round(avg(pct_low)::numeric,1),'avg_pct_vs_average', round(avg(pct_avg)::numeric,1),
    'band', case when count(*)=0 then 'not enough data' when avg(pct_avg) <= -4 then 'below market average'
                 when avg(pct_avg) < 5 then 'around market average' else 'above market average' end
  ) into v_pos from pos;
  with months as (select date_trunc('month', (now() - (n||' month')::interval)) m from generate_series(0,11) n),
  qb as (select date_trunc('month',created_at) m, count(*) c from quotes where supplier_id=p_supplier_id group by 1),
  rb as (select date_trunc('month',revealed_at) m, count(*) c from transactions where supplier_id=p_supplier_id group by 1)
  select jsonb_agg(jsonb_build_object('month', to_char(months.m,'Mon YY'),'quotes', coalesce(qb.c,0), 'reveals', coalesce(rb.c,0)) order by months.m)
    into v_hist from months left join qb on qb.m=months.m left join rb on rb.m=months.m;
  v := jsonb_build_object('supplier_id', p_supplier_id,'quotes_total', v_quotes,'reveals', v_reveals,'hired', v_hired,
    'lost_to_others', v_lost,'win_ratio', round(100.0*v_hired/nullif(v_quotes,0),1),'reveal_ratio', round(100.0*v_reveals/nullif(v_quotes,0),1),
    'qd_revenue', v_qd_rev,'deal_value_awarded', v_deal_val,'avg_lead_time_days', v_avg_lead,'rating', v_rating,
    'rating_percentile', v_rating_pct,'response_rate', v_resp,'pending_reviews', v_pending_reviews,'active_rfqs', v_active_rfqs,
    'price_positioning', v_pos,'history_12m', v_hist,'document_expiries', fn_supplier_expiries(p_supplier_id));
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_supply_health()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; s timestamptz := now()-interval '30 days'; v_total int; v_matched int; v_quoted int; v_nosupply int; v_ttfq numeric; v_fill numeric; v_owner text; v_gaps jsonb; v_gapcount int;
begin
  insert into agent_runs(agent,started_at) values('supply_health',now()) returning id into v_run;
  select count(*) into v_total from inquiries where created_at>=s;
  select count(*) into v_matched from inquiries i where i.created_at>=s and exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  select count(*) into v_quoted from inquiries i where i.created_at>=s and exists(select 1 from quotes q where q.inquiry_id=i.id);
  select count(*) into v_nosupply from inquiries i where i.created_at>=s and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  v_fill := case when v_total>0 then round(v_quoted::numeric/v_total,3) else null end;
  select round(percentile_cont(0.5) within group (order by extract(epoch from (fq.first_q - i.created_at))/3600)::numeric,1)
    into v_ttfq
    from inquiries i join lateral (select min(q.created_at) first_q from quotes q where q.inquiry_id=i.id) fq on true
    where i.created_at>=s and fq.first_q is not null;
  -- coverage gaps: categories with >=3 inquiries in 30d and quote-rate < 50%
  select coalesce(jsonb_agg(g),'[]'::jsonb), count(*) into v_gaps, v_gapcount from (
    select i.category,
      count(*) as inquiries,
      count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id)) as quoted,
      round(count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id))::numeric/count(*),2) as quote_rate
    from inquiries i where i.created_at>=s and i.category is not null
    group by i.category
    having count(*)>=3 and count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id))::numeric/count(*) < 0.5
    order by count(*) desc limit 20
  ) g;
  insert into supply_health_snapshots(period_end,metrics) values (current_date,
    jsonb_build_object('inquiries_30d',v_total,'matched',v_matched,'quoted',v_quoted,'no_supply',v_nosupply,'fill_rate',v_fill,'median_hours_to_first_quote',v_ttfq,'coverage_gaps',v_gaps));
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  -- queue a report for the Follow-up agent when health is weak
  if v_total>=5 and (coalesce(v_fill,0) < 0.5 or v_gapcount>0 or v_nosupply>0) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table)
      values('followup','supply_health','pending','medium',
        'Supply health: '||coalesce(round(v_fill*100)::text,'?')||'% of requests got a quote (30d)',
        'Source/activate suppliers in low-coverage categories; '||v_nosupply||' request(s) had no supplier match.',
        jsonb_build_object('fill_rate',v_fill,'no_supply',v_nosupply,'median_hours_to_first_quote',v_ttfq,'gaps',v_gaps),'inquiries');
    if v_owner is not null then
      insert into notifications(type,to_email,to_role,channel,subject,body)
        values('supply_health',v_owner,'admin','email','QuotesDone supply-health alert',
          'In the last 30 days: '||v_total||' requests, '||coalesce(round(v_fill*100)::text,'?')||'% received a quote, '||v_nosupply||' had no matched supplier, median time-to-first-quote '||coalesce(v_ttfq::text,'n/a')||'h, '||v_gapcount||' low-coverage categor(ies). Open the Secretary or Follow-up agent for the breakdown.');
    end if;
  end if;
  update agent_runs set finished_at=now(),status='ok',counts=jsonb_build_object('inquiries_30d',v_total,'fill_rate',v_fill,'no_supply',v_nosupply,'gaps',v_gapcount) where id=v_run;
end; $function$;

CREATE OR REPLACE FUNCTION public.fn_watch_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_score numeric;
  v_at_risk text;
  v_secret text;
begin
  select overall_score_measurable into v_score from v_business_health;
  select string_agg(department || ' ' || score || '% (' || basis || ')', E'\n')
    into v_at_risk from v_department_health where status = 'at risk';

  if v_at_risk is not null then
    select value into v_secret from app_secrets where key='cred_db_internal';
    perform net.http_post(
      url := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/alert_founder',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := jsonb_build_object(
        '__secret', v_secret,
        'event', 'Business health ' || v_score || '% - department(s) at risk',
        'detail', v_at_risk,
        'level', 'warn',
        'dedupe_key', 'health:' || to_char(now(),'YYYY-MM-DD')
      ),
      timeout_milliseconds := 20000);
  end if;
  return jsonb_build_object('score', v_score, 'at_risk', coalesce(v_at_risk,'none'));
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ws_rfq_360(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare i public.inquiries%rowtype; j jsonb; docs jsonb := '[]'::jsonb; hired text;
begin
  select * into i from public.inquiries where id=p_id;
  if i.id is null then return jsonb_build_object('error','RFQ not found'); end if;
  if i.drawing_file_path is not null then docs := docs || jsonb_build_object('type','Drawing','name',coalesce(i.drawing_file_name,'drawing'),'path',i.drawing_file_path); end if;
  if i.drawing_redacted_paths is not null then
    docs := docs || coalesce((select jsonb_agg(jsonb_build_object('type','Drawing (redacted)','name','redacted','path',x)) from unnest(i.drawing_redacted_paths) x),'[]'::jsonb);
  end if;
  select company_name into hired from public.leads where id=i.hired_supplier_id;
  j := jsonb_build_object(
    'requirements', jsonb_build_object('category',i.category,'emirate',i.emirate,'role_needed',i.role_needed,
       'summary',i.summary,'spec',i.spec,'boq',i.boq,'boq_confidence',i.boq_confidence,'budget',i.budget,
       'scope_type',i.scope_type,'trades',i.trades,'keywords',i.keywords),
    'status', jsonb_build_object('status',i.status,'pipeline_stage',i.pipeline_stage,'deal_owner',i.deal_owner,
       'expected_value',i.expected_value,'outcome',i.outcome,'lost_reason',i.lost_reason,'completed_at',i.completed_at,
       'project_id',i.project_id,'created_at',i.created_at),
    'ai_qualification', jsonb_build_object('completeness',i.completeness,'rfq_ready',i.rfq_ready,'routing',i.routing,'brief_source',i.brief_source),
    'selected_supplier', case when i.hired_supplier_id is not null then jsonb_build_object('id',i.hired_supplier_id,'company_name',hired) else null end,
    'documents', docs,
    'matching', coalesce((select jsonb_agg(jsonb_build_object('supplier_id',m.supplier_id,'company_name',l.company_name,
       'similarity',m.similarity,'match_reason',m.match_reason,'sent_at',m.sent_at) order by m.similarity desc nulls last)
       from public.inquiry_matches m left join public.leads l on l.id=m.supplier_id where m.inquiry_id=p_id),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'supplier_id',q.supplier_id,'company_name',l.company_name,
       'amount',q.quote_amount,'status',q.status,'lead_time',q.lead_time,'validity',q.validity,'quality',q.quality,
       'created_at',q.created_at) order by q.quote_amount asc nulls last)
       from public.quotes q left join public.leads l on l.id=q.supplier_id where q.inquiry_id=p_id),'[]'::jsonb),
    'procurement', public.fn_procurement_analysis(p_id),
    'clarifications', coalesce((select jsonb_agg(jsonb_build_object('question',qn.question,'answer',qn.answer,
       'supplier_id',qn.supplier_id,'asked_at',qn.asked_at,'answered_at',qn.answered_at) order by qn.asked_at desc)
       from public.questions qn where qn.inquiry_id=p_id),'[]'::jsonb),
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',i.created_at,'event','RFQ created') e
        union all select jsonb_build_object('at',m.sent_at,'event','Matched supplier') from public.inquiry_matches m where m.inquiry_id=p_id and m.sent_at is not null
        union all select jsonb_build_object('at',q.created_at,'event','Quote received: AED '||coalesce(q.quote_amount::text,'?')) from public.quotes q where q.inquiry_id=p_id
        union all select jsonb_build_object('at',i.completed_at,'event','Completed'||coalesce(' ('||i.outcome||')','')) where i.completed_at is not null
      ) tl)
  );
  return j;
end $function$;

CREATE OR REPLACE FUNCTION public.hook_password_verification_attempt(event jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_uid uuid; v_valid boolean; v_email text; v_recent int;
begin
  begin v_uid := (event->>'user_id')::uuid; exception when others then v_uid := null; end;
  v_valid := coalesce((event->>'valid')::boolean, true);
  if not v_valid then
    begin select email into v_email from auth.users where id = v_uid; exception when others then v_email := null; end;
    select count(*) into v_recent from public.security_events
      where kind='login_failed' and subject = coalesce(v_email,'')
        and created_at > now() - interval '15 minutes';
    insert into public.security_events(kind, severity, source, subject, detail)
    values ('login_failed',
            case when v_recent >= 4 then 'high' else 'medium' end,
            'password',
            coalesce(v_email,''),
            jsonb_build_object('user_id', v_uid, 'recent_15m', v_recent + 1,
                               'why', 'password verification failed'));
  end if;
  return '{}'::jsonb;
end $function$;

CREATE OR REPLACE FUNCTION public.mask_contact(s text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when s is null then s else
    regexp_replace(
    regexp_replace(
    regexp_replace(
    regexp_replace(s,
      '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[hidden until reveal]', 'gi'),
      '(https?://|www\.)[^[:space:]]+', '[hidden until reveal]', 'gi'),
      '\y[[:alnum:]-]{2,}\.(com|ae|net|org|io|me)\y', '[hidden until reveal]', 'gi'),
      '(\+?971|00971|0)[[:space:].-]?[0-9]{1,2}[[:space:].-]?[0-9]{3}[[:space:].-]?[0-9]{4}', '[hidden until reveal]', 'gi')
  end
$function$;

CREATE OR REPLACE FUNCTION public.qd_recompute_response()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  with stats as (
    select t.supplier_id, count(*) as reveals,
      count(*) filter (where t.supplier_ack_at is not null
        or exists(select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
        or exists(select 1 from inquiries i where i.id=t.inquiry_id and i.hired_supplier_id=t.supplier_id)
        or (t.refund_status is null and t.revealed_at < now()-interval '7 days')) as responded
    from transactions t where t.revealed_at is not null group by t.supplier_id
  )
  update leads l set rv_reveals=s.reveals, rv_responded=s.responded,
    rv_response_rate=case when s.reveals>0 then round(s.responded::numeric/s.reveals,3) else null end
  from stats s where s.supplier_id=l.id;
end $function$;

CREATE OR REPLACE FUNCTION public.qd_reveal_nudges()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare base text := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/supplier_ack';
begin
  with due as (
    select t.id, t.inquiry_id, t.supplier_id, t.ack_token, l.email, coalesce(l.locale,'en') as locale
    from transactions t join leads l on l.id=t.supplier_id
    where t.revealed_at is not null and t.revealed_at < now()-interval '24 hours'
      and t.nudged_24_at is null and coalesce(t.fee_status,'')='paid' and t.refund_status is null and t.supplier_ack_at is null
      and not exists (select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
      and l.email ~ '@'
  ), ins as (
    insert into notifications(type,to_email,to_role,inquiry_id,subject,body)
    select 'supplier_nudge', d.email, 'supplier', d.inquiry_id,
      case when d.locale='ar' then 'عميل دافع بانتظارك — يُرجى الرد'
           else 'A paying customer is waiting for you — please respond' end,
      (case when d.locale='ar'
        then 'دفع أحد العملاء لكشف بيانات تواصلك على QuotesDone وهو بانتظار ردك. يُرجى التواصل معه في أقرب وقت. وفقاً لاتفاقية المورّد، إذا لم ترد خلال ٣ أيام عمل وتم استرداد المبلغ للعميل، تُطبَّق رسوم عدم استجابة تعادل رسوم الكشف (٣٪ من قيمة العرض) على حسابك.'
        else 'A customer has paid to reveal your contact on QuotesDone and is waiting to hear from you. Please contact them as soon as possible. Under the Supplier Agreement, if you do not respond within 3 working days and the customer is refunded, a non-response charge equal to the reveal fee (3% of the quoted value) applies to your account.' end)
      || E'\n\n' ||
      (case when d.locale='ar' then 'هل تواصلت مع العميل بالفعل؟ أكّد هنا لإيقاف هذه التذكيرات: '
            else 'Already contacted this customer? Confirm here to stop these reminders: ' end)
      || base || '?tx=' || d.id || '&token=' || d.ack_token
    from due d returning 1
  )
  update transactions set nudged_24_at=now() where id in (select id from due);

  with due as (
    select t.id, t.inquiry_id, t.supplier_id, t.ack_token, l.email, coalesce(l.locale,'en') as locale
    from transactions t join leads l on l.id=t.supplier_id
    where t.revealed_at is not null and t.revealed_at < now()-interval '48 hours'
      and t.nudged_48_at is null and coalesce(t.fee_status,'')='paid' and t.refund_status is null and t.supplier_ack_at is null
      and not exists (select 1 from messages m where m.inquiry_id=t.inquiry_id and m.supplier_id=t.supplier_id and m.sender='supplier' and coalesce(m.blocked,false)=false and m.created_at>t.revealed_at)
      and l.email ~ '@'
  ), ins as (
    insert into notifications(type,to_email,to_role,inquiry_id,subject,body)
    select 'supplier_nudge', d.email, 'supplier', d.inquiry_id,
      case when d.locale='ar' then 'تذكير أخير: عميل لا يزال بانتظارك — يُرجى الرد اليوم'
           else 'Final reminder: a customer is still waiting — please respond today' end,
      (case when d.locale='ar'
        then 'هذا تذكير أخير بأن عميلاً دافعاً بانتظار ردك على QuotesDone. إذا لم ترد وتم استرداد المبلغ للعميل، تُطبَّق رسوم عدم استجابة تعادل رسوم الكشف (٣٪ من قيمة العرض)، وقد يؤدي تكرار عدم الرد إلى إزالتك من المنصّة.'
        else 'This is a final reminder that a paying customer is waiting for your response on QuotesDone. If you do not respond and the customer is refunded, a non-response charge equal to the reveal fee (3% of the quoted value) applies, and repeated non-response may lead to removal from the Platform.' end)
      || E'\n\n' ||
      (case when d.locale='ar' then 'هل تواصلت مع العميل بالفعل؟ أكّد هنا لإيقاف هذه التذكيرات: '
            else 'Already contacted this customer? Confirm here to stop these reminders: ' end)
      || base || '?tx=' || d.id || '&token=' || d.ack_token
    from due d returning 1
  )
  update transactions set nudged_48_at=now() where id in (select id from due);
end $function$;

CREATE OR REPLACE FUNCTION public.rl_check(p_key text, p_limit integer, p_seconds integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n int;
begin
  delete from rl_hits where at < now() - (p_seconds || ' seconds')::interval and k = p_key;
  select count(*) into n from rl_hits where k = p_key and at > now() - (p_seconds || ' seconds')::interval;
  if n >= p_limit then return false; end if;
  insert into rl_hits(k) values (p_key);
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.run_agent(p_job text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text;
begin
  select value into s from app_secrets where key='cred_db_internal';
  perform net.http_post(
    url := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/agents',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s, 'job', p_job)
  );
end$function$;

CREATE OR REPLACE FUNCTION public.run_auto_deploy()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d boolean; s text; ak text;
begin
  select dirty into d from public.deploy_state where id=1;
  if not coalesce(d,false) then return 'clean'; end if;
  select value into s from public.app_secrets where key='cred_db_internal';
  select value into ak from public.app_secrets where key='anon_key';
  perform net.http_post(
    url:='https://' || public.qd_project_ref() || '.supabase.co/functions/v1/site_deploy',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||ak),
    body:=jsonb_build_object('__secret', s),
    timeout_milliseconds:=150000);
  update public.deploy_state set dirty=false, last_deploy=now(), last_status='triggered' where id=1;
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  return 'deploying';
end $function$;

CREATE OR REPLACE FUNCTION public.run_doc_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text;
begin
  select value into s from public.app_secrets where key='cred_db_internal';
  perform net.http_post(
    url := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/doc_reminder',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s, 'days', 14));
end $function$;

CREATE OR REPLACE FUNCTION public.run_pending_digest()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare s text;
begin
  select value into s from public.app_secrets where key='cred_db_internal';
  perform net.http_post(
    url := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/pending_digest',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s)
  );
end$function$;

CREATE OR REPLACE FUNCTION public.run_site_autodeploy()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp', 'net'
AS $function$
declare s text; d boolean; lastdep timestamptz; ak text;
begin
  select dirty, last_deploy_at into d, lastdep from public.site_publish_state where id=1;
  if not coalesce(d,false) then return; end if;
  if lastdep is not null and now()-lastdep < interval '50 seconds' then return; end if;
  select value into s from public.app_secrets where key='cred_db_internal';
  select value into ak from public.app_secrets where key='anon_key';
  if s is null then return; end if;
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  update public.deploy_state set dirty=false, last_deploy=now(), last_status='triggered' where id=1;
  perform net.http_post(
    url := 'https://' || public.qd_project_ref() || '.supabase.co/functions/v1/site_deploy',
    body := jsonb_build_object('__secret', s),
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||ak),
    timeout_milliseconds := 150000
  );
end$function$;

CREATE OR REPLACE FUNCTION public.trg_block_banned_inquiry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_banned boolean;
begin
  select banned into v_banned from customers where id = NEW.customer_id;
  if coalesce(v_banned, false) then
    raise exception 'Your account has been paused due to repeated cancelled requests. Please contact support@quotesdone.com to restore it.';
  end if;
  return NEW;
end $function$;

CREATE OR REPLACE FUNCTION public.trg_company_faq_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin perform public.fn_company_faq_sync(); return null; end $function$;

CREATE OR REPLACE FUNCTION public.trg_mask_quote_contact()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.scope := mask_contact(new.scope);
  new.notes := mask_contact(new.notes);
  new.conditions := mask_contact(new.conditions);
  new.exclusions := mask_contact(new.exclusions);
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.trg_pricing_facts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin perform fn_company_facts_sync(); return null; end $function$;

CREATE OR REPLACE FUNCTION public.trg_quote_committed_hash()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_text text;
begin
  -- 5 Aug 2026. fn_fraud_scan's `copied_quote` rule groups quotes by committed_hash having more
  -- than one distinct supplier — a control for the same quotation being filed by two suppliers.
  -- It could NEVER fire: the only writer of committed_hash was quote_review_api, deleted in
  -- d79b28e (22 Jul 2026) as proven-dead, and nothing replaced it. The rule has been reading a
  -- column nothing populates ever since.
  --
  -- Hash the WORDS THE SUPPLIER WROTE, deliberately NOT quote_amount: identical amounts on one
  -- RFQ are already caught by the identical_bids rule immediately above it in fn_fraud_scan, and
  -- folding the amount in here would make copied_quote a noisy duplicate of that rule rather than
  -- an independent signal. Two suppliers filing the same PROSE is the thing worth flagging.
  v_text := btrim(lower(regexp_replace(
    coalesce(new.scope,'') || ' ' || coalesce(new.notes,'') || ' ' ||
    coalesce(new.payment_terms,'') || ' ' || coalesce(new.warranty,'') || ' ' ||
    coalesce(new.committed_items::text,''),
    '[^a-z0-9]+', ' ', 'g')));
  -- A floor, so thin and boilerplate quotes cannot collide. "supply and install as specified"
  -- legitimately repeats across honest suppliers; a real copied quotation carries far more text.
  -- Below the floor the column stays NULL and fn_fraud_scan skips it (it filters coalesce<>'').
  if length(v_text) >= 40 then
    new.committed_hash := encode(extensions.digest(v_text, 'sha256'), 'hex');
  else
    new.committed_hash := null;
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.trg_self_reg_category()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.source='self_registered' and coalesce(trim(NEW.categories),'')<>'' then
    -- skip if it already exactly equals an active category slug (known)
    if not exists (select 1 from category_agents where active and slug=NEW.categories) then
      -- only fire when the category actually changed (or on insert)
      if TG_OP='INSERT' or NEW.categories is distinct from OLD.categories then
        perform public.fn_provision_category_call(NEW.categories, NEW.id, NEW.services);
      end if;
    end if;
  end if;
  return NEW;
end $function$;

