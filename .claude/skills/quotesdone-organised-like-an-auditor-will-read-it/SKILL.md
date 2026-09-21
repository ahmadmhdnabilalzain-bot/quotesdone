---
name: quotesdone-organised-like-an-auditor-will-read-it
description: "ALWAYS APPLY on the QuotesDone repository. The founder's ruling of 10 Sep 2026: the code must be organised as though a real software engineer built it, because one day he will hand it to an external auditor and 'I can't understand shit, it's all mixed everywhere' is not an acceptable outcome. He tied this directly to a repeated failure — decisions we finalise get forgotten and he has to re-state them — because a decision with no obvious home is a decision that will be lost. Load this before creating any file, routine, table or check, and before closing any session."
---

# QuotesDone — organised the way an auditor will read it

The founder, 10 September 2026:

> *"I hope you're actually organized in terms of how the code is built so that it matches as if a
> real software engineer is building it. I don't want it to be extremely messy so that, let's say,
> one day I give it to someone to audit it, like a real auditor, he will tell me, oh, I can't
> understand shit. It's all mixed everywhere… Keep that as a skill whenever you build so that
> everything is structured properly."*

And immediately after, the reason it matters to him:

> *"I've noticed many things we discuss and we finalized. You forget later on. And then when I
> correct you, you say you are right. Clearly, this is a matter of how organized the code is."*

**He is right, and the diagnosis is the important half.** This is not a tidiness preference. A
decision with no obvious home is a decision that will be forgotten, and he pays for it by having to
say the same thing twice. Every rule below exists to give a decision a home.

---

## 1. A decision the founder makes is written down BEFORE the work starts

`public.founder_instruction` holds his words verbatim, the subject, a status, and evidence. A
trigger refuses `status='done'` with empty evidence.

**The moment he says something, it goes in the ledger — not at the end of the session.** A session
that ends unexpectedly must not take his instructions with it. This is the single highest-value
rule here, because it is the one that addresses what he actually complained about.

```
node <scratchpad>/ledger.mjs <scratchpad>/instructions.json   # long text, no shell mangling
select * from public.fn_founder_open_instructions();          # what is still owed
```

- Record his words **verbatim**, not a paraphrase. The paraphrase is what drifts.
- `note` carries the reading — what it means for the build — so the next session does not re-derive it.
- Close it with `evidence` naming what was built and how it was proved. Never with "done".

**Never write long text through a shell command line.** Quotes and non-ASCII get mangled — Arabic
came through as 50 ASCII question marks once and three "failures" were the harness, not the code.
Write a file, pass the path.

## 2. One subject, one file, and the filename is the sentence

`scripts/sql/` holds one file per change, named as a lowercase sentence saying what it does —
`the_customer_asks_and_the_chain_actually_starts.sql`. This is a real strength of the repo and it is
why an auditor can navigate 995 files at all. Keep it.

- **A file states its subject in the first 40 lines**: what was measured, what was wrong, what this
  changes, and what it deliberately does not change.
- **Do not create a second file for a subject that already has one.** Edit the owning file and
  re-apply; `create or replace` is idempotent. A second file for the same routine means the MANIFEST
  decides which one is real, and the loser is a lie sitting in the tree.
- **Say what you did NOT fix.** `one_customers_drawing_is_not_everyone_elses_knowledge.sql` says in
  its header that it does not fix the writer. That sentence is what let the writer get fixed an hour
  later instead of never.

## 3. The index must not point at nothing — and measure it correctly

`scripts/sql/MANIFEST.txt` is the apply order and it decides which file is canonical for a routine.

**Measured 10 Sep 2026, and the first measurement was wrong in a way worth keeping here.** A quick
loop reported "1,343 entries, 348 naming files that do not exist" — a quarter of the index dead. It
was not. The file is 1,345 lines: **995 entries, 348 comment lines** documenting why the file
exists, and 2 blank. The loop had treated every comment line as a filename and every one of them
failed the file test. The true state is clean: **995 entries, 995 files, 0 missing, 0 duplicates,
0 files unlisted.**

Two lessons, and the second is the one that generalises:

- **A count is not a finding until you know what you counted.** `grep -c .` counts comments.
  This is the same error as reporting a per-key spending cap as an account balance, and the same
  correction applies: check what the number MEANS before reporting it.
- **Filter comments and blanks explicitly**, or the check indicts its own documentation:

```
# entries naming a file that does not exist -- must be 0
grep '\.sql$' scripts/sql/MANIFEST.txt | while read -r f; do [ -f "$f" ] || echo "$f"; done | wc -l
# files not named in the index -- must be 0
for f in scripts/sql/*.sql; do grep -qxF "$f" scripts/sql/MANIFEST.txt || echo "$f"; done | wc -l
# entries vs distinct entries -- must be equal
grep -c '\.sql$' scripts/sql/MANIFEST.txt; grep '\.sql$' scripts/sql/MANIFEST.txt | sort -u | wc -l
```

Run all three before a session ends. When you delete or rename a file, remove its line in the same
commit — with the Edit tool, never a shell redirect (a hook rewrites redirect targets and has
corrupted MANIFEST before).

## 4. Where things live, so an auditor is not guessing

| what | where | the rule |
|---|---|---|
| database change | `scripts/sql/<lowercase_sentence>.sql` + a MANIFEST line | one file per subject; MANIFEST order decides the winner, append to the END |
| runtime | `supabase/functions/<seat-or-surface>/index.ts` | one directory per surface; deploy and read back |
| gate | `scripts/checks/*.mjs` | a check retires WITH its subject — rename to `*.RETIRED.mjs`, never soften it |
| the founder's words | `public.founder_instruction` | verbatim, immediately |
| a settled policy | `public.company_policy_decision` and the guard that enforces it | the database enforces it, not a comment |
| conduct rules | `.claude/skills/*/SKILL.md`, registered in `.claude/CLAUDE.md` | if it is a rule for HOW to work, it is a skill, not a doc |
| a narrative | `docs/` | context and history; never the source of truth for behaviour |

**A rule that lives only in prose is a rule that will be broken.** Where a rule can be a CHECK
constraint, a trigger, a policy or a check script, make it one. The estate's own vocabulary has
taught this repeatedly — `amount_source`, `reason_code` and `status` all refused a wrong guess and
were right to.

## 5. Explain WHY, with the measurement, in the code

The convention this repo already uses and must keep: a comment states what was **measured**, what
was wrong, and what changed — not what the code does line by line.

> `-- "elevator installation" resolved to FLOORING. Both scored 1 ('elevator' vs 'installation' in
> item text) and flooring won the tie on row count. A trade-name match is now worth ten of an
> item-text match.`

That comment is why nobody will "simplify" the weighting back out. A comment saying
`-- score the categories` protects nothing.

- Quote the founder when his ruling is the reason. It settles the argument permanently.
- Name the date. `-- 9 SEP 2026 — PHASE MACHINERY REMOVED` tells a reader whether it still applies.
- **Never describe a forbidden pattern by spelling it**, if a check greps for that string — it will
  match your comment. Twice a correct file failed its own check that way.

## 6. Before writing anything new, look for the thing that already owns it

Measured today: `fn_price_confidence` already assembled trade price bands and already returned them
on every path — it just required an amount to get in the door. `fn_ar_norm` already normalised
Arabic. `mep_trade` already held bilingual trade labels. The lazy read of the repo is the accurate
one: **most of what you need exists, one layer over.**

```
graphify query "<question>"                                    # scoped subgraph, before grepping
select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prosrc ilike '%<table_or_concept>%';
```

A second implementation of something that exists is the definition of "all mixed everywhere".

## 7. Scratch is scratch, and it does not belong in the repository

**Measured 10 Sep 2026: 79 agent worktrees under `.claude/worktrees/` had been committed as gitlinks
with no `.gitmodules`, so every CI checkout printed `fatal: No url found for submodule path` and
every job — including the green ones — ended with `git failed with exit code 128`.** The founder saw
green runs with errors in them and asked why.

Temporary files go in the session scratchpad, never the project. Before committing, look at what is
actually modified rather than what you remember editing:

```
git status --short | grep -v '^??' | awk '{print $2}' | xargs -n1 dirname | sort -u
```

Stage explicit paths. Never `git add -A`.

## 8. Do not test against a half-built product, and never against a real person

The founder, 10 September 2026:

> *"I don't want you to do actual tests now… I care about the workflow now, and I know tests will
> fail because the customer portal is not done and the supplier portal as well… And the LLM is not
> open as well."*

A red result from an unfinished funnel is not information. Build the workflow correctly and prove it
by structure and by assertions close to the change.

**And a probe must be INCAPABLE of reaching a real person, not merely careful to clean up.** A
reveal-receipt probe picked a real supplier out of `public.leads`, and one queued message survived
its own cleanup and was sent: a real company was told a customer had paid to reveal them, with a
five-day clock and a penalty attached. No customer had. Cleanup is a promise; capability is a fact.

- Fixtures are `ZZ DEMO — …` in names and `@example.invalid` in addresses. **Assert it**, do not
  assume it.
- A probe creates its own subjects and deletes them, and asserts on **every** direction it touched —
  that probe checked the customer's address and never the supplier's, which is exactly the row that
  escaped.
- A probe in a file that also defines something must end by returning a verdict ROW (`PROBE OK` /
  `PROBE FAILED: …`), never `raise exception` and never `raise notice` (NOTICE is discarded by the
  management API and nobody reads it — PR #749)
  — the raise rolls the DDL back with it and the apply reports success over nothing.
- A `DO` block is ONE statement. Four calls to a routine that reads a 2.69-million-row table ran past
  `statement_timeout` and rolled back a completed migration. Assert once, cheaply; prefer
  primary-key lookups.

## 9. The end-of-session check that keeps the tree honest

```
node scripts/checks/canonical_routine_manifest.mjs             # 0 findings, incl. uncommitted DDL
node scripts/checks/security_advisors_match_the_baseline.mjs   # 0 NEW
node scripts/checks/run.mjs                                    # exit 0
node scripts/checks/export_from_either_source_is_identical.mjs --write   # LAST, after every apply
node scripts/verify_deploy_parity.mjs --all
git status --short | grep -v '^??' | wc -l                     # 0
select * from public.fn_founder_open_instructions();           # nothing owed that he thinks is done
```

**`uncommitted application DDL` is the one that catches the specific failure he noticed.** Applying
to production and not committing makes the repository and the database disagree, and it fails CI
with a red email to him. It read 0 locally and 14 in CI, because the local tree had the files and
`main` did not. **Apply and commit belong to the same piece of work.**
