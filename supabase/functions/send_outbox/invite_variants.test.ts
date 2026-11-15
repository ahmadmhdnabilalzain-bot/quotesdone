// THE INVITATION COPY TEST (15 Nov 2026, marketing): every variant is held to the founder's copy rules, the variant comes only
// from the row's kind, and a row without one (a seed, an older row) is the approved text A.
// scripts/sql/the_invitation_ramps_on_measured_health_and_tests_its_copy.sql fixes each lead's variant and writes the kind.
import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import { campaignMail, INVITE_VARIANTS, m365CopyLint, m365InvitationText, m365Subject, M365_SEED_KIND, variantOfKind } from './m365_lane.ts';

const WHO = [{}, { company: 'Sigma Ceramics' }, { company: 'Sigma Ceramics', trade: 'tiling' }, { trade: 'fire_safety' }];

Deno.test('every variant passes every copy rule, with and without a company and a trade', () => {
  for (const v of INVITE_VARIANTS) for (const who of WHO) {
    const body = m365InvitationText(who, v); const subject = m365Subject(who, v);
    for (const l of m365CopyLint({ subject, body })) assert(l.ok, `variant ${v} ${JSON.stringify(who)}: ${l.rule}: ${l.detail}`);
    assert(!/\b(free|join|register|commission|1,000|invitation|exclusive)\b/i.test(body + ' ' + subject), `variant ${v} carries an offer phrase`);
    assert(!/\b(buyers are|customers are) (already )?sending\b/i.test(body), `variant ${v} claims buyers that do not exist yet`);
  }
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
