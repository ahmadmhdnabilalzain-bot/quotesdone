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
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

export const PROJECT_REF = 'htdblwldjkcgjvmqkbeh';

function token() {
  if (process.env.SUPABASE_ACCESS_TOKEN) return process.env.SUPABASE_ACCESS_TOKEN.trim();
  const p = join(homedir(), '.supabase', 'access-token');
  if (existsSync(p)) return readFileSync(p, 'utf8').trim();
  throw new Error('No Supabase access token (SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token).');
}

// `retry: false` turns the backoff OFF for one call. MEASURED 18 Sep 2026, twice: the accountant's
// 22-file DDL replay outlives the management API gateway (524), the retry POSTs the SAME batch while
// the first copy is still running server-side, and the two copies deadlock on each other --
// "deadlock detected: process A waits for AccessExclusiveLock on relation 17188; blocked by process
// B", 18 minutes of wall clock for a check that can never pass. A rolled-back transaction is safe to
// re-issue SERIALLY; it is not safe to re-issue CONCURRENTLY, and a 524 is not proof the first copy
// has stopped. Any caller whose statement can outlive the gateway must pass `retry: false`.
export async function sql(query, { ref = PROJECT_REF, retry = true } = {}) {
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
        body: JSON.stringify({ query }),
      });
    } catch (err) {
      if (retry && attempt < 5) {
        const wait = Math.min(2000 * 2 ** attempt, 30000);
        process.stderr.write(`-- transport ${err?.cause?.code || err?.message || 'error'}; `
          + `retry in ${wait / 1000}s (${attempt + 1}/5)\n`);
        await new Promise(r => setTimeout(r, wait));
        continue;
      }
      throw err;
    }
    const text = await res.text();
    if (retry && (res.status === 429 || res.status >= 500) && attempt < 7) {
      const wait = Math.min(2000 * 2 ** attempt, 60000);
      process.stderr.write(`-- ${res.status}; retry in ${wait / 1000}s (${attempt + 1}/7)\n`);
      await new Promise(r => setTimeout(r, wait));
      continue;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 2000)}`);
    try { return JSON.parse(text); } catch { return text; }
  }
}

/** Quote a JS string as a SQL literal. */
export const lit = s => `'${String(s).replace(/'/g, "''")}'`;

/** Build a `values (...),(...)` list; every cell is quoted as text. */
export const valuesOf = rows => rows.map(r => `(${r.map(lit).join(',')})`).join(',');
