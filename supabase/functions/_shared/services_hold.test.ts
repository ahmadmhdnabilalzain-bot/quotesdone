// deno test --no-lock --allow-read supabase/functions/_shared/services_hold.test.ts
// Founder ledger 1469. Each test names the BAD behaviour it would catch (the "known-bad control").
import { assert, assertEquals, assertFalse, assertMatch } from 'jsr:@std/assert@1';
import { pendingFounderSubject, servicesHoldMail, SERVICES_UNCONFIRMED } from './services_hold_copy.ts';
import { rerunGateAfterConfirm } from './supplier_capability.ts';
// customer_api and supplier_api are index.ts plus modules since 9 Nov 2026: read the whole function, as the node checks do.
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

Deno.test('a services hold is told to confirm its services, never that someone is reviewing it', () => {
  const m = servicesHoldMail('ZZ DEMO Co');
  assertMatch(m.body, /Services tab/); assertMatch(m.body, /Confirm my services/);
  // known-bad control: the text every other pending supplier gets
  assertFalse(/reviewing/i.test(m.body), 'the old "sales engineer is reviewing" wording must not reach this supplier');
  assertFalse(/[؀-ۿ]/.test(m.subject + m.body), 'suppliers are written to in English');
});

Deno.test('the founder is not told "auto-approve is off" for a services hold, and still is for the real case', () => {
  assertFalse(/auto-approve/i.test(pendingFounderSubject(SERVICES_UNCONFIRMED)));
  assertMatch(pendingFounderSubject(null), /auto-approve is off/);           // control: the unchanged case
  assertMatch(pendingFounderSubject('documents_being_read'), /auto-approve is off/);
});

Deno.test('save_profile routes a services hold through the helpers', async () => {
  const src = functionSource('supplier_api');
  assertMatch(src, /decision === 'pending' && v\.reason === SERVICES_UNCONFIRMED\s*\?\s*servicesHoldMail\(name\)/);
  assertMatch(src, /pendingFounderSubject\(v\.reason\)/);
});

// A fake admin whose rpc answers from a script and whose tables record inserts.
function fake(held: string | null, rpcAnswers: Array<{ data?: unknown; error?: { message: string } }>) {
  const log = { rpc: 0, inserted: [] as unknown[] };
  const admin = {
    from(t: string) {
      if (t === 'leads') return { select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { licence_gate_reason: held } }) }) }) };
      return { insert: (row: unknown) => { log.inserted.push(row); return Promise.resolve({ error: null }); } };
    },
    rpc: () => Promise.resolve(rpcAnswers[Math.min(log.rpc++, rpcAnswers.length - 1)]),
  };
  return { admin, log };
}

Deno.test('the gate re-run is skipped for a supplier not held for its services', async () => {
  const { admin, log } = fake('licence_unreadable', []);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'not_held'); assertEquals(log.rpc, 0);
});

Deno.test('a held supplier is decided by the confirm', async () => {
  const { admin, log } = fake(SERVICES_UNCONFIRMED, [{ data: { ok: true, decision: 'approved' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'approved'); assertEquals(log.rpc, 1);
});

Deno.test('a timeout is answered queued at once, never retried for another 8 s, and is on the sales engineer queue (known-bad: 10 Nov, two 8 s timeouts back to back)', async () => {
  const { admin, log } = fake(SERVICES_UNCONFIRMED, [{ error: { message: 'canceling statement due to statement timeout' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'queued');
  assertEquals(log.rpc, 1, 'a timeout is not retried: the minute tick re-runs it');
  assertEquals(log.inserted.length, 1, 'the failure is on the sales engineer queue');
  assert(JSON.stringify(log.inserted[0]).includes('statement timeout'));
});

Deno.test('the gate answering queued (a row lock it could not take in 3 s) reaches the supplier as queued', async () => {
  const { admin, log } = fake(SERVICES_UNCONFIRMED, [{ data: { ok: true, queued: true, decision: 'queued' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'queued'); assertEquals(log.rpc, 1); assertEquals(log.inserted.length, 0);
});

Deno.test('the confirm calls the bounded gate, never the unbounded one', () => {
  const src = Deno.readTextFileSync(new URL('./supplier_capability.ts', import.meta.url));
  const body = src.slice(src.indexOf('export async function rerunGateAfterConfirm'), src.indexOf('export async function capabilityConfirm'));
  assertMatch(body, /rpc\('fn_sales_engineer_verifies_supplier_now'/);
  assertFalse(/rpc\('fn_sales_engineer_verifies_supplier'/.test(body), 'the unbounded gate waits on any lock for as long as the statement lives');
});

Deno.test('any other rpc {error} is retried once, then surfaced and queued: never silent', async () => {
  const { admin, log } = fake(SERVICES_UNCONFIRMED, [{ error: { message: 'connection reset' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'failed');
  assertEquals(log.rpc, 2, 'one retry');
  assertEquals(log.inserted.length, 1, 'the failure is on the sales engineer queue');
});

Deno.test('a first-try error that the retry clears still approves', async () => {
  const { admin, log } = fake(SERVICES_UNCONFIRMED, [{ error: { message: 'blip' } }, { data: { ok: true, decision: 'approved' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'approved'); assertEquals(log.rpc, 2); assertEquals(log.inserted.length, 0);
});

Deno.test('an answer with ok:false is a failure too', async () => {
  const { admin } = fake(SERVICES_UNCONFIRMED, [{ data: { ok: false, error: 'lead_not_found' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'failed');
});
