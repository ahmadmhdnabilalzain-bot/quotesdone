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
    if (attempt < 6) { await sleep(1500 * Math.pow(2, attempt)); return post(ref, sql, attempt + 1); }
    throw new Error(`transport failed after ${attempt + 1} attempts: ${e.name}: ${e.message}`);
  }
  if (r.status === 429 || r.status === 502 || r.status === 503 || r.status === 504) {
    if (attempt < 6) { await sleep(1500 * Math.pow(2, attempt)); return post(ref, sql, attempt + 1); }
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
