// dispatch_inquiry — the automated cross-match dispatcher. For a finalized (rfq_ready) inquiry it
// runs the sharp adjudicator (route_inquiry), applies guardrails, PERSISTS accepted matches to
// inquiry_matches (which fires the seller-notify trigger), logs the full routing decision to
// inquiries.routing, and on ZERO genuine fits raises an internal coverage-gap flag WITHOUT spamming
// any seller. Fully automated — no founder approval. Idempotent + atomic dispatch lock (no races).
// v3: agent_runs instrumentation.
// v4 CORRECTNESS FIX: when every inquiry_matches insert failed, the inquiry was still recorded as
//    outcome:'dispatched' and the caller got ok:true - a customer RFQ that looks routed but reached
//    nobody. That case now returns ok:false and raises a founder_alert + email, so it surfaces even
//    if the caller ignores the response. Route failures escalate the same way.
// v5 AUTHORITY FIX (28 Jul 2026): body.force===true used to be honoured on the strength of
//    inbound_secret alone. inbound_secret is accepted by 134 of 187 functions, so anything holding
//    it could bypass THREE independent safety guards at once - the already_dispatched check, the
//    freshness of the atomic dispatch lock, and the lost-claim exit. Two concurrent forced runs both
//    read the existing-match set before either writes, so the dedup does not hold and suppliers get
//    contacted twice about the same RFQ. force now needs its OWN key (dispatch_force_key) plus a
//    written reason, and every use is recorded and escalated to the founder. A force attempt without
//    that key is refused outright rather than silently downgraded, so nobody believes an override
//    took effect when it did not.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 28 Jul 2026 (missed by the 27 Jul sweep): sec() returns undefined/'' when the
// app_secrets read fails or the row is missing, and the guard below compared strictly, so a caller
// posting {} matched and gained full service-role authority on a function that requires no JWT. The
// stored secret must now be a real value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function policyInt(k: string, dflt: number){ const { data } = await admin.from('decision_policy').select('value').eq('key', k).maybeSingle(); const n = Number((data as any)?.value); return Number.isFinite(n) && n > 0 ? n : dflt; }
const LOCK_STALE_MS = 120000;

const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'dispatch_inquiry', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging block dispatch */ }
}
// Out-of-band escalation: a customer RFQ reaching nobody is revenue loss and must not depend
// on whatever called this function noticing the response body.
async function escalate(subject: string, detail: string, level = 'high', event = 'rfq_not_dispatched') {
  try { await admin.from('founder_alerts').insert({ level, event, detail: String(detail).slice(0, 900), channel: 'email' }); } catch (_e) { /* */ }
  try {
    const owner = ((await sec('admin_emails')) || 'management@quotesdone.com').split(',')[0].trim();
    await admin.from('notifications').insert({ type: event, to_email: owner, to_role: 'admin', channel: 'email', subject, body: detail, status: 'queued' });
  } catch (_e) { /* */ }
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    const inbound = await sec('inbound_secret');
    if (!secretOk(inbound) || body.__secret !== inbound) { await logRun('error', {}, 'forbidden: dispatch_inquiry called without the inbound secret'); return J({ error: 'forbidden' }, 403); }
    const inquiryId = String(body.inquiry_id || '');
    if (!inquiryId) return J({ error: 'inquiry_id_required' }, 400);

    // ---- FORCE AUTHORITY GATE (v5) ----------------------------------------------------------
    // force bypasses idempotency AND concurrency control. It therefore needs authority that
    // inbound_secret does not confer, and it must never be usable anonymously or by accident.
    let force = false;
    if (body.force === true) {
      const forceKey = await sec('dispatch_force_key');
      const reason = String(body.force_reason || '').trim();
      if (!secretOk(forceKey) || body.__force_key !== forceKey || reason.length < 10) {
        await logRun('error', { inquiry_id: inquiryId, stage: 'force_auth' },
          'REFUSED a force-dispatch: force=true requires dispatch_force_key AND a force_reason of at least 10 characters. ' +
          'force bypasses the already_dispatched guard, the dispatch lock and the lost-claim exit, so two concurrent forced runs ' +
          'can contact the same suppliers twice about one RFQ. Nothing was dispatched.');
        await escalate('Refused force-dispatch on inquiry ' + inquiryId,
          'Someone called dispatch_inquiry with force=true but without dispatch_force_key (or without a written reason).\n\n' +
          'Inquiry: ' + inquiryId + '\nReason supplied: ' + (reason || '(none)') + '\n\n' +
          'The call was refused and nothing was dispatched. If this was you, supply __force_key and force_reason. ' +
          'If it was not, something holding inbound_secret is attempting to re-notify suppliers.',
          'high', 'force_dispatch_refused');
        return J({ error: 'force_requires_dispatch_force_key_and_reason' }, 403);
      }
      force = true;
      await logRun('warn', { inquiry_id: inquiryId, stage: 'force_auth', force_reason: reason.slice(0, 200) },
        'FORCE DISPATCH AUTHORISED for inquiry ' + inquiryId + '. Idempotency and the concurrency lock are being bypassed deliberately. Reason: ' + reason.slice(0, 250));
      await escalate('Force-dispatch used on inquiry ' + inquiryId,
        'dispatch_inquiry was run with force=true, which re-dispatches an RFQ that was already dispatched and bypasses the concurrency lock.\n\n' +
        'Inquiry: ' + inquiryId + '\nStated reason: ' + reason + '\n\nSuppliers not already matched to this RFQ may be contacted about it now.',
        'warn', 'force_dispatch_used');
    }
    // -----------------------------------------------------------------------------------------

    const { data: inq } = await admin.from('inquiries').select('id,rfq_ready,routing,category,emirate,summary,status').eq('id', inquiryId).maybeSingle();
    if (!inq) { await logRun('error', { inquiry_id: inquiryId }, 'inquiry_not_found - dispatch requested for an inquiry that does not exist'); return J({ error: 'inquiry_not_found' }, 404); }
    if (inq.rfq_ready !== true) return J({ ok: true, skip: 'not_rfq_ready' });
    const routing = (inq.routing && typeof inq.routing === 'object') ? inq.routing as any : {};
    if (routing.dispatched_at && !force) return J({ ok: true, skip: 'already_dispatched', dispatched_at: routing.dispatched_at });

    // ATOMIC CLAIM: set dispatch_lock only if unlocked (or stale). Losers of the race skip.
    const nowMs = Date.now(); const nowIso = new Date(nowMs).toISOString();
    const prevLock = routing.dispatch_lock ? Date.parse(routing.dispatch_lock) : 0;
    const lockFresh = prevLock && (nowMs - prevLock) < LOCK_STALE_MS;
    if (lockFresh && !force) return J({ ok: true, skip: 'dispatch_in_progress' });
    const { data: claimed } = await admin.from('inquiries')
      .update({ routing: { ...routing, dispatch_lock: nowIso } })
      .eq('id', inquiryId)
      .or('routing->>dispatch_lock.is.null,routing->>dispatch_lock.eq.' + (routing.dispatch_lock || ''))
      .select('id');
    if ((!claimed || !claimed.length) && !force) return J({ ok: true, skip: 'lost_claim' });

    const MAX_FANOUT = await policyInt('match_max_fanout', 5);
    const label = (inq.category || 'uncategorised') + ' / ' + (inq.emirate || 'UAE');

    // 1) run the sharp adjudicator (reuse route_inquiry)
    let route: any = null;
    try {
      const r = await fetch('https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/route_inquiry', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: inbound, inquiry_id: inquiryId })
      });
      route = await r.json();
    } catch (e) {
      const m = String((e as Error)?.message || e);
      await logRun('error', { inquiry_id: inquiryId, category: inq.category, emirate: inq.emirate }, 'RFQ NOT DISPATCHED - route_inquiry call threw, no supplier was contacted: ' + m);
      await escalate('RFQ not dispatched: ' + label, 'A finalized customer RFQ (' + label + ') could not be routed because route_inquiry failed, so NO supplier was contacted.\n\nInquiry: ' + inquiryId + '\nError: ' + m + '\n\nThe dispatch lock clears after 2 minutes and a retry will re-attempt. If this repeats, the RFQ is stuck.');
      return J({ ok: false, error: 'route_failed', detail: m }, 502);
    }
    if (!route || route.error) {
      const m = String(route?.error || 'no_route');
      await logRun('error', { inquiry_id: inquiryId, category: inq.category, emirate: inq.emirate }, 'RFQ NOT DISPATCHED - route_inquiry returned an error, no supplier was contacted: ' + m.slice(0, 200));
      await escalate('RFQ not dispatched: ' + label, 'A finalized customer RFQ (' + label + ') could not be routed — route_inquiry returned an error, so NO supplier was contacted.\n\nInquiry: ' + inquiryId + '\nError: ' + m + '\n\nThe dispatch lock clears after 2 minutes and a retry will re-attempt.');
      return J({ ok: false, error: 'route_error', detail: m }, 502);
    }

    const fitsAll: any[] = Array.isArray(route.fits) ? route.fits : [];
    const decisionBase = {
      dispatch_lock: null, dispatched_at: new Date().toISOString(), job_type: route.job_type || null, primary_trade: route.primary_trade || null,
      reasoning: route.reasoning || '', evaluated: route.evaluated ?? null, retrieval: route.retrieval || null, fits_returned: fitsAll.length,
      forced: force || undefined, force_reason: force ? String(body.force_reason || '').slice(0, 300) : undefined
    };

    // 2) ZERO genuine fits — never spam sellers; raise an internal coverage-gap flag
    if (!fitsAll.length) {
      await admin.from('inquiries').update({ routing: { ...routing, ...decisionBase, outcome: 'no_fit', fanout: 0 } }).eq('id', inquiryId);
      let flagged = true;
      try {
        await admin.from('agent_actions').insert({
          agent: 'operations_ai', kind: 'coverage_gap', status: 'pending', risk: 'medium',
          title: 'RFQ had no matchable seller' + (inq.category ? (': ' + inq.category) : ''),
          recommendation: 'A finalized customer RFQ (' + label + ') produced ZERO genuine seller matches — a supply-coverage gap. Consider acquiring/onboarding sellers in this trade+emirate. No sellers were contacted.',
          detail: { signal: 'coverage_gap:' + inquiryId, inquiry_id: inquiryId, category: inq.category, emirate: inq.emirate, primary_trade: route.primary_trade, evaluated: route.evaluated },
          target_table: 'inquiries', target_id: inquiryId
        });
      } catch (_e) { flagged = false; }
      if (!flagged) await escalate('Coverage gap not recorded: ' + label, 'An RFQ (' + label + ', inquiry ' + inquiryId + ') produced zero seller matches AND the coverage_gap flag failed to insert, so this gap is not in your action queue.');
      await logRun('ok', { inquiry_id: inquiryId, outcome: 'no_fit', notified: 0, evaluated: route.evaluated ?? null, category: inq.category, emirate: inq.emirate, coverage_gap_flagged: flagged },
        'coverage gap: no genuine seller for ' + label + (flagged ? '' : ' (WARNING: coverage_gap flag failed to insert)'));
      return J({ ok: true, outcome: 'no_fit', notified: 0, note: 'no genuine seller — coverage gap flagged, no seller contacted' });
    }

    // 3) guardrails: dedup against existing matches, cap fanout
    const { data: existing } = await admin.from('inquiry_matches').select('supplier_id').eq('inquiry_id', inquiryId);
    const already = new Set((existing || []).map((r: any) => Number(r.supplier_id)));
    const pick: any[] = [];
    for (const f of fitsAll) { const id = Number(f.id); if (id && !already.has(id) && !pick.some(p => Number(p.id) === id)) pick.push(f); if (pick.length >= MAX_FANOUT) break; }
    const capped = fitsAll.length > pick.length + already.size;

    // 4) persist matches (gate trigger allows only rfq_ready; notify trigger queues seller emails)
    let inserted = 0; const sent_ids: number[] = []; let insertErrors = 0; let lastInsertErr = '';
    for (const f of pick) {
      const reason = String((route.primary_trade ? route.primary_trade + ' — ' : '') + (f.reason || 'genuine capability match')).slice(0, 300);
      const { error } = await admin.from('inquiry_matches').insert({ inquiry_id: inquiryId, supplier_id: Number(f.id), similarity: null, match_reason: reason, sent_at: new Date().toISOString() });
      if (!error) { inserted++; sent_ids.push(Number(f.id)); }
      else { insertErrors++; lastInsertErr = String(error.message || '').slice(0, 200); }
    }

    const outcome = (pick.length && inserted === 0) ? 'dispatch_failed' : 'dispatched';
    await admin.from('inquiries').update({ routing: { ...routing, ...decisionBase, outcome, fanout: inserted, fit_ids: sent_ids, capped, max_fanout: MAX_FANOUT } }).eq('id', inquiryId);
    const counts = { inquiry_id: inquiryId, outcome, notified: inserted, attempted: pick.length, insert_errors: insertErrors, capped, max_fanout: MAX_FANOUT, category: inq.category, emirate: inq.emirate, forced: force };

    if (pick.length && inserted === 0) {
      // v4: no longer reported as a successful dispatch.
      await logRun('error', counts, 'RFQ REACHED NOBODY - all ' + pick.length + ' inquiry_matches inserts failed. Last error: ' + lastInsertErr);
      await escalate('RFQ reached no suppliers: ' + label,
        'A finalized customer RFQ (' + label + ') found ' + pick.length + ' matching supplier(s), but EVERY attempt to record the match failed, so no supplier was notified.\n\n' +
        'Inquiry: ' + inquiryId + '\nSuppliers that should have been contacted: ' + pick.length + '\nDatabase error: ' + lastInsertErr +
        '\n\nThe inquiry is marked dispatch_failed. This customer is waiting for quotes that will not arrive.');
      return J({ ok: false, outcome: 'dispatch_failed', notified: 0, attempted: pick.length, error: 'match_insert_failed', detail: lastInsertErr });
    }
    if (insertErrors) {
      await logRun('error', counts, insertErrors + ' of ' + pick.length + ' seller matches failed to insert, only ' + inserted + ' seller(s) contacted. Last error: ' + lastInsertErr);
      await escalate('RFQ only partly dispatched: ' + label,
        'A customer RFQ (' + label + ', inquiry ' + inquiryId + ') matched ' + pick.length + ' supplier(s) but only ' + inserted + ' were successfully contacted; ' + insertErrors + ' failed.\n\nDatabase error: ' + lastInsertErr);
    } else {
      await logRun('ok', counts, '');
    }
    return J({ ok: true, outcome: 'dispatched', notified: inserted, capped, max_fanout: MAX_FANOUT, job_type: route.job_type, primary_trade: route.primary_trade });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception during dispatch: ' + m); return J({ error: m }, 500); }
});
