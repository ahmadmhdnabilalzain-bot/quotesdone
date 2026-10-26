// The founder's reply to the monthly calendar, read without a network (marketing, 23 Sep 2026).
//   deno test supabase/functions/_shared/marketing_calendar_mail.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { approvalTokenOf, calendarTokenOf, isCalendarReply, ownWords, planTokenOf, replyIntent } from './marketing_calendar_mail.ts';

const TOK = '0123456789abcdef0123456789abcdef';

Deno.test('an article or launch-plan approval reply is read by its own token, never as a calendar or plan reply', () => {
  assertEquals(approvalTokenOf({ to: `approve+${TOK}@mail.quotesdone.com` }), TOK);
  assertEquals(approvalTokenOf({ to: 'info@quotesdone.com', subject: `Re: Article for this week: X [approve ${TOK}]` }), TOK);
  assertEquals(approvalTokenOf({ to: `plan+${TOK}@mail.quotesdone.com` }), null);
  assertEquals(calendarTokenOf({ to: `approve+${TOK}@mail.quotesdone.com` }), null);
  assertEquals(isCalendarReply({ to: `approve+${TOK}@mail.quotesdone.com` }), false);
  assertEquals(planTokenOf({ to: `approve+${TOK}@mail.quotesdone.com` }), null);
});

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
                   'موافق\n\nSent from my iPhone', 'Approve\n-- \nAhmad',
                   // Outlook: a rule of underscores above the quoted mail
                   'Approve\n\n________________________________\nFrom: QuotesDone <info@quotesdone.com>\nlooks fine but change X',
                   // Gmail: the "On ... wrote:" header wrapped over two lines, with a change request quoted below it
                   'approve\n\nOn Tue, 23 Sep 2026 at 10:02, QuotesDone Social <calendar+0123@mail.quotesdone.com>\nwrote:\n\nbut change the third video',
                   'موافق\n\nفي الثلاثاء 23 سبتمبر 2026، QuotesDone\nكتب:\nغير موافق']) {
    assertEquals(replyIntent(t), 'approve', JSON.stringify(t));
  }
});

Deno.test('anything that is not only an approval approves nothing: it is a change request for the seat', () => {
  for (const t of ['looks fine but change X', 'approve but move post 3 to Friday', "don't approve", 'not approved', 'ok',
                   'thanks', 'approve?', 'موافق لكن غيّر الفيديو الثالث', 'غير موافق',
                   'On second thought, do not approve']) {
    assertEquals(replyIntent(t), 'change', JSON.stringify(t));
  }
  // nothing of his own above the quote: neither an approval nor something to act on
  for (const t of ['', '> approve', '_____\napprove', '\n\nOn Tue, 23 Sep 2026 X wrote:\n> approve']) {
    assertEquals(replyIntent(t), 'unclear', JSON.stringify(t));
  }
});

Deno.test('the change request the seat receives is his own words, without the quoted calendar', () => {
  assertEquals(ownWords('Move video 3 to Monday.\nAnd drop TikTok for video 5.\n\nOn Tue, 23 Sep 2026 X wrote:\n> approve'),
    'Move video 3 to Monday.\nAnd drop TikTok for video 5.');
});

Deno.test('a reply to the monthly idea plan is found by its address or its subject, never confused with a calendar', () => {
  const tok = '0123456789abcdef0123456789abcdef';
  assertEquals(planTokenOf({ to: 'plan+' + tok + '@mail.quotesdone.com' }), tok);
  assertEquals(planTokenOf({ to: 'info@quotesdone.com', subject: 'Re: November video ideas [plan ' + tok + ']' }), tok);
  assertEquals(planTokenOf({ to: 'calendar+' + tok + '@mail.quotesdone.com' }), null);
  assertEquals(planTokenOf({ to: 'plan+' + tok + '@evil.example' }), null);
  assertEquals(isCalendarReply({ to: 'plan+' + tok + '@mail.quotesdone.com' }), false);
});
