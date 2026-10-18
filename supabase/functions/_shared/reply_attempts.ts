// reply_attempts — every model attempt behind a conversation reply, and what each rewrite corrected, is kept on the row
// the reply is logged in (assistant_logs, social_message), so sales_engineer's daily knowledge-gap check can read
// "rewrite:" as a guard_rewrite gap (customer_support, 12 Oct 2026). The column is added by
// scripts/sql/a_reply_keeps_its_attempts_for_the_knowledge_gap_check.sql, applied at merge: until it is live, the row
// is written WITHOUT it rather than lost — a log never fails a reply.
// prevented by: _shared/reply_attempts.test.ts
// deno-lint-ignore no-explicit-any
type Db = { from(t: string): any };

/** Insert the row with reply_attempts; if the column is not there yet, insert it without. Returns the inserted id or null. */
export async function logWithAttempts(db: Db, table: 'assistant_logs' | 'social_message', row: Record<string, unknown>, attempts: unknown, select?: string): Promise<{ data: unknown; error: { message: string } | null }> {
  const run = async (r: Record<string, unknown>) => {
    try {
      const q = db.from(table).insert(r);
      return select ? await q.select(select).single() : await q;
    } catch (e) { return { data: null, error: { message: String((e as Error)?.message || e) } }; }
  };
  const first = await run({ ...row, reply_attempts: attempts });
  if (first?.error && /reply_attempts/.test(String(first.error.message))) return await run(row);
  return first ?? { data: null, error: null };
}
