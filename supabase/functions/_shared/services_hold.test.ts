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

Deno.test('an rpc {error} is retried once, then surfaced and queued: never silent (known-bad: the old code ignored it)', async () => {
  const { admin, log } = fake(SERVICES_UNCONFIRMED, [{ error: { message: 'statement timeout' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'failed');
  assertEquals(log.rpc, 2, 'one retry');
  assertEquals(log.inserted.length, 1, 'the failure is on the sales engineer queue');
  assert(JSON.stringify(log.inserted[0]).includes('statement timeout'));
});

Deno.test('a first-try error that the retry clears still approves', async () => {
  const { admin, log } = fake(SERVICES_UNCONFIRMED, [{ error: { message: 'blip' } }, { data: { ok: true, decision: 'approved' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'approved'); assertEquals(log.rpc, 2); assertEquals(log.inserted.length, 0);
});

Deno.test('an answer with ok:false is a failure too', async () => {
  const { admin } = fake(SERVICES_UNCONFIRMED, [{ data: { ok: false, error: 'lead_not_found' } }]);
  assertEquals(await rerunGateAfterConfirm(admin, 7), 'failed');
});
