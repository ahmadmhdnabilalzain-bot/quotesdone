// scripts/e2e/knowledge_gap_audit.mjs — the WEEKLY knowledge-gap audit (ledger 1200, 19 Oct 2026). Seat: customer_support
// (owner), sales_engineer (knowledge). Run by a Claude session on the subscription once a week (ruling 1198: knowledge
// is authored and ingested by Claude, never collected by agents through OpenRouter).
//
// ONE LIST, ONE PLACE. public.sales_knowledge_gap already receives every refusal, hedge, correction and guard rewrite
// from the live channels (fn_knowledge_gap_sweep, daily). This audit adds the week's measured misses to it and then
// works the list down: every row ends 'knowledge_added' (the ingest that closed it is named) or 'not_a_gap'.
//
//   list    node scripts/e2e/knowledge_gap_audit.mjs list [--scored <live_seat_conversations_*.scored.json>]...
//           Files each scored conversation below target as a gap (kind 'hedge' when it said "I don't know",
//           else 'corrected'), then prints every open gap. Rows the code can classify without judgement are
//           proposed 'not_a_gap' (an outage reason: the model never answered, so nothing was missing from the
//           knowledge; a ZZ DEMO fixture question; a question about nothing we sell). The rest are the session's to ingest.
//   close   node scripts/e2e/knowledge_gap_audit.mjs close --ids 2,3 --status knowledge_added --ref <commit or PR>
//           Only after the ingest is live (merged and deployed). A 'knowledge_added' close names its ingest in source_ref.
import { readFileSync } from 'node:fs';
import { REF, q } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const all = (f) => argv.flatMap((a, i) => (a === f ? [argv[i + 1]] : []));
const read = (sql) => mgmtRead(REF, sql);
process.env.QD_FIXTURES = '1';
const write = (sql, why) => mgmtFixture(REF, sql, why);

// Not a knowledge gap: the model never answered (an outage or the hold), the question is our own fixture, or it is
// about nothing we sell. Proposed by code, never closed by code: the session confirms with `close`.
const OUTAGE = /^(model_hold|circuit_open|no_model_answer|no model produced|not_reasoned_yet)/i;
export const proposeNotAGap = (g) => OUTAGE.test(g.refusal || '') ? 'outage: the model never answered'
  : /^ZZ DEMO\b/.test(g.question || '') ? 'a ZZ DEMO fixture question'
  : /\b(kfc|mcdonald|macdonald|weather)\b/i.test(g.question || '') ? 'off topic' : null;

if (argv[0] === 'list') {
  for (const f of all('--scored')) {
    const s = JSON.parse(readFileSync(f, 'utf8'));
    for (const g of s.gaps) {
      const question = `[live_seat_conversations ${s.run_tag}] ${g.id} (${g.seat}/${g.lang}) scored ${g.pct}%: ${(g.issues || []).join('; ')}`.slice(0, 1000);
      await write(`insert into public.sales_knowledge_gap (question_norm, question, asks, first_asked_at, last_asked_at, refusal, status, kind, source, source_ref, detector)
        values (${q('lsc:' + s.run_tag + ':' + g.id)}, ${q(question)}, 1, now(), now(), ${q('below the 95% conversation target')}, 'open',
        ${q((g.issues || []).some((i) => /know|not sure|check/i.test(i)) ? 'hedge' : 'corrected')}, 'live_seat_conversations', ${q(s.run_tag + ':' + g.id)}, 'knowledge_gap_audit')
        on conflict (question_norm) do nothing`, 'weekly audit files a measured gap');
    }
  }
  const open = await read(`select id, kind, left(question, 300) question, refusal, asks, source from public.sales_knowledge_gap where status = 'open' order by asks desc, id`);
  const rows = open.map((g) => ({ ...g, proposed_not_a_gap: proposeNotAGap(g) }));
  console.log(JSON.stringify(rows, null, 1));
  console.error(`open gaps ${rows.length}: proposed not_a_gap ${rows.filter((r) => r.proposed_not_a_gap).length}, to ingest ${rows.filter((r) => !r.proposed_not_a_gap).length}`);
} else if (argv[0] === 'close') {
  const ids = (val('--ids') || '').split(',').map(Number).filter((n) => n > 0);
  const status = val('--status'), ref = val('--ref');
  if (!ids.length || !['knowledge_added', 'not_a_gap'].includes(status)) throw new Error('close --ids 1,2 --status knowledge_added|not_a_gap [--ref <ingest>]');
  if (status === 'knowledge_added' && !ref) throw new Error('REFUSED: a knowledge_added close names its ingest (--ref)');
  const r = await write(`update public.sales_knowledge_gap set status = ${q(status)}, closed_at = now()${ref ? `, source_ref = coalesce(source_ref || ' | ', '') || ${q('ingest ' + ref)}` : ''}
    where id in (${ids.join(',')}) and status = 'open' returning id`, 'weekly audit closes gaps');
  console.log(`closed ${r.length} of ${ids.length} as ${status}${ref ? ' by ' + ref : ''}`);
} else if (process.argv[1]?.endsWith('knowledge_gap_audit.mjs')) {
  console.error('usage: knowledge_gap_audit.mjs list|close (see the header)'); process.exit(2);
}
