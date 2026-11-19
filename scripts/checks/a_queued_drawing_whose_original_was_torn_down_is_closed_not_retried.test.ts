// A QUEUED DRAWING WHOSE ORIGINAL WAS TORN DOWN IS CLOSED, NOT RETRIED (19 Nov 2026, sales_engineer; agent cad-worker-fix).
//
// MEASURED (production SELECT, 19 Nov 2026): cad_read_jobs held 2 rows, both why 'pages_need_time', both 'failed' after 3
// attempts with "the stored drawing could not be downloaded (HTTP 400)". Queued 17 Nov 23:53:23Z and 23:55:11Z (7 and 9 min
// after demo purge 206), owner an example.invalid address, file "ZZ DEMO mechanical set(.pdf| p1.pdf)". Their source_path had
// no row in storage.objects (bucket drawing-files), nor did anything under the customer's folder, and customer 3143c84b was
// gone: a proof's teardown deleted the original, and Supabase storage answers a missing object with HTTP 400 (body
// statusCode "404"). The worker then asked again at the next two hourly runs (claimed_at 02:19:23Z is the THIRD claim:
// fn_cad_read_claim overwrites it) and raised cad_read_worker:job_failed. Asking again can never bring a deleted file back.
//
// Now: on a 400/404 the worker reads storage.objects; when the original is not there the job is closed at once as
// 'source_gone' (status done, no BOQ, no pages), and no finding is raised when it was a demo drawing or its customer is gone.
// A real customer who still exists and whose original vanished IS raised (cad_read_worker:source_gone): that is a defect.
// An object storage still holds (a 400 for another reason) and any other status stay loud and are retried as before.
//
// Also proven: --watch keeps the worker claiming every minute until the window ends, so a sheet queued after the hourly
// run's start is read within a minute (drainUntil), outside the edge's CPU cap.
//   deno test --no-lock --node-modules-dir=none scripts/checks/a_queued_drawing_whose_original_was_torn_down_is_closed_not_retried.test.ts
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { drainUntil, runJob, sourceGoneIsRaised, WATCH_FRESH_SQL, watchDeps, watchMinutes, watchReleaseSql, type Job } from '../cad_read_worker.ts';

const JOB: Job = {
  id: 'a0b00000-0000-4000-8000-0000000000d1', customer_id: 'c0ffee00-0000-4000-8000-0000000000d1', owner_email: 'qd-zz-cust@example.invalid',
  source_path: 'drawings/c0ffee00-0000-4000-8000-0000000000d1/1794959484550_ZZ DEMO mechanical set.pdf', file_name: 'ZZ DEMO mechanical set.pdf',
  mime: 'application/pdf', attempts: 1, why: 'pages_need_time', boq_in: { queued_pages: { pages_in: 1, seed_terms: [], done: [], left: [] } },
};

type Seen = { sql: string[]; storage: string[] };
/** Storage answers `status` for the original; the management API answers the existence read with `gone`. */
function stub(status: number, gone: { held: boolean; customer: boolean; demo: boolean }): Seen {
  const seen: Seen = { sql: [], storage: [] };
  globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.includes('/storage/v1/object/')) {
      seen.storage.push(url);
      return new Response(JSON.stringify({ statusCode: '404', error: 'not_found', message: 'Object not found' }), { status });
    }
    if (url.includes('/database/query')) {
      const q = JSON.parse(String(init?.body)).query as string;
      seen.sql.push(q);
      return new Response(JSON.stringify(q.includes('storage.objects') ? [gone] : []), { status: 201 });
    }
    throw new Error('unexpected fetch ' + url);
  }) as typeof fetch;
  return seen;
}
const real = globalThis.fetch;

Deno.test('a demo original torn down: the job is closed as source_gone at once, no finding, no retry', async () => {
  const seen = stub(400, { held: false, customer: false, demo: true });
  try { await runJob(JOB, 'zz-demo-service'); } finally { globalThis.fetch = real; }
  // the path is sent segment by segment, a space as %20 (not the cause: the object is absent)
  assert(seen.storage[0].endsWith('/drawing-files/drawings/c0ffee00-0000-4000-8000-0000000000d1/1794959484550_ZZ%20DEMO%20mechanical%20set.pdf'), seen.storage[0]);
  const look = seen.sql.find((q) => q.includes('storage.objects'));
  assert(look && look.includes("bucket_id = 'drawing-files'") && look.includes(JOB.source_path), 'storage.objects is read for the exact path');
  const done = seen.sql.find((q) => q.includes('update public.cad_read_jobs'));
  assert(done && done.includes("status = 'done'") && done.includes('"held_reason":"source_gone"') && done.includes('"kind":"source_gone"'), `closed: ${done}`);
  assert(!seen.sql.some((q) => q.includes('fn_it_engineer_finding_upsert')), 'a torn-down demo drawing raises nothing');
});

Deno.test('a real customer still here whose original vanished: closed, and raised as cad_read_worker:source_gone', async () => {
  // the existence read answers: the customer row is still there and the owner is not a demo address
  const seen = stub(404, { held: false, customer: true, demo: false });
  try { await runJob(JOB, 'zz-demo-service'); } finally { globalThis.fetch = real; }
  assert(seen.sql.some((q) => q.includes("status = 'done'") && q.includes('source_gone')), 'closed, not retried');
  const raised = seen.sql.find((q) => q.includes('fn_it_engineer_finding_upsert'));
  assert(raised && raised.includes('cad_read_worker:source_gone'), `raised: ${raised}`);
});

Deno.test('an original storage still holds (a 400 for another reason): loud, and back to the queue as before', async () => {
  const seen = stub(400, { held: true, customer: true, demo: false });
  try { await assertRejects(() => runJob(JOB, 'zz-demo-service'), Error, 'could not be downloaded (HTTP 400)'); } finally { globalThis.fetch = real; }
  assert(!seen.sql.some((q) => q.includes('update public.cad_read_jobs')), 'the job is not closed here');
});

Deno.test('a storage outage (HTTP 503): retried as before, and storage.objects is not read', async () => {
  const seen = stub(503, { held: false, customer: false, demo: true });
  try { await assertRejects(() => runJob(JOB, 'zz-demo-service'), Error, 'HTTP 503'); } finally { globalThis.fetch = real; }
  assertEquals(seen.sql.length, 0);
});

Deno.test('--watch: a sheet queued after the run began is claimed within a minute, and no claim starts past the window', async () => {
  let now = 0;
  const claims: number[] = [];
  const ran: string[] = [];
  // a job appears at minute 12.5 of the window
  const claim = async () => { claims.push(now); return now >= 12.5 * 60_000 && !ran.length ? [{ ...JOB, id: 'late' }] : []; };
  const n = await drainUntil({ claim, run: async (j) => { ran.push(j.id); }, until: 50 * 60_000, every: 60_000, now: () => now, sleep: async (ms) => { now += ms; } });
  assertEquals(ran, ['late']);
  assertEquals(n, 1);
  const pickedAt = claims.find((t) => t >= 12.5 * 60_000)!;
  assert(pickedAt - 12.5 * 60_000 <= 60_000, `picked ${pickedAt - 12.5 * 60_000} ms after it was queued`);
  assert(claims.every((t) => t < 50 * 60_000), 'no claim at or past the window end');
  assertEquals(claims.length, 50);
});

Deno.test('--watch: a job asked again is put back on a watch pass (its retry waits for the next hourly run), run on the first', async () => {
  let now = 0;
  const ran: string[] = [], released: string[] = [];
  const claim = async (first: boolean) => first ? [{ ...JOB, id: 'retry-first', attempts: 2 }] : now === 60_000 ? [{ ...JOB, id: 'retry-watch', attempts: 2 }, { ...JOB, id: 'fresh', attempts: 1 }] : [];
  await drainUntil({ claim, run: async (j) => { ran.push(j.id); }, release: async (j) => { released.push(j.id); }, until: 5 * 60_000, every: 60_000, now: () => now, sleep: async (ms) => { now += ms; } });
  assertEquals(ran, ['retry-first', 'fresh']);
  assertEquals(released, ['retry-watch']);
});

Deno.test('--watch: one pass by default; the window is bounded to 50 minutes (the next hourly run starts at :18)', () => {
  assertEquals(watchMinutes([]), 0);
  assertEquals(watchMinutes(['--watch=30']), 30);
  assertEquals(watchMinutes(['--watch=500']), 50);
  assertEquals(watchMinutes(['--watch=abc']), 0);
  assertEquals(watchMinutes(['--watch=-5']), 0);
});

// ── review of #2076 (19 Nov 2026) ─────────────────────────────────────────────────────────────────────────────────────
Deno.test('a job with no customer_id whose original vanished is raised: nothing proves a teardown (unless it is a demo)', async () => {
  const seen = stub(400, { held: false, customer: false, demo: false });
  try { await runJob({ ...JOB, customer_id: null }, 'zz-demo-service'); } finally { globalThis.fetch = real; }
  assert(seen.sql.some((q) => q.includes("status = 'done'") && q.includes('source_gone')), 'closed, not retried');
  const raised = seen.sql.find((q) => q.includes('fn_it_engineer_finding_upsert'));
  assert(raised && raised.includes('cad_read_worker:source_gone') && raised.includes('customer not recorded'), `raised: ${raised}`);
  const look = seen.sql.find((q) => q.includes('storage.objects'))!;
  assert(/false as customer/.test(look), 'no customer row is looked up for a null id');
  assert(look.includes("raw_app_meta_data ? 'e2e_run'"), 'an e2e-run login counts as demo');
  // the rule, every case
  assertEquals(sourceGoneIsRaised({ customer_id: null }, { customer: false, demo: false }), true);
  assertEquals(sourceGoneIsRaised({ customer_id: null }, { customer: false, demo: true }), false);
  assertEquals(sourceGoneIsRaised({ customer_id: JOB.customer_id }, { customer: false, demo: false }), false, 'customer gone with it: a teardown');
  assertEquals(sourceGoneIsRaised({ customer_id: JOB.customer_id }, { customer: true, demo: false }), true);
  assertEquals(sourceGoneIsRaised({ customer_id: JOB.customer_id }, { customer: true, demo: true }), false);
});

Deno.test('a demo job with no customer_id (ZZ DEMO or e2e run): closed, nothing raised', async () => {
  const seen = stub(400, { held: false, customer: false, demo: true });
  try { await runJob({ ...JOB, customer_id: null }, 'zz-demo-service'); } finally { globalThis.fetch = real; }
  assert(seen.sql.some((q) => q.includes('source_gone')));
  assert(!seen.sql.some((q) => q.includes('fn_it_engineer_finding_upsert')));
});

Deno.test('watch SQL: a watch pass claims only when a job with attempts = 0 is queued; the first pass always claims', async () => {
  assertEquals(WATCH_FRESH_SQL, `select exists (select 1 from public.cad_read_jobs where status = 'queued' and attempts = 0) as fresh`);
  assert(!/\b(update|insert|delete)\b/i.test(WATCH_FRESH_SQL), 'the freshness check writes nothing');
  for (const [fresh, first, claims] of [[false, false, 0], [true, false, 1], [false, true, 1], [null, false, 0]] as const) {
    const sent: string[] = [];
    const d = watchDeps((q) => { sent.push(q); return Promise.resolve(q === WATCH_FRESH_SQL ? [{ fresh }] : [{ ...JOB, attempts: 1 }]); });
    const jobs = await d.claim(first);
    assertEquals(sent.filter((q) => q.includes('fn_cad_read_claim(6)')).length, claims, `fresh=${fresh} first=${first}`);
    assertEquals(sent.includes(WATCH_FRESH_SQL), !first, 'the first pass reads no freshness');
    assertEquals(jobs.length, claims);
  }
});

Deno.test('watch SQL: the release puts a running retry back as queued with its attempt returned, and nothing else', async () => {
  const want = `update public.cad_read_jobs set status = 'queued', attempts = attempts - 1 where id = $qd$${JOB.id}$qd$::uuid and status = 'running'`;
  assertEquals(watchReleaseSql(JOB.id), want);
  const sent: string[] = [];
  await watchDeps((q) => { sent.push(q); return Promise.resolve([]); }).release({ ...JOB, attempts: 2 });
  assertEquals(sent, [want]);
  // a hostile id stays inside its dollar-quoted literal
  const hostile = "x'; drop table zz; --";
  assert(watchReleaseSql(hostile).includes(`$qd$${hostile}$qd$::uuid`));
});
