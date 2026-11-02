// NOTHING A PERSON SENDS US WAITS, AND THE FOUNDER IS NOT PAGED (ledger 1436, 1447, audit of 2 Nov 2026).
// Reads source only. Fails if a handler goes back to returning 'waiting' for ever, if the rehearsal page or the personal
// number comes back, or if a scheduled send is reported late again.
//   node --test scripts/checks/nothing_a_person_sends_us_waits.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const R = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const MOBILE = /971\s?50\s?931\s?9355|971509319355/;

test('the personal mobile is on no public surface', () => {
  for (const f of ['src/content/marketing.json', 'src/content/company.json',
    'supabase/functions/site_assistant/index.ts',
    'supabase/functions/_shared/ai_reply.ts', 'supabase/functions/_shared/doc_template.ts',
    'supabase/functions/_shared/brand_assets/letterhead.html', 'knowledge/brief/company.md']) {
    assert.doesNotMatch(R(f), MOBILE, f);
  }
});

test('the signed Supplier Agreement keeps its text: the mobile leaves it only with a new version', async () => {
  const { createHash } = await import('node:crypto');
  const m = await import('node:fs');
  const src = m.readFileSync(new URL('../../supabase/functions/_shared/supplier_agreement.ts', import.meta.url), 'utf8');
  const sha = /SUPPLIER_AGREEMENT_SHA256 = '([0-9a-f]{64})'/.exec(src)[1];
  const en = JSON.parse(/SUPPLIER_AGREEMENT_EN = (".*");/.exec(src)[1]);
  const ar = JSON.parse(/SUPPLIER_AGREEMENT_AR = (".*");/.exec(src)[1]);
  assert.equal(createHash('sha256').update(en + '\n' + ar).digest('hex'), sha, 'the agreement text no longer matches its signed hash');
});

test('a request with no supplier does not page the founder, and the form mails nobody', () => {
  const c = R('supabase/functions/customer_api/index.ts');
  assert.doesNotMatch(c, /event: 'rfq_no_supplier'/);
  assert.doesNotMatch(c, /type: 'rfq_no_supplier'/);
  assert.doesNotMatch(R('supabase/functions/contact_submit/index.ts'), /requestDelivery/);
});

test('a mail whose answer died is asked again, then owned (inbound 1615)', () => {
  const s = R('scripts/sql/a_triaged_mail_whose_answer_died_is_asked_again_then_owned.sql');
  assert.match(s, /set triaged_at = null/);
  assert.match(s, /'mailbox\.supplier_reply'/);
  assert.match(s, /'review\.requested'/);
  assert.match(R('scripts/sql/a_supplier_reply_gets_the_action_it_asked_for.sql'), /one e-mail address manages one company/);
});

test('the voice line tells the caller what to do', () => {
  const t = R('supabase/functions/voice_otp/twiml.ts');
  assert.match(t, /Send a WhatsApp message to this same number/);
  assert.match(t, /loop="2"/);
});

test('the reply handlers act, and the expiry keeps a question with a person', () => {
  const a = R('scripts/sql/a_supplier_reply_gets_the_action_it_asked_for.sql');
  assert.match(a, /fn_sales_engineer_takes_invite_reply\(p_id bigint\)\s+returns jsonb language sql volatile/);
  assert.doesNotMatch(a, /FUNCTION public\.fn_sales_engineer_supplier_outreach_tick/, 'the tick is #1744\'s: its complaint stop and sending window must not be overwritten');
  assert.doesNotMatch(a, /FUNCTION public\.fn_sales_engineer_sends_registration_reminder/, 'the sender is #1744\'s');
  assert.match(a, /p_stage in \('incomplete', 'started'\)/, 'the reminder must name only what is missing');
  const b = R('scripts/sql/nothing_a_person_sends_us_waits_without_a_seat_that_acts.sql');
  assert.match(b, /kept_for_a_person_at/);
  assert.match(R('scripts/sql/a_send_scheduled_for_later_is_not_a_late_delivery.sql'), /n\.not_before > now\(\)/);
});

test('a stranger cannot make the contact form mail an address: every unsafe case is held for the seat, not answered, not lost', () => {
  const sql = R('scripts/sql/nothing_a_person_sends_us_waits_without_a_seat_that_acts.sql');
  for (const why of ['suppressed_or_bounced', 'founder_address', 'role_address', 'known_supplier_lane', 'second_message_in_24h', 'daily_ceiling', 'address_shape']) {
    assert.match(sql, new RegExp(`'${why}'`), why);
  }
  assert.match(sql, /case when v_hold is not null then 'customer_support' end/, 'a held message must be owned so triage never answers it');
  assert.match(sql, /'inbound_review'/, 'a held message must be named on a seat item');
  const edge = R('supabase/functions/contact_submit/index.ts');
  assert.match(edge, /answerHold\(email, ip, allow\)/);
  assert.match(edge, /source: 'held:' \+ hold/);
  assert.match(R('supabase/functions/_shared/contact_answer_gate.ts'), /judgeDns/);
  assert.match(R('scripts/sql/nothing_a_person_sends_us_waits_without_a_seat_that_acts_probe.sql'), /was LOST/);
});
