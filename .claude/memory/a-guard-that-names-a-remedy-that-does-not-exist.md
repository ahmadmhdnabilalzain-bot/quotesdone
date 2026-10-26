---
name: a-guard-that-names-a-remedy-that-does-not-exist
description: "An immutability guard told callers to \"reverse it instead\" and pointed at a routine nobody had built"
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T05:52:01.257Z
---

9 Sep 2026. The founder ruled a vendor out of scope after a sweep had already booked and POSTED it.
`trg_gl_journal_immutable` refuses to delete a posted journal:

```
raise exception 'Posted journal % is immutable (reverse it instead)', old.id;
```

and carves out exactly one exemption, commented *"allow only the controlled void marking done by
fn_gl_reverse"*. Measured: **`fn_gl_reverse` did not exist.** Nothing in `pg_proc` matched, nothing
in the repo defined it. So the ledger had NO way to correct a mis-booking — the one operation a set
of books must always support — and the guard read as correct while being a dead end.

**The lens:** a guard that names its remedy is making a promise. Whenever one says *"do X instead"*,
**check that X exists**. The guard itself will never fail a test — it refuses exactly as designed —
so the gap only surfaces the first time somebody genuinely needs the remedy, which is the worst
moment to discover it. Same family as [[finished-capability-with-no-entry-point]], inverted: here
the entry point was advertised and the capability was missing.

**Built it** (`scripts/sql/a_posted_entry_is_reversed_never_erased.sql`): the reversal writes a new
journal carrying the opposite of every line, marks the original `void` pointing at it, **requires a
reason** (undoing a posted entry is a decision and the ledger must carry why), refuses a journal
that is not posted or already reversed, and refuses to stand if the pair does not net to zero.

**Reverse, do not delete.** The entry really was posted; erasing it loses the fact that the company
once believed the cost was its own, which is exactly what an audit needs to see. The `expense_entries`
row IS deleted, though, because the founder's figures are computed from that table — the ledger keeps
the history, the book keeps the truth, and the register records why the vendor is excluded.

Related: [[a-mention-is-not-a-reference]], [[guarded-by-a-condition-that-cannot-occur]].
