// inquiry_intake/owed_reply.ts — the portal's poll for a turn filed for the re-ask (`poll_turn_id`). Moved verbatim from
// handle.ts (19 Nov 2026, it_engineer; ledgers 1714/1715/1556: handle.ts was 1,418 lines), which answers it first.
// deno-lint-ignore-file no-explicit-any
import { ACTOR } from '../_shared/intake_requirements.ts';
import { J, admin } from './shared.ts';

// A TURN STILL OWED THE MODEL'S ANSWER IS READ, NEVER RECOMPUTED (_shared/reask.ts). When the model was up and refused
// every draft, the turn was filed for the re-ask and the portal shows "still working on your answer"; it asks here,
// by the turn's id, until the re-asked reply is on the row (reask_of). A read only: no rate-limit slot, nothing written.
export async function owedReply(email: string, b: any, pollId: string): Promise<Response> {
  const { data: row } = await admin.from('inquiry_intake').select('id,email,status,turns').eq('id', b.intake_id).maybeSingle();
  if (!row || row.email !== email) return J({ error: 'not_found' }, 404);
  const a = (Array.isArray(row.turns) ? row.turns : []).find((t: any) => t && t.role === 'assistant' && t.reask_of === pollId);
  // handed to the sales engineer after the last refused re-ask: the portal says it is with them (still UI state)
  const { data: h } = a ? { data: null } : await admin.from('reasoning_held_question').select('escalated_at,status')
    .eq('dedupe_key', 'intake_unwritten:' + row.id + ':' + pollId).maybeSingle();
  return J({ ok: true, polled: true, intake_id: row.id, pending: !a, state: a ? 'answered' : h?.escalated_at ? 'with_team' : 'working',
             assistant_message: a ? String(a.text || '') : '', status: row.status, agent: ACTOR });
}
