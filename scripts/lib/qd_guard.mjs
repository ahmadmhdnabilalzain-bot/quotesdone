// qd_guard.mjs — the production-refusal guard.
//
// Batch 0 step 2 requires that migration, cleanup and fixture work REFUSE to run against
// production, and that the refusal is "a guard the scripts call, not a convention".
//
// Every write path in this repo's tooling must obtain its query function from here.
// mgmtWrite() throws before the first byte reaches the network if the target ref is
// production, or if the SQL carries a production literal.
//
// Read-only work against production is legitimate (A-01 was diagnosed that way), so
// mgmtRead() is deliberately separate and permits PROD. It refuses anything that looks
// like a write.
import { readFileSync } from 'node:fs';

export const PROD_REF = 'htdblwldjkcgjvmqkbeh';

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const H = { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' };

export class ProductionRefusal extends Error {
  constructor(msg) { super('REFUSED: ' + msg); this.name = 'ProductionRefusal'; }
}

// A ref is production if it IS the production ref. Resolution is exact-match on purpose:
// a typo must fail closed, not fall through to "probably staging".
export function assertNotProduction(ref, what = 'write') {
  if (typeof ref !== 'string' || !/^[a-z]{20}$/.test(ref)) {
    throw new ProductionRefusal(`target ref ${JSON.stringify(ref)} is not a valid project ref`);
  }
  if (ref === PROD_REF) {
    throw new ProductionRefusal(`${what} targeted production (${PROD_REF}). Batch 0 forbids this.`);
  }
  return ref;
}

// A branch that carries production's ref inside a cron command or a function body will call
// production from staging. That happened on 3-4 Aug for eighteen hours. Any SQL we send to a
// branch is checked for the literal before it is sent.
export function assertNoProductionLiteral(sql, where = 'statement') {
  if (sql.includes(PROD_REF)) {
    throw new ProductionRefusal(
      `${where} embeds the production ref ${PROD_REF}. Applying it to a branch would point ` +
      `branch code at production. Strip or rewrite it first.`);
  }
  return sql;
}

// The management API throttles. On 4 Aug a schema rebuild and a data copy ran against it at the
// same time and BOTH started failing with 429 - which the rebuild then recorded as "this statement
// cannot be replayed", turning a rate limit into a false reproducibility defect. Transport failures
// are retried with backoff so that a recorded failure means what it says.
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// A request with no timeout is not a slow request, it is a stopped program. The 4 Aug rebuild
// stalled at function ~150 of 590 on a connection that never resolved: the backoff below could
// not fire because the promise never settled, and the job sat there looking like work. Every
// request now fails loudly after REQ_TIMEOUT_MS so a hang becomes a retry, not a silence.
const REQ_TIMEOUT_MS = Number(process.env.QD_REQ_TIMEOUT_MS || 60000);

// THE WAITS CARRY UP TO 1s OF JITTER, and the ladder matches scripts/lib/db.mjs (7 attempts, 60 s
// cap). MEASURED 22 Sep 2026: the six-attempt, jitter-free ladder below ran out after ~94 s of
// wall clock inside demo_factory's TEARDOWN, and
// a_supplier_who_ignores_holds_is_warned_then_held went red with `management API 429` — the check
// had already proved the warning, the hold and the founder-only lift, and failed while deleting
// its own fixtures. Deterministic powers of two are the reason it ran out rather than waited:
// several checks share one rate limiter in one job, so a fixed ladder makes them retry in lockstep
// and collide on the same window again. db.mjs learned this; this second transport had not.
const jitter = () => Math.floor(Math.random() * 1000);

async function post(ref, sql, attempt = 0) {
  let r, body;
  try {
    r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
      method: 'POST', headers: H, body: JSON.stringify({ query: sql }),
      signal: AbortSignal.timeout(REQ_TIMEOUT_MS),
    });
    body = await r.text();
  } catch (e) {
    // Timeout or transport failure: retry on the same schedule as a 429.
    if (attempt < 7) {
      await sleep(Math.min(1500 * Math.pow(2, attempt), 60000) + jitter());
      return post(ref, sql, attempt + 1);
    }
    throw new Error(`transport failed after ${attempt + 1} attempts: ${e.name}: ${e.message}`);
  }
  if (r.status === 429 || r.status === 502 || r.status === 503 || r.status === 504) {
    if (attempt < 7) {
      await sleep(Math.min(1500 * Math.pow(2, attempt), 60000) + jitter());
      return post(ref, sql, attempt + 1);
    }
    if (r.status === 429) {
      const e = new Error('INFRASTRUCTURE, NOT A FINDING: the Supabase management API is rate-'
        + 'limiting this run and the backoff is exhausted. Production was not measured. Re-run it.'
        + `\n  HTTP 429: ${body.slice(0, 300)}`);
      e.status = 429; e.throttled = true;
      throw e;
    }
  }
  if (!r.ok) {
    const e = new Error(`management API ${r.status}: ${body.slice(0, 300)}`);
    e.status = r.status; e.body = body.slice(0, 2000);
    throw e;
  }
  return body ? JSON.parse(body) : null;
}

// WRITE: refuses production, refuses production literals.
export async function mgmtWrite(ref, sql, where = 'statement') {
  assertNotProduction(ref, 'write');
  assertNoProductionLiteral(sql, where);
  return post(ref, sql);
}

// DATA WRITE: the same refusal on the TARGET, but the production ref is permitted inside a value.
//
// The literal check above exists because a ref in an EXECUTABLE position - a cron command, a
// function body - makes branch code call production, which is exactly what happened for eighteen
// hours on 3-4 Aug. A row of knowledge whose CONTENT mentions the production ref is a different
// thing entirely: it is inert text, and refusing it stopped the agent_knowledge copy at 1,500 of
// 1,869 rows, leaving staging with a knowledge base that was silently 20% short.
//
// So this is a separate door with its own lock rather than a weakening of the existing one:
// the statement must be a plain INSERT, and anything that could execute is refused outright.
// Use mgmtWrite for everything else.
const EXECUTABLE = /\b(create\s+(or\s+replace\s+)?(function|procedure|view|trigger|rule)|alter\s+function|cron\.(schedule|alter_job)|do\s*\$\$|execute\s+format|net\.http_)/i;

export async function mgmtWriteData(ref, sql, where = 'data copy') {
  assertNotProduction(ref, 'write');
  // org_authority's guard trigger refuses a widening insert unless app.change_reason is set, so a
  // legitimate copy is prefixed with one transaction-local set_config. Allow exactly that prefix
  // and nothing else - it is the only non-INSERT statement a data copy is permitted to carry.
  const body = sql.replace(/^\s*select\s+set_config\(\s*'app\.change_reason'[\s\S]*?,\s*true\s*\)\s*;/i, '');
  if (!/^\s*insert\s+into\b/i.test(body)) {
    throw new ProductionRefusal(
      `${where} is not a plain INSERT. mgmtWriteData only carries row data; use mgmtWrite.`);
  }
  // CHECK THE SKELETON, NOT THE PAYLOAD. The rows travel as one quoted ::jsonb literal, and this
  // corpus is a company's own engineering knowledge - it discusses `create or replace function`,
  // `net.http_post` and cron because that is what the IT and security desks know about. Matching
  // the raw statement refused 369 of 1,869 agent_knowledge rows for containing the word, which is
  // censorship of the data rather than protection of the database. Strip quoted literals first
  // (Postgres doubles an embedded quote), then judge what is left - that is the part that executes.
  const skeleton = body.replace(/'(?:[^']|'')*'/g, "''");
  if (EXECUTABLE.test(skeleton)) {
    throw new ProductionRefusal(
      `${where} contains an executable construct outside a quoted value. ` +
      `Row data cannot define behaviour; use mgmtWrite.`);
  }
  return post(ref, sql);
}

// FIXTURE WRITE ON THE ONLY PROJECT LEFT (15 Aug 2026).
//
// Staging was deleted at the founder's instruction. Everything above stays exactly as it was —
// assertNotProduction still refuses production for every migration, cleanup and rebuild path, and
// mgmtWrite is unchanged. This is a THIRD door with its own lock, the same shape as mgmtWriteData
// above, and it exists because the alternative was to delete the fixture suite.
//
// The suite is real coverage: a 685-line end-to-end journey, the intake-routing probe that pins two
// live defects, and the demo factory 75 files import from. Retargeting it by weakening
// assertNotProduction would have removed the guard from the 30-odd migration and rebuild scripts
// that share it, to serve the ~20 that make fixtures. So the guard keeps its meaning and the
// fixtures ask for an exemption out loud:
//
//   * QD_FIXTURES=1 must be set in the environment. There is no default and no fallback — a script
//     run without it refuses before the first byte reaches the network, which is what a bare
//     `node scripts/staging/journey_test.mjs` did when it targeted a project that no longer exists.
//   * Every row a run creates carries its run tag, and teardown derives what to delete FROM THE
//     DATABASE rather than from a hand-maintained list. That was already true; it is now the thing
//     standing between a fixture run and live data.
//
// WHAT THIS IS NOT: it is not a rollback. The management API gives each POST its own implicit
// transaction and a fixture crosses HTTP — auth users are minted through the Auth admin API and
// edge functions connect on their own sessions — so no single aborted transaction can cover a
// journey. Pure-SQL assertions SHOULD use the aborted-transaction probe instead of this door, and
// most checks in scripts/checks do. This is for the ones that genuinely cannot.
export async function mgmtFixture(ref, sql, where = 'fixture') {
  if (process.env.QD_FIXTURES !== '1') {
    throw new ProductionRefusal(
      `${where} wanted to write fixture data to ${ref}, and QD_FIXTURES is not set to 1. ` +
      'This is live data. Set QD_FIXTURES=1 for the run if you mean it; every row is tagged and ' +
      'torn down in a finally, but nothing here is inside a transaction that can roll back.');
  }
  if (typeof ref !== 'string' || !/^[a-z]{20}$/.test(ref)) {
    throw new ProductionRefusal(`fixture target ${JSON.stringify(ref)} is not a valid project ref`);
  }
  return post(ref, sql);
}

// READ: production permitted, writes refused.
const WRITE_RE = /\b(insert|update|delete|truncate|drop|alter|create|grant|revoke|comment\s+on|refresh\s+materialized|vacuum|reindex|call|do)\b/i;
export async function mgmtRead(ref, sql, where = 'read') {
  if (WRITE_RE.test(sql.replace(/--[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, ''))) {
    throw new ProductionRefusal(`${where} is not read-only; use mgmtWrite against a branch instead`);
  }
  return post(ref, sql);
}

// Convenience: resolve the staging ref from env/argv and prove it is not production.
export function resolveStagingRef(argvRef) {
  const ref = (argvRef || process.env.QD_STAGING_REF || '').trim();
  if (!ref) throw new ProductionRefusal('no staging ref supplied (argv[2] or QD_STAGING_REF)');
  return assertNotProduction(ref, 'staging resolution');
}
