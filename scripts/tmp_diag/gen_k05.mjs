// K05 — the two gates on public.inquiry_matches refused without saying so.
import { writeFileSync } from 'node:fs';
import { liveBody, splice } from './splice.mjs';

const HEADER = `-- K05 — a gate that refused a row and told nobody
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. public.inquiry_matches carries two BEFORE INSERT
-- gates and both answer a refusal with a bare \`return null\`:
--
--   a00_unsafe_match_eligibility  banned / matching_blocked / permanently_closed / expired licence
--   gate_incomplete_match         "silently skip: incomplete RFQs don't qualify for routing"
--
-- A BEFORE trigger returning null is not an error. PostgREST answers 201 with no row and plpgsql's
-- INSERT reports SUCCESSFUL_COMPLETION, so a refusal and a write are the same observation to every
-- caller that does not ask for the row back. That has already cost this estate twice:
--
--   15 Aug 2026  dispatch_inquiry counted a refused supplier as a notified one, routing.fanout
--                over-reported the reach of the RFQ, and the redispatch sweep -- which only retries
--                a fanout recorded as 0 -- never retried an RFQ whose every match was refused.
--   23 Aug 2026  W12-S06 lost its declared effect to the second gate and the refusal named nothing,
--                so the hand-over recorded the wrong cause. See K02.
--
-- WHAT THIS FILE CHANGES. Neither gate's DECISION moves: the same rows are refused, for the same
-- reasons, and the return stays null so a multi-row insert is not aborted by one refused candidate.
-- What changes is that the refusal is now stated:
--
--   * one stable verdict per outcome -- PASS, BLOCKED_MISSING_MATCH_EVIDENCE, BLOCKED_NOT_RFQ_READY,
--     BLOCKED_INELIGIBLE_SUPPLIER -- published on the transaction-local key
--     app.inquiry_match_gate_verdict, together with app.inquiry_match_gate_reason;
--   * a warning naming the verdict and the row;
--   * and public.fn_phase_d_object_write reads the verdict when a write returns no key, so
--     pd_object_write_produced_nothing now says WHICH gate refused and why instead of reporting the
--     silence.
--
-- WHY NOT public.unsafe_block. The eligibility gate writes there and should: an inquiry sent to a
-- banned supplier is a safety incident and unsafe_class registers it as one. An incomplete RFQ is
-- ordinary business routing, and recording every one of those in the safety ledger would make the
-- ledger useless for the thing it exists to find. The verdict key carries it instead.
--
-- ROLLBACK: scripts/sql/down/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody_down.sql
-- re-applies the previous bodies of the two trigger functions and of fn_phase_d_object_write.
--
-- GENERATED from the live bodies by scripts/tmp_diag/gen_k05.mjs.

CREATE OR REPLACE FUNCTION public.trg_gate_incomplete_match()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare ready boolean; v_found boolean := false; v_verdict text; v_reason text;
begin
  if NEW.inquiry_id is null then
    v_verdict := 'BLOCKED_MISSING_MATCH_EVIDENCE';
    v_reason  := 'the assignment names no inquiry, so there is nothing whose readiness could be judged';
  else
    select true, i.rfq_ready into v_found, ready
      from public.inquiries i where i.id = NEW.inquiry_id;
    if not coalesce(v_found, false) then
      v_verdict := 'BLOCKED_MISSING_MATCH_EVIDENCE';
      v_reason  := format('inquiry %s does not exist', NEW.inquiry_id);
    elsif ready is not true then
      v_verdict := 'BLOCKED_NOT_RFQ_READY';
      v_reason  := format('inquiry %s is %s; an incomplete RFQ does not qualify for routing',
                          NEW.inquiry_id,
                          case when ready is null then 'not scored for readiness' else 'not rfq_ready' end);
    else
      v_verdict := 'PASS';
      v_reason  := format('inquiry %s is rfq_ready', NEW.inquiry_id);
    end if;
  end if;

  perform set_config('app.inquiry_match_gate_verdict', v_verdict, true);
  perform set_config('app.inquiry_match_gate_reason',  v_reason,  true);
  if v_verdict = 'PASS' then return NEW; end if;

  raise warning 'gate_incomplete_match: % — %', v_verdict, v_reason;
  return null;   -- the row is refused; the verdict above is how a caller knows it was refused
end
$function$;

`;

// The eligibility gate publishes the same key, so ONE key answers "why did this row not land".
const elig = splice(await liveBody('fn_unsafe_match_eligibility_guard'), [
  [`  if l.id is null then return new; end if;`,
   `  if l.id is null then
    -- K05. The supplier is not on record here; this gate has nothing to judge and says so rather
    -- than leaving the verdict key holding whatever the previous row left in it.
    perform set_config('app.inquiry_match_gate_verdict', 'PASS', true);
    perform set_config('app.inquiry_match_gate_reason',
      format('supplier %s is not in public.leads; this gate judges eligibility and has no row',
             new.supplier_id), true);
    return new;
  end if;`],
  [`  if v_reason is null then return new; end if;`,
   `  if v_reason is null then
    perform set_config('app.inquiry_match_gate_verdict', 'PASS', true);
    perform set_config('app.inquiry_match_gate_reason',
      format('supplier %s is eligible to receive a match', new.supplier_id), true);
    return new;
  end if;

  -- K05. A REFUSAL THAT STATES ITSELF. The ledger row below is the safety record; this is the
  -- verdict the writer and the caller read, on the same key the readiness gate publishes.
  perform set_config('app.inquiry_match_gate_verdict', 'BLOCKED_INELIGIBLE_SUPPLIER', true);
  perform set_config('app.inquiry_match_gate_reason',
    format('supplier %s: %s', new.supplier_id, v_reason), true);`],
]);

// The writer names the verdict instead of reporting the silence.
const write = splice(await liveBody('fn_phase_d_object_write'), [
  [`    if v_result_ref is null then
      raise exception 'fn_phase_d_object_write: the write to % for % returned no key. Refusing to report a write that produced nothing. (pd_object_write_produced_nothing)',
        wm.target_relation, v_object using errcode = '23502';
    end if;`,
   `    if v_result_ref is null then
      -- K05. NAME THE GATE THAT REFUSED. A BEFORE trigger returning null gives a statement that
      -- "succeeded" with no row, and this message used to report only the silence -- which is how
      -- W12-S06's cause was recorded wrongly in the 23 Aug hand-over. Where the refusing gate
      -- published a verdict, it is quoted here.
      raise exception 'fn_phase_d_object_write: the write to % for % returned no key. Refusing to report a write that produced nothing. Gate verdict: % — %. (pd_object_write_produced_nothing)',
        wm.target_relation, v_object,
        coalesce(nullif(current_setting('app.inquiry_match_gate_verdict', true),''), '(no gate published a verdict)'),
        coalesce(nullif(current_setting('app.inquiry_match_gate_reason', true),''), 'no reason was published')
        using errcode = '23502';
    end if;`],
]);

writeFileSync('scripts/sql/phase_d_k05_a_gate_that_refused_a_row_and_told_nobody.sql',
  HEADER + elig + ';\n\n' + write + ';\n');
console.log('written');
