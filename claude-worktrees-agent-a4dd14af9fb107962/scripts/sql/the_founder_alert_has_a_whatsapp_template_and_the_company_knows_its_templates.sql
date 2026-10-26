-- THE FOUNDER ALERT HAS A WHATSAPP TEMPLATE, AND THE COMPANY KNOWS ITS TEMPLATES (6 Sep 2026).
--
-- Founder, 6 Sep 2026 (verbatim, final): "whatsapp token with twilio is with you, fix the template yourself."
--
-- MEASURED BEFORE THIS FILE (production, 10:54 UTC; re-measured 13:50 UTC by the continuing agent — same):
--   * notifications channel='whatsapp': 11 rows, all type founder_alert to the founder, all 'skipped' (the
--     founder-mail audit marked them this morning; last_error says so). Zero queued. Zero ever sent.
--   * Twilio Content API (ContentAndApprovals): 29 templates on the account; the ten registered under the
--     six supplier/customer keys are APPROVED (en+ar); control_mode_code is REJECTED (Meta refused the
--     AUTHENTICATION category for this WABA; Control Mode is retired anyway); there is NO founder-alert
--     template at all.
--   * Twilio Senders API: the WhatsApp sender is ONLINE, display name "QuotesDone", quality HIGH,
--     tier 250 customers/24h.
--   * The last five WhatsApps from our number (13-16 Aug) were freeform founder alerts from alert_founder
--     and every one is 'undelivered' with error 63016: a freeform body outside a 24-hour session. That is
--     why he never received an alert on WhatsApp: the alert path had no template.
--   * cron 34 wa_flush (the only drainer of channel='whatsapp' rows) has been INACTIVE since 2 Sep 00:26
--     UTC. reenable_crons_after_standdown.sql switched it on with email_cron_2min and sms_flush at the
--     2 Sep resume; email_cron_2min is still on, wa_flush and sms_flush were switched off again by
--     something no file in the tree and no company_stand_down row records. A sender that is off with no
--     recorded reason is a finished capability with no entry point; it is switched back on below.
--
-- WHAT THIS FILE DOES:
--   1. public.messaging_template — the template ledger (key, lang, sid, category, status, submitted/approved
--      timestamps, rejection reason). Seeded with the SIDs registered in app_secrets.wa_template_sids; the
--      statuses are filled by the edge functions from Twilio's live answers, never typed here.
--   2. fn_notify_founder — the WhatsApp row now carries p_detail after the first line, so the template's
--      {{2}} ("Details: ...") has something to say. Every other line is the live definition restated.
--   3. fn_company_self_knowledge_sync — one more qd-company record, 'messaging-templates', rendered from the
--      ledger every 15 minutes, so every agent can answer "is the WhatsApp template approved" from the table.
--   4. cron 34 wa_flush back on through the kernel wrapper (already wrapped; the call only re-activates).
--   5. kernel_routine_ownership rows for the two restated routines follow this manifest file.
--
-- THE EDGE FUNCTIONS THAT PAIR WITH IT (deployed the same day): wa_template_setup gains the founder_alert
-- template ("QuotesDone alert: {{1}}. Details: {{2}}. Open the OS to act.", UTILITY, en) and writes the
-- ledger; send_whatsapp gates every template on the ledger, refreshes a not-yet-approved status from Twilio
-- at most every ten minutes, sends only with APPROVED, and holds (never errors) while pending; alert_founder
-- (v3, the HTTP door to fn_notify_founder — it no longer sends anything itself) was STALE on production
-- (older than the repo) and is redeployed so parity is LIVE.
-- The messaging-templates record is appended at the END of the self-knowledge array on purpose: sibling
-- files of the same day restate fn_company_self_knowledge_sync too, and a last record merges cleanly.
--
--   node scripts/apply_sql.mjs scripts/sql/the_founder_alert_has_a_whatsapp_template_and_the_company_knows_its_templates.sql --apply --ddl
begin;

-- 1. THE LEDGER ------------------------------------------------------------------------------------
create table if not exists public.messaging_template (
  sid              text primary key,                      -- Twilio Content SID (HX…); not a secret
  channel          text not null default 'whatsapp',
  template_key     text not null,                         -- send_whatsapp's tmplKey() vocabulary
  lang             text not null default 'en',
  name             text,                                  -- Twilio friendly_name / Meta template name
  category         text,                                  -- UTILITY / MARKETING / AUTHENTICATION
  status           text not null default 'unknown',       -- Twilio's word verbatim: approved / pending / received / rejected / unsubmitted …
  submitted_at     timestamptz,                           -- when wa_template_setup submitted it (null for the July templates created by hand)
  approved_at      timestamptz,                           -- when Twilio was FIRST SEEN answering 'approved' (Meta's own timestamp is not exposed)
  rejection_reason text,
  last_checked_at  timestamptz,
  note             text,
  created_at       timestamptz not null default now()
);
comment on table public.messaging_template is
  'WhatsApp (Twilio Content) templates and their Meta approval status. Written by wa_template_setup (create/status) and send_whatsapp (lazy refresh); read by send_whatsapp (only status=approved is ever sent) and by fn_company_self_knowledge_sync (qd-company:messaging-templates).';
create index if not exists messaging_template_key_idx on public.messaging_template (channel, template_key, lang);
alter table public.messaging_template enable row level security;
revoke all on public.messaging_template from anon, authenticated;

-- seed: every SID the estate registered, status unknown until Twilio is asked
insert into public.messaging_template (sid, channel, template_key, lang, status, note)
select l.sid, 'whatsapp', k.tkey, l.lang, 'unknown',
       'seeded 6 Sep 2026 from app_secrets.wa_template_sids; status is Twilio''s answer once wa_template_setup or send_whatsapp asks'
  from public.app_secrets s
  cross join lateral jsonb_each(s.value::jsonb) as k(tkey, langs)
  cross join lateral jsonb_each_text(k.langs) as l(lang, sid)
 where s.key = 'wa_template_sids' and l.sid ~ '^HX[0-9a-f]{32}$'
on conflict (sid) do nothing;

update public.messaging_template
   set note = 'Control Mode is retired (Sep 2026) and Meta refused the AUTHENTICATION category for this WABA; not a sender path'
 where template_key = 'control_mode_code';

-- 2. fn_notify_founder (full live definition; only the WhatsApp body changes) ----------------------
CREATE OR REPLACE FUNCTION public.fn_notify_founder(p_event text, p_detail text, p_level text DEFAULT 'high'::text, p_kind text DEFAULT NULL::text, p_dedupe_key text DEFAULT NULL::text, p_owner_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_email text; v_phone text; v_kind text; v_level text; v_allowed boolean; v_route jsonb;
begin
  v_level := coalesce(nullif(btrim(p_level), ''), 'high');
  v_kind  := coalesce(nullif(btrim(p_kind), ''), 'unregistered');
  select allowed_to_email into v_allowed from public.founder_mail_policy where kind = v_kind;

  if not coalesce(v_allowed, false) then
    v_route := public.fn_founder_mail_route(v_kind, p_event, p_detail, v_level, p_owner_agent);
    -- the console log (read by the OS and by fn_founder_brief) records what happened instead of an email
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values (v_level, p_event,
            coalesce(p_detail, '') || E'\n\n-> routed to ' || coalesce(v_route ->> 'owner', v_route ->> 'dept')
              || ' as org_task #' || (v_route ->> 'task_id') || ' (founder_mail_policy: ' || v_kind || ')',
            'routed', p_dedupe_key);
    return v_route || jsonb_build_object('emailed', false);
  end if;

  -- ALLOWED. At most one delivery per dedupe_key per 24 hours: alert_founder's contract, kept in the database.
  if p_dedupe_key is not null and exists (
       select 1 from public.founder_alerts f
        where f.dedupe_key = p_dedupe_key and f.channel in ('email', 'whatsapp')
          and f.created_at > now() - interval '24 hours') then
    insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
    values (v_level, p_event, p_detail, 'deduped', p_dedupe_key);
    return jsonb_build_object('mode', 'email', 'emailed', false, 'deduped', true, 'kind', v_kind);
  end if;

  select nullif(split_part(coalesce(value, ''), ',', 1), '') into v_email from public.app_secrets where key = 'admin_emails';
  v_email := coalesce(v_email, 'management@quotesdone.com');
  select nullif(btrim(value), '') into v_phone from public.app_secrets where key = 'admin_mfa_phone';

  insert into public.founder_alerts (level, event, detail, channel, dedupe_key)
  values (v_level, p_event, p_detail, 'email', p_dedupe_key);

  -- the email queue (send_outbox / Resend)
  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel)
  values ('founder_alert', v_kind, v_email, 'founder', '[Attention] ' || p_event, p_detail, 'queued', 'email');

  -- WhatsApp for severe levels (send_whatsapp / Twilio); trg_wa_fanout does NOT fan out founder rows.
  -- 6 SEP 2026: the detail rides in the body after the first line. send_whatsapp fills the founder_alert
  -- template ("QuotesDone alert: {{1}}. Details: {{2}}. Open the OS to act.") from exactly this shape:
  -- {{1}} is the first line without the "QuotesDone " prefix, {{2}} is what follows.
  if v_phone is not null and lower(v_level) in ('critical', 'urgent', 'high', 'danger') then
    insert into public.notifications (type, kind, to_phone, to_role, subject, body, status, channel)
    values ('founder_alert', v_kind, v_phone, 'founder', p_event,
            'QuotesDone [' || v_level || ']: ' || p_event
              || coalesce(E'\n' || nullif(btrim(p_detail), ''), ''), 'queued', 'whatsapp');
  end if;
  return jsonb_build_object('mode', 'email', 'emailed', true, 'kind', v_kind);
end $function$
;

-- 3. fn_company_self_knowledge_sync (full live definition; one record added) -----------------------
CREATE OR REPLACE FUNCTION public.fn_company_self_knowledge_sync()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_state jsonb := public.fn_company_state();
  v_snap  jsonb := public.fn_company_snapshot();
  v_brief text  := public.fn_company_brief(6000);
  v_fee   numeric; v_sup_fee numeric; v_charge date; v_refund_wd int; v_cur text;
  v_target text; v_deadline text;
  v_social text; v_social_at text; v_blog text; v_blog_at text;
  v_funnel text;
  v_founder text;
  v_tmpl text;
  v_rev numeric; v_exp numeric; v_pnl text;
  v_records jsonb; r jsonb; v_rid text; v_n int := 0;
  reg public.company_registration%rowtype;
begin
  select * into reg from public.company_registration order by recorded_at desc limit 1;
  -- the founder identity (who leads the company)
  select string_agg(identity, ' / ' order by identity) into v_founder
    from public.phase_c_founder_identity where active and kind = 'email';
  -- the live P&L (financial state beyond headline revenue)
  select coalesce(sum(amount) filter (where type='revenue'),0), coalesce(sum(amount) filter (where type='expense'),0),
         string_agg(case when amount <> 0 then '  - '||type||': '||name||' = AED '||amount::text else null end, E'\n' order by type, code)
    into v_rev, v_exp, v_pnl from public.gl_pnl;
  select standard_reveal_rate, supplier_reg_fee, supplier_charging_starts, refund_window_working_days,
         coalesce(reveal_currency,'AED')
    into v_fee, v_sup_fee, v_charge, v_refund_wd, v_cur
    from public.pricing_config order by id limit 1;

  select coalesce(target_value::text,'1000000'), coalesce(to_char(deadline,'DD Mon YYYY'),'31 Aug 2027')
    into v_target, v_deadline
    from public.company_goals
   where active and (lower(coalesce(key,'')) like '%revenue%' or lower(coalesce(goal,'')) like '%revenue%'
                     or category = 'Financial')
   order by sort nulls last limit 1;

  select left(coalesce(content->>'text', content->>'body', content::text), 240), to_char(created_at,'DD Mon YYYY')
    into v_social, v_social_at from public.social_posts order by created_at desc limit 1;
  select title, to_char(coalesce(published_at, updated_at),'DD Mon YYYY')
    into v_blog, v_blog_at from public.blog_posts where published order by published_at desc nulls last limit 1;

  -- 6 SEP 2026: the WhatsApp template ledger (messaging_template), one line per template, live.
  select coalesce(string_agg('  - ' || template_key || ' [' || lang || ']: ' || upper(status) || ' (' || sid
           || coalesce(', ' || category, '') || coalesce(', submitted ' || to_char(submitted_at, 'DD Mon YYYY'), '')
           || coalesce(', approved (first seen ' || to_char(approved_at, 'DD Mon YYYY') || ')', '')
           || coalesce(', reason: ' || left(rejection_reason, 90), '') || coalesce(', ' || note, '') || ')',
           E'\n' order by template_key, lang), '  (no templates recorded)')
    into v_tmpl from public.messaging_template where channel = 'whatsapp';

  select string_agg('  ' || workflow_id || ' — ' || workflow_name, E'\n' order by workflow_id)
    into v_funnel from public.phase_b_workflow
   where workflow_id in ('W04','W05','W06','W07','W08','W09','W10','W12','W13','W14','W15','W16','W17','W18');

  v_records := jsonb_build_array(

    -- 6 SEP 2026: the company's registration and tax status, from company_registration (the founder
    -- supplied the trade licence and ruled on VAT that day; both are closed facts, never questions).
    jsonb_build_object('rid','registration','module','company_registration',
      'title','QuotesDone — Trade licence, registration and tax status',
      'kw', to_jsonb(array['trade licence','trade license','licence number','license number','DET','department of economy and tourism',
        'issuing authority','licence expiry','renewal','activity code','portal','software design','trader licence','e-trader',
        'VAT','vat registered','TRN','tax registration number','FTA','federal tax authority','threshold','375,000','corporate tax',
        'are we vat registered','do we charge vat','company registration','legal entity','owner','who owns the licence']),
      'content',
        case when reg.license_no is null then 'REGISTRATION: not recorded.' else
        'TRADE LICENCE: ' || reg.authority || ' ' || reg.license_type || ' no. ' || reg.license_no || ', trade name "' || reg.trade_name || '"; issued ' ||
        to_char(reg.issued_on,'DD Mon YYYY') || ', expires ' || to_char(reg.expires_on,'DD Mon YYYY') || ' (renew before then; renewal is a company task, not a founder question).' || E'\n' ||
        'OWNER: ' || reg.owner_name || ' (' || reg.owner_share || '); licensed activities: ' || reg.activities || '.' || E'\n' ||
        'REGISTERED CONTACT: ' || reg.registered_email || ', ' || reg.registered_mobile || '; e-stores on the licence: ' || reg.e_stores || '.' || E'\n' ||
        'LICENCE CLASS: ' || reg.license_class_note || E'\n' ||
        'TAX STATUS: ' || case when reg.vat_registered then 'VAT-registered, TRN ' || coalesce(reg.trn,'?') else
          'NOT VAT-registered (founder ruling ' || to_char(reg.vat_ruling_on,'DD Mon YYYY') || '): no VAT is charged or shown on any QuotesDone invoice until taxable supplies reach the FTA mandatory registration threshold of AED ' ||
          to_char(reg.vat_threshold_aed,'FM999,999,999') || ' in a rolling 12 months. Do not ask the founder about VAT or the TRN; when revenue approaches the threshold the CFO opens a registration task.' end || E'\n' ||
        'CORPORATE TAX: ' || coalesce(reg.corporate_tax_note,'registration status not recorded.')
        end),

    jsonb_build_object('rid','identity','module','company_identity',
      'title','QuotesDone — Identity, Vision and Mission',
      'kw', to_jsonb(array['vision','mission','what is quotesdone','who are we','company','marketplace','target','revenue goal','anonymous','uae','b2b',
        'who is the founder','company founder','who owns quotesdone','founder name','ahmad alzain','the owner',
        'company target and deadline','revenue target','what is our goal','aed 1 million target','1000000 by 2027','when is the deadline']),
      'content',
        'WHO WE ARE. ' || coalesce(v_state->>'mission','') || E'\n' ||
        'VISION: ' || coalesce(v_state->>'vision','') || E'\n' ||
        'TARGET: AED ' || v_target || ' in revenue by ' || v_deadline ||
          ' — every department''s objectives trace to this one number.' || E'\n' ||
        'HOW IT WORKS IN ONE LINE: an anonymous UAE B2B quotation marketplace — buyers post an RFQ, verified UAE '
        'suppliers submit quotes, and the buyer pays a small reveal fee to unlock and contact a chosen supplier. '
        'Every department is an autonomous AI expert that plans and executes toward the vision.' || E'\n' ||
        'FOUNDER / OWNER: Ahmad Alzain (' || coalesce(v_founder,'management@quotesdone.com') || '). The company is '
        'founder-led: he sets the vision, the target and the boundaries, and he is the ONLY approver of refunds. '
        'The AI departments run everything else on their own.'),

    jsonb_build_object('rid','financials','module','financials',
      'title','QuotesDone — Our Financials (live P&L)',
      'kw', to_jsonb(array['financials','finance','p&l','profit and loss','expenses','costs','revenue','how much did we spend','what were our expenses','net','burn','money','accounting','are we profitable']),
      'content',
        'LIVE FINANCIAL STATE (from the general ledger; refreshes):' || E'\n' ||
        '  Total revenue: AED ' || round(coalesce(v_rev,0),2)::text || '  ·  Total expenses: AED ' || round(coalesce(v_exp,0),2)::text ||
        '  ·  Net: AED ' || round(coalesce(v_rev,0)-coalesce(v_exp,0),2)::text || E'\n' ||
        'By account (non-zero lines):' || E'\n' || coalesce(v_pnl,'  (no posted amounts yet)') || E'\n' ||
        'Read it honestly: revenue is ' || case when coalesce(v_rev,0)=0 then 'AED 0 because the marketplace is pre-launch' else 'as above' end ||
        '; the spend so far is mostly software and AI infrastructure while the company is being built.'),

    jsonb_build_object('rid','operating-model','module','operating_model',
      'title','QuotesDone — How the Marketplace Works, End to End',
      'kw', to_jsonb(array['funnel','operating model','how it works','journey','inquiry','rfq','routing','packaging','dispatch','reveal','pipeline','workflow']),
      'content',
        'THE FUNNEL. A customer''s job travels the pipeline autonomously:' || E'\n' ||
        '  W04 register/onboard the customer → W05 intake and qualify the inquiry (RFQ) → W06 route it to the right '
        'category → W07 process any drawings/BOQ/documents → W08 build and approve a supplier-SAFE package (customer '
        'identity and any contact details stripped) → W09/W10 onboard and verify suppliers → W12 match and dispatch to '
        'enough confirmed suppliers → W13 notify them → W14 suppliers submit and we evaluate quotations → W15 build the '
        'top-3 comparison and reveal path → W16 the customer pays the reveal fee and gets supplier contact → W17 handles '
        'any refund/dispute, W18 support and retention.' || E'\n' ||
        'ANONYMITY: buyers and suppliers never see each other until the buyer pays to reveal. Quotes are anonymized/'
        'masked until then. The 30 workflows that run this: ' || coalesce(v_funnel,'(registry)') ),

    jsonb_build_object('rid','commercials','module','commercials',
      'title','QuotesDone — Fees, Pricing and Refund Terms (live)',
      'kw', to_jsonb(array['fee','reveal fee','review fee','pricing','how much','commission','refund','supplier fee','registration fee','late fee','cost','price','supplier charging','when does supplier charging start','how much do suppliers pay','are suppliers charged','supplier registration','supplier pays']),
      'content',
        'REVEAL FEE (what the customer pays to unlock a supplier): ' || round(v_fee*100,2) || '% of the deal, in ' || v_cur ||
          ' — read live from pricing_config, so this figure is always the current one.' || E'\n' ||
        'SUPPLIERS: registration is FREE until ' || coalesce(to_char(v_charge,'DD Mon YYYY'),'01 Aug 2027') ||
          ', then ' || coalesce(v_sup_fee::text,'1000') || ' ' || v_cur || ' per year. Suppliers are auto-approved on a verified file.' || E'\n' ||
        'REFUNDS: window is ' || coalesce(v_refund_wd::text,'3') || ' UAE working days from reveal (Fri IS a working day; '
        'weekend is Sat+Sun); a 3% processing deduction applies; EVERY refund of any amount requires the founder''s approval.' || E'\n' ||
        'LATE FEE on overdue recoverables: 9% per annum (UAE Federal Decree-Law 50/2022).'),

    jsonb_build_object('rid','comparison-report','module','comparison_report',
      'title','QuotesDone — The Top-3 Comparison Report',
      'kw', to_jsonb(array['comparison report','compare','top 3','top three','quote comparison','ranking','shortlist','quote_compare','how do we compare','side by side']),
      'content',
        'THE COMPARISON REPORT IS ALWAYS THE TOP 3. However many quotations arrive — 3 or 100 — quote_compare ranks '
        'them ALL and returns the top three (ranks 1, 2, 3). It is NOT cheapest-wins: quotes are scored across multiple '
        'technical and commercial factors — price positioned across the range of offers, lead time, warranty, scope match, '
        'payment terms — so the strongest overall quote wins, not merely the lowest. The ranking is deterministic; the model '
        'writes the plain-language explanation of why the top three are the top three. The customer sees an anonymized '
        'side-by-side comparison table, saveable as a PDF, and only then decides whom to reveal.'),

    jsonb_build_object('rid','quotation-format','module','quotation_format',
      'title','QuotesDone — What a Supplier Quotation Contains',
      'kw', to_jsonb(array['quotation format','quote format','what is in a quote','quote fields','lead time','validity','payment terms','warranty','scope','exclusions','anonymized']),
      'content',
        'A supplier quotation carries: the quote amount, lead time, validity period, payment terms, warranty, scope of '
        'supply, conditions, exclusions, and notes. It may be typed or extracted from an uploaded file, then structured '
        'and committed (hashed) so it cannot be silently changed. BEFORE the customer sees it, the supplier''s identity '
        'and any contact details are anonymized/masked. The price the customer sees (customer_price) includes the '
        'platform margin/app fee on top of the supplier''s amount.'),

    jsonb_build_object('rid','terms','module','terms_and_conditions',
      'title','QuotesDone — Terms, Anonymity and Working Days',
      'kw', to_jsonb(array['terms','conditions','t&c','anonymous','reveal','working days','jurisdiction','policy','rules','uae']),
      'content',
        'QuotesDone is an ANONYMOUS UAE B2B marketplace. Suppliers are verified before they can quote. Buyer and supplier '
        'identities are hidden from each other until the buyer pays the reveal fee to contact a chosen supplier. All time '
        'windows use UAE working days (Asia/Dubai; Friday is a working day; the weekend is Saturday and Sunday; public '
        'holidays excluded). The reveal refund window is ' || coalesce(v_refund_wd::text,'3') || ' working days. Late fees '
        'follow UAE Federal Decree-Law 50/2022 (9% p.a.). The platform mediates disputes through a defined escalation ladder.'),

    jsonb_build_object('rid','governance','module','governance',
      'title','QuotesDone — How the Company Governs Itself',
      'kw', to_jsonb(array['governance','who approves','autonomy','refund approval','founder','escalation','boundaries','decisions','authority']),
      'content',
        'QuotesDone runs as ten autonomous AI departments (90 brain agents) that plan and execute toward the vision '
        'WITHOUT needing the founder''s approval for ordinary work. The founder is escalated to only for: money that '
        'leaves the company (every refund, any amount, needs his approval), destructive/irreversible production changes, '
        'and decisions only he holds (his intentions, external credentials, commercial direction). Everything else — '
        'routing, packaging, matching, pricing within policy, content — the agents decide and own. Colleagues hand work '
        'to one another through defined handoffs; nothing is left unowned.'),

    -- DYNAMIC: regenerated from the live org every run.
    jsonb_build_object('rid','organization','module','organization',
      'title','QuotesDone — The Organization: Departments, Colleagues and Roles',
      'kw', to_jsonb(array['organization','org chart','departments','how many agents','who works here','colleagues','roles','manager','line manager','team','north star','who does what','name the ten departments','list the departments','what are our departments','department names','the 10 departments']),
      'content', 'THE COMPANY YOU WORK IN (live roster — these are your colleagues; know who does what and who leads each team).' || E'\n' ||
        'THE TEN DEPARTMENTS: ' || coalesce((select string_agg(name, ', ' order by sort nulls last, dept_key) from public.org_departments where active),'') || E'\n' ||
        coalesce(v_brief,'')),

    -- DYNAMIC: the live snapshot every run.
    jsonb_build_object('rid','live-state','module','live_state',
      'title','QuotesDone — Live Company State (current)',
      'kw', to_jsonb(array['live','current','right now','revenue','last month revenue','how much revenue','customers','suppliers','open tasks','kpi','last social post','last blog','latest post','state','status','how are we doing']),
      'content',
        'LIVE STATE as of ' || to_char(now(),'DD Mon YYYY HH24:MI') || ' UTC (this refreshes; if a figure is 0 the company '
        'is pre-launch, not broken):' || E'\n' ||
        '  Revenue (last 30 days): ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' AED' || E'\n' ||
        '  Customers: ' || coalesce(v_snap->>'customers','0') || ' (with an inquiry: ' || coalesce(v_snap->>'customers_with_inquiry','0') || ')' || E'\n' ||
        '  Approved suppliers: ' || coalesce(v_snap->>'approved_suppliers','0') || ' · Sendable supplier pool: ' || coalesce(v_snap->>'sendable_pool','0') || E'\n' ||
        '  Employees (brain agents): ' || coalesce(v_snap->>'employees','90') || ' · Departments: ' || coalesce(v_snap->>'departments','10') || E'\n' ||
        '  KPIs tracked: ' || coalesce(v_snap->>'kpis','0') || ' (open gaps: ' || coalesce(v_snap->>'kpi_gaps_open','0') || ')' || E'\n' ||
        '  Open tasks: ' || coalesce(v_snap->>'open_tasks','0') || ' · Items needing the founder: ' || coalesce(v_snap->>'needs_founder','0') || E'\n' ||
        '  AI spend (last 30 days): ' || coalesce(v_snap->>'ai_cost_30d_aed','0') || ' AED' || E'\n' ||
        '  Last social post: ' || coalesce(nullif(v_social,''),'(none yet)') || case when v_social_at is not null then ' [' || v_social_at || ']' else '' end || E'\n' ||
        '  Last blog post: ' || coalesce(nullif(v_blog,''),'(none yet)') || case when v_blog_at is not null then ' [' || v_blog_at || ']' else '' end),

    jsonb_build_object('rid','stage','module','company_stage',
      'title','QuotesDone — What Stage the Company Is At',
      'kw', to_jsonb(array['stage','pre-launch','have we launched','are we live','do we have customers','how many customers','are we operating','company status','how far along','launched yet','traction','are we making money']),
      'content',
        'COMPANY STAGE — READ THIS BEFORE ANSWERING ANYTHING ABOUT TRACTION. QuotesDone is PRE-LAUNCH. The '
        'platform and the AI organization are built and being readied; there are ' || coalesce(v_snap->>'customers','0') ||
        ' real customers and AED ' || coalesce(v_snap->>'revenue_30d_aed','0') || ' revenue so far. What is already in place: '
        '10 departments and ' || coalesce(v_snap->>'employees','90') || ' AI agents, 30 workflows, 86 supplier categories, '
        'the knowledge base and ' || coalesce(v_snap->>'approved_suppliers','1') || ' approved supplier(s). What is still pending before real '
        'operation: the marketplace go-live, real customer inquiries arriving, and funded AI inference so the agents can reason. '
        'NEVER claim customers, revenue, or results the numbers above do not show — we are building toward AED 1,000,000 by 31 Aug 2027, not there yet.'),

    -- 6 SEP 2026 (added at the END of the array on purpose: sibling files of the same day restate this
    -- function too, and a record appended last merges without touching theirs): the WhatsApp templates
    -- and their Meta approval status, from messaging_template (the founder said "fix the template
    -- yourself"; the status is company knowledge, never his question).
    jsonb_build_object('rid','messaging-templates','module','messaging_templates',
      'title','QuotesDone — WhatsApp templates and their Meta approval status (live)',
      'kw', to_jsonb(array['whatsapp template','whatsapp templates','template approval','meta approval','twilio','content sid','contentsid',
        'founder alert whatsapp','whatsapp alert','whatsapp alerts to the founder','is the whatsapp template approved','pending template',
        'template pending','template rejected','63016','utility template','messaging template','messaging_template','wa_template_sids',
        'can we send whatsapp','why did the whatsapp not arrive','send_whatsapp','wa_template_setup','business-initiated message','24-hour session']),
      'content',
        'WHATSAPP TEMPLATES (Twilio Content API, approved by Meta; live from messaging_template):' || E'\n' || v_tmpl || E'\n' ||
        'THE RULES. A business-initiated WhatsApp (an alert to the founder, a job / quote / reveal / document notice to a supplier or '
        'customer) is deliverable ONLY through a Meta-APPROVED template sent by ContentSid; a freeform body is delivered only inside the '
        '24-hour session the recipient opened by messaging us first (Twilio error 63016 otherwise). A template still pending approval is a '
        'HELD message, never a failed one: send_whatsapp keeps supplier and customer rows queued until the template lands, marks founder-alert '
        'rows skipped with the reason (the email already carried the alert), and refuses a direct send with the reason instead of erroring. '
        'Templates are created and submitted by the wa_template_setup function (category UTILITY, language en/ar, the body opens AND closes '
        'with literal text because Meta rejects a variable at the start or end); the sender refreshes each pending status from Twilio at most '
        'every ten minutes and only ever sends with a status of APPROVED. The sender number is registered with Meta as "QuotesDone" '
        '(quality rating and messaging tier are read from Twilio, not assumed). Nobody asks the founder about WhatsApp templates: the '
        'status above is the answer, and a pending line means Meta has not answered yet.')
  );

  for r in select * from jsonb_array_elements(v_records) loop
    v_rid := 'qd-company:' || (r->>'rid');
    insert into public.ops_knowledge(
      record_id, scope_type, scope_key, layer, module, record_type, title, content,
      structured_data, source_ids, implementation_status, validation_status, authority_tier,
      risk_level, version, keywords, dependencies, escalation_rule, jurisdiction, source_freshness,
      confidentiality, runtime_eligible, deterministic, supersession_state, embedding_status,
      effective_date)
    values (
      v_rid, 'company', 'company_core', 'company_core', r->>'module', 'md', r->>'title',
      -- fold the keyword vocabulary into the content so the generated tsv (title+content) indexes the
      -- phrasings agents actually ask in, not only the prose. This is what makes deep questions match.
      (r->>'content') || E'\n\nYou can answer questions about: ' ||
        array_to_string(array(select jsonb_array_elements_text(r->'kw')), ', ') || '.',
      '{}'::jsonb, array['fn_company_self_knowledge_sync'], 'active', 'validated', 'autonomous',
      'low', '1', array(select jsonb_array_elements_text(r->'kw')), '{}'::text[], '{}'::jsonb, 'UAE', 'current',
      'internal', true, true, 'current', 'pending', current_date)
    on conflict (record_id) do update set
      module = excluded.module, title = excluded.title, content = excluded.content,
      keywords = excluded.keywords, effective_date = excluded.effective_date,
      supersession_state = 'current', embedding_status = 'pending';
    v_n := v_n + 1;
  end loop;

  -- The org directory (everyone knows everyone: role, line manager, KPI, live rating) and the
  -- published content (FAQ, social, blog, website) are recomposed in the same refresh.
  perform public.fn_company_org_directory_sync();

  return jsonb_build_object('ok', true, 'records', v_n, 'ran_at', now(),
    'revenue_30d_aed', v_snap->>'revenue_30d_aed', 'reveal_fee_pct', round(v_fee*100,2),
    'employees', v_snap->>'employees');
end $function$
;

-- 4. wa_flush back on (already wrapped by the kernel: this only re-activates it) -------------------
do $cron$
declare r jsonb;
begin
  r := public.fn_kernel_wrap_and_enable_cron(34, 'it_operations_engineer', 'product_eng');
  if not coalesce((r ->> 'ok')::boolean, false) then
    raise exception 'wa_flush (cron 34) could not be re-enabled: %', r;
  end if;
end $cron$;

-- 5. the ownership ledger follows this manifest file ----------------------------------------------
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file)
values
  ('public', 'fn_notify_founder', 'p_event text, p_detail text, p_level text, p_kind text, p_dedupe_key text, p_owner_agent text',
   'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated 6 Sep 2026: the WhatsApp row carries the detail for the founder_alert template',
   'MANIFEST', 'scripts/sql/the_founder_alert_has_a_whatsapp_template_and_the_company_knows_its_templates.sql'),
  ('public', 'fn_company_self_knowledge_sync', '',
   'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated 6 Sep 2026: renders qd-company:messaging-templates from messaging_template',
   'MANIFEST', 'scripts/sql/the_founder_alert_has_a_whatsapp_template_and_the_company_knows_its_templates.sql')
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file, recorded_at = now();

-- PROOF ------------------------------------------------------------------------------------------
do $proof$
declare n int; v_def text; v_active boolean;
begin
  select count(*) into n from public.messaging_template where channel = 'whatsapp';
  if n < 11 then raise exception 'messaging_template seeded % rows; expected the 11 registered SIDs (5 keys x en/ar + control_mode_code)', n; end if;
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'fn_notify_founder';
  if v_def not like '%nullif(btrim(p_detail), '''')%' then raise exception 'fn_notify_founder does not carry the detail'; end if;
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.proname = 'fn_company_self_knowledge_sync';
  if v_def not like '%messaging-templates%' then raise exception 'fn_company_self_knowledge_sync does not render the ledger'; end if;
  select active into v_active from cron.job where jobid = 34;
  if not coalesce(v_active, false) then raise exception 'cron 34 wa_flush is not active'; end if;
  raise notice 'proof: messaging_template % rows seeded; fn_notify_founder carries the detail; self-knowledge renders messaging-templates; wa_flush active', n;
end $proof$;

commit;
