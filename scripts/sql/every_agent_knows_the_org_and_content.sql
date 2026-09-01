-- EVERY AGENT KNOWS THE ORG AND THE CONTENT (Step 2, continued).
--
-- Extends the universal company_core knowledge with the parts a real colleague also knows: the whole
-- org directory (every agent, their role, their line manager, what they are measured on and their live
-- rating -- so everyone knows everyone), and the company's own published content (the 484 FAQ answers,
-- the social posts, the blog, the website pages). All recomposed from source, so nothing is static.
--
-- fn_company_knowledge_upsert: one place to write a company_core record correctly (generated tsv, the
-- 24 NOT NULL columns, current supersession). fn_company_org_directory_sync: the generator, called at
-- the end of fn_company_self_knowledge_sync so the single 15-min cron refreshes everything.
--
--   node scripts/apply_sql.mjs scripts/sql/every_agent_knows_the_org_and_content.sql --apply --ddl

begin;

create or replace function public.fn_company_knowledge_upsert(
  p_rid text, p_module text, p_title text, p_content text, p_kw text[])
 returns void language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
begin
  insert into public.ops_knowledge(
    record_id, scope_type, scope_key, layer, module, record_type, title, content,
    structured_data, source_ids, implementation_status, validation_status, authority_tier,
    risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
    confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status, effective_date)
  values (
    'qd-company:'||p_rid, 'company', 'company_core', 'company_core', p_module, 'md', p_title,
    p_content || E'\n\nYou can answer questions about: ' || array_to_string(p_kw, ', ') || '.',
    '{}'::jsonb, array['fn_company_org_directory_sync'], 'active', 'validated', 'autonomous',
    'low', '1', p_kw, '{}'::text[], '{}'::jsonb, 'UAE', 'current',
    'internal', true, true, 'current', 'pending', current_date)
  on conflict (record_id) do update set
    module=excluded.module, title=excluded.title, content=excluded.content,
    keywords=excluded.keywords, effective_date=excluded.effective_date,
    supersession_state='current', embedding_status='pending';
end $fn$;
revoke execute on function public.fn_company_knowledge_upsert(text,text,text,text,text[]) from public;

create or replace function public.fn_company_org_directory_sync()
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare d record; s record; a_txt text; sec_txt text; v_social text; v_blog text; v_web text; v_n int := 0;
begin
  -- 1. THE WHOLE ORG DIRECTORY — one record per department; everyone knows everyone's role, line
  --    manager, what they are measured on and their live rating.
  for d in select dept_key, name, charter, north_star, lead_agent from public.org_departments where active order by dept_key loop
    select string_agg(
             '  - ' || a.agent_key || ' (' || coalesce(a.title, a.role, '') || ') — reports to ' || coalesce(a.manager_key,'—')
             || coalesce((select ' — measured on: ' || string_agg(k.kpi || ' [target ' || coalesce(k.target_value::text,'—')
                          || ', current ' || coalesce(k.actual_value::text,'—') || ']', '; ')
                          from public.employee_kpi k where k.agent_key = a.agent_key and coalesce(k.active,true)), ''),
             E'\n' order by a.agent_key)
      into a_txt from public.org_agents a where a.active and a.department = d.dept_key;
    perform public.fn_company_knowledge_upsert(
      'org-' || d.dept_key, 'organization',
      'QuotesDone Org — the ' || coalesce(d.name, d.dept_key) || ' team',
      'DEPARTMENT: ' || coalesce(d.name, d.dept_key) || ' [' || d.dept_key || ']. Lead: ' || coalesce(d.lead_agent,'—')
      || '. North star: ' || coalesce(d.north_star,'—') || E'\n'
      || 'Members — agent — role — reports to (line manager) — measured on [target, current rating]:' || E'\n'
      || coalesce(a_txt, '(none)'),
      array[d.dept_key, coalesce(d.name,''), 'who works in ' || coalesce(d.name,d.dept_key), 'department team',
            'line manager', 'who reports to whom', 'kpi', 'measured on', 'current rating', 'colleagues',
            'who leads ' || coalesce(d.name,d.dept_key)]);
    v_n := v_n + 1;
  end loop;

  -- 2. THE PUBLISHED FAQ — grouped by section; the 484 answers a colleague could give a customer or supplier.
  for s in select coalesce(nullif(btrim(section),''),'general') sec, string_agg('Q: '||question||E'\n'||'A: '||coalesce(answer,''), E'\n' order by sort nulls last, id) qa
             from public.company_faq where coalesce(public,true) and coalesce(status,'approved') <> 'rejected'
             group by 1 loop
    perform public.fn_company_knowledge_upsert(
      'faq-' || regexp_replace(lower(s.sec),'[^a-z0-9]+','-','g'), 'faq',
      'QuotesDone FAQ — ' || s.sec,
      'FREQUENTLY ASKED (published answers — you may give these to customers and suppliers):' || E'\n' || left(s.qa, 6000),
      array['faq', 'frequently asked', s.sec, 'question', 'answer', 'how do i', 'what is', 'customer question', 'supplier question']);
    v_n := v_n + 1;
  end loop;

  -- 3. SOCIAL, BLOG, WEBSITE — the company's own published content.
  select string_agg('  - ['||to_char(created_at,'DD Mon YYYY')||', '||coalesce(channels::text,'')||', '||coalesce(status,'')||'] '
                    || left(coalesce(content->>'text', content->>'body', content::text), 200), E'\n' order by created_at desc)
    into v_social from public.social_posts;
  perform public.fn_company_knowledge_upsert('content-social','content','QuotesDone — Our Social Media Posts',
    'SOCIAL MEDIA POSTS (most recent first):' || E'\n' || coalesce(v_social,'(none yet)'),
    array['social media','social post','last post','latest post','instagram','linkedin','what did we post','our content','marketing post']);
  v_n := v_n + 1;

  select string_agg('  - ['||coalesce(to_char(published_at,'DD Mon YYYY'),'draft')||', '||coalesce(category,'')||'] '||title
                    ||coalesce(' — '||excerpt,''), E'\n' order by published_at desc nulls last)
    into v_blog from public.blog_posts where published;
  perform public.fn_company_knowledge_upsert('content-blog','content','QuotesDone — Our Blog Articles',
    'BLOG ARTICLES (published):' || E'\n' || left(coalesce(v_blog,'(none yet)'), 6000),
    array['blog','article','blog post','our articles','what have we written','content','seo','latest blog']);
  v_n := v_n + 1;

  select string_agg('  - /'||slug, E'\n' order by slug) into v_web from public.pages;
  perform public.fn_company_knowledge_upsert('content-website','content','QuotesDone — Our Website Pages',
    'WEBSITE PAGES we publish (the public site an agent should know exists):' || E'\n' || coalesce(v_web,'(none)')
    || E'\n\nThe published legal terms, services and marketing copy live on these pages; the terms and commercials are also summarised in the company terms and commercials knowledge.',
    array['website','web page','our site','pages','website content','what is on our website','public site']);
  v_n := v_n + 1;

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now());
end $fn$;
revoke execute on function public.fn_company_org_directory_sync() from public;

commit;
