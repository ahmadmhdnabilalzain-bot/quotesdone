// K33 — teach v_kernel_trigger_source_derived about all three kernel doors.
//
// Generated from the LIVE view definition so only the kernelcaller predicate can move.
import { readFileSync, writeFileSync } from 'node:fs';
import { sql } from './lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_viewdef('public.v_kernel_trigger_source_derived'::regclass, true) as def`);

// pg_get_viewdef normalises the SQL, so match on the semantic content rather than the original
// formatting: the regex-match against fn_kernel_trigger_submit inside the kernelcaller CTE.
const m = def.match(/(kernelcaller AS \(\s*SELECT[\s\S]*?FROM body b\s*\n\s*WHERE )\(?(b\.src ~ '[^']*fn_kernel_trigger_submit[^']*'::text)\)?/);
if (!m) {
  console.error('kernelcaller predicate not found in the live view definition. First 40 lines:\n'
    + def.split('\n').slice(0, 40).join('\n'));
  process.exit(1);
}

const NEW = `${m[1]}(${m[2]}\n         -- K33. All THREE doors, not one. fn_kernel_trigger_submit is the request door;\n` +
  `         -- fn_kernel_signal_submit is the signal door K16 built for a run that already exists;\n` +
  `         -- fn_kernel_source_emit is the canonical wrapper §3 authorises in as many words, and\n` +
  `         -- it is what every cut-over source actually calls. Matching only the first meant the\n` +
  `         -- view reported 38 of 38 sources bypassing the kernel after eleven had been cut over\n` +
  `         -- and verified against pg_proc: a column answering a narrower question than its name.\n` +
  // Single backslashes in the emitted SQL. standard_conforming_strings is on, so '\\y' would be a
  // literal backslash followed by y and the regex would not compile — it did not, first time.
  `         OR b.src ~ '${'\\'}yfn_kernel_signal_submit${'\\'}s*${'\\'}('::text\n` +
  `         OR b.src ~ '${'\\'}yfn_kernel_source_emit${'\\'}s*${'\\'}('::text)`;

const patched = def.replace(m[0], NEW);
if (patched === def) { console.error('replacement produced no change'); process.exit(1); }

writeFileSync('scripts/sql/kernel_k33_derived_view_knows_all_three_doors.sql',
  readFileSync('scripts/sql/kernel_k33_header.txt', 'utf8') +
  `\nbegin;\n\ncreate or replace view public.v_kernel_trigger_source_derived as\n${patched.trim()}\n\n` +
  `comment on view public.v_kernel_trigger_source_derived is\n` +
  `  'K10, corrected by K33. routes_through_inbox recognises all THREE kernel doors — '\n` +
  `  'fn_kernel_trigger_submit, fn_kernel_signal_submit and the canonical wrapper '\n` +
  `  'fn_kernel_source_emit that the specification authorises — instead of only the first. It had '\n` +
  `  'been answering a narrower question than its own column name.';\n\n` +
  `revoke all on public.v_kernel_trigger_source_derived from public;\n` +
  `grant select on public.v_kernel_trigger_source_derived to service_role;\n\ncommit;\n`);
console.log('emitted');
