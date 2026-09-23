// A provider's structured fields decide; its free text never does.
import { assertEquals } from 'jsr:@std/assert@1';
import { readTranscript, twilioVerdict } from './provider_signals.ts';

Deno.test('Twilio: the code decides, not the message', () => {
  assertEquals(twilioVerdict(63016), 'not_yet');
  assertEquals(twilioVerdict('63042'), 'not_yet');
  assertEquals(twilioVerdict(21211), 'rejected');          // invalid number: a real rejection, whatever the prose says
  // no code at all: unknown, retried, never read off "template not approved" in the message
  assertEquals(twilioVerdict(null), 'unknown');
  assertEquals(twilioVerdict('template not approved'), 'unknown');
});

Deno.test('transcribe: "was there speech" is the model\'s structured answer', () => {
  assertEquals(readTranscript('{"speech": true, "text": " two coats of paint "}'), { speech: true, text: 'two coats of paint' });
  assertEquals(readTranscript('{"speech": false, "text": ""}'), { speech: false, text: '' });
  // a caller who SAYS "silence" is transcribed, not emptied by a placeholder regex
  assertEquals(readTranscript('{"speech": true, "text": "silence"}'), { speech: true, text: 'silence' });
  assertEquals(readTranscript('```json\n{"speech": false, "text": "noise"}\n```'), { speech: false, text: '' });
  assertEquals(readTranscript([{ text: '{"speech": true, ' }, { text: '"text": "مرحبا"}' }]), { speech: true, text: 'مرحبا' });
  // not the object: unreadable, never a guess
  assertEquals(readTranscript('(silence)'), null);
  assertEquals(readTranscript('{"text": "hi"}'), null);
  assertEquals(readTranscript(null), null);
});
