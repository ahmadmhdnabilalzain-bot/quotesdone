// The database and the matcher behind lib/rematch.ts's sweep (sales_engineer, 10 Nov 2026). Kept apart from the rule so
// rematch.test.ts can run the rule with no database; this is the only file that reaches production for it.
import { admin } from '../context.ts';
import { isClosedRequest } from '../../_shared/request_closed.ts';
import { matchAndNotify } from './matching.ts';
import { matcherFindingKey, type RematchIO, type WaitingRequest } from './rematch.ts';

export function liveRematchIO(): RematchIO {
  return {
    waiting: async (limit) => {
      const { data, error } = await admin.from('inquiries').select('id,category,emirate,summary,budget,routing,parent_inquiry_id')
        .eq('status', 'sent').eq('routing->>matcher_unavailable', 'true').order('created_at').limit(limit);
      if (error) throw new Error(error.message);
      const rows = (data || []) as (WaitingRequest & { parent_inquiry_id: string | null })[];
      // A per-trade part whose combined request the customer cancelled (or that is otherwise closed) is not matched again.
      const parents = [...new Set(rows.map((r) => r.parent_inquiry_id).filter(Boolean))] as string[];
      const closed = new Set<string>();
      if (parents.length) {
        const { data: ps } = await admin.from('inquiries').select('id,status').in('id', parents);
        for (const p of ps || []) if (isClosedRequest(p.status)) closed.add(String(p.id));
      }
      return rows.filter((r) => !r.parent_inquiry_id || !closed.has(String(r.parent_inquiry_id)));
    },
    claim: async (id, routingBefore, leaseUntil) => {
      const before = routingBefore?.rematch?.next_at ?? null;
      const leased = { ...(routingBefore || {}), rematch: { ...(routingBefore?.rematch || {}), next_at: leaseUntil, leased_at: new Date().toISOString() } };
      let q = admin.from('inquiries').update({ routing: leased }).eq('id', id).eq('status', 'sent');
      q = before == null ? q.is('routing->rematch->>next_at', null) : q.eq('routing->rematch->>next_at', String(before));
      const { data, error } = await q.select('id');
      return !error && Array.isArray(data) && data.length === 1;
    },
    match: (id, opts, prior) => matchAndNotify(id, opts, prior),
    told: async (id, matches) => {
      const { data, error } = await admin.rpc('fn_sales_engineer_rematch_told', { p_inquiry: id, p_matches: matches });
      if (error) throw new Error('fn_sales_engineer_rematch_told: ' + error.message);
      return data;
    },
    closeFinding: async (id, note) => { await admin.rpc('fn_it_engineer_finding_close', { p_issue_key: matcherFindingKey(id), p_note: note }); },
  };
}
