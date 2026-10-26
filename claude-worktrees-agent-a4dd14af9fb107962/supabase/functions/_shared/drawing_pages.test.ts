// drawing_pages.test.ts — a redacted drawing page that fails to sign is COUNTED, LOGGED and RAISED,
// and the pages that did sign are still served (18 Sep 2026, sales_engineer).
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/drawing_pages.test.ts
// The storage client is a recorder: nothing reaches production storage, a database or a person.
// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { DRAWING_SIGN_ISSUE, drawingWithheld, signRedactedDrawings } from './drawing_pages.ts';

/** `fails` decides how each path answers: 'ok', 'error' (the shape createSignedUrl really returns), or 'throw'. */
function fake(fails: (path: string) => 'ok' | 'error' | 'throw' | 'hang') {
  const rpcs: { name: string; args: any }[] = [];
  const inserts: { table: string; row: any }[] = [];
  const signed: string[] = [];
  const admin = {
    storage: {
      from: (_bucket: string) => ({
        createSignedUrl: async (path: string, _s: number) => {
          signed.push(path);
          const mode = fails(path);
          if (mode === 'throw') throw new Error('socket hang up');
          if (mode === 'hang') return await new Promise(() => {}); // never resolves: only the deadline ends it
          if (mode === 'error') return { data: null, error: { message: 'Object not found' } };
          return { data: { signedUrl: 'https://storage.example.invalid/' + path + '?token=SECRET-TOKEN' }, error: null };
        },
      }),
    },
    rpc: async (name: string, args: any) => { rpcs.push({ name, args }); return { data: {}, error: null }; },
    from: (table: string) => ({ insert: async (row: any) => { inserts.push({ table, row }); return { error: null }; } }),
  };
  return { admin, rpcs, signed, inserts };
}

const ROWS = [
  { id: 'zz-demo-inq-1', paths: ['redacted/zz-demo-1/page_p1.jpg', 'redacted/zz-demo-1/page_p2.jpg', 'redacted/zz-demo-1/page_p3.jpg'] },
  { id: 'zz-demo-inq-2', paths: [] },
];

Deno.test('every page signs: served, nothing failed, no finding', async () => {
  const f = fake(() => 'ok');
  const out = await signRedactedDrawings(f.admin, ROWS);
  assertEquals(out['zz-demo-inq-1'].urls.length, 3);
  assertEquals([out['zz-demo-inq-1'].expected, out['zz-demo-inq-1'].served, out['zz-demo-inq-1'].failed], [3, 3, 0]);
  // An inquiry with no drawings is NOT the same reading as one whose drawings all arrived.
  assertEquals([out['zz-demo-inq-2'].expected, out['zz-demo-inq-2'].served, out['zz-demo-inq-2'].failed], [0, 0, 0]);
  assertEquals(f.rpcs.length, 0);
});

for (const mode of ['error', 'throw'] as const) {
  Deno.test(`one page ${mode}s: the other two are STILL served, the failure is counted and raised`, async () => {
    const f = fake((p) => (p.endsWith('page_p2.jpg') ? mode : 'ok'));
    const out = await signRedactedDrawings(f.admin, ROWS);

    // 1. Partial service: the inbox is not emptied by one bad page.
    assertEquals(out['zz-demo-inq-1'].urls.length, 2);
    assertEquals([out['zz-demo-inq-1'].expected, out['zz-demo-inq-1'].served, out['zz-demo-inq-1'].failed], [3, 2, 1]);
    assert(!out['zz-demo-inq-1'].urls.some((u) => u.includes('page_p2')), 'the failed page was served anyway');

    // 2. One finding, one dedupe key, counts that tell broken from idle.
    const finding = f.rpcs.find((r) => r.name === 'fn_it_engineer_finding_upsert');
    assert(finding, 'no IT engineer finding was raised');
    assertEquals(f.rpcs.length, 1, 'more than one finding per request');
    assertEquals(finding.args.p_issue_key, DRAWING_SIGN_ISSUE);
    assertEquals(finding.args.p_affected, 1);
    assertEquals(finding.args.p_raised_by, 'sales_engineer');
    const ev = finding.args.p_evidence;
    assertEquals([ev.pages_expected, ev.pages_served, ev.pages_failed, ev.inquiries_affected], [3, 2, 1, 1]);
    assertEquals(ev.per_inquiry, [{ inquiry_id: 'zz-demo-inq-1', expected: 3, failed: 1 }]);

    // 3. The path and the message are recorded; a signed URL, its token and any key are not.
    assertEquals(ev.sample_errors.length, 1);
    assertEquals(ev.sample_errors[0].path, 'redacted/zz-demo-1/page_p2.jpg');
    assert(String(ev.sample_errors[0].message).length > 0, 'the storage message was not recorded');
    const written = JSON.stringify(finding.args);
    for (const secret of ['SECRET-TOKEN', 'token=', 'https://storage.example.invalid']) {
      assert(!written.includes(secret), 'a signed URL or token was written into the finding: ' + secret);
    }
  });
}

Deno.test('every page fails: nothing is served, and the finding says how many were expected', async () => {
  const f = fake(() => 'error');
  const out = await signRedactedDrawings(f.admin, ROWS);
  assertEquals(out['zz-demo-inq-1'].urls.length, 0);
  assertEquals([out['zz-demo-inq-1'].expected, out['zz-demo-inq-1'].served, out['zz-demo-inq-1'].failed], [3, 0, 3]);
  const ev = f.rpcs[0].args.p_evidence;
  assertEquals([ev.pages_expected, ev.pages_served, ev.pages_failed], [3, 0, 3]);
});

Deno.test('the finding failing to open leaves a second trail in agent_runs, and never takes the inbox down', async () => {
  const f = fake(() => 'error');
  (f.admin as any).rpc = async () => { throw new Error('rpc unavailable'); };
  const out = await signRedactedDrawings(f.admin, ROWS);
  assertEquals(out['zz-demo-inq-1'].failed, 3);
  const run = f.inserts.find((i) => i.table === 'agent_runs');
  assert(run, 'the finding path was down and nothing else recorded the fault');
  assertEquals(run.row.status, 'error');
  assertEquals([run.row.counts.pages_expected, run.row.counts.pages_served, run.row.counts.pages_failed], [3, 0, 3]);
  assertEquals(run.row.counts.finding_unavailable, 1);
});

Deno.test('a signing call that never answers is a counted failure, not a hung inbox', async () => {
  const f = fake((p) => (p.endsWith('page_p2.jpg') ? 'hang' : 'ok'));
  // The deadline fires immediately instead of after 8 s, so the proof costs nothing in CI time.
  const realTimeout = globalThis.setTimeout;
  (globalThis as any).setTimeout = ((fn: () => void) => realTimeout(fn, 0)) as typeof setTimeout;
  try {
    const out = await signRedactedDrawings(f.admin, ROWS);
    assertEquals([out['zz-demo-inq-1'].expected, out['zz-demo-inq-1'].served, out['zz-demo-inq-1'].failed], [3, 2, 1]);
    const ev = f.rpcs[0].args.p_evidence;
    assertEquals(ev.sample_errors[0].path, 'redacted/zz-demo-1/page_p2.jpg');
    assert(String(ev.sample_errors[0].message).includes('timed out'), 'the timeout was not the recorded reason');
  } finally { globalThis.setTimeout = realTimeout; }
});

Deno.test('a token-shaped fragment in a storage error never reaches the finding', async () => {
  const f = fake(() => 'error');
  (f.admin.storage as any).from = () => ({ createSignedUrl: async () => ({ data: null, error: { message: 'refused for https://x.invalid/o?token=LEAKED-abc123&x=1' } }) });
  await signRedactedDrawings(f.admin, ROWS);
  const written = JSON.stringify(f.rpcs[0].args);
  assert(!written.includes('LEAKED-abc123'), 'a token-shaped fragment was recorded: ' + written);
  assert(written.includes('token=[removed]'), 'the message was not recorded at all');
});

// 22 Sep 2026: a held drawing / a CAD file reached the supplier as nothing at all, with no word that it existed.
Deno.test('a customer file with no shareable page is reported as withheld, never as absent', () => {
  assertEquals(drawingWithheld(true, 0), true);    // held drawing, CAD file, BOQ sheet: an original, no pages
  assertEquals(drawingWithheld(true, 3), false);   // the redacted pages are the drawing
  assertEquals(drawingWithheld(false, 0), false);  // no file was attached
});
