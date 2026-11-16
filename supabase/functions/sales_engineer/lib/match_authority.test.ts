// matchAuthority: the sales engineer's 'match' on the subject-aware authority rule (third review, item 6). No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { matchAuthority, routineIsMissing, type Rpc, type RpcResult } from './match_authority.ts';

function rpcOf(answers: RpcResult[]) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const rpc: Rpc = (fn, args) => { calls.push({ fn, args }); return Promise.resolve(answers[Math.min(calls.length - 1, answers.length - 1)]); };
  return { rpc, calls };
}

Deno.test('a permitted match passes the request as the subject and the ask', async () => {
  const m = rpcOf([{ data: { may_act: true, grant: 'sales.matching' }, error: null }]);
  const r = await matchAuthority(m.rpc, ' 9b1d ');
  assertEquals(r.ok, true);
  assertEquals(m.calls.length, 1);
  assertEquals(m.calls[0].args.p_subject, 'inquiry:9b1d');
  assertEquals((m.calls[0].args.p_ask as Record<string, unknown>).facts, { inquiry_id: '9b1d' });
});

Deno.test('a refusal the rule asked the CEO about is 202 with the hand-over, not 403', async () => {
  const m = rpcOf([{ data: { may_act: false, route: 'ceo_case_decision', asked: true, handoff_id: 412, status: 'pending', reason: 'no grant' }, error: null }]);
  const r = await matchAuthority(m.rpc, 'abc');
  assert(!r.ok);
  if (!r.ok) {
    assertEquals(r.status, 202);
    assertEquals(r.body.asked, true);
    assertEquals(r.body.handoff_id, 412);
    assertEquals(r.body.status, 'pending');
    assert(String(r.body.message).startsWith('asked the CEO (ceo.authority #412); the answer lands on that hand-over and in your pool block; call again after allow_once'));
  }
});

Deno.test('a refusal that asked nobody (a hard limit, no subject) stays 403', async () => {
  for (const data of [{ may_act: false, route: 'hard_limit', asked: false }, { may_act: false, route: 'ceo_case_decision', asked: false, not_asked_because: 'no subject' }]) {
    const r = await matchAuthority(rpcOf([{ data, error: null }]).rpc, '');
    assert(!r.ok && r.status === 403, JSON.stringify(r));
  }
});

Deno.test('before the SQL is applied the old three-argument form answers (no deploy-order hazard)', async () => {
  const m = rpcOf([{ data: null, error: { code: 'PGRST202', message: 'Could not find the function public.fn_agent_may_act(p_amount_aed, p_ask, p_grantee_role_id, p_action_class, p_subject)' } },
                   { data: { may_act: true }, error: null }]);
  const r = await matchAuthority(m.rpc, 'x1');
  assertEquals(r.ok, true);
  assertEquals(m.calls.length, 2);
  assertEquals(Object.keys(m.calls[1].args).sort(), ['p_action_class', 'p_amount_aed', 'p_grantee_role_id']);
});

Deno.test('another error is 403 with its detail, and is not retried', async () => {
  const m = rpcOf([{ data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } }]);
  const r = await matchAuthority(m.rpc, 'x2');
  assert(!r.ok && r.status === 403 && String(r.body.detail).includes('timeout'));
  assertEquals(m.calls.length, 1);
  assert(!routineIsMissing({ code: '57014', message: 'timeout' }));
  assert(routineIsMissing({ message: 'function public.fn_agent_may_act(text, text, numeric, text, jsonb) does not exist' }));
});
