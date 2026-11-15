// supplier_api — what every module of this function shares: the CORS headers, the JSON responder, the error
// answer that never carries a database sentence, the service-role client and URL, the secret reader and the
// feature switch, and the request context index.ts hands each action group. ONE copy of each.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { createClient, type User } from 'jsr:@supabase/supabase-js@2';
import type { SafeInquiry } from './quote_review.ts';
import { annotate, maskContact } from '../_shared/observe.ts';

export const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
export const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
// NO DATABASE SENTENCE REACHES A RESPONSE (28 Oct 2026, review of #1712; ledger 1401 audit S7). Six actions answered a
// refused write with the Postgres message itself, eight put a database, storage or exception message in `detail`, and
// the outer catch answered String(e) on every action, create_company's included (sanctionedEmail throws the PostgREST
// error when its read fails). The message is logged here; the caller gets the portal's existing unexpected_error copy.
const SERVER_ERROR = { error: 'Something went wrong. Please try again.', code: 'unexpected_error' } as const;
// THE CAUSE IS KEPT WHERE A SEAT READS IT (13 Nov 2026, it_engineer). The message went to console.error only, i.e. the edge
// function log, which no seat reads: on 13 Nov 08:10:57 a supplier's spec_fill answered unexpected_error after 11.3 s and
// agent_runs said only "unexpected_error"; the cause (fn_customer_support_takes_delivery cancelled by the 8 s statement
// timeout behind a rehearsal's lock on inquiries) had to be dug out of the postgres log. It now rides on the response
// (annotate) into this request's own fn:supplier_api agent_runs row as counts.cause / counts.cause_where, which the IT
// seat's run-cluster duty reads. The browser still never sees a database sentence.
// masked before it is logged AND before it is written (review item 7: a raise or a constraint message can carry an e-mail or a
// phone number; the edge function log is kept and read by more people than the row's owner)
export const failed = (where: string, e: unknown, status = 500) => {
  const cause = maskContact(String((e as { message?: unknown } | null)?.message ?? e));
  console.error(`supplier_api ${where}:`, cause);
  return annotate(J({ ...SERVER_ERROR }, status), { cause_where: where.slice(0, 80), cause: cause.slice(0, 300) });
};
export const logged = (where: string, e: unknown) => { console.error(`supplier_api ${where}:`, maskContact(String((e as { message?: unknown } | null)?.message ?? e))); };
export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
// A WRITE A PERSON DEPENDS ON THAT DID NOT LAND TELLS THE IT SEAT (15 Nov 2026, review 2 of the certificate branch, items 6 and
// A-C). The person is told in the answer; the seat gets one finding per issue key (fn_it_engineer_finding_upsert counts the
// recurrences), with the masked cause. It is FILED IN THE BACKGROUND (EdgeRuntime.waitUntil, as kyc's termsNotRecorded): behind the
// lock that failed the write it can take seconds more, and the person's page must get its sentence first. Never throws.
export function tellItSeat(issueKey: string, title: string, where: string, evidence: Record<string, unknown>): void {
  const file = (async () => {
    try {
      const { error } = await admin.rpc('fn_it_engineer_finding_upsert', {
        p_issue_key: issueKey.slice(0, 120), p_title: title, p_where: where, p_blast: 'customer_facing', p_affected: 1,
        p_evidence: { ...evidence, at: new Date().toISOString() }, p_ruled_out: [],
        p_undetermined: ['why the write failed: read the postgres log at this time for a lock wait or a statement timeout (scripts/lib/replay_guard.mjs)'],
        p_raised_by: 'it_engineer',
      });
      if (error) logged('IT finding not raised (' + issueKey + ')', error);
    } catch (e) { logged('IT finding not raised (' + issueKey + ')', e); }
  })();
  const rt = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } }).EdgeRuntime;
  if (typeof rt?.waitUntil === 'function') rt.waitUntil(file); else file.catch(() => null);
}
export const SUPA_URL = Deno.env.get('SUPABASE_URL')!;

export async function secretVal(key: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle(); return data?.value || null; }

// The same switch supplier_portal reads: the model may be asked about a document only when the
// founder has turned it on (22 Sep 2026, SEATS-02).
export async function flagOn(key: string): Promise<boolean> { return /^(on|true|1)$/i.test(String(await secretVal(key) || '').trim()); }

/** One request, as the actions read it: built once by index.ts after the caller is signed in and cleared. */
export type ActionCtx = {
  req: Request;
  jwt: string;
  user: User;
  email: string;
  // the parsed body and its action, exactly as untyped as `await req.json()` gave them in the single-file handler
  // deno-lint-ignore no-explicit-any
  body: any;
  // deno-lint-ignore no-explicit-any
  action: any;
  /** This function's own handler (index.ts), for the actions that run it in-process with the caller's session. */
  handle: (req: Request) => Promise<Response>;
  /** index.ts safeInquiryOf: the job as the review may read it, through `inbox`. */
  safeInquiryOf: (req: Request, jwt: string, inquiryId: string) => Promise<SafeInquiry | null>;
};
