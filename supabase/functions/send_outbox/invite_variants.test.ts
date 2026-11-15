// THE INVITATION COPY TEST (15 Nov 2026, marketing): every variant is held to the founder's copy rules, the variant comes only
// from the row's kind, and a row without one (a seed, an older row) is the approved text A.
// scripts/sql/the_invitation_ramps_on_measured_health_and_tests_its_copy.sql fixes each lead's variant and writes the kind.
import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import { campaignMail, claimsBuyersExist, FINAL_TOUCH_KIND, INVITE_VARIANTS, m365CopyLint, m365FinalTouchSubject, m365FinalTouchText, m365InvitationText, m365Subject, M365_SEED_KIND, PROMISE_WE_DO_NOT_KEEP, SIGNATURE, STOP_LINE, variantOfKind } from './m365_lane.ts';
import { campaignStep, isCampaignRow } from './invite_lane.ts';

const WHO = [{}, { company: 'Sigma Ceramics' }, { company: 'Sigma Ceramics', trade: 'tiling' }, { trade: 'fire_safety' }];

Deno.test('every variant passes every copy rule, with and without a company and a trade', () => {
  for (const v of INVITE_VARIANTS) for (const who of WHO) {
    const body = m365InvitationText(who, v); const subject = m365Subject(who, v);
    for (const l of m365CopyLint({ subject, body })) assert(l.ok, `variant ${v} ${JSON.stringify(who)}: ${l.rule}: ${l.detail}`);
    assert(!/\b(free|join|register|commission|1,000|invitation|exclusive)\b/i.test(body + ' ' + subject), `variant ${v} carries an offer phrase`);
    assert(!/\b(buyers are|customers are) (already )?sending\b/i.test(body), `variant ${v} claims buyers that do not exist yet`);
    assert(!PROMISE_WE_DO_NOT_KEEP.test(body), `variant ${v} promises to do a step for them (ledger 1401)`);
    assert(!claimsBuyersExist(body), `variant ${v} says buyers already post requests`);
  }
});

// THE TWO FALSE CLAIMS OF THE OLD VARIANT B (review of the funnel branch, item 1). The text of 15 Nov (d8f9ca074) passed every rule
// of the day; each phrasing must now fail the lane's own copy rules, so send_outbox holds a row that carries it.
const OLD_B = ["Hi Sigma Ceramics team,",
  "I'm Ahmad, founder of QuotesDone in Dubai. Companies in the UAE post their requests for quotation with us, and each request goes only to suppliers in that exact trade.",
  'Which trades does your company cover? If you reply with them, we will set up your company page for you.', SIGNATURE, STOP_LINE].join('\n\n');
Deno.test('the old variant B fails the copy rules on both false claims, and each phrasing alone is caught', () => {
  const failed = m365CopyLint({ subject: 'Which trades does your company cover?', body: OLD_B }).filter((l) => !l.ok).map((l) => l.rule);
  assert(failed.some((r) => /never promises to set up their page/.test(r)), 'the set-up promise passed: ' + failed.join('; '));
  assert(failed.some((r) => /never says buyers already send requests/.test(r)), 'the buyers claim passed: ' + failed.join('; '));
  for (const t of ['we will set up your company page for you', "We'll create your profile for you.", 'Our team will complete your registration.',
                   'we can build your listing']) assert(PROMISE_WE_DO_NOT_KEEP.test(t), t);
  for (const t of ['Companies in the UAE post their requests for quotation with us.', 'Buyers are already sending requests.',
                   'Customers send us requests every day.']) assert(claimsBuyersExist(t), t);
  // what the honest variants say is not a claim
  for (const t of ['Companies in the UAE will post requests with us. Buyers have not started sending requests yet.',
                   'QuotesDone is a platform where companies in the UAE post requests for quotation. We are putting together our list now, before buyers start sending requests.',
                   "If you reply with them, I will send you your company's own sign-up link, so you can add your company yourself."]) {
    assert(!claimsBuyersExist(t) && !PROMISE_WE_DO_NOT_KEEP.test(t), t);
  }
});

Deno.test('the last note to a parked lead is a nudge of kind invite_final_touch: its own words, no link, every copy rule', () => {
  for (const who of WHO) {
    const body = m365FinalTouchText(who); const subject = m365FinalTouchSubject(who);
    for (const l of m365CopyLint({ subject, body })) assert(l.ok, `final touch ${JSON.stringify(who)}: ${l.rule}: ${l.detail}`);
    assert(!/https?:|wa\.me|www\.|\/portal/i.test(body + subject), 'the last note carries a link');
    assert(!/\b(free|join|register|commission|1,000|invitation|exclusive|whatsapp)\b/i.test(body + ' ' + subject), 'the last note carries an offer phrase or a channel');
  }
  const f = campaignMail({ type: 'supplier_invite_nudge', kind: FINAL_TOUCH_KIND, body: 'Hi Sigma Ceramics team,' }, { company: 'Sigma Ceramics' });
  assertEquals(f.text, m365FinalTouchText({ company: 'Sigma Ceramics' }));
  assertEquals(f.subject, 'One last note from QuotesDone');
  assertEquals(f.bad, []);
  // only the nudge type with that kind is the last note; the kind on another type changes nothing
  assertEquals(campaignMail({ type: 'supplier_invite', kind: FINAL_TOUCH_KIND, body: '' }, {}).text, m365InvitationText({}, 'a'));
  assert(isCampaignRow({ type: 'supplier_invite_nudge', to_role: 'supplier' }), 'the last note is not a campaign row');
});

Deno.test('a queued campaign row obeys the live switches at send time; an unreadable answer holds it', () => {
  const now = new Date('2026-11-16T07:00:00Z');
  assert(isCampaignRow({ type: 'supplier_invite', to_role: 'supplier' }));
  assert(!isCampaignRow({ type: 'supplier_invite_seed', to_role: 'supplier' }), 'the placement seed is not campaign mail');
  assert(!isCampaignRow({ type: 'supplier_registration_reminder', to_role: 'supplier' }));
  assert(!isCampaignRow({ type: 'supplier_invite', to_role: 'admin' }));
  const v = [{ id: 1, verdict: 'send' as const, why: '' }, { id: 2, verdict: 'cancel' as const, why: 'invite_enabled is false' },
             { id: 3, verdict: 'requeue' as const, why: 'the google mailboxes are held by the bounce judgement' }];
  assertEquals(campaignStep(v, 1, now).step, 'send');
  const c = campaignStep(v, 2, now); assertEquals(c.step, 'cancel'); assert(c.step === 'cancel' && /invite_enabled is false/.test(c.why));
  const r = campaignStep(v, '3', now); assertEquals(r.step, 'requeue');
  assert(r.step === 'requeue' && r.until.toISOString() === '2026-11-17T06:00:00.000Z', 'a held class is not asked again at 10:00 Dubai tomorrow');
  const miss = campaignStep(v, 9, now); assert(miss.step === 'requeue' && miss.until.getTime() - now.getTime() === 30 * 60_000, 'a row the answer does not name is sent');
  const down = campaignStep(null, 1, now); assert(down.step === 'requeue', 'a failed check sends');
});

Deno.test('the three variants are three different emails, and A is the approved text unchanged', () => {
  const texts = INVITE_VARIANTS.map((v) => m365InvitationText({ company: 'Sigma Ceramics', trade: 'tiling' }, v));
  assertEquals(new Set(texts).size, 3);
  assertEquals(m365InvitationText({ company: 'Sigma Ceramics' }, 'a'), m365InvitationText({ company: 'Sigma Ceramics' }));
  assertEquals(m365Subject({ trade: 'tiling' }), 'A question about your tiling work');
  assertNotEquals(m365Subject({ trade: 'tiling' }, 'c'), m365Subject({ trade: 'tiling' }, 'a'));
});

Deno.test('the variant comes only from the row kind; anything else is A', () => {
  assertEquals(variantOfKind('invite_variant:b'), 'b');
  assertEquals(variantOfKind('invite_variant:c'), 'c');
  for (const k of [null, undefined, '', 'invite_variant:z', 'invite_variant:bb', M365_SEED_KIND, 'sales_engineer_x', ' invite_variant:b']) assertEquals(variantOfKind(k), 'a');
});

Deno.test('campaignMail writes the row kind variant, and a seed is always A', () => {
  const b = campaignMail({ type: 'supplier_invite', kind: 'invite_variant:b', body: 'Hi Sigma Ceramics team,' }, { company: 'Sigma Ceramics' });
  assertEquals(b.subject, 'Which trades does your company cover?');
  assertEquals(b.text, m365InvitationText({ company: 'Sigma Ceramics' }, 'b'));
  assertEquals(b.bad, []);
  const nudge = campaignMail({ type: 'supplier_invite_nudge', kind: 'invite_variant:c', body: '' }, { company: 'Sigma Ceramics' });
  assertEquals(nudge.text, m365InvitationText({ company: 'Sigma Ceramics' }, 'c'));
  const seed = campaignMail({ type: 'supplier_invite_seed', kind: M365_SEED_KIND, body: 'Hello,\n\nid:2026-11-15-10:00:00:000t', subject: 'x' });
  assert(seed.text.startsWith(m365InvitationText({}, 'a')));
});
