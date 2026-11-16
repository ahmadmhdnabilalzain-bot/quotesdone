// "Not for me", "I'm available", trade corrections, figure confirmation and going on leave: supplier_api/not_for_me.ts decides;
// this resolves the caller's own company from his JWT (sales_engineer, 16 Nov 2026).
import { type ActionCtx, J, admin, failed } from '../context.ts';
import { NOT_FOR_ME_ACTIONS, notForMe } from '../not_for_me.ts';

export async function notForMeActions(c: ActionCtx): Promise<Response | undefined> {
  const { email, body, action } = c;
  if (!(NOT_FOR_ME_ACTIONS as readonly string[]).includes(String(action))) return undefined;
  const { data: sup } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
  if (!sup) return J({ error: 'claim your company first', code: 'no_company' }, 400);
  try { const [s, o] = await notForMe(admin, Number(sup.id), String(action), body ?? {}); return J(o, s); }
  catch (e) { return failed(String(action), e); }
}
