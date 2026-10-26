-- fn_ops_authority_check refuses any action class with no action_class_gate row: "Unreviewed is
-- not unrestricted: map it to a hard gate, or to NULL with a stated rationale, before it can be
-- autonomous." 28 of the executor registry's active classes had no row, so every one of them was
-- refused no matter what org_authority said. This is the review it asked for.
--
-- Mapped to a hard gate where the action genuinely crosses one; NULL where it does not, each with
-- the reason. Reading money is not moving money -- money_verify, invoice_review, ap_duplicate_scan
-- and spend_check inspect records and change no balance, so they carry no money_move gate, while
-- anything that actually moves money keeps one through the existing 35 rows.
insert into public.action_class_gate (action_class, gate_action_class, rationale, reviewed_on, reviewed_by)
values
  ('collections_chase','legal_commitment','Chasing a debt asserts a claim against a counterparty and is not reversible once sent.','2026-08-10','corpus_review'),
  ('dispute_open','legal_commitment','Opening a dispute is a formal position taken against a counterparty.','2026-08-10','corpus_review'),
  ('pdpl_action','authentication_identity','Acts on a data subject''s personal data under PDPL; irreversible and identity-bearing.','2026-08-10','corpus_review'),
  ('escalate_founder',null,'Notifying the founder is the escape hatch itself; gating it would remove the only path out of a stuck decision.','2026-08-10','corpus_review'),
  ('money_verify',null,'Verification READS ledger and invoice records and moves no balance. Anything that moves money keeps its money_move gate.','2026-08-10','corpus_review'),
  ('invoice_review',null,'Reviews an invoice document and changes no balance; payment itself is separately gated.','2026-08-10','corpus_review'),
  ('ap_duplicate_scan',null,'Detects duplicate payables. Read-only over accounts payable.','2026-08-10','corpus_review'),
  ('spend_check',null,'Compares spend against budget. Read-only.','2026-08-10','corpus_review'),
  ('compare_quotes',null,'Ranks quotes for a customer and commits nothing.','2026-08-10','corpus_review'),
  ('qualify_inquiry',null,'Scores an inbound inquiry for completeness.','2026-08-10','corpus_review'),
  ('boost_recommend',null,'Recommends a budget boost; the spend itself is gated by ad_spend.','2026-08-10','corpus_review'),
  ('capability_exam',null,'Examines an employee''s own knowledge and writes an exam result.','2026-08-10','corpus_review'),
  ('content_revise',null,'Revises a draft. Publishing is separately gated by public_claim_publish.','2026-08-10','corpus_review'),
  ('knowledge_fill_gap',null,'Writes knowledge corrections into the staging corpus, reversible by revision.','2026-08-10','corpus_review'),
  ('seo_produce',null,'Produces SEO drafts; publication is separately gated.','2026-08-10','corpus_review'),
  ('qa_gate',null,'Holds work that fails a quality check. Restrictive, never permissive.','2026-08-10','corpus_review'),
  ('security_review',null,'Reads scan output and reports. Remediation is separately gated.','2026-08-10','corpus_review'),
  ('secops_pattern_test',null,'Runs detection patterns against test fixtures.','2026-08-10','corpus_review'),
  ('uptime_verify',null,'Probes endpoints and records the verdict.','2026-08-10','corpus_review'),
  ('health_report',null,'Summarises health signals already computed.','2026-08-10','corpus_review'),
  ('metric_alerts',null,'Raises an alert from a computed metric.','2026-08-10','corpus_review'),
  ('bi_snapshot',null,'Writes a periodic analytics snapshot.','2026-08-10','corpus_review'),
  ('brand_scan',null,'Scans public mentions and records them.','2026-08-10','corpus_review'),
  ('event_dispatch',null,'Delivers an already-emitted event to its subscribers.','2026-08-10','corpus_review'),
  ('evolution_scan',null,'Inspects the estate and raises proposals; it applies nothing.','2026-08-10','corpus_review'),
  ('growth_simulate',null,'Runs a forward simulation and writes no live state.','2026-08-10','corpus_review'),
  ('idea_submit',null,'Files an idea for consideration.','2026-08-10','corpus_review'),
  ('review_submit',null,'Submits work into the review chain, which decides separately.','2026-08-10','corpus_review')
on conflict (action_class) do nothing;
