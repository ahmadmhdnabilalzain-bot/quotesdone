// A CUSTOMER'S WHATSAPP MESSAGE IS STORED BEFORE ANYTHING IS DONE WITH IT (19 Oct 2026, seat customer_support).
// Sandbox run 5 (tag 321d13ae, S19): a Twilio-signed demo message got HTTP 200 and was found in no table 4 s later.
// Its wa_messages row was written 73 s after arrival, at the END of the model-written turn (#1335); an isolate killed
// inside that window lost the message, and wa_inbound_seen made Twilio's redelivery a "duplicate". index.ts cannot be
// driven offline, so this reads it: once the sender is authenticated, the arrival row is inserted before the first
// branch that can answer or return, and the turn's rows complete it rather than being its first write.
import { assert } from 'jsr:@std/assert@1';

const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const code = src.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');

Deno.test('wa_inbound stores an authenticated message on arrival, before any branch or model call', () => {
  const arrival = code.search(/admin\.from\('wa_messages'\)\.insert\(waRow\(receivedAt, \{[\s\S]{0,400}?stage: 'received'/);
  assert(arrival > 0, 'the arrival insert (meta.stage received) is gone');
  const provenance = code.indexOf('verifyProvenance(MessageSid');
  assert(provenance > 0 && provenance < arrival, 'the arrival row must follow authentication, never precede it');
  const after = code.slice(provenance, arrival);
  // The only returns between authentication and the arrival row are the refusal paths, which store their own row.
  for (const m of after.matchAll(/return TW\(/g)) {
    const before = after.slice(Math.max(0, m.index! - 2500), m.index!);
    assert(/waInsert\(receivedAt/.test(before), 'a return between authentication and the arrival row stores nothing');
  }
  for (const later of ["fn_spec_offer_whatsapp_reply", 'menuMeaning(', 'await modelSays(', 'holdUnwritten({', "fn_identify_contact"]) {
    const at = code.indexOf(later);
    assert(at > arrival, `${later} runs before the message is stored`);
  }
});

Deno.test('only a crashed turn is left at received: a finished turn closes its arrival row, and resilience_ping sweeps the rest', async () => {
  assert(/\bcatch \(e\) \{\s*crashed = true;/.test(code), 'the exception path no longer marks the turn as crashed');
  assert(/finally \{[\s\S]{0,400}if \(!crashed && arrivalId != null\)[\s\S]{0,200}stage: 'handled'/.test(code), 'a finished turn no longer closes its arrival row');
  const ping = await Deno.readTextFile(new URL('../resilience_ping/index.ts', import.meta.url));
  assert(/rpc\('fn_wa_arrival_sweep'/.test(ping), 'resilience_ping no longer runs fn_wa_arrival_sweep');
  const sql = await Deno.readTextFile(new URL('../../../scripts/sql/a_whatsapp_message_whose_turn_crashed_reaches_customer_support_in_five_minutes.sql', import.meta.url));
  assert(/meta->>'stage' = 'received'[\s\S]{0,200}interval '5 minutes'[\s\S]{0,300}for update skip locked[\s\S]{0,300}'stage', 'escalated'/.test(sql),
    'the sweep must take only rows still at received after 5 minutes, lock them, and mark them escalated in the same statement (once)');
  assert(!/fn_reason_hold\(|net\.http_post/.test(sql), 'the sweep must escalate only, never replay the turn');
  assert(/'failed', now\(\), 'wa_arrival:' \|\| m\.id[\s\S]{0,80}on conflict \(dedupe_key\) do nothing/.test(sql),
    'the sweep must queue the holding notice (escalated, status failed so it is never replayed) once per message');
  // The race with a slow turn: completing the arrival row is guarded on 'received', and a swept row is closed, not overwritten.
  assert(/update\(waRow\(rcv, row\)\)\.eq\('id', id\)\.eq\('meta->>stage', 'received'\)/.test(code), 'waInsert overwrites a row the sweep already took');
  assert((code.match(/fn_wa_arrival_turn_finished/g) || []).length >= 2, 'a late reply (row or no row) no longer closes what the sweep opened');
});

Deno.test('the turn completes the arrival row in place (one row per message), not a second insert-only write', () => {
  assert(!/^function waInsert\(/m.test(code), 'an insert-only module-level waInsert is back: it would duplicate the arrival row');
  assert(/update\(waRow\(rcv, row\)\)\.eq\('id', id\)/.test(code), 'waInsert no longer completes the arrival row');
});
