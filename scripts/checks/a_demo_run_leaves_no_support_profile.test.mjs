// A DEMO RUN LEAVES NO SUPPORT PROFILE BEHIND (19 Oct 2026).
//
// support_customer_profile points at customers and leads ON DELETE SET NULL, and support_case points at the
// profile with no cascade. demo_factory teardown used to "defer" the profile on 23503 and then delete the
// customer, which nulled the link: 29 orphaned @example.invalid profiles by 19 Oct. This fails if teardown stops
// removing the profile (and its case) before the customers and leads it names, and, with a management token,
// if production holds any demo profile whose customer is gone.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const src = readFileSync(root + 'scripts/lib/demo_factory.mjs', 'utf8');
const body = src.slice(src.indexOf('export async function teardown('));

test('teardown removes the support case and profile before the leads and customers they name', () => {
  const at = (label) => body.indexOf(`['${label}',`);
  for (const l of ['support_case', 'support_customer_profile', 'leads', 'customers']) assert.ok(at(l) > 0, `teardown has no '${l}' step`);
  assert.ok(at('support_case') < at('support_customer_profile'), 'the case must go before its profile');
  assert.ok(at('support_customer_profile') < at('leads'), 'the profile must go before the leads delete nulls its link');
  assert.ok(at('support_customer_profile') < at('customers'), 'the profile must go before the customers delete nulls its link');
  assert.match(body, /email like 'qd-\$\{tag\}-%@example\.%'\)`/, 'the profile scope lost the run address');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: no demo support profile outlives its customer', { skip: hasToken ? false : 'no Supabase management token in this environment' }, async () => {
  const { mgmtRead, PROD_REF } = await import('../lib/qd_guard.mjs');
  const rows = await mgmtRead(PROD_REF, `select id, email from public.support_customer_profile sp
     where sp.email like '%@example.invalid' and not exists (select 1 from public.customers c where c.id = sp.customer_id)
       and sp.created_at < now() - interval '6 hours'`);
  assert.equal(rows.length, 0, `orphaned demo support profiles: ${rows.map((r) => `${r.id} ${r.email}`).join(', ')}`);
});
