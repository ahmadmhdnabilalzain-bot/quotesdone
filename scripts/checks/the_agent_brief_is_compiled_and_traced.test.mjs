// The cached agent brief (knowledge/brief) must be compiled into the edge module the chats import, must
// carry the live document versions, and every regulation digest must carry a source URL and access date.
// Prevents: an edited .md that never reaches the agents, and a company figure drifting from company_facts.json.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { compileBrief, renderModule } from '../kb/compile_brief.mjs';

const read = (p) => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8');

test('generated module equals a fresh compile', () => {
  assert.equal(read('supabase/functions/_shared/brief.generated.ts'), renderModule(compileBrief()));
});

test('company brief cites the live Terms and Supplier Agreement versions and the figures in company_facts', () => {
  const facts = JSON.parse(read('src/content/company_facts.json'));
  const brief = read('knowledge/brief/company.md');
  assert.match(brief, new RegExp(`Customer Terms of Service \\*\\*${facts.documents.terms.version}\\*\\*`));
  assert.match(brief, new RegExp(`Supplier Agreement \\*\\*${facts.documents['supplier-agreement'].version}\\*\\*`));
  assert.ok(brief.includes(`**${facts.facts.reveal_fee_pct.value}%**`));
  assert.ok(brief.includes(`AED ${facts.facts.nonresponse_admin_fee_aed.value}`));
  assert.ok(brief.includes(`${facts.facts.late_interest_pct_pa.value}% p.a.`));
  assert.ok(brief.includes(`AED ${facts.facts.subscription_fee_aed.value.toLocaleString('en-US')} per year`));
});

test('every regulation digest names its sources and access date', () => {
  const dir = new URL('../../knowledge/brief/uae_regulations/', import.meta.url);
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.md'))) {
    const t = readFileSync(new URL(f, dir), 'utf8');
    assert.match(t, /https?:\/\//, `${f} has no source URL`);
    assert.match(t, /2026-10-12/, `${f} has no access date`);
  }
});

// Ruling 1209 (13 Oct 2026): the contract-practice and materials digests carry sources and an access date the
// same way, and the whole always-included block stays under the ~120k-token ceiling the ruling set.
test('contract practice and every materials digest name sources and access date', () => {
  const dir = new URL('../../knowledge/brief/uae_materials_brands/', import.meta.url);
  const files = readdirSync(dir).filter((x) => x.endsWith('.md')).map((f) => new URL(f, dir));
  assert.equal(files.length, 10, 'one materials digest per trade group');
  for (const u of [new URL('../../knowledge/brief/uae_contract_practice.md', import.meta.url), ...files]) {
    const t = readFileSync(u, 'utf8');
    assert.match(t, /https?:\/\//, `${u.pathname} has no source URL`);
    assert.match(t, /2026-10-13/, `${u.pathname} has no access date`);
  }
});

test('the compiled brief stays under 120k tokens', () => {
  const { approxTokens } = compileBrief();
  assert.ok(approxTokens < 120000, `brief is ~${approxTokens} tokens`);
});
