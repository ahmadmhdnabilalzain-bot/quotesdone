// THE E-MAIL BAN IS READ BESIDE THE COMPANY (it_engineer, 12 Nov 2026; regcert run 50123afa J5).
// The two sanctions reads by address need only the signed-in e-mail, so index.ts starts them before it awaits the company
// read, and the gate awaits that promise after the by-lead read. On main the e-mail reads were issued only after the
// company read AND the by-lead read had returned: one extra serial hop (~40 ms in the edge_logs timeline of the slow
// 03:00:05Z dashboard) on every supplier_portal request. index.ts calls Deno.serve on import, so this reads its source,
// as overview.test.ts does.
//   deno test supabase/functions/supplier_portal/the_email_ban_is_read_beside_the_company.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';

const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url))
  .split('\n').map((l) => l.replace(/\/\/.*$/, '')).join('\n');

Deno.test('the e-mail ban read is started before the company read is awaited', () => {
  const start = src.indexOf('sanctionedEmail(admin, email)');
  const company = src.indexOf("await admin.from('leads')");
  assert(start > 0, 'index.ts no longer reads the e-mail ban');
  assert(company > 0, 'index.ts no longer reads the company');
  assert(start < company, 'the e-mail ban read waits behind the company read again (one serial hop on every request)');
});

Deno.test('the gate still refuses on either ban, and awaits the started read rather than issuing a second one', () => {
  assertEquals((src.match(/sanctionedEmail\(/g) ?? []).length, 1, 'expected exactly one call of sanctionedEmail');
  assert(/if \(await sanctionedLead\(admin, sup\.id\) \|\| await emailBanned\) return J\(SANCTIONED_REFUSAL, 403\);/.test(src),
    'the 403 gate does not await both the by-lead read and the started e-mail read');
  assert(/emailBanned\.catch\(\(\) => \{\}\)/.test(src), 'an early return (no_company) would leave the started read unobserved');
});
