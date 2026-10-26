// The marketing seat's LinkedIn drafts (marketing, 22 Sep 2026). ZZ DEMO people only; no network.
//   deno test supabase/functions/_shared/marketing_outreach.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { classifyReply, composeFirst, composeFollowUp, founderList, NOTE_MAX, type Prospect, type Segment } from './marketing_outreach.ts';

const SEGMENTS: Segment[] = ['developer', 'contractor_procurement', 'consultant', 'facility_manager'];
const person = (id: number, segment: Segment, language: 'en' | 'ar', opening_line: string | null = null): Prospect =>
  ({ id, full_name: language === 'ar' ? 'ZZ DEMO سارة' : 'Eng. ZZ-Sara Demo', company: 'ZZ DEMO Developments', segment, language, opening_line });

Deno.test('every template, in both languages and every segment, passes the style gate and fits a note', () => {
  for (const s of SEGMENTS) for (const l of ['en', 'ar'] as const) for (let id = 1; id <= 6; id++) {
    const c = composeFirst(person(id, s, l, l === 'en' ? 'Congratulations on the handover of your latest tower.' : null));
    assertEquals(c.lint, [], `${s}/${l}/${id}`);
    assert(c.note.length <= NOTE_MAX, `${s}/${l}/${id} note is ${c.note.length} characters`);
    assert(c.message.length < 1900);
  }
});

Deno.test('the greeting uses the first name without a title, and the hook is only the cited company line', () => {
  const c = composeFirst(person(7, 'developer', 'en', 'Congratulations on the handover of your latest tower.'));
  assert(c.message.startsWith('Hello ZZ-Sara,'), c.message);
  assert(c.message.includes('Congratulations on the handover'));
  const bare = composeFirst(person(7, 'developer', 'en'));
  assert(!bare.message.includes('Congratulations'));
  assert(!/we met|our mutual|as discussed|following our/i.test(bare.message), 'never claims a relationship');
});

Deno.test('the same person always gets the same draft; neighbours vary', () => {
  assertEquals(composeFirst(person(11, 'consultant', 'en')), composeFirst(person(11, 'consultant', 'en')));
  const asks = new Set([1, 2, 3, 4, 5, 6].map((id) => composeFirst(person(id, 'consultant', 'en')).message.split('\n').pop()));
  assert(asks.size >= 2, 'the closing line varies between people');
});

Deno.test('a pasted reply is read, and the follow-up is professional in its language', () => {
  assertEquals(classifyReply('Not interested, thanks'), 'decline');
  assertEquals(classifyReply('Sounds good, please share details'), 'positive');
  assertEquals(classifyReply('Busy this month, maybe after Eid'), 'later');
  assertEquals(classifyReply('What is your fee structure?'), 'question');
  assertEquals(classifyReply('لا، شكرًا'), 'decline');
  assertEquals(classifyReply('نعم، أرسل التفاصيل'), 'positive');
  assertEquals(classifyReply('مشغول حاليًا، لاحقًا إن شاء الله'), 'later');
  for (const l of ['en', 'ar'] as const) for (const r of ['yes', 'not interested', 'later', 'how much?']) {
    const f = composeFollowUp({ full_name: 'ZZ DEMO Sara', language: l }, r);
    assertEquals(f.lint, [], `${l}/${r}`);
  }
});

Deno.test('the founder list carries each link and says when a profile is not public', () => {
  const l = founderList('2026-09-23', [{ full_name: 'ZZ DEMO Sara', role_title: 'Procurement Manager', company: 'ZZ DEMO Co', language: 'en',
    linkedin_url: null, message: 'Hello', note: 'Hello', link: 'https://x.example.invalid/m' }]);
  assert(l.subject.includes('1 people'));
  assert(l.body.includes('https://x.example.invalid/m') && l.body.includes('search LinkedIn'));
});
