// NOTHING ON WHATSAPP REACHES THE FOUNDER ANY MORE
//
// Operating constitution 1.2: "Neither agent sends unsolicited operational alerts or approval
// requests to him." And on the public-contact rule specifically: sharing his number "neither alerts
// Ahmad internally nor promises a transfer, availability or response, and the automated case
// continues."
//
// wa_inbound had four founder-directed writes, three of which I added THIS MORNING under the old
// rule. They are replaced by a report to the CEO through the contract built for it, which is where
// the constitution says operational matters go.
//
// The distinction being preserved: a customer receiving Ahmad's public number is fine and stays. An
// internal ALERT telling him it happened is what the constitution forbids, because it turns a
// customer-facing courtesy into a task in his queue.
//
//   node scripts/kb/remove_founder_escalations_from_whatsapp.mjs [--apply]

import { readFileSync, writeFileSync } from 'node:fs';

const APPLY = process.argv.includes('--apply');
const P = 'supabase/functions/wa_inbound/index.ts';
let s = readFileSync(P, 'utf8');
const before = s;

// 1. THE PUBLIC-CONTACT ALERT. Someone asked for a person, got the number, and the founder was told.
//    The constitution removes exactly this. The case continues; nobody is paged.
const A_START = s.indexOf("      if (route.needs_a_person === true) {");
if (A_START >= 0) {
  const A_END = s.indexOf('      }', s.indexOf("status: 'queued' }); } catch (_e) { /* */ }", A_START)) + '      }'.length;
  s = s.slice(0, A_START) + [
    '      // THE FOUNDER IS NO LONGER TOLD. Operating constitution 1.2: sharing his approved public',
    '      // number "neither alerts Ahmad internally nor promises a transfer, availability or',
    '      // response, and the automated case continues". Two writes stood here -- a founder_alerts',
    '      // row and an email to him -- and both turned a customer-facing courtesy into a task in',
    '      // his queue. The customer still gets the number; the internal page is gone.',
    '      if (route.needs_a_person === true) {',
    '        try {',
    '          await admin.rpc(\'fn_support_report_to_ceo\', {',
    '            p_idempotency_key: \'wa:person:\' + (MessageSid || From) ,',
    '            p_severity: \'routine\',',
    '            p_subject: \'A customer asked to speak to a person and was given the public contact\',',
    '            p_evidence: { from: From, message: Body.slice(0, 300), number_given: true },',
    '            p_attempted: [\'shared the approved public contact\', \'kept the case open\'],',
    '            p_requested: \'Visibility only. No action is requested and no work is waiting on this.\',',
    '          });',
    '        } catch (_e) { /* the reply already went out; visibility must not block it */ }',
    '      }',
  ].join('\n') + s.slice(A_END);
  console.log('replaced the public-contact founder alert with a CEO report');
}

// 2 and 3. THE ESCALATION EMAIL AND ALERT on the model path, and the send-failure alert. Same rule:
//    an operational problem goes to the CEO, which is the seat that can act on it.
s = s.replace(
  /\s*try \{ await admin\.from\('founder_alerts'\)\.insert\(\{ level: 'warn', event: 'wa_send_failed'[\s\S]*?\} catch \(_e\) \{ \/\* \*\/ \}/,
  [
    '',
    "      // A FAILED SEND IS THE CEO'S, not the founder's. It was a founder_alerts row and an email",
    '      // to him; under constitution 1.2 neither agent sends him unsolicited operational alerts.',
    '      try {',
    "        await admin.rpc('fn_support_report_to_ceo', {",
    "          p_idempotency_key: 'wa:send_failed:' + (MessageSid || From),",
    "          p_severity: 'elevated',",
    "          p_subject: 'A WhatsApp reply could not be delivered',",
    '          p_evidence: { to: From, provider_error: sendErr || null, audience: audienceFinal },',
    "          p_attempted: ['composed the reply', 'attempted delivery through the configured sender'],",
    "          p_requested: 'Decide whether to retry on this channel or reach the customer another way.',",
    '        });',
    '      } catch (_e) { /* */ }',
  ].join('\n'));

s = s.replace(
  /\s*try \{ await admin\.from\('notifications'\)\.insert\(\{ type: 'wa_escalation'[\s\S]*?\} catch \(_e\) \{ \/\* \*\/ \}\s*try \{ await admin\.from\('founder_alerts'\)\.insert\(\{ level: 'info', event: 'wa_escalation'[\s\S]*?\} catch \(_e\) \{ \/\* \*\/ \}/,
  [
    '',
    '      // AN ESCALATION GOES TO THE CEO. This wrote an email to the founder and a founder_alerts',
    '      // row saying a message "needs a human". Under constitution 1.2 there is no human queue and',
    '      // no founder escalation: the CEO is the final internal authority and the one that can act.',
    '      try {',
    "        await admin.rpc('fn_support_report_to_ceo', {",
    "          p_idempotency_key: 'wa:escalation:' + (MessageSid || From),",
    "          p_severity: 'serious',",
    "          p_subject: 'A WhatsApp conversation needs a decision support cannot make',",
    '          p_evidence: { from: From, message: Body.slice(0, 400), audience: audienceFinal, replied: sent },',
    "          p_attempted: ['answered from live account facts and approved knowledge', 'checked the standing grant'],",
    "          p_requested: 'Decide the outcome, or issue a standing grant that covers it.',",
    '        });',
    '      } catch (_e) { /* */ }',
  ].join('\n'));

const remaining = (s.match(/founder_alerts/g) || []).length;
console.log('founder_alerts references remaining in wa_inbound: ' + remaining + ' (the two in the shared alert helper are its own plumbing)');
if (s === before) { console.log('nothing changed — anchors did not match'); process.exit(1); }
if (APPLY) { writeFileSync(P, s); console.log('written'); } else console.log('DRY RUN — nothing written');
