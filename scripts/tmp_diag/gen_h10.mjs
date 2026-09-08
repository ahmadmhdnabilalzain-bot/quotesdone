// H10 generator: fn_phase_d_effect_produce — the review_record write fills review_chain's four
// mandatory columns from facts the run already holds, not from a catalogue it never consulted.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const HEAD = `-- H10 — the review verdict wrote a chain row with no subject, no author and no stage type
--
-- MEASURED 23 Aug 2026 on 36 of 50 remaining un-executed steps, every one:
--     null value in column "subject_type" of relation "review_chain" violates not-null constraint
--
-- public.review_chain demands subject_type, subject_id, dept_key, author_agent and stage NOT NULL.
-- review_record's write map maps all five. But fn_phase_d_fixture_effect_payload -- the routine that
-- fills a relation's mandatory columns from the committed catalogue -- keys off e.effect_object_id,
-- the STEP's declared business object (inquiry, quotation, ...), not off review_record. A
-- REVIEW_VERDICT step's declared object is the thing being reviewed, so the review-chain columns
-- were never in that routine's population and the REVIEW_VERDICT branch here wrote them as null.
--
-- They are not content a handler invents; every one is a fact the run already holds:
--   subject_type  the object under review -- e.effect_object_id, the step's own declared object
--   subject_id    the identity of that object -- the business_key the dispatch already derived, or
--                 the step-run compound where a review step names no object of its own
--   author_agent  the actor accountable for the output under review -- v_actor. review_chain
--                 CHECK review_chain_no_self_approval_ck refuses author = reviewer, and BR-002
--                 already guarantees the review step's actor is independent of its reviewer, so
--                 author_agent is the actor and reviewer_agent (the map's reviewer_role_id key)
--                 is the reviewer -- never the same identity
--   stage         already set to sr.step_id
--
-- The catalogue's global subject_type/subject_id/author_agent fixtures (PDF-4007/4008/4010) stay --
-- they are what fn_phase_d_fixture_effect_payload would use IF review_record were the effect object,
-- and a caller who supplies these keys still overrides -- but a review step no longer depends on a
-- routine that was looking at a different object. dept_key is filled by the existing owner_ref
-- derivation, which resolves a real department for a COMPANY-scoped write.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_effect_produce (phase_d_e26 is the last file
-- that defines it). No DDL.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_effect_produce'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

const a1 = `    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','review_record',
      'business_key', coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
      'owner_ref', coalesce(v_owner, sr.accountable_role_id),
      'created_by', v_actor,
      'state', coalesce(v_state, v_payload->>'verdict'),
      'payload', v_payload || jsonb_build_object(
        'stage', sr.step_id, 'notes', coalesce(v_payload->>'notes', 'phase_d review verdict'))));`;
once(a1, 'A1');
def = def.replace(a1, `    -- H10. review_chain demands subject_type, subject_id, author_agent and stage. The caller's
    -- payload wins where it names them; otherwise each is the fact the run already holds -- what is
    -- under review, its identity, and who reviewed it -- never invented. dept_key comes from the
    -- owner_ref derivation, which resolves a real department for a COMPANY-scoped write.
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','review_record',
      'business_key', coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
      'owner_ref', coalesce(v_owner, sr.accountable_role_id),
      'created_by', v_actor,
      'state', coalesce(v_state, v_payload->>'verdict'),
      'payload', jsonb_build_object(
        'subject_type', e.effect_object_id,
        'subject_id',   coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
        'author_agent', v_actor,
        'stage',        sr.step_id,
        'notes',        coalesce(v_payload->>'notes', 'phase_d review verdict'))
        || v_payload));`);

writeFileSync('scripts/sql/phase_d_h10_the_review_verdict_that_named_no_subject.sql', HEAD + '\n' + def + '\n');
console.log('H10 written');
