// supplier_api `me` READS IN ONE WAVE AND ANSWERS AS BEFORE (11 Nov 2026, customer_support; registration certification free round 6).
// lib/me_row.ts supplierOf: the row and the three app_secrets keys are issued together, terms_version is read once, and
// terms_current / terms_stands are what the handler computed before (supplierAcceptanceStands).
// Known-bad control: the old handler's order (row, then terms_version, then the acceptance's two keys) puts one read in
// flight at a time, and the first test fails on it.
//   deno test --no-lock supabase/functions/supplier_api/me_row.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { ME_COLUMNS, supplierOf } from './lib/me_row.ts';
import { supplierAcceptanceStands } from '../_shared/supplier_terms.ts';

function world(row: Record<string, unknown> | null, secrets: Record<string, string | null>) {
  let now = 0, most = 0; const asked: string[] = []; let cols = '';
  const slow = async <T>(f: () => T): Promise<T> => { now++; most = Math.max(most, now); await new Promise((r) => setTimeout(r, 5)); try { return f(); } finally { now--; } };
  const admin = { from: (n: string) => { assertEquals(n, 'leads'); const q = { select: (c: string) => { cols = c; return q; }, eq: () => q, maybeSingle: () => slow(() => ({ data: row, error: null })) }; return q; } };
  const sec = (k: string) => { asked.push(k); return slow(() => secrets[k] ?? null); };
  return { admin, sec, asked, most: () => most, cols: () => cols };
}
const ROW = { id: 7, company_name: 'ZZ DEMO Me Row LLC', claimed_by: 'qd-me@example.invalid', accepted_terms_version: 'v16' };

Deno.test('the row and the terms keys are read in one wave, terms_version once', async () => {
  const w = world(ROW, { terms_version: 'v17', supplier_terms_version: '', supplier_terms_carries_from: 'v16' });
  const s = await supplierOf(w.admin, 'qd-me@example.invalid', w.sec);
  assert(w.most() >= 3, `only ${w.most()} read(s) in flight together: \`me\` waits on each in turn`);
  assertEquals(w.asked.filter((k) => k === 'terms_version').length, 1, 'terms_version read twice');
  assertEquals(w.cols(), ME_COLUMNS);
  assertEquals([s?.id, s?.terms_current, s?.terms_stands], [7, 'v17', true]);
});

Deno.test('terms_current and terms_stands are what the handler answered before, in every case', async () => {
  const cases: [string | null, Record<string, string | null>][] = [
    ['v16', { terms_version: 'v17', supplier_terms_version: 'v17', supplier_terms_carries_from: '' }],
    ['v17', { terms_version: 'v12', supplier_terms_version: 'v17', supplier_terms_carries_from: null }],
    ['v16', { terms_version: 'v17', supplier_terms_version: null, supplier_terms_carries_from: 'v15, v16' }],
    [null, { terms_version: 'v17', supplier_terms_version: null, supplier_terms_carries_from: null }],
    ['v17', { terms_version: null, supplier_terms_version: null, supplier_terms_carries_from: null }],
  ];
  for (const [accepted, secrets] of cases) {
    const w = world({ ...ROW, accepted_terms_version: accepted }, secrets);
    const s = await supplierOf(w.admin, 'qd-me@example.invalid', w.sec);
    const before = await supplierAcceptanceStands(async (k) => secrets[k] ?? null, accepted);
    assertEquals([s?.terms_current, s?.terms_stands], [secrets.terms_version ?? null, before], JSON.stringify({ accepted, secrets }));
  }
});

Deno.test('no company: null, as `me` answered', async () => {
  const w = world(null, { terms_version: 'v17' });
  assertEquals(await supplierOf(w.admin, 'qd-none@example.invalid', w.sec), null);
});

// 12 Nov 2026 (review of the portal shell): leads.source is read to answer `listed`, and never reaches the browser raw.
Deno.test('me answers listed as a boolean and never the raw leads.source', async () => {
  for (const [source, listed] of [['self_registered', false], ['apify_2026-06', true], [null, null]] as const) {
    const admin = { from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { id: 1, company_name: 'ZZ DEMO Me Row', accepted_terms_version: null, source }, error: null }) }) }) }) };
    const row = await supplierOf(admin as never, 'zz-demo-me@example.invalid', () => Promise.resolve(null)) as Record<string, unknown>;
    assertEquals([row.listed, 'source' in row], [listed, false], String(source));
  }
});
