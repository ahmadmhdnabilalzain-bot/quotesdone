// The founder's reply to the monthly calendar, read without a network (marketing, 23 Sep 2026).
//   deno test supabase/functions/_shared/marketing_calendar_mail.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { calendarTokenOf, isCalendarReply, replyIntent } from './marketing_calendar_mail.ts';

const TOK = '0123456789abcdef0123456789abcdef';

Deno.test('the token is read from the Reply-To tag or from the subject, and nothing else', () => {
  assertEquals(calendarTokenOf({ to: `calendar+${TOK}@mail.quotesdone.com` }), TOK);
  assertEquals(calendarTokenOf({ to: 'info@quotesdone.com', subject: `Re: Social calendar October 2026 [ref ${TOK}]` }), TOK);
  assertEquals(calendarTokenOf({ to: `calendar+${TOK}@evil.example.invalid` }), null);
  assertEquals(calendarTokenOf({ to: 'calendar+short@mail.quotesdone.com', subject: 'approve' }), null);
  assertEquals(isCalendarReply({ to: 'calendar+short@mail.quotesdone.com' }), true, 'a malformed tag is still OUR reply: refused, not misrouted');
  assertEquals(isCalendarReply({ to: 'expenses@mail.quotesdone.com', subject: 'Invoice' }), false);
});

Deno.test('approve in English and Arabic, with the quoted email below ignored', () => {
  for (const t of ['approve', 'Approve.', 'approved', 'OK approve', 'ok, approved!', 'I approve', 'Approved, thanks',
                   'موافق', 'أوافق', 'تمت الموافقة', 'نعم موافق',
                   'approve\n\nOn Tue, 23 Sep 2026 QuotesDone <info@quotesdone.com> wrote:\n> The calendar ... change nothing',
                   'موافق\n\nSent from my iPhone', 'Approve\n-- \nAhmad']) {
    assertEquals(replyIntent(t), 'approve', JSON.stringify(t));
  }
});

Deno.test('anything that is not only an approval approves nothing', () => {
  for (const t of ['looks fine but change X', 'approve but move post 3 to Friday', "don't approve", 'not approved', 'ok',
                   'thanks', '', 'approve?', 'موافق لكن غيّر الفيديو الثالث', 'غير موافق', '> approve']) {
    assertEquals(replyIntent(t), 'unclear', JSON.stringify(t));
  }
});
