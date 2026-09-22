// PROBE — the Sales Engineer's assist floor and its portal report, against PRODUCTION.
//
// Every assertion here is about behaviour that would otherwise be a claim. In particular:
//   * a NONSENSE question must be REFUSED. An unfiltered vector search always finds a nearest
//     neighbour, so "it answered a real question" proves nothing on its own.
//   * a REAL question must be ANSWERED and must name the records it cited.
//   * POSITIVE CONTROL first: the knowledge body must actually hold rows, or the refusal above is
//     proved by an empty table rather than by the floor.
//   * the report runs on the ONE real customer, and on a SYNTHETIC supplier seeded inside a
//     transaction that is then rolled back by raising CHK<<...>>, so production gains no row and
//     the numbers still surface.
import { readFileSync } from 'node:fs';

const REF = 'htdblwldjkcgjvmqkbeh';
const token = (process.env.SUPABASE_ACCESS_TOKEN || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

// The management API rate-limits hard after a heavy session; a 429 between two assertions would
// report a FAIL that is about the transport, not about the subject.
async function sql(query, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const t = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 6) {
    await new Promise((s) => setTimeout(s, 2000 * (attempt + 1)));
    return sql(query, attempt + 1);
  }
  if (!r.ok) return { error: t };
  return { rows: JSON.parse(t) };
}

const one = async (q) => (await sql(q)).rows?.[0];

const secrets = (await sql(`select key, value from app_secrets where key in ('cred_fn_sales_engineer','anon_key')`)).rows;
const S = Object.fromEntries(secrets.map((r) => [r.key, r.value]));
const FN = `https://${REF}.supabase.co/functions/v1/sales_engineer`;

async function call(body) {
  const r = await fetch(FN, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + S.anon_key },
    body: JSON.stringify({ ...body, __secret: S.cred_fn_sales_engineer }),
  });
  return { status: r.status, json: await r.json().catch(() => null) };
}

let fails = 0;
const check = (name, ok, detail) => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail === undefined ? '' : '  — ' + detail}`);
  if (!ok) fails++;
};

// ── 0. POSITIVE CONTROLS ──────────────────────────────────────────────────────────────────────
const ctl = await one(`select
  (select count(*) from sales_knowledge) k,
  (select count(*) from sales_knowledge where embedding_gte is not null) e,
  (select count(*) from customers) c`);
console.log('\n-- POSITIVE CONTROL --');
console.log(ctl);
check('sales_knowledge holds rows', Number(ctl.k) > 0, `${ctl.k} records`);
check('every record is embedded', Number(ctl.e) === Number(ctl.k), `${ctl.e}/${ctl.k}`);
check('the one real customer exists', Number(ctl.c) === 1, `${ctl.c}`);

// ── 1. THE FLOOR ──────────────────────────────────────────────────────────────────────────────
console.log('\n-- ASSIST: NONSENSE MUST BE REFUSED --');
const nonsense = await call({ action: 'assist', message: 'zorblax quantum flibbertigibbet moonbeam turnip parade' });
console.log(JSON.stringify({ status: nonsense.status, answered: nonsense.json?.answered, refusal: nonsense.json?.refusal, cited: nonsense.json?.cited, reply: nonsense.json?.reply }, null, 2));
check('nonsense is not answered', nonsense.json?.answered === false, 'refusal=' + nonsense.json?.refusal);
check('nonsense cites nothing', (nonsense.json?.cited || []).length === 0);
// 9 Sep: the founder rejected the old refusal string outright — "that reply with 'i dont have
// that...' should never happen". The fall-through is now an ACTION, so the assertion is that the
// reply names a real task, not that it apologises.
check('nonsense opens a task instead of refusing', Number.isFinite(Number(nonsense.json?.task_id)),
  'task_id=' + nonsense.json?.task_id);
check('the reply names the task and its owner',
  /task #\d+/.test(String(nonsense.json?.reply || '')) && /Sales Engineer/.test(String(nonsense.json?.reply || '')));

console.log('\n-- ASSIST: A REAL QUESTION MUST BE ANSWERED AND CITED --');
const QREAL = 'what documents does a supplier need for verification';
const real = await call({ action: 'assist', message: QREAL });
console.log(JSON.stringify({ answered: real.json?.answered, cited: real.json?.cited, floor: real.json?.floor }, null, 2));
check('real question is answered', real.json?.answered === true);
check('real question cites records', (real.json?.cited || []).length > 0, (real.json?.cited || []).join(', '));
check('the reply carries content', String(real.json?.reply || '').length > 100, String(real.json?.reply || '').length + ' chars');
// The candidate list is deliberately NOT in the customer-facing reply — a portal caller has no
// business seeing the record ids we rejected. It is read back from the decision log instead, which
// is where the build prompt asked for it.
check('the reply does not leak rejected candidates', real.json?.candidates === undefined);

// THE FLOOR IS THE CAUSE, NOT A COINCIDENCE. Raise it above the best hit and the same question,
// same records, same index must now be refused. Without this the "nonsense was refused" result is
// consistent with a floor that never fires.
// There are TWO admission routes since the 9 Sep widening, so there are two things to prove.
// Raising the cosine floor above the best hit must close the VECTOR route — it cannot close the
// lexical-only route, because rows with no embedding were never put to a cosine floor at all and
// pretending otherwise would be the dishonest assertion here.
const bestRow = await one(`select max((c->>'similarity')::numeric) best from sales_decision_log,
  lateral jsonb_array_elements(candidates) c where action='assist' and query like 'what documents%'`);
const best = Number(bestRow.best);
const raisedTo = Math.min(0.999, best + 0.02);
const raised = await call({ action: 'assist', message: QREAL, min_similarity: raisedTo });
// Which route each surviving citation came through is recorded, so this is read rather than
// inferred from the record id — kb_chunks and agent_knowledge both hold embedded AND unembedded
// rows, so the corpus name alone cannot tell you which gate a row passed.
const raisedRoutes = await one(`select
    count(*) filter (where (c->>'cited')::boolean and c->>'route' = 'vector+lexical') via_vector,
    count(*) filter (where (c->>'cited')::boolean and c->>'route' = 'lexical_only')   via_lexical
  from sales_decision_log l, lateral jsonb_array_elements(l.candidates) c
 where l.id = (select max(id) from sales_decision_log where action='assist' and min_similarity = ${raisedTo})`);
check('raising the cosine floor above the best hit closes the vector route',
  Number(raisedRoutes?.via_vector) === 0,
  `best=${best} raised_to=${raisedTo.toFixed(4)} via_vector=${raisedRoutes?.via_vector} via_lexical_only=${raisedRoutes?.via_lexical} (unembedded rows were never subject to a cosine floor)`);
// And the lexical gate is load-bearing on BOTH routes: min_rank raises the corroboration bar for
// embedded rows and, since c_lex_only is greatest(0.20, p_min_rank), the bar for unembedded ones
// too. An unreachable rank must therefore refuse outright.
const lexOff = await call({ action: 'assist', message: QREAL, min_rank: 9 });
check('an unreachable lexical rank refuses the same question on every route',
  lexOff.json?.answered === false, 'refusal=' + lexOff.json?.refusal + ' cited=' + (lexOff.json?.cited || []).join(','));

// ── 2. THE DECISION LOG ───────────────────────────────────────────────────────────────────────
console.log('\n-- DECISION LOG --');
const log = (await sql(`select id, action, left(query,50) q, min_similarity, min_rank, k, answered, refusal,
  jsonb_array_length(candidates) n_candidates, cited
  from sales_decision_log order by id desc limit 5`)).rows;
console.table(log);
check('the log recorded the nonsense refusal', log.some((r) => r.answered === false && /zorblax/.test(r.q || '')));
check('the log recorded the answered query with citations', log.some((r) => r.answered === true && (r.cited || []).length > 0));
check('every logged row carries the floor it applied', log.every((r) => r.action !== 'assist' || r.min_similarity !== null));
check('rejected candidates are kept, not only cited ones',
  log.some((r) => Number(r.n_candidates) > (r.cited || []).length));

// ── 3. THE REPORT ON THE ONE REAL CUSTOMER ────────────────────────────────────────────────────
console.log('\n-- REPORT: the one real customer --');
const cid = (await one(`select id from customers limit 1`)).id;
const custRep = await call({ action: 'report', party_kind: 'customer', party_id: cid });
console.log(JSON.stringify(custRep.json, null, 2));
const cj = custRep.json || {};
check('customer report returns ok', cj.ok === true);
check('total spend is labelled true_zero, not a bare 0', cj.total_spend_aed?.basis === 'true_zero',
  `value=${cj.total_spend_aed?.value} denominator=${cj.total_spend_aed?.denominator}`);
check('inquiries is labelled true_zero', cj.inquiries?.basis === 'true_zero');
check('no supplier performance is invented', Array.isArray(cj.supplier_performance) && cj.supplier_performance.length === 0);

// ── 4. THE REPORT ON A SYNTHETIC SUPPLIER, INSIDE AN ABORTED TRANSACTION ──────────────────────
// The fixture follows the estate's convention (ZZ DEMO / example.invalid) and never commits: the
// block raises CHK<<...>> carrying the report, so Postgres rolls the insert back and the numbers
// still reach this process through the error message.
console.log('\n-- REPORT: a synthetic supplier, rolled back --');
const probe = `
do $probe$
declare v_id bigint; v jsonb; v_before bigint; v_after bigint;
begin
  select count(*) into v_before from leads;
  insert into leads (company_name, rating, claimed)
  values ('ZZ DEMO Sales Engineer Probe', 4.4, false) returning id into v_id;
  select count(*) into v_after from leads;
  -- POSITIVE CONTROL: without this, a report full of zeros could be a report on nothing.
  if v_after <> v_before + 1 then raise exception 'CHK<<fixture did not land>>'; end if;
  v := fn_sales_portal_report('supplier', v_id::text);
  raise exception 'CHK<<%>>', v::text;
end $probe$;`;
const res = await sql(probe);
const m = String(res.error || '').match(/CHK<<([\s\S]*?)>>/);
if (!m) { check('synthetic supplier report ran', false, String(res.error).slice(0, 400)); }
else {
  const sj = JSON.parse(JSON.parse(`"${m[1].replace(/"/g, '\\"')}"`.replace(/\\\\/g, '\\')) || '{}');
  console.log(JSON.stringify(sj, null, 2));
  check('supplier report returns ok', sj.ok === true);
  check('jobs won is true_zero with its denominator', sj.jobs_won?.basis === 'true_zero',
    `value=${sj.jobs_won?.value} denominator=${sj.jobs_won?.denominator}`);
  check('approval is UNKNOWN, never "0 approved"', sj.approval?.basis === 'unknown');
  check('win rate refuses a denominator of zero', sj.win_rate_pct?.basis === 'unknown');
  check('the directory rating is labelled derived_not_earned',
    sj.rating_from_directory?.basis === 'derived_not_earned', `value=${sj.rating_from_directory?.value}`);
  check('the rating earned here is separate and empty',
    sj.rating_earned_here?.basis === 'true_zero' && sj.rating_earned_here?.value === null);
  check('capability confirmation state is reported', typeof sj.capability_confirmation?.state === 'string',
    sj.capability_confirmation?.state);
  check('document expiry is an array', Array.isArray(sj.document_expiry));
}
const after = await one(`select count(*) n from leads where company_name like 'ZZ DEMO%'`);
check('the fixture left NOTHING behind', Number(after.n) === 0, `${after.n} ZZ DEMO leads remain`);

console.log(`\n${fails === 0 ? 'ALL CHECKS PASSED' : fails + ' CHECK(S) FAILED'}`);
process.exit(fails === 0 ? 0 : 1);
