// THE CONTACT TEMPLATE GETS SLOTS, LIKE EVERY OTHER COMPANY FACT
//
// fn_wa_answer already renders {{reveal_rate}}, {{free_count}} and {{reg_fee}} from configuration.
// The contact_human template was the odd one out: it carried the founder's number typed into the
// sentence, spaced as "+971 50 931 9355", and never named him.
//
// Two problems with that. The number could not change without editing a row, and the build spec asks
// for the founder's NAME in the reply -- "You can contact Ahmad Alzain, founder of QuotesDone, on
// {{founder_public_phone}}" -- which a bare number cannot give.
//
// So the template gets the same treatment as every other company fact: slots, filled from the
// approved publication settings at render time.
//
//   node scripts/kb/wire_public_contact_slots.mjs [--apply]

import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const APPLY = process.argv.includes('--apply');

const r = await sql(`select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                      where n.nspname='public' and p.proname='fn_wa_answer'`);
let d = r[0].d;

const ANCHOR = "  v_reply := replace(v_reply, '{{reg_fee}}',     coalesce(round(v_cfg.supplier_reg_fee)::text, '1000'));";
if (!d.includes(ANCHOR)) { console.log('anchor not found in fn_wa_answer'); process.exit(1); }

const ADD = ANCHOR + `

  -- THE APPROVED PUBLIC CONTACT, filled the same way. It is read from the settings that say
  -- publication in their names -- never from founder_mobile, which is a private contact record that
  -- happens to hold the same digits. Two values matching is not permission to publish either.
  --
  -- When the setting is absent the slot renders a sentence that ADMITS it rather than an empty
  -- string. "You can contact  on  " is worse than saying the contact is not configured, and the
  -- build spec asks for a blocker reported to the CEO rather than a placeholder shown to a customer.
  v_reply := replace(v_reply, '{{founder_public_phone}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_phone'),
             '(no approved public contact is configured yet)'));
  v_reply := replace(v_reply, '{{founder_public_name}}',
    coalesce((select value from public.app_secrets where key = 'founder_public_name'),
             'the owner'));`;

d = d.replace(ANCHOR, ADD);
if (!d.trimEnd().endsWith(';')) d = d.trimEnd() + ';\n';

const HEAD = `-- THE CONTACT TEMPLATE GETS SLOTS, LIKE EVERY OTHER COMPANY FACT
--
-- Founder, 7 September 2026: "+971509319355 is my number / Ahmad Alzain is my name / the agent will
-- use twilio number though."
--
-- fn_wa_answer already fills {{reveal_rate}}, {{free_count}} and {{reg_fee}} from configuration. The
-- contact_human template was the exception: it had the number typed into the sentence, spaced as
-- "+971 50 931 9355", and it never named him. The number could not change without editing a row,
-- and the spec's wording -- "You can contact Ahmad Alzain, founder of QuotesDone, on
-- {{founder_public_phone}}" -- needs a name a bare number cannot supply.
--
-- The slots read the settings that say PUBLICATION in their names. founder_mobile holds the same
-- digits and is deliberately not the source: it is a private contact record, and two values matching
-- today is not permission to publish either of them.
--
-- WHEN THE SETTING IS ABSENT the slot renders a sentence that admits it. An empty string would give
-- a customer "You can contact  on  ", and the spec asks for a blocker reported to the CEO rather
-- than a placeholder shown to a person.

`;

const TEMPLATE = `
-- The template itself, in the spec's wording, with both slots.
update public.wa_reply_intent
   set answer_template = 'Of course. You can contact {{founder_public_name}}, founder of QuotesDone, on {{founder_public_phone}}. I have noted that you asked for a person.'
 where intent_key = 'contact_human';
`;

if (APPLY) {
  writeFileSync('scripts/sql/the_contact_template_gets_slots_like_every_other_fact.sql', HEAD + d + TEMPLATE);
  console.log('written');
} else console.log('dry run — would rewrite fn_wa_answer and the contact_human template');
process.exit(0);
