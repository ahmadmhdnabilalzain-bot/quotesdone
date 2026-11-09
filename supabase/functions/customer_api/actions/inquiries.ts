// customer_api — requests: concierge, repeat_inquiry, create_inquiry, missing_specs / add_missing_specs, rfq_note,
// my_inquiries, spec_offer_reply, complete_inquiry, edit_inquiry, cancel_inquiry.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
//
// KEPT AS IT WAS: repeat_inquiry reassigns `body` and `action` and FALLS THROUGH into create_inquiry, the one posting
// door. That is why both are `let` here and why the two blocks stay adjacent and in this order.
import { NOT_LIVE_QUOTE_IN } from '../../_shared/quote_live.ts';
import { seedTerms, redactBoq } from '../../_shared/anonymise.ts';
import { postedSingle, postedSplit } from '../../_shared/inquiry_posted.ts';
import { notSureKeys, specHandoffArgs } from '../spec_handoff.ts';
import { splitInquiry } from '../../_shared/inquiry_split.ts';
import { repeatCheck, repeatPlan } from '../repeat.ts';
import { HELD_NOTICE, hasArabic, holdForEnglish, mailMatched, supplierMail } from '../../_shared/supplier_english.ts';
import { defaultDeps } from '../../_shared/think.ts';
import { openLines, settleLines, type BoqCheck } from '../../_shared/boq_open_lines.ts';
import { asLocale, documentLocale } from '../../_shared/registered_locale.ts';
import { labelQuotes } from '../../_shared/quote_labels.ts';
import { accountMissing } from '../../_shared/account_rule.ts';
import { currentCustomerTermsVersion, needsReacceptance, REACCEPT_MESSAGE } from '../../_shared/customer_terms.ts';
import { applyEdits, validateStored, supplierLine } from '../../_shared/intake_requirements.ts';
import { feeBaseOf, feeBasisLine, priceStated, vatStated } from '../../_shared/stated_price.ts';
import { requestDelivery } from '../../_shared/deliver.ts';
import { acceptedMessage, apologyMessage, offerTexts, type OfferForText } from '../../_shared/line_specs/no_exact_spec.ts';
import { arabicTextsFor } from '../../_shared/reasoned_governance.ts';
import { sanctionedLeads } from '../../_shared/sanctioned.ts';
import { heldQuoteIds, itemsByQuote } from '../../_shared/reveal_guard.ts';
import { verifiedBadges } from '../../_shared/verified_badges.ts';
import { scrubIdentity } from '../../supplier_api/identity_scrub.ts';
import { type ActionCtx, INQUIRY_LIMIT_PER_HOUR, J, SERVICE, SUPABASE_URL, admin, getSecret } from '../context.ts';
import { EDIT_WINDOW_MS, inquiryNotSaved, labelize, supplierLabel } from '../lib/inquiry_rules.ts';
import { signedDrawing } from '../lib/storage.ts';
import { resolveRedactedPaths } from '../lib/drawings.ts';
import { buyerNameOf, matchAndNotify, notifyLosers } from '../lib/matching.ts';
import { getCfg, ratingBand, ratingOf, refundRef, revealFee, reviewCountBand, yearsBand } from '../lib/pricing.ts';

export async function inquiryActions(c: ActionCtx): Promise<Response | undefined> {
  let { body, action } = c;
  const { user, email, cust, recordTermsAcceptance } = c;
    // THE FIRST-INQUIRY CONCIERGE (customer_support, 29 Sep 2026; founder ledger 1018). The composer asks for the
    // step-by-step guidance (describe the job, PDF or CAD drawings only per ruling 1000, the trade's specs from its
    // verified pack, what happens next) and shows it on a customer's first request. Read-only, in the page language.
    // scripts/sql/customer_support_guides_a_first_request_step_by_step_and_asks_a_held_one_for_its_specs.sql
    if (action === 'concierge') {
      const { data, error } = await admin.rpc('fn_customer_concierge', { p_customer: cust.id,
        p_category: body.category ? String(body.category).slice(0, 80) : null, p_lang: documentLocale(body.lang, cust.locale), p_inquiry: null });
      if (error) return J({ ok: false, error: 'concierge_unavailable' }, 503);
      return J({ ok: true, concierge: data });
    }

    // REPEAT A PAST REQUEST IN ONE CLICK (founder_instruction 1028; ./repeat.ts). It builds a ready intake from
    // the customer's own earlier request and then falls through to create_inquiry, the one posting door.
    if (action === 'repeat_inquiry') {
      const { data: o } = await admin.from('inquiries').select('id,customer_id,parent_inquiry_id,category,emirate,raw_input,spec,summary,budget,scope_type,trades,floor,project_id,lang,created_at').eq('id', String(body.inquiry_id || '')).maybeSingle();
      if (!o || o.customer_id !== cust.id) return J({ error: 'not_found' }, 404);
      if (o.parent_inquiry_id) return J({ error: 'repeat_the_whole_request', message: 'This is one trade of a larger request. Repeat the whole request instead.' }, 409);
      const now = new Date();
      const cats = [...new Set([o.category, ...(Array.isArray(o.trades) ? o.trades : [])].filter(Boolean).map(String))];
      const { data: cs } = cats.length ? await admin.from('category_specs').select('fields').in('category', cats) : { data: [] };
      const checklistKeys = (cs || []).flatMap((r: any) => Array.isArray(r.fields) ? r.fields.map((f: any) => String(f?.key || '')).filter(Boolean) : []);
      const plan = repeatPlan(o, now, body.edits && typeof body.edits === 'object' ? body.edits : {}, checklistKeys);
      // Checked before anything is written, so a refusal leaves no intake row (release review of #1180).
      const chk = repeatCheck(plan, now);
      if (!chk.ok) return J({ error: 'nothing_to_repeat', missing: chk.missing, message: 'This request has no saved answers to repeat. Please start a new request instead.' }, 422);
      // The edit step (founder_instruction 1028): the customer sees the copy and changes it before anything is posted.
      if (body.preview === true) return J({ ok: true, draft: { summary: plan.brief.summary, budget: plan.brief.budget, emirate: plan.brief.emirate, required_by: chk.required_by } });
      // Double-click guard: one copy of the same request per customer within three minutes.
      // ponytail: read-then-insert, so two calls in the same instant can both pass; add a unique key if that is ever seen.
      const since = new Date(now.getTime() - 3 * 60e3).toISOString();
      const { count: dup } = await admin.from('inquiry_intake').select('id', { count: 'exact', head: true }).eq('customer_id', cust.id).eq('brief->>repeat_of', o.id).gte('created_at', since);
      if ((dup || 0) > 0) return J({ error: 'already_repeated', message: 'This request was just posted again. Check your requests list.' }, 409);
      // A repeat draft that never posted (create_inquiry refused it) is retired after the window, so the
      // database guard below never blocks a later repeat of the same request.
      await admin.from('inquiry_intake').update({ status: 'expired' }).eq('customer_id', cust.id).eq('status', 'ready').eq('brief->>repeat_of', o.id).lt('created_at', since);
      // IDEMPOTENT IN THE DATABASE (release review of #1180): inquiry_intake_one_open_repeat is a unique partial index
      // on (customer_id, brief->>'repeat_of') while 'ready', so two concurrent clicks cannot both insert; 23505 = 409.
      const { data: it, error: ie } = await admin.from('inquiry_intake').insert({ customer_id: cust.id, email, category: plan.category, status: 'ready', raw_input: plan.raw_input, brief: plan.brief, readiness: 100, missing: [], turns: [] }).select('id').single();
      if (ie?.code === '23505') return J({ error: 'already_repeated', message: 'This request was just posted again. Check your requests list.' }, 409);
      if (ie || !it) return J({ error: 'save_failed' }, 500);
      // A NEW body built only from the server's plan: nothing else the client sent reaches create_inquiry.
      body = { ...plan.body, intake_id: it.id };
      action = 'create_inquiry';
    }

    if (action === 'create_inquiry') {
      // THE FIRST CONFIRMATION MESSAGE (same build). The moment a request is posted, customer_support e-mails a
      // first request its number and the steps, or a later request held for its specs exactly what is missing
      // (once per request; the customer_support.concierge duty covers the other doors). Its guidance comes back
      // on the answer so the portal can show it. Never fails the post: a request that went out stays posted.
      const confirmRequest = async (id: string): Promise<unknown> => {
        try { const { data } = await admin.rpc('fn_customer_support_concierge_confirm', { p_inquiry: id }); return (data as { concierge?: unknown } | null)?.concierge ?? null; }
        catch (_e) { return null; }
      };
      // THE INQUIRY'S LANGUAGE (founder, 28 Sep 2026): every message to the customer about this request
      // uses the language they chose when they created it - the page language the composer sends.
      // Stored on inquiries.lang; public.fn_inquiry_locale reads it. Suppliers are always written in English.
      const inquiryLang = documentLocale(body.lang, cust.locale);
      // THE FOUNDER'S ACCOUNT RULE (14 Sep 2026): a request is made only by a signed-up customer with
      // a name, an 18+ date of birth, an OTP-verified mobile OR email, and the Terms checkbox. The
      // definition lives in _shared/account_rule.ts so kyc and this gate cannot drift. A reachable
      // mobile stays required on top (the reveal hands the winning supplier a contact card).
      const missingAcct = accountMissing(cust);
      if (!String(cust.phone || '').trim()) missingAcct.push('mobile_number');
      if (missingAcct.length) return J({ error: 'account_incomplete', code: 'account_incomplete', missing: missingAcct, message: 'Please finish setting up your account first: ' + missingAcct.join(', ') + '. Open the Account tab.' }, 403);
      // REGISTRATION COMPLETENESS GATE (2 Aug 2026, external code review). This endpoint checked
      // email_verified and nothing else, so the three things that make a buyer real — a name, a
      // reachable mobile, and an accepted version of the Terms — were enforced by the FRONTEND
      // only. Anyone with a verified email and a JWT could POST straight here and put an RFQ in
      // front of matched suppliers with none of them. Two concrete costs: the supplier who later
      // wins the job is handed a reveal (which the buyer paid 3% for) containing an empty contact
      // card, and there is no accepted-terms record to point at if that job goes wrong — the
      // entire T&C evidence chain assumes tos_accepted_at exists by the time an RFQ is dispatched.
      //
      // Deliberately NOT blocking on signed_terms_path. The signed certificate is produced
      // out-of-band by compliance_archive (PDF render + Dropbox mirror), so a transient failure
      // there is not the buyer's fault, is not a privacy risk, and blocking on it would take a
      // customer's ability to trade away for an operational fault of ours. It is repaired in the
      // background instead, so the evidence still lands and the gap stays visible.
      // (Enforced by the account-rule gate above since 14 Sep 2026.)
      // A NEWER TERMS VERSION IS ACCEPTED INLINE, NEVER A WALL (release review of #1240): an older acceptance stands
      // until this, the customer's next request. The composer shows the current Terms with a checkbox and resends
      // with accept_terms_version; nothing else about the request changes. 409, with the message in both languages.
      {
        const curV = await currentCustomerTermsVersion(getSecret);
        if (needsReacceptance(cust, curV)) {
          if (body.accept_terms_version !== curV) return J({ error: 'terms_reaccept', code: 'terms_reaccept', version: curV, message: REACCEPT_MESSAGE.en, message_ar: REACCEPT_MESSAGE.ar }, 409);
          if (!(await recordTermsAcceptance())) return J({ error: 'could not record the acceptance', code: 'terms_not_recorded' }, 500);
        }
      }
      if (!cust.signed_terms_path) {
        // Fire-and-forget repair. Never awaited: create_inquiry must not inherit the latency or
        // the failure mode of a PDF render and a Dropbox round-trip.
        try {
          const s = await getSecret('cred_fn_customer_api');
          fetch(`${SUPABASE_URL}/functions/v1/compliance_archive`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: s, action: 'sign', kind: 'customer', email }) }).catch(() => { /* best effort */ });
        } catch (_e) { /* never blocks the buyer */ }
      }
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: recent } = await admin.from('inquiries').select('id', { count: 'exact', head: true }).eq('customer_id', cust.id).gte('created_at', hourAgo);
      if ((recent || 0) >= INQUIRY_LIMIT_PER_HOUR) return J({ error: 'You have created many requests in a short time. Please try again later.' }, 429);
      const drawing = body.drawing && typeof body.drawing === 'object' ? body.drawing : null;
      let boqObj = drawing?.boq && typeof drawing.boq === 'object' ? drawing.boq : null;
      const briefSource = drawing ? (['drawing','quotation','boq'].includes(String(drawing.brief_source)) ? String(drawing.brief_source) : 'drawing') : null;
      let intake: any = null;
      if (body.intake_id) { const { data: it } = await admin.from('inquiry_intake').select('*').eq('id', String(body.intake_id)).maybeSingle(); if (it && it.email === email && it.status === 'ready') intake = it; }
      // INTAKE GATE BYPASS (27 Jul 2026). The mandatory intake used to be waived whenever the
      // CALLER posted a drawing object carrying a one-line boq array — a body the client builds
      // and can therefore forge, so { drawing: { boq: { boq: [{}] } } } skipped the questions
      // entirely and suppliers got briefs with no scope, quantity or emirate. The only bypass now
      // is a real, server-side inquiry_intake row owned by this customer and marked 'ready'
      // (resolved just above). A drawing still enriches the brief; it no longer replaces it.
      if (!intake) return J({ error: 'intake_required', message: 'Please answer a few quick questions so suppliers can quote accurately.' }, 428);
      const briefObj = intake?.brief && typeof intake.brief === 'object' ? intake.brief : null;
      let category = String(body.category || '').trim();
      if (!category && intake?.category) category = String(intake.category).trim();
      if (!category && boqObj?.category) category = String(boqObj.category).trim();
      const raw = String(body.raw_input || (intake?.raw_input || '')).slice(0, 4000);
      let summary = String(body.summary || '').slice(0, 500);
      if (!summary && briefObj?.summary) summary = String(briefObj.summary).slice(0, 500);
      if (!summary && boqObj?.summary) summary = String(boqObj.summary).slice(0, 500);
      // THE TRADE IS THE INTAKE'S, ALREADY REASONED (23 Sep 2026, decision point customer_api.keywords). The keyword
      // fallback (./keywords.ts detect()) is deleted and NOTHING here reads the words for a trade: a request only
      // posts from a 'ready' intake (above), and inquiry_intake always saves a trade on it — the model's, the one
      // tradeOf reasoned (held: the intake itself is held and never reaches 'ready', point 18), or 'general' when
      // no listed trade is exactly the job. 'general' here is only that same no-trade answer, never a guess.
      // A category the body or the drawing names is data from outside: only an exact category_specs key is kept;
      // anything else is ignored and the intake's reasoned trade decides (never a nearest match).
      if (category && category !== 'general') {
        const { data: known } = await admin.from('category_specs').select('category').eq('category', category).maybeSingle();
        if (!known) category = intake?.category ? String(intake.category).trim() : '';
      }
      if (!category) category = 'general';
      const emirate = body.emirate || (briefObj?.emirate || null) || null;
      const specIn = body.spec && typeof body.spec === 'object' ? body.spec : {};
      const spec = (briefObj?.details && typeof briefObj.details === 'object') ? { ...briefObj.details, ...specIn } : specIn;
      const budget = (body.budget ? String(body.budget) : (briefObj?.budget ? String(briefObj.budget) : '')).slice(0, 80) || null;
      // THE SALES ENGINEER'S QUESTIONS GATE THE POST (founder, 14 Sep 2026: "do you require a warranty?
      // do you require installation? do you have specific material in mind ... our job is to ask").
      // inquiry_intake only marks an intake ready once they are answered; this re-checks the stored
      // answers on the server, because a ready intake from before this change, or a body that edits
      // them, must not post a request whose baseline is missing. Edits from the summary card are
      // parsed again here (applyEdits); the browser's reading of them is never trusted. The answers go
      // into spec, so the existing identity scrub (spec_masked, scrubDeep) covers them and suppliers
      // read them with the rest of the brief (docs/contracts/intake_answers.md).
      const reqCategory = String(briefObj?.requirements?.category || intake?.category || category);
      let reqStored: any = briefObj?.requirements ?? null;
      if (body.requirement_edits && typeof body.requirement_edits === 'object' && !Array.isArray(body.requirement_edits) && Object.keys(body.requirement_edits).length) {
        const ed = applyEdits(reqCategory, reqStored, body.requirement_edits, new Date());
        if (ed.invalid.length) return J({ error: 'requirements_invalid', keys: ed.invalid, message: 'One of your changes could not be read. Pick one of the options instead.' }, 422);
        reqStored = ed.stored;
      }
      const reqCheck = validateStored(reqCategory, reqStored);
      if (!reqCheck.ok) return J({ error: 'requirements_incomplete', missing: reqCheck.missing, message: 'A few quick questions are still open: materials, installation, warranty or the date you need it by.' }, 428);
      spec.customer_requirements = reqStored;
      const scope_type = ['single','multi','turnkey'].includes(String(body.scope_type)) ? String(body.scope_type) : 'single';
      const tradesIn = Array.isArray(body.trades) ? body.trades.map((t: any) => String(t).toLowerCase()).filter(Boolean) : [];
      // inquiries.keywords: the stated trade codes and the drawing's own keywords — nothing read off the brief's words.
      let keywords = Array.from(new Set([category, ...tradesIn]));
      if (Array.isArray(boqObj?.keywords)) keywords = Array.from(new Set([...keywords, ...boqObj.keywords.map((s: any) => String(s).toLowerCase())]));
      keywords = keywords.slice(0, 30);
      const drawingPath = drawing?.drawing_file_path ? String(drawing.drawing_file_path) : null;
      const drawingName = drawing?.drawing_file_name ? String(drawing.drawing_file_name).slice(0, 180) : null;
      // Never trust drawing.drawing_redacted_paths from the body — see resolveRedactedPaths above.
      const rr = await resolveRedactedPaths(String(cust.id), String(user.id || ''), drawing);
      if ('err' in rr) return J(rr.err, rr.status);
      const drawingRedacted = rr.paths.length ? rr.paths.slice(0, 24) : null;
      // `tradesIn` arrives from the request body, so Set<unknown> is what TypeScript infers and
      // every downstream use of a trade - labelize(tr), KW[tr], category: tr - was an error.
      // Coercing here rather than casting at each use means a non-string trade is normalised once,
      // at the boundary, instead of being asserted away four times further down.
      const tradeStrings: string[] = (Array.isArray(tradesIn) ? tradesIn : []).map((t: unknown) => String(t ?? '').trim()).filter((s: string) => s.length > 0);
      const distinctTrades: string[] = Array.from(new Set<string>(tradeStrings)).slice(0, 6);
      const wantSplit = scope_type === 'multi' && distinctTrades.length > 1;
      const wantTurnkey = scope_type === 'turnkey';
      // THE ANONYMITY GATE (founder, 14 Sep 2026): "any info related to the client name / project
      // details contact info or anything that could let the supplier know who is the customer need to
      // be removed before sharing the drawings" — "the same applies for boq's". The BOQ is stored
      // ONLY after _shared/anonymise has removed this customer's own name, email, phone, project and
      // file name wherever they appear, plus plot / Makani / address / permit patterns, and a residual
      // scan found nothing. A BOQ that still identifies the customer is HELD: not stored on the RFQ,
      // recorded as a 'boq_held' run so it is visible, and never sent. It does not fail open.
      // THE DRAWING'S OPEN LINES ARE SETTLED AND RECORDED HERE (14 Sep 2026, _shared/boq_open_lines).
      // The sales engineer asked the customer to confirm our count; whatever is true at Send is the
      // outcome — confirmed, adjusted, not sure, or unanswered (the window closes when the customer
      // sends). Lines nobody confirmed go out as "estimated from drawing, supplier to verify
      // take-off", and the outcome is recorded on the inquiry, so nothing is silently assumed.
      if (boqObj && Array.isArray(boqObj.boq)) {
        const open = openLines(boqObj.boq);
        if (open.length) {
          const asked = briefObj?.boq_check && typeof briefObj.boq_check === 'object' ? briefObj.boq_check as BoqCheck : null;
          const outcome: BoqCheck = asked && asked.status !== 'asked' ? asked : { status: 'unanswered', asked_at: asked?.asked_at, answered_at: null, lines: open };
          boqObj = { ...boqObj, boq: settleLines(boqObj.boq, outcome) };
          spec.boq_check = { status: outcome.status, asked_at: outcome.asked_at || null, answered_at: outcome.answered_at || null, answer: outcome.answer || null, adjustments: outcome.adjustments || {}, lines: open, recorded_at: new Date().toISOString(), recorded_by: 'sales_engineer' };
        }
      }
      if (boqObj) {
        let projName = '';
        { const want = String(body.project_id || briefObj?.project_id || '').trim();
          if (want) { const { data: pj } = await admin.from('projects').select('name').eq('id', want).eq('customer_id', cust.id).maybeSingle(); projName = pj?.name ? String(pj.name) : ''; } }
        const seeds = seedTerms({ name: cust.full_name || '', email: cust.email || email, phone: cust.phone || '', project: projName, extra: [drawingName || ''] });
        const gate = redactBoq(boqObj, seeds);
        if (gate.held) {
          try { await admin.from('drawing_redaction_runs').insert({ customer_id: cust.id, owner_email: email, source_path: drawingPath, output_paths: [], pages_in: 0, pages_out: 0, skipped: 0, status: 'boq_held', pages_verified: 0, verify_failed: 1, verify_detail: { reasons: gate.reasons.slice(0, 20) } }); } catch (_e) { /* the hold stands even if its record fails */ }
          boqObj = null;
        } else boqObj = gate.boq;
      }
      const drawCols = { drawing_file_path: drawingPath, drawing_file_name: drawingName, drawing_redacted_paths: drawingRedacted, boq: boqObj, boq_confidence: boqObj?.confidence || null };

      // ── §7: THREE THINGS THE ASSISTANT EXTRACTED AND THIS ROUTINE THREW AWAY ────────────────────
      // The intake contract emits brief.quantity and brief.timeline — measured true — and the
      // ready-brief card shows the timeline to the customer before they press Send. Then
      // create_inquiry merged ONLY brief.details into inquiries.spec, so both survived just for the
      // minority of categories whose checklist happens to define a canonical key for them
      // (quantity: 30 of 56, timeline: 3 of 56). Everywhere else the customer confirmed a number
      // and the supplier never saw it.
      //
      // quantity is merged into spec under the canonical key and NEVER overwrites an answer the
      // customer gave explicitly: a checklist answer is stated, brief.quantity is inferred, and an
      // inference must not overwrite a statement.
      const briefQty = briefObj?.quantity;
      if (briefQty != null && String(briefQty).trim() !== '' && !('quantity' in spec)) spec.quantity = briefQty;
      // The window as stated, plus a resolved date when one can be resolved. Suppliers quote
      // against the phrase; the portal sorts against the date. `required_by` stays null rather than
      // guessing — "as soon as possible" is a real answer and is not a date.
      const timelineTxt = briefObj?.timeline != null ? String(briefObj.timeline).slice(0, 120) : (reqStored?.required_by?.text ? String(reqStored.required_by.text).slice(0, 120) : null);
      const isoDay = /^\d{4}-\d{2}-\d{2}$/;
      const requiredBy = (() => {
        // The date the customer gave the sales engineer is the customer's own answer and wins.
        const asked = String(reqStored?.required_by?.date || '');
        if (isoDay.test(asked)) return asked;
        const t = String(briefObj?.required_by || '').trim();
        if (isoDay.test(t)) return t;
        // The duration is found ANYWHERE in the phrase, not only at its start. Real answers read
        // "Installation required within 8 weeks of order" — an anchored match resolves that to
        // null, which is a date silently lost rather than a date honestly absent.
        const m = /(\d{1,4})\s*(day|days|week|weeks|month|months)\b/i.exec(String(timelineTxt || ''));
        if (!m) return null;
        const n = Number(m[1]); if (!Number.isFinite(n) || n <= 0 || n > 3650) return null;
        const mult = /week/i.test(m[2]) ? 7 : /month/i.test(m[2]) ? 30 : 1;
        return new Date(Date.now() + n * mult * 86400e3).toISOString().slice(0, 10);
      })();
      // §6: the floor this scope sits on, when the brief or the caller names one.
      const floorTxt = (body.floor ?? briefObj?.floor) != null ? String(body.floor ?? briefObj?.floor).slice(0, 40) : null;
      // §3 assistant-infers-project: the project the RFQ belongs to. Verified as THIS customer's —
      // a project_id from the request body is caller-supplied and must never link an RFQ to
      // somebody else's project.
      let projectId: string | null = null;
      { const want = String(body.project_id || briefObj?.project_id || '').trim();
        if (want) { const { data: pj } = await admin.from('projects').select('id').eq('id', want).eq('customer_id', cust.id).maybeSingle(); projectId = pj ? String(pj.id) : null; } }
      // §7 rfq-certificates: the category's required certificates and approvals, COPIED onto the
      // RFQ at creation so the supplier quoting it and the customer reading it see the same list,
      // and so a later edit to the category cannot change what an RFQ was quoted against.
      const checklistFor = async (cat: string) => {
        if (!cat) return null;
        try {
          const { data: cs } = await admin.from('category_specs').select('compliance_checklist').eq('category', cat).maybeSingle();
          const cl = cs?.compliance_checklist;
          const list = Array.isArray(cl?.list) ? cl.list : (Array.isArray(cl) ? cl : null);
          return list && list.length ? { list, source: 'category_specs', category: cat, attached_at: new Date().toISOString() } : null;
        } catch (_e) { return null; }
      };
      // A repeated request is linked to the one it copies (founder_instruction 1028); read from the server-side intake only.
      const briefCols = { floor: floorTxt, delivery_window: timelineTxt, required_by: requiredBy, project_id: projectId, ...(briefObj?.repeat_of ? { repeat_of: String(briefObj.repeat_of) } : {}) };

      if (wantSplit) {
        // ALL OR NOTHING (_shared/inquiry_split.ts; review of #653). Parent and every child are saved
        // first; any failed child removes what was saved and the post fails naming the trades, so no
        // supplier is invited to a partial request and no parent lists a trade that never went out.
        // Suppliers are matched and notified only once every child exists.
        const childSummary = (tr: string) => ((summary ? summary + ' — ' : '') + labelize(tr) + ' works (part of a combined project)').slice(0, 500);
        const childKw = (tr: string) => [tr];
        const parentIdRef = { id: '' };
        const res = await splitInquiry(distinctTrades, {
          insertParent: async () => {
            const { data, error } = await admin.from('inquiries').insert({ customer_id: cust.id, lang: inquiryLang, category: 'combined', emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords, status: 'split', budget, scope_type: 'multi', trades: distinctTrades, brief_source: briefSource, ...drawCols, ...briefCols }).select('id').maybeSingle();
            return error || !data ? null : String(data.id);
          },
          insertChild: async (tr) => {
            const { data, error } = await admin.from('inquiries').insert({ customer_id: cust.id, lang: inquiryLang, parent_inquiry_id: parentIdRef.id, category: tr, emirate, role_needed: 'supplier', raw_input: raw, spec, summary: childSummary(tr), keywords: childKw(tr), status: 'sent', budget, scope_type: 'single', trades: [tr], brief_source: briefSource, ...drawCols, ...briefCols, compliance_checklist: await checklistFor(tr) }).select('id').maybeSingle();
            return error || !data ? null : String(data.id);
          },
          deleteInquiries: async (ids) => {
            // Children reference the parent, so they go first. Scoped to this customer's rows.
            const kids = ids.filter((i) => i !== parentIdRef.id);
            if (kids.length) { const { error } = await admin.from('inquiries').delete().in('id', kids).eq('customer_id', cust.id); if (error) return false; }
            const { error } = await admin.from('inquiries').delete().eq('id', parentIdRef.id).eq('customer_id', cust.id);
            return !error;
          },
          notifyChild: async (id, tr) => {
            const tlabel = labelize(tr);
            const extra = ' This is the ' + tlabel + ' portion of a larger project — please quote for the ' + tlabel + ' works only; other trades are handled separately.' + (boqObj ? (briefSource === 'boq' ? ' The customer’s own bill of quantities is attached.' : ' A redacted drawing is attached.') : '');
            // Each child is ONE trade and is routed like any single request: through the capability
            // matcher (sales_engineer.match), not keyword matching. Measured 14 Sep 2026: split children
            // went to match_suppliers_kw, which matched a registered aluminium supplier and no one for
            // the glass child, while the capability router knows glass as glazing.
            const { matches } = await matchAndNotify(id, { category: tr, emirate, summary: childSummary(tr), budget, extra: extra + supplierLine(reqStored) });
            return matches;
          },
          finding: async (detail) => {
            console.error('split compensation failed', JSON.stringify(detail));
            try { await admin.rpc('fn_emit', { p_event_type: 'it.finding', p_entity_type: 'inquiry', p_entity_id: String(detail.parent_id || ''), p_actor: 'sales_engineer', p_payload: detail }); } catch (_e) { /* logged above */ }
          },
        }, (id) => { parentIdRef.id = id; });
        if (!res.ok) {
          return J({ error: 'split_failed', code: 'split_failed', failed_trades: res.failed_trades, ...(res.cleanup_failed ? { cleanup_failed: true } : {}),
            message: 'Your request could not be sent to every trade (' + res.failed_trades.map(labelize).join(', ') + '). Nothing was sent — please try again.' }, 500);
        }
        if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
        // ONE ANSWER SHAPE (_shared/inquiry_posted.ts): inquiry_id is the parent, the stable id of
        // what the customer asked for; child_ids / quotable_ids are what suppliers quote on.
        return J({ ...postedSplit(res.parentId, res.children.map((c) => ({ ...c, label: labelize(c.trade) })), distinctTrades), concierge: await confirmRequest(res.parentId) });
      }

      if (wantTurnkey) {
        const tkKeywords = Array.from(new Set([...keywords, 'fitout', 'fit out', 'fit-out', 'turnkey', 'interior', 'renovation', 'decoration', ...distinctTrades])).slice(0, 40);
        const { data: inq, error: e1 } = await admin.from('inquiries').insert({ customer_id: cust.id, lang: inquiryLang, category: 'fitout', emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords: tkKeywords, status: 'sent', budget, scope_type: 'turnkey', trades: distinctTrades.length ? distinctTrades : (tradesIn.length ? tradesIn : null), brief_source: briefSource, ...drawCols, ...briefCols, compliance_checklist: await checklistFor('fitout') }).select('id').maybeSingle();
        if (e1) return J(...inquiryNotSaved(e1));
        if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
        const tradeList = distinctTrades.map(labelize).join(', ');
        const extra = (tradeList ? ' Combined turnkey scope covering: ' + tradeList + '.' : '') + (boqObj ? (briefSource === 'boq' ? ' The customer’s own bill of quantities is attached.' : ' A redacted drawing is attached.') : '');
        const { matches } = await matchAndNotify(String(inq!.id), { category: 'fitout', emirate, summary, budget, extra: extra + supplierLine(reqStored) });
        return J({ ...postedSingle(String(inq!.id), 'turnkey', matches), concierge: await confirmRequest(String(inq!.id)) });
      }

      const { data: inq, error: e1 } = await admin.from('inquiries').insert({ customer_id: cust.id, lang: inquiryLang, category, emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords, status: 'sent', budget, scope_type: 'single', trades: tradesIn.length ? tradesIn : null, brief_source: briefSource, ...drawCols, ...briefCols, compliance_checklist: await checklistFor(category) }).select('id').maybeSingle();
      if (e1) return J(...inquiryNotSaved(e1));
      if (intake) { try { await admin.from('inquiry_intake').update({ status: 'consumed' }).eq('id', intake.id); } catch (_e) { /* */ } }
      const extra = boqObj ? (briefSource === 'quotation' ? ' A scope (anonymized from the customer’s own quotation, prices removed) is attached.' : (briefSource === 'boq' ? ' The customer’s own bill of quantities is attached (quantities as the customer wrote them, prices removed).' : ' A drawing with a draft bill of quantities is attached.')) : '';
      const { matches, routing } = await matchAndNotify(String(inq!.id), { category, emirate, summary, budget, extra: extra + supplierLine(reqStored) });
      return J({ ...postedSingle(String(inq!.id), 'single', matches, routing), concierge: await confirmRequest(String(inq!.id)) });
    }

    // THE CUSTOMER'S FOLLOW-UP REACHES THE RFQ (website audit 14 Sep 2026, BROKEN). "Ask the
    // assistant about this request" posted to inquiry_intake, which ignores inquiry_id, so every
    // follow-up became an orphan intake draft and no supplier ever saw it. A follow-up is now an
    // addendum: stored on public.rfq_clarification as a born-answered note (the same table the
    // pre-reveal Q&A uses, so a supplier reads one list), scrubbed of contact details and the
    // customer's own name, and emailed to every matched supplier through the same queue the
    // original invitation used.
    // A REQUEST HELD FOR ITS SPECS IS COMPLETED BY ITS CUSTOMER (customer_support, 29 Sep 2026; founder ledger 1018).
    // missing_specs: one field per required spec the hold check (fn_rfq_required_check) finds missing, asked in the
    // intake's plain words in the customer's language. add_missing_specs: the answers go through the one door
    // (fn_inquiry_add_missing_specs), which writes them under the key the check reads, lets the row's trigger re-run
    // the check, notes them on the request and tells every matched supplier. A request that is now complete and had
    // reached no supplier is offered to the matcher here, exactly as at posting. The e-mail reply path uses the same
    // door (source email_reply). scripts/sql/a_held_request_takes_its_missing_specs_from_the_customer_and_is_released_when_complete.sql
    if (action === 'missing_specs' || action === 'add_missing_specs') {
      const iid = String(body.inquiry_id || '');
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,emirate,summary,budget,status').eq('id', iid).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ ok: false, error: 'not_your_inquiry' }, 403);
      if (action === 'missing_specs') {
        const { data, error } = await admin.rpc('fn_inquiry_missing_specs', { p_inquiry: iid, p_lang: documentLocale(body.lang, cust.locale) });
        if (error) return J({ ok: false, error: 'missing_specs_unavailable' }, 503);
        return J({ ok: true, ...(data as Record<string, unknown>) });
      }
      // The same scrub every supplier-facing text passes: the answers reach the matched suppliers.
      const answers: Record<string, string> = {}; const hits: string[] = [];
      const raw = (body.answers && typeof body.answers === 'object') ? body.answers as Record<string, unknown> : {};
      for (const [k, v] of Object.entries(raw).slice(0, 40)) {
        const clean = String(scrubIdentity(String(v ?? '').slice(0, 300), cust.full_name, hits) || '').trim();
        if (clean.replace(/\[removed\]/g, '').trim()) answers[String(k).slice(0, 80)] = clean;
      }
      // "Not sure" records no answer: it opens a handoff to the sales engineer for those specs (./spec_handoff.ts).
      const unsure = notSureKeys(body.not_sure);
      const hand = specHandoffArgs(iid, cust.id, unsure);
      let handoff: number | null = null;
      if (hand) {
        const { data: hid, error: herr } = await admin.rpc('fn_seat_handoff', hand);
        if (herr) return J({ ok: false, error: 'handoff_failed' }, 500);
        handoff = (hid as number) ?? null;
      }
      if (!Object.keys(answers).length && hand) return J({ ok: true, released: false, handoff, not_sure: unsure });
      const { data: res, error } = await admin.rpc('fn_inquiry_add_missing_specs', { p_inquiry: iid, p_customer: cust.id, p_answers: answers, p_source: 'customer_portal' });
      if (error) return J({ ok: false, error: 'save_failed' }, 500);
      const r = (res || {}) as Record<string, any>;
      if (!r.ok) return J({ ok: false, error: r.error || 'save_failed', missing: r.missing ?? null }, r.error === 'not_your_inquiry' ? 403 : r.error === 'inquiry_closed' ? 409 : 400);
      let matches: number | null = null;
      if (r.ready === true && r.reached_suppliers === false) {
        ({ matches } = await matchAndNotify(iid, { category: String(inq.category || ''), emirate: inq.emirate ?? null, summary: String(inq.summary || ''),
          budget: inq.budget ?? null, extra: ' The customer completed the details this trade needs.' }));
      }
      // An answer in Arabic script was saved as written and its supplier copy is held for its English
      // (fn_inquiry_add_missing_specs files it for the replay; _shared/supplier_english.ts finishEnglish sends it).
      const held = r.held_for_english === true ? { notice: HELD_NOTICE.ar, notice_en: HELD_NOTICE.en } : {};
      return J({ ...r, ...held, released: r.ready === true, matches, removed: hits.length, handoff });
    }

    if (action === 'rfq_note') {
      const iid = String(body.inquiry_id || '');
      const raw = String(body.text || '').trim().slice(0, 1500);
      if (!iid || raw.length < 2) return J({ error: 'text_required' }, 400);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,category,emirate,status').eq('id', iid).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'not_your_inquiry' }, 403);
      if (['cancelled', 'closed', 'completed'].includes(String(inq.status))) return J({ error: 'inquiry_closed' }, 409);
      const hourAgo = new Date(Date.now() - 3600e3).toISOString();
      const { count: recentNotes } = await admin.from('rfq_clarification').select('id', { count: 'exact', head: true }).eq('inquiry_id', iid).eq('kind', 'note').gte('asked_at', hourAgo);
      if ((recentNotes || 0) >= 10) return J({ error: 'too_many_notes' }, 429);
      const hits: string[] = [];
      const clean = String(scrubIdentity(raw, cust.full_name, hits) || '').trim();
      if (clean.replace(/\[removed\]/g, '').trim().length < 2) return J({ error: 'text_required' }, 400);
      // Every matched supplier reads this note, and suppliers read English only (_shared/supplier_english.ts):
      // Arabic is kept as written and the supplier copy is held until the model route writes its English.
      const nowIso = new Date().toISOString();
      if (hasArabic(clean)) {
        const { data: held, error: herr } = await admin.from('rfq_clarification').insert({ inquiry_id: iid, supplier_id: null, kind: 'note', answer: null,
          answer_as_written: clean, english_held_at: nowIso, answered_at: nowIso, source: 'rfq_note' }).select('id').single();
        if (herr || !held) return J({ error: 'save_failed' }, 500);
        try { await holdForEnglish(admin, Number(held.id), clean); } catch (_e) { return J({ error: 'save_failed' }, 500); }
        return J({ ok: true, id: held.id, text: clean, notified: 0, removed: hits.length, held_for_english: true, notice: HELD_NOTICE.ar, notice_en: HELD_NOTICE.en });
      }
      const { data: ins, error: nerr } = await admin.from('rfq_clarification').insert({ inquiry_id: iid, supplier_id: null, kind: 'note', answer: clean, answered_at: nowIso, source: 'rfq_note' }).select('id').single();
      if (nerr || !ins) return J({ error: 'save_failed' }, 500);
      const notified = await mailMatched(admin, iid, supplierMail('note', inq, null, clean));
      return J({ ok: true, id: ins.id, text: clean, notified, removed: hits.length });
    }

    if (action === 'my_inquiries') {
      // rfq_no is the human reference (spec §8, "RFQ #88291"). The primary key is a uuid, which is
      // not a number a customer can read out on the phone or quote in an email to a supplier.
      // §7 spec, §8 stage, §9 applied filters. THREE THINGS WERE COMPUTED AND NEVER SERVED:
      //   pipeline_stage/stage_changed_at — recorded on every inquiry, while the browser derived
      //     the stage from quotes.length and anyRevealed. A guess sitting on top of a fact.
      //   routing — the filters the matcher actually applied (job_type, primary_trade, reasoning).
      //     Spec §9 shows them back to the customer; they never left the database.
      //   floor / required_by / delivery_window — added 7 Aug for §6 and §7.
      const cols = 'id,category,emirate,summary,spec,status,created_at,budget,scope_type,brief_source,drawing_file_path,drawing_file_name,boq,boq_confidence,hired_supplier_id,outcome,parent_inquiry_id,trades,rfq_no,pipeline_stage,stage_changed_at,routing,floor,required_by,delivery_window,project_id,rfq_ready';
      // ONE READ AT A TIME WAS THE OVERVIEW'S CRITICAL PATH (15 Sep 2026). Measured with the e2e
      // harness's per-call timing on production (smoke run 34888342875 and a probe of 8 page loads):
      // the six dashboard calls already start together, and my_inquiries answers last (1.40-1.61 s
      // warm) because it made eleven database reads one after another. Each read below waits only for
      // what it needs, so they run in four waves: [cfg, requests, sales, reviews] -> children ->
      // [quotes, matches, open offers, refunds] -> [supplier rows, supplier performance].
      // The answer is unchanged; only the waiting is.
      const [cfg, { data: tops }, txRes, { data: revs }] = await Promise.all([
        getCfg(),
        admin.from('inquiries').select(cols).eq('customer_id', cust.id).is('parent_inquiry_id', null).order('created_at', { ascending: false }).limit(25),
        admin.from('transactions').select('id,quote_id,revealed_at,supplier_ack_at,refund_status,refund_deadline,total_charged').eq('customer_id', cust.id),
        admin.from('reviews').select('transaction_id').eq('customer_id', cust.id),
      ]);
      const topIds = (tops || []).map((i) => i.id);
      let kids: any[] = [];
      if (topIds.length) { const { data: ch } = await admin.from('inquiries').select(cols).in('parent_inquiry_id', topIds).order('created_at', { ascending: true }); kids = ch || []; }
      const kidsByParent: Record<string, any[]> = {};
      for (const k of kids) { (kidsByParent[String(k.parent_inquiry_id)] ||= []).push(k); }
      const ids = [...topIds, ...kids.map((k) => k.id)];
      const txs: any[] = ids.length ? (txRes.data || []) : [];
      if (ids.length && txRes.error) console.error('my_inquiries: transactions read failed —', txRes.error.message);
      const txIds = txs.map((t) => t.id);
      const [qsRes, msRes, sosRes, rfsRes] = await Promise.all([
        ids.length ? admin.from('quotes').select('id,inquiry_id,supplier_id,option_no,quote_amount,price_ex_vat,gross_amount,discount_amount,discount_label,vat_treatment,vat_amount,amount_as_stated,terms_spec,status,notes,lead_time,validity,payment_terms,warranty,scope,conditions,exclusions,source,created_at,expires_at').in('inquiry_id', ids).not('status', 'in', NOT_LIVE_QUOTE_IN).order('quote_amount', { ascending: true }) : null,
        ids.length ? admin.from('inquiry_matches').select('inquiry_id,supplier_id,similarity,match_reason').in('inquiry_id', ids) : null,
        ids.length ? admin.from('spec_alternative_offer').select('id,inquiry_id,line_no,item,attr,label_en,label_ar,requested,alternatives,state,reply_by').in('inquiry_id', ids).eq('customer_id', cust.id).eq('state', 'open').order('opened_at', { ascending: true }) : null,
        txIds.length ? admin.from('refunds').select('id,transaction_id,refund_decision_id').in('transaction_id', txIds) : null,
      ]);
      const allQuotes: Record<string, any>[] = qsRes?.data || [];
      // WHAT THE PORTAL MAY LIST IS WHAT THE COMPARISON MAY RANK (customer-portal audit CP-01 and
      // CP-15, 22 Sep 2026). This action filtered on status <> 'draft' alone, so two kinds of quote
      // reached the customer's screen that no other surface will act on:
      //   * a quote ON HOLD for missing details — quote_compare withholds it from the ranking and
      //     both tables (the founder's hold rule, 14 Sep 2026), yet it was listed here with a
      //     Reveal button, so the customer could pay 3% for the one quote we refuse to stand behind.
      //   * a quote from a SANCTIONED supplier — never shown to a customer (instruction 516). The
      //     ban lands after the quote was submitted, so the row survives the matcher.
      // Both are now excluded from the list and the held ones are COUNTED (`on_hold` per request),
      // because a quote that vanished with no explanation is its own defect. A quote the customer
      // has already paid to reveal is never withdrawn: that disclosure is theirs.
      const paidQuoteIds = new Set(txs.map((t) => String(t.quote_id)));
      // THE LAST THREE WAVES ARE ONE (coordinator ruling G5, 19 Oct 2026). The sanctions read, the
      // quote lines and the supplier rows each waited for the one before, though all three need only
      // the quote list. In Postgres each is under 4 ms (pg_stat_statements max); what they cost was
      // three edge-to-database round trips back to back. The supplier rows are now read for every
      // quoting supplier — a superset of the listed ones, used only through supMeta lookups of quotes
      // that survive the filters, so the answer is unchanged.
      const allSupIds = [...new Set(allQuotes.map((q) => q.supplier_id).filter((x) => x != null))] as (string | number)[];
      const [sanctionedSup, itemsOf, supRows] = await Promise.all([
        sanctionedLeads(admin, allSupIds),
        itemsByQuote(admin, allQuotes.map((q) => String(q.id))),
        allSupIds.length ? Promise.all([admin.from('leads').select('id,company_name,app_rating,app_reviews,emirate,founded_year,rv_response_rate,rv_reveals,verified,licence_gate_reason,license_doc_path,license_expiry,company_profile_doc_path').in('id', allSupIds), admin.from('supplier_perf').select('supplier_id,won,win_rate').in('supplier_id', allSupIds)]) : null,
      ]);
      const inqById = new Map<string, any>([...(tops || []), ...kids].map((i: any) => [String(i.id), i]));
      const heldIds = new Set<string>();
      for (const [iid, row] of inqById) {
        const mine = allQuotes.filter((q) => String(q.inquiry_id) === iid && !paidQuoteIds.has(String(q.id)));
        if (!mine.length) continue;
        for (const id of heldQuoteIds(mine.map((q) => ({ quote: q, items: itemsOf[String(q.id)] || [] })), row.category ?? null, row.spec)) heldIds.add(id);
      }
      const onHoldByInq: Record<string, number> = {};
      for (const q of allQuotes) if (heldIds.has(String(q.id))) onHoldByInq[String(q.inquiry_id)] = (onHoldByInq[String(q.inquiry_id)] || 0) + 1;
      const quotes: Record<string, any>[] = allQuotes.filter((q) => !heldIds.has(String(q.id)) && !sanctionedSup.has(String(q.supplier_id)));
      // How many suppliers the request actually reached. Without this the portal cannot tell
      // "waiting for quotes" apart from "this reached nobody", and shows hope either way.
      const matchedBy: Record<string, number> = {};
      // WHY a given supplier was contacted. inquiry_matches.match_reason is the ONLY place the
      // system records it; this read kept a COUNT and threw the text away, so the only surface
      // rendering a reason was OsxShell — /os, staff-only. It is now served, keyed by supplier, and
      // REVEAL-GATED in the row mapper below.
      //
      // The gate is not optional. route_inquiry builds its candidate list as `#<id> — <Company
      // Name>` (route_inquiry/index.ts:305) and asks the model for a free-text reason per
      // candidate, so a reason may name the supplier outright. Emitting it pre-reveal would hand
      // over the identity the reveal fee exists to sell.
      //
      // THE MATCH PERCENTAGE IS NOW SERVED. It used not to be, and the reason was correct at the
      // time: both writer sites passed the literal null, so every row held null in every
      // environment and a "% match" here would have been invented rather than surfaced. Both
      // writers now store the score their matcher actually computed, normalised to 0..1 (see
      // matchAndNotify above), so there is a real number to serve.
      //
      // NOT REVEAL-GATED, unlike match_reason. A percentage names nobody — it is a number about the
      // fit between a brief and an anonymous quote — so it costs the reveal fee nothing. The reason
      // text is gated because route_inquiry builds its candidate list as `#<id> — <Company Name>`
      // (route_inquiry/index.ts) and asks the model for free-text per candidate, so a reason may
      // name the supplier outright and emitting it pre-reveal would hand over the identity the
      // reveal fee exists to sell.
      //
      // NULL MEANS NOT SCORED AND MUST RENDER AS ABSENT. A match written on the legacy
      // AI-adjudicator path carries no number at all; serving 0 there would tell the customer this
      // supplier is a 0% fit, which is a different and false claim. null travels as null.
      const reasonBySup: Record<string, string> = {};
      const pctBySup: Record<string, number> = {};
      const bestPct: Record<string, number> = {};
      try { const ms = msRes?.data; for (const m of (ms || [])) { matchedBy[String(m.inquiry_id)] = (matchedBy[String(m.inquiry_id)] || 0) + 1; if (m.match_reason) reasonBySup[String(m.inquiry_id) + ':' + String(m.supplier_id)] = String(m.match_reason); const sim = m.similarity == null ? null : Number(m.similarity); if (sim != null && Number.isFinite(sim)) { const pct = Math.round(sim * 100); pctBySup[String(m.inquiry_id) + ':' + String(m.supplier_id)] = pct; if (pct > (bestPct[String(m.inquiry_id)] ?? -1)) bestPct[String(m.inquiry_id)] = pct; } } } catch (_e) { /* */ }
      const supIds = [...new Set(quotes.map((q) => q.supplier_id))];
      const supMeta: Record<string, any> = {};
      if (supIds.length && supRows) { const [{ data: ls }, { data: perf }] = supRows; const perfById: Record<string, any> = {}; for (const p of (perf||[])) perfById[String(p.supplier_id)] = p; const _yr = new Date().getFullYear(); for (const l of ls || []) supMeta[String(l.id)] = { r: ratingOf(l), name: l.company_name || null, emirate: l.emirate, verified: !!l.verified, vb: verifiedBadges(l), years_active: l.founded_year ? Math.max(0, _yr - Number(l.founded_year)) : null, jobs_won: (perfById[String(l.id)]||{}).won ?? 0, win_rate: (perfById[String(l.id)]||{}).win_rate ?? null, rr: Number(l.rv_reveals) > 0 && l.rv_response_rate != null ? Number(l.rv_response_rate) : null }; }
      const revealedQ = new Set<string>(); const txByQuote: Record<string, string> = {}; const revealAtByQuote: Record<string, string | null> = {};
      // 21 Sep 2026 (customer audit, finding 17): the portal said "AED 778 paid" for a card charged
      // AED 816.37 — it printed the 3% fee, not transactions.total_charged (fee + card processing).
      const chargedByQuote: Record<string, number | null> = {};
      // public.transactions HAS NO created_at COLUMN - in staging or in production. Selecting it
      // made PostgREST answer 400, so `txs` came back null, `for (const t of txs || [])` iterated
      // nothing, and revealedQ stayed empty: NO QUOTE WAS EVER MARKED REVEALED. The customer paid
      // the reveal fee, `reveal` wrote the transactions row, and the portal went on showing
      // "Supplier A" with banded ratings and supplier_ref null, forever. Found 5 Aug 2026 by the
      // first fixture that ever created a transactions row - the journey never reveals, so a green
      // 37/37 said nothing about it. revealed_at is the column that exists; there is no fallback.
      // The Reveal Guarantee clock on the customer's own job needs the facts the refund ladder runs
      // on — when they paid, whether the supplier acknowledged, and any refund already in motion.
      // All four are columns on the sale; nothing is inferred.
      const guaranteeByQuote: Record<string, Record<string, unknown>> = {};
      if (ids.length) { for (const t of txs) { revealedQ.add(String(t.quote_id)); txByQuote[String(t.quote_id)] = String(t.id); revealAtByQuote[String(t.quote_id)] = t.revealed_at || null; chargedByQuote[String(t.quote_id)] = t.total_charged == null ? null : Number(t.total_charged); guaranteeByQuote[String(t.quote_id)] = { revealed_at: t.revealed_at || null, supplier_ack_at: t.supplier_ack_at || null, refund_status: t.refund_status || null, refund_deadline: t.refund_deadline || null }; }
        // D4 (14 Sep 2026): the refund case and the chief executive's decision behind it, so the
        // customer can quote both. refunds.refund_decision_id references ceo_approval(decision_id);
        // it is null until the decision exists, and the portal says "awaiting" rather than inventing one.
        if (txIds.length) { const rfs = rfsRes?.data; const qByTx: Record<string, string> = {}; for (const [qk, tk] of Object.entries(txByQuote)) qByTx[tk] = qk; for (const rf of rfs || []) { const g = guaranteeByQuote[qByTx[String(rf.transaction_id)]]; if (g) { g.refund_ref = refundRef(rf.id); g.decision_ref = rf.refund_decision_id ? 'QD-D-' + rf.refund_decision_id : null; } } } }
      const ratedTx = new Set((revs || []).map((r) => String(r.transaction_id)));
      // NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321): the open question, with its
      // alternatives as values and supplier COUNTS only (the table cannot hold anything else).
      const offersBy: Record<string, unknown[]> = {};
      if (ids.length) { const sos = sosRes?.data; for (const s of sos || []) { const { inquiry_id, ...rest } = s as Record<string, unknown>; (offersBy[String(inquiry_id)] ||= []).push(rest); } }
      const now = new Date();
      // Pre-reveal quote rows carry BANDS only (see ratingBand/reviewCountBand/yearsBand above);
      // rating_source, emirate and win_rate are set to undefined so JSON.stringify omits the keys
      // outright rather than shipping a null the client could still reason about. Revealed quotes
      // — a transactions row exists for that quote_id — keep the exact values, unchanged.
      // §9 THE APPLIED FILTERS, WITHOUT THE FREE TEXT. inquiries.routing records what the matcher
      // did: job_type, primary_trade, emirate and how many suppliers it evaluated. It ALSO records
      // `reasoning`, which route_inquiry generates against a candidate list built as
      // `#<id> — <Company Name>` and can therefore name a supplier outright — the same hazard that
      // makes match_reason reveal-gated. The filters are shown back; the free text is not, and this
      // projection is why: serving routing whole would leak the identity the reveal fee sells.
      const appliedFilters = (r: any) => {
        if (!r || typeof r !== 'object') return null;
        const n = Array.isArray(r.evaluated) ? r.evaluated.length : (Number.isFinite(Number(r.evaluated)) ? Number(r.evaluated) : null);
        const f = { job_type: r.job_type ?? null, primary_trade: r.primary_trade ?? null, emirate: r.emirate ?? null, evaluated: n };
        return (f.job_type || f.primary_trade || f.emirate || f.evaluated != null) ? f : null;
      };
      const mapRow = async (i: any) => ({ id: i.id, rfq_no: i.rfq_no ?? null, category: i.category, emirate: i.emirate, summary: i.summary, spec: i.spec, status: i.status, created_at: i.created_at,
        // §8: the stage the LIFECYCLE recorded, not one the browser guessed from quotes.length.
        pipeline_stage: i.pipeline_stage ?? null, stage_changed_at: i.stage_changed_at ?? null,
        applied_filters: appliedFilters(i.routing),
        // §6/§7: the floor this RFQ is scoped to, and the delivery window the assistant extracted.
        floor: i.floor ?? null, required_by: i.required_by ?? null, delivery_window: i.delivery_window ?? null,
        project_id: i.project_id ?? null, budget: i.budget || null, scope_type: i.scope_type || null, brief_source: i.brief_source || null, boq: i.boq || null, boq_confidence: i.boq_confidence || null, drawing_file_name: i.drawing_file_name || null, hired_supplier_id: i.hired_supplier_id ?? null, outcome: i.outcome ?? null, trades: i.trades || null, matched_suppliers: matchedBy[String(i.id)] || 0, best_match_pct: bestPct[String(i.id)] ?? null,
        // ONE EDIT WINDOW, ONE NUMBER (customer-portal audit CP-06, 22 Sep 2026). This said 24 hours
        // while fn_edit_inquiry refuses after 1 hour and the minutes counter beside it counted down
        // from 60, so the portal offered an Edit button for 23 hours that the server always refused.
        editable: (i.status === 'sent') && ((Date.now() - new Date(i.created_at).getTime()) < EDIT_WINDOW_MS), edit_minutes_left: (i.status === 'sent') ? Math.max(0, Math.round((EDIT_WINDOW_MS - (Date.now() - new Date(i.created_at).getTime()))/60000)) : 0,
        // How many quotes are on hold for missing details and are therefore not in the list below.
        on_hold: onHoldByInq[String(i.id)] || 0, drawing_file_url: await signedDrawing(i.drawing_file_path), spec_offers: offersBy[String(i.id)] || [], quotes: quotes.filter((q) => q.inquiry_id === i.id).map((q, idx, arr) => { const lab = labelQuotes(arr.map((x: any) => ({ id: String(x.id), supplier_id: x.supplier_id, option_no: x.option_no }))).get(String(q.id)); const m = supMeta[String(q.supplier_id)] || {}; const r = m.r || {}; const revealed = revealedQ.has(String(q.id)); return { id: q.id, supplier_ref: revealed ? q.supplier_id : null, label: lab ? lab.en : 'Supplier ' + supplierLabel(idx), label_ar: lab ? lab.ar : null, option_no: q.option_no ?? 1, price: q.quote_amount, reveal_fee: revealFee(Number(feeBaseOf(q) ?? 0), cfg), price_stated: priceStated(q, 'en'), price_stated_ar: priceStated(q, 'ar'), gross_amount: q.gross_amount ?? null, discount_amount: q.discount_amount ?? null, discount_label: q.discount_label ?? null, vat_treatment: q.vat_treatment ?? null, vat_stated: vatStated(q, 'en'), vat_stated_ar: vatStated(q, 'ar'), fee_basis: feeBasisLine(feeBaseOf(q), cfg ? cfg.standard_reveal_rate : null, 'en'), fee_basis_ar: feeBasisLine(feeBaseOf(q), cfg ? cfg.standard_reveal_rate : null, 'ar'), notes: q.notes, lead_time: q.lead_time, validity: q.validity, expires_at: q.expires_at ?? null, expired: q.expires_at ? (new Date(q.expires_at) < now) : false, payment_terms: q.payment_terms, warranty: q.warranty, scope: q.scope, conditions: q.conditions, exclusions: q.exclusions, source: q.source || 'form', status: q.status, revealed, revealed_at: revealAtByQuote[String(q.id)] || null, supplier_name: revealed ? (m.name ?? null) : undefined, total_charged: revealed ? (chargedByQuote[String(q.id)] ?? null) : undefined, guarantee: revealed ? (guaranteeByQuote[String(q.id)] || null) : undefined, rated: ratedTx.has(String(txByQuote[String(q.id)] || '')), rating: revealed ? (r.value ?? null) : ratingBand(r.value), rating_count: revealed ? (r.count ?? 0) : reviewCountBand(r.count), rating_source: revealed ? (r.source || null) : undefined, match_reason: revealed ? (reasonBySup[String(i.id) + ':' + String(q.supplier_id)] ?? null) : undefined, match_pct: pctBySup[String(i.id) + ':' + String(q.supplier_id)] ?? null, emirate: revealed ? (m.emirate ?? null) : undefined, verified: m.verified ?? false, years_active: revealed ? (m.years_active ?? null) : yearsBand(m.years_active), jobs_won: m.jobs_won ?? 0, win_rate: revealed ? (m.win_rate ?? null) : undefined,
          // W9 badges: only measured facts, null when absent. Pre-reveal the response rate is floored
          // to a 10% band and the rating stays out (the banded rating above already shows it), so a
          // badge can never be an exact fingerprint of one company.
          badges: { licence_verified: m.vb ? m.vb.licence_verified : false, documents_complete: m.vb ? m.vb.documents_complete : false, response_rate: m.rr == null ? null : (revealed ? m.rr : Math.floor((m.rr <= 1 ? m.rr : m.rr / 100) * 10) / 10), jobs_completed: Number(m.jobs_won) > 0 ? Number(m.jobs_won) : null, rating: revealed && typeof r.value === 'number' ? r.value : null } }; }) });
      // EACH mapRow AWAITS A STORAGE ROUND TRIP (signedDrawing) THAT THE OLD LOOP SERIALISED. Up to
      // 25 top-level rows plus every child were signed one at a time — an N+1 sequential-await chain
      // on the Overview's critical path (e2e run 6, 14 Sep 2026: 6.5s vs run 5's 1.6-1.8s, growing
      // with the number of ZZ DEMO rows that carry a drawing). None of these rows' signed URLs depend
      // on each other, so they run together; wall time is now the slowest ONE, not the sum.
      const out = await Promise.all((tops || []).map(async (i) => {
        // mapRow returns an object literal, so its inferred type has no is_combined / child_count /
        // children. The combined-project decoration below is genuinely dynamic - only split parents
        // get it - so the row is typed as an open record rather than the literal's shape.
        const row: Record<string, any> = await mapRow(i);
        const ch = kidsByParent[String(i.id)];
        if (ch && ch.length) { row.is_combined = true; row.child_count = ch.length; row.children = await Promise.all(ch.map((c: any) => mapRow(c))); }
        return row;
      }));
      // `locale` added 5 Aug 2026. customers.locale was stored and, from the portal's point of
      // view, never served: the brief called it "stored and never served", which measurement shows
      // is not quite right - `me` returns the whole customer row via select('*'), locale included.
      // But THE PORTAL NEVER CALLS `me`. It calls `kyc state` and this action, so the field was on
      // the wire only where nothing was listening, and CustomerPortal fell back to
      // localStorage['qd-lang'] and the NEXT_LOCALE cookie. A customer who set Arabic on one device
      // got English on the next, and the Arabic journey exercised a path the portal could not reach.
      // promo is always false: there is no promotional reveal rate (founder, 6 Sep 2026); the key stays so no reader breaks.
      // The ladder's numbers, from the same row the refund sweep and the supplier email read, so the
      // portal's timeline cannot drift from what is actually enforced (5 / 3 / 7-14 on 14 Sep 2026).
      const pc = (cfg || {}) as unknown as Record<string, number | null | undefined>;
      const guarantee_terms = { window_days: pc.refund_window_working_days ?? null, chase_after_days: pc.chase_after_working_days ?? null, bank_min_days: pc.bank_settlement_working_days_min ?? null, bank_max_days: pc.bank_settlement_working_days_max ?? null };
      return J({ inquiries: out, locale: cust.locale || null, promo: false, guarantee_terms });
    }

    // NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321): the customer answers in the portal.
    // The routine records it (owner check, open state, which option, when, channel 'portal', inquiry
    // closed on "no"); customer_support then confirms or apologises in the registered language.
    if (action === 'spec_offer_reply') {
      const offerId = Number(body.offer_id); const choice = String(body.choice || '').trim();
      if (!Number.isFinite(offerId) || offerId <= 0 || !choice) return J({ error: 'bad_request' }, 400);
      const { data: res, error: aErr } = await admin.rpc('fn_spec_offer_answer', { p_offer: offerId, p_customer: cust.id, p_choice: choice, p_channel: 'portal' });
      if (aErr) { console.error('spec_offer_reply:', aErr.message); return J({ error: 'spec_offer_failed' }, 500); }
      if (!res?.ok) return J({ error: res?.error || 'spec_offer_failed', state: res?.state ?? null }, res?.error === 'not_your_offer' ? 403 : res?.error === 'not_found' ? 404 : 409);
      try {
        const { data: o } = await admin.from('spec_alternative_offer').select('id,inquiry_id,item,label_en,label_ar,requested,alternatives,accepted_value').eq('id', offerId).maybeSingle();
        const { data: c } = await admin.from('customers').select('email,locale').eq('id', cust.id).maybeSingle();
        const { data: inqRow } = await admin.from('inquiries').select('rfq_no').eq('id', String(res.inquiry_id)).maybeSingle();
        const lang = asLocale(c?.locale ?? cust.locale);
        const arTexts = res.state === 'accepted' && o ? await arabicTextsFor(defaultDeps(admin, 'customer_api'), lang, offerTexts(o as OfferForText), { fileOnly: true }) : undefined;
        const msg = res.state === 'accepted' ? acceptedMessage(o as OfferForText, lang, { rfqNo: inqRow?.rfq_no, arTexts }) : apologyMessage(o as OfferForText, lang, 'declined', { rfqNo: inqRow?.rfq_no });
        const kind = res.state === 'accepted' ? 'accepted' : 'apology_declined';
        // customer_support asks and answers the alternatives question (finding SP-F-08, 22 Sep 2026;
        // the same change in sales_engineer/index.ts carries the reasoning). The `type` is unchanged.
        const base = { type: 'spec_offer_' + kind, kind: 'customer_support_spec_offer_' + kind, to_role: 'customer', inquiry_id: String(res.inquiry_id), subject: msg.subject, body: msg.body, status: 'queued', lang, requested_by: 'customer_support', sender: 'customer_support' };
        const rows: Record<string, unknown>[] = [];
        if (c?.email) rows.push({ ...base, channel: 'email', to_email: c.email, dedupe_key: `spec_offer:${offerId}:${kind}:email` });
        // WhatsApp consent is the confirmed WhatsApp number, nothing else (#322): the row names the customer by
        // email and the a03 trigger addresses it to their confirmed number, or records why it was not sent.
        if (c?.email) rows.push({ ...base, channel: 'whatsapp', to_email: c.email, dedupe_key: `spec_offer:${offerId}:${kind}:whatsapp` });
        // An Arabic confirmation with a line not yet reasoned is PARKED with its placeholders and sent by
        // fn_arabic_outbound_flush the moment the Arabic exists — never sent with English in it.
        if (msg.untranslated?.length && rows.length) {
          const { error: pErr } = await admin.rpc('fn_arabic_outbound_park', { p_texts: msg.untranslated, p_rows: rows });
          // A failed park is an error, never a send: the message has placeholders in it.
          if (pErr) throw new Error('the Arabic confirmation could not be parked: ' + pErr.message);
          rows.length = 0;
        }
        const { data: sent } = rows.length ? await requestDelivery(admin, rows) : { data: [] };
        await admin.rpc('fn_spec_offer_mark', { p_offer: offerId, p_action: 'answered', p_notification_ids: (sent || []).map((d) => d.notification_id).filter((x) => typeof x === 'number') });
      } catch (e) {
        const why = String((e as Error)?.message || e);
        console.error('spec_offer_reply: confirmation not queued —', why);
        // The answer is recorded; the confirmation is not. It is never silent: customer_support's CEO report names it.
        try {
          await admin.rpc('fn_support_report_to_ceo', { p_idempotency_key: 'spec_offer_confirmation_failed:' + offerId, p_severity: 'routine',
            p_subject: 'A customer\'s choice was recorded but its confirmation could not be queued', p_evidence: { offer_id: offerId, error: why.slice(0, 500) },
            p_attempted: ['recorded the answer', 'queued or parked the confirmation'], p_requested: 'Send the confirmation by hand or re-queue it.' });
        } catch (_e) { /* the console line above still stands */ }
      }
      return J({ ok: true, state: res.state, inquiry_closed: !!res.inquiry_closed });
    }

    if (action === 'complete_inquiry') {
      const qid = String(body.quote_id || '');
      const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id').eq('id', qid).maybeSingle(); if (!q) return J({ error: 'Quote not found' }, 404);
      const { data: inq } = await admin.from('inquiries').select('id,customer_id,summary,status,hired_supplier_id').eq('id', q.inquiry_id).maybeSingle();
      if (!inq || inq.customer_id !== cust.id) return J({ error: 'Not your inquiry' }, 403);
      const { data: tx } = await admin.from('transactions').select('id').eq('quote_id', qid).eq('customer_id', cust.id).maybeSingle();
      if (!tx) return J({ error: 'Reveal this supplier first.' }, 403);
      // HIRE IS IDEMPOTENT (customer-portal audit CP-11, 22 Sep 2026). Every press of "Hire" wrote
      // the same row again AND re-ran notifyLosers, so the losing suppliers were emailed "the
      // customer chose another supplier" once per press. The second press of the same button on
      // the same supplier now answers ok and sends nothing; a DIFFERENT supplier on a job already
      // awarded is refused rather than silently re-awarded.
      if (String(inq.status || '') === 'completed' && inq.hired_supplier_id != null) {
        const same = Number(inq.hired_supplier_id) === Number(q.supplier_id);
        return same
          ? J({ ok: true, already_completed: true })
          : J({ ok: false, error: 'already_hired', code: 'already_hired', message: 'You have already hired a supplier for this request.', message_ar: 'لقد اخترت مورّدًا لهذا الطلب بالفعل.' }, 409);
      }
      // The award itself is the lock: only the press that finds hired_supplier_id still null wins
      // it, so two presses that arrive together still send one round of notices.
      const { data: won } = await admin.from('inquiries').update({ status: 'completed', hired_supplier_id: q.supplier_id, completed_at: new Date().toISOString(), outcome: 'hired' }).eq('id', inq.id).is('hired_supplier_id', null).select('id');
      if (!won || !won.length) return J({ ok: true, already_completed: true });
      await notifyLosers(String(inq.id), inq.summary ?? null, Number(q.supplier_id));
      return J({ ok: true });
    }

    if (action === 'edit_inquiry') {
      const iid = String(body.inquiry_id || '');
      const patch = (body.patch && typeof body.patch === 'object') ? body.patch : body;
      // WHAT A CUSTOMER MAY EDIT IN PLACE (customer-portal audit CP-04, 22 Sep 2026). This forwarded
      // spec, boq, trades, keywords and raw_input straight into fn_edit_inquiry, which writes them
      // to the row with no anonymity scrub and no requirements check — the two gates create_inquiry
      // puts every one of those fields through (scrubDeep / redactBoq for the customer's identity,
      // intake_requirements for the answers suppliers quote against). An edit could therefore put
      // the customer's own name into a BOQ line the suppliers read, or empty the requirements that
      // the hold rule measures quotes against.
      //   Only the three fields that carry no structure are editable here: the summary (scrubbed
      //   with the same scrubber every supplier-facing text goes through), the budget and the
      //   emirate. A change to the scope, the BOQ or the trades is a new request — the portal's own
      //   Edit form offers nothing else.
      const clean: Record<string, unknown> = {};
      for (const k of ['budget', 'emirate']) if (patch[k] !== undefined) clean[k] = patch[k];
      if (patch.summary !== undefined) {
        const bn = await buyerNameOf(String(iid));
        // A name we could not read is a name we cannot scrub: the edit is refused rather than
        // written unscrubbed (the rule buyerName/scrubIdentity already enforce on every send).
        if (!bn.resolved) return J({ ok: false, error: 'summary_not_editable', code: 'summary_not_editable', message: 'We could not check this text for your own details just now. Please try again in a moment.', message_ar: 'تعذّر التحقق من خلو النص من بياناتك الآن. يُرجى المحاولة بعد لحظات.' }, 503);
        clean.summary = scrubIdentity(String(patch.summary).slice(0, 500), bn.name, []) || '';
      }
      if (!Object.keys(clean).length) return J({ ok: false, error: 'nothing_editable', code: 'nothing_editable', message: 'Only the description, the budget and the emirate can be changed. For anything else, please post a new request.', message_ar: 'يمكن تعديل الوصف والميزانية والإمارة فقط. لأي تغيير آخر يُرجى إنشاء طلب جديد.' }, 400);
      const { data: r } = await admin.rpc('fn_edit_inquiry', { p_inquiry: iid, p_customer: cust.id, p_patch: clean });
      if (r?.error) return J({ error: r.message || r.error, editable_until: r.editable_until }, r.error === 'not_your_inquiry' ? 403 : 400);
      return J(r || { ok: true });
    }

    if (action === 'cancel_inquiry') {
      const iid = String(body.inquiry_id || '');
      const reason = body.reason ? String(body.reason).slice(0, 300) : null;
      const { data: r } = await admin.rpc('fn_cancel_inquiry', { p_inquiry: iid, p_customer: cust.id, p_reason: reason });
      if (r?.error) return J({ error: r.message || r.error }, r.error === 'not_your_inquiry' ? 403 : 400);
      return J(r || { ok: true });
    }
}
