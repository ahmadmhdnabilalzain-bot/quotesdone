// registered_locale.test.ts — the one language helper, including what happens when the lookup fails.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/registered_locale.test.ts
// ZZ DEMO addresses only; the client is a recorder, so nothing reaches a database or a person.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { asLocale, documentLocale, registeredLocale, LOOKUP_FAILED_ISSUE } from './registered_locale.ts';

// Finding 4 (customer audit, 21 Sep 2026): the Arabic-copy button of an English-registered customer
// was served the English PDF because quote_pdf read customers.locale only.
Deno.test('a document asked for in Arabic is Arabic even for an English-registered customer; junk falls back', () => {
  assertEquals(documentLocale('ar', 'en'), 'ar');
  assertEquals(documentLocale('en', 'ar'), 'en');
  assertEquals(documentLocale(undefined, 'ar'), 'ar');
  assertEquals(documentLocale('fr', 'en'), 'en');
});

function fake(answer: { data?: unknown; error?: { message: string } } | 'throw') {
  const rpcs: { name: string; args: any }[] = []; const inserts: { table: string; row: any }[] = [];
  const admin = {
    rpc: async (name: string, args: any) => {
      rpcs.push({ name, args });
      if (name === 'fn_registered_locale') { if (answer === 'throw') throw new Error('network down'); return { data: answer.data ?? null, error: answer.error ?? null }; }
      return { data: {}, error: null };
    },
    from: (table: string) => ({ insert: async (row: any) => { inserts.push({ table, row }); return { error: null }; } }),
  };
  return { admin, rpcs, inserts };
}
const WHO = { role: 'customer', customerId: 'c-zzdemo', email: 'zz.demo.buyer@example.invalid' };

Deno.test('asLocale: ar and ar-AE are Arabic, anything else English', () => {
  assertEquals([asLocale('ar'), asLocale('ar-AE'), asLocale('AR'), asLocale('en'), asLocale(null), asLocale('fr')], ['ar', 'ar', 'ar', 'en', 'en', 'en']);
});

Deno.test('a registered row decides, whatever the sign-up language says', async () => {
  const f = fake({ data: 'ar' });
  assertEquals(await registeredLocale(f.admin, WHO, 'en'), 'ar');
  assertEquals(f.inserts.length, 0);
});

Deno.test('nobody registered yet: the sign-up language applies, and it is not a fault', async () => {
  const f = fake({ data: null });
  assertEquals(await registeredLocale(f.admin, WHO, 'ar'), 'ar');
  assertEquals(f.inserts.length, 0);
  assertEquals(f.rpcs.filter((r) => r.name === 'fn_it_engineer_finding_upsert').length, 0);
});

for (const [label, answer] of [['returns an error', { error: { message: 'permission denied for function fn_registered_locale' } }], ['throws', 'throw']] as const) {
  Deno.test(`the lookup ${label}: the message still goes, a warning and an IT finding are recorded, no personal data`, async () => {
    const f = fake(answer as never);
    assertEquals(await registeredLocale(f.admin, WHO, 'ar'), 'ar');
    const run = f.inserts.find((i) => i.table === 'agent_runs');
    assert(run, 'no agent_runs warning');
    assertEquals(run.row.status, 'warn');
    assertEquals(run.row.counts.role, 'customer');
    const finding = f.rpcs.find((r) => r.name === 'fn_it_engineer_finding_upsert');
    assert(finding, 'no IT engineer finding');
    assertEquals(finding.args.p_issue_key, LOOKUP_FAILED_ISSUE);
    const written = JSON.stringify([run.row, finding.args]);
    assert(!written.includes('example.invalid') && !written.includes('c-zzdemo'), 'an address or id was recorded: ' + written);
  });
}
