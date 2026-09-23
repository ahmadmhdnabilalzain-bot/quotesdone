// reasoned_routing with a mocked model: each decision answered each way, held -> no guess and queued with
// its surface, dedupe key and subject; and the SQL that files these questions uses the same option ids.
import { assert, assertEquals } from 'jsr:@std/assert';
import type { ThinkDeps } from './think.ts';
import {
  DOCUMENT_SUBJECT, ESCALATION_LEGAL, ESCALATION_NEITHER, ESCALATION_REPEAT, REFUND_OFF_PLATFORM, SAME_REQUEST, TASK_RESPONSIBILITY_NONE,
  collaborationRuleOptions, escalationMeaning, escalationOptions, refundOffPlatform, sameInquiry, supplierDocumentSubject,
  taskCollaborationRule, taskResponsibility, taskResponsibilityOptions,
} from './reasoned_routing.ts';

const PLAN = JSON.stringify({ steps: [{ id: 's1', goal: 'read what was written', query: 'q', needs_knowledge: false }], facts: [] });
function mock(o: { held?: boolean; choice?: string }) {
  const rpcs: [string, Record<string, unknown>][] = []; let llm = 0;
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.held ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : { allowed: false, rule: 'route_not_registered' }) as never),
    llm: (phase) => {
      llm++;
      if (phase === 'decompose') return Promise.resolve({ content: PLAN, model: 'm' });
      return Promise.resolve({ content: JSON.stringify({ answer: 'Read the text and chose.', reasoning: ['s1: read it'], cited: [], confidence: 0.8, asked_back: null, decision: { choice: o.choice } }), model: 'm' });
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: fn === 'fn_reason_hold' ? 7 : null, error: null }); },
  };
  return { deps, rpcs, llmCalls: () => llm };
}
const heldCall = (m: ReturnType<typeof mock>) => m.rpcs.find(([f]) => f === 'fn_reason_hold')?.[1] as Record<string, unknown> | undefined;

Deno.test('escalation: reasoned legal / repeat / neither; held files ceo.escalation_meaning and guesses nothing', async () => {
  const cands = [{ id: 12, headline: 'ZZ we paid a supplier before the licence check' }];
  const base = { text: 'ZZ the supplier kept the deposit and we will go to court', kind: 'escalate', actor: 'sales_engineer', legalTriggers: ['dispute', 'liability'], candidates: cands, dedupeKey: 'ceo.escalation:abc' };
  assertEquals((await escalationMeaning(mock({ choice: ESCALATION_LEGAL }).deps, base)).value, 'legal_matter');
  assertEquals((await escalationMeaning(mock({ choice: ESCALATION_REPEAT + 12 }).deps, base)).value, 'repeats_failure_12');
  assertEquals((await escalationMeaning(mock({ choice: ESCALATION_NEITHER }).deps, base)).value, 'neither');
  const m = mock({ held: true });
  const r = await escalationMeaning(m.deps, base);
  assertEquals(r.value, null);
  assertEquals(r.result.status, 'held');
  assertEquals(m.llmCalls(), 0, 'no model is called under the hold');
  const h = heldCall(m)!;
  assertEquals([h.p_seat, h.p_surface, h.p_dedupe_key], ['ceo', 'ceo.escalation_meaning', 'ceo.escalation:abc']);
  assertEquals(h.p_subject, { kind: 'escalate', actor: 'sales_engineer' });
  assertEquals(escalationOptions(['dispute'], cands).map((x) => x.id), ['legal_matter', 'repeats_failure_12', 'neither']);
});

Deno.test('an option the model invents is refused, never taken', async () => {
  const r = await escalationMeaning(mock({ choice: 'dispute' }).deps, { text: 'ZZ x', kind: 'approve', actor: 'ceo', legalTriggers: [], candidates: [], dedupeKey: 'k' });
  assertEquals(r.value, null);
  assertEquals(r.result.status, 'held');
});

Deno.test('refund notes: engaged / not; held queues ceo.refund_off_platform with the refund as subject', async () => {
  const o = { transactionId: 'tx-1', refundId: 5, note: 'Refund note: ZZ she paid him in cash at the site', dedupeKey: 'refund_offp:tx-1:md5' };
  assertEquals((await refundOffPlatform(mock({ choice: 'engaged_off_platform' }).deps, o)).value, 'engaged_off_platform');
  assertEquals((await refundOffPlatform(mock({ choice: 'not_off_platform' }).deps, o)).value, 'not_off_platform');
  const m = mock({ held: true });
  assertEquals((await refundOffPlatform(m.deps, o)).value, null);
  const h = heldCall(m)!;
  assertEquals([h.p_seat, h.p_surface, h.p_dedupe_key], ['ceo', 'ceo.refund_off_platform', 'refund_offp:tx-1:md5']);
  assertEquals(h.p_subject, { transaction_id: 'tx-1', refund_id: 5 });
});

Deno.test('supplier document: each subject; held queues supplier_documents.subject for the sales engineer', async () => {
  const o = { documentId: 9, leadId: 3, label: 'ZZ شهادة الأيزو 9001', kind: 'supporting:certificate', dedupeKey: 'supdoc:9:md5' };
  for (const id of ['iso', 'insurance', 'manufacturer_auth', 'none']) assertEquals((await supplierDocumentSubject(mock({ choice: id }).deps, o)).value, id);
  const m = mock({ held: true });
  assertEquals((await supplierDocumentSubject(m.deps, o)).value, null);
  const h = heldCall(m)!;
  assertEquals([h.p_seat, h.p_surface, h.p_dedupe_key], ['sales_engineer', 'supplier_documents.subject', 'supdoc:9:md5']);
  assertEquals(h.p_subject, { document_id: 9, lead_id: 3 });
});

Deno.test('repeat request: same / different; held queues inquiry.same_request', async () => {
  const o = { inquiryId: 'i2', earlierId: 'i1', earlier: 'ZZ lay 20 m2 porcelain', current: 'ZZ kitchen floor, twenty square metres', dedupeKey: 'inquiry_dup:i2' };
  assertEquals((await sameInquiry(mock({ choice: 'same_request' }).deps, o)).value, 'same_request');
  assertEquals((await sameInquiry(mock({ choice: 'different_request' }).deps, o)).value, 'different_request');
  const m = mock({ held: true });
  assertEquals((await sameInquiry(m.deps, o)).value, null);
  assertEquals(heldCall(m)!.p_surface, 'inquiry.same_request');
  assertEquals(heldCall(m)!.p_subject, { inquiry_id: 'i2', earlier_id: 'i1' });
});

Deno.test('task: responsibility and collaboration rule reasoned; held queues each for the CEO seat', async () => {
  const rows = [{ responsibility: 'business_development', os_key: 'sales' }, { responsibility: 'sales', os_key: 'sales' }];
  const o = { taskId: 4, deptKey: 'exec', author: 'ceo', text: 'ZZ find three new facility managers', rows, dedupeKey: 'task_resp:4:md5' };
  assertEquals((await taskResponsibility(mock({ choice: 'business_development' }).deps, o)).value, 'business_development');
  assertEquals((await taskResponsibility(mock({ choice: TASK_RESPONSIBILITY_NONE }).deps, o)).value, 'none');
  const m = mock({ held: true });
  assertEquals((await taskResponsibility(m.deps, o)).value, null);
  assertEquals(heldCall(m)!.p_subject, { task_id: 4, dept_key: 'exec', author: 'ceo' });
  assertEquals(taskResponsibilityOptions(rows).map((x) => x.id), ['business_development', 'sales', 'none']);
  const ro = { taskId: 4, ruleId: 2, situation: 'Publishing anything externally', text: 'ZZ post the Q3 update', dedupeKey: 'task_rule:4:2:md5' };
  assertEquals((await taskCollaborationRule(mock({ choice: 'applies' }).deps, ro)).value, 'applies');
  assertEquals((await taskCollaborationRule(mock({ choice: 'does_not_apply' }).deps, ro)).value, 'does_not_apply');
  const m2 = mock({ held: true });
  assertEquals((await taskCollaborationRule(m2.deps, ro)).value, null);
  assertEquals([heldCall(m2)!.p_surface, heldCall(m2)!.p_dedupe_key], ['ceo.task_collaboration_rule', 'task_rule:4:2:md5']);
});

Deno.test('the SQL that files these questions uses the same surfaces and option ids (no drift)', () => {
  const sql = Deno.readTextFileSync(new URL('../../../scripts/sql/routing_and_ceo_decisions_are_reasoned_not_word_matched.sql', import.meta.url));
  const ids = [...DOCUMENT_SUBJECT, ...REFUND_OFF_PLATFORM, ...SAME_REQUEST, ...collaborationRuleOptions('x')].map((x) => x.id)
    .concat([ESCALATION_LEGAL, ESCALATION_NEITHER, ESCALATION_REPEAT, TASK_RESPONSIBILITY_NONE]);
  for (const id of ids) assert(sql.includes(`'${id}`), `the SQL has no option ${id}`);
  for (const s of ['ceo.escalation_meaning', 'ceo.refund_off_platform', 'supplier_documents.subject', 'inquiry.same_request', 'ceo.task_responsibility', 'ceo.task_collaboration_rule']) {
    assert(sql.includes(`'${s}'`), `the SQL files no ${s}`);
  }
  for (const s of ['ceo__escalation_meaning', 'ceo__refund_off_platform', 'ceo__task_responsibility', 'ceo__task_collaboration_rule', 'inquiry__same_request']) {
    assert(sql.includes(`create or replace function public.fn_reason_apply_${s}(p_id bigint, p_result jsonb)`), `no replay effect for ${s}`);
  }
});
