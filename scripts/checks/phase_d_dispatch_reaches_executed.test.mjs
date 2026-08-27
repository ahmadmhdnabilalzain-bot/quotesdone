// THE PHASE D POSITIVE CONTROL: a handler must be able to reach EXECUTED through the real kernel
// path, in production execution context, and leave a row in phase_d_effect_ledger.
//
// Phase D's deliverable is 257 deterministic business handlers that the estate executes. For the
// whole of its build, `phase_d_dispatch` recorded zero EXECUTED and `phase_d_effect_ledger` held
// zero rows, and two independent acceptance audits said so. A board check that counts committed
// effects cannot tell "the capability is broken" from "nothing has arrived to exercise it" — the
// number is 0 either way. This test is the difference: it DRIVES the path and asserts the outcome.
//
// It runs in ONE ABORTED TRANSACTION. Nothing it writes survives, `fn_phase_d_fixture_residue()` is
// asserted 0 inside the same transaction, and every business table it could touch is asserted
// unchanged. That is deliberate: proving the capability must not manufacture the committed row
// whose absence the board reports.
//
// Boundary, stated rather than implied. What is asserted here is that the dispatch REACHES the
// handler and the handler PRODUCES an effect for steps whose declared effect needs no
// caller-supplied business key. It is NOT a claim that all 257 steps execute — 185 of them write a
// business object and refuse without a business_key and owner_ref that only a caller can supply,
// which is the behaviour `fn_phase_d_effect_produce` was written to have, and 21 more are held
// closed by the capability boundary while paid inference waits for Phase E.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

// A CHECK THAT CANNOT RUN MUST SAY SO, AND MUST NOT THROW. This file needs the Supabase management
// credential. The tokenless `checks` workflow runs `npm test` with no env block, and reading the
// token file unconditionally made this an ENOENT hard failure there rather than a declared skip.
//
// node:test's own skip, never a top-level process.exit(0) — a file that registers zero tests reads
// as success to a runner, which is how a check goes quiet without anyone noticing.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
// The exact string .github/workflows/project-parity.yml greps for. node:test prints a skip as
// `﹣ name # SKIPPED: reason`, which that grep does not match, so a file that skipped inside the one
// CI job holding the credential would read as a pass. Printing this makes the skip visible to the
// gate as well as to a human.
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');


const token = () => (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8')).trim();
const REF = 'htdblwldjkcgjvmqkbeh';

// The management endpoint has no transaction handle, so the abort is expressed the only way it can
// be: the whole drive lives inside a DO block that always raises, and the result travels out in the
// exception message. A green run that did NOT raise would mean the block never reached its report.
async function drive(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const body = await r.text();
  const m = body.match(/PD_DRIVE_RESULT (\{[\s\S]*?\})\\nCONTEXT/);
  assert.ok(m, `the drive did not reach its report. Raw response:\n${body.slice(0, 1500)}`);
  return JSON.parse(m[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\'));
}

// Drives every workflow the frozen registry declares, through fn_kernel_workflow_start,
// fn_kernel_step_complete, fn_kernel_handoff_accept and fn_kernel_review_decide — the canonical
// doors, none of them re-implemented here. Phase D is dispatched by the kernel openers, not by this
// script: the script only supplies what an actor supplies.
const DRIVE = `
do $$
declare
  v jsonb; run bigint; sr record; hnd bigint; recv text; i int; v_wf text;
  v_rev text; tsk bigint;
  n_before_cost bigint; n_before_cron bigint;
begin
  select count(*) into n_before_cost from public.ai_cost_log;
  select count(*) into n_before_cron from cron.job where active;

  for v_wf in select workflow_id from public.phase_b_workflow order by workflow_id loop
    begin
      v := public.fn_kernel_workflow_start(jsonb_build_object(
        'workflow_id', v_wf, 'business_object_id', 'zz-phase-d-drive-' || v_wf,
        'source_kind','autonomous', 'source_ref','phase-d-positive-control',
        'requested_by','phase-d-positive-control'));
      run := (v->>'run_id')::bigint;
    exception when others then continue;
    end;

    for i in 1..16 loop
      select sr2.step_run_id, sr2.step_id, sr2.accountable_role_id into sr
        from public.phase_c_workflow_step_run sr2
       where sr2.run_id = run and sr2.state = 'active'
       order by sr2.step_run_id limit 1;
      exit when sr.step_run_id is null;

      -- A step that names an independent reviewer needs that reviewer's approved verdict before
      -- the kernel will accept its completion. That is a kernel rule and it is honoured through
      -- the kernel's own door, never bypassed.
      select s.independent_reviewer_role_id into v_rev
        from public.phase_b_workflow_step s where s.step_id = sr.step_id;
      if coalesce(btrim(coalesce(v_rev,'')),'') <> '' then
        select t.task_id into tsk from public.phase_c_task t
         where t.run_id = run and t.step_id = sr.step_id order by t.task_id desc limit 1;
        if tsk is not null then
          begin
            perform public.fn_kernel_review_decide(jsonb_build_object(
              'task_id', tsk, 'reviewer_role_id', v_rev, 'decision','approved',
              'reason','phase-d positive control: an independent reviewer approves'));
          exception when others then null;
          end;
        end if;
      end if;

      begin
        perform public.fn_kernel_step_complete(jsonb_build_object(
          'step_run_id', sr.step_run_id, 'actor_role_id', sr.accountable_role_id, 'outcome','pass',
          'idempotency_key','zz-phase-d-drive-' || v_wf || '-' || sr.step_run_id,
          'inputs', jsonb_build_object('note','phase-d positive control'),
          'output', jsonb_build_object('status','completed','output','phase-d positive control'),
          'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
          'requested_action','proceed','acceptance_criteria','phase-d positive control',
          'object_version', 1));
      exception when others then exit;
      end;

      select h.handoff_run_id, h.receiving_role_id into hnd, recv
        from public.phase_c_handoff_run h where h.run_id = run and h.status = 'open' limit 1;
      if hnd is not null then
        begin
          perform public.fn_kernel_handoff_accept(jsonb_build_object(
            'handoff_run_id', hnd, 'actor_role_id', recv, 'decision','accept','outcome','accept',
            'reason','phase-d positive control', 'packet', jsonb_build_object(
              'object_version',1,'output','phase-d positive control',
              'business_object_id','zz-phase-d-drive-' || v_wf,
              'acceptance_evidence','phase-d positive control','unresolved_blockers','none',
              'requested_action','proceed',
              'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)))));
        exception when others then exit;
        end;
      end if;
    end loop;
  end loop;

  raise exception 'PD_DRIVE_RESULT %', (select jsonb_build_object(
    'dispatch_rows',   (select count(*) from public.phase_d_dispatch),
    'executed',        (select count(*) from public.phase_d_dispatch where outcome = 'EXECUTED'),
    'executed_steps',  (select coalesce(jsonb_agg(distinct step_id), '[]'::jsonb)
                          from public.phase_d_dispatch where outcome = 'EXECUTED'),
    'ledger_rows',     (select count(*) from public.phase_d_effect_ledger),
    'production_ctx',  (select count(*) from public.phase_d_dispatch d
                          join public.phase_d_effect_ledger el on el.step_run_id = d.step_run_id
                         where d.outcome = 'EXECUTED'),
    'residue',         (select count(*) from public.fn_phase_d_fixture_residue()),
    'customers',       (select count(*) from public.customers),
    'inquiries',       (select count(*) from public.inquiries),
    'quotes',          (select count(*) from public.quotes),
    'transactions',    (select count(*) from public.transactions),
    'cost_rows_delta', (select count(*) from public.ai_cost_log) - n_before_cost,
    'active_cron_delta', (select count(*) from cron.job where active) - n_before_cron
  ));
end $$;`;

test('a Phase D handler reaches EXECUTED through the kernel path and produces an effect', { skip: SKIP }, async () => {
  const r = await drive(DRIVE);

  assert.ok(Number(r.dispatch_rows) > 0,
    'the kernel openers dispatched nothing at all — Phase D is not wired into the kernel');

  assert.ok(Number(r.executed) >= 1,
    `no step reached EXECUTED in ${r.dispatch_rows} dispatches. Phase D's deliverable is handlers ` +
    `the estate executes; a dispatch that only ever refuses has not been shown to work. ` +
    `Executed steps: ${JSON.stringify(r.executed_steps)}`);

  assert.ok(Number(r.ledger_rows) >= 1,
    'a step reported EXECUTED but phase_d_effect_ledger holds no row — the outcome column moved ' +
    'without an effect behind it, which is the shape this estate has been caught by before');

  assert.equal(Number(r.ledger_rows), Number(r.executed),
    `${r.executed} steps EXECUTED but ${r.ledger_rows} effect ledger rows exist; every executed ` +
    'dispatch must have produced exactly one effect');
});

test('the drive leaves no residue and touches no business table or paid provider', { skip: SKIP }, async () => {
  const r = await drive(DRIVE);

  assert.equal(Number(r.residue), 0,
    'fn_phase_d_fixture_residue() is non-zero INSIDE the drive: the probe wrote a fixture into a ' +
    'business relation. It would have rolled back, but the write path is wrong.');

  for (const t of ['customers', 'inquiries', 'quotes', 'transactions']) {
    assert.equal(Number(r[t]), 0,
      `public.${t} holds ${r[t]} rows during the drive; the zero-residue business tables must stay ` +
      'at zero, including inside an aborted transaction');
  }

  assert.equal(Number(r.cost_rows_delta), 0,
    'the drive added rows to ai_cost_log — a handler reached a paid provider. The capability ' +
    'boundary must fail closed on any execution_context other than test.');

  assert.equal(Number(r.active_cron_delta), 0,
    'the drive changed the number of active cron jobs; the automation hold must survive it');
});

test('nothing the drive did was committed', { skip: SKIP }, async () => {
  // Read AFTER the aborted transactions above. The committed counts are the subject here, and the
  // assertion is deliberately "unchanged", not "zero" — if a future committed arrival legitimately
  // produces effects, this test must fail loudly and be re-read by a person, not silently pass.
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: `select
      -- 27 AUG 2026 — "a real arrival has now driven the estate", which is the case the sentence
      -- below anticipated, and it has been read.
      --
      -- public.phase_d_dispatch is an APPEND-ONLY audit of every dispatch the kernel attempted. It
      -- read 0 only because nothing had committed one. 'a_phone_cannot_select_an_account.test.mjs'
      -- commits two customers on production every run — the one check in this estate that cannot be
      -- made rollback-safe, because the guard it exercises lives in the login_otp edge function,
      -- which connects on its own session and cannot see an uncommitted transaction; that file
      -- argues the trade-off at length. Each INSERT fires z50_customer_registered_kernel_emit, which
      -- opens a W04 run, which dispatches W04-S01. So the suite adds two rows here per run, and its
      -- 'finally' deletes the customers — which since 27 Aug cancels those runs through
      -- a00_kernel_parent_delete_guard instead of orphaning them, which is how the eight orphaned
      -- W04 runs of 26 Aug were made.
      --
      -- A dispatch that was ATTEMPTED and REFUSED, on a run that was then cancelled, is history. A
      -- dispatch that reached EXECUTED is an effect, and an effect from an aborted probe is the
      -- residue this test exists to catch. That distinction is what is counted now; the total is
      -- reported beside it so the growth is visible rather than asserted away.
      (select count(*) from public.phase_d_dispatch) as dispatch_total,
      (select count(*) from public.phase_d_dispatch where outcome <> 'REFUSED') as dispatch_not_refused,
      (select count(*) from public.phase_d_effect_ledger) as ledger,
      (select count(*) from public.fn_phase_d_fixture_residue()) as residue;` }),
  }).then(x => x.json());
  const row = Array.isArray(r) ? r[0] : r;

  assert.equal(Number(row.residue), 0, 'the drive left fixture residue behind');
  console.log(`      public.phase_d_dispatch: ${row.dispatch_total} committed row(s), `
    + `${row.dispatch_not_refused} of them not REFUSED`);
  assert.equal(Number(row.dispatch_not_refused), 0,
    `public.phase_d_dispatch holds ${row.dispatch_not_refused} committed row(s) that are not ` +
    'REFUSED, out of ' + row.dispatch_total + '. A dispatch that reached the handler and was not ' +
    'refused produced or attempted an effect; committed, that is residue from a drive that should ' +
    'have rolled back. Read the rows before changing this line.');
  assert.equal(Number(row.ledger), 0,
    `public.phase_d_effect_ledger holds ${row.ledger} committed rows — see the note above.`);
});
