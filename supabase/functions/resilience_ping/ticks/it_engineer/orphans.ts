// resilience_ping ticks owned by the it_engineer seat: the orphaned-function drain tick (doc_extract, email_triage, send_sms, sanctions_screen, email_cron, wa_templates_watch). Moved out of ticks/it_engineer.ts unchanged (9 Nov 2026);
// the order the steps run in is still set in resilience_ping/index.ts (STEP_RUN).
import { failureOf } from '../../steps.ts';
import { FN, GATEWAY, admin, sec } from '../../shared.ts';

// TWO FUNCTIONS THAT NOTHING CALLED (17 Sep 2026, it_engineer). email_cron and wa_templates_watch are
// deployed, owned and instrumented, and pg_cron — which used to call them — has been empty since
// 7 Sep. agent_runs held ONE row for each, both 9 Sep 07:10. email_cron reports the one thing
// send_outbox structurally cannot (a disabled mail system: nothing would invoke send_outbox to tell
// you it is off) and auto-detects Resend domain verification; wa_templates_watch flips
// wa_templates_ready when Meta approves, and WhatsApp is the founder's command channel.
//
// GATED IN POSTGRES, like backupTick: one RPC answers for all of them, so a tick where none is due costs
// one round trip and no HTTP. email_cron is due only while email is NOT enabled (when it is, outboxTick
// below already drains every tick and email_cron would add nothing but a second flush);
// wa_templates_watch only while wa_templates_ready is not 'true', so it stops polling Twilio the moment
// approval lands. Measured 18 Sep: both flags are 'true', so both gates are shut and this step is the
// RPC alone. Each swallows its own error — a step that throws is a step the whole tick pays for.
//
// FOUR MORE JOINED ON 18 Sep 2026 (it_engineer, orphan audit). Every one is deployed, owned and live, and
// had no caller at all since pg_cron emptied on 7 Sep. Gates and measured backlogs are in
// scripts/sql/four_live_functions_had_no_clock_and_the_sanctions_screen_had_no_producer.sql:
//   doc_extract   the ONLY writer of documents.extracted and the only OCR path. 12 documents sat
//                 pending, the last extraction was 12 Aug. It CALLS ai_gateway on every document, so
//                 wiring it starts real model spend and OpenRouter is on hold: the gate also requires
//                 app_secrets.doc_extract_drain_enabled = 'true', a key that does not exist, so it ships
//                 SHUT. Flipping that one key is the whole switch-on.
//   email_triage  the only writer of inbound_messages.triaged_at; LLM per message, same flag treatment
//                 (email_triage_enabled). Measured drainable backlog: 0.
//   send_sms      drains channel='sms' notifications, which send_outbox deliberately refuses. NO flag —
//                 no model, and the gate is the queue itself, exactly like whatsappTick below.
//   sanctions_screen  downloads the UN and UAE sanctions lists and hands them to
//                 fn_supplier_sanctions_screen. Weekly, gated on the age of the newest screening_run.
// THE WHOLE STEP IS BOUNDED, NOT EACH CALL. Six gates, each with its own timeout, add to more than the
// 110 s the entire tick is allowed (30+20+20+25+40+55 = 190 s). So the step carries ONE budget, the gates
// run in priority order, and a job is only STARTED if what is left of the budget covers its own worst
// case — so ORPHAN_BUDGET_MS is a real ceiling and not a suggestion. Every one of these consumers is a
// queue drainer or an idempotent poller, so being deferred costs a beat and never a message. And a
// deferral is returned as a FAILURE, so a step that keeps running out of budget raises an IT finding
// instead of silently starving its tail — that failure has already been paid for once in this estate
// (outbox starvation, #691).
const ORPHAN_BUDGET_MS = 60_000;
// doc_extract extracts ONE document per call, so a queue of 12 would take three hours at one a tick.
// ponytail: up to 3 a tick, ~96 documents/day; raise DOC_MAX (and the budget) if a real upload queue
// outruns it.
const DOC_MAX = 3;

export async function orphanTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_resilience_orphan_steps_due');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const due = data as any;
    if (!due || !Object.values(due).some(Boolean)) return { due: false };
    const secret = await sec('cred_fn_resilience_ping');
    // THE SANCTIONS SCREEN TAKES A DIFFERENT CREDENTIAL, AND THIS STEP COULD NEVER HAVE REACHED IT
    // (18 Sep 2026). Internal credentials are SCOPED — fn_internal_auth refuses one that is not scoped
    // to the callee — and this function's is not scoped to sanctions_screen. Measured in production:
    //   fn_internal_auth(cred_fn_resilience_ping, 'send_outbox')      -> ok:true (credential 49)
    //   fn_internal_auth(cred_fn_resilience_ping, 'sanctions_screen') -> out_of_scope
    //   fn_internal_auth(cred_cron_compliance,    'sanctions_screen') -> ok:true (credential 175,
    //                                              context cron.compliance, scope ['sanctions_screen'])
    // Exactly ONE credential in the table is scoped to sanctions_screen, and it is not this one. Proved
    // over HTTP as well: presenting this function's credential past the platform gateway answered
    // 403 {"error":"forbidden"}. So the step presents the credential the scope model already says owns
    // that call, rather than widening fn.resilience_ping's scope — widening it would make scoped
    // credentials decorative, which is the one thing audit 9.5 exists to prevent.
    const complianceSecret = await sec('cred_cron_compliance');
    // THE SAME RULE FOR THE OTHER FIVE (28 Sep 2026, it_engineer). wa_templates_watch answered 403 on
    // every hourly run: internal_credential_audit, 137 rows in 48 h, context fn.resilience_ping,
    // reason out_of_scope. send_sms, email_cron, email_triage and doc_extract were out of scope the
    // same way and only silent because their gates were shut. Each presents its owning context's
    // credential (scripts/sql/the_template_watcher_is_called_with_a_credential_scoped_to_it.sql);
    // prevented by scripts/checks/resilience_orphan_jobs_present_a_scoped_credential.test.mjs.
    const notificationsSecret = await sec('cred_cron_notifications');
    const documentsSecret = await sec('cred_cron_documents');
    // The accountant's own credential for its expense_sweep (reasoned_books.ts presents the same one):
    // this function's credential is not scoped to the accountant, and widening it is what audit 9.5 forbids.
    const accountantSecret = await sec('cred_fn_accountant');
    // A 200 CARRYING A FAILED BODY IS A FAILURE, AND failureOf CANNOT SEE INSIDE `body` (third finding
    // from independent review). Returning {status, body} meant only a fetch exception or a 4xx/5xx was
    // ever counted: a callee answering HTTP 200 {ok:false, error:'…'} — which is how every one of these
    // reports a refusal — was recorded in `results` and never pushed onto `failing`, so it raised no IT
    // finding. That is quote_compare's {ok:false} at HTTP 200, and it is in this repo's own skill as the
    // reason to assert on the effect and not the status. The failure is lifted to the top of the entry so
    // failureOf reads it. A bare {ok:false} with NO error string is deliberately left alone: by steps.ts's
    // convention that is a seat that has already staged its own finding, and counting it twice is noise.
    const call = async (slug: string, ms = 20000, body: Record<string, unknown> = {}, cred: string = secret) => {
      try {
        const r = await fetch(FN + '/' + slug, {
          method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
          body: JSON.stringify({ __secret: cred, ...body }), signal: AbortSignal.timeout(ms),
        });
        const b = await r.json().catch(() => null);
        const inner = r.status < 400 ? failureOf(b) : null;   // a 4xx/5xx is already read off `status`
        return inner
          ? { ok: false, error: slug + ' answered HTTP ' + r.status + ' with: ' + inner, status: r.status, body: b }
          : { status: r.status, body: b };
      } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
    };
    const t0 = Date.now();
    const left = () => ORPHAN_BUDGET_MS - (Date.now() - t0);
    // Order is priority: a queued SMS has a person at the end of it; the sanctions download is weekly
    // and the least urgent thing here, so it goes last and is the one that gets deferred.
    // The third element is that job's OWN worst case, and the loop below will not start a job it cannot
    // afford to finish. Gating on "any time left at all" would make ORPHAN_BUDGET_MS a suggestion: 500 ms
    // left is enough to start a 55 s download, and the step would overrun the whole tick's 110 s.
    const jobs: Array<[string, string, number, () => Promise<unknown>]> = [
      ['send_sms', 'send_sms', 30000, () => call('send_sms', 30000, { limit: 25 }, notificationsSecret)],
      ['email_cron', 'email_cron', 20000, () => call('email_cron', 20000, {}, notificationsSecret)],
      ['wa_templates', 'wa_templates_watch', 20000, () => call('wa_templates_watch', 20000, {}, notificationsSecret)],
      ['doc_extract', 'doc_extract', 25000, async () => {
        const d0 = Date.now();
        const runs: unknown[] = [];
        for (let i = 0; i < DOC_MAX && left() > 25_000; i++) {
          const r = await call('doc_extract', 25000, {}, documentsSecret);
          runs.push(r);
          // deno-lint-ignore no-explicit-any
          if ((r as any)?.body?.note === 'no pending documents' || (r as any)?.error) break;
        }
        // runSteps judges this step per ENTRY, and an entry it cannot read is a failure it cannot see.
        // {calls, ms, runs} has neither `ok` nor `status`, so a 500 from doc_extract would vanish inside
        // `runs` — the same shape of blindness the nested flag exists to end. Lift the first failure to
        // the top of this entry so failureOf reads it.
        const bad = runs.map((r) => failureOf(r)).find(Boolean) ?? null;
        return bad
          ? { ok: false, error: bad, calls: runs.length, ms: Date.now() - d0, runs }
          : { calls: runs.length, ms: Date.now() - d0, runs };
      }],
      ['email_triage', 'email_triage', 40000, () => call('email_triage', 40000, {}, notificationsSecret)],
      // 28 Sep 2026: held expense mail is swept daily, so a receipt from a sender the books know is booked
      // without a model (scripts/sql/the_books_catch_up_under_the_model_hold_from_known_senders.sql).
      ['expense_sweep', 'accountant.expense_sweep', 55000, () => call('accountant', 55000, { action: 'expense_sweep' }, accountantSecret)],
      ['sanctions', 'sanctions_screen', 55000, () => call('sanctions_screen', 55000, {}, complianceSecret)],
    ];
    const out: Record<string, unknown> = {};
    for (const [gate, key, need, run] of jobs) {
      if (!due[gate]) continue;
      // A DEFERRED JOB IS A FAILURE, NOT A NOTE (found in independent review before this shipped).
      // Written as {deferred:true}, failureOf reads neither `ok` nor `status`, so runSteps would skip it
      // and the IT engineer would never hear about it — and `sanctions` is last in this list, so the one
      // thing here that is a compliance obligation is exactly the one a busy tick would starve in
      // silence, for ever. That is outbox starvation (#691) rebuilt one level down. So it is shaped as
      // {ok:false, error}: fn_it_duty_settle raises ONE finding per step and counts the repeats, which is
      // the difference between "deferred once, 15 minutes late" and "never runs".
      if (left() < need) {
        out[key] = { ok: false, error: 'deferred: only ' + Math.max(0, left()) + ' ms of the orphan step budget left, this call needs ' + need + ' ms' };
        continue;
      }
      out[key] = await run();
    }
    out.ms = Date.now() - t0;
    return out;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
