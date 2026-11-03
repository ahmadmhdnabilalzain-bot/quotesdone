// EVERY LINE OF THE BRIEF STILL REACHES A REPLY (it_engineer, 3 Nov 2026). Until 3 Nov every chat reply carried all 32
// knowledge files (140-150k Sonnet tokens). It now carries the core, the supplier how-to for a supplier, and one trade
// pack chosen by code (scripts/kb/compile_brief.mjs, supabase/functions/_shared/company_brief.ts). Splitting must lose
// nothing, so this fails when:
//   - a line of any compiled source file is in no block (core, supplier part or pack part);
//   - a playbook category has no pack, or its pack lacks its own section, its family's general rules, its materials
//     digest, its regulation digest or its row of the contract-practice table;
//   - a fact the existing checks pin (the_agent_brief_is_compiled_and_traced, a_supplier_is_told_approval_is_automatic)
//     left the CORE, which is the only block every reply carries;
//   - an edge function other than the brief's own module reads the pack parts, so no reply path can send them all.
// The token cap per reply path is proven in supabase/functions/_shared/brief_budget.test.ts.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { compileBrief } from '../kb/compile_brief.mjs';

const REPO = join(import.meta.dirname, '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8').replace(/\r\n/g, '\n');
const b = compileBrief();
const byId = new Map(b.partIds.map((id, i) => [id, b.partText[i]]));

// Per file, the multiset of its lines must be found in the blocks that file was compiled into (its own <<<FILE>>> blocks),
// so a dropped section cannot hide behind the same line in another file.
const blocksOf = (f) => [b.core, b.supplier, ...b.partText].join('\n').split(/(?=<<<FILE knowledge\/brief\/)/)
  .filter((x) => x.startsWith(`<<<FILE knowledge/brief/${f}>>>`) || x.startsWith(`<<<FILE knowledge/brief/${f}#`)).join('\n');
function lostLines(files, blocks = blocksOf) {
  const lost = [];
  for (const f of files) {
    const have = new Set(blocks(f).split('\n').map((l) => l.trim()));
    for (const l of read('knowledge/brief/' + f).split('\n').map((x) => x.trim()).filter(Boolean)) if (!have.has(l)) lost.push(`${f}: ${l.slice(0, 100)}`);
  }
  return lost;
}

test('every non-empty line of every compiled source file is in that file\'s own blocks (core, supplier part or pack parts)', () => {
  assert.deepEqual(lostLines(b.files), [], 'lines no reply can receive');
});

test('known-bad control: a section the compiler drops is caught', () => {
  // drop the joinery row of the contract-practice table from the blocks: the check must name it
  const without = (f) => blocksOf(f).split('\n').filter((l) => !l.startsWith('| **joinery_and_furniture** |')).join('\n');
  const lost = lostLines(['uae_contract_practice.md'], without);
  assert.equal(lost.length, 1, lost.join('\n'));
  assert.match(lost[0], /joinery_and_furniture/);
});

test('every playbook category has a pack with its section, general rules, materials, regulation digest and contract row', () => {
  const codes = [];
  for (const f of readdirSync(join(REPO, 'knowledge/brief/conversation')).filter((x) => x.endsWith('.md'))) {
    const fam = f.replace(/\.md$/, '');
    for (const c of read('knowledge/brief/conversation/' + f).match(/^\*\*Categories:\*\*\s*(.+)$/m)[1].split(',').map((s) => s.trim())) {
      codes.push(c);
      const row = b.packs.find((p) => p[0] === c);
      assert.ok(row, `${c} has no pack`);
      const [, family, ...ids] = row;
      assert.equal(family, fam, c);
      assert.ok(ids.includes(`conversation/${f}`) && ids.includes(`uae_materials_brands/${f}`) && ids.includes(`uae_contract_practice.md#${fam}`), c);
      const sec = ids.find((id) => id.startsWith(`conversation/${f}#`));
      assert.ok(sec && new RegExp(`^## .*[(,]\\s*${c}\\s*[,)]`, 'm').test(byId.get(sec)), `${c}: its pack lacks its own playbook section`);
      assert.equal(ids.filter((id) => id.startsWith('uae_regulations/')).length, 1, `${c}: its pack must carry exactly one regulation digest`);
    }
  }
  assert.equal(b.packs.length, codes.length, 'one pack per category, none extra');
});

test('the facts the existing checks pin are in the core, which every reply carries', () => {
  const facts = JSON.parse(read('src/content/company_facts.json'));
  const core = b.core;
  assert.ok(core.includes(`**${facts.facts.reveal_fee_pct.value}%**`));
  assert.ok(core.includes(`AED ${facts.facts.nonresponse_admin_fee_aed.value}`));
  assert.ok(core.includes(`${facts.facts.late_interest_pct_pa.value}% p.a.`));
  assert.ok(core.includes(`AED ${facts.facts.subscription_fee_aed.value.toLocaleString('en-US')} per year`));
  assert.match(core, new RegExp(`Customer Terms of Service \\*\\*${facts.documents.terms.version}\\*\\*`));
  assert.match(core, /Approval is \*\*automatic\*\* when the six are complete/);
  assert.match(core, /authority outside the UAE|foreign or unconfirmed issuing authority/i);
  assert.ok(core.includes('<<<FILE knowledge/brief/conversation_style.md>>>') && core.includes('<<<FILE knowledge/brief/gulf_arabic_guide.md>>>'));
});

test('only the brief module reads the pack parts: no reply path can send every pack', () => {
  const walk = (d) => readdirSync(d).flatMap((e) => { const p = join(d, e); return statSync(p).isDirectory() ? walk(p) : [p]; });
  const users = walk(join(REPO, 'supabase/functions')).filter((p) => p.endsWith('.ts') && !/\.test\.ts$|brief\.generated\.ts$/.test(p))
    .filter((p) => /\b(BRIEF_PART_TEXT|BRIEF_PART_IDS|BRIEF_PACKS|KNOWLEDGE_TEXT|PLAYBOOK_TEXT|packOf)\b/.test(readFileSync(p, 'utf8')))
    .map((p) => relative(REPO, p).replace(/\\/g, '/')).sort();
  assert.deepEqual(users, ['supabase/functions/_shared/company_brief.ts', 'supabase/functions/sales_engineer/conversation_plan.ts']);
  assert.match(read('supabase/functions/sales_engineer/conversation_plan.ts'), /plansFrom\(PLAYBOOK_TEXT\)/, 'the plan reads the playbooks; it sends nothing');
});
