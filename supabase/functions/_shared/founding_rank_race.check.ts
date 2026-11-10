// AN APPROVAL NEVER WAITS ON ANOTHER TRANSACTION'S RANK LOCK (10 Nov 2026, seat: sales_engineer).
//
// Runs the committed bodies of public.fn_assign_founding_rank and public.fn_sales_engineer_reruns_held_verifications
// against a throwaway Postgres (the local gate's otp-race step starts one; locally:
// QD_OTP_RACE_PG=postgres://... deno test --no-lock --allow-read --allow-env --allow-net <this file>). Never production.
//
// What it replays: on 10 Nov 2026 a supplier's services confirm timed out twice (8 s each) and once took 40.4 s,
// because fn_assign_founding_rank took pg_advisory_xact_lock('qd_founding_rank') and WAITED while another open
// transaction (a probe approving a ZZ DEMO supplier) held it. The check holds that lock open in transaction A and
// approves a second supplier in B under a 2 s statement_timeout:
//   * B must finish (old body: canceling statement due to statement timeout), unranked;
//   * once A ends, the minute tick ranks B, with the next number;
//   * twelve approvals at once, then the tick: every supplier ranked, numbers 1..N with no gap and no repeat.
// QD_RANK_RACE_SQL=<file> runs the same assertions against another body (the before-proof).
import postgres from 'npm:postgres@3.4.5';

const PG_URL = Deno.env.get('QD_OTP_RACE_PG');
const FILE = Deno.env.get('QD_RANK_RACE_SQL')
  ? new URL('file://' + Deno.env.get('QD_RANK_RACE_SQL'))
  : new URL('../../../scripts/sql/a_supplier_who_confirms_his_services_is_answered_in_seconds.sql', import.meta.url);

/** One `create or replace function public.<name>(...) ... $fn$;` statement out of the committed file. */
function definition(text: string, name: string): string {
  const m = new RegExp(`create or replace function public\\.${name}\\([\\s\\S]*?\\$fn\\$;`).exec(text);
  if (!m) throw new Error(`${name} is not defined in ${FILE.pathname}`);
  return m[0];
}

Deno.test({ name: 'an approval is never held behind another transaction\'s founding-rank lock, and the tick ranks it', ignore: !PG_URL, fn: async () => {
  const sql = postgres(PG_URL!, { max: 20, onnotice: () => {} });
  try {
    await sql.unsafe(`
      drop table if exists public.leads, public.app_secrets, public.supplier_capabilities, public.supplier_capability_confirmation cascade;
      create table public.leads (id bigserial primary key, verified boolean default false, banned boolean default false,
        approval_status text, licence_gate_reason text, approved_at timestamptz, founding_rank int, subscription_exempt boolean);
      create unique index leads_founding_rank_uidx on public.leads (founding_rank) where founding_rank is not null;
      create table public.app_secrets (key text primary key, value text);
      create table public.supplier_capabilities (supplier_id bigint, confirmed_at timestamptz, confirmed_version int);
      create table public.supplier_capability_confirmation (supplier_id bigint, version int);`);
    const text = await Deno.readTextFile(FILE);
    await sql.unsafe(definition(text, 'fn_assign_founding_rank'));
    // The tick exists only in the new file; the old body is judged on the lock alone.
    const tick = /fn_sales_engineer_reruns_held_verifications\(\)/.test(text);
    if (tick) await sql.unsafe(definition(text, 'fn_sales_engineer_reruns_held_verifications'));
    await sql.unsafe(`create trigger trg_assign_founding_rank before insert or update on public.leads
                      for each row execute function public.fn_assign_founding_rank();`);
    const approve = (q: postgres.Sql | postgres.ReservedSql) =>
      q`insert into public.leads (verified, approval_status, approved_at) values (true, 'approved', now()) returning id, founding_rank`;

    // 1. A holds the rank lock in an open transaction (rank 1).
    const a = await sql.reserve();
    await a`begin`;
    const [ra] = await approve(a);
    if (ra.founding_rank !== 1) throw new Error(`the first approval must be rank 1, got ${ra.founding_rank}`);

    // 2. B approves under a 2 s statement timeout while A is still open.
    const b = await sql.reserve();
    const t0 = Date.now();
    let rb: { id: number; founding_rank: number | null } | null = null; let err = '';
    try {
      await b`set statement_timeout = '2s'`;
      [rb] = await approve(b) as unknown as Array<{ id: number; founding_rank: number | null }>;
    } catch (e) { err = String((e as Error).message); }
    const ms = Date.now() - t0;
    b.release();
    await a`commit`; a.release();
    if (err) throw new Error(`an approval waited on another transaction's rank lock and failed after ${ms} ms: ${err}`);
    if (ms > 1500) throw new Error(`an approval took ${ms} ms while another transaction held the rank lock`);
    if (rb!.founding_rank !== null) throw new Error(`B could not have taken a rank while A held the lock, got ${rb!.founding_rank}`);

    // 3. The tick ranks B now that A is done.
    if (!tick) throw new Error('no fn_sales_engineer_reruns_held_verifications: nothing ranks a supplier the trigger skipped');
    const [t] = await sql`select public.fn_sales_engineer_reruns_held_verifications() as r`;
    const [b2] = await sql`select founding_rank, subscription_exempt from public.leads where id = ${rb!.id}`;
    if (b2.founding_rank !== 2 || b2.subscription_exempt !== true) throw new Error(`the tick must rank B 2 and exempt, got ${JSON.stringify(b2)} (tick ${JSON.stringify(t.r)})`);

    // 4. Twelve approvals at once, then the tick: 1..14, no gap, no repeat.
    await Promise.all(Array.from({ length: 12 }, () => approve(sql)));
    await sql`select public.fn_sales_engineer_reruns_held_verifications()`;
    const ranks = (await sql`select founding_rank from public.leads order by founding_rank`).map((r) => r.founding_rank);
    const want = Array.from({ length: 14 }, (_, i) => i + 1);
    if (JSON.stringify(ranks) !== JSON.stringify(want)) throw new Error(`ranks must be 1..14 exactly, got ${ranks.join(',')}`);
  } finally {
    await sql.unsafe('drop table if exists public.leads, public.app_secrets, public.supplier_capabilities, public.supplier_capability_confirmation cascade').catch(() => {});
    await sql.end();
  }
} });
