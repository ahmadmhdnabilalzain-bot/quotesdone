// supplier_api accept_terms, the HANDLER in memory (review 2 of 13 Nov 2026, item 6). An acceptance write that is cancelled three
// times (a lock, the 8 s statement_timeout) answers the person 503 terms_not_recorded, never ok, AND files the it_engineer finding
// kyc files (terms_not_recorded:supplier_portal), in the background after the answer, with no e-mail address in it.
// Its earlier test read the source text only.
//
// Incapable of reaching anything: the handler's own service-role client is replaced by a recorder before the action runs, and the
// party is a ZZ DEMO address on @example.invalid.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/supplier_api/a_terms_write_that_never_lands_tells_a_seat.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';

const EMAIL = 'zz-demo-terms-seat@example.invalid';
type Rpc = { fn: string; args: Record<string, unknown> };

function world(writeFails: boolean) {
  const rpcs: Rpc[] = [];
  const writes: Record<string, unknown>[] = [];
  const from = (table: string) => {
    let op = 'select'; let patch: Record<string, unknown> | null = null; let key = '';
    const answer = () => {
      if (op === 'update') {
        writes.push(patch!);
        return writeFails ? { data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } } : { data: [{ id: 41 }], error: null };
      }
      if (table === 'leads') return { data: { id: 41, accepted_terms_at: null, accepted_terms_version: null, contact_name: null, signatory_name: null }, error: null };
      if (table === 'app_secrets') return { data: key === 'supplier_terms_version' ? { value: 'v5' } : null, error: null };
      return { data: null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, in: () => b, is: () => b, order: () => b, limit: () => b,
      eq: (k: string, v: unknown) => { if (k === 'key') key = String(v); return b; },
      update: (p: Record<string, unknown>) => { op = 'update'; patch = p; return b; },
      maybeSingle: () => Promise.resolve(answer()),
      then: (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(answer()).then(res, rej),
    };
    return b;
  };
  const rpc = (fn: string, args: Record<string, unknown>) => { rpcs.push({ fn, args }); return Promise.resolve({ data: { ok: true }, error: null }); };
  return { from, rpc, rpcs, writes };
}

async function accept(w: ReturnType<typeof world>) {
  Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9'); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
  const waited: Promise<unknown>[] = [];
  (globalThis as { EdgeRuntime?: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { waited.push(p); } };
  const ctx = await import('./context.ts');
  Object.assign(ctx.admin, { from: w.from, rpc: w.rpc });   // the handler's own client, pointed at the recorder
  const { profileActions } = await import('./actions/profile.ts');
  const quiet = console.error; console.error = () => {};
  try {
    const res = await profileActions({ req: new Request('http://127.0.0.1/', { method: 'POST', headers: { 'x-forwarded-for': '192.0.2.10', 'user-agent': 'zz-test' } }),
      email: EMAIL, action: 'accept_terms', body: { action: 'accept_terms', full_name: 'Zz Demo Person' } } as never);
    const findingsBeforeWait = w.rpcs.filter((r) => r.fn === 'fn_it_engineer_finding_upsert').length;
    await Promise.all(waited);
    return { status: res!.status, j: await res!.json(), waited: waited.length, findingsBeforeWait };
  } finally { console.error = quiet; }
}

Deno.test('supplier_api accept_terms: a write cancelled three times answers 503 terms_not_recorded and files the IT finding in the background', async () => {
  const w = world(true);
  const r = await accept(w);
  assertEquals(r.status, 503);
  assertEquals(r.j.code, 'terms_not_recorded');
  assert(!r.j.ok, 'never ok');
  assertEquals(w.writes.length, 3, 'three tries of the same write');
  assertEquals(r.waited, 1, 'the finding is handed to EdgeRuntime.waitUntil, after the answer');
  const f = w.rpcs.filter((x) => x.fn === 'fn_it_engineer_finding_upsert');
  assertEquals(f.length, 1, 'the IT seat is told once');
  assertEquals(f[0].args.p_issue_key, 'terms_not_recorded:supplier_portal');
  assertMatch(String((f[0].args.p_evidence as Record<string, unknown>).reason), /statement timeout/);
  assert(!JSON.stringify(f[0].args).includes(EMAIL), 'the finding carries no e-mail address');
});

Deno.test('supplier_api accept_terms: a write that lands files no finding', async () => {
  const w = world(false);
  const r = await accept(w);
  assertEquals(r.status, 200);
  assertEquals(r.j.ok, true);
  assertEquals(w.rpcs.filter((x) => x.fn === 'fn_it_engineer_finding_upsert').length, 0);
});
