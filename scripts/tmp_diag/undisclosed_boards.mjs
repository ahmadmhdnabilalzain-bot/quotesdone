import { readFileSync } from 'node:fs';
import { sql } from '../phase_b/lib/db.mjs';
const cfg = JSON.parse(readFileSync('scripts/checks/kernel-boards.json', 'utf8'));
const RATCHET = cfg.ratchet || cfg.disclosed || [];
const boards = await sql('select * from public.fn_kernel_all_boards()');
const set = new Set(RATCHET.map((e) => `${e.board} ${e.check}`));
const red = boards.filter((r) => !r.ok);
console.log(`${boards.length} checks, ${red.length} red`);
for (const r of red) {
  const disclosed = set.has(`${r.board} ${r.check_name}`);
  console.log(`${disclosed ? 'disclosed ' : 'UNDISCLOSED '} ${r.board}.${r.check_name}`);
  console.log(`    expected ${r.expected} | got ${String(r.actual).replace(/\s+/g, ' ').slice(0, 200)}`);
}
