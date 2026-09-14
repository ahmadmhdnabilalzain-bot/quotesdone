// A COMPANY IS NEVER ROUTED THROUGH AN APPROVAL CHAIN — founder, 14 Sep 2026:
//   "i think its better just to remove the approvals tab. cause even if a company signed up, we
//    don't wanna interfere in their approvals process and they are treated like normal individuals"
//
// What this guards, and why each half exists:
//   1. SOURCE (always runs, CI included). No edge function calls the dropped approval routines or
//      reads the dropped tables, and the customer portal has no Approvals destination — not in the
//      sidebar, not in the mobile More menu (both built from PortalShell's NAV_GROUPS), not as an
//      alert target, not as a module. A revived call would 500 at run time against a routine that
//      no longer exists; this fails first.
//   2. PRODUCTION (skips without a token, like org_identity_coverage). The award path — triggers on
//      inquiries, quotes and transactions — carries no trigger whose body mentions an approval, no
//      routine anywhere reads the dropped objects, and the objects themselves are gone. Before the
//      drop, an award by a customer who owned an organisation with a matching policy fired
//      trg_approval_raise_on_award; after it, that customer's award runs through exactly the same
//      triggers as an individual's, which is what the first query asserts.
//
// Patterns are anchored on call shapes (rpc('…'), .from('…'), id: '…'), not on words, so the
// comments that explain the removal cannot match them.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';

const walk = (dir, out = []) => {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) { if (n !== 'node_modules') walk(p, out); }
    else if (/\.(ts|tsx|mjs|js)$/.test(n)) out.push(p);
  }
  return out;
};
const read = (p) => readFileSync(p, 'utf8');

test('no edge function calls an approval routine or reads an approval/organisation table', () => {
  const bad = [];
  for (const f of walk('supabase/functions')) {
    const s = read(f);
    if (/rpc\(\s*['"]fn_approval_/.test(s)) bad.push(`${f}: rpc to fn_approval_*`);
    if (/\.from\(\s*['"](procurement_approval_(policy|request)|customer_organization(_member)?|v_approval_trace)['"]/.test(s)) bad.push(`${f}: reads a dropped table`);
    if (/kind:\s*['"]approval_due['"]/.test(s)) bad.push(`${f}: emits an approval_due alert`);
  }
  assert.deepEqual(bad, []);
});

test('the customer portal has no Approvals destination anywhere', () => {
  const bad = [];
  for (const f of walk('src')) {
    const s = read(f);
    if (/<ApprovalChain\b|import\s*\{[^}]*\bApprovalChain\b/.test(s)) bad.push(`${f}: mounts ApprovalChain`);
    if (/\bmod_approvals\b/.test(s)) bad.push(`${f}: mod_approvals label`);
    if (/id:\s*['"]approvals['"]|setView\(\s*['"]approvals['"]|\[\s*['"]approvals['"]\s*,/.test(s)) bad.push(`${f}: approvals view id`);
  }
  assert.equal(existsSync('src/components/portal/approvals/ApprovalChain.tsx'), false, 'ApprovalChain.tsx must stay deleted');
  assert.deepEqual(bad, []);
});

const TOKEN_FILE = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(TOKEN_FILE) ? read(TOKEN_FILE) : '')).trim();

test('production: an award runs through no approval trigger and the approval objects are gone', { skip: !token && 'no SUPABASE_ACCESS_TOKEN (expected in CI)' }, async () => {
  const query = `select json_build_object(
    'award_path_approval_triggers', (select count(*) from pg_trigger t join pg_proc f on f.oid = t.tgfoid
        where not t.tgisinternal and t.tgrelid in ('public.inquiries'::regclass, 'public.quotes'::regclass, 'public.transactions'::regclass)
          and (t.tgname ilike '%approval%' or f.prosrc ilike '%approval_request%' or f.prosrc ilike '%approval_polic%')),
    'readers', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and (p.prosrc ilike '%procurement_approval%' or p.prosrc ilike '%customer_organization%'
          or p.prosrc ~ 'fn_approval_(list|decide|policy_match|raise_on_award)')),
    'objects', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public'
        and c.relname in ('procurement_approval_policy','procurement_approval_request','customer_organization','customer_organization_member','v_approval_trace'))
  ) as r`;
  const res = await fetch('https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query', {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  assert.equal(res.status < 300, true, `management API answered ${res.status}`);
  const r = (await res.json())[0].r;
  assert.deepEqual(r, { award_path_approval_triggers: 0, readers: 0, objects: 0 });
});
