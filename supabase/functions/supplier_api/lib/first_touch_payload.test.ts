// marketing, 15 Nov 2026: fails if a registration with no kept tags stops reaching fn_marketing_first_touch_record
// (the cause of 0 rows in marketing_first_touch while an invited supplier registered).
import { assertEquals } from 'jsr:@std/assert@1';
import { firstTouchPayload, firstTouchRefusal } from './first_touch_payload.ts';

Deno.test('a missing touch is sent as {} so the routine records the opened invitation', () => {
  assertEquals(firstTouchPayload(null), {});
  assertEquals(firstTouchPayload(undefined), {});
  assertEquals(firstTouchPayload('utm_source=x'), {});
  assertEquals(firstTouchPayload([1]), {});
});

Deno.test('kept tags are sent unchanged', () => {
  const t = { utm_source: 'founder', utm_medium: 'whatsapp', utm_campaign: '2026-11', utm_content: null, landing_path: '/portal', first_seen_at: '2026-11-15T19:00:00Z' };
  assertEquals(firstTouchPayload(t), t);
});

Deno.test('only a refusal other than "no tag" is worth a log line', () => {
  assertEquals(firstTouchRefusal({ ok: true, recorded: true }), null);
  assertEquals(firstTouchRefusal({ ok: false, recorded: false, reason: 'no_utm' }), null);
  assertEquals(firstTouchRefusal({ ok: true, recorded: false, reason: 'no lead' }), 'no lead');
  assertEquals(firstTouchRefusal(null), null);
});

Deno.test('registration.ts no longer returns before the call on a missing touch', async () => {
  const src = await Deno.readTextFile(new URL('./registration.ts', import.meta.url));
  const body = src.slice(src.indexOf('export async function recordFirstTouch'), src.indexOf('export async function emailProven'));
  assertEquals(/if \(!touch \|\| typeof touch !== 'object'\) return/.test(body), false);
  assertEquals(body.includes('firstTouchPayload(raw)'), true);
});
