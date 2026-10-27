// NOTHING IN THE DELIVERABILITY TEST CAN TURN THE SUPPLIER INVITATIONS ON (27 Oct 2026; it_engineer; ledger 1312, 1340).
//
// Resuming invitations at >= 80% Outlook inbox is a real send to real suppliers, so it stays the founder's
// confirmation. The test loop only records and reports. This reads the function's source and its SQL file and fails
// if either names the invitation switches at all, or writes any app_secrets key other than its own three.
// Test files and fixtures are not read (they are not deployed and this file names the switches to look for them).
//
//   deno test --no-lock --allow-read=. supabase/functions/deliverability_test/no_invitation_switch_is_written.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';

const HERE = new URL('./', import.meta.url);
const SQL = new URL('../../../scripts/sql/the_it_engineer_runs_the_glockapps_test_and_files_its_verdict_without_the_founder.sql', import.meta.url);
// built from parts so a grep for the key names finds the code that writes them, not this test
const SWITCHES = new RegExp(['invite' + '_enab', 'wa_supplier_invite' + '_golive', 'supplier_outreach' + '_golive', 'invite_m365' + '_enabled'].join('|'), 'i');
const OWN_KEYS = ['deliverability_retest_weekly', 'deliverability_test_request', 'cred_fn_deliverability_test'];

function sources(): { name: string; text: string }[] {
  const out: { name: string; text: string }[] = [];
  for (const e of Deno.readDirSync(HERE)) {
    if (e.isFile && e.name.endsWith('.ts') && !e.name.endsWith('.test.ts')) out.push({ name: e.name, text: Deno.readTextFileSync(new URL(e.name, HERE)) });
  }
  return out;
}

Deno.test('the function source never names an invitation switch', () => {
  const files = sources();
  assert(files.some((f) => f.name === 'index.ts') && files.some((f) => f.name === 'handler.ts'), 'the scan found the function');
  for (const f of files) assert(!SWITCHES.test(f.text), `${f.name} names an invitation switch: ${f.text.match(SWITCHES)?.[0]}`);
});

Deno.test('the function writes app_secrets in exactly one place: deleting its own one-shot request flag', () => {
  const writes: string[] = [];
  for (const f of sources()) {
    for (const m of f.text.matchAll(/from\(\s*['"]app_secrets['"]\s*\)\s*\.(update|upsert|insert|delete)\b[^\n;]*/g)) writes.push(`${f.name}: ${m[0]}`);
    // an rpc that could write a setting would bypass the scan above
    assert(!/rpc\(\s*['"]fn_[a-z_]*(campaign|invite_(enable|resume|start))[a-z_]*['"]/i.test(f.text), `${f.name} calls a campaign routine`);
  }
  assertEquals(writes.length, 1, writes.join('\n'));
  assert(/\.delete\(\)\.eq\('key', REQUEST_KEY\)/.test(writes[0]), writes[0]);
});

Deno.test('the SQL file never names an invitation switch and writes only its own app_secrets keys', () => {
  const text = Deno.readTextFileSync(SQL);
  assert(!SWITCHES.test(text), 'the SQL file names an invitation switch: ' + text.match(SWITCHES)?.[0]);
  const keys = [...text.matchAll(/(?:insert\s+into\s+public\.app_secrets\s*\(key,\s*value\)\s*values\s*\(\s*'([a-z0-9_]+)'|update\s+public\.app_secrets\b[^;]*?key\s*=\s*'([a-z0-9_]+)'|delete\s+from\s+public\.app_secrets\b[^;]*?key\s*=\s*'([a-z0-9_]+)')/gi)]
    .map((m) => m[1] || m[2] || m[3]);
  assert(keys.length >= 2, 'the scan found the file\'s own writes: ' + keys.join(','));
  for (const k of keys) assert(OWN_KEYS.includes(k), `the SQL file writes app_secrets key ${k}`);
  assert(!/update\s+public\.app_secrets/i.test(text), 'the SQL file updates an app_secrets row it does not own');
});
