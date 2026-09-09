-- EVERY SEAT CARRIES THE COMPANY KNOWLEDGE.
--
-- Founder ruling, 9 September 2026, verbatim: "the company knowledge is literally connected to
-- every seat automatically. Any seat that we made, the company knowledge should be there.
-- Otherwise, those agents wouldn't know where they work or what they do or what is our company
-- about."
--
-- It was FALSE when he said it. Measured the same day: fn_it_engineer_assist and fn_ceo_context
-- existed but no runtime called them; the it_engineer edge function called exactly one routine
-- (fn_agent_may_act) and ceo_agent exactly one (fn_ceo_command_submit); only fn_accountant_assist
-- and fn_sales_assist retrieved anything at all, and neither of them carried a word about what the
-- company IS. A seat could answer a question about a VAT threshold from its own specialist pack and
-- have no idea it works for a Dubai DET-licensed marketplace that is not VAT-registered.
--
-- THE CANONICAL BODY IS THE OPERATIONAL TABLES, NOT A PROSE COPY.
-- company_faq (customer-facing wording), ops_knowledge layer 'company_core' (103 prose rows) and
-- the agent packs are all DERIVED restatements: they are written once and then drift, and nothing
-- fails when they do. The tables below are what the product actually ENFORCES -- pricing_config
-- carries the no-discount-no-cap CHECK constraint that reveal_fee() computes against, the refund
-- guards read decision_policy, the licence facts are the registration record itself -- so a block
-- composed from them cannot say one thing while the platform does another.
--   company_registration      the DET licence, VAT and corporate-tax position
--   company_vision            vision and mission
--   pricing_config            the reveal rate, the supplier registration fee and the free count
--   decision_policy           the money figures inside the refund ladder
--   company_policy_decision   the founder's standing decisions, never_ask_again
--   org_agents + org_role     the seats and where each one escalates
--   target_contract           what the company is aiming at
--   fn_company_hard_rules()   REUSED, not restated -- it already reads pricing_config, decision_policy
--                             and the published Supplier Agreement for the five hard rules
--
-- NOT ONE FIGURE IS WRITTEN OUT HERE. Every number, date and name is read at call time.
-- fn_company_brief() is deliberately NOT reused: it narrates departments, and the founder removed
-- the department layer totally on 7 September 2026, so it describes an organisation that is gone.

-- THE DEFAULT BUDGET IS MEASURED, NOT GUESSED. The whole block came out at 13,209 characters on
-- 9 Sep 2026, so a 9,000 default silently dropped half the founder's standing decisions and every
-- one of the four targets -- leaving section 7 as a heading with nothing under it, which reads to a
-- model as "this company has no targets" rather than "this was cut". The default now clears the
-- real length with room to grow, and a section that IS cut says so in the text.
-- WHY THERE IS A PUBLIC AUDIENCE AT ALL. Four of the five seats answer only internally, and for them
-- the whole block is right. The fifth -- customer_support -- runs on site_assistant, the widget on
-- the public home page, where a stranger with no session is talking to it. Sections 1 to 4 are
-- already public: they are the licence on the DET register, the Terms and the Supplier Agreement as
-- published, and the fee the checkout charges. Sections 5 to 7 are not: the seat list, the founder's
-- standing decisions and the revenue targets are internal, and pinning them into a public prompt
-- would put them one polite question away from anyone. p_audience => 'public' stops at section 4 and
-- SAYS that it stopped, so a public answer is grounded in the same live figures without carrying the
-- company's internal decisions out to the home page.
--
-- The one-argument signature is dropped first: leaving it in place beside this one makes the bare
-- call fn_company_context() ambiguous, and every seat routine calls it exactly that way.
drop function if exists public.fn_company_context(integer);

create or replace function public.fn_company_context(p_max_chars integer default 16000,
                                                     p_audience text default 'internal')
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
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
  || ' The company is PRE-LAUNCH: no real customer, inquiry, quotation or transaction exists yet, and'
  || ' that is a fact about the stage, never a reason to answer as if a capability were missing.'
  || E'\n\n'
  || '## 3. THE HARD RULES -- the founder''s only rules; no employee may relax them' || E'\n'
  || public.fn_company_hard_rules() || E'\n'
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
          else 'NOT registered, and registration is NOT required until taxable turnover reaches the'
               || ' AED ' || coalesce(to_char(v_reg.vat_threshold_aed, 'FM999,999,999'), '375,000')
               || ' threshold. No invoice carries VAT and no agent asks the founder about it again'
               || ' (founder ruling, ' || coalesce(to_char(v_reg.vat_ruling_on, 'DD Mon YYYY'), '6 Sep 2026') || ').' end
  || E'\n'
  || coalesce('Corporate tax: ' || v_reg.corporate_tax_note || E'\n', '')
  || coalesce('Auditor: ' || v_reg.auditor || E'\n', '')
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
$function$;

revoke execute on function public.fn_company_context(integer, text) from public;
grant execute on function public.fn_company_context(integer, text) to service_role;

-- THE SUPPORT SEAT ESCALATED TO TWO ROLES THAT NO LONGER EXIST. org_role.escalation_targets for
-- customer_support read {communications_manager, chief_of_staff}; both were deleted with the
-- department layer on 7 September 2026 and neither is in org_role today. fn_support_context's own
-- pinned invariant already says "Escalation goes to the CEO", so the company block would have
-- printed a reporting line that contradicts the seat's own instructions. Corrected at source.
update public.org_role
   set escalation_targets = array['ceo'], updated_at = now()
 where role_id = 'customer_support'
   and escalation_targets is distinct from array['ceo'];

-- ---------------------------------------------------------------------------------------------
-- SEAT: ceo -- fn_ceo_context. 1 return path(s), every one of them now carries the company block.
-- The rest of this definition is the routine exactly as it was deployed; only the pinned
-- 'company' key is added.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ceo_context(p_query text, p_max_chars integer DEFAULT 18000, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record;
  v_out jsonb := '[]'::jsonb;
  v_used int := 0;
  v_n int := 0;
  v_how text := null;
begin
  for r in select * from public.fn_ceo_knowledge_search(p_query, p_limit) loop
    exit when v_used + length(r.body) > greatest(2000, p_max_chars);
    v_how := coalesce(v_how, r.matched_how);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'domain', r.domain, 'body', r.body, 'body_sha256', r.body_sha256,
      'source_ids', to_jsonb(r.source_ids), 'source_path', r.source_path,
      'review_status', r.review_status, 'authority_effect', r.authority_effect,
      'relevance', r.relevance, 'matched_how', r.matched_how, 'warning', r.warning);
    v_used := v_used + length(r.body);
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'query', p_query,
    'records', v_out,
    'record_count', v_n,
    'chars_used', v_used,
    'matched_how', v_how,
    'sufficient', v_n > 0,
    'signal', case when v_n = 0
                   then 'INSUFFICIENT CONTEXT -- nothing in the CEO knowledge pack matched this query. Say so rather than answering from memory.'
                   when v_how = 'best_terms'
                   then 'Advisory context, matched on the best terms rather than all of them. Read each title before relying on it. Company facts, targets, budgets and permissions must be read from the application, not from these records.'
                   else 'Advisory context only. Company facts, targets, budgets and permissions must be read from the application, not from these records.' end,
    'pack_fingerprint', (select max(pack_fingerprint) from public.ceo_knowledge));
end $function$;

-- ---------------------------------------------------------------------------------------------
-- SEAT: customer_support -- fn_support_context. 1 return path(s), every one of them now carries the company block.
-- The rest of this definition is the routine exactly as it was deployed; only the pinned
-- 'company' key is added.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_support_context(p_query text, p_max_chars integer DEFAULT 12000, p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record; v_out jsonb := '[]'::jsonb; v_used int := 0; v_n int := 0; v_how text;
begin
  for r in select * from public.fn_support_knowledge_search(p_query, p_limit) loop
    exit when v_used + length(r.body) > greatest(1500, p_max_chars);
    v_how := coalesce(v_how, r.matched_how);
    v_out := v_out || jsonb_build_object(
      'record_id', r.record_id, 'record_kind', r.record_kind, 'title', r.title,
      'body', r.body, 'source_ids', to_jsonb(r.source_ids), 'review_status', r.review_status,
      'relevance', r.relevance, 'matched_how', r.matched_how, 'warning', r.warning);
    v_used := v_used + length(r.body); v_n := v_n + 1;
  end loop;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'query', p_query,
    -- PINNED EVERY TIME, never retrieved and never rankable. These are the rules that must hold
    -- when the retrieval finds nothing, which is exactly when an agent is most tempted to improvise.
    'invariants', jsonb_build_array(
      'Never say you checked, sent, escalated, fixed, refunded or approved anything without tool evidence for it.',
      'A tool error means "cannot verify right now". It never means "no inquiry", "unpaid" or "no discount".',
      'Never reveal a supplier name, contact, logo, amount or quotation content in a notification. The quotation stays in the portal, including after a reveal payment.',
      'Never invent a fee, discount, promotion, policy, deadline or guaranteed outcome.',
      'A supplied email, number or reference is a search clue, never proof of account ownership.',
      'Never request a password, full card number or a banking OTP.',
      'Identify as QuotesDone Support. Never impersonate a person and never claim to be human.',
      'Escalation goes to the CEO. Never to the founder, and never to an invented department.'),
    'advisory_records', v_out,
    'record_count', v_n,
    'matched_how', v_how,
    'sufficient', v_n > 0,
    -- The caller fills this from the database. It is named rather than left implicit so that a
    -- caller who forgets it produces an obviously empty slot instead of a confident general answer.
    'account_facts', null,
    'account_facts_note', 'The CALLER must fill account_facts from authorised live data. Advisory records never contain this customer''s facts.',
    'signal', case when v_n = 0
                   then 'NO ADVISORY COVERAGE for this query. Answer from company policy and live account facts, or say you will check. Do not improvise from these records.'
                   else 'Advisory guidance only. Account facts come from the database.' end);
end $function$;

-- ---------------------------------------------------------------------------------------------
-- SEAT: sales_engineer -- fn_sales_assist. 2 return path(s), every one of them now carries the company block.
-- The rest of this definition is the routine exactly as it was deployed; only the pinned
-- 'company' key is added.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_sales_assist(p_text text, p_embedding vector, p_min_similarity numeric DEFAULT 0.86, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_actor text DEFAULT 'sales_engineer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  -- Per-corpus candidate width. Wider than the answer width so the floors have something to reject
  -- and the decision log records the near-misses that justify the floor.
  v_wide      int := greatest(v_k * 4, 20);
  -- LEXICAL-ONLY ADMISSION BAR. Applied only to rows with no embedding, where there is no vector
  -- to corroborate with. Deliberately 4x p_min_rank's default: it is carrying the whole burden of
  -- proof on its own. Measured basis in the report accompanying this file.
  -- Floored at 0.20 but never BELOW p_min_rank, so a caller that raises the corroboration bar
  -- raises this one too. Without that tie the lexical-only route would be untestable: the probe
  -- that proves a floor bites by raising it above the best hit would leave this route wide open
  -- and conclude the floors do not fire. A gate nobody can prove fires is not a gate.
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  -- ponytail: kb_chunks lexical route takes the first 4,000 index matches and ranks those, not the
  -- global best of 2.5m unembedded rows. Ranking every match of a common term would be a table
  -- scan on every portal message. Raise it, or embed the rest, if recall proves short.
  c_kb_scan   int := 4000;
  -- Out of scope by the company's own exclusion, and by slug so it cannot drift.
  c_fnb       text[] := array['cat:catering-companies','cat:bakery-equipment-suppliers',
                              'cat:food-processing-equipment-suppliers','cat:hospitality-supplies-companies',
                              'cat:cold-room-and-refrigeration-suppliers'];
  v_tq        tsquery;
  -- LEXEME OVERLAP — MEASURED, TRIED, AND REJECTED AS AN ADMISSION RULE. Recorded here because a
  -- rejected relaxation is worth more to the next reader than a silent one.
  --
  -- Over 18 realistic portal questions on 9 Sep 2026, all 5 that fell through did so at
  -- lexical_rank EXACTLY 0.0000 while their best vector hit sat at 0.888–0.916. Not weak evidence
  -- — NO lexical match at all, because websearch_to_tsquery ANDs every term and no single passage
  -- contains all of "dubai & supplier & cover & abu & dhabi". So lowering p_min_rank would have
  -- recovered nothing, and the measurement is what says so rather than a guess.
  --
  -- The obvious relaxation was to corroborate on lexeme OVERLAP instead: admit a row that clears
  -- cosine 0.86 and carries at least 40% of the question's own lexemes literally. It was built,
  -- applied and measured. "does a Dubai supplier cover Abu Dhabi as well" then returned a joinery
  -- FIRE-DOOR CERTIFICATION passage — cosine 0.888, lexemes "dubai" and "suppli" present, subject
  -- entirely wrong. A confidently wrong answer to a procurement question is the exact failure the
  -- floors exist to prevent, so the relaxation was reverted within the hour. The overlap count is
  -- still computed and logged as a DIAGNOSTIC, because it is the cheapest signal for which gaps
  -- are a phrasing problem and which are a genuinely absent subject — it is simply not allowed to
  -- admit anything.
  v_lex       text[];
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_norm      text;
  v_gap       public.sales_knowledge_gap%rowtype;
  v_task      bigint;
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_need := least(coalesce(cardinality(v_lex), 0), greatest(2, ceil(0.4 * coalesce(cardinality(v_lex), 0))::int));

  -- Every corpus produces the same six columns so the union is a fact about provenance, not about
  -- shape. `route` records HOW a row could be admitted, and is what stops a vector-bearing row
  -- being let in on lexical evidence alone.
  create temporary table if not exists _sa_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate has a guard that refuses an unqualified DELETE, and a
  -- WHERE-less delete on a scratch table is exactly what that guard exists to catch elsewhere.
  truncate table _sa_cand;

  -- sales_knowledge — the seat's own pack. 1,136 rows, 100% embedded.
  if p_embedding is not null then
    insert into _sa_cand
    select 'sales_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || case when k.epistemic_status is null then '' else ' · ' || k.epistemic_status end,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from sales_knowledge k
     where k.embedding_gte is not null
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'sales_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, ''), null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from sales_knowledge k
   where k.embedding_gte is null and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge — 9,139 rows, 100% embedded, tsv + hnsw.
  if p_embedding is not null then
    insert into _sa_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.record_type, '') || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'   -- never quote a superseded rule
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- kb_chunks — 2,686,026 rows. Both routes matter here and the lexical one matters most: 93.8% of
  -- this corpus has no vector at all, so a vector-only reader sees 6% of the category and trade
  -- field body.
  if p_embedding is not null then
    insert into _sa_cand
    select 'kb_chunks', c.id::text, c.title, left(c.content, 4000),
           coalesce(c.source_kind, '') || case when c.category is null then '' else ' · ' || c.category end
             || case when c.citation is null then '' else ' · ' || c.citation end,
           (1 - (c.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(c.fts, v_tq), 0)::numeric * (case when c.fts @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(c.fts) u where u.lexeme = any (v_lex))
      from kb_chunks c
     where c.embedding_gte is not null
     order by c.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'kb_chunks', x.id::text, x.title, left(x.content, 4000),
         coalesce(x.source_kind, '') || case when x.category is null then '' else ' · ' || x.category end
           || case when x.citation is null then '' else ' · ' || x.citation end,
         null::numeric, ts_rank(x.fts, v_tq)::numeric, false, 0
    from (select c.id, c.title, c.content, c.source_kind, c.category, c.citation, c.fts
            from kb_chunks c
           where c.embedding_gte is null and c.fts @@ v_tq
           limit c_kb_scan) x
   order by ts_rank(x.fts, v_tq) desc
   limit v_wide;

  -- agent_knowledge — 2,556 rows. The 1,627 'cat:%' rows carry no embedding, which is exactly why
  -- section 1 of this file exists. F&B excluded by slug.
  if p_embedding is not null then
    insert into _sa_cand
    select 'agent_knowledge', a.id::text, a.topic, left(a.content, 4000),
           a.agent_key || case when a.layer is null then '' else ' · ' || a.layer end,
           (1 - (a.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(a.search, v_tq), 0)::numeric * (case when a.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(a.search) u where u.lexeme = any (v_lex))
      from agent_knowledge a
     where a.embedding_gte is not null
       and not (a.agent_key = any (c_fnb))
       and coalesce(a.validation_status, '') <> 'quarantined'
     order by a.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'agent_knowledge', a.id::text, a.topic, left(a.content, 4000),
         a.agent_key || case when a.layer is null then '' else ' · ' || a.layer end,
         null::numeric, ts_rank(a.search, v_tq)::numeric, false, 0
    from agent_knowledge a
   where a.embedding_gte is null and a.search @@ v_tq
     and not (a.agent_key = any (c_fnb))
     and coalesce(a.validation_status, '') <> 'quarantined'
   order by ts_rank(a.search, v_tq) desc
   limit v_wide;

  -- support_knowledge — 408 rows, tsvector only. Lexical is not a fallback here, it is the only
  -- instrument the table has.
  insert into _sa_cand
  select 'support_knowledge', s.record_id, s.title, left(s.body, 4000),
         coalesce(s.record_kind, '') || case when s.domain is null then '' else ' · ' || s.domain end,
         null::numeric, ts_rank(s.search, v_tq)::numeric, false, 0
    from support_knowledge s
   where s.search @@ v_tq
     and coalesce(s.runtime_index_eligible, true)
   order by ts_rank(s.search, v_tq) desc
   limit v_wide;

  -- category_specs / category_quote_specs — 56 and 141 rows, no index of any kind. Small enough to
  -- vectorise the tsquery on the fly, and they answer the single most common portal question there
  -- is: what does this category actually require.
  insert into _sa_cand
  select 'category_specs', cs.category, cs.label,
         left('Supplier requirements: ' || coalesce(cs.supplier_requirements::text, 'none recorded')
           || E'\nCompliance checklist: ' || coalesce(cs.compliance_checklist::text, 'none recorded')
           || E'\nQuote fields: ' || coalesce(cs.fields::text, 'none recorded'), 4000),
         'category spec · ' || cs.category, null::numeric,
         ts_rank(to_tsvector('english', coalesce(cs.category,'') || ' ' || coalesce(cs.label,'') || ' '
                 || coalesce(cs.supplier_requirements::text,'') || ' ' || coalesce(cs.compliance_checklist::text,'')), v_tq)::numeric,
         false, 0
    from category_specs cs
   where to_tsvector('english', coalesce(cs.category,'') || ' ' || coalesce(cs.label,'') || ' '
         || coalesce(cs.supplier_requirements::text,'') || ' ' || coalesce(cs.compliance_checklist::text,'')) @@ v_tq
   limit v_wide;

  insert into _sa_cand
  select 'category_quote_specs', q.id::text, q.label,
         left('Aspect: ' || coalesce(q.aspect, '—') || E'\nMandatory: ' || coalesce(q.mandatory::text, 'unknown')
           || E'\n' || coalesce(q.note, ''), 4000),
         'quote spec · ' || coalesce(q.spec_group, ''), null::numeric,
         ts_rank(to_tsvector('english', coalesce(q.spec_group,'') || ' ' || coalesce(q.aspect,'') || ' '
                 || coalesce(q.label,'') || ' ' || coalesce(q.note,'')), v_tq)::numeric,
         false, 0
    from category_quote_specs q
   where to_tsvector('english', coalesce(q.spec_group,'') || ' ' || coalesce(q.aspect,'') || ' '
         || coalesce(q.label,'') || ' ' || coalesce(q.note,'')) @@ v_tq
   limit v_wide;

  -- ADMISSION. A vector-bearing row must clear the cosine floor AND corroborate lexically. A row
  -- with no vector must clear the stricter lexical-only bar. Nothing else is admitted.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity and c.lexical_rank >= p_min_rank) as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)                                as ok_lexical
      from _sa_cand c
  ), ranked as (
    select j.*, (j.ok_vector or j.ok_lexical) as cited,
           row_number() over (
             order by (case when j.ok_vector or j.ok_lexical then 0 else 1 end),
                      (case when j.has_vector then 0 else 1 end),
                      j.similarity desc nulls last, j.lexical_rank desc) as rn
      from judged j
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'cleared_floor', coalesce(r.has_vector and r.similarity >= p_min_similarity, false),
      -- Diagnostic only, deliberately NOT an admission criterion. See the header note.
      'lex_hits', r.lex_hits, 'lex_overlap_would_admit', (v_need > 0 and r.lex_hits >= v_need),
      'corroborated', r.lexical_rank >= (case when r.has_vector then p_min_rank else c_lex_only end),
      'cited', r.cited) order by r.rn) filter (where r.rn <= 40), '[]'::jsonb),
    coalesce(array_agg(r.corpus || ':' || r.record_id order by r.rn)
             filter (where r.cited and r.rn <= v_k), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id, 'title', r.title,
      'provenance', r.provenance,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'content', r.content) order by r.rn) filter (where r.cited and r.rn <= v_k), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from ranked r;

  select max(similarity), max(lexical_rank) into v_best_sim, v_best_rank from _sa_cand;
  select corpus into v_best_corp from _sa_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _sa_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;

    -- ── THE FALLBACK IS AN ACTION, NOT A SENTENCE ────────────────────────────────────────────
    -- The founder's objection was never to the honesty of "I do not have that". It was to nothing
    -- happening afterwards. Something happens now: the question is kept, counted, and owned.
    v_norm := left(lower(regexp_replace(btrim(p_text), '\s+', ' ', 'g')), 400);

    select * into v_gap from sales_knowledge_gap where question_norm = v_norm;

    if not found then
      insert into org_tasks (title, detail, status, tier, action_class, assigned_agent,
                             priority, requires_evidence, needs_founder)
      values (
        left('Answer an unanswered portal question: ' || btrim(p_text), 160),
        'A customer or supplier asked this in the portal and the Sales Engineer could not source an '
          || 'answer from any corpus it searches (sales_knowledge, ops_knowledge, kb_chunks, '
          || 'agent_knowledge, support_knowledge, category_specs, category_quote_specs).' || E'\n\n'
          || 'QUESTION: ' || btrim(p_text) || E'\n'
          || 'REFUSAL: ' || v_refusal || E'\n'
          || 'CLOSEST THE ESTATE GOT: corpus ' || coalesce(v_best_corp, 'none')
          || ', cosine ' || coalesce(round(v_best_sim, 4)::text, 'n/a')
          || ', lexical rank ' || coalesce(round(v_best_rank, 4)::text, 'n/a')
          || ' (floors: cosine ' || p_min_similarity || ', lexical corroboration ' || p_min_rank
          || ', lexical-only ' || c_lex_only || ').' || E'\n\n'
          || 'DONE MEANS: the knowledge exists in a searchable corpus and this question returns it. '
          || 'Then set sales_knowledge_gap.status to knowledge_added.',
        'assigned', 'advisory', 'knowledge_gap', 'sales_engineer', 3, true, false)
      returning id into v_task;

      insert into sales_knowledge_gap
        (question_norm, question, refusal, best_similarity, best_lexical_rank, nearest_corpus, task_id)
      values (v_norm, left(btrim(p_text), 2000), v_refusal,
              round(v_best_sim, 4), round(v_best_rank, 4), v_best_corp, v_task);
    else
      v_task := v_gap.task_id;
      update sales_knowledge_gap
         set asks = asks + 1, last_asked_at = now(), refusal = v_refusal,
             best_similarity = greatest(coalesce(best_similarity, 0), coalesce(round(v_best_sim, 4), 0)),
             best_lexical_rank = greatest(coalesce(best_lexical_rank, 0), coalesce(round(v_best_rank, 4), 0))
       where id = v_gap.id;
      -- Asked repeatedly is the definition of urgent. The task's priority follows the demand.
      update org_tasks set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
       where id = v_task and status not in ('done', 'cancelled');
    end if;

    v_handoff :=
      'I have not got a sourced answer to that yet, and I will not guess at a procurement question. '
      || 'I have recorded it and opened task #' || coalesce(v_task::text, '?')
      || ', owned by the Sales Engineer, with your question kept word for word. '
      || 'It is being looked into and you will get an answer on it.';
  end if;

  insert into sales_decision_log
    (actor, action, query, min_similarity, min_rank, k, candidates, cited, answered, refusal)
  values
    (coalesce(p_actor, 'sales_engineer'), 'assist', left(p_text, 2000), p_min_similarity,
     p_min_rank, v_k, v_cands, v_cited, cardinality(v_cited) > 0, v_refusal);

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('sales_knowledge','ops_knowledge','kb_chunks','agent_knowledge',
                                 'support_knowledge','category_specs','category_quote_specs'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'lexemes_in_question', coalesce(cardinality(v_lex), 0), 'lexeme_overlap_needed', v_need, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor AND match the all-terms lexical query at ts_rank >= min_rank. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. lexeme_overlap_needed is reported as a diagnostic only: admitting on partial overlap was measured and returned a topically wrong passage, so it does not admit. A nearest neighbour is always found; a lexical match is not.'),
    'refusal', v_refusal,
    'gap_recorded', case when cardinality(v_cited) = 0 then true else false end,
    'task_id', v_task,
    'handoff', v_handoff);
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- SEAT: accountant -- fn_accountant_assist. 2 return path(s), every one of them now carries the company block.
-- The rest of this definition is the routine exactly as it was deployed; only the pinned
-- 'company' key is added.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_accountant_assist(p_text text, p_embedding vector DEFAULT NULL::vector, p_min_similarity numeric DEFAULT 0.86, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_min_overlap numeric DEFAULT 0.60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  v_wide      int := greatest(v_k * 4, 20);
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  v_tq        tsquery;
  v_lex       text[];
  v_nlex      int;
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_lex  int;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_nlex := coalesce(cardinality(v_lex), 0);
  -- The greater of 60% and two lexemes, so a short question cannot be admitted on one common word.
  v_need := case when v_nlex = 0 then 2147483647
                 else greatest(least(2, v_nlex), ceil(coalesce(p_min_overlap, 0.60) * v_nlex)::int) end;

  create temporary table if not exists _aa_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate refuses an unqualified DELETE and a WHERE-less delete on a
  -- scratch table is exactly what that guard exists to catch elsewhere.
  truncate table _aa_cand;

  -- accountant_knowledge -- the seat's own body.
  if p_embedding is not null then
    insert into _aa_cand
    select 'accountant_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || ' · ' || k.epistemic_status,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from accountant_knowledge k
     where k.embedding_gte is not null and k.runtime_index_eligible
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _aa_cand
  select 'accountant_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, '') || ' · ' || k.epistemic_status,
         null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from accountant_knowledge k
   where k.embedding_gte is null and k.runtime_index_eligible and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge -- how this company actually operates. A finance question frequently turns on a
  -- company rule rather than on accounting, and a seat that cannot see those answers half a
  -- question. Superseded rows are excluded: never quote a rule that has been replaced.
  if p_embedding is not null then
    insert into _aa_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.record_type, '') || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- ADMISSION. The cosine floor is a hard AND for every vector-bearing row; corroboration may come
  -- from either the all-terms rank or literal lexeme overlap, and one of the two is required.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity
             and (c.lexical_rank >= p_min_rank or c.lex_hits >= v_need))     as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)             as ok_lexical
      from _aa_cand c
  ), ranked as (
    select j.*, (j.ok_vector or j.ok_lexical) as cited,
           row_number() over (
             order by (case when j.ok_vector or j.ok_lexical then 0 else 1 end),
                      (case when j.has_vector then 0 else 1 end),
                      j.similarity desc nulls last, j.lexical_rank desc) as rn
      from judged j
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'cleared_floor', coalesce(r.has_vector and r.similarity >= p_min_similarity, false),
      'lex_hits', r.lex_hits, 'lex_needed', v_need,
      'corroborated', case when r.has_vector then (r.lexical_rank >= p_min_rank or r.lex_hits >= v_need)
                           else r.lexical_rank >= c_lex_only end,
      'cited', r.cited) order by r.rn) filter (where r.rn <= 40), '[]'::jsonb),
    coalesce(array_agg(r.corpus || ':' || r.record_id order by r.rn)
             filter (where r.cited and r.rn <= v_k), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id, 'title', r.title,
      'provenance', r.provenance,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'content', r.content) order by r.rn) filter (where r.cited and r.rn <= v_k), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from ranked r;

  select max(similarity), max(lexical_rank), max(lex_hits)
    into v_best_sim, v_best_rank, v_best_lex from _aa_cand;
  select corpus into v_best_corp from _aa_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _aa_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;
    v_handoff :=
      'I do not have a sourced answer to that, and I will not guess at a financial or tax question. '
      || 'If it needs a rate, a threshold, a deadline or a penalty, that figure is deliberately not '
      || 'held in my knowledge: it is published by the Federal Tax Authority and must be read from '
      || 'its current publication for the period concerned.';
  end if;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('accountant_knowledge', 'ops_knowledge'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'min_overlap', p_min_overlap, 'lexemes_in_question', v_nlex, 'lexeme_overlap_needed', v_need,
      'best_similarity', round(v_best_sim, 4), 'best_lexical_rank', round(v_best_rank, 4),
      'best_lex_hits', v_best_lex, 'nearest_corpus', v_best_corp, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor -- always -- AND corroborate literally by one of two routes: the all-terms lexical query at ts_rank >= min_rank, or at least lexeme_overlap_needed of the question''s own lexemes present verbatim in the row. The overlap route exists because the all-terms route was measured at exactly ts_rank 0.0000 on 9 of 35 realistic questions whose correct record sat at cosine 0.887-0.933: websearch_to_tsquery ANDs every term, so one filler adverb defeats it. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. A nearest neighbour is always found; a literal match is not.'),
    'refusal', v_refusal,
    'handoff', v_handoff);
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- SEAT: it_engineer -- fn_it_engineer_assist. 2 return path(s), every one of them now carries the company block.
-- The rest of this definition is the routine exactly as it was deployed; only the pinned
-- 'company' key is added.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_it_engineer_assist(p_text text, p_embedding vector DEFAULT NULL::vector, p_min_similarity numeric DEFAULT 0.83, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_min_overlap numeric DEFAULT 0.60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  v_wide      int := greatest(v_k * 4, 20);
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  v_tq        tsquery;
  v_lex       text[];
  v_nlex      int;
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_lex  int;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_nlex := coalesce(cardinality(v_lex), 0);
  -- The greater of 60% and two lexemes, so a short question cannot be admitted on one common word.
  v_need := case when v_nlex = 0 then 2147483647
                 else greatest(least(2, v_nlex), ceil(coalesce(p_min_overlap, 0.60) * v_nlex)::int) end;

  create temporary table if not exists _ite_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate refuses an unqualified DELETE, and a WHERE-less delete on a
  -- scratch table is exactly the shape that guard exists to catch elsewhere.
  truncate table _ite_cand;

  -- it_engineer_knowledge -- the seat's own body.
  if p_embedding is not null then
    insert into _ite_cand
    select 'it_engineer_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || ' · ' || k.epistemic_status,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from it_engineer_knowledge k
     where k.embedding_gte is not null and k.runtime_index_eligible
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _ite_cand
  select 'it_engineer_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, '') || ' · ' || k.epistemic_status,
         null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from it_engineer_knowledge k
   where k.embedding_gte is null and k.runtime_index_eligible and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge -- the 165 it_security_deep rows plus how this company actually operates.
  if p_embedding is not null then
    insert into _ite_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.layer, '') || case when o.module is null then '' else ' · ' || o.module end
             || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- ADMISSION. The cosine floor is a hard AND for every vector-bearing row; corroboration may come
  -- from either the all-terms rank or literal lexeme overlap, and one of the two is required.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity
             and (c.lexical_rank >= p_min_rank or c.lex_hits >= v_need))     as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)             as ok_lexical
      from _ite_cand c
  ), ranked as (
    select j.*, (j.ok_vector or j.ok_lexical) as cited,
           row_number() over (
             order by (case when j.ok_vector or j.ok_lexical then 0 else 1 end),
                      (case when j.has_vector then 0 else 1 end),
                      j.similarity desc nulls last, j.lexical_rank desc) as rn
      from judged j
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'cleared_floor', coalesce(r.has_vector and r.similarity >= p_min_similarity, false),
      'lex_hits', r.lex_hits, 'lex_needed', v_need,
      'corroborated', case when r.has_vector then (r.lexical_rank >= p_min_rank or r.lex_hits >= v_need)
                           else r.lexical_rank >= c_lex_only end,
      'cited', r.cited) order by r.rn) filter (where r.rn <= 40), '[]'::jsonb),
    coalesce(array_agg(r.corpus || ':' || r.record_id order by r.rn)
             filter (where r.cited and r.rn <= v_k), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id, 'title', r.title,
      'provenance', r.provenance,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'content', r.content) order by r.rn) filter (where r.cited and r.rn <= v_k), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from ranked r;

  select max(similarity), max(lexical_rank), max(lex_hits)
    into v_best_sim, v_best_rank, v_best_lex from _ite_cand;
  select corpus into v_best_corp from _ite_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _ite_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;
    v_handoff :=
      'I do not have a sourced answer to that, and I will not guess during an incident. '
      || 'If the question is whether a specific published vulnerability reaches this estate, that '
      || 'is deliberately not held in my knowledge: I hold no CVE identifier, no version-specific '
      || 'vulnerability claim and no patch level, because I cannot read a vulnerability feed and an '
      || 'invented one is worse than none. Determine it against the component''s own advisory and '
      || 'the version the platform actually reports. If the question is about live state, read the '
      || 'live state: the answer is in the database, the edge logs or the deploy history, not here.';
  end if;

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('it_engineer_knowledge', 'ops_knowledge'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'min_overlap', p_min_overlap, 'lexemes_in_question', v_nlex, 'lexeme_overlap_needed', v_need,
      'best_similarity', round(v_best_sim, 4), 'best_lexical_rank', round(v_best_rank, 4),
      'best_lex_hits', v_best_lex, 'nearest_corpus', v_best_corp, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor -- always -- AND corroborate literally by one of two routes: the all-terms lexical query at ts_rank >= min_rank, or at least lexeme_overlap_needed of the question''s own lexemes present verbatim in the row. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. A nearest neighbour is always found; a literal match is not.'),
    'refusal', v_refusal,
    'handoff', v_handoff);
end
$function$;

revoke execute on function public.fn_ceo_context(text, integer, integer) from public;
revoke execute on function public.fn_support_context(text, integer, integer) from public;
grant execute on function public.fn_ceo_context(text, integer, integer) to service_role;
grant execute on function public.fn_support_context(text, integer, integer) to service_role;
