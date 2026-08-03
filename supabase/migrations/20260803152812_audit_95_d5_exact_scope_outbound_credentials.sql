-- AUDIT 9.5 / decision D5 (3 Aug 2026): replace the tier credential model with exact scopes.
--
-- WHY D3 HAD TO BE REVISED. A coverage check - every caller must have ONE credential whose scope
-- is a superset of the callees it actually hops to - was run against the 12 credentials D3 issued.
-- It found two defects:
--
--   1. SEVEN callers had no covering credential at all: agent_brain, dropbox_backup,
--      kb_autofill_gaps, kb_deepen, os_pages, route_inquiry, secretary_act. Five of the seven are
--      named in the repair brief's own list of "29 fn.ai callers"; the brief says the multi-callee
--      ones "take their per-caller credential instead", but those per-caller credentials were never
--      issued. Migrating as written would have produced the first out_of_scope outage in production.
--
--   2. TWENTY more callers were materially over-granted. Nine callers needing one or two callees
--      would each have received fn.internal's 22 slugs. canon_eval needs only agent_brain and would
--      have been handed send_outbox, alert_founder, asset_delete, meta_ads and postiz_publish.
--      That is the shared secret with extra steps, which is the thing 9.5 exists to remove.
--
-- THE MODEL NOW. One credential per distinct callee-set, reusing an existing credential wherever
-- its scope is already an exact match. Every over-grant goes to zero. fn.docs, fn.knowledge and
-- fn.internal become unused and are retired below.
--
-- D3's PRECISE credentials are KEPT AS PRECISE. fn.reveal_invoice and fn.pdpl_request have scopes
-- that other callers share, but D3 issued them deliberately so a leak on the money and PII paths is
-- attributable to one caller. Retiring them into a shared bucket would throw that away, so the
-- shared buckets fn.to_pdf_native and fn.to_alert_founder are minted alongside them instead.
--
-- CORRECTION carried into the scopes: os_pages does NOT get deploy_next_preview. os_pages:168 posts
-- __deploy_secret (app_secrets.deploy_secret), not __secret, so that hop never reaches
-- fn_internal_auth at all. The deploy channel is a separate, correctly segregated authority and
-- putting it in an internal scope would have misrepresented it as one. Same reason it is removed
-- from the retiring fn.internal.
--
-- SAFE TO APPLY BEFORE THE CODE CHANGES, exactly as D3 was: issuing a credential grants nothing by
-- itself, nothing presents it until a caller is migrated, and fn_internal_auth still accepts the
-- legacy shared secret. Purely additive.
--
-- IDEMPOTENT: a context that already holds a live credential is skipped, never re-minted, because
-- the plaintext is returned once and a blind re-issue would orphan the value already distributed.

do $$
declare
  v jsonb;
  r record;
  v_issued int := 0;
  v_skipped int := 0;
begin
  for r in
    select * from (values
      -- ---- SHARED EXACT-SCOPE BUCKETS ---------------------------------------------------------
      -- Named for the callee, not for a caller, because more than one caller shares them and
      -- naming a shared credential after one of its holders is how fn.internal became misleading.
      ('fn.to_pdf_native',     'cred_fn_to_pdf_native',     array['pdf_native']),                   -- compliance_archive doc_render make_pdf
      ('fn.to_alert_founder',  'cred_fn_to_alert_founder',  array['alert_founder']),                -- cost_snapshot uptime_check
      ('fn.to_make_pdf',       'cred_fn_to_make_pdf',       array['make_pdf']),                     -- agent_learnings_report collections_legal
      ('fn.to_route_inquiry',  'cred_fn_to_route_inquiry',  array['route_inquiry']),                -- dispatch_inquiry match_eval
      ('fn.to_agent_brain',    'cred_fn_to_agent_brain',    array['agent_brain']),                  -- canon_eval

      -- ---- ONE CALLER, ONE CREDENTIAL ---------------------------------------------------------
      ('fn.agent_act',         'cred_fn_agent_act',         array['meta_ads','postiz_publish']),
      ('fn.agent_brain',       'cred_fn_agent_brain',       array['ai_gateway','kb_deepen','kb_search']),
      ('fn.agents',            'cred_fn_agents',            array['make_pdf','make_xlsx']),
      ('fn.alert_founder',     'cred_fn_alert_founder',     array['send_whatsapp']),
      ('fn.attach_photos',     'cred_fn_attach_photos',     array['drawing_redact']),
      ('fn.dept_learn',        'cred_fn_dept_learn',        array['dept_learn']),
      ('fn.dept_plan',         'cred_fn_dept_plan',         array['dept_plan']),
      ('fn.dropbox_backup',    'cred_fn_dropbox_backup',    array['make_pdf','quote_compare']),
      ('fn.dropbox_oauth',     'cred_fn_dropbox_oauth',     array['dropbox_sync']),
      ('fn.email_cron',        'cred_fn_email_cron',        array['send_outbox']),
      ('fn.inbound_email',     'cred_fn_inbound_email',     array['profile_ai']),
      ('fn.kb_autofill_gaps',  'cred_fn_kb_autofill_gaps',  array['alert_founder','kb_fill_gap']),
      ('fn.kb_deepen',         'cred_fn_kb_deepen',         array['ai_gateway','kb_ingest_text']),
      ('fn.knowledge_exam',    'cred_fn_knowledge_exam',    array['kb_search']),
      ('fn.marketing_draft',   'cred_fn_marketing_draft',   array['marketing_image']),
      ('fn.os_pages',          'cred_fn_os_pages',          array['ai_gateway','translate_html']),
      ('fn.reg_fetch',         'cred_fn_reg_fetch',         array['kb_ingest']),
      ('fn.resilience_ping',   'cred_fn_resilience_ping',   array['alert_founder','send_outbox']),
      ('fn.route_inquiry',     'cred_fn_route_inquiry',     array['ai_gateway','inquiry_parse']),
      ('fn.social_stage',      'cred_fn_social_stage',      array['postiz_publish']),
      -- secretary_act's four extra callees come from its dynamic callFn(name, ...) dispatch at
      -- secretary_act:25, read by hand rather than guessed: intent_router, finance_ingest,
      -- postiz_publish, asset_delete.
      ('fn.secretary_act',     'cred_fn_secretary_act',     array['agent_brain','ai_gateway','asset_delete','finance_ingest','intent_router','postiz_publish']),

      -- cos_execute dispatches to org_action_executor.target. This scope is the 39 kind='edge'
      -- targets live in that registry today, plus its own resolved agent_brain hop. It is wide
      -- because the executor genuinely is - it can reach refunds_api, send_outbox and support_ai -
      -- so the containment for this one is NOT the scope. It is the registry write constraint in
      -- the companion migration, which makes THIS credential's scope the source of truth for what
      -- may be added. See 20260803153500.
      ('fn.cos_execute',       'cred_fn_cos_execute',       array[
          'agent_autogen','agent_brain','agent_learnings_report','ai_health','alert_founder',
          'analytics_recommend','boost_recommend','collections_legal','compliance_archive',
          'content_revise','cos_execute','cost_snapshot','doc_reminder','enrich_capability',
          'exec_agents','finance_doc','finance_ingest','inquiry_ai','kb_deepen','kb_fill_gap',
          'knowledge_exam','kyc','legal_review','marketing_draft','match','money_tests',
          'os_incidents','pdpl_request','profile_ai','qa_suite','quote_compare','refunds_api',
          'resilience_ping','route_inquiry','send_outbox','seo_gen','social_stage','support_ai',
          'uptime_check','vt_scan'])
    ) as t(ctx, k, scope)
  loop
    if exists (select 1 from public.internal_credential c
                where c.context = r.ctx and c.active and c.retired_at is null) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v := public.fn_internal_credential_issue(
           r.ctx, r.scope,
           'D5 exact-scope outbound caller credential, issued 3 Aug 2026 from the resolved hop '
           || 'inventory plus a coverage check against every caller');

    -- Distribution stays on app_secrets (decision D2). The limit is unchanged and still recorded:
    -- any compromised edge function can read every row here, so scoping buys attribution, rotation
    -- and containment of a LEAKED credential - it does not contain a compromised function.
    insert into public.app_secrets (key, value)
    values (r.k, v ->> 'secret')
    on conflict (key) do update set value = excluded.value;

    v_issued := v_issued + 1;
  end loop;

  raise notice 'D5 credentials: issued=%, skipped_already_present=%', v_issued, v_skipped;
end $$;

-- The three tier credentials D5 makes unused. They were issued 3 Aug and have never been presented
-- (use_count 0), so retiring them removes nothing that is in service. Done in the same migration as
-- the replacements so the health view never shows a window where both models look live.
--
-- Guarded: a tier that has somehow been used is NOT retired, because that would mean a caller was
-- migrated to it between D3 and now and retiring it would break that caller.
do $$
declare r record; v_retired int := 0; v_held int := 0;
begin
  for r in select context, use_count from public.internal_credential
            where context in ('fn.docs','fn.knowledge','fn.internal')
              and active and retired_at is null
  loop
    if coalesce(r.use_count, 0) > 0 then
      v_held := v_held + 1;
      raise warning 'NOT retiring %: use_count=% - something presented it, investigate before retiring',
                    r.context, r.use_count;
      continue;
    end if;
    update public.internal_credential
       set active = false,
           retired_at = now(),
           label = label || ' | RETIRED 3 Aug 2026 (D5): superseded by exact-scope credentials, never presented'
     where context = r.context;
    delete from public.app_secrets
     where key = 'cred_' || replace(r.context, '.', '_');
    v_retired := v_retired + 1;
  end loop;
  raise notice 'D5 tier retirement: retired=%, held_back=%', v_retired, v_held;
end $$;
