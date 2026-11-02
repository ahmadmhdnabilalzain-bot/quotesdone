-- INTERNAL SEATS READ THE LIVE BUSINESS FIGURES IN THE COMPANY BLOCK (19 Oct 2026). Assigned: customer_support (the leak
-- fix this completes); the block is every seat's (fn_company_context). Review of #1549, item 4.
--
-- MEASURED 19 Oct 2026 (schema mirror, read-only): no_external_answer_can_state_an_internal_number.sql withdraws the
-- ops_knowledge rows carrying live figures (qd-company:business-entities, live-state, supplier-loops) from every
-- retrieval path, the internal seats' knowledge_vector_ml retrieval included. fn_company_context(audience internal) did
-- NOT carry those figures (it reads registration, vision, pricing, decisions, seats and targets), so withdrawing the rows
-- would have left the CEO and the other internal seats without the counts. The live source is
-- fn_business_entity_summary() (service_role only; anon cannot execute it).
--
-- WHAT THIS CHANGES: fn_company_context, internal audience only, appends "LIVE BUSINESS FIGURES" read at call time from
-- fn_business_entity_summary() (customers, suppliers total / approved / prospective, sendable pool, inquiries, quotes,
-- transactions, categories). The PUBLIC block returns before this line and is unchanged; a failure of the summary
-- never fails the block. The body is otherwise the live definition, verbatim (canonical before this:
-- the_public_company_block_carries_no_internal_figures.sql). CREATE OR REPLACE keeps the routine's grants.
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs (in production the
-- internal block carries suppliers_total and the public block does not).
-- Apply at merge, AFTER the_public_company_block_carries_no_internal_figures.sql's position:
--   node scripts/apply_sql.mjs scripts/sql/internal_seats_read_the_live_business_figures_in_the_company_block.sql --apply --ddl

-- APPLY ORDER, ENFORCED HERE (review of #1549): this body is the_public_company_block_carries_no_internal_figures.sql's
-- plus one section. Applied before that file, it would put back an older body. The guard refuses unless the live
-- routine already carries that file's public-block boundary; scripts/checks/customer_support_senior_contributions_are_
-- working_duties.test.mjs also refuses a MANIFEST that lists this file before that one.
do $order$ begin
  if not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fn_company_context'
                   and p.prosrc like '%A PUBLIC BLOCK STOPS HERE%' and p.prosrc like '%deliberately withheld%') then
    raise exception 'apply order: fn_company_context is not yet the_public_company_block_carries_no_internal_figures.sql body; apply that first';
  end if;
end $order$;

create or replace function public.fn_company_context(p_max_chars integer DEFAULT 16000, p_audience text DEFAULT 'internal'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reg      record;
  v_vis      record;
  v_pct      numeric;
  v_fee      numeric;
  v_freen    int;
  v_starts   date;
  v_core     text;
  v_tail     text := '';
  v_add      text;
  v_seats    text := '';
  v_block    text;
  v_missing  text[] := '{}';
  v_budget   int := greatest(coalesce(p_max_chars, 9000), 4000);
  v_trunc    boolean := false;
  r          record;
  v_pub      boolean := coalesce(lower(btrim(p_audience)), 'internal') = 'public';
begin
  select * into v_reg from public.company_registration order by recorded_at desc nulls last limit 1;
  select vision, mission into v_vis from public.company_vision order by id limit 1;
  select coalesce(standard_reveal_rate, 0.03) * 100, supplier_reg_fee,
         coalesce(supplier_free_count, 1000), supplier_charging_starts
    into v_pct, v_fee, v_freen, v_starts
    from public.pricing_config order by id limit 1;

  -- A MISSING FACT IS NAMED, NEVER PAPERED OVER. A block that silently drops the licence because
  -- the row went missing reads exactly like a block that never had one, and a seat would answer
  -- from memory. 'complete' is what the check asserts on.
  if v_reg.license_no is null then v_missing := v_missing || 'company_registration.license_no'; end if;
  if v_vis.mission   is null then v_missing := v_missing || 'company_vision.mission';           end if;
  if v_pct           is null then v_missing := v_missing || 'pricing_config.standard_reveal_rate'; end if;

  for r in
    select a.agent_key,
           coalesce(nullif(btrim(a.title), ''), ro.display_name, a.agent_key) as display,
           coalesce(nullif(btrim(a.role), ''), '')                            as role_text,
           coalesce(array_to_string(ro.escalation_targets, ', '), '')         as escalates_to
      from public.org_agents a
      left join public.org_role ro
        on ro.runtime_agent_key = a.agent_key and ro.status = 'active'
     where a.active
     order by a.agent_key
  loop
    v_seats := v_seats || '- ' || r.agent_key || ' (' || r.display || ')'
      || case when r.escalates_to <> '' then ' -- escalates to ' || r.escalates_to else '' end
      || case when r.role_text  <> '' then ': ' || left(r.role_text, 220) else '' end
      || E'\n';
  end loop;

  v_core :=
     '# QUOTESDONE -- COMPANY KNOWLEDGE. Every seat carries this block. It is composed from the live'
  || ' operational tables at call time; no figure in it is written into any routine. It is what you'
  || ' answer FROM about the company, and none of it may be relaxed, discounted or improvised on.'
  || E'\n\n'
  || '## 1. WHO WE ARE' || E'\n'
  || 'Trade name: ' || coalesce(v_reg.trade_name, '(not on record)') || '.'
  || ' Owner: ' || coalesce(v_reg.owner_name, '(not on record)')
  || coalesce(' ' || v_reg.owner_share, '') || ' -- he is the founder, Chairman and CEO.' || E'\n'
  || 'Licensing authority: ' || coalesce(v_reg.authority, '(not on record)') || '.'
  || ' Licensed activities: ' || coalesce(v_reg.activities, '(not on record)') || '.' || E'\n'
  || 'Registered contact: ' || coalesce(v_reg.registered_email, '-')
  || ' / ' || coalesce(v_reg.registered_mobile, '-') || '.' || E'\n'
  || 'Online: ' || coalesce(v_reg.e_stores, '-') || E'\n'
  || 'Vision: ' || coalesce(v_vis.vision, '(not on record)') || E'\n'
  || 'Mission: ' || coalesce(v_vis.mission, '(not on record)') || E'\n\n'
  || '## 2. WHAT WE SELL' || E'\n'
  || 'A UAE B2B anonymous quotation marketplace for construction, fit-out and related supply. A buyer'
  || ' posts an RFQ describing a job or a product; verified UAE suppliers submit quotations without'
  || ' either side seeing the other; the buyer compares them FREE of charge and pays a '
  || coalesce(round(v_pct, 2)::text, '3') || '% reveal fee on the value of the quotation it selects to'
  || ' unlock that supplier''s identity and contact details. Suppliers pay NO commission -- ever.'
  || ' Supplier registration is free for the first ' || v_freen || ' registrations and AED '
  || coalesce(v_fee::text, '1000') || ' per year after that'
  || case when v_starts is null
          then ' -- there is NO calendar deadline: charging begins with registration number '
               || (v_freen + 1) || ', whenever that happens (founder ruling, 6 Sep 2026).'
          else ', charged from ' || to_char(v_starts, 'DD Mon YYYY') || '.' end
  -- Internal only (instruction 777): a statement of how many customers exist is a figure.
  || case when v_pub then '' else
     ' The company is PRE-LAUNCH: no real customer, inquiry, quotation or transaction exists yet, and'
  || ' that is a fact about the stage, never a reason to answer as if a capability were missing.' end
  || E'\n\n'
  || '## 3. THE HARD RULES -- the founder''s only rules; no employee may relax them' || E'\n'
  -- The category-opening rule carries an internal supplier threshold (instruction 777); the public
  -- block states the matching rule as a capability instead.
  || case when v_pub
          then regexp_replace(public.fn_company_hard_rules(), '\n5\. CATEGORY OPENING[^\n]*',
                 E'\n5. MATCHING: every request goes only to verified suppliers of its exact trade, never to a'
                 || ' neighbouring one, and new trades are welcome.')
          else public.fn_company_hard_rules() end || E'\n'
  || '## 4. LICENCE, TAX AND AUDIT' || E'\n'
  || 'Licence ' || coalesce(v_reg.license_no, '(none on record)')
  || coalesce(' (' || v_reg.license_type || ')', '')
  || coalesce(', issued ' || to_char(v_reg.issued_on, 'DD Mon YYYY'), '')
  || coalesce(', EXPIRES ' || to_char(v_reg.expires_on, 'DD Mon YYYY'), '')
  || coalesce(', issued by ' || v_reg.authority, '') || '.' || E'\n'
  || coalesce(v_reg.license_class_note || E'\n', '')
  || 'VAT: '
  || case when coalesce(v_reg.vat_registered, false)
          then 'REGISTERED' || coalesce(', TRN ' || v_reg.trn, '') || '.'
          -- The turnover threshold tells a stranger what our revenue is below (instruction 777).
          when v_pub then 'NOT registered; no invoice carries VAT.'
          else 'NOT registered, and registration is NOT required until taxable turnover reaches the'
               || ' AED ' || coalesce(to_char(v_reg.vat_threshold_aed, 'FM999,999,999'), '375,000')
               || ' threshold. No invoice carries VAT and no agent asks the founder about it again'
               || ' (founder ruling, ' || coalesce(to_char(v_reg.vat_ruling_on, 'DD Mon YYYY'), '6 Sep 2026') || ').' end
  || E'\n'
  -- Both notes reason about revenue thresholds and internal roles: internal only (instruction 777).
  || case when v_pub then '' else
        coalesce('Corporate tax: ' || v_reg.corporate_tax_note || E'\n', '')
     || coalesce('Auditor: ' || v_reg.auditor || E'\n', '') end
  || E'\n';

  -- A PUBLIC BLOCK STOPS HERE, AND SAYS SO. Silently ending after section 4 would read to a model
  -- as "this company has four seats' worth of nothing behind it"; naming the boundary tells it the
  -- rest exists and is not its to discuss.
  if coalesce(lower(btrim(p_audience)), 'internal') = 'public' then
    v_block := v_core
      || '## 5. WHAT IS NOT IN THIS BLOCK' || E'\n'
      || 'This is the PUBLIC company block, for a surface a stranger can talk to. The internal'
      || ' sections -- who staffs the company, the founder''s standing decisions and the revenue'
      || ' targets -- are deliberately withheld. Never speculate about them, and never state a'
      || ' company fact that is not written above.' || E'\n';
    return jsonb_build_object(
      'block', v_block, 'chars', length(v_block), 'truncated', false,
      'complete', cardinality(v_missing) = 0, 'missing', to_jsonb(v_missing),
      'audience', 'public', 'as_of', now(), 'fingerprint', md5(v_block),
      'rule', 'The PUBLIC half of the company knowledge: identity, what we sell, the published hard '
           || 'rules, the licence and the tax position, all read from the live tables at call time. '
           || 'Never state a fee, date, licence number, threshold or policy that is not in it.');
  end if;

  v_core := v_core
  || '## 5. THE SEATS -- the whole company. There are no departments: the founder removed the'
  || ' organisation chart totally on 7 September 2026, and no seat may invent another one.' || E'\n'
  || coalesce(nullif(v_seats, ''), '(no active seat on record)')
  || E'\n';

  -- SECTIONS 6 AND 7 ARE THE BUDGETED TAIL. Sections 1-5 are never truncated: they are the answer
  -- to "where do I work and what are the rules", and a block that loses the reveal fee to a
  -- character budget is worse than no block at all.
  v_add := '## 6. THE FOUNDER''S STANDING DECISIONS -- settled; never ask him about any of them again'
        || E'\n';
  for r in
    select decision_key, decision_text
      from public.company_policy_decision
     where coalesce(never_ask_again, true)
     order by decision_key
  loop
    if length(v_core) + length(v_add) + length(r.decision_text) + 8 > v_budget then
      v_trunc := true; exit;
    end if;
    v_add := v_add || '- ' || r.decision_key || ': ' || r.decision_text || E'\n';
  end loop;
  if v_trunc then
    v_add := v_add || '(cut for length -- there are more standing decisions than fit this budget.'
          || ' Read public.company_policy_decision, or call fn_company_context with a larger'
          || ' p_max_chars, before answering anything that turns on one.)' || E'\n';
  end if;
  v_tail := v_tail || v_add || E'\n';

  v_add := '## 7. WHAT THE COMPANY IS AIMING AT' || E'\n';
  declare
    v_cut7 boolean := false;
  begin
  for r in
    select contract_key, objective, deadline, accountable_owner
      from public.target_contract
     where status = 'active'
     order by priority nulls last, contract_key
  loop
    if length(v_core) + length(v_tail) + length(v_add) + length(r.objective) + 60 > v_budget then
      v_trunc := true; v_cut7 := true; exit;
    end if;
    v_add := v_add || '- ' || r.contract_key || ': ' || r.objective
          || ' (by ' || coalesce(r.deadline::text, 'no deadline')
          || ', owned by ' || coalesce(r.accountable_owner, 'unassigned') || ')' || E'\n';
  end loop;
  if v_cut7 then
    v_add := v_add || '(cut for length -- read public.target_contract where status = ''active'','
          || ' or call fn_company_context with a larger p_max_chars.)' || E'\n';
  end if;
  v_tail := v_tail || v_add;
  end;

  -- LIVE BUSINESS FIGURES, INTERNAL ONLY (19 Oct 2026, review of #1549). The ops_knowledge rows that carried these
  -- (qd-company:business-entities and its kin) are now withdrawn from every retrieval path so no external answer can
  -- quote them; the internal seats read the same numbers here instead, live, from fn_business_entity_summary(). The
  -- public block returned above never reaches this line.
  begin
    v_tail := v_tail || chr(10) || '## LIVE BUSINESS FIGURES (internal only: never state these to a customer or supplier)' || chr(10)
      || (select string_agg(key || ': ' || value, chr(10) order by key) from jsonb_each_text(public.fn_business_entity_summary())) || chr(10);
  exception when others then
    -- NOT SWALLOWED (review of #1549): the failure is named in the block and in missing[], so complete=false says it
    -- (the routine is STABLE and cannot write a log row; every caller already reads complete/missing).
    v_missing := array_append(v_missing, 'live business figures: fn_business_entity_summary failed: ' || left(sqlerrm, 200));
    v_tail := v_tail || chr(10) || '## LIVE BUSINESS FIGURES: UNAVAILABLE (' || left(sqlerrm, 200) || '). Do not estimate them.' || chr(10);
  end;
  v_block := v_core || v_tail;

  return jsonb_build_object(
    'block',       v_block,
    'chars',       length(v_block),
    'truncated',   v_trunc,
    'complete',    cardinality(v_missing) = 0,
    'missing',     to_jsonb(v_missing),
    'audience',    'internal',
    'as_of',       now(),
    'fingerprint', md5(v_block),
    'sources',     jsonb_build_array('company_registration', 'company_vision', 'pricing_config',
                                     'decision_policy', 'company_policy_decision', 'org_agents',
                                     'org_role', 'target_contract',
                                     'fn_company_hard_rules() (pricing_config + decision_policy + pages.legal_supplier_body)'),
    'rule',        'This is the COMPANY knowledge every seat carries, read from the live tables at '
                || 'call time. It is not advisory and it is not rankable: it holds even when the '
                || 'seat''s own retrieval finds nothing, which is exactly when a seat is most '
                || 'tempted to improvise. Never state a fee, date, licence number, threshold or '
                || 'policy that is not in this block.');
end
$function$


;
