# docs/reports: reports that used to live only on the laptop

These folders were moved off `C:\Users\Opera\Desktop\` on 26 Oct 2026 by the ceo seat. The founder's
ruling is that GitHub is the single source of truth and nothing lives only on the laptop
(`public.founder_instruction` 1278 and 1281; memory: `.claude/memory/github-is-the-single-source-of-truth.md`).

## Where the files went

**Text reports and markdown are in git, here.** That covers `.md`, `.json`, `.txt`, `.log`, `.csv`,
`.html`, `.sql` and `.cjs` files. Each folder keeps its original Desktop name. File contents are
unchanged, apart from one redaction (see below).

**Everything else is in the private Supabase storage bucket `evidence`** on `htdblwldjkcgjvmqkbeh`.
This follows the coordinator's decision on PR #1598, which ruled out about 700 MB of screenshots in
git. The bucket holds:

- screenshots, screen recordings, PDFs and office files
- every file over 5 MB
- real third parties' documents

`EVIDENCE_INDEX.md` lists every object: its original Desktop path, its object key, size, sha256 and
why it is not in git. Object keys are the original path with every character outside `A–Z a–z 0–9 . _ / -`
replaced by `_`.

| folder | text files in git | objects in `evidence` |
|---|---:|---:|
| `QuotesDone Campaign/` | 4 | 0 |
| `QuotesDone Sandbox Test 2026-10/` | 937 | 2,498 |

No other `Desktop\QuotesDone*` folder existed on 26 Oct 2026.

## Who can read the bucket

The bucket is private: it is not public, and no URL works without a key. Row level security is on for
`storage.objects`, and on 26 Oct 2026 the table had no policy at all. So the anon and authenticated
roles cannot read any private bucket, and only the service role can.

Verified on 26 Oct 2026 by requesting an object three ways:

- with the anon key
- with no key
- through the public URL

All three were refused. `EVIDENCE_INDEX.md` records the responses.

The bucket is registered for the Dropbox storage sweep in
`scripts/sql/the_laptops_evidence_lives_in_a_private_bucket_not_in_git.sql`, so it is not the only copy.

To read an object as the service role:
`GET https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/authenticated/evidence/<key>`.

## How the text in git was checked

Every added file was measured on 26 Oct 2026.

**Keys and tokens.** A regex sweep looked for:

- Supabase PATs, Stripe live and test keys, webhook secrets, Resend keys and JWTs
- GitHub, Slack, AWS, Google, OpenRouter and Anthropic keys
- private-key blocks, Dropbox tokens, and Postgres URLs with a password

There were two hits, and neither is a key:

- the string `re_services_cleaning`, which is a page slug
- a Stripe test-mode checkout session id (`cs_test_…`), which is an identifier

**Emails and phones.** Every email address is `@example.invalid`, `@quotesdone.com`, or one of the
founder's own mailboxes. Every UAE number is either a `+9715000000NN` fixture or the company's own
number. The same check ran over the binaries now in the bucket:

- PDFs, read with `pdftotext`
- office files, unzipped and read

That is how the customers register was caught; it is in the third-party set below. No OCR was run
over the screenshots.

## The one redaction

`QuotesDone Sandbox Test 2026-10/stage2_0a717394.log`, line 5, printed two key prefixes:

- the first eight characters of the unsubscribe signing key
- the first two characters of the Stripe test webhook secret

Both are replaced with `[redacted]` in the copy in git. No full key was in the file.

## The third-party set (322 objects, `why = third-party`)

These files hold real companies' brochures, or real people's names, emails or phone numbers. They are
in the bucket and must never come into git:

- `real_profiles*/`: real contractors' profile PDFs, plus the OCR text and model output taken from them
- the Dropbox repair plans of 7 and 12 Oct, and `repair_dry_run_moves.json`: real customers' names in Dropbox paths
- `demo_inventory_2026-10-12.md`: lists real customers' Dropbox folders by name
- `customers/customers-register.xlsx`: a real customer's name, email and mobile

## Not copied, recorded instead

The trade licence PDF stays in the founder's Dropbox, at
`Dropbox/QuotesDone Backup/Assets/639183403868888392.pdf` (192,892 bytes).

## Session reports written here directly

| folder | what it proves |
|---|---|
| `chat-turn-latency-2026-10-27/` | portal assistant turns before and after the one-call, 70 s clock fix: p95 150.3 s with two 504s, then 13.0 s with none (12 EN + 12 AR ZZ DEMO turns each) |
| `adaptive-conversations-2026-10-27/` | the adaptive conversation bank on the portal chat (#1635 with #1640 merged). Latest (the plan per trade, 6cf746dea): whole bank 43 scenarios, 0/43 at >= 95 %, mean 76.5 %, 0/22 stalls, per-turn p50 10.1 s / p95 17.7 s on the 22. Earlier (c639f66ac): 22/22 code gates, mean 83 %. Production before: 0 %, 9 of 10 conversations lost a turn |
| `intake-turn-latency-2026-10-27/` | customer intake interview turns before and after the one-clock fix: p95 113.5 s (3 of 15 turns over 30 s), then 20.1 s over 54 turns with none over 25 s (ZZ DEMO, EN + AR) |
