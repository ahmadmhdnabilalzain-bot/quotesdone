// Serve THIS checkout's edge function on 127.0.0.1:<port>, against the real database and the real (deployed) ai_gateway, so
// scripts/eval/conversation_quality.mjs measures a branch's code before it is deployed (customer_support, 3 Nov 2026; the
// --model gateway pattern of the document-intake suite). The function's own observe() wrapper honours the caller's
// x-qd-e2e-run only with proof (the service bearer or x-qd-e2e-secret, _shared/e2e_run.ts), and every call it makes back to
// the project carries the tag, so its model calls are costed and capped by the run's rehearsal window.
//
//   SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… deno run -A --no-lock --node-modules-dir=auto scripts/eval/serve_function_locally.ts <slug> <port>
// Prints "LISTENING <port>" once it accepts requests.
const [slug, port] = Deno.args;
if (!/^[a-z_]+$/.test(slug || '') || !/^\d{4,5}$/.test(port || '')) { console.error('usage: <slug> <port>'); Deno.exit(2); }
// the edge runtime's background-work hook: keep the promise alive and swallow its failure, as the platform does
(globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime ??= { waitUntil: (p: Promise<unknown>) => { p.catch(() => {}); } };
const serve = Deno.serve.bind(Deno);
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (a: any, b?: any) => serve({ port: Number(port), hostname: '127.0.0.1', onListen: () => console.log('LISTENING ' + port) },
  typeof a === 'function' ? a : typeof b === 'function' ? b : a.handler);
await import(new URL(`../../supabase/functions/${slug}/index.ts`, import.meta.url).href);
