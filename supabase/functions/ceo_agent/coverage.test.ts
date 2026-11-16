// coverageAction: the objective and the limits at the CEO's door (ledger 1701, 1696). No network: the routines are stubbed.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { coverageAction, type Db } from './coverage.ts';

function dbOf(answers: Record<string, unknown> = {}, errors: Record<string, string> = {}) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const db: Db = {
    rpc: (fn, args) => { calls.push({ fn, args }); return Promise.resolve({ data: answers[fn] ?? null, error: errors[fn] ? { message: errors[fn] } : null }); },
    recentDecisions: (limit) => { calls.push({ fn: 'ceo_supply_decision', args: { limit } }); return Promise.resolve({ data: [{ kind: 'run' }], error: null }); },
  };
  return { db, calls };
}

Deno.test('coverage: the founder reads coverage, funnel, limits and decisions; nothing is written', async () => {
  const m = dbOf({ fn_supplier_coverage: { covered_suppliers: 1, target_suppliers: 30 }, fn_supplier_funnel_reading: { invited: 0 }, fn_company_limits: { daily_spend_aed: 30 } });
  const r = await coverageAction(m.db, 'founder', 'coverage', { days: 9999 });
  assertEquals(r?.status, 200);
  assertEquals((r?.body.coverage as Record<string, unknown>).covered_suppliers, 1);
  assertEquals(m.calls.map((c) => c.fn).sort(), ['ceo_supply_decision', 'fn_company_limits', 'fn_supplier_coverage', 'fn_supplier_funnel_reading']);
  assertEquals(m.calls.find((c) => c.fn === 'fn_supplier_funnel_reading')?.args.p_days, 365, 'the window is bounded');
});

Deno.test('coverage: a routine that fails is a 503 naming it, never an empty success', async () => {
  const r = await coverageAction(dbOf({}, { fn_supplier_coverage: 'function does not exist' }).db, 'ceo', 'coverage', {});
  assertEquals(r?.status, 503);
  assert(String(r?.body.detail).includes('does not exist'));
});

Deno.test('limit and target: only the CEO, only with a reason; the founder is told, not asked', async () => {
  for (const action of ['limit', 'target']) {
    const m = dbOf();
    const f = await coverageAction(m.db, 'founder', action, { key: 'daily_spend_aed', value_aed: 500, reason: 'a long enough reason for the change' });
    assertEquals(f?.status, 403);
    assertEquals(m.calls.length, 0, 'the founder\'s call writes nothing');
    assertEquals((await coverageAction(m.db, 'ceo', action, { reason: 'short' }))?.status, 400);
    assertEquals(m.calls.length, 0);
  }
  const m = dbOf({ fn_ceo_sets_company_limit: { ok: true, effective_at: '2026-11-16T10:00:00Z', in_force_now: 30 } });
  const r = await coverageAction(m.db, 'ceo', 'limit', { key: 'daily_spend_aed', value_aed: '120', reason: 'Two campaigns this week need room above AED 30.' });
  assertEquals(r?.status, 200);
  assertEquals(m.calls[0], { fn: 'fn_ceo_sets_company_limit', args: { p_key: 'daily_spend_aed', p_value_aed: 120, p_reason: 'Two campaigns this week need room above AED 30.' } });
  assertEquals(r?.body.in_force_now, 30, 'the value in force does not move today');
});

Deno.test('target: retire with null; the routine\'s refusal is a 400', async () => {
  const m = dbOf({ fn_ceo_sets_coverage_target: { ok: false, reason: 'no active trade zz' } });
  const r = await coverageAction(m.db, 'ceo', 'target', { trade: 'zz', target: null, reason: 'retire it: nobody asks for this trade in the UAE' });
  assertEquals(r?.status, 400);
  assertEquals(m.calls[0].args.p_target, null);
  assertEquals(m.calls[0].args.p_emirate, 'UAE');
  assertEquals(await coverageAction(m.db, 'ceo', 'board', {}), null, 'another action is not this door\'s');
});
