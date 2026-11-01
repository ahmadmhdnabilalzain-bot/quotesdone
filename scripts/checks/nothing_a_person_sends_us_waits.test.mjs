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
  for (const f of ['src/content/marketing.json', 'src/content/company.json', 'src/content/legal.json',
    'supabase/functions/_shared/supplier_agreement.ts', 'supabase/functions/site_assistant/index.ts',
    'supabase/functions/_shared/ai_reply.ts', 'supabase/functions/_shared/doc_template.ts',
    'supabase/functions/_shared/brand_assets/letterhead.html', 'knowledge/brief/company.md']) {
    assert.doesNotMatch(R(f), MOBILE, f);
  }
});

test('a request with no supplier does not page the founder, and the form mails nobody', () => {
  const c = R('supabase/functions/customer_api/index.ts');
  assert.doesNotMatch(c, /event: 'rfq_no_supplier'/);
  assert.doesNotMatch(c, /type: 'rfq_no_supplier'/);
  assert.doesNotMatch(R('supabase/functions/contact_submit/index.ts'), /requestDelivery/);
});

test('the voice line tells the caller what to do', () => {
  const t = R('supabase/functions/voice_otp/twiml.ts');
  assert.match(t, /Send a WhatsApp message to this same number/);
  assert.match(t, /loop="2"/);
});

test('the reply handlers act, and the expiry keeps a question with a person', () => {
  const a = R('scripts/sql/a_supplier_reply_gets_the_action_it_asked_for.sql');
  assert.match(a, /fn_sales_engineer_takes_invite_reply\(p_id bigint\)\s+returns jsonb language sql volatile/);
  assert.match(a, /r\.stage = 'clicked' and v_why is not null/, 'a paused campaign must not stop chasing a started supplier');
  assert.match(a, /p_stage in \('incomplete', 'started'\)/, 'the reminder must name only what is missing');
  const b = R('scripts/sql/nothing_a_person_sends_us_waits_without_a_seat_that_acts.sql');
  assert.match(b, /kept_for_a_person_at/);
  assert.match(R('scripts/sql/a_send_scheduled_for_later_is_not_a_late_delivery.sql'), /n\.not_before > now\(\)/);
});
