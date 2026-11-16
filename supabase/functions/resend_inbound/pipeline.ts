// resend_inbound: READING one verified delivery, the steps index.ts's handler ran inside the webhook request until 15 Nov 2026.
// Unchanged, and in the same order: each step hands on what the next one reads, and the first Response a step gives is the
// outcome. Since 15 Nov 2026 (it_engineer; scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql) the webhook
// only records the delivery in public.inbound_mail_queue and answers; lib/queue.ts's reader calls this for each message it
// claims. An exception is NOT caught here: the reader counts it as a failed attempt and reads the message again later.
import { readMail } from './steps/read_mail.ts';
import { marketingReplies } from './steps/marketing_replies.ts';
import { expenseGate } from './steps/expense_gate.ts';
import { bounceUnsubscribe } from './steps/bounce_unsubscribe.ts';
import { receipts } from './steps/receipts.ts';
import { supplierDocs } from './steps/supplier_docs.ts';
import type { Out as AuthenticateOut } from './steps/authenticate.ts';

/** `req` carries the delivery's svix-id header (the receipt key's fallback); `raw` is the body exactly as it was verified. */
export async function readDelivery(c1: Pick<AuthenticateOut, 'req' | 'raw'>): Promise<Response> {
  const c2 = await readMail(c1 as AuthenticateOut); if (c2 instanceof Response) return c2;
  const c3 = await marketingReplies(c2); if (c3 instanceof Response) return c3;
  const c4 = await expenseGate(c3); if (c4 instanceof Response) return c4;
  const c5 = await bounceUnsubscribe(c4); if (c5 instanceof Response) return c5;
  const c6 = await receipts(c5); if (c6 instanceof Response) return c6;
  return await supplierDocs(c6);
}
