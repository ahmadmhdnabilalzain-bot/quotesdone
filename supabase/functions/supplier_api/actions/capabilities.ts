// supplier_api — what the company can quote for: capability_state / capability_confirm, services_*.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
//
// The capability history comment above capability_state sat, in the single file, between claim and support_rating;
// it moved here with the action it describes.
import { capabilityState, capabilityConfirm } from '../../_shared/supplier_capability.ts';
import { servicesState, servicesResolve, servicesRewrite, servicesSaveRewrite, transcribeServiceNote, voiceEnabled } from '../../_shared/supplier_services.ts';
import { answerQuestion, listQuestions, type MapWords } from '../../_shared/supplier_service_questions.ts';
import { runtimeWaitUntil } from '../../_shared/async_webhook.ts';
import { type ActionCtx, J, SUPA_URL, admin } from '../context.ts';

export async function capabilityActions(c: ActionCtx): Promise<Response | undefined> {
  const { req, email, body, action } = c;
    // WHAT THIS COMPANY CAN QUOTE FOR (12 Aug 2026; answered here since 14 Sep 2026).
    //
    // Until 14 Sep this proxied to the capability_agent edge function, which the 7 Sep sweep deleted
    // from production; every call since returned the gateway's 404. state/confirm never needed a
    // model and now run in-process from _shared/supplier_capability.ts (see its header). The history
    // below is kept because the security argument still holds: the id comes from the caller's JWT.
    //
    // Original note — the supplier-facing side of capability_agent (12 Aug 2026).
    //
    // fn_match_capability gates on supplier_capabilities.confirmed_at ("GATE: supplier confirmed
    // their own scope") and capability_agent's `confirm` is its only writer. That endpoint had no
    // caller anywhere, so no supplier could ever be matched to anything.
    //
    // IT IS PROXIED HERE RATHER THAN CALLED FROM THE BROWSER, and that is a security decision, not
    // tidiness. capability_agent takes `supplier_id` straight from the request body and authenticates
    // only with an internal secret. Handing the browser that secret would let any signed-in supplier
    // read and CONFIRM another company's scope by changing one number - the same enumeration defect
    // claim_lookup was hardened against on 19 Jul, one layer up. Here the id is resolved from the
    // caller's own JWT via claimed_by and the client's id is never consulted.

    if (action === 'capability_state' || action === 'capability_confirm') {
      const { data: mine } = await admin.from('leads').select('id,service_emirates').eq('claimed_by', email).maybeSingle();
      if (!mine) return J({ error: 'claim_your_company_first', code: 'no_company', message: 'Claim your company before confirming what it can quote for.' }, 400);
      if (action === 'capability_state') return J(await capabilityState(admin, Number(mine.id)));
      // Whitelisted fields only. The client cannot inject supplier_id, and there is no route to the
      // old `analyze` (a model pass) from here.
      const fwd: Record<string, unknown> = {};
      {
        for (const k of ['trades','roles','services','products','coverage_emirates','brands',
                         'project_types','exclusions','min_project_value','max_project_value']) {
          if (body[k] !== undefined) fwd[k] = body[k];
        }
        // COVERAGE 12 Aug 2026. Walked the registration end to end and the confirmed row came out
        // with coverage_emirates = {} even though the same supplier had just told the registration
        // form they serve Dubai, Sharjah and Abu Dhabi. CapabilityConfirmPanel sends
        // `cap.coverage_emirates || []`, and for anyone whose scope was never derived from a
        // scrape (every self-registered and every newly-invited supplier) `cap` is null, so it
        // posts an empty array over the answer we already hold. fn_match_capability then ranks
        // them with `why: 'coverage not stated'` - still matchable, but below an identical
        // supplier who happened to have a derived row. The emirates are not missing; they are
        // one table away. Defaulted server-side so every caller gets it, and only when the client
        // genuinely has nothing to say: an explicit non-empty list from the screen always wins.
        const sent = fwd.coverage_emirates as unknown[] | undefined;
        if (!Array.isArray(sent) || !sent.length) {
          const declared = (mine as { service_emirates?: string[] }).service_emirates;
          if (Array.isArray(declared) && declared.length) fwd.coverage_emirates = declared;
        }
      }
      const [status, out] = await capabilityConfirm(admin, Number(mine.id), fwd);
      return J(out, status);
    }

    // THE SERVICES CHECKLIST (15 Sep 2026, sales_engineer) — docs/api/supplier_portal_services.md.
    // Same rule as the capability pair above: the supplier id comes from the caller's own JWT, never
    // from the body. The confirm underneath is capabilityConfirm, so the ledger row is unchanged.
    if (action === 'services_state' || action === 'services_resolve'
        || action === 'services_rewrite' || action === 'services_save_rewrite' || action === 'transcribe_service_note'
        || action === 'services_questions' || action === 'services_answer') {
      const { data: mine } = await admin.from('leads').select('id,service_emirates').eq('claimed_by', email).maybeSingle();
      if (!mine) return J({ error: 'claim_your_company_first', code: 'no_company' }, 400);
      const sid = Number(mine.id);
      const declaredEmirates = () => (Array.isArray(mine.service_emirates) ? mine.service_emirates as string[] : []);
      if (action === 'services_state') return J(await servicesState(admin, sid));
      if (action === 'services_resolve') { const [s, o] = await servicesResolve(admin, body); return J(o, s); }
      // THE SALES ENGINEER'S REWRITE (instruction 438). Preview writes nothing; the save is the
      // supplier's confirmation of what it was shown.
      if (action === 'services_rewrite') { const [s, o] = await servicesRewrite(admin, sid, body); return J(o, s); }
      if (action === 'services_save_rewrite') { const [s, o] = await servicesSaveRewrite(admin, sid, body, declaredEmirates()); return J(o, s); }
      // THE QUESTIONS (12 Nov 2026, slice 4; ruling 1647): read them, and answer one. The answer itself asks no model: the options
      // were fixed when his documents were read, so an answer is one read and one write. "Something else" words are mapped AFTER the
      // response, by the same rewrite the "Add a service we missed" box uses, which the model reads (rulings 1663/1664); a key that
      // fits comes back as a card, never as a tick.
      if (action === 'services_questions') {
        try { return J({ ok: true, questions: await listQuestions(admin, sid) }); }
        catch (_e) { return J({ ok: false, error: 'questions_unavailable', code: 'questions_unavailable' }, 503); }
      }
      if (action === 'services_answer') {
        const mapWords: MapWords = async (text) => {
          const [st, out] = await servicesRewrite(admin, sid, { text });
          if (st !== 200) return [];
          const items = (out.items as { kind: string; key?: string; label_en?: string }[] | undefined) ?? [];
          const named = items.filter((i) => i.kind === 'service' && i.key).map((i) => ({ key: i.key!, label_en: i.label_en ?? i.key! }));
          const meant = ((out.meaning as { proposals?: { key: string; label_en: string }[] } | undefined)?.proposals ?? []).map((p) => ({ key: p.key, label_en: p.label_en }));
          return [...named, ...meant];
        };
        const [s, o] = await answerQuestion(admin, sid, body, { waitUntil: runtimeWaitUntil(), mapWords });
        return J(o, s);
      }
      // Voice goes to the existing transcribe function with the caller's own token, so it keeps its
      // own sign-in check, byte sniffing and malware scan. Nothing reaches it while the flag is off.
      const [s, o] = await transcribeServiceNote(sid, body, {
        enabled: () => voiceEnabled(admin),
        recentCount: async (id) => {
          const { count } = await admin.from('supplier_voice_note').select('id', { count: 'exact', head: true })
            .eq('supplier_id', id).gte('created_at', new Date(Date.now() - 3600e3).toISOString())
            .not('outcome', 'in', '(flag_off,rate_limited)');
          return count || 0;
        },
        audit: async (row) => { const { error } = await admin.from('supplier_voice_note').insert(row); if (error) console.error('supplier_voice_note insert failed', error.message); },
        start: async (row) => {
          const { data, error } = await admin.from('supplier_voice_note').insert(row).select('id').single();
          if (error) console.error('supplier_voice_note insert failed', error.message);
          return async (patch) => { if (data?.id) await admin.from('supplier_voice_note').update(patch).eq('id', data.id); };
        },
        transcribe: async (b64, mime) => {
          try {
            const r = await fetch(`${SUPA_URL}/functions/v1/transcribe`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: req.headers.get('Authorization') || '' }, body: JSON.stringify({ audio_b64: b64, mime }) });
            const j = await r.json().catch(() => ({}));
            return r.ok && j && j.ok && typeof j.text === 'string' ? { ok: true, text: j.text } : { ok: false, error: String(j?.error || r.status) };
          } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
        },
      });
      return J(o, s);
    }
}
