// resilience_ping ticks owned by the it_engineer seat: the "itlater" chain of duties 19-24 and the steps that ride on it. Moved out of ticks/it_engineer.ts unchanged (9 Nov 2026);
// the order the steps run in is still set in resilience_ping/index.ts (STEP_RUN).
import { failureOf, type StepClock, stepClock } from '../../steps.ts';
import { takeProviderReadings } from '../../../_shared/it_provider_readings.ts';
import { runPostmasterStep, takePostmasterReading } from '../../../_shared/it_postmaster_readings.ts';
import { takeOpenPullRequests, takeUsageReadings, verifyRevisions } from '../../../_shared/it_duty_readings.ts';
import { runRestoreTable } from '../../../_shared/it_restore_drill.ts';
import { rotateAndSettle } from '../../../_shared/it_rotate_by_api.ts';
import { PAUSED, pausedDuties } from '../../../_shared/duty_pause.ts';
import { timedFetch } from '../../../_shared/timed_fetch.ts';
import { advanceOpenDeliberations } from '../../../_shared/seat_deliberation.ts';
import { liveDeliveryIO, sendHeldNotices } from '../../../_shared/reasoned_delivery.ts';
import { customerReplyGate } from '../../../_shared/ai_reply.ts';
import { FN, GATEWAY, SERVICE_KEY, admin, kickDetached, sec } from '../../shared.ts';

// THE IT ENGINEER'S DUTIES 19-24 (founder, 14 Sep 2026: "add all for accountant and IT"). Each step is its
// own try, so one failing duty is reported and never stops the others or the watchdog. Only booleans and
// counts come back, because this endpoint is public. The routines each own a file in scripts/sql/.
//   renewal        fn_it_renewal_watch   licences, domains, tokens: 60 and 30 days to the accountant (20)
//   changes        GitHub's verdict on every revision a signed apply named, then fn_it_change_watch (24)
//   open_prs       daily: one finding per open pull request (not dependabot's) idle for over 48 hours (25)
//   usage          when it_duty_schedule says so: provider usage against the caps in it_threshold (22)
//   restore_table  monthly: one table page from the newest finished export restored into scratch (19)
// Duty 19's file half is duty 9's sample (itScheduledTick); 21 is duty 10's sender check; 23's patch PR
// runs in .github/workflows/it-weekly-readings.yml. Runs before the alert tick, so anything raised here
// goes round the IT loop on this same pass.
export async function itLaterDutiesTick(clock: StepClock = stepClock()): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  const rpc = async (fn: string, args?: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(fn, args);
    if (error) throw new Error(fn + ': ' + error.message);
    return data;
  };
  const pause = await pausedDuties(admin);
  const step = async (name: string, run: () => Promise<unknown>) => {
    if (pause.has('resilience_ping.' + name)) { out[name] = PAUSED; return; }
    // every step is timed on the run's clock, which outlives the 120 s race (steps.ts stepClock)
    clock.begin(name);
    try { out[name] = await run(); } catch (e) { out[name] = { ok: false, error: String((e as Error)?.message || e).slice(0, 300) }; }
    clock.end(name, !failureOf(out[name]));
  };
  await step('renewal', async () => { await rpc('fn_it_renewal_watch'); return { ok: true }; });
  await step('changes', async () => {
    const revs = ((await rpc('fn_it_change_revisions_due')) ?? []) as string[];
    await rpc('fn_it_change_revisions_record', { p: await verifyRevisions(sec, revs) });
    return { asked: revs.length };
  });
  // Open pull requests left alone (it_engineer, 10 Nov 2026): 15 sessions' pull requests sat unmerged for up to three
  // weeks, some with SQL never applied. Read from GitHub with the token verifyRevisions uses; decided by
  // stale_pull_requests.ts; raised and closed by fn_it_open_pull_requests_record. Due once a day (it_duty_schedule).
  await step('open_pull_requests', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('open_pull_requests')) return { due: false };
    const r = await takeOpenPullRequests(sec);
    const out = (await rpc('fn_it_open_pull_requests_record', { p: r })) as Record<string, unknown>;
    return { due: true, basis: (r as { basis?: string }).basis, stale: out?.stale ?? null, closed: out?.closed ?? null };
  });
  await step('usage', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('usage')) return { due: false };
    await rpc('fn_it_usage_watch', { p_r: await takeUsageReadings(sec) });
    return { due: true };
  });
  // WhatsApp / SMS delivery health (22 Sep 2026): read from what Twilio reported — delivered, read,
  // failed, undelivered — never from 'sent', which only ever meant Twilio accepted the message.
  await step('whatsapp_delivery', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('whatsapp_delivery')) return { due: false };
    return { due: true, result: await rpc('fn_it_whatsapp_delivery_health') };
  });
  // THE SCHEDULED READINGS RUN BEFORE THE MODEL STEPS (it_engineer, 19 Oct 2026). They used to sit at the end of this
  // chain, behind deliberations, held-reasoning replay and routine judgements. Since ruling 1260 opened the models,
  // those steps make real model calls (ai_cost_log, 01:00-04:00 UTC 19 Oct: 242 to 1,796 calls an hour, up from
  // 31-115). The detached itlater run ran out of its instance's time before reaching the tail: provider_status
  // last succeeded at 00:46 UTC and model_catalogue never ran once, while duty:usage and duty:whatsapp_delivery,
  // which come first, kept running every hour. These four steps are cheap, model-free and due-gated, so they run
  // first; a slow model step can delay only itself and the steps after it.
  // Provider status pages and the Vercel firewall (24 Sep 2026, it_engineer; seat audit IT gaps 3 and 5). Measured
  // here, decided by fn_it_provider_watch, hourly by it_duty_schedule 'provider_status'.
  await step('provider_status', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('provider_status')) return { due: false };
    const r = (await rpc('fn_it_provider_watch', { p_r: await takeProviderReadings(sec) })) as Record<string, unknown>;
    return { due: true, failing: r?.failing ?? null };
  });
  // Gmail Postmaster Tools, once a day (it_engineer, 24 Sep 2026): spam rate, reputation and SPF/DKIM/DMARC for
  // quotesdone.com, read by _shared/it_postmaster_readings.ts and stored and acted on by fn_it_postmaster_record
  // (a finding at 0.1%; the #943 invitation pause at 0.3% or reputation LOW/BAD). Next to the sender duty's DNS and
  // blocklist reading, on this heartbeat, never pg_cron. This function deploys on merge while its SQL may still be
  // pending, so runPostmasterStep records a missing routine or table as "skipped: schema not applied".
  await step('postmaster', () => runPostmasterStep((fn, args) => admin.rpc(fn, args), () => takePostmasterReading(fetch, sec)));
  // The model registry against the public OpenRouter catalogue, once a day (it_engineer, follow-up 28). Reading the
  // catalogue is a public GET with no key, not inference. Postgres records (fn_model_catalogue_sync): every disagreement
  // becomes a ledger row and a finding; no price is ever changed here (rulings 1217/1218). Only the fields the
  // rule reads are sent, so the payload is a fraction of the catalogue.
  await step('model_catalogue', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('model_catalogue')) return { due: false };
    const res = await timedFetch('https://openrouter.ai/api/v1/models', {}, 20_000);
    if (!res.ok) throw new Error('catalogue answered HTTP ' + res.status);
    // deno-lint-ignore no-explicit-any
    const data = ((await res.json())?.data ?? []) as any[];
    const cat = data.map((m) => ({ id: m?.id, context_length: m?.context_length ?? null,
      pricing: { prompt: m?.pricing?.prompt ?? null, completion: m?.pricing?.completion ?? null } }));
    const r = (await rpc('fn_model_catalogue_sync', { p_catalogue: cat })) as Record<string, unknown>;
    return { due: true, compared: r?.compared, open: r?.open, new: r?.new,
             resolved: r?.resolved };
  });
  await step('supplier_docs', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('supplier_docs')) return { due: false };
    const r = (await rpc('fn_sales_engineer_supplier_documents_tick')) as Record<string, unknown>;
    return { due: true, approved_rechecked: r?.approved_rechecked, registrations_closed: r?.registrations_closed };
  });
  await step('held_registrations', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('held_registrations')) return { due: false };
    const unreached = await rpc('fn_sales_engineer_closes_unreached_requests');
    return { due: true, ...((await rpc('fn_sales_engineer_decides_held_registrations')) as Record<string, unknown>), unreached };
  });
  // Its own step, never behind fn_it_restore_table_due: a drill that stops completing is a finding.
  await step('restore_overdue', async () => rpc('fn_it_restore_table_overdue'));
  // Two seats never agree on one model family (founder_instruction 873). The review steps are routed and
  // held in the database (a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql): under the hold each
  // one records "held, not run" once and costs nothing. Then the agreement monitor: a reviewer approving
  // >= 90% of >= 10 proposals, or a review with no independent model, is a finding for the CEO.
  await step('deliberations', async () => advanceOpenDeliberations(admin, 3));
  // Ledger 1152: open requests to review an automated decision are decided by the owning seat on another model family. The
  // model call runs in the CEO seat's own function (this heartbeat never imports the model client).
  await step('review_requests', async () => {
    const r = await fetch(FN + '/ceo_agent', { method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: await sec('cred_fn_ceo_agent'), action: 'review_requests', limit: 1 }), signal: AbortSignal.timeout(55000) });
    const j = await r.json().catch(() => null);
    return r.ok ? j : { ok: false, error: 'ceo_agent review_requests ' + r.status, body: j };
  });
  // Every escalation carries a clock (16 Nov 2026, escalation_clock.ts): the CEO seat decides and customer_support tells the person,
  // in the CEO seat's own function (this heartbeat never imports the model client). Nothing due: two reads and no model.
  await step('escalation_clocks', async () => {
    const r = await fetch(FN + '/ceo_agent', { method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: await sec('cred_fn_ceo_agent'), action: 'escalation_clocks', limit: 1 }), signal: AbortSignal.timeout(55000) });
    const j = await r.json().catch(() => null);
    return r.ok ? j : { ok: false, error: 'ceo_agent escalation_clocks ' + r.status, body: j };
  });
  await step('deliberation_independence', async () => rpc('fn_it_deliberation_independence_watch'));
  // Reviews held for want of an independent model, and third-family last-resort reviews, reach the CEO (#880).
  await step('review_independence', async () => rpc('fn_it_review_independence_watch'));
  // Questions a seat could not reason about under the hold are reasoned the moment it lifts
  // (founder_instruction 886-903; _shared/think.ts replayHeld). Under the hold fn_reason_held_due
  // returns nothing and no model is asked, so this step costs one gate read. Since 7 Oct (ledger 1175) a tick claims REPLAY_CLAIM
  // at a time, concurrently, up to REPLAY_MAX_ROWS within REPLAY_BUDGET_MS, a slice that fits every tick (12 Oct).
  // 27 Oct 2026 (review of #1688): the replay no longer runs here. It is KICKED into its own detached invocation
  // (heldReplayTick, its own DETACHED_MS), so its model calls can never eat the time of the steps after it
  // (reasoning_escalate's owed holding notices, routine_judgements, wa_arrival_sweep, ceo_support_replies). Measured:
  // duty:detached_itlater:itlater "passed its 120000 ms limit", seen 51 times 16:17-20:32Z with a 25 s replay budget.
  await step('reasoning_held', async () => kickDetached('heldReplay'));
  // The four routine judgements (quote spec match, repeat requests, supplier trade words, unknown-sender mail) queued by
  // their callers and not judged inline: five a tick, no per-day limit; three failed readings end a row. Held rows stay queued
  // (scripts/sql/the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does.sql).
  // 27 Oct 2026 (it_engineer): KICKED into its own detached run (routineJudgementsTick), the same move #1688 made for the
  // replay. Measured: the 22:01:12Z itlater run claimed five rows here at 22:01:27 and judged them one after another at
  // ~60 s each (two model calls of 19-31 s apiece); the run's cap fired at 22:03:12 with this step still going.
  await step('routine_judgements', async () => kickDetached('routineJudgements'));
  // A WHATSAPP TURN THAT CRASHED (customer_support, 19 Oct 2026): a wa_messages row still at stage 'received' after 5 minutes
  // goes to customer_support once and into the held-question queue (so reasoning_escalate below sends the holding notice in the same tick); never replayed
  // (scripts/sql/a_whatsapp_message_whose_turn_crashed_reaches_customer_support_in_five_minutes.sql).
  await step('wa_arrival_sweep', async () => ({ escalated: ((await rpc('fn_wa_arrival_sweep', { p_limit: 20 })) as unknown[] | null ?? []).length }));
  // A held question never expires: at 48 hours (or after 5 failed reasonings) it becomes a pending item in its
  // seat's queue, once, and a WhatsApp customer is told a person is handling it. Runs under the hold too; the
  // row stays held and is still replayed above the moment the hold lifts.
  // The CEO's answer to a customer_support handover (customer_support, #1462) passes the customer-reply gate before it
  // is sent; a held answer leaves the item open. Routing and pick-up run on pg_cron (cs_held_question_route); only this
  // TypeScript gate runs here (a_customer_support_question_reaches_a_person_in_fifteen_minutes.sql).
  await step('ceo_support_replies', async () => {
    const due = ((await rpc('fn_ceo_support_reply_due', { p_limit: 10 })) ?? []) as { handover_id: number; answer: string; lang: 'en' | 'ar'; supplier: boolean }[];
    const verdicts: Record<string, unknown>[] = [];
    for (const d of due) {
      const problems = await customerReplyGate((fn, args) => admin.rpc(fn, args), d.answer, d.lang, d.supplier);
      verdicts.push({ id: d.handover_id, verdict: await rpc('fn_ceo_support_reply_record', { p_handover_id: d.handover_id, p_problems: problems }), problems });
    }
    return { verdicts };
  });
  await step('reasoning_escalate', async () => {
    const rows = (await rpc('fn_reason_held_escalate', { p_limit: 20 })) as unknown[] | null;
    // The notices owed — the rows just escalated AND any earlier one whose send failed — come from the queue, not
    // from the escalate call's return, so a failure is retried (a_customer_notice_that_failed_is_sent_again.sql).
    const owed = (await rpc('fn_reason_held_notice_due', { p_limit: 20 })) as { id: number; surface: string; question: string; subject: Record<string, unknown> | null }[] | null;
    const told = await sendHeldNotices(owed ?? [], liveDeliveryIO(admin), (id, d) => rpc('fn_reason_held_notice_record', { p_id: id, p_delivery: d }));
    return { escalated: (rows ?? []).length, told };
  });
  // A SUPPLIER DOCUMENT WHOSE READ NEVER FINISHED (review of #1404): a profile or catalogue is marked 'reading' before
  // its parse; one still 'reading' after 30 minutes was killed mid-parse. It is set unreadable with the reason and handed
  // to the sales_engineer seat (fn_supplier_doc_reading_escalate) - never left silent - and the gate never approves past it.
  // BEFORE THAT, ONE RE-READ (19 Oct 2026, sales_engineer; _shared/supplier_docs_later.ts): a profile or catalogue read
  // after its upload answered and still 'reading' 10 minutes on is read once more by supplier_api (it runs after that
  // answer), marked retry; only a second stall reaches the escalation below.
  await step('supplier_doc_reread', async () => {
    const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/supplier_api', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY },
      body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), action: 'docs_reread' }),
    }, 30_000);
    const j = await r.json().catch(() => ({}));
    if (!(r.ok && j?.ok)) throw new Error('supplier_api docs_reread: ' + String(j?.error ?? r.status));
    return { rereading: j.rereading };
  });
  await step('supplier_doc_reading_stuck', async () => {
    const rows = (await rpc('fn_supplier_doc_reading_escalate', { p_minutes: 30, p_limit: 50 })) as unknown[] | null;
    return { handed_to_sales_engineer: (rows ?? []).length };
  });
  // THE SUPPLIER TRADE BACKFILL (sales_engineer, 23 Sep 2026): files at most the daily cap of leads for reasoning,
  // and NOTHING unless app_secrets.lead_reclassify_backfill = 'go' (the cost is quoted beside the gate).
  await step('lead_reclassify', async () => rpc('fn_lead_reclassify_tick', { p_limit: 20 }));
  await step('restore_table', async () => {
    if ((await rpc('fn_it_restore_table_due')) !== true) return { due: false };
    const pick = await rpc('fn_it_restore_table_pick');
    await rpc('fn_it_restore_table_record', { p: await runRestoreTable(admin, pick) });
    return { due: true };
  });
  // Duty 15's third-party half: a provider key the estate can rotate by API is rotated and recorded; the database
  // decides when (fn_it_provider_rotation_claim) and the old key is deleted only after the overlap (_shared/it_rotate_by_api.ts).
  await step('rotate_by_api', async () => rotateAndSettle({ rpc, sec, fetch: (u, i) => timedFetch(u, i, 20_000) }));
  // The sales engineer's daily document duty, on this heartbeat because pg_cron is not coming back:
  // expiry reconcile and final notice, approved suppliers re-verified, 14-day incomplete registrations
  // closed (the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql). Counts only.
  return out;
}
