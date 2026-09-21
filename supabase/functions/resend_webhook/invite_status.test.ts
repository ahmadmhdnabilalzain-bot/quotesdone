// deno test supabase/functions/resend_webhook/invite_status.test.ts
// Replays the failure: a spam complaint was recorded as a bounce, hiding the complaint rate.
import { assertEquals } from 'jsr:@std/assert@1';
import { inviteStatusFor } from './invite_status.ts';

Deno.test('a spam complaint is a complaint, never a bounce', () => {
  assertEquals(inviteStatusFor(true, false), 'complained');
  // a complaint event can never also be read as a bounce, whatever the bounce fields say
  assertEquals(inviteStatusFor(true, true), 'complained');
});

Deno.test('a hard bounce is a bounce; anything else leaves the lead alone', () => {
  assertEquals(inviteStatusFor(false, true), 'bounced');
  assertEquals(inviteStatusFor(false, false), null);
});
