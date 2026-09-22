// DELETE EDGE FUNCTIONS FROM PRODUCTION — the counterpart to deploy_functions.mjs.
//
// On 8 September 2026, 137 edge functions were removed from production by hand, because the
// repository had a deployer and no remover. Eight of them were the customer and supplier portals,
// and every button on /me and /portal returned 404 for about ninety minutes. A hand-run curl leaves
// no record of what was deleted, no check that it SHOULD be, and nothing to read afterwards.
//
// THE GUARD THAT MATTERS: a slug is deletable only if supabase/functions/<slug>/index.ts is ABSENT
// from the working tree. The repository is the statement of intent; production is the consequence.
// If the file is still there, deleting the deployment is not a removal, it is an outage — that is
// exactly the shape of the portal incident, where production lost what the app still called.
//
// It also refuses a slug that is still named in function_owner without being absent, and prints what
// it is about to do before doing it. --confirm is required; without it this is a dry run.
//
//   node scripts/delete_functions.mjs --ref=htdblwldjkcgjvmqkbeh os_api os_ops        # dry run
//   node scripts/delete_functions.mjs --ref=htdblwldjkcgjvmqkbeh --confirm os_api ... # delete
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const args = process.argv.slice(2);
const ref = (args.find((a) => a.startsWith('--ref=')) || '').split('=')[1];
const confirm = args.includes('--confirm');
const slugs = args.filter((a) => !a.startsWith('--'));

if (!ref || !slugs.length) {
  console.error('usage: node scripts/delete_functions.mjs --ref=<project> [--confirm] <slug>...');
  process.exit(2);
}

const TOKEN = process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(join(homedir(), '.supabase', 'access-token'))
      ? readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim() : '');
if (!TOKEN) { console.error('no SUPABASE_ACCESS_TOKEN'); process.exit(2); }

const api = async (path, method = 'GET') => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}${path}`, {
    method, headers: { Authorization: `Bearer ${TOKEN}` },
  });
  return { status: r.status, text: await r.text() };
};

const live = new Set(JSON.parse((await api('/functions')).text).map((f) => f.slug));

const refused = [];
const doable = [];
for (const s of slugs) {
  if (existsSync(`supabase/functions/${s}/index.ts`)) {
    refused.push(`${s}: still present in the repository. Delete the source first — removing a live `
      + `deployment the app still calls is an outage, not a removal.`);
  } else if (!live.has(s)) {
    console.log(`  already absent from production: ${s}`);
  } else {
    doable.push(s);
  }
}

if (refused.length) {
  console.error('\nREFUSED:');
  for (const r of refused) console.error('  ' + r);
  process.exit(1);
}

console.log(`\n${doable.length} function(s) to delete from ${ref}:`);
for (const s of doable) console.log('  ' + s);

if (!confirm) {
  console.log('\nDRY RUN. Re-run with --confirm to delete.');
  process.exit(0);
}

let ok = 0;
for (const s of doable) {
  const r = await api(`/functions/${s}`, 'DELETE');
  const good = r.status >= 200 && r.status < 300;
  if (good) ok++;
  console.log(`  ${good ? 'deleted' : 'FAILED'}  ${s}  (HTTP ${r.status})${good ? '' : ' ' + r.text.slice(0, 160)}`);
}
console.log(`\nDELETED ${ok}/${doable.length}`);
process.exit(ok === doable.length ? 0 : 1);
