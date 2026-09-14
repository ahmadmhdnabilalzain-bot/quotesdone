// The rules stripe_setup's webhook_ensure follows (webhook_plan.ts). The live cases are the ones the
// independent review of #631 required: a live endpoint is never duplicated and its secret never written.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { drift, ours, planWebhookEnsure, sameSecret } from './webhook_plan.ts';

const REQ = ['checkout.session.completed', 'invoice.paid'] as const;
const PROJECT = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/stripe_webhook';
const VARIANT = 'https://pay.quotesdone.com/functions/v1/stripe_webhook';   // a different host, same handler path
const OTHER = 'https://hooks.example.com/stripe';

Deno.test('ONE matcher: any endpoint ending in the handler path is ours, anything else is not', () => {
  assertEquals(ours([{ url: PROJECT }, { url: VARIANT }, { url: OTHER }]).length, 2);
  assertEquals(ours([{ url: OTHER }]).length, 0);
});

Deno.test('live endpoint exists at a variant URL: no create, no secret write, additive sync only', () => {
  const p = planWebhookEnsure({ mode: 'live', endpoints: [{ id: 'we_live', url: VARIANT, enabled_events: ['checkout.session.completed'] }], required: REQ, secretStored: true });
  assertEquals(p.kind, 'sync');
  assertEquals(p.writesSecret, false);
  if (p.kind === 'sync') { assertEquals(p.endpoint.id, 'we_live'); assertEquals(p.missing, ['invoice.paid']); }
});

Deno.test('live with no endpoint of ours is refused, never created', () => {
  const p = planWebhookEnsure({ mode: 'live', endpoints: [{ url: OTHER }], required: REQ, secretStored: true });
  assertEquals(p.kind, 'refuse');
  assertEquals(p.writesSecret, false);
});

Deno.test('live endpoint whose secret is not stored is refused, never rotated', () => {
  const p = planWebhookEnsure({ mode: 'live', endpoints: [{ url: PROJECT, enabled_events: [...REQ] }], required: REQ, secretStored: false });
  assertEquals(p.kind, 'refuse');
  assertEquals(p.writesSecret, false);
});

Deno.test('test with no endpoint of ours is the only case that creates one and writes a secret', () => {
  const p = planWebhookEnsure({ mode: 'test', endpoints: [{ url: OTHER }], required: REQ, secretStored: false });
  assertEquals(p, { kind: 'create', writesSecret: true });
});

Deno.test('test endpoint that exists is synced additively, never duplicated', () => {
  const synced = planWebhookEnsure({ mode: 'test', endpoints: [{ id: 'we_t', url: PROJECT, enabled_events: ['invoice.paid'] }], required: REQ, secretStored: true });
  assertEquals(synced.kind, 'sync');
  const same = planWebhookEnsure({ mode: 'test', endpoints: [{ id: 'we_t', url: PROJECT, enabled_events: ['*'] }], required: REQ, secretStored: true });
  assertEquals(same.kind, 'in_sync');
});

Deno.test('two endpoints of ours are refused rather than guessed between', () => {
  for (const mode of ['test', 'live'] as const) {
    const p = planWebhookEnsure({ mode, endpoints: [{ url: PROJECT }, { url: VARIANT }], required: REQ, secretStored: true });
    assertEquals(p.kind, 'refuse', mode);
  }
});

Deno.test('drift reports only what is missing, and a wildcard subscription misses nothing', () => {
  assertEquals(drift({ enabled_events: ['invoice.paid'] }, REQ).missing, ['checkout.session.completed']);
  assertEquals(drift({ enabled_events: ['*'] }, REQ), { missing: [], wildcard: true });
});

Deno.test('the token comparison accepts only the exact token', async () => {
  assert(await sameSecret('tok_abc123', 'tok_abc123'));
  for (const g of ['tok_abc12', 'tok_abc1234', 'TOK_abc123', '', 'x']) assert(!(await sameSecret(g, 'tok_abc123')), g);
  assert(!(await sameSecret('', '')), 'an unset stored token never matches');
});
