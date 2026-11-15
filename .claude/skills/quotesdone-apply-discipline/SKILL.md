---
name: quotesdone-apply-discipline
description: "ALWAYS APPLY on the QuotesDone repository. The mechanical checklist for changing production: every SQL apply needs its MANIFEST line, every new routine needs a revoke and a pinned search_path, every new table needs a policy, every commit needs every directory the change touched, and a probe that raises rolls the DDL back with it. Written 9 Sep 2026 after CI caught the same four omissions three times in one session. Load this before applying SQL, creating a routine or table, or committing."
---

# QuotesDone — the mechanical discipline for changing production

This is not about judgement. It is the short list of steps that get skipped when the interesting
part of the work is finished, and every one of them has already cost a red CI run on this
repository. The founder, 9 Sep 2026: *"fine so add that as a skill so you dont do the same mistake
again."*

The pattern behind all of them is the same: **the check caught it, not me.** These steps move the
catch earlier.

---

## 1. An apply is not finished until the MANIFEST line exists

**Happened four times in one session.** `node scripts/apply_sql.mjs <file> --apply --ddl` succeeds,
the routine is live, the work looks done — and `canonical_routine_manifest` fails because
`scripts/sql/MANIFEST.txt` has no line for the file. Twice it also caused a phantom *drift* finding,
because the older file defining that routine was still the canonical one.

**The rule: apply and MANIFEST are one action, in the same turn, in this order.**

```
node scripts/apply_sql.mjs scripts/sql/<file>.sql --apply --ddl   # 1. apply
# 2. IMMEDIATELY: append the filename as a new LAST line of scripts/sql/MANIFEST.txt with Edit
node scripts/checks/canonical_routine_manifest.mjs                # 3. confirm 0 findings
```

- **Use the Edit tool. NEVER a shell redirect** — a hook rewrites redirect targets and has corrupted
  MANIFEST.txt before.
- **Order in the file is what decides the winner.** A redefinition placed above the file it
  supersedes loses. Append to the END.
- If several agents are writing to the tree at once, re-read the tail before appending; the line you
  are anchoring on may have moved.
- **A file committed but not yet applied gets its own note, never a MANIFEST line:**
  `scripts/sql/pending/<same name as the .sql>.txt`, whose text is the reason and what would move it.
  When it is applied, **delete that note and append the file to the END of MANIFEST.txt** in the same
  commit. An empty note, or a note plus a MANIFEST line, is a finding. (One shared `PENDING.txt` made
  every parallel PR conflict on the same end-of-file lines; it was retired 22 Sep 2026.)

---

## 2. A new routine needs a revoke AND a pinned search_path

CI failed on **seven routines at once** with a mutable `search_path`, and separately on
`fn_price_confidence` answering unauthenticated callers.

```sql
create or replace function public.fn_x(...)
returns ... language plpgsql
security definer
set search_path to 'public', 'pg_temp'      -- REQUIRED. Not optional, not cosmetic.
as $fn$ ... $fn$;

revoke execute on function public.fn_x(<exact signature>) from public, anon, authenticated;
```

**Why search_path is not hygiene.** A SECURITY DEFINER routine without it resolves unqualified names
against the *caller's* search_path. Anyone able to create a schema earlier in that path can shadow a
table or operator and have the routine execute their object with the definer's privileges. One of
the seven was `fn_refund_execution_requires_ceo_approval` — the trigger that decides whether money
may move.

**Two traps inside the revoke:**

- **`CREATE` grants EXECUTE to PUBLIC. `CREATE OR REPLACE` preserves the existing ACL.** So a rewrite
  that DROPs and CREATEs silently opens a routine that was closed. `fn_price_confidence` came back
  anon-executable exactly this way.
- **A revoke names a SIGNATURE, not a name.** `fn_price_confidence` had two overloads; revoking
  `(text,numeric,numeric,text)` left `(text,numeric)` wide open. **Enumerate the overloads before
  writing the revoke:**

```sql
select p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'fn_x';
```

To fix search_path on an existing routine, prefer `alter function ... set search_path to ...` — it
adds the clause without retyping a body, which matters when the body decides whether money moves.

---

## 3. A new table needs a policy and a revoke

CI failed on **seven tables at once**: RLS enabled, no policy. That state denies everyone, so it is
not an open door — which is exactly why it is worth fixing. **A table with RLS on and no policy is
indistinguishable from one where somebody meant to write a policy and forgot.**

```sql
alter table public.t enable row level security;
create policy t_service_role_only on public.t
  as permissive for all to public using (false) with check (false);
revoke all on public.t from anon, authenticated;
```

`service_role` bypasses RLS, so the seats keep full access. The policy exists to say *deliberately
service-role only* in the schema rather than in someone's memory.

---

## 4. A probe that `raise exception`s rolls back the DDL in the same file

The estate's aborted-transaction probe is the right tool for testing a write without leaving one, **on the
local database** (`node scripts/db/local_pg16.mjs start`; on production only a light SELECT: a rolled-back
transaction there holds the real change's locks, 13 Nov 2026) — **and it is wrong in a file that also defines something.** `apply_sql.mjs` runs the file as one
transaction, so the raise takes the `create function` with it. This happened twice: a chain was
proved and simultaneously un-built, and the apply reported success.

- **File contains DDL → the probe must CLEAN UP AFTER ITSELF** (delete its rows, assert they are
  gone) and end by RETURNING A VERDICT ROW — `select 'PROBE OK' as verdict` or
  `select 'PROBE FAILED: <why>' as verdict`. **Never `raise notice`**: the management API discards
  NOTICE and `apply_sql.mjs` reads none, so 35 files carried a failure verdict nobody could ever read
  (measured 18 Sep 2026, PR #749). The applier now exits 3 on a `PROBE FAILED` row.
- **File is a pure probe, no DDL → `raise exception 'CHK<<…>>'` is correct.**

Either way the probe must assert it left nothing behind, and must not touch real rows — name the
real ids it must not disturb and count them before and after.

---

## 5. `git add` every directory the change touched

The widget's Arabic fix never entered the commit because the staging list was
`scripts/ supabase/ docs/` and the file lives in `src/`. It was verified working locally, so a
correct edit and a red check coexisted for an hour.

**Before committing, look at what is actually modified rather than what you remember editing:**

```
git status --short | grep -v '^??' | awk '{print $2}' | xargs -n1 dirname | sort -u
```

Stage explicit paths (never `git add -A` — the tree carries hundreds of unrelated worktree files),
then confirm the diff contains the file you think it does:

```
git diff --cached --stat | grep <the file you changed>
```

---

## 6. Run the gates BEFORE the PR, not after

The sequence that would have avoided every red run in this session:

```
node scripts/checks/canonical_routine_manifest.mjs          # 0 findings
node scripts/checks/security_advisors_match_the_baseline.mjs # 0 NEW
node scripts/checks/run.mjs                                  # exit 0
node scripts/checks/export_from_either_source_is_identical.mjs --write   # LAST, always
node scripts/verify_deploy_parity.mjs --all
```

**Regenerate the schema mirror LAST**, after every apply, or it reports uncommitted DDL.

**`verify_deploy_parity.mjs` is a sampler, not a byte check.** It compares the 25 longest string
literals per function, so a small change to a large function reports `LIVE` while undeployed. Do not
read it as proof that a specific edit shipped; verify that edit by calling the function.

---

## 7. A check that greps source will match your own comment

Twice in one session a check failed against a file that was already correct, because the comment
*explaining* the fix quoted the forbidden pattern verbatim:

- the Arabic check searched for `if (healthy) return` and found it in prose describing the bug
- the refund check searched for a direct table write and found it in a comment saying not to do that

When a check greps for a string, **describe the shape rather than spelling it** in nearby comments,
or anchor the check on something a comment cannot contain (`if (healthy) return J(`).

---

## 8. Before reporting a number, check what it MEANS

Not mechanical, but it belongs here because it cost the same kind of rework.

- **A per-key spending cap was reported as the account balance, twice.** The second check confirmed
  the *value* was accurate and never asked whether it measured what was claimed. When a source
  offers two similar figures, name both and say which binds.
- **A test signup was reported as the company's first customer** because it carried no demo marker.
  Absence of a marker is not evidence of realness. Score on evidence FOR the thing.
- **Before a detector pages the founder, check what it is counting.** A new refusal detector was one
  tick from a CRITICAL page because two guards were enforcing the founder's own rules correctly.
  Exemptions belong in a register that names the rule, never in trusting a log's word for itself.

---

## 9. A fix is not finished until something fails when its cause returns

Founder, 21 Sep 2026 (instruction 573): *"i dont want things to pop up again for the same reasons"*.
A probe runs once, at apply; a PR description is read once. Neither stops the cause coming back.
Every fix ships with ONE of these, and it must FAIL on the original input (break it once to see):

- **a unit test replaying the failing input** — `customer_api/rating_input.test.ts` sends a stars-only
  rating, the exact 17 Sep request that got HTTP 500;
- **a `scripts/checks` test over the live mirror** (`supabase/schema/full_schema/`, eleven parts read as
  one through `readSchemaMirror()` in `scripts/lib/schema_mirror.mjs` since #1123, kept equal to
  production on every PR) — `no_routine_names_a_table_alias_after_its_own_record.test.mjs` found
  `fn_it_backup_recheck` raising 42702 on every call, hours after its own probe printed PROBE OK
  (the probe read the source text; it never ran the routine — **a probe runs the routine**);
- **a verdict-row probe** only for what cannot be read offline, and **a nightly journey step** for
  what only a browser shows (layout, copy, timing).

The PR and the report name it: **"prevented by: <file>"**. No such line = not done.
Retries are not guards: retry a blip (`scripts/lib/retry.mjs`), never a real failure, and never
retry a non-idempotent write on a 5xx — a 524 can commit behind the error (21 Sep, mid-run: the
purge census held 1,178,961 non-standard rows for 589,199 live; it now refuses to plan unless it
sums to the table). Index of 21 Sep: `docs/it/RECURRENCE_GUARDS_21_SEP_2026.md`.
