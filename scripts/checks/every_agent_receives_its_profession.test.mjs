// EVERY AGENT RECEIVES ITS PROFESSION.
//
// Knowledge audit, 6 Sep 2026 (docs/knowledge_audit/company_wide.md §3b): fn_agent_context's "LAYER 2 -
// YOUR PROFESSIONAL EXPERTISE" carried zero profession rows for 54 of 54 active employees, because its
// admit guard (~8,200 chars) was evaluated after 11-13k chars of standing blocks; LAYER 3 (live state)
// and LAYER 4 (lessons) sat past the 19,500 characters fn_agent_context_capped keeps for agent_brain;
// the four T&C hard rules were in no head; and the retrieval exam had written supplier-category route
// YAML into non-marketplace employees as "what the organisation has learned". Each of those is a
// mechanism, each was fixed by mechanism (scripts/sql/every_agent_receives_its_profession.sql and its
// siblings), and this check is what keeps them fixed:
//
//   1. for EVERY active employee, fn_agent_context(key, 22000) carries at least one profession body
//      under LAYER 2 (a "## " row, not just the heading);
//   2. the four hard rules - reveal fee, top-3 report, supplier non-response, AED 15,000 / 3x
//      anti-circumvention - are in every head;
//   3. LAYER 3 and LAYER 4 headings sit inside the first 19,500 characters;
//   4. no non-marketplace employee's LAYER 4 carries a category pack (the route files are the only
//      rows whose text names an opcat- route or a category_specialists path), and no such employee
//      holds a non-quarantined category-pack fill at all.
//
// READ-ONLY against production, one context per call (each ~0.3-0.6 s under an 8 s statement timeout;
// a lateral with several position() references re-evaluates the STABLE function per reference, which
// is why the positions are computed here rather than in SQL).
//
//   node --test scripts/checks/every_agent_receives_its_profession.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../phase_c/lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

const HEAD_KEEP = 19500;
const L2 = '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE';
const L1 = '# LAYER 1 - COMPANY KNOWLEDGE';
const L3 = '# LAYER 3 - LIVE OPERATIONAL STATE';
const L4 = '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED';
const RULES = ['REVEAL FEE', 'TOP-3 COMPARISON REPORT', 'SUPPLIER NON-RESPONSE', 'ANTI-CIRCUMVENTION', 'AED 15,000', 'best THREE'];
const CATEGORY_PACK = /opcat-\d{3}|category_specialists\/routes\//;

async function rows(q) {
  const r = await sql(`set local statement_timeout = '8s'; ${q}`);
  return Array.isArray(r) ? r : [];
}
const pos = (s, m) => { const i = s.indexOf(m); return i < 0 ? 0 : i + 1; };

let agents = null;
const contexts = new Map();
async function load() {
  if (agents) return;
  agents = await rows(`select agent_key, department from public.org_agents where active and kind in ('brain','agent') order by department, agent_key`);
  for (const a of agents) {
    let ctx = null, err = null;
    for (let t = 0; t < 3 && ctx === null; t++) {
      try { const r = await rows(`select public.fn_agent_context('${a.agent_key.replace(/'/g, "''")}', 22000) ctx`); ctx = r[0]?.ctx ?? null; }
      catch (e) { err = e; }
    }
    contexts.set(a.agent_key, ctx === null ? { error: String(err?.message || 'no context') } : { ctx });
  }
}

test('every active employee gets a profession body under LAYER 2', { skip: SKIP }, async () => {
  await load();
  assert.ok(agents.length >= 50, `expected the ~54 active employees, found ${agents.length}`);
  const bad = [];
  for (const a of agents) {
    const c = contexts.get(a.agent_key);
    if (!c.ctx) { bad.push(`${a.agent_key}: ${c.error}`); continue; }
    const l2 = pos(c.ctx, L2), l1 = pos(c.ctx, L1);
    const body = l2 && l1 && l1 > l2 ? c.ctx.slice(l2 - 1 + L2.length, l1 - 1) : '';
    if (!/## /.test(body)) bad.push(`${a.agent_key} (${a.department}): LAYER 2 has no profession row`);
  }
  assert.deepEqual(bad, [], 'employees whose prompt carries no professional expertise:\n  ' + bad.join('\n  '));
});

test('the four hard T&C rules are in every head', { skip: SKIP }, async () => {
  await load();
  const bad = [];
  for (const a of agents) {
    const c = contexts.get(a.agent_key);
    if (!c.ctx) { bad.push(`${a.agent_key}: ${c.error}`); continue; }
    const missing = RULES.filter((m) => !c.ctx.includes(m));
    if (missing.length) bad.push(`${a.agent_key}: missing ${missing.join(', ')}`);
  }
  assert.deepEqual(bad, [], 'heads without the four hard rules:\n  ' + bad.join('\n  '));
});

test('LAYER 3 and LAYER 4 sit inside the 19,500 characters the capped path keeps', { skip: SKIP }, async () => {
  await load();
  const bad = [];
  for (const a of agents) {
    const c = contexts.get(a.agent_key);
    if (!c.ctx) { bad.push(`${a.agent_key}: ${c.error}`); continue; }
    const l3 = pos(c.ctx, L3), l4 = pos(c.ctx, L4);
    if (l3 === 0 || l3 > HEAD_KEEP) bad.push(`${a.agent_key} (${a.department}): LAYER 3 at ${l3}`);
    if (l4 === 0 || l4 > HEAD_KEEP) bad.push(`${a.agent_key} (${a.department}): LAYER 4 at ${l4}`);
  }
  assert.deepEqual(bad, [], 'live state or lessons outside the run-time head:\n  ' + bad.join('\n  '));
});

test('no non-marketplace employee carries a category pack in LAYER 4', { skip: SKIP }, async () => {
  await load();
  const bad = [];
  for (const a of agents) {
    if (a.department === 'marketplace') continue;
    const c = contexts.get(a.agent_key);
    if (!c.ctx) { bad.push(`${a.agent_key}: ${c.error}`); continue; }
    const l4 = pos(c.ctx, L4);
    if (!l4) continue;
    const tail = c.ctx.slice(l4 - 1);
    const end = tail.indexOf('\n# ', L4.length);
    const layer4 = end < 0 ? tail : tail.slice(0, end);
    if (CATEGORY_PACK.test(layer4)) bad.push(`${a.agent_key} (${a.department})`);
  }
  assert.deepEqual(bad, [], 'LAYER 4 still carries a supplier-category route file for:\n  ' + bad.join('\n  '));

  // the mechanism behind it: no served category-pack fill outside marketplace
  const r = await rows(`
    select k.agent_key, count(*) n from public.agent_knowledge k
     where k.layer = 'experience' and k.source_ref like 'ops_knowledge:%'
       and coalesce(k.validation_status,'') <> 'quarantined'
       and k.agent_key not like 'cat:%'
       and not exists (select 1 from public.org_agents a where a.agent_key = k.agent_key and a.department = 'marketplace')
       and exists (select 1 from public.ops_knowledge o where o.record_id = substring(k.source_ref from 15) and o.scope_type = 'category')
     group by 1 order by 1 limit 20`);
  assert.deepEqual(r, [], 'served category-pack fills outside marketplace (the exam must never write these):\n' + JSON.stringify(r, null, 1));
});
