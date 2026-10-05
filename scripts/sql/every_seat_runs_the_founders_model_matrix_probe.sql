-- EVERY SEAT RUNS THE FOUNDER'S MODEL MATRIX - THE PROBE.
-- Seat: sales_engineer. 29 Sep 2026. Founder_instruction 1056.
-- Proves every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql on production, read-only:
-- ONE block that always raises, so nothing it touches survives (it writes nothing anyway), and its verdict travels in
-- the error text as CHK<<PROBE OK ...>> or CHK<<PROBE FAILED ...>>. It calls no model: fn_ai_route and
-- fn_ai_route_review only CHOOSE one.
--
-- WHAT IT ASSERTS
--   1. Functions of EVERY seat resolve as the matrix says, the way ai_gateway resolves them (fn, class, agent):
--      the sales engineer's comparison on Opus, everything else it does on Gemini with luna behind it, its two
--      reviews on luna with Opus behind; the CEO's hard work on Opus, its easy work on Gemini, luna behind both;
--      every other seat, and the shared classes a non-SE caller reaches, on Gemini with DeepSeek behind; speech
--      and video on Gemini with no fallback.
--   2. EVERY review pair is cross-family: for every class with reviews_class, every author class, and each of the
--      author's primary AND fallback models, fn_ai_route_review picks a reviewer and a fallback outside the
--      author's family (the redaction verify always has a fallback); and on the normal path (the author on its
--      primary) the reviewer is the review class's OWN primary or fallback - the pair the matrix names is the pair
--      that runs, never a pool model.
--   3. The fleet: nothing active names Sol, GLM or Qwen 3.8; every model a policy names is registered, approved
--      and HELD with the fleet's open_until (still in the future); every Opus row leaves room for thinking; no
--      class falls back to itself; the review pool is luna, Opus, DeepSeek; DeepSeek carries the catalogue's price.
-- Before its file is applied: node scripts/qsql.mjs on (the change file + this file) replays both in one aborted
-- transaction, which is how the PR proved it.

do $p$
declare
  c_gem  constant text := 'google/gemini-3.8-flash';
  c_opus constant text := 'anthropic/claude-opus-5.5';
  c_luna constant text := 'openai/gpt-6-luna';
  c_deep constant text := 'deepseek/deepseek-v4.1-flash';
  bad jsonb := '[]'::jsonb;
  r record; a record; m text; v jsonb; fam text; n_route int := 0; n_pair int := 0; n_class int := 0;
  v_hold timestamptz;
  fam_of constant text := 'select lower(btrim(provider)) from public.model_registry where model_id = $1';
  f_model text; f_fb text;
begin
  -- ── 1. ONE ROUTE PER FUNCTION, EVERY SEAT ─────────────────────────────────────────────────────────
  for r in select * from (values
    -- sales_engineer
    ('SE quote_compare',               null,                          'quote_compare',           null,               c_opus, c_luna),
    ('SE quote_review',                null,                          'quote_review',            null,               c_opus, c_luna),
    ('SE quote_extract',               null,                          'quote_extract',           null,               c_gem,  c_luna),
    ('SE doc_extract',                 null,                          'doc_extract',             null,               c_gem,  c_luna),
    ('SE license_extract',             null,                          'license_extract',         null,               c_gem,  c_luna),
    ('SE extract_text',                null,                          'extract_text',            null,               c_gem,  c_luna),
    ('SE supplier_catalog_ingest',     null,                          'supplier_catalog_ingest', null,               c_gem,  c_luna),
    ('SE drawing_boq',                 null,                          'drawing_boq',             null,               c_gem,  c_luna),
    ('SE drawing_redact find',         null,                          'drawing_redact',          null,               c_gem,  c_luna),
    ('SE drawing_redact_verify',       null,                          'drawing_redact_verify',   null,               c_luna, c_opus),
    ('SE drawing_boq_confirm',         'drawing_boq_confirm',         'drawing_boq',             null,               c_luna, c_opus),
    ('SE inquiry_intake',              null,                          'inquiry_intake',          null,               c_gem,  c_luna),
    ('SE inquiry_parse',               null,                          'inquiry_parse',           null,               c_gem,  c_luna),
    ('SE supplier_review',             null,                          'supplier_review',         null,               c_gem,  c_luna),
    ('SE inquiry_ai',                  null,                          'inquiry_ai',              null,               c_gem,  c_luna),
    ('SE project_consultant',          null,                          'project_consultant',      null,               c_gem,  c_luna),
    ('SE supplier_onboard',            null,                          'supplier_onboard',        null,               c_gem,  c_luna),
    ('SE customer_api',                null,                          'customer_api',            null,               c_gem,  c_luna),
    ('SE messages_api',                null,                          'messages_api',            null,               c_gem,  c_luna),
    ('SE route_inquiry',               null,                          'route_inquiry',           null,               c_gem,  c_luna),
    ('SE transcribe',                  null,                          'transcribe',              null,               c_gem,  null),
    ('SE portal assistant',            'customer_portal_assistant',   'site_assistant',          'sales_engineer',   c_gem,  c_luna),
    ('SE reasoning',                   'sales_engineer_reasoning',    'sales_engineer',          'sales_engineer',   c_gem,  c_luna),
    ('SE think plan',                  'routine_employee_reasoning',  'sales_engineer',          'sales_engineer',   c_gem,  c_luna),
    ('SE think decide',                'internal_judgement',          'sales_engineer',          'sales_engineer',   c_gem,  c_luna),
    ('SE think customer',              'customer_communication',      'supplier_api',            'sales_engineer',   c_gem,  c_luna),
    ('SE think supplier',              'supplier_communication',      'supplier_api',            'sales_engineer',   c_gem,  c_luna),
    ('SE unmapped',                    null,                          'supplier_portal',         'sales_engineer',   c_gem,  c_luna),
    ('SE on a shared vision class',    'vision',                      'supplier_api',            'sales_engineer',   c_gem,  c_luna),
    -- ceo
    ('CEO judgement (hard)',           'ceo_judgement',               'ceo_agent',               null,               c_opus, c_luna),
    ('CEO approval (hard)',            'ceo_approval_decision',       'ceo_agent',               'ceo',              c_opus, c_luna),
    ('CEO strategy (hard)',            'ceo_strategic_planning',      'ceo_agent',               'ceo',              c_opus, c_luna),
    ('CEO report (hard)',              'executive_report',            'ceo_agent',               'ceo',              c_opus, c_luna),
    ('CEO think decide (hard)',        'internal_judgement',          'ceo_agent',               'ceo',              c_opus, c_luna),
    ('CEO think plan (easy)',          'routine_employee_reasoning',  'ceo_agent',               'ceo',              c_gem,  c_luna),
    ('CEO think customer (easy)',      'customer_communication',      'ceo_agent',               'ceo',              c_gem,  c_luna),
    ('CEO unmapped (easy)',            null,                          'zz_probe_ceo_unmapped',   'ceo',              c_gem,  c_luna),
    ('CEO on a shared class (easy)',   'summarization',               'ceo_agent',               'ceo',              c_gem,  c_luna),
    -- customer_support
    ('CS wa_inbound',                  null,                          'wa_inbound',              null,               c_gem,  c_deep),
    ('CS widget visitor',              'visitor_chat',                'site_assistant',          'customer_support', c_gem,  c_deep),
    ('CS email_triage',                null,                          'email_triage',            null,               c_gem,  c_deep),
    ('CS directive parse',             'json_extraction',             'founder_directive',       null,               c_gem,  c_deep),
    ('CS think decide',                'internal_judgement',          'wa_inbound',              'customer_support', c_gem,  c_deep),
    ('CS unmapped',                    null,                          'zz_probe_cs_unmapped',    'customer_support', c_gem,  c_deep),
    -- accountant
    ('ACC expense',                    'accountant_expense_classification', 'accountant',        'accountant',       c_gem,  c_deep),
    ('ACC think plan',                 'routine_employee_reasoning',  'accountant',              'accountant',       c_gem,  c_deep),
    ('ACC unmapped class',             'accountant_sweep',            'accountant',              'accountant',       c_gem,  c_deep),
    -- it_engineer
    ('IT reasoning',                   'engineering_reasoning',       'resilience_ping',         'it_engineer',      c_gem,  c_deep),
    ('IT unmapped',                    null,                          'zz_probe_it_unmapped',    'it_engineer',      c_gem,  c_deep),
    -- marketing
    ('MKT social inbox',               null,                          'marketing_social_inbox',  null,               c_gem,  c_deep),
    ('MKT plan',                       'marketing_plan',              'marketing',               'marketing',        c_gem,  c_deep),
    ('MKT watch (video+audio)',        'marketing_watch',             'marketing',               'marketing',        c_gem,  null),
    -- the shared classes, reached by a caller that is not the sales engineer
    ('shared document_extraction',     null,                          'capability_agent',        null,               c_gem,  c_deep),
    ('shared json_extraction',         null,                          'canon_eval',              null,               c_gem,  c_deep),
    ('shared procurement_reasoning',   null,                          'analytics_recommend',     null,               c_gem,  c_deep),
    ('shared customer_communication',  null,                          'support_ai',              null,               c_gem,  c_deep),
    ('shared agent_reasoning',         null,                          'agent_brain',             null,               c_gem,  c_deep)
  ) t(label, cls, fn, agent, want_p, want_f) loop
    v := public.fn_ai_route(r.cls, null, null, r.fn, false, null, r.agent);
    n_route := n_route + 1;
    if coalesce(v->>'model', 'none') <> r.want_p or coalesce(v->>'fallback', 'none') <> coalesce(r.want_f, 'none') then
      bad := bad || to_jsonb(r.label || ' got ' || coalesce(v->>'model', 'none') || '>' || coalesce(v->>'fallback', 'none')
                             || ' on ' || coalesce(v->>'task_class', '?'));
    end if;
  end loop;

  -- A voice note carries an audio part, so ai_gateway asks for 'audio': still Gemini, and still NO second model -
  -- the only other active model that hears is the web-grounded :online variant, which is never a substitute.
  v := public.fn_ai_route(null, null, null, 'transcribe', false, array['audio'], null);
  n_route := n_route + 1;
  if coalesce(v->>'model', 'none') <> c_gem or v->>'fallback' is not null then
    bad := bad || to_jsonb('SE transcribe with audio got ' || coalesce(v->>'model', 'none') || '>' || coalesce(v->>'fallback', 'none'));
  end if;

  -- A confident CEO is still on Opus: the confidence-prior downgrade no longer moves an 'xlarge' (named hard) route.
  v := public.fn_ai_route('ceo_strategic_planning', null, 0.99, 'ceo_agent', false, null, 'ceo');
  n_route := n_route + 1;
  if coalesce(v->>'model', 'none') <> c_opus then
    bad := bad || to_jsonb('CEO strategy at confidence 0.99 got ' || coalesce(v->>'model', 'none'));
  end if;

  -- A think() decision's author is found: a marketing decision billed where think() bills it (internal_judgement,
  -- on Gemini) proves its author, and the CEO's cross-family review opens. Everything here is rolled back by the
  -- final raise; the handoff it opens goes to the CEO seat, never to a person.
  insert into public.ai_cost_log (fn, agent_key, seat, task_class, model_used, ok)
  values ('zz_probe_author', 'marketing', 'marketing', 'internal_judgement', c_gem, true);
  begin
    v := public.fn_seat_duty_cross_review('marketing.zz_probe_author', 'marketing', 'ceo', 'Probe: is this plan sound?',
           '{"probe": true}'::jsonb, '{"plan": "probe"}'::jsonb, jsonb_build_object('model', c_gem), null, null);
    if not exists (select 1 from public.seat_deliberation where question = 'Probe: is this plan sound?' and author_model = c_gem) then
      bad := bad || to_jsonb('a think() decision''s author was not proven: ' || left(coalesce(v::text, 'null'), 200));
    end if;
  exception when others then
    bad := bad || to_jsonb('the author proof of a think() decision raised: ' || left(sqlerrm, 200));
  end;

  -- ... and only a RECENT one: an internal_judgement call older than 24 hours is no proof. The gate infers the author
  -- from the seat's last call in 24 hours; with only a 2-day-old row it must find none (author 'deterministic').
  delete from public.ai_cost_log where seat = 'accountant' and task_class = 'internal_judgement';
  insert into public.ai_cost_log (occurred_at, fn, agent_key, seat, task_class, model_used, ok)
  values (now() - interval '2 days', 'zz_probe_author_stale', 'accountant', 'accountant', 'internal_judgement', c_gem, true);
  begin
    v := public.fn_high_stakes_gate('zz_probe_stale', 'accountant', 'zz_probe', 'stale', 'ZZ DEMO stale author probe',
           '{}'::jsonb, '{}'::jsonb, null, null, true);
    if coalesce(v->>'author_model', '') = c_gem then
      bad := bad || to_jsonb('a 2-day-old internal_judgement call was accepted as the author'::text);
    end if;
  exception when others then
    bad := bad || to_jsonb('the stale-author gate raised: ' || left(sqlerrm, 200));
  end;

  -- A seat's own route never allows fewer tokens than the class it splits.
  for r in select s.task_class, split_part(s.task_class, '__', 1) seat, split_part(s.task_class, '__', 2) base, b.max_tokens base_max
             from public.model_policy s join public.model_policy b on b.task_class = split_part(s.task_class, '__', 2)
            where s.active and position('__' in s.task_class) > 0 loop
    v := public.fn_ai_route(r.base, null, null, 'zz_probe_ceiling', false, null, r.seat);
    n_route := n_route + 1;
    -- the seat's row supplies the models (policy_class) while the call is still logged as the class itself
    if v->>'policy_class' is distinct from r.task_class or v->>'task_class' is distinct from r.base
       or coalesce((v->>'max_tokens')::int, 0) < coalesce(r.base_max, 0) then
      bad := bad || to_jsonb(r.task_class || ' routed as ' || coalesce(v->>'task_class', '?') || '/' || coalesce(v->>'policy_class', '?')
                             || ' with ' || coalesce(v->>'max_tokens', '?') || ' tokens, base allows ' || coalesce(r.base_max::text, '?'));
    end if;
  end loop;

  -- The consumer register knows think()'s classes, the seat routes and the moved functions.
  if not (public.fn_it_model_consumer_listed('wa_inbound', 'internal_judgement')
          and public.fn_it_model_consumer_listed('accountant', 'routine_employee_reasoning')
          and public.fn_it_model_consumer_listed('ceo_agent', 'internal_judgement')
          and public.fn_it_model_consumer_listed('sales_engineer', 'customer_communication')
          and public.fn_it_model_consumer_listed('quote_extract', 'sales_engineer__document_extraction')
          and public.fn_it_model_consumer_listed('inquiry_intake', 'inquiry_qualification_conversation')
          and public.fn_it_model_consumer_listed('drawing_boq', 'drawing_and_boq_analysis')) then
    bad := bad || to_jsonb('a think() class, a seat route or a moved function reads as an unlisted model consumer'::text);
  end if;

  -- The same routes through the review router, the way ai_gateway takes a call that names counterpart_model.
  for r in select * from (values
    ('SE verify over Gemini',          'knowledge_validation',      'sales_engineer',   c_gem,  null::text[],     c_luna, c_opus),
    ('CEO verify over Opus',           'knowledge_validation',      'ceo',              c_opus, null,             c_luna, c_deep),
    ('CEO verify over Gemini',         'knowledge_validation',      'ceo',              c_gem,  null,             c_luna, c_deep),
    ('CS verify over Gemini',          'knowledge_validation',      'customer_support', c_gem,  null,             c_deep, c_luna),
    ('comparison over Gemini reads',   'quote_comparison',          null,               c_gem,  null,             c_opus, c_luna),
    ('redaction verify over Gemini',   'identity_redaction_verify', null,               c_gem,  array['vision'],  c_luna, c_opus),
    ('redaction verify over luna',     'identity_redaction_verify', null,               c_luna, array['vision'],  c_opus, c_deep),
    ('CEO judges Gemini seats',        'ceo_judgement',             'ceo',              c_gem,  null,             c_opus, c_luna),
    ('CEO blind review of marketing',  'seat_deliberation_blind',   'ceo',              c_gem,  null,             c_opus, c_luna)
  ) t(label, cls, agent, author, caps, want_p, want_f) loop
    v := public.fn_ai_route_review_for(r.cls, r.author, r.agent, null, null, r.caps);
    n_route := n_route + 1;
    if coalesce(v->>'model', 'none') <> r.want_p or coalesce(v->>'fallback', 'none') <> r.want_f then
      bad := bad || to_jsonb(r.label || ' got ' || coalesce(v->>'model', 'none') || '>' || coalesce(v->>'fallback', 'none'));
    end if;
  end loop;

  -- ── 2. EVERY REVIEW PAIR IS CROSS-FAMILY ──────────────────────────────────────────────────────────
  for r in select p.task_class, p.model_primary, p.model_fallback, p.reviews_class from public.model_policy p
            where p.active and cardinality(coalesce(p.reviews_class, '{}')) > 0 order by 1 loop
    for a in select x.cls from unnest(r.reviews_class) x(cls) loop
      if not exists (select 1 from public.model_policy p where p.task_class = a.cls and p.active) then
        bad := bad || to_jsonb(r.task_class || ' reviews ' || a.cls || ', which is no active class'); continue;
      end if;
    end loop;
    -- every route an author class can run on: its own row AND every seat's own row for it ('<seat>__<class>'), since
    -- a sales engineer or CEO call on that class takes the seat's models while it is logged as the class
    -- ... and, where the author's row has a fallback and is not itself a review, every seat's own plan B (the
    -- fallback of a catch-all row replaces the class's for that seat's calls, section 3 of the change file)
    for a in select x.cls, p.task_class route_row, p.model_primary,
                    array_remove(array[p.model_fallback], null)
                    || case when p.model_fallback is null or cardinality(coalesce(p.reviews_class, '{}')) > 0 then '{}'::text[]
                            else array(select distinct i.fallback_model from public.model_policy_by_identity i
                                        where i.scope = 'current_agent' and i.fallback_model is not null) end fallbacks
               from unnest(r.reviews_class) x(cls)
               join public.model_policy p on p.active
                and (p.task_class = x.cls or right(p.task_class, length(x.cls) + 2) = '__' || x.cls) loop
      -- the normal path (the author on its primary) is served by the review's OWN pair, never by the pool: the pair
      -- the matrix names is the pair that runs. (seat_deliberation reviews in both directions - a CEO plan on Opus is
      -- judged by the class's fallback, luna - so this is asserted on the pick, not on the primary alone.)
      v := public.fn_ai_route_review(r.task_class, a.model_primary);
      if a.model_primary not in ('none', 'none/deterministic')
         and coalesce(v->>'model', 'none') not in (r.model_primary, coalesce(r.model_fallback, 'none')) then
        bad := bad || to_jsonb(r.task_class || ' over ' || a.route_row || ' on ' || a.model_primary || ' left its own pair: '
                               || coalesce(v->>'model', 'none'));
      end if;
      foreach m in array array(select distinct y from unnest(array[a.model_primary] || a.fallbacks) y where y is not null) loop
        continue when m in ('none', 'none/deterministic');
        v := public.fn_ai_route_review(r.task_class, m);
        n_pair := n_pair + 1;
        execute fam_of into fam using m;
        execute fam_of into f_model using v->>'model';
        execute fam_of into f_fb using v->>'fallback';
        if v->>'model' is null then
          bad := bad || to_jsonb(r.task_class || ' over ' || a.route_row || ' on ' || m || ': no reviewer');
        elsif f_model = fam or f_fb = fam then
          bad := bad || to_jsonb(r.task_class || ' over ' || m || ' routed ' || (v->>'model') || '>' || coalesce(v->>'fallback', 'none'));
        end if;
        if r.task_class = 'identity_redaction_verify' and v->>'fallback' is null then
          bad := bad || to_jsonb('identity_redaction_verify over ' || m || ' has no fallback');
        end if;
      end loop;
    end loop;
  end loop;

  -- ── 3. THE FLEET ──────────────────────────────────────────────────────────────────────────────────
  select max(open_until) into v_hold from public.llm_route_health;
  if v_hold is null or v_hold < now() + interval '1 year' then
    bad := bad || to_jsonb('the hold is not on: max(open_until) = ' || coalesce(v_hold::text, 'null'));
  end if;
  for r in select distinct x.m from public.model_policy p, unnest(array[p.model_primary, p.model_fallback]) x(m)
            where p.active and p.tier <> 'none' and x.m is not null and x.m not in ('none', 'none/deterministic') loop
    if not exists (select 1 from public.model_registry g where g.model_id = r.m and g.active and g.approved) then
      bad := bad || to_jsonb(r.m || ' is named by a policy and not an active approved registry row');
    end if;
    if not exists (select 1 from public.llm_route_health h where h.model_id = r.m and h.open_until = v_hold) then
      bad := bad || to_jsonb(r.m || ' is named by a policy and not held with the fleet');
    end if;
    if r.m in ('openai/gpt-5.6-sol', 'z-ai/glm-5.3-flash', 'qwen/qwen3.8-max-0902') then
      bad := bad || to_jsonb(r.m || ' is still named by an active policy');
    end if;
  end loop;
  -- every class that calls a model is on the matrix's four models, except the measurement classes named in the file
  for r in select task_class, model_primary, model_fallback from public.model_policy
            where active and tier <> 'none'
              and task_class not in ('marketing_geo_search', 'marketing_geo_online')
              and (model_primary not in (c_gem, c_opus, c_luna, c_deep)
                   or coalesce(model_fallback, 'x') not in (c_luna, c_deep, c_opus, 'x')) loop
    bad := bad || to_jsonb(r.task_class || ' is off the matrix: ' || r.model_primary || '>' || coalesce(r.model_fallback, 'none'));
  end loop;
  -- ── 4. EVERY CLASS HAS A SEAT AND A ROUTE IN THE MATRIX (marketing, 29 Sep 2026) ─────────────────────
  -- #1114 merged after #1126 and added three classes on Sol; nothing asked which seat they belonged to. Every active
  -- class that calls a model is named here with its seat and its route, and runs exactly that route's pair. A NEW
  -- class with no line here is a finding: whoever adds it decides its seat here, in the same PR.
  -- ('measure' = the GEO measurement engines, whose models are the measurement itself; their pair is not asserted.)
  for r in
    -- (4 Oct 2026, item 21) each route also carries the TIER the change file's sections 4a/4b write for it and the
    -- max_tokens FLOOR its section 4d writes: 4000 on every route with Opus as primary or fallback (room for thinking),
    -- else only "set" (>= 1). drawing_and_boq_analysis has its own 8000 (4d), asserted below the loop.
    with route(route, p, f, t, min_tok) as (values
      ('se', c_gem, c_luna, 'medium', 1), ('se_compare', c_opus, c_luna, 'xlarge', 4000), ('se_review', c_luna, c_opus, 'small', 4000),
      ('ceo_hard', c_opus, c_luna, 'xlarge', 4000), ('ceo_review', c_luna, c_deep, 'small', 1), ('other', c_gem, c_deep, 'medium', 1),
      ('other_review', c_deep, c_luna, 'small', 1), ('hears', c_gem, null, 'medium', 1), ('measure', null, null, null, null)),
    matrix(cls, seat, route) as (values
      ('quote_comparison', 'sales_engineer', 'se_compare'), ('sales_engineer_reasoning', 'sales_engineer', 'se'),
      ('customer_portal_assistant', 'sales_engineer', 'se'), ('inquiry_qualification_conversation', 'sales_engineer', 'se'),
      ('rfq_routing', 'sales_engineer', 'se'), ('redaction_detection', 'sales_engineer', 'se'),
      ('drawing_and_boq_analysis', 'sales_engineer', 'se'), ('identity_redaction_verify', 'sales_engineer', 'se_review'),
      ('drawing_boq_confirm', 'sales_engineer', 'se_review'), ('speech_transcription', 'sales_engineer', 'hears'),
      ('sales_engineer__document_extraction', 'sales_engineer', 'se'), ('sales_engineer__json_extraction', 'sales_engineer', 'se'),
      ('sales_engineer__procurement_reasoning', 'sales_engineer', 'se'), ('sales_engineer__knowledge_validation', 'sales_engineer', 'se_review'),
      ('ceo_judgement', 'ceo', 'ceo_hard'), ('ceo_approval_decision', 'ceo', 'ceo_hard'), ('ceo_strategic_planning', 'ceo', 'ceo_hard'),
      ('chief_of_staff_decision', 'ceo', 'ceo_hard'), ('executive_report', 'ceo', 'ceo_hard'), ('department_planning', 'ceo', 'ceo_hard'),
      ('seat_deliberation_blind', 'ceo', 'ceo_hard'), ('seat_deliberation_compare', 'ceo', 'ceo_hard'),
      ('ceo_article_review', 'ceo', 'ceo_hard'), ('ceo__internal_judgement', 'ceo', 'ceo_hard'), ('ceo__knowledge_validation', 'ceo', 'ceo_review'),
      ('accountant_expense_classification', 'accountant', 'other'), ('accountant_receipt_extraction', 'accountant', 'other'),
      ('accountant_weekly_report', 'accountant', 'other'), ('finance_analysis', 'accountant', 'other'),
      ('support_ai', 'customer_support', 'other'), ('visitor_chat', 'customer_support', 'other'), ('wa_inbound', 'customer_support', 'other'),
      ('email_triage', 'customer_support', 'other'), ('inbound_email', 'customer_support', 'other'),
      ('resend_inbound', 'customer_support', 'other'), ('intent_detection', 'customer_support', 'other'),
      ('engineering_reasoning', 'it_engineer', 'other'), ('reflection_and_learning', 'it_engineer', 'other'),
      ('security_incident_analysis', 'it_engineer', 'other'), ('edge_case_escalation', 'it_engineer', 'other'), ('health_ping', 'it_engineer', 'other'),
      ('marketing_copy', 'marketing', 'other'), ('marketing_evaluate', 'marketing', 'other'), ('marketing_plan', 'marketing', 'other'),
      ('marketing_plan_defend', 'marketing', 'other'), ('marketing_quality_review', 'marketing', 'other'),
      ('marketing_research', 'marketing', 'other'), ('marketing_watch', 'marketing', 'hears'),
      ('marketing_article_draft', 'marketing', 'other'), ('marketing_article_revise', 'marketing', 'other'),
      ('marketing_geo_search', 'marketing', 'measure'), ('marketing_geo_online', 'marketing', 'measure'),
      ('customer_communication', 'shared', 'other'), ('supplier_communication', 'shared', 'other'),
      ('agent_reasoning', 'shared', 'other'), ('routine_employee_reasoning', 'shared', 'other'), ('internal_judgement', 'shared', 'other'),
      ('general_drafting', 'shared', 'other'), ('category_classification', 'shared', 'other'), ('content_drafting', 'shared', 'other'),
      ('contract_analysis', 'shared', 'other'), ('legal_analysis', 'shared', 'other'), ('document_extraction', 'shared', 'other'),
      ('document_extraction_multimodal', 'shared', 'other'), ('json_extraction', 'shared', 'other'), ('json_extraction_text', 'shared', 'other'),
      ('ocr', 'shared', 'other'), ('ocr_cleanup', 'shared', 'other'), ('vision', 'shared', 'other'),
      ('procurement_reasoning', 'shared', 'other'), ('knowledge_ingestion', 'shared', 'other'), ('knowledge_research', 'shared', 'other'),
      ('memory_retrieval', 'shared', 'other'), ('summarization', 'shared', 'other'), ('translation', 'shared', 'other'),
      ('translation_general', 'shared', 'other'), ('knowledge_validation', 'shared', 'other_review'))
    select p.task_class, p.model_primary, p.model_fallback, p.tier, p.max_tokens, m.seat, m.route, rt.p want_p, rt.f want_f,
           rt.t want_t, rt.min_tok
      from public.model_policy p
      left join matrix m on m.cls = p.task_class
      left join route rt on rt.route = m.route
     where p.active and p.tier <> 'none' and p.model_primary not in ('none', 'none/deterministic')
  loop
    n_class := n_class + 1;
    if r.seat is null then
      bad := bad || to_jsonb(r.task_class || ' has no seat in the matrix (add it to section 4 of this probe)');
    elsif r.route <> 'measure' and (r.model_primary is distinct from r.want_p or r.model_fallback is distinct from r.want_f) then
      bad := bad || to_jsonb(r.task_class || ' (' || r.seat || ', ' || r.route || ') runs ' || r.model_primary || '>'
                             || coalesce(r.model_fallback, 'none') || ', the matrix says ' || r.want_p || '>' || coalesce(r.want_f, 'none'));
    elsif r.route <> 'measure' and r.tier is distinct from r.want_t then
      bad := bad || to_jsonb(r.task_class || ' (' || r.route || ') is tier ' || r.tier || ', the matrix says ' || r.want_t);
    elsif r.route <> 'measure' and coalesce(r.max_tokens, 0) < r.min_tok then
      bad := bad || to_jsonb(r.task_class || ' (' || r.route || ') allows ' || coalesce(r.max_tokens::text, 'no') || ' max_tokens, the matrix needs at least ' || r.min_tok);
    end if;
  end loop;
  if (select coalesce(max_tokens, 0) from public.model_policy where task_class = 'drawing_and_boq_analysis') < 8000 then
    bad := bad || to_jsonb('drawing_and_boq_analysis allows fewer than its 8000 max_tokens'::text);
  end if;

  if exists (select 1 from public.model_policy where active and model_fallback = model_primary and model_primary not in ('none', 'none/deterministic')) then
    bad := bad || to_jsonb('a class falls back to its own primary'::text);
  end if;
  if exists (select 1 from public.model_policy where c_opus in (model_primary, model_fallback) and coalesce(max_tokens, 0) < 4000) then
    bad := bad || to_jsonb('an Opus class leaves less than 4000 tokens for thinking'::text);
  end if;
  if (select string_agg(model_id, ',' order by rank) from public.review_pool where active) is distinct from c_luna || ',' || c_opus || ',' || c_deep then
    bad := bad || to_jsonb('review pool is ' || coalesce((select string_agg(model_id, ',' order by rank) from public.review_pool where active), 'empty'));
  end if;
  -- (30 Sep 2026) no price literal here: the catalogue moves prices (deepseek 0.30/1.20 -> 0.0198/0.396); the_registry_prices_are_the_catalogue_s_prices owns price. This asserts the model is registered and able.
  if not exists (select 1 from public.model_registry where model_id = c_deep
                   and context_len = 1048576 and supports_vision and not supports_audio and provider = 'deepseek') then
    bad := bad || to_jsonb('deepseek is not registered as the catalogue serves it'::text);
  end if;
  if (select count(*) from public.model_policy_by_identity i
       where i.scope = 'current_agent'
         and ((i.identity_key in ('sales_engineer', 'ceo') and (i.primary_model, i.fallback_model, i.escalation_model) = (c_gem, c_luna, c_opus))
           or (i.identity_key in ('marketing', 'accountant', 'it_engineer', 'customer_support') and (i.primary_model, i.fallback_model) = (c_gem, c_deep)))) <> 6 then
    bad := bad || to_jsonb('a seat catch-all in model_policy_by_identity is off the matrix'::text);
  end if;

  if jsonb_array_length(bad) = 0 then
    raise exception 'CHK<<PROBE OK routes=% review_pairs=% classes=% hold_until=%>>', n_route, n_pair, n_class, v_hold::date;
  end if;
  -- the management API returns only the first ~2,000 characters of an error: six findings and the count travel
  raise exception 'CHK<<PROBE FAILED count=% routes=% pairs=% %>>', jsonb_array_length(bad), n_route, n_pair,
    (select jsonb_agg(x) from (select x from jsonb_array_elements(bad) x limit 6) q)::text;
end $p$;
