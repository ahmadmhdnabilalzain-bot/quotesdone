---
name: github-is-the-single-source-of-truth
description: "Founder 26 Oct 2026 (ledger 1278, 1281): GitHub is always the single source of truth; nothing lives only on the laptop; the laptop is cleared. Memory lives in .claude/memory/, reports in docs/reports/."
metadata:
  type: feedback
  modified: 2026-10-26
---

**The ruling, 26 Oct 2026 (ledger 1278):** *"GitHub is always the single source of truth; nothing
lives only on the laptop; the laptop is cleared."* The order that came with it (ledger 1281): a cloud
session started from his phone must know everything a laptop session knows.

**Why:** until 26 Oct the operating memory lived only in
`~/.claude/projects/C--Users-Opera-quotesdone/memory/` and the campaign and sandbox evidence lived
only in `Desktop/QuotesDone*` folders. A phone session, a fresh machine or an external auditor saw
none of it, and the laptop is being cleared.

**Where things live now:**
- **This memory**: `.claude/memory/` in the repository. `MEMORY.md` is the index. Every session reads
  it first (the rule is in `.claude/CLAUDE.md`).
- **Reports**: the text reports and markdown go in `docs/reports/<original folder name>/`.
- **Evidence binaries and third-party files**: never in git (coordinator's decision on PR #1598,
  26 Oct 2026). They go in the private Supabase storage bucket **`evidence`** on `htdblwldjkcgjvmqkbeh`.
  - What belongs there: screenshots, recordings, PDFs and office files, anything over 5 MB, and real
    third parties' documents (real supplier profiles, lead or customer lists, anything carrying a real
    person's email or phone).
  - Access: no storage.objects policy, so only the service role can read it.
  - Index: every object is listed with its size and sha256 in `docs/reports/EVIDENCE_INDEX.md`.
  - Backup: the bucket is registered for the Dropbox STORAGE SWEEP.
- **Secrets**: never in git. They live as edge-function secrets and Vercel env vars, and in his
  password manager.
- **The trade licence PDF**: stays in his Dropbox, which is cloud storage already, at
  `Dropbox/QuotesDone Backup/Assets/639183403868888392.pdf` (192,892 bytes). It is not copied into the
  repository. The facts on it are in [[trade-licence-and-vat-status-are-closed]] and
  [[the-meta-business-portfolio-and-the-licence-facts]].

**How to apply:**
- When you learn something a future session needs, edit or add a file here and land it **by PR**,
  the same as code. A note that exists only in a local `~/.claude` folder does not exist.
- Never write a report or evidence folder to the Desktop or any other laptop-only path.
  - Text: under `docs/reports/`, after the secrets and personal-data scan.
  - Binaries and third-party files: in the `evidence` bucket, with a line in `EVIDENCE_INDEX.md`.
- Before committing anything copied from outside the repository, scan it for keys, tokens and real
  third parties' emails and phone numbers.

Related: [[ci-runs-locally-ubicloud-stopped]], [[company-knowledge-stays-in-sync-everywhere]].
