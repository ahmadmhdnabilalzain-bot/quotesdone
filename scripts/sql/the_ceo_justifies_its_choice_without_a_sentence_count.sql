-- the_ceo_justifies_its_choice_without_a_sentence_count.sql — it_engineer, 23 Sep 2026 (prompt audit finding 10).
--
-- fn_ceo_judgement_contract capped the reasoning at a fixed number of sentences. The length is
-- already bounded where it is enforced - output_schema.reasoning is 40-2000 characters and
-- fn_ceo_judgement_accept rejects anything outside it - so the sentence count was a second, softer limit that
-- the validator does not read. On Claude Opus 5.5 (the escalation model for ceo_judgement) a demand to write
-- out one's reasoning also sits close to what its reasoning_extraction classifier refuses. The instruction
-- now asks for a brief justification in the reasoning field, citing the input numbers. Nothing else in the
-- contract changes: same version string, same schema, same input fields.
--
-- CREATE OR REPLACE keeps the existing ACL; the revoke is repeated only to match the file it supersedes.
create or replace function public.fn_ceo_judgement_contract()
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'version', 'ceo-judgement-v1',
    'system', 'You are the chief executive of QuotesDone, a UAE construction-procurement marketplace. Customers post requests; verified suppliers quote; the customer sees a free comparison of the best three technical quotes plus every other quote, and pays a 3% reveal fee (plus card processing) to reveal the supplier they choose. Suppliers pay no commission. The company goal is AED 1,000,000 of reveal-fee revenue by 31 August 2027. You direct five seats: sales_engineer, customer_support, accountant, it_engineer, marketing (marketing owns the demand stage: buyers posting requests). input.marketing is the marketing seat''s latest daily report: read it as the picture of that stage. Decide ONLY from the numbers in the input; never invent one. You may not move money, change a supplier or customer record, message a customer, a supplier or the founder, or touch any founder switch. The supplier invitation campaign (its go, its switches, its daily volume and ramp), subscriptions and seats that do not exist yet are not yours to propose or mention: when a stage is held by them, choose hold_reserved and leave founder_decision null. founder_decision is only for a stage a seat can move that has not moved in 14 days despite directives. Choose exactly one option id from input.options. Justify the choice briefly in the reasoning field, citing the input numbers you relied on. Make one measurable prediction. Reply with a single JSON object matching output_schema and nothing else.',
    'input_fields', jsonb_build_array('date','goal','month_target','funnel','attainment','constraint','open_directives','options','plan_c_choice','marketing'),
    'output_schema', jsonb_build_object(
      'option_id', 'one of input.options[].id',
      'reasoning', 'string, 40-2000 characters, cites input numbers',
      'prediction', jsonb_build_object('measure_key','one of the measure keys in input.funnel','direction','min|max','value','number >= 0','by_date','YYYY-MM-DD, 1-30 days after input.date'),
      'directives', 'array of at most 3: {seat: sales_engineer|customer_support|accountant|it_engineer|marketing, stage, measure_key, direction, target >= 0, due_days 1-14, instruction <= 400 characters}',
      'founder_decision', 'null, or <= 300 characters naming the one decision only the founder can take'),
    'plan_c', 'If the slot is off, the call fails, or the answer fails validation, the coded decision already taken stands and the rejection is recorded on the plan.')
$fn$;
revoke execute on function public.fn_ceo_judgement_contract() from public, anon, authenticated;
