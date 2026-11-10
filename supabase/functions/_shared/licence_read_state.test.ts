// An unread licence field is the supplier's to fix only when our reader actually read the document (licence_read_state.ts).
// Replays #1901 item 6: license_extract answered extract_failed, the number stayed blank, and the gate asked the supplier for
// a clearer copy three times and closed the registration at day 14.
//   deno test supabase/functions/_shared/licence_read_state.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { licenceLeftUnread, licenceReadState, modelOutcomeOf, LICENCE_BEING_READ_NOTE } from './licence_read_state.ts';

const scan = { licence_legal_name: 'ZZ DEMO Licence Scan LLC', trade_license_no: null, license_expiry: '2027-06-30', license_authority: 'Dubai Economy and Tourism' };

Deno.test('extract_failed with the number blank is OUR failure, never the file', () => {
  const outcome = modelOutcomeOf({ error: 'extract_failed' });
  assertEquals(outcome, 'failed');
  assertEquals(licenceReadState(licenceLeftUnread(scan), outcome), 'ours_failed');
});

Deno.test('a model that is switched off, or had nothing to send, is our failure too', () => {
  assertEquals(licenceReadState(true, 'off'), 'ours_failed');
  assertEquals(licenceReadState(true, 'not_sent'), 'ours_failed');
});

Deno.test('the model answering "unreadable" is the file: the supplier may be asked', () => {
  const outcome = modelOutcomeOf({ ok: true, doc: { unreadable: true } });
  assertEquals(outcome, 'unreadable');
  assertEquals(licenceReadState(licenceLeftUnread(scan), outcome), 'file_unreadable');
});

Deno.test('a reading that still leaves a blank is the document: read', () => {
  assertEquals(licenceReadState(true, modelOutcomeOf({ ok: true, doc: { legal_name: 'X', confidence: 'high' } })), 'read');
});

Deno.test('every field read by code is read, whatever the model did', () => {
  const all = { ...scan, trade_license_no: '1234567' };
  assertEquals(licenceLeftUnread(all), false);
  for (const m of ['not_needed', 'off', 'failed', 'unreadable', 'read'] as const) assertEquals(licenceReadState(false, m), 'read');
});

Deno.test('the supplier is told it is our side, in English', () => {
  assertEquals(/[؀-ۿ]/.test(LICENCE_BEING_READ_NOTE), false);
  assertEquals(/on our side, not yours/.test(LICENCE_BEING_READ_NOTE), true);
});
