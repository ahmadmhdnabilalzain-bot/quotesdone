-- P2-C1 - recovered verbatim from supabase_migrations.schema_migrations.
-- Applied version: 20260802174756   name: p2_c1_stage_b5_evidence_score_semantics
-- SHA-256 of the applied SQL: 0b78da64e6bf1753c43229ee1aa6ea7510fd5fe46802ffabc986b9e786e7682a
-- Recovered by scripts/recover_stage_a_b_b5.mjs against the manifest committed beforehand.
-- The body below is byte-for-byte as applied; only this header was added, and it is
-- excluded from the checksum.

-- P2-C1 STAGE B.5 (1/5) - EVIDENCE SCORE, not confidence, not probability.
--
-- 1.00 / 0.95 / 0.90 / 0.75 / 0.60 / 0.40 are RULE WEIGHTS chosen by hand to order the sources and
-- to keep document evidence below the confirmation threshold. Nothing has measured them against
-- real inquiries. Calling that column `confidence` invites someone to read 0.60 as "60% likely to
-- be right", which is a claim nobody has earned.

drop view if exists public.v_inquiry_trade_status cascade;

alter table public.inquiry_trade_candidate rename column confidence to evidence_score;
alter table public.inquiry_trade_candidate_evidence rename column confidence to evidence_score;

alter table public.inquiry_trade_candidate
  add column if not exists score_basis text not null default 'rule_weight_provisional'
    check (score_basis in ('rule_weight_provisional','calibrated_frequency','measured_probability'));
alter table public.inquiry_trade_candidate_evidence
  add column if not exists score_basis text not null default 'rule_weight_provisional'
    check (score_basis in ('rule_weight_provisional','calibrated_frequency','measured_probability'));
alter table public.inquiry_trade_candidate
  add column if not exists confirmation_factors jsonb;

comment on column public.inquiry_trade_candidate.evidence_score is
  'A rule weight on 0..1, NOT a probability. See score_basis. Provisional until the full 3,324-scenario run calibrates it.';
comment on column public.inquiry_trade_candidate.score_basis is
  'rule_weight_provisional = hand-chosen ordering weight. calibrated_frequency = observed hit rate from the scenario corpus. measured_probability = a real posterior. Only the first is in use today.';
comment on column public.inquiry_trade_candidate.confirmation_factors is
  'The six inputs to the confirm/propose decision, recorded per candidate so the decision can be re-read later: source authority, exactness, alias specificity, ambiguity, runner-up matches, confirmation requirement.';

create table if not exists public.mep_evidence_weight (
  weight_key        text primary key,
  evidence_source   text not null,
  variant           text,
  evidence_score    numeric(4,3) not null,
  score_basis       text not null default 'rule_weight_provisional',
  source_authority  text not null,
  exactness         text not null,
  auto_confirms     boolean not null,
  rationale         text not null
);
alter table public.mep_evidence_weight enable row level security;

insert into public.mep_evidence_weight
  (weight_key, evidence_source, variant, evidence_score, source_authority, exactness, auto_confirms, rationale) values
  ('structured_answer','structured_answer', null, 1.000, 'customer', 'exact_selection', true,
   'The customer picked the trade from a list. There is nothing to infer and nothing to confirm.'),
  ('customer_text.trade_name','customer_text','trade_name', 0.950, 'customer', 'exact_phrase', true,
   'The customer named the trade in their own words. Below structured selection only because free text can carry a passing mention.'),
  ('scope_rule.mep_full_scope','scope_rule','mep_full_scope', 0.900, 'derived_from_customer', 'phrase_rule', true,
   'An MEP anchor with a full-scope modifier, or an explicit full-MEP phrase. Derived from the customer''s words, so it confirms - but it is a rule, which is why it sits below a named trade.'),
  ('alias.unique','alias','unique', 0.750, 'customer', 'catalogue_alias', true,
   'A catalogue alias belonging to exactly one trade appeared in the customer text. Specific and customer-authored, so it confirms.'),
  ('document_extraction','document_extraction', null, 0.600, 'document', 'catalogue_alias', false,
   'An approved document contains an alias. NEVER auto-confirms, at any score: a drawing is not an instruction. The weight orders it against other evidence; the confirmation rule is separate and absolute.'),
  ('alias.ambiguous','alias','ambiguous', 0.400, 'customer', 'catalogue_alias', false,
   'The alias belongs to more than one trade, so the evidence does not say which. Proposes and asks.')
on conflict (weight_key) do nothing;

comment on table public.mep_evidence_weight is
  'The rule weights, and why each is where it is. auto_confirms is NOT derived from the score: document evidence would never confirm even at 0.99, because the rule is about authority, not strength.';

create view public.v_inquiry_trade_status as
select c.group_id, c.trade_key, t.label_en, t.is_core, c.status, c.evidence_source,
       c.evidence_score, c.score_basis, c.confirmation_factors,
       c.requires_confirmation, c.match_reason,
       c.proposed_at, c.confirmed_at, c.confirmed_by, c.rejected_at, c.rejection_reason,
       c.inactivated_at, c.activated_at, c.workstream_id,
       w.active as workstream_active,
       (select count(*) from public.inquiry_trade_candidate_evidence e where e.candidate_id = c.id) as evidence_rows,
       (c.status = 'confirmed' and w.active) as counts_toward_dispatch
  from public.inquiry_trade_candidate c
  join public.mep_trade t on t.trade_key = c.trade_key
  left join public.inquiry_workstream w on w.id = c.workstream_id;

comment on view public.v_inquiry_trade_status is
  'Only a confirmed candidate with an active workstream counts toward dispatch. A proposed trade is visible, evidenced, and inert.';

create or replace function public.fn_group_dispatch_report(p_group_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_gd public.v_group_dispatch%rowtype; v_blockers jsonb := '[]'::jsonb; r record;
begin
  select * into v_gd from public.v_group_dispatch where group_id = p_group_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_group'); end if;

  if v_gd.active_workstreams = 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','no_active_workstream','severity','blocking',
      'detail','No trade has been confirmed for this inquiry, so there is nothing to dispatch.',
      'remedy','Confirm at least one trade, or answer the open clarification.'));
  end if;

  if cardinality(v_gd.shared_missing_mandatory) > 0 then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','shared_mandatory_missing','severity','blocking',
      'fields', to_jsonb(v_gd.shared_missing_mandatory),
      'detail','Shared project fields required by an active workstream are unanswered.'));
  end if;

  if not v_gd.no_unresolved_shared_conflict then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','open_shared_conflict','severity','blocking',
      'fields', (select coalesce(jsonb_agg(c.field_id), '[]'::jsonb)
                   from public.inquiry_answer_conflict c
                   join public.field_definition fd on fd.field_id = c.field_id
                  where c.group_id = p_group_id and c.resolved_at is null and fd.scope = 'shared'),
      'detail','A shared field has sources that disagree. Every workstream is affected.'));
  end if;

  for r in select * from public.v_workstream_dispatch
            where group_id = p_group_id and active and not dispatch_eligible loop
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','trade_not_eligible','severity','blocking','trade_key', r.trade_key,
      'missing_mandatory', to_jsonb(r.missing_mandatory),
      'unresolved_conflicts', to_jsonb(r.blocked_by),
      'gate_states', r.gate_states,
      'detail','This trade is not dispatch-eligible, so the group is not.'));
  end loop;

  for r in select gr.gate_key,
                  coalesce((select g.state::text from public.inquiry_gate g
                             where g.group_id = p_group_id and g.workstream_id is null
                               and g.gate_key = gr.gate_key), 'not_evaluated') as state
             from public.inquiry_gate_required gr where gr.level = 'group' loop
    if r.state not in ('passed','not_applicable') then
      v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
        'blocker','group_gate_not_satisfied','severity','blocking',
        'gate_key', r.gate_key, 'state', r.state,
        'detail', case when r.state = 'not_evaluated'
                       then 'This gate has never been evaluated. Absent reads as failed.'
                       else 'Gate state is ' || r.state || '.' end));
    end if;
  end loop;

  for r in select trade_key, evidence_score, score_basis, evidence_source
             from public.inquiry_trade_candidate
            where group_id = p_group_id and status = 'proposed' loop
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','trade_awaiting_confirmation','severity','informational','trade_key', r.trade_key,
      'evidence_source', r.evidence_source, 'evidence_score', r.evidence_score,
      'score_basis', r.score_basis,
      'detail','Proposed but not confirmed. It contributes nothing to dispatch until a person confirms it.'));
  end loop;

  if exists (select 1 from public.inquiry_trade_clarification
              where group_id = p_group_id and answered_at is null) then
    v_blockers := v_blockers || jsonb_build_array(jsonb_build_object(
      'blocker','open_clarification','severity','blocking',
      'question', (select question_en from public.inquiry_trade_clarification
                    where group_id = p_group_id and answered_at is null limit 1),
      'detail','The customer has been asked which trades this enquiry covers.'));
  end if;

  return jsonb_build_object(
    'ok', true, 'group_id', p_group_id,
    'overall_dispatch_eligible', v_gd.overall_dispatch_eligible,
    'active_workstreams', v_gd.active_workstreams,
    'shared_complete', v_gd.shared_complete,
    'group_gate_states', v_gd.gate_states,
    'blocking_trades', to_jsonb(v_gd.blocking_trades),
    'blockers', v_blockers,
    'blocker_count', jsonb_array_length(v_blockers));
end $fn$;

revoke all on function public.fn_group_dispatch_report(bigint) from public, anon, authenticated;
;