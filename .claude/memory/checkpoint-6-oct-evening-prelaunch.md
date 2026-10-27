---
name: checkpoint-6-oct-evening-prelaunch
description: "READ FIRST on resume after the laptop restart, 6 Oct 2026 ~19:30 UTC: pre-launch state, open PRs, what runs tonight, the launch checklist, the founder's end-list"
metadata:
  node_type: memory
  type: project
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-06T19:27:24.033Z
---

**Resume point, 6 Oct 2026 ~19:30 UTC.** The founder restarted his laptop, which stopped all background agents. Start a fresh RELEASE OPERATOR immediately, with the same rules: independent reviewer agents, only the operator labels, green-only merges, SQL via the release train one at a time, never push to a labelled PR, never the founder's identity, CI on Ubicloud. Ledger 1159 froze scope to launch-critical items; replace any operator that sits idle for more than 30 minutes.

**Merged 5–6 Oct (main, drift 0):**
- Infrastructure and CI: #1233 Ubicloud CI, #1257 / #1263 audit fixes, #1261 / #1262 main fixes, #1265 backup_prune_mode registered.
- Mail and messaging: #1226 Serper / DuckDuckGo removed, #1229 M365 seed id, #1236 WhatsApp fallback, #1256 WhatsApp template missing-not-404, #1252 archiver / seal bucket / registry, #1264 M365 lane Reply-To = supplier@ plus Graph inbox reader.
- Testing and checks: #1230 stage-2 sandbox E2E (tagged window, $4 cap), #1241, #1242, #1243, #1244, #1248, #1249, #1251, #1253, #1258 CEO decision loop closes at originator.
- Data and retention: #1231 backup rotation (backup_prune_mode='delete', first real prune 7 Oct), #1232 5-year retention (NOT armed yet), #1235 held questions, #1237 PDPL export / erase, #1238 summaries.
- Legal and terms: #1239 supplier notices cite clause 33, #1240 customer re-accept, #1250 liability terms (Customer Terms v10 + Supplier Agreement v15, intermediary / not liable, verified UAE articles; CTL 50/2022 Art. 265; new Civil Code FDL 25/2025).
- Security: #1245 OTP atomic verify / issue, #1247 HSTS.
- Knowledge: #1220 kb_chunks copy-swap MERGED 19:10 (the swap runs only 02:00–05:00 Dubai, avoiding 02:50–03:10).

**Open:**
- #1228: CEO pricing class; 20-request probe; green, needs review.
- #1254: a check uses a ZZ DEMO QA identity, never the founder; green, needs review.
- #1255: knowledge eval redo; real buyer questions; low word overlap. With its author.
- #1259: Arabic retrieval (AR 0.997); merges after #1255. Post-merge: deploy embed_ml + think.ts functions FIRST, then SQL, load_verified_packs, ml backfill, eval --ml.
- #1246: resilience_ping auth plus the cron route fails closed. GATED on the founder setting CRON_SECRET in Vercel production.
- #1234: privacy 1.6. Release after #1232's retention is armed, following an inspected dry run (conversation_retention_daily 23:20 UTC).
- Dependabot #1222–#1224: after launch.

**Launch checklist** (ledger 1141: "ready" only with every gate measured the same day):
1. Confirm the M365 inbox reader logs success, plus a test reply from a QA mailbox. Then GlockApps: 3 paid credits unused, M365 cap 150/day, seeds via kind invite_m365_seed. The 6 Oct test to the founder's Dorata mailbox landed in Junk; mail-tester 10/10, SPF/DKIM/DMARC pass, outbound SCL 1, so the Reply-To mismatch was the suspect, now fixed by #1264.
2. Stage-2 sandbox: `node scripts/e2e/stage2.mjs --run`, after a dry run. 10 suppliers / 10 customers ZZ DEMO, artifacts in Desktop\QuotesDone Sandbox Test 2026-10, full cleanup verified at 0.
3. Production check suite fully green.
4. Staged campaign: 10, then 20 per day, the first batch previewed to the founder, a tested kill switch.

**Founder's end-list** (ledger 1146):
- 2FA on Supabase, GitHub, Vercel, Stripe, Microsoft, GoDaddy, Resend, Twilio, Meta.
- Supabase password sign-in off; session time limits; Twilio Verify voice channel on.
- CRON_SECRET in Vercel.
- Remove the extra Mail.Read, Mail.ReadBasic and Mail.ReadBasic.All grants on the QuotesDone mailer app.

**Rulings this session:** see [[ready-means-every-gate-measured]] and [[ci-runs-on-ubicloud]]. Retention is active plus 5 years (1126). The 3 extra seeded founder sessions are cleared (1158). Nothing is routed to the founder (all approvals go to the CEO).
