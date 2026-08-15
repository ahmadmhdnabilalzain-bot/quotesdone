// Prove the Phase B guards FIRE.
//
//   node scripts/checks/phase_b_guards_reject_injected_defects.test.mjs
//
// A constraint that has never refused anything is indistinguishable from no constraint.  Each
// case below injects one specific defect inside an aborted transaction and requires the
// database to refuse it; a case that succeeds is the failure.  Nothing is left behind: every
// statement ends in a rollback, and the test asserts the row counts are unchanged afterwards.
//
// The defects are the ten the Phase B master prompt names, plus the three this estate has
// actually shipped before: an owner addressed to a name nobody models, a handoff naming
// parties who do not own the steps it joins, and an exception escalating to its own detector.
import { sql } from '../phase_b/lib/db.mjs';

// Ids are DERIVED from the live registry, never hard-coded.  The first version of this test
// used 'H-W12-01-02', which does not exist: the UPDATE matched zero rows, raised nothing, and
// the test read that silence as "the guard accepted the defect".  A zero row count cannot tell
// a dead guard from an injection that never landed, so every mutating case now also asserts it
// actually changed a row.
const [ids] = await sql(`
  select
    (select handoff_id from public.phase_b_handoff where workflow_id = 'W12' order by handoff_id limit 1) as w12_handoff,
    (select h.from_step_id from public.phase_b_handoff h where h.workflow_id = 'W12' order by h.handoff_id limit 1) as w12_from,
    (select s.step_id from public.phase_b_workflow_step s
      where s.independent_reviewer_role_id is not null order by s.step_id limit 1) as reviewed_step,
    (select s.step_id from public.phase_b_workflow_step s
      where s.workflow_id = 'W12' and s.actor_kind = 'canonical_role' order by s.step_id limit 1) as w12_step,
    (select s.step_id from public.phase_b_workflow_step s
      where s.workflow_id = 'W14' and s.step_type = 'decision' order by s.step_id limit 1) as w14_decision,
    (select s.step_id from public.phase_b_workflow_step s
      where s.workflow_id = 'W16' and s.accountable_role_id = 'payments_and_billing_manager'
      order by s.step_id limit 1) as w16_payment_step,
    (select exception_id from public.phase_b_exception order by exception_id limit 1) as any_exception`);
for (const [k, v] of Object.entries(ids)) {
  if (!v) { console.error(`FAIL  could not derive a live id for "${k}" — the registry is not loaded as expected`); process.exit(1); }
}

/** Wrap a mutation so it fails loudly when it matches no row. */
const mustAffect = stmt => `do $inject$ begin
  ${stmt};
  if not found then raise exception 'INJECTION MISSED: the statement matched no row'; end if;
end $inject$;`;

const CASES = [
  {
    name: 'missing owner',
    why: 'a step with no accountable owner must not be storable',
    sql: `insert into public.phase_b_workflow_step
            (step_id, workflow_id, step_no, step_name, step_type, accountable_role_id,
             package_accountable_token, actor_kind, entry_condition, required_inputs,
             required_action, required_output, acceptance_criteria, closure_criteria,
             failure_or_block_state, idempotency_scope, next_step_if_pass, next_step_if_fail,
             success_workflow_state, failure_workflow_state)
          values ('ZZ-INJECT-01','W01',900,'x','analysis',null,'x','canonical_role','x','x','x','x','x','x',
                  'blocked','x','WORKFLOW_COMPLETE','WORKFLOW_BLOCKED','completed','blocked')`,
    // the BEFORE trigger fires ahead of the NOT NULL constraint and names the step, which is
    // the more useful refusal of the two
    expect: /accountable to .{0,2}<NULL>|null value in column .accountable_role_id|not-null/i,
  },
  {
    name: 'two owners for one step',
    why: 'step_id is the primary key, so a second accountable owner needs a second row',
    sql: `insert into public.phase_b_workflow_step
            (step_id, workflow_id, step_no, step_name, step_type, accountable_role_id,
             package_accountable_token, actor_kind, entry_condition, required_inputs,
             required_action, required_output, acceptance_criteria, closure_criteria,
             failure_or_block_state, idempotency_scope, next_step_if_pass, next_step_if_fail,
             success_workflow_state, failure_workflow_state)
          select step_id, workflow_id, 901, 'x','analysis','ceo','ceo','canonical_role','x','x','x','x','x','x',
                 'blocked','x','WORKFLOW_COMPLETE','WORKFLOW_BLOCKED','completed','blocked'
            from public.phase_b_workflow_step where step_id = 'W01-S01'`,
    expect: /duplicate key value|phase_b_workflow_step_pkey/i,
  },
  {
    name: 'unknown owner',
    why: 'an owner addressed to a name nobody models is the defect this estate repeats most',
    sql: `update public.phase_b_workflow_step
             set accountable_role_id = 'head_of_vibes' where step_id = 'W01-S02'`,
    expect: /does not resolve to an active canonical role/i,
  },
  {
    name: 'inactive owner',
    why: 'a retired role cannot own current work',
    sql: mustAffect(`update public.phase_b_workflow_step
             set accountable_role_id = (select role_id from public.org_role where status <> 'active' order by role_id limit 1)
           where step_id = 'W01-S02'`),
    expect: /does not resolve to an active canonical role|store the canonical role_id/i,
  },
  {
    name: 'alias stored instead of canonical id',
    why: 'two spellings of one employee must not become two identities in the registry',
    sql: mustAffect(`update public.phase_b_workflow_step
             set accountable_role_id = 'payments_billing_manager' where step_id = '${ids.w16_payment_step}'`),
    expect: /store the canonical role_id/i,
  },
  {
    name: 'unknown next step',
    why: 'a step pointing at a target that does not exist is an unreachable branch',
    sql: `${mustAffect(`update public.phase_b_workflow_step
             set next_step_if_pass = 'W01-S99' where step_id = 'W01-S01'`)}
          do $$ declare n bigint; begin
            select count(*) into n from public.phase_b_workflow_step s
             where s.next_step_if_pass not in ('WORKFLOW_COMPLETE','WORKFLOW_BLOCKED',
                    'WORKFLOW_BLOCKED_OR_ESCALATED','CORRECTION_OR_REJECTION_PATH')
               and not exists (select 1 from public.phase_b_workflow_step t where t.step_id = s.next_step_if_pass);
            if n = 0 then raise exception 'GUARD DID NOT DETECT the dangling next_step reference'; end if;
            raise exception 'DETECTED % dangling next_step reference(s)', n;
          end $$;`,
    expect: /DETECTED \d+ dangling next_step reference/i,
  },
  {
    name: 'invalid state transition',
    why: 'only declared transitions are permitted',
    sql: `do $$ begin
            if public.fn_phase_b_transition_allowed('completed','active') then
              raise exception 'GUARD FAILED: completed -> active was accepted';
            end if;
            raise exception 'REFUSED completed -> active as undeclared';
          end $$;`,
    expect: /REFUSED completed -> active/i,
  },
  {
    name: 'creator is own reviewer',
    why: 'independent review requires different effective identities, not different spellings',
    sql: mustAffect(`update public.phase_b_workflow_step
             set independent_reviewer_role_id = accountable_role_id where step_id = '${ids.reviewed_step}'`),
    expect: /phase_b_step_creator_not_reviewer/i,
  },
  {
    name: 'creator/reviewer alias collision',
    why: 'the same employee under two names must still collide',
    sql: `update public.phase_b_workflow_step
             set independent_reviewer_role_id = 'risk_governance_manager'
           where step_id = (select step_id from public.phase_b_workflow_step
                             where accountable_role_id = 'risk_and_governance_manager' order by step_id limit 1);
          do $$ declare n bigint; begin
            select count(*) into n from public.phase_b_workflow_step
             where independent_reviewer_role_id is not null
               and public.fn_phase_b_resolve_role(independent_reviewer_role_id)
                 = public.fn_phase_b_resolve_role(accountable_role_id);
            if n = 0 then raise exception 'GUARD DID NOT DETECT the alias collision'; end if;
            raise exception 'DETECTED % alias collision(s)', n;
          end $$;`,
    expect: /DETECTED \d+ alias collision/i,
  },
  {
    name: 'category overlay granted dispatch authority',
    why: 'an overlay may never dispatch, approve a supplier, reveal identity or decide money',
    sql: mustAffect(`update public.phase_b_workflow_step
             set actor_kind = 'category_overlay', accountable_role_id = 'relevant_category_overlay'
           where step_id = '${ids.w12_step}'`),
    expect: /category overlay cannot be accountable in W12/i,
  },
  {
    name: 'category overlay owning a decision step in its own scope',
    why: 'inside W05..W14 the overlay may own an analysis step only',
    sql: mustAffect(`update public.phase_b_workflow_step
             set actor_kind = 'category_overlay', accountable_role_id = 'relevant_category_overlay'
           where step_id = '${ids.w14_decision}'`),
    expect: /may own an analysis step only/i,
  },
  {
    name: 'handoff naming a party who does not own the step',
    why: 'a handoff contract that misnames its parties cannot be accepted by anyone',
    sql: mustAffect(`update public.phase_b_handoff set sending_role_id = 'ceo'
                      where handoff_id = '${ids.w12_handoff}'`),
    expect: /says sender ceo but step .* is owned by/i,
  },
  {
    name: 'handoff to itself',
    why: 'a handoff whose sender is its receiver is not a handoff',
    sql: mustAffect(`update public.phase_b_handoff
             set receiving_role_id = sending_role_id where handoff_id = '${ids.w12_handoff}'`),
    expect: /phase_b_handoff_two_parties|says receiver/i,
  },
  {
    name: 'owner change with no handoff contract',
    why: 'every owner-to-owner transition needs a contract, not a message',
    sql: `${mustAffect(`delete from public.phase_b_handoff where handoff_id = '${ids.w12_handoff}'`)}
          do $$ declare n bigint; begin
            select count(*) into n from public.phase_b_workflow_step s
              join public.phase_b_workflow_step t on t.step_id = s.next_step_if_pass
             where s.accountable_role_id <> t.accountable_role_id
               and not exists (select 1 from public.phase_b_handoff h
                                where h.from_step_id = s.step_id and h.to_step_id = t.step_id);
            if n = 0 then raise exception 'GUARD DID NOT DETECT the missing handoff'; end if;
            raise exception 'DETECTED % owner change(s) with no contract', n;
          end $$;`,
    expect: /DETECTED \d+ owner change\(s\) with no contract/i,
  },
  {
    name: 'exception escalating to its own detector',
    why: 'escalating to the identity that raised it is not a second pair of eyes',
    sql: mustAffect(`update public.phase_b_exception
             set escalation_owner_role_id = detection_owner_role_id
           where exception_id = '${ids.any_exception}'`),
    expect: /phase_b_exception_independent_escalation/i,
  },
  {
    name: 'missing founder gate',
    why: 'a founder-reserved decision must not be reachable without a founder gate',
    sql: `${mustAffect(`update public.phase_b_workflow_step set founder_gate = 'none'
           where founder_gate is not null and lower(founder_gate) <> 'none'`)}
          do $$ declare n bigint; begin
            select count(*) into n from public.fn_phase_b_invariants()
             where check_name = 'authority.founder_boundary_without_any_gate' and not ok;
            if n = 0 then raise exception 'GUARD DID NOT DETECT the removed founder gates'; end if;
            raise exception 'DETECTED founder boundaries with no gate';
          end $$;`,
    expect: /DETECTED founder boundaries with no gate/i,
  },
  {
    name: 'completed workflow with an open blocker',
    why: 'closure must be impossible while anything mandatory is open',
    sql: `do $$ declare n bigint; begin
            select count(*) into n from public.fn_phase_b_closure_blockers(
              'W12',
              (select array_agg(step_id) from public.phase_b_workflow_step where workflow_id = 'W12'),
              1::bigint, 0::bigint);
            if n = 0 then raise exception 'GUARD FAILED: closure allowed with an open blocker'; end if;
            raise exception 'REFUSED closure: % blocker reason(s)', n;
          end $$;`,
    expect: /REFUSED closure: \d+ blocker reason/i,
  },
  {
    name: 'closure with a mandatory step incomplete',
    why: 'every mandatory step must be completed or validly skipped',
    sql: `do $$ declare n bigint; begin
            select count(*) into n from public.fn_phase_b_closure_blockers(
              'W12', array['W12-S01']::text[], 0::bigint, 0::bigint);
            if n = 0 then raise exception 'GUARD FAILED: closure allowed with steps outstanding'; end if;
            raise exception 'REFUSED closure: % incomplete step(s)', n;
          end $$;`,
    expect: /REFUSED closure: \d+ incomplete step/i,
  },
];

const before = (await sql(`select
    (select count(*) from public.phase_b_workflow_step) steps,
    (select count(*) from public.phase_b_handoff) handoffs,
    (select count(*) from public.phase_b_exception) exceptions`))[0];

let pass = 0;
const failures = [];
for (const c of CASES) {
  // Every case runs inside a transaction that always ends in ROLLBACK, so a case that
  // unexpectedly SUCCEEDS still leaves nothing behind.
  const body = `begin;\n${c.sql};\n`
    + `do $verify$ begin raise exception 'NOT REFUSED: %', ${JSON.stringify(c.name).replace(/^"|"$/g, "'")}; end $verify$;\nrollback;`;
  let err = null;
  try { await sql(body); } catch (e) { err = String(e.message); }
  await sql('rollback;').catch(() => {});

  if (!err) { failures.push(`${c.name}: no error at all — the defect was ACCEPTED`); continue; }
  if (/NOT REFUSED/.test(err)) { failures.push(`${c.name}: injected defect was ACCEPTED (${c.why})`); continue; }
  if (!c.expect.test(err)) {
    failures.push(`${c.name}: refused, but not for the expected reason.\n    got: ${err.slice(0, 300)}`);
    continue;
  }
  pass++;
  console.log(`PASS  ${c.name.padEnd(48)} ${c.why}`);
}

const after = (await sql(`select
    (select count(*) from public.phase_b_workflow_step) steps,
    (select count(*) from public.phase_b_handoff) handoffs,
    (select count(*) from public.phase_b_exception) exceptions`))[0];

console.log(`\n${pass}/${CASES.length} guards fired.`);
for (const f of failures) console.log(`FAIL  ${f}`);

if (JSON.stringify(before) !== JSON.stringify(after)) {
  console.log(`FAIL  the test changed the database: ${JSON.stringify(before)} -> ${JSON.stringify(after)}`);
  process.exit(1);
}
console.log(`row counts unchanged: ${JSON.stringify(after)}`);
process.exit(failures.length === 0 ? 0 : 1);
