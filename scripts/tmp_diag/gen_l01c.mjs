import { sql } from '../phase_b/lib/db.mjs';
import { writeFileSync } from 'node:fs';
const get = async sig => (await sql(`select pg_get_functiondef('${sig}'::regprocedure) def`))[0].def;
let he = await get('public.fn_phase_d_handler_execute(jsonb)');
const A = `         || case when b.handler_class = 'DECISION_HANDLER'
                 then jsonb_build_object('decided_by', v_actor, 'decided_at', now())
                 else '{}'::jsonb end));`;
if (!he.includes(A)) { console.error('MISS'); process.exit(1); }
const R = `         || case when b.handler_class = 'DECISION_HANDLER'
                 then jsonb_build_object('decided_by', v_actor, 'decided_at', now())
                 else '{}'::jsonb end
         -- L01. THE VERSION AND THE DIGEST THAT WERE ACCEPTED, FOR A STEP THAT RECORDS AN
         -- ACCEPTANCE. W09-S06's own frozen completion condition is "Displayed version, recorded
         -- version and document hash match" and the record it wrote carried none of the three:
         -- the payload was the workflow_record blob and nothing else. It went unseen because the
         -- fixture scenario built the acceptance itself, with the published pair on it, and every
         -- downstream read found the FIXTURE's record. Asked to withhold the object the workflow
         -- under test produces, W09-S07, S08 and S09 refused on BR-025 reading a business key
         -- where a digest belongs. The pair is the step's own resolved context -- the same value
         -- BR-025 has just judged at this step -- so the record now states what was accepted and
         -- BR-025 can judge it again downstream. A step whose object is not a registered
         -- acceptance adds nothing, and a context that resolved neither key adds nothing.
         || case when exists (select 1 from public.phase_d_acceptance_document a
                               where a.object_id = ec.effect_object_id)
                 then jsonb_strip_nulls(jsonb_build_object(
                        'terms_version', p_input->'context'->>'terms_version',
                        'terms_hash',    p_input->'context'->>'terms_hash'))
                 else '{}'::jsonb end));`;
he = he.replace(A, R);
writeFileSync('scripts/tmp_diag/l01_handler_execute.sql', he);
console.log('handler len=' + he.length);
