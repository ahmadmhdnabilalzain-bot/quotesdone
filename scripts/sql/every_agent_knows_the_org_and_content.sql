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
declare d record; s record; a_txt text; sec_txt text; v_social text; v_blog text; v_web text; v_cat text;
        v_wf text; v_legal text; v_compl text; v_biz jsonb; v_n int := 0;
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

  -- 4. THE SUPPLIER CATEGORY TAXONOMY — every category an RFQ can be routed to.
  select string_agg('  ' || num || '. ' || name || case when regulated then ' (regulated)' else '' end, E'\n' order by sort, num)
    into v_cat from public.catalog_supplier_categories;
  perform public.fn_company_knowledge_upsert('categories', 'taxonomy',
    'QuotesDone — The Supplier Categories We Cover',
    'SUPPLIER CATEGORIES (' || (select count(*) from public.catalog_supplier_categories)::text
      || ' in total) — every category an RFQ can be routed to, in order:' || E'\n' || coalesce(v_cat, '(none)'),
    array['categories','supplier categories','what do we cover','category list','taxonomy','trades','how many categories','what categories','regulated categories','which category','list the categories']);
  v_n := v_n + 1;

  -- 5. THE FULL OPERATING CATALOG — all 30 workflows the company runs, every domain (not just the funnel).
  select string_agg('  ' || workflow_id || ' [' || coalesce(domain,'') || '] ' || workflow_name, E'\n' order by workflow_id)
    into v_wf from public.phase_b_workflow;
  perform public.fn_company_knowledge_upsert('workflows', 'operating_model',
    'QuotesDone — The 30 Workflows We Run',
    'THE COMPANY''S FULL OPERATING MODEL — every workflow the company runs, by id, domain and purpose:' || E'\n'
    || coalesce(v_wf,'') || E'\n'
    || 'The marketplace core (customer to suppliers to reveal) is W05 to W06 to W07 to W08 to W12 to W13 to W14 to W15 to W16; '
    || 'the rest run growth (W01-W03,W20,W21), product/AI (W22-W24), finance (W16,W27), legal (W28), assurance/security (W24,W29), '
    || 'data/knowledge (W25,W26) and people/org (W30).',
    array['workflows','processes','how we operate','operating model','what workflows do we run','what does workflow','the 30 workflows','how does work flow end to end','our processes','company operations']);
  v_n := v_n + 1;

  -- 6. LEGAL, COMPLIANCE AND POLICY FRAMEWORK.
  select string_agg('  - ' || coalesce(title, slug) || case when coalesce(category,'') <> '' then ' [' || category || ']' else '' end
         || case when coalesce(summary,'') <> '' then ': ' || left(summary,140) else '' end, E'\n' order by category, title)
    into v_legal from public.legal_documents;
  select string_agg('  - ' || requirement || ' (' || case when present then 'in place' else 'pending' end || ')', E'\n' order by priority nulls last, id)
    into v_compl from public.legal_checklist;
  perform public.fn_company_knowledge_upsert('legal', 'legal_compliance',
    'QuotesDone — Legal, Compliance and Policy Framework',
    'LEGAL & COMPLIANCE. QuotesDone operates under UAE law (Asia/Dubai; PDPL data protection). Published legal documents:' || E'\n'
    || coalesce(v_legal,'(none)') || E'\n' || 'Compliance checklist:' || E'\n' || coalesce(v_compl,'(none)') || E'\n'
    || 'Posture: anonymous marketplace, buyer/supplier identities protected until reveal, EVERY refund is founder-approved, '
    || 'late fees under UAE Federal Decree-Law 50/2022, disputes handled through a defined escalation ladder.',
    array['legal','compliance','regulatory','policy','terms of service','privacy policy','pdpl','data protection','uae law','are we compliant','legal documents','what laws apply','governing law','gdpr']);
  v_n := v_n + 1;

  -- 7. THE BUSINESS ENTITIES — the live customer/supplier/order landscape, and HOW to look up any one.
  begin v_biz := public.fn_business_entity_summary(); exception when others then v_biz := '{}'::jsonb; end;
  perform public.fn_company_knowledge_upsert('business-entities', 'business_data',
    'QuotesDone — Our Customers, Suppliers and Orders (live), and how to look them up' || E'\n' ||
    'THE BUSINESS RIGHT NOW (live counts):' || E'\n' ||
    '  Customers: ' || coalesce(v_biz->>'customers','0') || ' (with an inquiry: ' || coalesce(v_biz->>'customers_with_inquiry','0') || ')' || E'\n' ||
    '  Suppliers: ' || coalesce(v_biz->>'suppliers_total','0') || ' total — ' || coalesce(v_biz->>'suppliers_approved','0') || ' approved, '
      || coalesce(v_biz->>'suppliers_prospective','0') || ' prospective; sendable pool ' || coalesce(v_biz->>'sendable_supplier_pool','0') || E'\n' ||
    '  Inquiries/RFQs: ' || coalesce(v_biz->>'inquiries','0') || '  ·  Quotes: ' || coalesce(v_biz->>'quotes','0') || '  ·  Transactions/orders: ' || coalesce(v_biz->>'transactions','0') || E'\n' ||
    '  Categories: ' || coalesce(v_biz->>'categories_total','0') || ' (' || coalesce(v_biz->>'categories_at_target','0') || ' at the 10-supplier target)' || E'\n' ||
    'HOW TO KNOW A SPECIFIC ONE (do not memorise the records — look them up live):' || E'\n' ||
    '  - fn_business_entity_lookup(entity, key): one customer/supplier/inquiry/quote/transaction by id, email, company name or phone -> its full profile.' || E'\n' ||
    '  - fn_business_entity_list(entity, filter, limit): list or search them (e.g. all approved suppliers, recent inquiries).' || E'\n' ||
    '  - fn_business_entity_summary(): these live counts. Call these functions directly — you run with the database access to do so.',
    'business_data',
    array['customers','suppliers','how many customers','how many suppliers','who are our customers','who are our suppliers','their profiles','their orders','look up a supplier','find a customer','list suppliers','our orders','the crm','business data','inquiries','quotes','transactions','entity lookup']);
  v_n := v_n + 1;

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now());
end $fn$;
revoke execute on function public.fn_company_org_directory_sync() from public;

commit;
