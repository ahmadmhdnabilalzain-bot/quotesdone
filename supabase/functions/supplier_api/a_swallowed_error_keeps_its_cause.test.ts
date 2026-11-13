// A SWALLOWED ERROR KEEPS ITS CAUSE WHERE A SEAT READS IT (it_engineer, 13 Nov 2026).
// 13 Nov 08:10:57: spec_fill answered unexpected_error after 11.3 s and its fn:supplier_api agent_runs row said nothing more;
// the cause (fn_customer_support_takes_delivery cancelled by the statement timeout) was only in the edge function log.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { annotationsOf } from '../_shared/observe.ts';

Deno.test('failed() answers the generic sentence and puts the cause on the agent_runs row, never in the body', async () => {
  // context.ts builds its service client at import: a local address that is never called here.
  if (!Deno.env.get('SUPABASE_URL')) Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
  if (!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'not-a-key');
  const { failed } = await import('./context.ts');
  const quiet = console.error; console.error = () => {};
  const res = failed('unhandled in spec_fill', new Error('canceling statement due to statement timeout'));
  console.error = quiet;
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body, { error: 'Something went wrong. Please try again.', code: 'unexpected_error' });
  const ann = annotationsOf(res) ?? {};
  assertEquals(ann.cause_where, 'unhandled in spec_fill');
  assertEquals(ann.cause, 'canceling statement due to statement timeout');
});

Deno.test('the outer catch names the action it was in', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(src.includes("return failed(actionName ? `unhandled in ${actionName}` : 'unhandled', e);"));
  assert(/actionName = String\(action \?\? ''\)\.slice\(0, 40\);/.test(src));
});

// Review of 13 Nov 2026, item 7: a raise or a constraint message can carry a person's e-mail or phone, and agent_runs is read by
// every seat and kept. The cause is masked before it is written; the shape of the failure stays readable.
Deno.test('the cause written to agent_runs carries no e-mail address and no phone number', async () => {
  if (!Deno.env.get('SUPABASE_URL')) Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
  if (!Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')) Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'not-a-key');
  const { failed } = await import('./context.ts');
  const quiet = console.error; console.error = () => {};
  const res = failed('unhandled in save_profile', new Error('duplicate key value violates unique constraint "leads_email_key": Key (email)=(zz.person@company-zz.ae) exists; mobile +971 50 123 4567 or 0501234567, landline 04 123 4567, lead 159271'));
  console.error = quiet;
  const cause = String((annotationsOf(res) ?? {}).cause);
  assert(!/@/.test(cause) && !/123 ?4567/.test(cause), cause);
  assert(cause.includes('<email>') && cause.includes('<phone>'), cause);
  assert(cause.includes('leads_email_key') && cause.includes('lead 159271'), 'the failure is still readable (a short id is not a phone)');
});

Deno.test('supplier_api accept_terms records through the same read-back as kyc, and answers the sentence when it did not land', () => {
  const all = Deno.readTextFileSync(new URL('./actions/profile.ts', import.meta.url));
  const src = all.slice(all.indexOf("if (action === 'accept_terms')"), all.indexOf("if (action === 'settings')"));
  assert(src.includes("const w = await recordAcceptance(() => admin.from('leads').update(upd).eq('id', sup.id).select('id'));"));
  assert(src.includes('if (!w.ok) return annotate(J({ ...TERMS_NOT_RECORDED }, w.blip ? 503 : 500)'));
  assert(!/const \{ error \} = await admin\.from\('leads'\)\.update\(upd\)/.test(src), 'the write whose blip answered a generic 500');
});
