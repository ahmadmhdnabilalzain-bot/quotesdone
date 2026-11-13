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
