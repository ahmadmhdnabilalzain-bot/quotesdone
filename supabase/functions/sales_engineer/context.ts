// sales_engineer — what every module of this function shares: the service-role client, the CORS headers, the JSON responder,
// the secret reader, the streamed caller's emitters, and the request context index.ts hands each action group.
// ONE copy of each; nothing here is declared anywhere else.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import type { Caller } from './lib/caller.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
export const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

export async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}
// The streamed caller's emitter, keyed by its request: the portal reply's checked sentences go out as the model writes them.
export const EMITTERS = new WeakMap<Request, (text: string) => void>();

/** One request, as the actions read it: built once by index.ts after the caller is known and a service caller has been kept to its actions. */
export type ActionCtx = {
  req: Request;
  // the parsed body, exactly as untyped as await req.json().catch(…) gave it in the single-file handler
  // deno-lint-ignore no-explicit-any
  body: any;
  // the caller, never null here: index.ts answered 401 before building the context
  caller: NonNullable<Caller>;
  action: string;
};
