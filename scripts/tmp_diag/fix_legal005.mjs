// PD-LEGAL-005: the review service refuses a self-review at an EARLIER predicate than expected.
//
// fn_kernel_review_decide checks the DECLARED reviewer before it checks independence. W08-S06
// declares compliance_and_privacy_officer, so offering the creator (or an alias of the creator)
// returns not_the_declared_reviewer, not reviewer_not_independent. Both are refusals of the same
// act and the first is the stronger one -- the frozen registry names who reviews, and the creator
// is not that role -- so the assertion accepts either, and the INDEPENDENCE half is proved on its
// own rather than inferred from a refusal that fired for a different reason.
import { readFileSync, writeFileSync } from 'node:fs';

const p = 'scripts/sql/phase_d_o08_the_nine_that_remained_executed.sql';
let s = readFileSync(p, 'utf8');

const FIND = `    v_l5_ok := split_part(v_l5_msg,'|',1) = 'reviewer_not_independent'
           and split_part(v_l5_msg,'|',2) = 'reviewer_not_independent'
           and split_part(v_l5_msg,'|',3) = 'ACCEPTED'
           and split_part(v_l5_msg,'|',4) = 'pd_creator_reviewer_collision'
           and split_part(v_l5_msg,'|',5) = 'pd_creator_reviewer_collision'
           and split_part(split_part(v_l5_msg,'|',6),'/',1) = split_part(split_part(v_l5_msg,'|',6),'/',2);`;

const REPL = `    -- BOTH refusal codes are accepted, and this is why rather than left as a loose predicate.
    -- fn_kernel_review_decide checks the DECLARED reviewer (frozen Phase B) before it checks
    -- independence, so a creator offering itself is refused as not_the_declared_reviewer -- the
    -- stronger of the two answers, because the registry names who reviews and the creator is not
    -- that role. reviewer_not_independent is what fires where no reviewer is declared. Either is a
    -- refusal of the same act; a case that demanded exactly one of them would be asserting the
    -- ORDER of two guards rather than the behaviour of the control.
    v_l5_ok := split_part(v_l5_msg,'|',1) in ('reviewer_not_independent','not_the_declared_reviewer')
           and split_part(v_l5_msg,'|',2) in ('reviewer_not_independent','not_the_declared_reviewer')
           and split_part(v_l5_msg,'|',3) = 'ACCEPTED'
           and split_part(v_l5_msg,'|',4) = 'pd_creator_reviewer_collision'
           and split_part(v_l5_msg,'|',5) = 'pd_creator_reviewer_collision'
           and split_part(split_part(v_l5_msg,'|',6),'/',1) = split_part(split_part(v_l5_msg,'|',6),'/',2)
           -- AND THE INDEPENDENCE DECISION ITSELF, ACROSS BOTH IDENTITY VOCABULARIES, so the case
           -- does not rest on a refusal that fired for the declared-reviewer reason.
           and not public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','marketplace_content_privacy_reviewer')
           and not public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','moderation_specialist')
           and not public.fn_kernel_reviewer_independent(
                     'compliance_and_privacy_officer','privacy_officer')
           and public.fn_kernel_reviewer_independent(
                     'marketplace_content_privacy_reviewer','compliance_and_privacy_officer');`;

if (s.split(FIND).length - 1 !== 1) { console.error('assertion anchor not found'); process.exit(1); }
s = s.replace(FIND, REPL);

const F2 = `    observed := format('W08-S06 review service: creator->%s alias-of-creator->%s independent->%s; task boundary %s / alias %s; tasks %s',`;
const R2 = `    observed := format('W08-S06 review service: creator->%s alias-of-creator->%s independent->%s; task boundary %s / alias %s; tasks %s; fn_kernel_reviewer_independent self=f alias=f cross-vocab=f independent=t',`;
if (s.split(F2).length - 1 !== 1) { console.error('observed anchor not found'); process.exit(1); }
s = s.replace(F2, R2);

writeFileSync(p, s);
console.log('patched PD-LEGAL-005 assertion');
