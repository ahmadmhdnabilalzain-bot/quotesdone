// The repository's SQL reader.  One project: htdblwldjkcgjvmqkbeh.
//
// Lived at scripts/phase_b/lib/db.mjs until 9 Sep 2026, with scripts/phase_c/lib/db.mjs as a
// re-export so Phase C scripts need not reach into Phase B's tree. Neither location was ever
// true of what it is: deploy_functions.mjs, every file in scripts/kb/ and a dozen checks import
// it, and none of them is a phase script. It moved here so the phase directories can be deleted
// without taking the deployer and the knowledge tooling with them.
//
// Every check here must verify by execution, so the validators talk to the live
// database rather than to a cached dump.  The 429 backoff is here for the same
// reason it is in scripts/qsql.mjs: a bare throttle reads exactly like a broken
// query, and that has been misdiagnosed as a defect before.
import { supabaseAccessToken as token } from './supabase_token.mjs';

export const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';

// `retry: false` turns the backoff OFF for one call. MEASURED 18 Sep 2026, twice: the accountant's
// 22-file DDL replay outlives the management API gateway (524), the retry POSTs the SAME batch while
// the first copy is still running server-side, and the two copies deadlock on each other --
// "deadlock detected: process A waits for AccessExclusiveLock on relation 17188; blocked by process
// B", 18 minutes of wall clock for a check that can never pass. A rolled-back transaction is safe to
// re-issue SERIALLY; it is not safe to re-issue CONCURRENTLY, and a 524 is not proof the first copy
// has stopped. Any caller whose statement can outlive the gateway must pass `retry: false`.
// `retryableBody` widens the retry to a 400 whose BODY names an infrastructure answer rather than a
// bad query. The management API returns `57014 canceling statement due to statement timeout` and
// `55P03 lock_not_available` as HTTP 400, indistinguishable by status from a syntax error, so a
// caller that must survive another session's apply has to name the pattern it will retry. It lives
// here rather than in each caller because there is one endpoint and there should be one retry
// policy for it: `export_from_either_source_is_identical.mjs` hand-rolled a second one on
// 18 Sep 2026 and that is how a hazard learned in this file stops reaching the checks.
// MEASURED 18 Sep 2026: fn_schema_export blocks for the whole duration of any concurrent
// ACCESS EXCLUSIVE lock (12,374 ms behind a 12s lock on one table, against ~900 ms unblocked), so
// without this a single `apply_sql --apply --ddl` elsewhere failed the schema-mirror gate outright.
//
// The waits carry up to 1s of JITTER. Several checks run in one CI job against one rate limiter;
// deterministic powers of two make them retry in lockstep and collide on the same window again.
//
// `readOnly` sets the management API's own read_only flag on the statement, so a check that only
// reads cannot write even by accident. It is a property of the request, not of the retry, and it
// lives here so a check does not have to hand-roll a second transport to get it — which is exactly
// how two checks ended up with no backoff at all (measured 22 Sep 2026, below).
//
// ON EXHAUSTION THIS SAYS WHICH IT WAS. MEASURED 22 Sep 2026: a throttled night turned six checks
// on origin/main red, and every one of them reported the throttle in the words of a finding —
// `query failed: 429`, `the probe left a ZZ DEMO party behind`, `management API 429`. A reviewer
// reading those has to re-run all six to learn that production was never wrong. The header above
// has said since the file was written that a bare throttle reads exactly like a broken query; the
// backoff prevented that while it had attempts left and then threw the same ambiguous text. The
// final error now names the throttle as infrastructure, in the one place every caller goes through.
export const THROTTLED = 'INFRASTRUCTURE, NOT A FINDING: the Supabase management API is rate-'
  + 'limiting this run and the backoff is exhausted. Production was not measured. Re-run it.';

export async function sql(query, {
  ref = PROJECT_REF, retry = true, retryableBody = null, readOnly = false,
} = {}) {
  const jitter = () => Math.floor(Math.random() * 1000);
  for (let attempt = 0; ; attempt++) {
    // THE CONNECTION ITSELF WAS THE ONE FAILURE THIS RETRY DID NOT COVER. A 429 and a 5xx were
    // retried; a fetch that THROWS -- ECONNRESET, "fetch failed", a socket hang up -- escaped and
    // killed the caller. Measured 23 Aug 2026: three separate Phase D deliverable builds died
    // part-way through with "the drive for W12 failed before it could report: fetch failed", and a
    // half-built deliverable is exactly what this file's header says the backoff exists to prevent.
    // A dropped connection reads like a broken query too.
    //
    // Callers of this helper mostly read, or write inside a transaction that ends in
    // `raise exception`, and for those re-issuing the statement cannot double-apply anything. A
    // statement whose effect commits on its own (`select public.fn_kernel_cron_exec(<jobid>)`, a
    // tick that POSTs) is the exception: if the first issue ran and only the answer was lost, the
    // retry runs it again, so such a callee must be idempotent per tick (sanctions_screen guards
    // ten minutes). The retry is loud, so a run that needed it says so.
    let res;
    try {
      res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(readOnly ? { query, read_only: true } : { query }),
      });
    } catch (err) {
      if (retry && attempt < 5) {
        const wait = Math.min(2000 * 2 ** attempt, 30000) + jitter();
        process.stderr.write(`-- transport ${err?.cause?.code || err?.message || 'error'}; `
          + `retry in ${wait / 1000}s (${attempt + 1}/5)\n`);
        await new Promise(r => setTimeout(r, wait));
        continue;
      }
      throw err;
    }
    const text = await res.text();
    const infraBody = Boolean(retryableBody) && !res.ok && retryableBody.test(text);
    if (retry && (res.status === 429 || res.status >= 500 || infraBody) && attempt < 7) {
      const wait = Math.min(2000 * 2 ** attempt, 60000) + jitter();
      process.stderr.write(`-- ${res.status}${infraBody ? ' (infrastructure, not the query)' : ''};`
        + ` retry in ${(wait / 1000).toFixed(1)}s (${attempt + 1}/7)\n`);
      await new Promise(r => setTimeout(r, wait));
      continue;
    }
    if (res.status === 429) {
      const e = new Error(`${THROTTLED}\n  HTTP 429: ${text.slice(0, 500)}`);
      e.status = 429; e.throttled = true;
      throw e;
    }
    // e.body is the untruncated answer: safe_replay.mjs reads a rolled-back query's rows out of it.
    if (!res.ok) throw Object.assign(new Error(`HTTP ${res.status}: ${text.slice(0, 2000)}`), { status: res.status, body: text });
    try { return JSON.parse(text); } catch { return text; }
  }
}

/** Quote a JS string as a SQL literal. */
export const lit = s => `'${String(s).replace(/'/g, "''")}'`;

/** Build a `values (...),(...)` list; every cell is quoted as text. */
export const valuesOf = rows => rows.map(r => `(${r.map(lit).join(',')})`).join(',');
