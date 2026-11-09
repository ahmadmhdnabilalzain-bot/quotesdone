// customer_api — what every module of this function shares: the service-role client, the URL and key,
// the CORS headers, the JSON responder, the per-hour limits, the secret reader, and the request context
// index.ts hands each action group. ONE copy of each; nothing here is declared anywhere else.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { createClient, type User } from 'jsr:@supabase/supabase-js@2';

export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
export const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
export const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
export const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
export const INQUIRY_LIMIT_PER_HOUR = 20;
export const PDF_LIMIT_PER_HOUR = 40;

export async function getSecret(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }

/** One request, as the actions read it: built once by index.ts after the caller is signed in and found. */
export type ActionCtx = {
  req: Request;
  // the parsed body, exactly as untyped as `await req.json()` gave it in the single-file handler
  // deno-lint-ignore no-explicit-any
  body: any;
  action: string;
  user: User;
  email: string;
  // the customers row (select('*') on the untyped client: any, as it was)
  // deno-lint-ignore no-explicit-any
  cust: any;
  recordTermsAcceptance: () => Promise<boolean>;
};
