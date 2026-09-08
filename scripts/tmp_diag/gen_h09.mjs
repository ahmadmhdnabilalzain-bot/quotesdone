// H09 generator: fn_phase_d_object_write — H02's "state not carried" refusal refused the 41 review
// verdicts; it becomes a reported fact instead of a refusal.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const HEAD = `-- H09 — a refusal H02 added that fired on the one object whose state was never a column
--
-- H02 refused a write that stated a state for a relation whose write map carries no state column
-- (pd_object_state_not_carried), on the argument that a state the relation cannot hold must not be
-- reported as held. Measured immediately afterwards: every REVIEW_VERDICT effect refused. The
-- review_record object is written by fn_phase_d_effect_produce with state = the verdict, and its
-- relation public.review_chain carries the verdict in its own columns (stage, notes, the payload)
-- and has never had a "state" column in its map -- the verdict is the content, not a state. The
-- refusal was a guard that fires when the system works (the third shape in the memory of this
-- estate), so it is removed: a stated state the map cannot carry is now REPORTED, as
-- state_carried_by_relation = false on the write's return, and the effect ledger's state_after
-- still records what was asked. The two corrections that mattered in H02 -- no invented 'open', and
-- a no-op confirmation instead of a refusal -- are untouched.
--
-- ROLLBACK: re-apply phase_d_h02's body. No DDL.
--
-- Two anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_object_write'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

const a1 = `    if v_state_given is not null
       and not exists (select 1 from jsonb_each_text(wm.column_map) k where k.value = 'state') then
      raise exception 'fn_phase_d_object_write: % was asked to carry state % and the write map for % maps no column to it. A state the relation cannot hold is not recorded as held. (pd_object_state_not_carried)',
        v_object, v_state_given, wm.target_relation using errcode = '22023';
    end if;
`;
once(a1, 'A1');
def = def.replace(a1, `    -- H09. A stated state the map cannot carry is reported on the return, not refused: review_record
    -- carries its verdict as content and has never had a state column.
`);

const a2 = `      'unchanged', v_unchanged,`;
once(a2, 'A2');
def = def.replace(a2, `      'unchanged', v_unchanged,
      'state_carried_by_relation', (v_state_given is null
         or exists (select 1 from jsonb_each_text(wm.column_map) k where k.value = 'state')),`);

writeFileSync('scripts/sql/phase_d_h09_a_refusal_that_fired_on_every_verdict.sql', HEAD + '\n' + def + '\n');
console.log('H09 written');
