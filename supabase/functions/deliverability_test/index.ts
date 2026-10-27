// deliverability_test — the GlockApps inbox-placement test of the supplier invitation, run without the founder
// (27 Oct 2026; Assigned: it_engineer; founder ledger 1312).
//
//   POST {action:'create'}   create a GlockApps manual test, read its seed list and test id, and queue one seed per
//                            address as notifications (type supplier_invite_seed, kind invite_m365_seed) carrying the
//                            live invite_subject / invite_body with "id:<testId>" as the last line, so send_outbox's
//                            Microsoft 365 lane sends them from supplier@quotesdone.com (send_outbox/m365_lane.ts).
//   POST {action:'collect'}  read the report; per provider inbox / spam / tabs / missing into
//                            public.deliverability_test_provider, the filter scores and rules into
//                            public.deliverability_test; when GlockApps says finished (or 48 h pass), decide and file
//                            the verdict through fn_deliverability_test_file.
//   POST {action:'report'}   the summary: Outlook / Microsoft inbox % against the 80% bar, and pass / fail.
//
// The it_engineer duty it_engineer.deliverability_test (fn_deliverability_test_tick, every 15 minutes) calls this
// with cred_fn_deliverability_test. Without the edge secret GLOCKAPPS_API_KEY every action answers
// {ok:false, status:'key_missing'} and changes nothing. Routes, header and schema: glockapps.ts.
// The SQL side: scripts/sql/the_it_engineer_runs_the_glockapps_test_and_files_its_verdict_without_the_founder.sql.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { FN, handle, REQUEST_KEY, type Db, type TestRow } from './handler.ts';
import type { ProviderRow } from './glockapps.ts';

const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(Deno.env.get('SUPABASE_URL')!, SERVICE_KEY, { auth: { persistSession: false } });
const COLS = 'test_id,project_id,created_at,reason,marker,from_address,seeds,status,verdict,polls,reported_at,summary,outlook,outlook_inbox_pct';
const must = <T>(r: { data: T; error: { message: string } | null }): T => { if (r.error) throw new Error(r.error.message); return r.data; };

const db: Db = {
  async secret(key) {
    const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle();
    return String(data?.value ?? '');
  },
  // the ONE app_secrets write in this function: the one-shot request flag it has just served
  async clearRequest() { must(await admin.from('app_secrets').delete().eq('key', REQUEST_KEY)); },
  async openTest() {
    return must(await admin.from('deliverability_test').select(COLS).in('status', ['seeds_queued', 'collecting'])
      .order('created_at', { ascending: true }).limit(1).maybeSingle()) as TestRow | null;
  },
  async getTest(testId) { return must(await admin.from('deliverability_test').select(COLS).eq('test_id', testId).maybeSingle()) as TestRow | null; },
  async latestTest() {
    return must(await admin.from('deliverability_test').select(COLS).order('created_at', { ascending: false }).limit(1).maybeSingle()) as TestRow | null;
  },
  async insertTest(row) { must(await admin.from('deliverability_test').insert(row)); },
  async updateTest(testId, patch) { must(await admin.from('deliverability_test').update(patch).eq('test_id', testId)); },
  async knownParties(emails) {
    const out = new Set<string>();
    for (let i = 0; i < emails.length; i += 100) {
      const chunk = emails.slice(i, i + 100);
      const { data } = await admin.rpc('fn_deliverability_known_parties', { p_emails: chunk });
      for (const e of (data as string[] | null) ?? []) out.add(String(e).toLowerCase());
    }
    return out;
  },
  async queueSeeds(rows) {
    // plain insert: notifications_dedupe_key_uidx is a PARTIAL unique index, which ON CONFLICT (dedupe_key) cannot name;
    // the key is per test and address, so a second insert of the same seed is refused rather than sent twice
    const data = must(await admin.from('notifications').insert(rows).select('id'));
    return ((data as { id: number }[] | null) ?? []).map((r) => Number(r.id));
  },
  async upsertProviders(testId, rows: ProviderRow[]) {
    if (!rows.length) return;
    must(await admin.from('deliverability_test_provider').upsert(rows.map((r) => ({ test_id: testId, ...r, updated_at: new Date().toISOString() })), { onConflict: 'test_id,provider' }));
  },
  async fileVerdict(testId) { return must(await admin.rpc('fn_deliverability_test_file', { p_test_id: testId })); },
  async finding(args) { must(await admin.rpc('fn_it_engineer_finding_upsert', args)); },
  async closeFinding(issueKey, note) { must(await admin.rpc('fn_it_engineer_finding_close', { p_issue_key: issueKey, p_note: note })); },
};

Deno.serve(async (req) => {
  const out = await handle(req, {
    db, fetch: (u, i) => timedFetch(u, i || {}, 20_000), env: (k) => Deno.env.get(k), now: () => new Date(),
    serviceKey: SERVICE_KEY,
    internalAuth: async (secret) => (await requireInternal(admin, secret, FN)).ok,
  });
  return new Response(JSON.stringify(out.body), { status: out.http, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
});
