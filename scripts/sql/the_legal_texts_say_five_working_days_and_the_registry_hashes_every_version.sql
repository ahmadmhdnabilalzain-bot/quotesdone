-- THE LEGAL TEXTS SAY FIVE WORKING DAYS, AND THE REGISTRY HASHES EVERY VERSION (6 Sep 2026).
--
-- Founder ruling of 6 Sep 2026 (verbatim in decision_policy.refund_policy_founder_decision_2026_09_06):
-- the refund ladder is 5 working days from the customer's payment, a chase at day 3, his final call on
-- day 5, the refund on no response, banks 7-14 working days, the AED 250 administrative fee stays, and
-- the 3% refunded plus 9% p.a. interest is recovered from the supplier. "This should be updated
-- everywhere." The ladder itself is scripts/sql/the_refund_ladder_is_five_working_days_with_a_chase_at_three_and_the_founders_final_call_at_five.sql;
-- this file is the TEXT and the REGISTRY.
--
-- WHAT PRODUCTION SAID BEFORE THIS FILE (measured 6 Sep 2026 14:00 UTC):
--   pages.legal_terms_body (the Customer Terms every customer accepts; identical to
--   legal_documents.customer-terms v3) clause 5: complaint within 7 days, refund only if the supplier
--   is silent for "three (3) working days of QuotesDone taking up your complaint". pages.legal_supplier_body
--   (= app_secrets.supplier_terms_html = legal_documents.supplier-agreement v5): "begin responding within
--   3 working days"; clause 33: a non-response charge equal to the reveal fee, nothing about the AED 250
--   administrative fee or the 9% interest (decision_policy.refund_admin_fee_aed carried a WARNING that
--   the fee was therefore not contractually recoverable). legal_documents.refund-policy v1.2: "three (3)
--   working days of the reveal", proof required, request within 10 working days, "Working days exclude
--   Fridays, Saturdays" (wrong: the week is Mon-Fri), processing "within fourteen (14) days".
--   legal_documents had no content hash; nothing bumped a version when a page changed; fn_legal_ai's
--   checklist looked for slug 'terms-of-service' while the Terms are registered as 'customer-terms', and
--   its "Governing Law & Dispute Resolution clause" row had no way to be satisfied (match_slug null),
--   so every morning it raised "Core legal documents missing: Customer Terms & Conditions / User
--   Agreement; Governing Law & Dispute Resolution clause" against documents that exist.
--
-- WHAT THIS FILE DOES:
--   1. legal_documents.content_sha256 + source; trg_legal_documents_hash computes the hash on every
--      write and bumps version + effective_date when the body changes (BR-025: acceptance can cite
--      version + hash). trg_pages_legal_sync copies a changed legal page into its registry row and
--      keeps app_secrets.supplier_terms_html in step, so the three copies cannot drift again.
--   2. The texts: Customer Terms clause 5, Supplier Agreement "response time" paragraph and clause 33,
--      Refund Policy sections 3-6, Complaints Policy working-week line. The four hard rules are kept
--      (3% reveal, non-response 3%, AED 15,000 / 3x anti-circumvention, anonymity).
--   3. app_secrets terms pins re-pinned to the new text (fn_terms_integrity stays ok): customer v3 -> v4,
--      supplier v5 -> v6. Privacy re-registered with its hash at 1.2.
--   4. legal_checklist: match_slug 'terms-of-service' -> 'customer-terms' (the instrument pointed at a
--      slug that never existed); the Governing Law row gets match_clause, and fn_legal_ai marks it
--      present only when BOTH agreements carry a governing-law-and-jurisdiction clause. Stronger, not
--      weaker: it now reads the documents' bodies.
--   5. Proof in the same transaction: texts read back, hashes present, fn_terms_integrity ok, and
--      fn_legal_ai() reports critical_missing = 0 on real data.
--
--   node scripts/apply_sql.mjs scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql --apply --ddl
begin;

-- ---------------------------------------------------------------- 1. the registry hashes and versions itself
alter table public.legal_documents
  add column if not exists content_sha256 text,
  add column if not exists source text;

CREATE OR REPLACE FUNCTION public.fn_legal_version_bump(p_version text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 'v3' -> 'v4', '1.2' -> '1.3', '5' -> '6', null/'' -> '1.1': the trailing integer is the counter
  select case
    when coalesce(p_version, '') !~ '[0-9]+\s*$' then '1.1'
    else regexp_replace(p_version, '([0-9]+)\s*$', ((substring(p_version from '([0-9]+)\s*$'))::int + 1)::text) end;
$function$;

CREATE OR REPLACE FUNCTION public.trg_legal_documents_hash()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  NEW.content_sha256 := encode(sha256(convert_to(coalesce(NEW.body_html, ''), 'UTF8')), 'hex');
  if TG_OP = 'UPDATE' and NEW.body_html is distinct from OLD.body_html then
    -- a changed body is a new version unless the statement set one itself
    if NEW.version is not distinct from OLD.version then
      NEW.version := public.fn_legal_version_bump(OLD.version);
    end if;
    NEW.effective_date := current_date;
    NEW.updated_at := now();
  elsif TG_OP = 'UPDATE' and NEW.version is distinct from OLD.version then
    NEW.updated_at := now();
  end if;
  return NEW;
end $function$;

drop trigger if exists a10_legal_documents_hash on public.legal_documents;
create trigger a10_legal_documents_hash
  before insert or update on public.legal_documents
  for each row execute function public.trg_legal_documents_hash();

-- the page a customer or supplier actually accepts IS the registry row; app_secrets.supplier_terms_html
-- is the copy fn_terms_integrity compares against the page
CREATE OR REPLACE FUNCTION public.trg_pages_legal_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if NEW.slug = 'legal_terms_body' then
    update public.legal_documents set body_html = NEW.html, source = 'pages:legal_terms_body'
     where slug = 'customer-terms' and body_html is distinct from NEW.html;
  elsif NEW.slug = 'legal_supplier_body' then
    update public.legal_documents set body_html = NEW.html, source = 'pages:legal_supplier_body'
     where slug = 'supplier-agreement' and body_html is distinct from NEW.html;
    update public.app_secrets set value = NEW.html, updated_at = now()
     where key = 'supplier_terms_html' and value is distinct from NEW.html;
  end if;
  return null;
end $function$;

drop trigger if exists trg_pages_legal_sync_a on public.pages;
create trigger trg_pages_legal_sync_a
  after insert or update of html on public.pages
  for each row execute function public.trg_pages_legal_sync();

-- backfill: every registered document gets its hash; a body that did not change keeps its version
update public.legal_documents set content_sha256 = null where content_sha256 is null;
update public.legal_documents set source = 'pages:legal_terms_body' where slug = 'customer-terms' and source is null;
update public.legal_documents set source = 'pages:legal_supplier_body' where slug = 'supplier-agreement' and source is null;
update public.legal_documents set source = 'legal_documents' where source is null;

-- ---------------------------------------------------------------- 2. the texts
-- Customer Terms, clause 5 (pages.legal_terms_body; the sync trigger carries it into customer-terms)
update public.pages
   set html = regexp_replace(regexp_replace(html,
     '<p>If, after a Reveal, the Supplier does not respond to you, your remedy[^<]*</p>',
     '<p>If, after a Reveal, the Supplier does not respond to you, you do not need to do anything for the clock to start: QuotesDone tracks every Reveal from the moment you pay. If the Supplier has not responded within three (3) working days of your payment, QuotesDone chases the Supplier on your behalf, copying you. If there is still no response by the fifth (5th) working day, the case goes to QuotesDone&#39;s founder for a final call. You may also raise a complaint through the Platform at any time; contacting the Supplier in writing (for example by email) and copying supplier@quotesdone.com puts your own attempt to reach the Supplier on record.</p>'),
     '<p>A refund or, at QuotesDone&#(39|x27);s option, a free re-introduction[^<]*</p>',
     '<p>If the Supplier has failed to respond both to you and to QuotesDone within five (5) working days of your payment and does not respond to the founder&#39;s final call, the Reveal Fee is refunded. The refund is the full Reveal Fee you paid (3% of the quotation value); QuotesDone deducts nothing from it. Every refund is decided by QuotesDone&#39;s founder; no refund is automatic and there is no self-service refund. Once a refund is issued, banks and card issuers usually take seven (7) to fourteen (14) working days to show it on your statement. Working days are Monday to Friday, excluding UAE public holidays.</p>')
 where slug = 'legal_terms_body';

-- Supplier Agreement: the response-time paragraph (fn_company_hard_rules reads "begin responding to the
-- Customer within N working days" from it) and clause 33 (pages.legal_supplier_body; the sync trigger
-- carries it into supplier-agreement and app_secrets.supplier_terms_html)
update public.pages
   set html = regexp_replace(regexp_replace(html,
     '<p><b>Winning a job &amp; response time\.</b>([^<]|<b>|</b>)*</p>',
     '<p><b>Winning a job &amp; response time.</b> When a Customer reveals and selects the Supplier, the Supplier is notified that it has won the job and the Customer is given the Supplier&#39;s contact details (by SMS, WhatsApp and/or email) so the Customer can make contact. The Supplier must begin responding to the Customer within <b>5 working days</b> of the Reveal. If the Supplier has not responded within 3 working days of the Reveal, QuotesDone chases the Supplier, copying the Customer; if there is still no response by the 5th working day the case goes to QuotesDone&#39;s founder for a final call, and if the Supplier does not respond to that call the Customer&#39;s reveal fee is refunded and the non-response charge in clause 33 applies. Repeated non-responsiveness may lead to suspension. QuotesDone is notified of every such case.</p>'),
     '<p>Once a Customer reveals the Supplier&#(39|x27);s contact details, the Supplier must respond[^<]*</p>',
     '<p>Once a Customer reveals the Supplier&#39;s contact details, the Supplier must respond to that Customer within five (5) working days of the Reveal, by the on-platform message thread, telephone, email or other reasonable means. QuotesDone tracks every Reveal from payment: if the Supplier has not responded within three (3) working days, QuotesDone chases the Supplier, copying the Customer; if there is still no response by the fifth (5th) working day, QuotesDone&#39;s founder makes a final call to the Supplier. If the Supplier does not respond to that call and QuotesDone consequently refunds the Customer&#39;s Reveal Fee, the Supplier shall pay QuotesDone: (a) a non-response charge equal to that Reveal Fee (3% of the quoted value); (b) an administrative fee of AED 250; and (c) simple interest on the total at nine percent (9%) per annum, the maximum rate permitted under UAE law, calculated from the date of the Customer&#39;s payment until settled. These amounts reflect QuotesDone&#39;s cost of the refund caused by the Supplier&#39;s non-response; they are payable within seven (7) days of QuotesDone&#39;s notice, may be recorded as a due on the Supplier&#39;s account, and may be set off against any amounts otherwise payable to the Supplier. The Supplier is not matched to new Customers until the amount is settled. Repeated non-response may also lead to suspension or removal from the Platform.</p>')
 where slug = 'legal_supplier_body';

-- Refund & Cancellation Policy, sections 3-6 (registry only; the site copy is src/content/legal.json)
update public.legal_documents
   set body_html = regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(body_html,
     '<p>We refund the Reveal Fee in one defined circumstance:[^<]*</p>',
     '<p>We refund the Reveal Fee in one defined circumstance: where a revealed supplier does not respond to you within five (5) working days of your payment and does not respond to our founder&#39;s final call. You do not need to prove anything for the clock to start: we track every reveal from the moment you pay. If the supplier has not responded within three (3) working days, we chase the supplier on your behalf and copy you; if there is still no response on the fifth (5th) working day, the case goes to our founder for a final call; if the supplier does not respond to that call, the refund is issued.</p>'),
     '<p>Acceptable proof includes dated copies[^<]*</p>',
     '<p>If you have tried to reach the supplier yourself, dated copies of emails, messages sent through the Platform, or call logs help us close the case faster, but they are not a condition of the refund. Working days are Monday to Friday, excluding UAE public holidays.</p>'),
     '<p>The Reveal Fee is not refundable once the revealed supplier has responded[^<]*</p>',
     '<p>The Reveal Fee is not refundable once the revealed supplier has responded to you within the five-working-day window, as the reveal service has then been fully delivered and the supplier has engaged.</p>'),
     '<p>The Reveal Fee is not refundable where the three-working-day window has passed[^<]*</p>',
     '<p>The Reveal Fee is not refundable where the supplier responded to you or to QuotesDone within the five-working-day window. Nothing in this section limits your non-waivable rights under UAE consumer protection law where they apply.</p>'),
     '<p>Submit your refund request within ten \(10\) working days[^<]*</p>',
     '<p>You do not need to submit a request for a non-response refund: the ladder above runs automatically from the moment you pay. You can still tell us at any time that the supplier is not responding, by emailing management@quotesdone.com or by using the support function on the Platform, and we will chase the supplier immediately.</p>'),
     '<p>Once we approve a refund, we aim to process it within[^<]*</p>',
     '<p>Once our founder approves a refund, it is issued to the original payment method through our payment processor. Banks and card issuers usually take seven (7) to fourteen (14) working days to show the refund on your statement.</p>'),
     '<p>Refunds are made in the currency of the original payment\.[^<]*</p>',
     '<p>Refunds are made in the currency of the original payment and for the full Reveal Fee you paid. QuotesDone does not deduct an administrative charge from your refund. The administrative fee of AED 250 and the interest at 9% per annum that QuotesDone charges under the Supplier Agreement are charged to the supplier whose non-response caused the refund, never to you.</p>')
 where slug = 'refund-policy';

-- Complaints & Dispute Resolution Policy: the working week is Monday to Friday
update public.legal_documents
   set body_html = replace(body_html, 'Working days exclude Fridays, Saturdays and UAE public holidays.', 'Working days are Monday to Friday, excluding UAE public holidays.')
 where slug = 'complaints-policy';

-- Privacy Policy: unchanged text, re-registered with its hash under a bumped version (BR-025)
update public.legal_documents
   set version = public.fn_legal_version_bump(version), effective_date = current_date
 where slug = 'privacy';

-- ---------------------------------------------------------------- 3. the terms pins follow the text
update public.app_secrets set value = (select encode(sha256(convert_to(html, 'UTF8')), 'hex') from public.pages where slug = 'legal_terms_body'), updated_at = now()
 where key = 'terms_sha256_customer';
update public.app_secrets set value = (select version from public.legal_documents where slug = 'customer-terms'), updated_at = now()
 where key in ('customer_terms_version', 'terms_sha256_customer_version');
update public.app_secrets set value = (select encode(sha256(convert_to(html, 'UTF8')), 'hex') from public.pages where slug = 'legal_supplier_body'), updated_at = now()
 where key = 'terms_sha256_supplier';
update public.app_secrets set value = (select version from public.legal_documents where slug = 'supplier-agreement'), updated_at = now()
 where key in ('terms_version', 'supplier_terms_version', 'terms_sha256_supplier_version');

-- ---------------------------------------------------------------- 4. the legal check measures the documents that exist
alter table public.legal_checklist add column if not exists match_clause text;
update public.legal_checklist
   set match_slug = 'customer-terms',
       notes = 'Core marketplace contract with customers (governing law, liability, dispute resolution). Registered as legal_documents.customer-terms (pages.legal_terms_body); the row pointed at slug terms-of-service, which never existed, until 6 Sep 2026.'
 where id = 1;
update public.legal_checklist
   set match_clause = 'governing law\s*(and|&amp;|&)\s*jurisdiction',
       notes = 'Embedded in the customer T&C and the supplier agreement: present only when BOTH agreement documents carry a governing-law-and-jurisdiction clause (match_clause, checked by fn_legal_ai against body_html since 6 Sep 2026).'
 where id = 13;

CREATE OR REPLACE FUNCTION public.fn_legal_ai()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare k record; v_health numeric; v_terms numeric; v_fresh numeric; n int; v_missing text; v_regchg int;
begin
  -- refresh checklist presence: a slug row is present when the registry holds that slug; a clause row
  -- (match_slug null, match_clause set) is present when EVERY registered agreement carries the clause
  -- in its body; a row with neither keeps what it has (nothing can prove it).
  update legal_checklist lc
     set present = case
       when lc.match_slug is not null then exists (select 1 from legal_documents d where d.slug = lc.match_slug)
       when lc.match_clause is not null then coalesce((select bool_and(d.body_html ~* lc.match_clause)
                                                         from legal_documents d where d.category = 'agreement'), false)
       else lc.present end;
  select * into k from legal_kpis;

  v_terms := round((coalesce(k.customer_terms_acceptance_pct,0)+coalesce(k.supplier_terms_acceptance_pct,0))/2,1);
  v_fresh := case when k.policies_published=0 then 0 else round(100.0*(k.policies_published-k.policies_stale)/k.policies_published,1) end;
  v_health := round(coalesce(k.coverage_pct,0)*0.35 + v_terms*0.30 + v_fresh*0.20 + greatest(0,100-coalesce(k.open_legal_flags,0)*10)*0.15,1);

  insert into legal_kpi_snapshots(snapshot_date,kpis) values (current_date, to_jsonb(k)||jsonb_build_object('legal_health',v_health,'terms_acceptance_avg',v_terms))
    on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  select string_agg(requirement,'; ') into v_missing from legal_checklist where not present and priority=1;
  select count(*) into v_regchg from compliance_sources where last_changed_at >= now()-interval '30 days';

  -- ESCALATIONS (founder-visible legal_flag; never legal advice)
  perform leg_flag('missing_core_docs', coalesce(k.critical_missing,0)>0, 'high', 'Core legal documents missing',
    'The platform is operating without these core documents: '||coalesce(v_missing,'')||'. They govern your contractual relationship with customers and suppliers (liability, governing law, dispute resolution). Have a licensed UAE lawyer prepare and approve them, then publish as versioned legal documents.');
  perform leg_flag('supplier_terms_acceptance', coalesce(k.suppliers_approved,0)>0 and coalesce(k.supplier_terms_acceptance_pct,0) < 90, 'high', 'Suppliers have not accepted current terms',
    'Only '||coalesce(k.supplier_terms_acceptance_pct,0)||'% of approved suppliers have accepted the current terms. Enforce terms acceptance (click-wrap / signed) at onboarding so agreements are enforceable.');
  perform leg_flag('customer_terms_acceptance', coalesce(k.customer_terms_acceptance_pct,0) < 90, 'medium', 'Customers have not accepted current terms',
    'Only '||coalesce(k.customer_terms_acceptance_pct,0)||'% of customers have accepted the current terms. Gate key actions (posting an inquiry / paying to reveal) behind explicit terms acceptance.');
  perform leg_flag('stale_policies', coalesce(k.policies_stale,0)>0, 'low', 'Policies due for annual review',
    k.policies_stale||' published policy(ies) have not been reviewed in over a year. Schedule an annual legal review.');
  perform leg_flag('reg_change_review', v_regchg>0, 'medium', 'Regulatory change may affect your terms/policies',
    v_regchg||' monitored authority source(s) changed in the last 30 days. Review whether your terms, privacy or compliance policies need updating with a lawyer.');

  select count(*) into n from agent_actions where agent='legal_ai' and status in ('pending','needs_review');
  return jsonb_build_object('ran_at',now(),'legal_health',v_health,'kpis',to_jsonb(k),'open_flags',n,
                            'critical_missing', k.critical_missing, 'missing_priority_1', v_missing);
end $function$;

-- ---------------------------------------------------------------- the ledger follows the manifest
insert into public.kernel_routine_ownership(schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file, justification, recorded_at)
values
  ('public', 'fn_legal_version_bump', 'p_version text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql', null, now()),
  ('public', 'trg_legal_documents_hash', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql', null, now()),
  ('public', 'trg_pages_legal_sync', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'defined by scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql', null, now()),
  ('public', 'fn_legal_ai', '', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT', 'restated by scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql (6 Sep 2026)', 'MANIFEST', 'scripts/sql/the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql', null, now())
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file,
  recorded_at = now();

insert into public.phase_c_component(
    component_id, component_type, source_path_or_db_object, entry_method, current_callers, external_entry,
    schedule_or_trigger, mutates_state, current_actor, canonical_system_actor, accountable_role_id,
    department_id, workflow_id, step_id, authority_class, trace_policy_id, idempotency_strategy, retry_policy,
    activation_state, classification, gap, repair_or_keep_action, evidence, measured_at)
values
  ('dbfn:trg_legal_documents_hash()', 'database_function', 'public.trg_legal_documents_hash',
   'trigger a10_legal_documents_hash BEFORE INSERT OR UPDATE on public.legal_documents', 'trigger:a10_legal_documents_hash', 'no',
   'BEFORE INSERT OR UPDATE on public.legal_documents', true, 'service_role', 'system.scheduler', 'general_counsel',
   'legal', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION',
   'pure function of the row (sha256 of body_html; version bump only when the body changes)', 'none',
   'active', 'WIRE_TO_CANONICAL', '', 'keep: BR-025 - every legal document version carries its content hash',
   'the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql 2026-09-06: new', now()::date),
  ('dbfn:trg_pages_legal_sync()', 'database_function', 'public.trg_pages_legal_sync',
   'trigger trg_pages_legal_sync_a AFTER INSERT OR UPDATE OF html on public.pages', 'trigger:trg_pages_legal_sync_a', 'no',
   'AFTER INSERT OR UPDATE OF html on public.pages', true, 'service_role', 'system.scheduler', 'general_counsel',
   'legal', 'SYSTEM_SCOPE', '', 'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION',
   'idempotent copy: writes only when the registry body differs from the page', 'none',
   'active', 'WIRE_TO_CANONICAL', '', 'keep: the accepted page and the registry row are one text',
   'the_legal_texts_say_five_working_days_and_the_registry_hashes_every_version.sql 2026-09-06: new', now()::date)
on conflict (component_id) do update set
    current_callers = excluded.current_callers, activation_state = 'active', classification = 'WIRE_TO_CANONICAL',
    accountable_role_id = excluded.accountable_role_id, department_id = excluded.department_id,
    trace_policy_id = excluded.trace_policy_id, evidence = excluded.evidence, gap = '';

-- ---------------------------------------------------------------- 5. proof, in the same transaction
do $proof$
declare v_terms text; v_sup text; v_ref text; r record; v jsonb; n int;
begin
  select html into v_terms from public.pages where slug = 'legal_terms_body';
  select html into v_sup   from public.pages where slug = 'legal_supplier_body';
  select body_html into v_ref from public.legal_documents where slug = 'refund-policy';
  if v_terms !~ 'within five \(5\) working days of your payment' or v_terms ~ 'three \(3\) working days of QuotesDone taking up'
     or v_terms !~ 'seven \(7\) to fourteen \(14\) working days' then
    raise exception 'Customer Terms clause 5 did not take';
  end if;
  if v_sup !~ 'begin responding to the Customer within <b>5 working days</b>' or v_sup ~ 'within three \(3\) working days of QuotesDone taking up'
     or v_sup !~ 'administrative fee of AED 250' or v_sup !~ 'nine percent \(9%\) per annum'
     or v_sup !~ 'liquidated compensation of AED 15,000 per incident, or three \(3\) times the fee' then
    raise exception 'Supplier Agreement clause 33 / response time did not take';
  end if;
  if v_ref !~ 'within five \(5\) working days of your payment' or v_ref ~ 'three \(3\) working days of the reveal' or v_ref ~ 'three-working-day'
     or v_ref ~ 'Submit your refund request within ten' or v_ref ~ 'exclude Fridays'
     or v_ref !~ 'seven \(7\) to fourteen \(14\) working days' or v_ref !~ 'administrative fee of AED 250' or v_ref !~ '9% per annum'
     or v_ref !~ 'Monday to Friday' then
    raise exception 'Refund Policy sections 3-6 did not take';
  end if;
  -- the registry: the two agreements carry the page text, every row has its hash, versions bumped
  for r in select d.slug, d.version, d.content_sha256, d.body_html = p.html as same
             from public.legal_documents d
             left join public.pages p on 'pages:' || p.slug = d.source
            where d.slug in ('customer-terms', 'supplier-agreement', 'refund-policy', 'privacy', 'complaints-policy') loop
    if r.content_sha256 is null or length(r.content_sha256) <> 64 then raise exception '% has no hash', r.slug; end if;
    if r.slug in ('customer-terms', 'supplier-agreement') and r.same is not true then raise exception '% differs from its page', r.slug; end if;
  end loop;
  if (select version from public.legal_documents where slug = 'customer-terms') <> 'v4' then raise exception 'customer-terms version not bumped to v4'; end if;
  if (select version from public.legal_documents where slug = 'supplier-agreement') <> 'v6' then raise exception 'supplier-agreement version not bumped to v6'; end if;
  if (select version from public.legal_documents where slug = 'refund-policy') <> '1.3' then raise exception 'refund-policy version not bumped to 1.3'; end if;
  if (select version from public.legal_documents where slug = 'privacy') <> '1.2' then raise exception 'privacy version not bumped to 1.2'; end if;
  select count(*) into n from public.legal_documents where content_sha256 is null;
  if n > 0 then raise exception '% legal_documents rows without a hash', n; end if;
  -- the accepted-terms pins agree with the published pages
  if exists (select 1 from public.fn_terms_integrity() t where not t.ok) then
    raise exception 'fn_terms_integrity is not ok after the re-pin: %', (select jsonb_agg(to_jsonb(t)) from public.fn_terms_integrity() t);
  end if;
  -- the legal check on real data
  v := public.fn_legal_ai();
  if coalesce((v->>'critical_missing')::int, 99) <> 0 then
    raise exception 'fn_legal_ai still reports critical_missing = %, missing: %', v->>'critical_missing', v->>'missing_priority_1';
  end if;
  raise notice 'proof ok: legal_ai %', v;
end $proof$;

commit;
