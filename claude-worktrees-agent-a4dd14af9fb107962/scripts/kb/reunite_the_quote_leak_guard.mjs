// REUNITE THE QUOTE LEAK GUARD WITH ITS IMPLEMENTATION
//
// public.quotes carries trg_mask_quote_contact, which strips contact details out of a quotation's
// free text so a supplier cannot put a phone number in the scope and reach the buyer around the
// platform. It calls mask_contact(text) -- SINGULAR. No committed file in this repository has ever
// defined that name. The implementation in history is mask_contacts (PLURAL); the singular was made
// by a direct apply that never reached a file. When the deletion removed it, the trigger kept calling
// a name with no definition anywhere, and every quotation carrying a scope failed to insert.
//
// So the real implementation comes back under the name history actually has, and the trigger is
// rewritten to call that. Reuniting the two is the fix. Inventing a wrapper named mask_contact would
// preserve the split that caused this.
//
//   node scripts/kb/reunite_the_quote_leak_guard.mjs

import { writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const SRC_COMMIT = '790dd45';
const SRC_FILE = 'supabase/migrations/20260630172659_quote_leak_guard.sql';
const src = execSync(`git show ${SRC_COMMIT}:${SRC_FILE}`, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });

const re = /create\s+or\s+replace\s+function\s+public\.mask_contacts\s*\(/gi;
let m, last = null;
while ((m = re.exec(src))) last = m;
if (!last) { console.error('mask_contacts not found in ' + SRC_FILE); process.exit(1); }
const start = last.index;
const tag = /\$([a-z0-9_]*)\$/i.exec(src.slice(start));
const open = start + tag.index;
const close = src.indexOf(tag[0], open + tag[0].length);
let end = close + tag[0].length;
const tail = /^\s*;?/.exec(src.slice(end));
if (tail) end += tail[0].length;
const body = src.slice(start, end);
console.log('recovered mask_contacts (' + body.length + ' chars)');

const HEAD = [
  '-- THE QUOTE LEAK GUARD, REUNITED WITH ITS IMPLEMENTATION',
  '--',
  '-- public.quotes carries trg_mask_quote_contact, which strips contact details out of a quotation',
  '-- free-text field so a supplier cannot put a phone number in the scope and reach the buyer around',
  '-- the platform. It called mask_contact(text) -- SINGULAR. No committed file in this repository has',
  '-- ever defined that name: the implementation in history is mask_contacts (PLURAL), and the',
  '-- singular was created by a direct apply that never reached a file.',
  '--',
  '-- When the 7 September deletion removed it, the trigger kept calling a name with no definition',
  '-- anywhere, and every quotation carrying a scope, notes, conditions or exclusions failed to insert.',
  '--',
  '-- The real implementation is restored under the name history actually has, and the trigger is',
  '-- rewritten to call THAT. Reuniting the two is the fix; a wrapper called mask_contact would',
  '-- preserve the split that caused this.',
  '--',
  '-- MY WRITE PROBE MISSED THIS ENTIRELY, which is the lesson worth keeping. The probe inserted the',
  '-- minimum a quotes row needs, and the minimum has no scope, so the trigger never fired and',
  '-- public.quotes reported writable. A probe thin enough to always pass proves nothing.',
  '',
].join('\n');

const TRIGGER = [
  '',
  '-- The trigger function, now calling a name that exists. Four fields, because a leak in the',
  '-- exclusions is as reachable to a buyer as a leak in the scope.',
  'create or replace function public.trg_mask_quote_contact()',
  'returns trigger',
  'language plpgsql',
  "set search_path to 'public', 'pg_temp'",
  'as $function$',
  'begin',
  '  new.notes      := public.mask_contacts(new.notes);',
  '  new.scope      := public.mask_contacts(new.scope);',
  '  new.conditions := public.mask_contacts(new.conditions);',
  '  new.exclusions := public.mask_contacts(new.exclusions);',
  '  return new;',
  'end $function$;',
  '',
].join('\n');

writeFileSync('scripts/sql/the_quote_leak_guard_reunited_with_its_implementation.sql', HEAD + '\n' + body + '\n' + TRIGGER);
console.log('written scripts/sql/the_quote_leak_guard_reunited_with_its_implementation.sql');
