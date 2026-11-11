// _shared/load_stub.ts limiterScope and isLoadRun (it_engineer, 11 Nov 2026, ruling 1622): a load run's widget turns
// spend their own limiter buckets, and only an open load window makes a run a load run. The gateway's half of the rule
// (who gets the canned completion) is pinned against the real handler in ai_gateway/load_stub.test.ts.
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock supabase/functions/_shared/load_stub.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { CANNED_TEXT, CANNED_TEXT_AR, cannedContent, cannedLang, isLoadRun, limiterScope } from './load_stub.ts';
import { siteReplyCheck, siteReplyLanguage } from '../site_assistant/reply_check.ts';

Deno.test('limiterScope: a real visitor keeps the real buckets; a load run gets its own, the global ceiling included', () => {
  assertEquals(limiterScope('203.0.113.9', null), { ip: '203.0.113.9', globalKey: 'site_assistant_global_day' });
  const s = limiterScope('198.18.0.7', 'zzload1');
  assertEquals(s.globalKey, 'load:zzload1:site_assistant_global_day');
  assert(s.ip.startsWith('load:zzload1:'));
  assert(s.globalKey !== 'site_assistant_global_day', 'a load run must never spend the real daily ceiling');
});

function adminWith(row: unknown, error: unknown = null) {
  const q: Record<string, unknown> = {};
  for (const m of ['select', 'eq', 'is', 'order', 'limit']) q[m] = () => q;
  q.maybeSingle = () => Promise.resolve({ data: row, error });
  return { from: (_t: string) => q };
}
const SOON = () => new Date(Date.now() + 600_000).toISOString();

Deno.test('isLoadRun: only a proven tag with an open load window', async () => {
  const open = { opened_by: 'load_test', models_allowed: false, ended_at: null, expires_at: SOON(), note: null };
  assertEquals(await isLoadRun(adminWith(open), null), false, 'no tag reads nothing and is not a load run');
  assertEquals(await isLoadRun(adminWith(open), 'zzload1'), true);
  assertEquals(await isLoadRun(adminWith({ ...open, opened_by: 'demo_factory.withRun' }), 'zzload1'), false);
  assertEquals(await isLoadRun(adminWith({ ...open, models_allowed: true }), 'zzload1'), false);
  assertEquals(await isLoadRun(adminWith(null), 'zzload1'), false);
  assertEquals(await isLoadRun(adminWith(open, { message: 'down' }), 'zzload1'), false);
});

// THE STUB'S WORDS PASS THE WIDGET'S CHECKS IN BOTH LANGUAGES (11 Nov 2026), so a load run measures the chat path and not
// the language check: the first run's English stub sent every Arabic conversation down the whole model ladder.
Deno.test('cannedLang reads the caller\'s reply rule first, then the message; both canned replies pass the widget\'s checks', () => {
  assertEquals(cannedLang("- Reply in Arabic in the customer's own register", []), 'ar');
  assertEquals(cannedLang('- Reply in UAE English, the language this conversation is in', [{ role: 'user', content: 'كيف تعمل المنصة؟' }]), 'en');
  assertEquals(cannedLang('', [{ role: 'user', content: 'كيف تعمل المنصة؟' }]), 'ar');
  assertEquals(cannedLang('', [{ role: 'user', content: 'How does it work?' }]), 'en');
  assertEquals(cannedLang('', 'not a list'), 'en');
  assertEquals(JSON.parse(cannedContent(true, 'ar')).reply, CANNED_TEXT_AR);
  for (const [lang, text] of [['en', CANNED_TEXT], ['ar', CANNED_TEXT_AR]] as const) {
    assertEquals(siteReplyLanguage(lang)(text), [], lang + ' language');
    const check = siteReplyCheck('# brief', 'rules', lang);
    for (const s of text.split(/(?<=[.?!؟])\s+/)) assertEquals(check(s), [], lang + ': ' + s);
  }
});
