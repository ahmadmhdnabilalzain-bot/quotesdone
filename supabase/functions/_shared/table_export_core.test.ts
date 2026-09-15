// The daily table export: a firewall refusal, an expired token and a provider outage mid-run.
// Pure tests, no network: the storage upload and the page reader are stand-ins.
import { assert, assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { classifyFailure, exportSlot, ExportError, leftoverFailure, retry, wafSafeJson, type Deps, type Slot } from './table_export_core.ts';

Deno.test('a v2-shaped state (failing table already off the queue) still yields an internal finding', () => {
  // the 2026-09-15 shape: kb_chunks errored under v2 and was shifted away; the queue moved on
  const st = { queue: [] as Slot[], errors: { kb_chunks: 'upload 2026-09-15/kb_chunks/page_0103.json: Forbidden' } };
  const f = leftoverFailure(st.errors);
  assert(f);
  assertEquals(f.cause, 'internal');
  assertEquals(f.table, 'kb_chunks');
  assert(f.error.startsWith('kb_chunks: upload 2026-09-15/kb_chunks/page_0103.json: Forbidden'));
  assertEquals(leftoverFailure({ a: 'x', b: 'y' })?.table, 'a,b');
  assertEquals(leftoverFailure({}), null);   // a clean day settles nothing here and closes via the success path
});

// What an OWASP guide row looks like (the shape of kb_chunks 185295, which the edge firewall refused).
const attacky = [
  { id: 185295, title: "OWASP WSTG 4.2 - inferring the length with LEN", content:
    "' UNION SELECT username, password FROM users-- ; <script>alert(1)</script> ../../etc/passwd ${jndi:ldap://x} `id` | /bin/sh" },
  { id: 2, title: 'quote " backslash \\ newline \n tab \t unicode \u00e9 \u4e2d \u0000 \u2028', n: -1.5e3, ok: true, none: null, arr: [1, 'a/b'] },
];

Deno.test('the escaped page parses to exactly the same value', () => {
  const s = wafSafeJson(attacky);
  assertEquals(JSON.parse(s), attacky);
  assertEquals(JSON.stringify(JSON.parse(s)), JSON.stringify(attacky));
  assertEquals(wafSafeJson([]), '[]');
});

Deno.test('the escaped page carries none of the characters a firewall signature needs, inside any string', () => {
  const s = wafSafeJson(attacky);
  for (const bad of ['<script', "'", '../', '/etc', '${', '`', '|', '--', ';', '(', 'jndi:']) {
    assert(!s.includes(bad), 'still contains ' + bad);
  }
});

function harness(opts: { pages: number; refuse?: (path: string, n: number) => Error | null }) {
  const stored = new Map<string, string>();
  const cleared: string[] = [];
  let calls = 0;
  const deps: Deps = {
    now: () => 0,
    clear: async (_s, t) => { cleared.push(t); },
    readPage: async (slot) => {
      const start = Number(slot.after ?? 0);
      const rows = start < opts.pages ? [{ id: start + 1, body: '<script>' + start }] : [];
      return { rows, done: start + 1 >= opts.pages, last: start + 1 };
    },
    upload: async (path, body) => {
      calls++;
      const e = opts.refuse?.(path, calls);
      if (e) throw e;
      stored.set(path, body);
    },
  };
  return { deps, stored, cleared, calls: () => calls };
}

Deno.test('a mid-run 403 leaves the slot on the refused page, and the resumed run continues there without clearing', async () => {
  let refuse = true;
  const h = harness({ pages: 6, refuse: (p) => (refuse && p.endsWith('page_0003.json') ? Object.assign(new Error('Forbidden'), { status: 403 }) : null) });
  const slot: Slot = { t: 'kb_chunks', after: null, page: 0, rows: 0, since: null };
  const up = (p: string, b: string) => retry('upload ' + p, () => h.deps.upload(p, b));
  const deps = { ...h.deps, upload: up };
  const err = await assertRejects(() => exportSlot('2026-09-15', slot, 1, deps), ExportError);
  assertEquals(err.cause_, 'internal');
  assert(err.message.includes('page_0003.json: Forbidden'));
  assertEquals(slot.page, 3);                 // the page that failed, not 0
  assertEquals(slot.after, 3);                // the key before it
  assertEquals(h.cleared, ['kb_chunks']);     // cleared once, at the very start
  assertEquals(h.calls(), 4);                 // pages 0,1,2 and ONE try of page 3: a 403 is not retried
  refuse = false;                             // the fix: the same page now goes through
  assert(await exportSlot('2026-09-15', slot, 1, deps));
  assertEquals(h.cleared, ['kb_chunks']);     // resuming did not wipe pages 0-2
  assertEquals([...h.stored.keys()].length, 6);
  assertEquals(slot.rows, 6);
});

Deno.test('an expired token is our own failure: classed internal and not retried', async () => {
  let n = 0;
  const err = await assertRejects(() => retry('upload x', async () => { n++; throw Object.assign(new Error('jwt expired'), { status: 401 }); },
    [0, 1, 1], async () => {}), ExportError);
  assertEquals(err.cause_, 'internal');
  assertEquals(n, 1);
  assertEquals(classifyFailure('jwt expired'), 'internal');
  assertEquals(classifyFailure('new row violates row-level security policy'), 'internal');
  assertEquals(classifyFailure('Forbidden'), 'internal');
  assertEquals(classifyFailure('The resource already exists'), 'internal');
});

Deno.test('a provider outage is retried three times and classed provider', async () => {
  let n = 0;
  const err = await assertRejects(() => retry('upload x', async () => { n++; throw Object.assign(new Error('Service Unavailable'), { status: 503 }); },
    [0, 1, 1], async () => {}), ExportError);
  assertEquals(err.cause_, 'provider');
  assertEquals(n, 3);
  assertEquals(classifyFailure('error sending request: connection reset'), 'provider');
  assertEquals(classifyFailure('x', 429), 'provider');
  let m = 0;
  assertEquals(await retry('upload y', async () => { if (++m < 3) throw new Error('fetch failed'); return 7; }, [0, 1, 1], async () => {}), 7);
});
