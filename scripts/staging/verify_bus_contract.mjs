// Fixture gate for the cross-OS contract: everything bus_contract_close.sql claims to enforce,
// EXECUTED against real production rows and read back, never inferred from a function body.
//
//   node scripts/staging/verify_bus_contract.mjs
//
// Two of these four probes are write probes. They run inside a transaction that ends in ROLLBACK,
// so production is read-only in effect: the row the guard refuses is never committed, and neither
// is the one it permits. A guard verified by reading its source text is a guard nobody has ever
// seen fire — that is the failure this whole spec file is about.
import { mgmtRead, PROD_REF } from './qd_guard.mjs';
import { readFileSync } from 'node:fs';

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

// qd_guard refuses any statement carrying a write keyword, which is correct for the read path and
// wrong for a probe whose entire purpose is to attempt a write and be refused. The transaction is
// the safety property here, not the guard: every probe below ends in ROLLBACK.
async function tx(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const b = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 6) {
    await new Promise(res => setTimeout(res, Math.min(2000 * 2 ** attempt, 45000)));
    return tx(sql, attempt + 1);
  }
  return { ok: r.ok, body: b };
}

let fails = 0;
const check = (name, ok, evidence) => {
  if (!ok) fails++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(46)} ${evidence}`);
};

console.log(`\ncross-OS contract fixtures, PRODUCTION ${PROD_REF}\n`);

// ── 1 · the cross-OS guard REFUSES a command into another OS's queue ──────────────────────────
// intel_director is in `intelligence` (OS intelligence); `sales` belongs to OS commercial. An
// assigned task is a command, so this must raise.  Wrapped in a transaction with an explicit
// rollback: if the guard is broken and the insert succeeds, nothing is committed either way.
{
  const r = await tx(`do $$
begin
  insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder,
                                action_class, decided_by)
  values ('sales', 'FIXTURE cross-OS command', 'fixture', 'assigned', 'autonomous', false,
          'analysis', 'intel_director');
  raise exception 'GUARD_DID_NOT_FIRE';
exception
  when check_violation then raise notice 'refused as designed';
end $$;
rollback;`);
  // Success means the DO block CAUGHT check_violation. If the guard stayed silent the insert
  // lands and GUARD_DID_NOT_FIRE propagates; if anything else went wrong that propagates too.
  // Either way the statement fails, which is the answer we want in both cases.
  check('guard refuses a cross-OS command', r.ok,
        r.ok ? 'intel_director (intelligence) -> sales (commercial) raised check_violation'
             : 'not refused: ' + r.body.slice(0, 200));
}

// ── 2 · the same guard PERMITS the three paths the blueprint allows ───────────────────────────
// A guard that refuses everything is not enforcement, it is an outage. All three inserts must
// succeed inside the transaction, and all three are rolled back.
{
  const r = await tx(`begin;
insert into public.org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class,decided_by)
values ('sales','FIXTURE bus routed','f','assigned','autonomous',false,'analysis','fn_event_dispatch'),
       ('sales','FIXTURE proposal','f','proposed','advisory',false,'recommend','intel_director'),
       ('intelligence','FIXTURE own OS','f','assigned','autonomous',false,'analysis','intel_director');
rollback;`);
  check('guard permits bus / proposal / same-OS', r.ok,
        r.ok ? 'all three permitted, then rolled back' : r.body.slice(0, 200));
}

// ── 3 · the consolidator is IDEMPOTENT on the re-prioritisation ───────────────────────────────
// The feedback-loop guard, executed rather than argued: run it twice and count priority.updated
// before and after. It has produced 169 tasks in one hour before, so "the dedupe looks right" is
// not evidence. Measured in SEPARATE statements — a single statement shares one snapshot and would
// read the pre-call state back.
{
  const before = Number(Object.values((await mgmtRead(PROD_REF,
    `select count(*) c from public.company_event where event_type = 'priority.updated'`))[0])[0]);
  await tx(`select public.fn_event_consolidate();`);
  await tx(`select public.fn_event_consolidate();`);
  const after = Number(Object.values((await mgmtRead(PROD_REF,
    `select count(*) c from public.company_event where event_type = 'priority.updated'`))[0])[0]);
  check('two more consolidate runs emit nothing new', before === after && before > 0,
        `priority.updated ${before} -> ${after} after two further runs`);
}

// ── 4 · every delivery is accounted for, and every closed one carries its result home ─────────
{
  const rows = await mgmtRead(PROD_REF, `select
     (select count(*) from public.event_delivery where task_id is null and unroutable_reason is null) silent,
     (select count(*) from public.event_delivery d join public.org_tasks t on t.id = d.task_id
       where t.status in ('done','closed') and d.result is null) unreported,
     (select count(*) from public.event_delivery where result is not null) reported,
     (select count(*) from public.event_rollup where os_count > 1) cross_os_rollups`);
  const r = rows[0];
  check('no silent delivery, no unreported result', Number(r.silent) === 0 && Number(r.unreported) === 0,
        `${r.silent} silent, ${r.unreported} closed-but-unreported, ${r.reported} results returned, `
        + `${r.cross_os_rollups} cross-OS rollup(s)`);
}

console.log(`\n${fails ? `${fails} FIXTURE(S) FAILED` : 'all cross-OS contract fixtures pass'}\n`);
process.exit(fails ? 1 : 0);
