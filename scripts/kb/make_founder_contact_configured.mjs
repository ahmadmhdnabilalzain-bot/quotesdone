// THE PUBLIC CONTACT COMES FROM CONFIGURATION, NOT FROM A LITERAL IN THREE ROUTINES
//
// Founder, 7 September 2026: "+971509319355 is my number / Ahmad Alzain is my name / the agent will
// use twilio number though."
//
// The build spec is precise about this: "Load only the approved public phone from current company
// configuration... Do not infer it from private documents or unrelated contact records... never
// output a placeholder." Three routines -- fn_wa_route, fn_wa_fact_pack and fn_wa_model_brief --
// carried the digits as a hard-coded string. That fails the rule twice over: the number cannot be
// changed without a migration, and nothing distinguishes a number we HOLD from a number we are
// ALLOWED TO PUBLISH.
//
// founder_mobile already existed and holds the same digits. It is deliberately NOT used here: it is
// a private contact record, and the fact that two values happen to match today is not permission to
// publish either. The new keys say publication in their names, and the founder approved exactly
// those two values for it.
//
// TWO NUMBERS, NEVER CONFUSED. founder_public_phone is what the agent GIVES OUT when someone asks
// for a person. twilio_wa_from (12183166814) is what the agent SENDS FROM. They must never swap:
// sending from the founder's number would put his phone in front of every customer, and publishing
// the Twilio number as "the founder" would be a lie.
//
//   node scripts/kb/make_founder_contact_configured.mjs [--apply]

import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const APPLY = process.argv.includes('--apply');
const LITERAL = '+971509319355';
const NAMES = ['fn_wa_route', 'fn_wa_fact_pack', 'fn_wa_model_brief'];

// The replacement: read the approved publication setting, and if it is absent say so rather than
// emit an empty string or a placeholder. A support message containing "your contact is  " is worse
// than one that admits the setting is missing.
const READ = `coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
                   '(no approved public contact is configured — tell the CEO)')`;

let body = '';
const done = [];
for (const name of NAMES) {
  const r = await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                        where n.nspname='public' and p.proname='${name}'`);
  if (!r.length) { console.log('missing: ' + name); continue; }
  let d = r[0].d;
  const before = (d.match(new RegExp('\\' + LITERAL.replace('+', '+'), 'g')) || []).length;
  if (!d.includes(LITERAL)) { console.log('no literal in ' + name); continue; }

  // Two shapes appear: the number inside a longer single-quoted sentence, and the number as its own
  // literal. The first is rewritten to concatenate the configured value; the second is replaced by
  // the read outright.
  d = d.split(`'${LITERAL}'`).join(`(${READ})`);
  d = d.replace(new RegExp("'([^']*)" + LITERAL.replace('+', '\\+') + "([^']*)'", 'g'),
    (_m, pre, post) => `'${pre}' || (${READ}) || '${post}'`);

  if (d.includes(LITERAL)) { console.log('WARNING: literal still present in ' + name + ' — left for a human'); continue; }
  if (!d.trimEnd().endsWith(';')) d = d.trimEnd() + ';\n';
  body += d + '\n';
  done.push(name + ' (' + before + ' occurrence' + (before === 1 ? '' : 's') + ')');
}

const HEAD = `-- THE PUBLIC CONTACT IS A CONFIGURED SETTING, NOT A LITERAL
--
-- Founder, 7 September 2026: "+971509319355 is my number / Ahmad Alzain is my name / the agent will
-- use twilio number though."
--
-- Three routines carried his number as a hard-coded string. The build spec forbids exactly that:
-- the approved public phone must come from current company configuration, must not be inferred from
-- a private contact record, and must never be emitted as a placeholder.
--
-- app_secrets.founder_mobile already held the same digits and is deliberately NOT the source. It is
-- a private contact record. Two values matching today is not permission to publish either of them.
-- The new key says publication in its name and holds exactly what he approved for it.
--
-- WHEN THE SETTING IS ABSENT the agent says so instead of emitting an empty string. A message
-- reading "you can reach us on  " is worse than one that admits the number is not configured, and
-- the spec asks for a blocker reported to the CEO rather than a placeholder printed to a customer.
--
-- TWO NUMBERS THAT MUST NEVER SWAP:
--   founder_public_phone  +971509319355   what the agent GIVES OUT when someone asks for a person
--   twilio_wa_from        12183166814     what the agent SENDS FROM
-- Sending from his number would put his phone in front of every customer; publishing the Twilio
-- number as "the founder" would be untrue.
--
-- Rewritten: ${done.join(', ') || '(none)'}

`;

if (!done.length) { console.log('nothing to rewrite'); process.exit(0); }
const OUT = 'scripts/sql/the_public_contact_is_configured_not_hard_coded.sql';
if (APPLY) { writeFileSync(OUT, HEAD + body); console.log('written ' + OUT); }
console.log('would rewrite: ' + done.join(', '));
process.exit(0);
