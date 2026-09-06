// CORRECTION. The closure listed fn_kernel_truncate_protection_state's two reds as pre-existing.
// They were not: they were this session's, and the estate's own gate caught it. Recorded as a
// correction rather than quietly rewritten, because a document that silently drops a wrong claim
// teaches the next reader nothing.
import { readFileSync, writeFileSync } from 'node:fs';

const p = 'docs/phase-d/PHASE_D_BUILDER_CLOSURE.md';
let s = readFileSync(p, 'utf8');
let bad = 0;
const rep = (find, repl, label) => {
  const n = s.split(find).length - 1;
  if (n !== 1) { console.error(`ANCHOR ${label}: matched ${n}`); bad++; return; }
  s = s.replace(find, repl);
};

rep('`fn_kernel_all_boards()` returns **11** failing checks. Every one predates this session and none\nmoved during it:',
  '`fn_kernel_all_boards()` returns **9** failing checks. Every one predates this session and none\nmoved during it.\n\n**A tenth and eleventh did NOT predate it, and this is the correction.** An earlier draft of this\nsection listed `fn_kernel_truncate_protection_state`\'s two checks — `enforcing_tables_without_a_\ntruncate_guard` and `enforcing_tables_still_granting_truncate`, both `4 of 91` — as pre-existing.\nThey were **this session\'s**, and the estate\'s own gate said so:\n\n> a kernel board is red and kernel-boards.json does not disclose it. Either the estate regressed, or\n> this is a gap that must be recorded with an owner and a reason before it is allowed to stand.\n\nThe board counts as ENFORCING any table carrying a row trigger whose function contains\n`raise exception`, and four tables reached that definition here: `phase_d_file_revision` (O04),\n`phase_d_quote_normalisation` (O06), `phase_d_legal_assertion` (O07) and `public.quotes`, which\nO06\'s `a30_quote_supplier_is_immutable` made enforcing. Every one refused a write and none refused a\nTRUNCATE, so each refusal was one statement away from irrelevant — `truncate\npublic.phase_d_file_revision` would have removed every redaction verdict without the\nreviewer-independence trigger having anything to say about it. All four still granted TRUNCATE to\nservice_role, because TRUNCATE arrives with ALL and nothing had taken it away.\n\n`phase_d_o16` attaches `z00_kernel_truncate_guard` and revokes the privilege on all four, and\nrevokes it on five sibling registries that are not enforcing today so the next trigger added to one\ndoes not reopen it. The board reads **0 of 91** on both counts. The mistake worth recording is not\nthe missing guard; it is that the first reading of this board was taken AFTER ten of this session\'s\nfiles had already been applied, and a number read after the change was described as the state\nbefore it.\n\nThe nine that genuinely predate this session:',
  'reds intro');

if (bad) process.exit(1);
writeFileSync(p, s);
console.log('closure corrected');
