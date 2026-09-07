// RECOVER THE FUNCTIONS THAT LIVE TRIGGERS STILL CALL
//
// Measured, not inferred: a real insert driven at each product table inside an aborted transaction.
// public.customers refused every row with "function is_disposable_email(text) does not exist" and
// public.inquiries with "mask_contacts_jsonb(jsonb) does not exist". No customer could register and
// no inquiry could be created, and nothing reported it because nothing had tried to write since the
// deletion.
//
// These are RESTORED rather than their triggers dropped, because each still does something the
// product needs. Dropping the masking trigger would have left every inquiry fully readable by the
// supplier side -- a privacy failure introduced while tidying a schema.
//
// Recovered verbatim from supabase/migrations_history, which is the record of what was actually
// applied on the day. That directory is read here, never edited.
//
//   node scripts/kb/recover_functions_triggers_still_call.mjs

import { readFileSync, writeFileSync } from 'node:fs';

const WANT = [
  ['is_disposable_email', 'supabase/migrations_history/20260629214950_improvements_foundation.sql'],
  ['mask_contacts_jsonb', 'supabase/migrations_history/20260729141449_durable_masking_on_inquiries.sql'],
  ['mask_name', 'supabase/migrations_history/20260803032305_harden_inquiry_masking_for_supplier_safe_view.sql'],
];

let out = '';
for (const [fn, file] of WANT) {
  let src;
  try { src = readFileSync(file, 'utf8'); } catch { console.log('cannot read ' + file); continue; }
  const re = new RegExp(String.raw`create\s+(or\s+replace\s+)?function\s+(public\.)?` + fn + String.raw`\s*\(`, 'gi');
  let m, last = null;
  while ((m = re.exec(src))) last = m;      // the LAST definition in the file is the one that stuck
  if (!last) { console.log('no definition of ' + fn + ' in ' + file); continue; }
  const start = last.index;
  const tag = /\$([a-z0-9_]*)\$/i.exec(src.slice(start));
  if (!tag) { console.log('no body quote for ' + fn); continue; }
  const open = start + tag.index;
  const close = src.indexOf(tag[0], open + tag[0].length);
  if (close < 0) { console.log('unterminated body for ' + fn); continue; }
  let end = close + tag[0].length;
  const tail = /^\s*;?/.exec(src.slice(end));
  if (tail) end += tail[0].length;
  out += src.slice(start, end) + '\n\n';
  console.log('recovered ' + fn + ' (' + (end - start) + ' chars) from ' + file.split('/').pop());
}

if (!out) { console.log('nothing recovered'); process.exit(1); }

const HEAD = `-- THE FUNCTIONS THREE LIVE TRIGGERS STILL CALL
--
-- The 7 September deletion removed 461 routines. plpgsql resolves a callee at RUN time, so every
-- trigger that called one kept existing and its table silently became UNWRITABLE. Measured by
-- driving a real insert at each product table inside an aborted transaction:
--
--   public.customers   refused every row: function is_disposable_email(text) does not exist
--   public.inquiries   refused every row: function mask_contacts_jsonb(jsonb) does not exist
--
-- No customer could register. No inquiry could be created. Nothing reported it, because nothing had
-- tried to write since the deletion -- the estate is on hold and the website had no traffic.
--
-- RESTORED RATHER THAN THEIR TRIGGERS DROPPED, because each still does something the product needs:
-- refusing a disposable signup address, and masking contact details out of an inquiry before the
-- supplier side can read it. Dropping the masking trigger would have left every inquiry fully
-- readable by suppliers -- a privacy failure introduced while tidying a schema.
--
-- Recovered verbatim from supabase/migrations_history, the record of what was actually applied.
-- That directory is read, never edited.

`;

writeFileSync('scripts/sql/the_functions_three_triggers_still_call.sql', HEAD + out);
console.log('written scripts/sql/the_functions_three_triggers_still_call.sql');
