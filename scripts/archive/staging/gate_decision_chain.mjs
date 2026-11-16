// gate_decision_chain.mjs — runs the ten-step decision chain END TO END on PRODUCTION and reads
// the effect back. Deploying fn_decide is not evidence that the chain runs; this is.
//
//   node scripts/archive/staging/gate_decision_chain.mjs
//
// Two traps this file is shaped around:
//
//  * ONE STATEMENT SHARES ONE SNAPSHOT. Calling fn_decide and counting its rows in the same
//    statement returns the PRE-call state and reports a working chain as 0/0. Every assertion here
//    is therefore posted as its OWN request, after the call has committed.
//  * A DO BLOCK THAT REWRITES pg_get_functiondef REPORTS SUCCESS FOR A BODY THAT CANNOT RUN. So
//    nothing here inspects a definition: it invokes the function against real rows.
//
// The gate-refusal probe runs inside a transaction that is ROLLED BACK. trg_decision_gate has to
// be shown REFUSING, and the only way to make it refuse is to hand it an unanalysed approval —
// which must not be left behind in production's ledger afterwards.
//
// NOT IDEMPOTENT, DELIBERATELY. Each run takes two REAL decisions and so adds two decision_record
// rows. That is the point — the chain is proved by running it, not by inspecting it — but it means
// this belongs in a hand or a CI step, never in a loop or a cron.
import { supabaseAccessToken } from '../../lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { PROD_REF } from '../../lib/qd_guard.mjs';

const token = supabaseAccessToken();

async function sql(q, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: q }),
  });
  const b = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 7) {
    const wait = Math.min(2000 * 2 ** attempt, 60000);
    console.log(`  ${r.status}; retrying in ${wait / 1000}s (attempt ${attempt + 1}/7)`);
    await new Promise(res => setTimeout(res, wait));
    return sql(q, attempt + 1);
  }
  if (!r.ok) throw new Error(`management API ${r.status}: ${b.slice(0, 400)}`);
  return b ? JSON.parse(b) : null;
}
const one = async (q) => { const r = await sql(q); return r && r[0] ? Object.values(r[0])[0] : null; };

let bad = 0;
const check = (label, ok, detail) => {
  if (!ok) bad++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label.padEnd(46)} ${detail}`);
};

// ---------------------------------------------------------------- 1. run two real decisions
// Real questions, not fixtures: which agent owns signage work, and which approved suppliers to
// invite for flooring. Both are decisions this company actually has to take.
// The watermark makes a re-run measure ITS OWN rows: filtering on a time window instead would
// count the previous run's decisions too and drift the assertions on every repeat.
const logMark = await one(`select coalesce(max(id),0)::text from public.decision_log`);

const r1 = await one(`select public.fn_decide('route_category',
  jsonb_build_object('category','signage','dept_key','operations',
    'question','Which agent owns Printing / Packaging / Signage work when an RFQ arrives?'),
  'operations_ai')::text`);
console.log('\ndecision 1 (route_category/signage):\n  ' + String(r1).slice(0, 400) + '\n');

const r2 = await one(`select public.fn_decide('invite',
  jsonb_build_object('category','flooring','n',5,'dept_key','operations',
    'question','Which approved flooring suppliers should be invited to quote first?'),
  'operations_ai')::text`);
console.log('decision 2 (invite/flooring):\n  ' + String(r2).slice(0, 400) + '\n');

const decs = [JSON.parse(r1), JSON.parse(r2)];
const ids = decs.map(d => d.decision_record_id).filter(Boolean);
check('fn_decide wrote a decision_record', ids.length === 2, `ids=${ids.join(',')}`);

// A decision the engine is not authorised to take must NOT reach the gate — it stays 'proposed'
// for a person. So the expected gate/execution counts come from what the engine decided, not from
// an assumption that everything is autonomous. On the first production run decision 2 escalated
// because production has zero approved flooring suppliers: confidence 0.2, correctly withheld.
const passed = decs.filter(d => d.gate_verdict === 'passed').length;
check('at least one decision cleared the gate', passed > 0,
  decs.map(d => `#${d.decision_record_id} ${d.status}/${d.gate_verdict || '(not gated)'}`).join(', '));

// ---------------------------------------------------------------- 2. read the effect back
// SEPARATE STATEMENTS. The rows below were written by the two calls above, which have committed.
const idList = ids.join(',') || '-1';

const step1 = await one(`select 'rows=' || count(*)::text || ' with a stated problem=' ||
  count(*) filter (where length(btrim(problem)) >= 10)::text
  from public.decision_record where id in (${idList})`);
check('step 1  problem captured', /rows=2 .*problem=2/.test(step1), step1);

const step4 = await one(`select 'four impacts + evidence=' || count(*) filter (
    where length(impact_business) >= 20 and length(impact_financial) >= 20
      and length(impact_legal) >= 10 and length(impact_customer) >= 20
      and jsonb_array_length(coalesce(evidence,'[]'::jsonb)) > 0)::text
  || ', gate inspected=' || count(*) filter (where gate_checked_at is not null)::text
  from public.decision_record where id in (${idList})`);
check('step 4  analysis + gate actually ran',
  step4 === `four impacts + evidence=2, gate inspected=${passed}` && passed > 0, step4);

const step6 = await one(`select 'with 2+ scored options=' || count(*) filter (
    where jsonb_typeof(options)='array' and jsonb_array_length(options) >= 2
      and (options->0->>'score') is not null and (options->1->>'score') is not null)::text
  from public.decision_record where id in (${idList})`);
check('step 6  two scored options generated', step6 === 'with 2+ scored options=2', step6);

const step3 = await one(`select 'sourced=' || count(*) filter (
    where jsonb_typeof(sources)='array' and jsonb_array_length(sources) > 0)::text
  || ', citing knowledge/memory=' || count(*) filter (where sources::text ~* '(knowledge|memory|kb_|lesson)')::text
  || ', retrieved hits=' || coalesce(sum((select sum((e->>'hits')::int) from jsonb_array_elements(sources) e
        where e->>'kind'='memory_search'))::text, '0')
  from public.decision_log where id > ${logMark}`);
check('step 3  knowledge retrieval on the log',
  /^sourced=2, citing knowledge\/memory=2, retrieved hits=[1-9]/.test(step3), step3);

const step7 = await one(`select 'gate verdicts=' || string_agg(coalesce(gate_verdict,'(null)')||':'||status, ', ')
  from public.decision_record where id in (${idList})`);
check('step 7  authority gate reached a verdict', /passed:approved/.test(step7), step7);

// Step 9 is the one the blueprint keeps losing: an execution row that cannot be traced back to the
// decision that caused it is not a linked execution. Assert the JOIN, not the two row counts.
const step9 = await one(`select 'linked pairs=' || count(*)::text
  || ', orphan executions=' || (select count(*) from public.v_executions_without_decision_trace)::text
  from public.action_execution a
  join public.decision_trace t on t.correlation_id = a.correlation_id
  where (a.request->>'decision_record_id')::bigint in (${idList})
    and t.entity_type='decision_record' and t.entity_id::bigint in (${idList})`);
check('step 9  execution linked back to decision',
  step9 === `linked pairs=${passed}, orphan executions=0` && passed > 0, step9);

// ---------------------------------------------------------------- 3. the gate must also REFUSE
// A gate that has only ever said yes has not been exercised. Rolled back: production keeps no row.
const refusal = await one(`begin;
with probe as (
  insert into public.decision_record(decided_by, problem, recommendation, status, impact_business)
  values ('gate_probe','Probe: does trg_decision_gate refuse an approval with no impact analysis?',
          'approve without doing the analysis','approved','too short')
  returning status, gate_verdict, left(gate_reason, 90) reason
)
select status || ' / ' || coalesce(gate_verdict,'(null)') || ' / ' || coalesce(reason,'') from probe;
rollback;`);
check('gate refuses an unanalysed approval', /^blocked_by_gate \/ refused \//.test(String(refusal)), refusal);

const residue = await one(`select count(*)::text from public.decision_record where decided_by='gate_probe'`);
check('refusal probe left no residue', residue === '0', `gate_probe rows=${residue}`);

// ---------------------------------------------------------------- 4. the producer exists at all
const writer = await one(`select count(*)::text from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='public' and p.prokind in ('f','p')
    and pg_get_functiondef(p.oid) ~* ('(inser'||'t|upda'||'te)\\s+(into\\s+)?(public\\.)?decision_record\\y')`);
check('a routine writes decision_record', Number(writer) > 0, `${writer} routine(s)`);

console.log(`\n${bad ? `${bad} CHECK(S) FAILED` : 'decision chain runs end to end on production'}`);
process.exit(bad ? 1 : 0);
