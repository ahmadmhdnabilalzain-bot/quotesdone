// commentClass with a MOCKED model: the class is reasoned among the eight policy classes; held is null and queued.
//   deno test --no-lock --allow-read=. supabase/functions/_shared/reasoned_social.test.ts
import { assertEquals } from 'jsr:@std/assert';
import { CLASSES, commentClass } from './reasoned_social.ts';
import { mockDeps } from './reasoned_trades.test.ts';

const EV = { platform: 'instagram' as const, commentId: 'c1', authorId: 'ZZDEMO1', text: 'Is this a scam? how do I register as a supplier' };

Deno.test('answered: the reasoned class stands, whatever words the comment uses', async () => {
  assertEquals((await commentClass(mockDeps({ choice: 'supplier_enquiry' }).deps, EV)).value, 'supplier_enquiry');
  assertEquals((await commentClass(mockDeps({ choice: 'spam_abuse' }).deps, { ...EV, text: 'Get 10k followers now' })).value, 'spam_abuse');
  assertEquals(CLASSES.length, 8);
});

Deno.test('held: null (nothing is hidden or said), queued under social_comment_class:<platform>:<id> with the comment as subject', async () => {
  const m = mockDeps({ hold: true });
  const r = await commentClass(m.deps, EV);
  assertEquals(r.value, null);
  const hold = m.rpcs.find(([f]) => f === 'fn_reason_hold')![1];
  assertEquals([hold.p_seat, hold.p_surface, hold.p_dedupe_key], ['marketing', 'marketing_social.comment_classify', 'social_comment_class:instagram:c1']);
  assertEquals(hold.p_subject, { platform: 'instagram', message_id: 'c1', user_id: 'ZZDEMO1' });
});

Deno.test('a revived replay is queued under a FRESH key (its first held question is closed)', async () => {
  const m = mockDeps({ hold: true });
  await commentClass(m.deps, { ...EV, retry: 'replaying:2026-09-23T10:00:00Z' });
  assertEquals(m.rpcs.find(([f]) => f === 'fn_reason_hold')![1].p_dedupe_key, 'social_comment_class:instagram:c1:replaying:2026-09-23T10:00:00Z');
});

Deno.test('a class that is not one of the eight is never used', async () => {
  assertEquals((await commentClass(mockDeps({ choice: 'hate' }).deps, EV)).value, null);
});
