// customer_api — opening a request: concierge, repeat_inquiry, create_inquiry.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move);
// split again from actions/inquiries.ts the same day (sales_engineer) into this and inquiry_lifecycle.ts.
//
// KEPT AS IT WAS: repeat_inquiry reassigns `body` and `action` and FALLS THROUGH into create_inquiry, the one posting
// door. That is why both are `let` here and why the two blocks stay adjacent and in this order.
import { seedTerms, redactBoq } from '../../_shared/anonymise.ts';
import { postedSingle, postedSplit } from '../../_shared/inquiry_posted.ts';
import { splitInquiry } from '../../_shared/inquiry_split.ts';
import { repeatCheck, repeatPlan } from '../repeat.ts';
import { openLines, settleLines, type BoqCheck } from '../../_shared/boq_open_lines.ts';
import { documentLocale } from '../../_shared/registered_locale.ts';
import { accountMissing } from '../../_shared/account_rule.ts';
import { currentCustomerTermsVersion, needsReacceptance, REACCEPT_MESSAGE } from '../../_shared/customer_terms.ts';
import { applyEdits, validateStored, supplierLine } from '../../_shared/intake_requirements.ts';
import { type ActionCtx, INQUIRY_LIMIT_PER_HOUR, J, SERVICE, SUPABASE_URL, admin, getSecret } from '../context.ts';
import { inquiryNotSaved, labelize } from '../lib/inquiry_rules.ts';
import { resolveRedactedPaths } from '../lib/drawings.ts';
import { ownDrawingPath } from '../drawing_path.ts';
import { matchAndNotify } from '../lib/matching.ts';
import { claimIntake, releaseIntake } from '../lib/intake_claim.ts';
import { keysOfTrade, serviceKeyCols, stateKeysForIntake } from '../lib/state_service_keys.ts';

export async function inquiryCreateActions(c: ActionCtx): Promise<Response | undefined> {
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
      // THE SEPARATE-QUOTES ANSWER IS GIVEN ONCE (lib/separate_quotes.ts, customer-journey audit 10 Nov 2026): a second yes
      // to the same request would invite every specialist again with a second per-trade copy. The portal says it is done.
      if (body.edits && typeof body.edits === 'object' && body.edits.sourcing === 'multi' && body.preview !== true) {
        const { count: sep } = await admin.from('inquiries').select('id', { count: 'exact', head: true }).eq('customer_id', cust.id).eq('repeat_of', o.id).eq('scope_type', 'multi').is('parent_inquiry_id', null);
        if ((sep || 0) > 0) return J({ error: 'already_separate', code: 'already_separate', message: 'This request already went out as separate quotes per trade.' }, 409);
      }
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
      if (body.intake_id) { const { data: it } = await admin.from('inquiry_intake').select('*').eq('id', String(body.intake_id)).maybeSingle(); if (it && it.email === email && it.status === 'ready') intake = it;
        // This intake already posted its request (lib/intake_claim.ts): Send again after a timeout is told so, not asked the questions again.
        else if (it && it.email === email && it.status === 'consumed') return J({ error: 'already_posted', code: 'already_posted', message: 'This request was already sent. Check your requests list.' }, 409); }
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
      // Only one of this customer's own uploads (../drawing_path.ts, M1 of the 10 Nov 2026 security audit).
      const own = ownDrawingPath(String(cust.id), drawing?.drawing_file_path);
      if (!own.ok) return J({ error: 'drawing_not_yours', code: 'drawing_not_yours', message: 'That drawing could not be attached. Please upload it again.', message_ar: 'تعذّر إرفاق هذا المخطط. يُرجى رفعه مرة أخرى.' }, 403);
      const drawingPath = own.path;
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
      // THE SERVICES AND TRADES THE CONVERSATION SETTLED (10 Nov 2026, sales_engineer; founder ledger 1572/1586). The request
      // chat records the services the customer's chosen solution names and the taxonomy trades it placed the job in
      // (inquiry_intake: brief.service_keys, brief.trade_codes, read from the server-side intake only, each re-checked for
      // shape here). The keys are stored on the inquiry, so matching gates on them (sales_engineer operator: stored, not
      // re-derived; a supplier holding none of the named trades' services still passes at trade level). The codes join the
      // single-trade request's trades (fn_taxonomy_trades_for passes a taxonomy code through), so a bus rental or a packaging
      // order reaches its own trade instead of 'general'; a split request keeps its slugs.
      const intakeServiceKeys: string[] = Array.isArray(briefObj?.service_keys) ? [...new Set((briefObj!.service_keys as unknown[]).map((k) => String(k)).filter((k) => /^[a-z0-9_]+\.[a-z0-9_]+$/.test(k)))].slice(0, 12) : [];
      const intakeTradeCodes: string[] = Array.isArray(briefObj?.trade_codes) ? [...new Set((briefObj!.trade_codes as unknown[]).map((k) => String(k)).filter((k) => /^[a-z0-9_]+$/.test(k)))].slice(0, 4) : [];
      // A repeated request is linked to the one it copies (founder_instruction 1028); read from the server-side intake only.
      const briefCols = { floor: floorTxt, delivery_window: timelineTxt, required_by: requiredBy, project_id: projectId, ...(briefObj?.repeat_of ? { repeat_of: String(briefObj.repeat_of) } : {}) };

      // THE SERVICES THE CUSTOMER CHOSE (10 Nov 2026, ledger 1573/1579): exact keys from the conversation state, when it holds
      // them (lib/state_service_keys.ts); otherwise none, and dispatch reads the brief as before.
      // One list: the keys the state holds and the ones the intake brief names (the chosen option's services), so a split
      // child still gets only its own trade's keys (keysOfTrade) and nothing is stored twice.
      const stateKeys = [...new Set([...(intake ? await stateKeysForIntake(admin, String(intake.id)) : []), ...intakeServiceKeys])].slice(0, 12);

      // ONE READY INTAKE POSTS ONE REQUEST (lib/intake_claim.ts): claimed here, by one conditional write, before any request is
      // written. It was marked consumed only after matching, so a second post of the same intake inside that window posted it twice.
      if (!(await claimIntake(admin, String(intake.id), email))) return J({ error: 'already_posted', code: 'already_posted', message: 'This request was already sent. Check your requests list.' }, 409);

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
            const { data, error } = await admin.from('inquiries').insert({ customer_id: cust.id, lang: inquiryLang, parent_inquiry_id: parentIdRef.id, category: tr, emirate, role_needed: 'supplier', raw_input: raw, spec, summary: childSummary(tr), keywords: childKw(tr), status: 'sent', budget, scope_type: 'single', trades: [tr], brief_source: briefSource, ...drawCols, ...briefCols, ...serviceKeyCols(await keysOfTrade(admin, stateKeys, tr)), compliance_checklist: await checklistFor(tr) }).select('id').maybeSingle();
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
          await releaseIntake(admin, String(intake.id));
          return J({ error: 'split_failed', code: 'split_failed', failed_trades: res.failed_trades, ...(res.cleanup_failed ? { cleanup_failed: true } : {}),
            message: 'Your request could not be sent to every trade (' + res.failed_trades.map(labelize).join(', ') + '). Nothing was sent — please try again.' }, 500);
        }
        // ONE ANSWER SHAPE (_shared/inquiry_posted.ts): inquiry_id is the parent, the stable id of
        // what the customer asked for; child_ids / quotable_ids are what suppliers quote on.
        // A part the matcher did not answer waits for the re-match (lib/rematch.ts): the portal says so for that part.
        const { data: waitingKids } = await admin.from('inquiries').select('id').eq('parent_inquiry_id', res.parentId).eq('routing->>matcher_unavailable', 'true');
        const waitingIds = new Set((waitingKids || []).map((k: { id: string }) => String(k.id)));
        return J({ ...postedSplit(res.parentId, res.children.map((c) => ({ ...c, label: labelize(c.trade), matching: waitingIds.has(String(c.inquiry_id)) })), distinctTrades), concierge: await confirmRequest(res.parentId) });
      }

      if (wantTurnkey) {
        const tkKeywords = Array.from(new Set([...keywords, 'fitout', 'fit out', 'fit-out', 'turnkey', 'interior', 'renovation', 'decoration', ...distinctTrades])).slice(0, 40);
        const { data: inq, error: e1 } = await admin.from('inquiries').insert({ customer_id: cust.id, lang: inquiryLang, category: 'fitout', emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords: tkKeywords, status: 'sent', budget, scope_type: 'turnkey', trades: distinctTrades.length ? distinctTrades : (tradesIn.length ? tradesIn : null), brief_source: briefSource, ...drawCols, ...briefCols, ...serviceKeyCols(stateKeys), compliance_checklist: await checklistFor('fitout') }).select('id').maybeSingle();
        if (e1) { await releaseIntake(admin, String(intake.id)); return J(...inquiryNotSaved(e1)); }
        const tradeList = distinctTrades.map(labelize).join(', ');
        const extra = (tradeList ? ' Combined turnkey scope covering: ' + tradeList + '.' : '') + (boqObj ? (briefSource === 'boq' ? ' The customer’s own bill of quantities is attached.' : ' A redacted drawing is attached.') : '');
        const { matches, routing } = await matchAndNotify(String(inq!.id), { category: 'fitout', emirate, summary, budget, extra: extra + supplierLine(reqStored) });
        // The routing goes back with the answer (finding c of 10 Nov 2026): a turnkey request no turnkey contractor matched
        // carries routing.separate_offer (how many specialists could quote it per trade), and the portal asks the customer
        // whether they want separate quotes. Nothing is split until they answer 'multi' (rulings 1021, 1025).
        return J({ ...postedSingle(String(inq!.id), 'turnkey', matches, routing), concierge: await confirmRequest(String(inq!.id)) });
      }

      const { data: inq, error: e1 } = await admin.from('inquiries').insert({ customer_id: cust.id, lang: inquiryLang, category, emirate, role_needed: 'supplier', raw_input: raw, spec, summary, keywords, status: 'sent', budget, scope_type: 'single', trades: tradesIn.length || intakeTradeCodes.length ? [...new Set([...tradesIn, ...intakeTradeCodes])] : null, brief_source: briefSource, ...drawCols, ...briefCols, ...serviceKeyCols(stateKeys), compliance_checklist: await checklistFor(category) }).select('id').maybeSingle();
      if (e1) { await releaseIntake(admin, String(intake.id)); return J(...inquiryNotSaved(e1)); }
      const extra = boqObj ? (briefSource === 'quotation' ? ' A scope (anonymized from the customer’s own quotation, prices removed) is attached.' : (briefSource === 'boq' ? ' The customer’s own bill of quantities is attached (quantities as the customer wrote them, prices removed).' : ' A drawing with a draft bill of quantities is attached.')) : '';
      const { matches, routing } = await matchAndNotify(String(inq!.id), { category, emirate, summary, budget, extra: extra + supplierLine(reqStored) });
      return J({ ...postedSingle(String(inq!.id), 'single', matches, routing), concierge: await confirmRequest(String(inq!.id)) });
    }
}
