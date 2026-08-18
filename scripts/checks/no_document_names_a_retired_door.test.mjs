// A DOCUMENT THAT NAMES A RETIRED DOOR IS A MAP OF A BUILDING THAT CHANGED.
//
//   node scripts/checks/no_document_names_a_retired_door.test.mjs
//
// THE DEFECT THIS EXISTS TO CATCH, found 17 Aug 2026 when the founder asked what was still pending
// for Phase C. docs/phase-c/PHASE_C_PHASE_D_HANDOFF.md — the document Phase D builds against — said:
//
//     "fn_phase_c_step_advance, fn_phase_c_task_create, fn_phase_c_handoff_open,
//      fn_phase_c_outbox_emit, fn_founder_command_submit and fn_phase_c_authority_check
//      are the doors."
//
// FOUR OF THE FIVE WRITERS WERE NO LONGER DOORS. fn_phase_c_step_advance was DISABLED at the kernel
// cutover on 16 Aug; the other three are KERNEL_INTERNAL_PRIMITIVE and no ordinary role holds
// EXECUTE on any of them. A handler written from that sentence would have been written against a
// routine that refuses it. Nothing could see it: every gate measures the RUNTIME, and this was a
// sentence in a Markdown file.
//
// The rule is narrow on purpose. It does not ask a document to list the doors correctly — that is
// unenforceable prose. It asks only that a document does not call a RETIRED path a door, which is
// decidable: public.kernel_retired_path says which paths are retired, and the phrasing that turns a
// mention into a claim is a short, closed list.
//
// READ-ONLY against production. Every statement it sends is a SELECT.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';

const LOCAL_TOKEN = 'C:/Users/Opera/.supabase/access-token';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();

// The phrasings that turn a mention into a claim that you may call it.
const CLAIMS = [/\bis the (only )?(way in|door|boundary|entry)\b/i, /\bare the doors\b/i,
                /\bthe canonical boundary\b/i, /\bcall\b[^.\n]{0,40}\bto (start|advance|create)\b/i];

const DOC_DIRS = ['docs/phase-c', 'docs/phase-c-kernel', 'docs/phase-c-final-kernel', 'docs/phase-d'];
const docs = DOC_DIRS.flatMap(d => {
  try { return readdirSync(d).filter(f => f.endsWith('.md')).map(f => join(d, f)); } catch { return []; }
});

test('no committed Phase C/D document calls a retired path a door', { skip: token ? false : 'SKIPPED: no management token, so kernel_retired_path cannot be read. Nothing is asserted.' }, async () => {
  const r = await fetch(`https://api.supabase.com/v1/projects/htdblwldjkcgjvmqkbeh/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: 'select path_name, disposition from public.kernel_retired_path order by 1' }),
  });
  assert.ok(r.ok, `could not read kernel_retired_path: ${r.status}`);
  const retired = await r.json();
  assert.ok(retired.length > 0, 'kernel_retired_path is empty — this check would pass vacuously');

  const findings = [];
  for (const doc of docs) {
    const lines = readFileSync(doc, 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (!CLAIMS.some(re => re.test(line))) return;
      // THE CLAIM SPANS THE LINES AROUND IT, NOT ONLY AFTER IT — and two bugs were forced out of
      // this block on 17 Aug 2026 before it was trusted:
      //   1. the window read i, i+1, i+2, so a list whose names sit on the lines BEFORE
      //      "are the doors" was never seen — which is exactly how the real defect was written;
      //   2. `\b` inside a TEMPLATE LITERAL is the backspace character, not a word boundary, so
      //      new RegExp(`\b${name}\b`) matched nothing at all.
      // Either bug alone made this check green and inert. A forced counterexample found both, and
      // the run below is what proves the check can still refuse something.
      const from = Math.max(0, i - 3), to = Math.min(lines.length, i + 3);
      const window = lines.slice(from, to).join('\n');
      // A passage that CORRECTS the claim is the fix, not the defect.
      if (/CORRECTED|no longer (a )?door|DISABLED|KERNEL_INTERNAL_PRIMITIVE|retired/i.test(window)) return;
      for (const p of retired) {
        if (new RegExp('\\b' + p.path_name + '\\b').test(window)) {
          findings.push(`${doc}:${i + 1} calls ${p.path_name} (${p.disposition}) a door`);
        }
      }
    });
  }
  assert.deepEqual(findings, [], `\n  ${findings.join('\n  ')}\n`
    + `\n  These are retired in public.kernel_retired_path. Derive the current doors instead:\n`
    + `    select distinct a.routine_name from public.kernel_write_authority a\n`
    + `     where not exists (select 1 from public.kernel_retired_path p where p.path_name = a.routine_name);\n`);
});
