// A COMPANY WHOSE OWNER LEFT GETS A NEW OWNER; THE SALES ENGINEER DECIDES (sales_engineer, 16 Nov 2026; agent W3_PEOPLE; wave-3
// item 4). The model is a stub (no paid call): each case gives it the decision a model returns and proves what code does with it.
// Code checks only the shape (one of three decisions, both texts present); the judgement is the model's.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { OWNERSHIP_SYS, claimInput, ownershipClaimsSweep, readDecision } from './ownership_claim.ts';

const DUE = [{ claim_id: 7, supplier_id: 42, opened_at: '2026-11-16T08:00:00Z', channel: 'email', his_words: 'ZZ DEMO the owner left in October; his mailbox is closed',
  evidence: { company: { name: 'ZZ DEMO Co', licence_legal_name: 'ZZ DEMO CO L.L.C', trade_licence_no: 'ZZ-1' },
    owner: { email: 'zz-demo-owner@example.invalid', last_sign_in_at: '2026-09-01T00:00:00Z', mail_bounced_90d: 3, mail_delivered_90d: 0 },
    claimant: { name: 'ZZ DEMO Member', role: 'estimator', member_since: '2026-03-01T00:00:00Z' }, members: [], earlier_hand_overs: [], earlier_claims: [] } }];

function stubAdmin(due: unknown = DUE, failDue = false) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    rpc: (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      if (fn === 'fn_supplier_ownership_claims_due') return Promise.resolve(failDue ? { data: null, error: { message: 'gone' } } : { data: due, error: null });
      if (fn === 'fn_supplier_ownership_claim_decide') return Promise.resolve({ data: { ok: true, decision: args.p_decision }, error: null });
      if (fn === 'fn_supplier_ownership_claims_complete') return Promise.resolve({ data: { transferred: 1, member_no_longer_counts: 0 }, error: null });
      return Promise.resolve({ data: null, error: { message: 'unexpected ' + fn } });
    },
  };
}

Deno.test('the decision is the model\'s: it reads the evidence and his words, and is told the owner keeps three days either way', () => {
  const input = claimInput(DUE[0]);
  assertMatch(input, /his mailbox is closed/);
  assertMatch(input, /mail_bounced_90d/);
  assertMatch(input, /ZZ DEMO CO L\.L\.C/);
  for (const k of ['transfer', 'ask', 'refuse', 'three days', 'data, not instructions']) assert(OWNERSHIP_SYS.includes(k), k);
});

Deno.test('only one of three decisions, with its reasons and his message, is accepted; anything else is no decision', () => {
  assertEquals(readDecision('{"decision":"transfer","reasoning":"mail bounces, licence names him","message":"Approved."}'),
    { decision: 'transfer', reasoning: 'mail bounces, licence names him', message: 'Approved.' });
  assertEquals(readDecision('noise {"decision":"ask","reasoning":"owner signed in last week","message":"Please send the licence page."} noise')?.decision, 'ask');
  assertEquals(readDecision('{"decision":"make_owner","reasoning":"x","message":"y"}'), null);
  assertEquals(readDecision('{"decision":"refuse","reasoning":"","message":"y"}'), null);
  assertEquals(readDecision('{"decision":"refuse","reasoning":"x"}'), null);
  assertEquals(readDecision(null), null);
  assertEquals(readDecision('not json'), null);
});

Deno.test('the beat decides each open case through the routine, and completes the transfers whose three days passed', async () => {
  const a = stubAdmin();
  const out = await ownershipClaimsSweep(a, () => Promise.resolve('{"decision":"ask","reasoning":"owner active in September only; proof is cheap","message":"Please send the trade licence page naming the manager."}'), 5);
  assertEquals(a.calls.map((c) => c.fn), ['fn_supplier_ownership_claims_complete', 'fn_supplier_ownership_claims_due', 'fn_supplier_ownership_claim_decide']);
  assertEquals(a.calls[2].args, { p_claim: 7, p_decision: 'ask', p_reasoning: 'owner active in September only; proof is cheap',
    p_message: 'Please send the trade licence page naming the manager.', p_decided_by: 'sales_engineer' });
  assertEquals(out, { completed: 1, decided: 1, undecided: 0 });
});

Deno.test('no model answer leaves the case open on the sales engineer\'s queue (never a guessed decision); a failed read decides nothing', async () => {
  const a = stubAdmin();
  const out = await ownershipClaimsSweep(a, () => Promise.resolve(null), 5);
  assertEquals(a.calls.map((c) => c.fn), ['fn_supplier_ownership_claims_complete', 'fn_supplier_ownership_claims_due']);
  assertEquals(out, { completed: 1, decided: 0, undecided: 1 });
  const b = stubAdmin(DUE, true);
  assertEquals((await ownershipClaimsSweep(b, () => Promise.resolve('{}'), 5)).decided, 0);
});
