// deno test supabase/functions/_shared/deliver.test.ts
// requestDelivery reports a row that was refused or filed-but-not-queued, and does NOT report a demo row
// the door deliberately did not file (handoff_id null, no error: ruling 1199).
import { requestDelivery } from './deliver.ts';

const admin = (data: unknown) => ({ rpc: async () => ({ data, error: null }) });
const eq = (a: unknown, b: unknown, m: string) => { if (a !== b) throw new Error(`${m}: ${a} !== ${b}`); };

Deno.test('a demo row the door did not file is not an error', async () => {
  const r = await requestDelivery(admin([{ handoff_id: null, seat: 'sales_engineer', status: null, notification_id: null, error: null }]), { type: 'quote_received' });
  eq(r.error, null, 'demo row');
});
Deno.test('a filed row with nothing queued is an error', async () => {
  const r = await requestDelivery(admin([{ handoff_id: 7, seat: 'sales_engineer', status: 'failed', notification_id: null, error: null }]), { type: 'quote_received' });
  eq(!!r.error, true, 'filed, not queued');
});
Deno.test('a refused row is an error', async () => {
  const r = await requestDelivery(admin([{ handoff_id: null, seat: 'x', status: null, notification_id: null, error: 'refused' }]), { type: 'quote_received' });
  eq(!!r.error, true, 'refused');
});
Deno.test('a queued row is fine', async () => {
  const r = await requestDelivery(admin([{ handoff_id: 7, seat: 'x', status: 'done', notification_id: 9, error: null }]), { type: 'quote_received' });
  eq(r.error, null, 'queued');
});
