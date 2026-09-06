// H02 generator: fn_phase_d_object_write — no invented state, an identity probe by the caller's key,
// and an idempotent confirmation instead of a refusal when the row already carries what was asked.
import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- H02 — the writer invented a state, could not find the row it was told about, and refused a
--        write that asked for exactly what the row already was
--
-- Three corrections to fn_phase_d_object_write, for the EXISTING_TABLE branch only. The Phase D
-- object store branch is byte-identical.
--
-- 1. THE DEFAULT STATE WAS 'open', ONTO RELATIONS THAT FORBID IT AND ONTO ROWS THAT WERE FURTHER ON.
--    v_state defaulted to 'open' for every caller that named none, and the kernel dispatch names
--    none (H01). public.refunds, public.department_objective and public.org_tasks CHECK-refuse it
--    (W17-S01..S08, W01-S03, W01-S07 measured 23 Aug 2026); an inquiry the scenario had settled at
--    quote_ready was written back to open by W05-S01 and GATE-011 then refused W05-S04..S09; a
--    transaction at payment_reconciled was written back to open by W16-S01 and BR-033 / GATE-019
--    refused W16-S02..S09. A state the caller did not state is not written: an insert takes the
--    relation's own default (refunds -> requested, org_tasks -> proposed, department_objective ->
--    active, documents -> pending, read from pg_attrdef) and an update leaves the row's state
--    column alone. A caller who DOES state one still gets it written, and a caller who states one
--    for a relation whose map carries no state column is refused (pd_object_state_not_carried)
--    rather than silently dropped. The store branch keeps 'open' as its declared initial state.
--
-- 2. AN UPSERT WHOSE MAP DOES NOT CARRY THE KEY COLUMN COULD NEVER FIND ITS ROW.
--    D18's pass 1 probes key_column with "the value that will be written into it", so when the map
--    maps no key column (supplier_account: public.leads.id is generated) the probe is skipped, pass
--    2 needs a natural key the payload rarely carries, and the write INSERTS. Measured: every W09
--    step that wrote supplier_account created a new lead, and the scenario's supplier and the run's
--    supplier drifted apart (36093 vs 36096 in one drive). The business_key a Phase D caller passes
--    for an EXISTING_TABLE object IS that relation's primary key -- fn_phase_d_dispatch_step takes it
--    off the run's business_object_id and F44 made the writer return exactly that -- so pass 1b now
--    probes key_column::text = business_key when the map does not write the key column. A uuid
--    business key against a bigint column compares as text and simply matches nothing, which is
--    what it did before.
--
-- 3. A WRITE THAT MOVES NO COLUMN IS A CONFIRMATION, NOT A REFUSAL.
--    D27's refusal read "A write that changes nothing is not a state transition", and it was right
--    about a transition. It was wrong about the effect: the declared completion condition of every
--    OBJECT_STATE_WRITE step is "a row exists in <relation> carrying the declared state, readable
--    back in the same transaction" (public.phase_d_step_effect.completion_condition), and a row
--    that already carries it satisfies that. W04-S01/S03/S04/S05 were refused
--    pd_object_no_state_change against a customer row that was exactly as declared. The writer now
--    returns the existing reference with unchanged = true and columns_written = [] and writes
--    nothing; the effect ledger records state_before = state_after, so a confirmation is
--    distinguishable from a transition by anyone counting.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_object_write (phase_d_g11 is the last file
-- that defines it). No DDL.
--
-- Six anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_object_write'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

const a1 = `  v_state      text  := coalesce(nullif(btrim(p_input->>'state'),''), 'open');`;
once(a1, 'A1');
def = def.replace(a1, a1 + `
  v_state_given text := nullif(btrim(p_input->>'state'),'');   -- H02: what the caller actually said
  v_unchanged  boolean := false;                               -- H02: a confirmation, not a write`);

const a2 = `    v_supplied := v_payload
                  || jsonb_build_object('state', v_state, 'owner_ref', v_owner_ref,
                                        'business_key', v_key);`;
once(a2, 'A2');
def = def.replace(a2, `    -- H02 (1). NO STATE THE CALLER DID NOT STATE. An insert takes the relation's default and an
    -- update leaves the column alone; a stated state for a relation whose map carries no state
    -- column is refused rather than dropped on the floor.
    if v_state_given is not null
       and not exists (select 1 from jsonb_each_text(wm.column_map) k where k.value = 'state') then
      raise exception 'fn_phase_d_object_write: % was asked to carry state % and the write map for % maps no column to it. A state the relation cannot hold is not recorded as held. (pd_object_state_not_carried)',
        v_object, v_state_given, wm.target_relation using errcode = '22023';
    end if;
    v_supplied := v_payload
                  || jsonb_build_object('owner_ref', v_owner_ref, 'business_key', v_key)
                  || case when v_state_given is null then '{}'::jsonb
                          else jsonb_build_object('state', v_state_given) end;`);

const a3 = `      if v_existing is null then
        for v_uq in`;
once(a3, 'A3');
def = def.replace(a3, `      -- H02 (2). THE CALLER'S KEY IS THE RELATION'S KEY when the map writes no key column: probe it
      -- as text, which matches nothing when the shapes differ and the row when they do not.
      if v_existing is null and not (wm.column_map ? wm.key_column) then
        begin
          v_sql := format('select %I::text from %s where %I::text = $1 limit 1',
                          wm.key_column, wm.target_relation, wm.key_column);
          execute v_sql into v_existing using v_key;
        exception when others then
          v_existing := null;
        end;
      end if;

` + a3);

const a4 = `        if cardinality(v_sets) = 0 then
          raise exception 'fn_phase_d_object_write: % exists as % and the payload moves no column. A write that changes nothing is not a state transition. (pd_object_no_state_change)',
            v_object, v_existing using errcode = '22023';
        end if;
        -- D18. Update the row the probe actually FOUND.`;
once(a4, 'A4');
def = def.replace(a4, `        if cardinality(v_sets) = 0 then
          -- H02 (3). The row already carries everything this call asked for. That is the declared
          -- completion condition of an OBJECT_STATE_WRITE met, not a transition refused: the
          -- existing reference is returned, nothing is written, and unchanged = true says so.
          v_unchanged := true;
          v_result_ref := v_existing;
        end if;
        -- D18. Update the row the probe actually FOUND.`);

const a5 = `        v_sql := format('update %s set %s where %I::text = $2 returning %I::text',
                        wm.target_relation, array_to_string(v_sets, ', '),
                        wm.key_column, wm.key_column);
        execute v_sql into v_result_ref using v_supplied, v_existing;`;
once(a5, 'A5');
def = def.replace(a5, `        if not v_unchanged then
          v_sql := format('update %s set %s where %I::text = $2 returning %I::text',
                          wm.target_relation, array_to_string(v_sets, ', '),
                          wm.key_column, wm.key_column);
          execute v_sql into v_result_ref using v_supplied, v_existing;
        end if;`);

const a6 = `      'business_key', v_key, 'state', v_state,
      'policy_family', b.policy_family, 'record_policy', b.record_policy,
      'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
      'columns_written', to_jsonb(v_cols),`;
once(a6, 'A6');
def = def.replace(a6, `      'business_key', v_key, 'state', v_state_given,
      'policy_family', b.policy_family, 'record_policy', b.record_policy,
      'owner_scope', b.ownership_scope, 'owner_ref', v_owner_ref,
      'columns_written', case when v_unchanged then '[]'::jsonb else to_jsonb(v_cols) end,
      'unchanged', v_unchanged,`);

writeFileSync('scripts/sql/phase_d_h02_a_state_the_caller_never_stated.sql', HEAD + '\n' + def + '\n');
console.log('H02 written');
