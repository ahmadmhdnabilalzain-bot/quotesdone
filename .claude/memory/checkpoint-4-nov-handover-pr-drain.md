---
name: checkpoint-4-nov-handover-pr-drain
description: "CHECKPOINT 4 Nov — weekly limit hit mid PR drain. 1392 proved with real AI and ready; older PRs in two background merge passes; Windows sign-in token fix not yet a PR; next steps."
metadata:
  type: project
---

Written 4 Nov 2026, when the founder stopped the session at 99% of the weekly usage: "we continue next week". Re-measure every line below against GitHub and production before acting on it.

**Merged on 4 Nov:** 1833 (a supplier profile is read to its last page) and 1718 (the reply probe cleans its own judgements). Before that, the same day: 1837, 1838, 1844, 1846, 1848, 1849, 1852, 1855, 1856, 1863, 1830, 1724, 1802, 1840, 1842, 1841, 1832, 1824, plus mirror PRs.

**Ready, not yet merged:**
- **1392** (customer_support, widget person check). Head fed2a523, which merges main. The real-model run on 4 Nov exited 0 with fails []: 6 calls on openai/gpt-6-luna-pro, AED 0.0186; ar_person true, en_plain false; replay_ceo_reports filed only held 901 and 902. All three review asks were already on the branch. It still needs its CI green and a release-operator merge.
- **1795, 1792, 1845** were fixed on 4 Nov (1795 restores DEMO_TX and drops the whole e2e-out upload; 1792 hand-resolves resend_inbound; 1845 regenerates the brief, 39,864/40,000 tokens). An independent review found all three MERGE-SAFE.
- The older PRs **1710, 1720, 1778, 1780, 1784, 1636, 1643, 1703, 1803, 1804, 1805** were reviewed MERGE-SAFE. Two laptop merge passes were working through them when the session stopped. GitHub returned 5xx on pushes and merges all day, so some may still be open: read their state, do not assume.

**Open problems:**
- **1720** fails "the database is running what this repository says" while the schema mirror reads "already current". The cause is not read yet; look at the check log before refreshing anything.
- **After 1703 merges**, run `node scripts/kb/load_knowledge_eval_questions.mjs`. It writes `expected_any`, and apply-on-merge must have applied the 1703 SQL first.
- **1482** (CSP nonce) needs a founder decision: per-request nonces make every page dynamic, so the static prerendering is lost. It also needs a browser proof of no CSP violations on a Vercel preview. It is labelled hold.
- **1649** is superseded: main owns deliverability_test, and the PR would email a stale 0% Outlook verdict. Founder said "dont close randomly"; report it, do not close it on our own.
- **1864** is an old mirror PR (after-1837-column) superseded by later mirror PRs. Never merge it, because it would write an older export.

**The laptop sign-in (not yet a PR):**
- On Windows, Supabase CLI v2 `supabase login` stores the token in the Credential Manager ("Supabase CLI:supabase") and writes no `~/.supabase/access-token`. So every script said "SUPABASE_ACCESS_TOKEN is not set" even though the founder was logged in.
- The fix was written and proven (it found a 44-character sbp_ token) only in the 1392 agent worktree, `.claude/worktrees/agent-ae39c2eed45d0bc91/scripts/lib/supabase_token.mjs`, uncommitted. It adds a win32 fallback that reads that credential through CredRead, plus go-keyring base64/hex decoding.
- Land it as its own it_engineer PR with a small test of `decodeKeyring`.
- The founder also generated a manual token that is visible in his terminal history; he was asked to revoke it.

**Still owed to the founder:**
- the demo-data purge plus his own two accounts, on his "3%" go (ruling 1539);
- the info@ inbound reply proof and the unlisted-sender reply proof (ruling 1543);
- the 11 held expense items await his decision.

**Merge mechanics that worked:**
- Merge one PR at a time and only when every check passes, the state is CLEAN and the head is unchanged, using `--match-head-commit`.
- Retry merges and pushes on GitHub 5xx.
- After an apply, a stale mirror is refreshed through regen-schema-mirror.yml on a branch made from origin/main, plus an empty commit, a PR and a merge.
- MANIFEST conflicts keep main's lines first. The Arabic register is merged as a union.

Related: [[checkpoint-3-nov-handover-week-of-4-nov]], [[never-merge-on-a-red-check]], [[apply-at-merge-never-before]].
