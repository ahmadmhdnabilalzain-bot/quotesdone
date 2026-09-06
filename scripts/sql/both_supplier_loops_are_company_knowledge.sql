-- BOTH SUPPLIER LOOPS ARE COMPANY KNOWLEDGE (6 Sep 2026).
--
-- The acquisition loop (scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql) and the weekly
-- sanctions screening (scripts/sql/the_compliance_officer_screens_registered_suppliers_weekly.sql) exist;
-- this file gives the two owning employees their standing procedure, as department-scope profession
-- records in ops_knowledge (layer department_shared, record_type standard_operating_procedure):
--   qd-loop:supplier-acquisition           supply / business_development (Business Development Manager)
--   qd-loop:supplier-sanctions-screening   legal  / compliance_and_privacy_officer (Compliance & Privacy Officer)
--
-- The company-wide record (qd-company:supplier-loops — owners, cadence, the 300/month target and this
-- month's value, the switch, the last fetch per source, open hits) is rendered every 15 minutes by
-- fn_company_self_knowledge_sync. That renderer is code-driven and seven branches restated it on 6 Sep
-- 2026, each apply dropping the others' records, so it is NOT restated here: the integrator merges every
-- record into the renderer once (scripts/sql/the_company_renderers_carry_every_record_of_6_sep.sql, which
-- carries the supplier-loops record appended at the END of v_records, as the last element). The proof
-- below reads that record from ops_knowledge and reports whether the live renderer produced it.
--
--   node scripts/apply_sql.mjs scripts/sql/both_supplier_loops_are_company_knowledge.sql --apply --ddl
begin;

-- ---------------------------------------------------------------- the two employees' profession records (department scope)
insert into public.ops_knowledge (
  record_id, scope_type, scope_key, dept_key, layer, module, record_type, role_key, title, content,
  structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level, version,
  keywords, dependencies, escalation_rule, jurisdiction, source_freshness, confidentiality, runtime_eligible,
  deterministic, supersession_state, embedding_status, effective_date)
values
  ('qd-loop:supplier-acquisition', 'department', 'supply', 'supply', 'department_shared', 'operating_procedure', 'standard_operating_procedure',
   'business_development', 'SOP — Supplier acquisition loop (Business Development Manager)',
   'PURPOSE: register at least 300 suppliers a month from the leads we hold, from inbound e-mail and from the estate''s own sources — without scraping and without paid inference (founder, 6 Sep 2026).' || E'\n'
   || 'OWNER: Business Development Manager (org_role business_development, agent bd). Nobody new: this is the role''s existing "supplier acquisition" responsibility.' || E'\n'
   || 'SWITCH: app_secrets.supplier_outreach_golive. While false, every sweep records "held" and does nothing else; the founder flips it when the app is perfect. invite_enabled remains the deliverability ramp''s own gate.' || E'\n'
   || 'DAILY, 09:00 UTC — supplier_invites_daily (enqueue_supplier_invites): the invitation batch to never-invited leads with a deliverable e-mail (email_suppressions, email_block_pattern, email_domain_mx, disposable domains), within invite_daily_cap, paused by the bounce-rate guard and the company calendar; recorded on the lead (invite_status, invited_at).' || E'\n'
   || 'DAILY, 05:30 UTC — supplier_outreach_daily (fn_supplier_outreach_daily): (a) follow-ups at +3 and +7 WORKING days after a delivered invitation, at most two, never to a lead that replied, registered, bounced or is suppressed, queued as notifications type supplier_invite_followup and recorded on the lead (invite_followups, invite_last_followup_at); (b) inbox intake (fn_supplier_lead_intake): every inbound message is classified by KEYWORDS — register / question / document / decline / bounce / other — linked to a lead by inbound lead_id, e-mail or domain, and register/question/document open ONE reply task on the BD manager carrying the templated reply to queue through the outbox; a decline suppresses the address; a bounce marks the lead; (c) lead sourcing (fn_supplier_lead_sourcing): inbound senders on business domains that match no lead become leads (source inbound_email); the staged directory is promoted daily by supplier_discovery_daily; RFQ and quote supplier mentions are harvested once inquiries exist.' || E'\n'
   || 'KPI: company_goals.suppliers_registered_monthly (at least 300, monthly, owner_dept supply) and the BD scorecard KPI "Suppliers registered per month", both measured from leads registration timestamps by fn_employee_kpi_measure.' || E'\n'
   || 'NEVER: send by hand, e-mail the founder, invite a suppressed or undeliverable address, invite or follow up a lead under a sanctions hold (task "Hold outreach and onboarding").',
   '{}'::jsonb, array['the_bd_manager_runs_the_supplier_acquisition_loop.sql'], 'active', 'validated', 'autonomous', 'low', '1',
   array['supplier acquisition','invite campaign','follow-up','300 suppliers','lead intake','inbound email','lead sourcing','supplier_outreach_golive','business development'],
   '{}'::text[], '{}'::jsonb, 'UAE', 'current', 'internal', true, true, 'current', 'pending', current_date),
  ('qd-loop:supplier-sanctions-screening', 'department', 'legal', 'legal', 'department_shared', 'operating_procedure', 'standard_operating_procedure',
   'compliance_and_privacy_officer', 'SOP — Weekly sanctions screening of registered suppliers (Compliance & Privacy Officer)',
   'PURPOSE: check every week whether any REGISTERED supplier appears on the UN consolidated list or the UAE Local Terrorist List, and update the team so a listed supplier is removed (founder, 6 Sep 2026).' || E'\n'
   || 'OWNER: Compliance & Privacy Officer (org_role compliance_and_privacy_officer, agent compliance_mgr, department legal) — the actor of supplier_onboarding step 4 "Compliance screen before anything is activated". Nobody new.' || E'\n'
   || 'WEEKLY, Mondays 03:00 UTC — sanctions_screen_weekly (fn_sanctions_screen_tick → edge function sanctions_screen): download the UN consolidated list (XML, scsanctions.un.org) and the UAE Local Terrorist List (uaeiec.gov.ae; PDF + legacy Excel only — the Excel is parsed, the PDF is not, no XML/JSON endpoint exists); record one screening_run per source (entries, fetched_at, sha256, status, note); store the names in screening_entry (normalised in SQL).' || E'\n'
   || 'SCREEN (fn_supplier_sanctions_screen): every lead in lifecycle_stage registered or approval_status approved, on legal name, licence name, owner, contact and e-mail domain label; a match is a normalised EXACT match or a CONSERVATIVE token overlap (at least two significant tokens, full containment). Each match is a supplier_screening_hit.' || E'\n'
   || 'ON A HIT: ONE task on the compliance officer with the evidence (field, value, listed name, source, reference, match kind, score) and ONE hold on the BD manager (no invitation, follow-up or onboarding step). The team is updated; the founder is not e-mailed. NOBODY is removed automatically.' || E'\n'
   || 'DECIDE (fn_supplier_screening_decide(hit, decision, actor)): compare licence, owner and address with the listing. CONFIRMED moves the supplier through the existing status path — leads.banned + banned_reason, matching_blocked, approval_status rejected — and closes both tasks as facts; FALSE_POSITIVE closes the hit. A failed download opens a task on the compliance officer to re-run the tick.',
   '{}'::jsonb, array['the_compliance_officer_screens_registered_suppliers_weekly.sql'], 'active', 'validated', 'autonomous', 'medium', '1',
   array['sanctions','sanctions screening','UN consolidated list','UAE local terrorist list','screening hit','banned supplier','compliance','weekly screening'],
   '{}'::text[], '{}'::jsonb, 'UAE', 'current', 'internal', true, true, 'current', 'pending', current_date)
on conflict (record_id) do update set
  title = excluded.title, content = excluded.content, keywords = excluded.keywords, role_key = excluded.role_key,
  effective_date = excluded.effective_date, supersession_state = 'current', embedding_status = 'pending';

-- ---------------------------------------------------------------- proof: the procedures are in ops_knowledge; the renderer's record is reported
do $proof$
declare n int; c text;
begin
  select count(*) into n from public.ops_knowledge
   where record_id in ('qd-loop:supplier-acquisition', 'qd-loop:supplier-sanctions-screening')
     and supersession_state = 'current' and scope_type = 'department' and layer = 'department_shared';
  if n <> 2 then raise exception 'profession records: % of 2', n; end if;
  select content into c from public.ops_knowledge where record_id = 'qd-company:supplier-loops' and supersession_state = 'current';
  if c is null or c not like '%SUPPLIER ACQUISITION LOOP%' or c not like '%WEEKLY SANCTIONS SCREENING%' then
    raise notice 'proof: 2 profession records current; qd-company:supplier-loops is NOT rendered yet (the integrator''s renderer file carries it)';
  else
    raise notice 'proof: 2 profession records current; qd-company:supplier-loops rendered by the live fn_company_self_knowledge_sync (% chars)', length(c);
  end if;
end $proof$;

commit;
