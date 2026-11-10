// sales_engineer — the internal routes: the customer cutoff, then handoffs, complete_handoff, match, health, grants, obligations, sectors, capability.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import { MATCH_ALL, relevanceFloorApplies } from '../../_shared/supplier_capability.ts';
import { serviceKeysOf, serviceVocab } from '../../_shared/service_vocabulary.ts';
import { remoteEmbedder } from '../../_shared/meaning_embed.ts';
import { recallCases } from '../../_shared/case_recall.ts';
import { tradeSlugsOf, matchEmirate } from '../../_shared/match_criteria.ts';
import { admin, J, type ActionCtx } from '../context.ts';
import { embed } from '../lib/embed.ts';
import { run } from '../lib/run.ts';

export async function operatorActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, caller, action } = c;
    // Everything below `assist` and `report` is INTERNAL: seat readiness, the grant ledger, the
    // sector catalogue and the format matrix. A portal customer is authenticated but is not staff,
    // and an authenticated caller reaching an operator route is how privilege quietly widens.
    if (caller.kind === 'customer') return J({ error: 'forbidden', action }, 403);

    // ── HANDOFFS ───────────────────────────────────────────────────────────────────────────────
    // What other seats have handed this one and it has not closed (a remediation waiting on a
    // customer's proof, a delivery result not yet back), and the door to close one with evidence.
    if (action === 'handoffs') {
      const { data } = await admin.from('agent_actions').select('id,status,title,detail,evidence,created_at')
        .eq('kind', 'handoff').eq('agent', 'sales_engineer').neq('status', 'done').order('id').limit(100);
      return J({ ok: true, seat: 'sales_engineer', open: data || [] });
    }
    if (action === 'complete_handoff') {
      const { data: h } = await admin.from('agent_actions').select('id,agent').eq('id', Number(body.id)).eq('kind', 'handoff').maybeSingle();
      if (!h || h.agent !== 'sales_engineer') return J({ error: 'not_this_seats_handoff' }, 404);
      const { data, error } = await admin.rpc('fn_seat_handoff_complete', { p_id: Number(body.id), p_evidence: body.evidence ?? {} });
      if (error) return J({ ok: false, error: error.message }, 400);
      await run('complete_handoff', 'ok', { handoff_id: Number(body.id) });
      return J(data);
    }

    // ── THE ALIAS QUEUE (10 Nov 2026, founder ledger 1573/1579) ───────────────────────────────────────────────────
    // A phrase a supplier confirmed for a service ("PVC decorative panels" -> wallpaper.wall_panels) becomes a name every
    // customer's words can reach only when this seat approves it. public.fn_service_alias_decide refuses a phrase that already
    // names another service; an approved one is appended to taxonomy_trade_service.aliases (text -> code, never a match rule).
    if (action === 'alias_proposals') {
      const { data, error } = await admin.from('service_alias_proposal').select('id,phrase,trade_code,code,source,supplier_ids,seen,created_at')
        .eq('status', 'proposed').order('seen', { ascending: false }).order('id').limit(100);
      if (error) return J({ ok: false, error: error.message }, 503);
      return J({ ok: true, seat: 'sales_engineer', open: data || [] });
    }
    if (action === 'alias_decide') {
      const decision = String(body.decision || '');
      if (!['approved', 'rejected'].includes(decision) || !Number(body.id)) return J({ ok: false, error: 'id_and_decision_required' }, 400);
      const { data, error } = await admin.rpc('fn_service_alias_decide', { p_id: Number(body.id), p_decision: decision,
        p_by: caller.kind === 'service' ? 'sales_engineer:' + caller.context : caller.kind, p_reason: body.reason ? String(body.reason).slice(0, 300) : null });
      if (error) return J({ ok: false, error: error.message }, 503);
      await run('alias_decide', (data as { ok?: boolean })?.ok ? 'ok' : 'error', { id: Number(body.id), decision });
      return J(data);
    }

    // ── MATCH ──────────────────────────────────────────────────────────────────────────────────
    // "match capability is the sales engineer task." (founder, 9 September 2026)
    //
    // WHAT THIS REPLACES. customer_api:187 POSTed to functions/v1/route_inquiry inside an
    // `if (useRouter)` try/catch. route_inquiry was deleted in 182308b and is deployed nowhere, so
    // that fetch 404'd, `rj?.ok` was falsy, routerAnswered stayed false and the very next block
    // degraded to match_suppliers_kw — KEYWORD matching — marking routing.fallback = true. No
    // exception, no alert, no stuck row. decision_policy.use_capability_matching is true, so the
    // intent was capability matching and the reality was keywords, silently, on every inquiry.
    //
    // NO MODEL, AND NONE IS WANTED HERE. The gates below are not judgement calls, they are facts
    // about a supplier's declared and confirmed scope, and public.fn_match_capability already
    // applies every one of them as hard SQL BEFORE ranking: supplier-confirmed scope
    // (confirmed_at not null), trade intersection, declared negative scope (excluded_trades),
    // contracted role via taxonomy_role, every taxonomy_trade.authority_required code,
    // project-value band, and emirate coverage. It is not re-implemented here and must not be —
    // a second matcher is a second answer.
    //
    // THE GRANT'S OWN WORDS ARE THE LIMIT. sales.matching carries: "Unknown mandatory evidence is
    // not a pass. No inventing a minimum supplier count and no padding with poor matches." So
    // nothing below ever relaxes the floor to reach a target count, ever widens the trade set to
    // find somebody, and ever returns a supplier the SQL gates refused. A short list is the answer
    // when the market is short.
    if (action === 'match') {
      const { data: mayRaw, error: mayErr } = await admin.rpc('fn_agent_may_act', {
        p_grantee_role_id: 'sales_engineer', p_action_class: 'matching', p_amount_aed: null,
      });
      const may = (mayRaw || {}) as Record<string, unknown>;
      if (mayErr || may.may_act !== true) {
        await run('match', 'refused', {}, String(may.reason || mayErr?.message || 'no grant'));
        return J({ ok: false, error: 'not_permitted', ...may }, 403);
      }

      // ── WHOSE INQUIRY IT IS, AND WHO DECIDES ITS CRITERIA (23 Sep 2026) ────────────────────
      //
      // WHAT WAS MEASURED, because the finding handed over said something else. The hand-over said
      // "a signed-in customer can steer which suppliers receive somebody else's inquiry". A customer
      // CANNOT reach this branch: the cutoff above (`if (caller.kind === 'customer') return 403`)
      // refuses every portal caller before `match` is read. (#866 also noted that no service list
      // existed on the request at all; PR #859 added one on 23 Sep 2026, and it goes through the one
      // criteria source below like every other criterion, so a named inquiry still decides its own.)
      // Nor does any caller in the repository pass criteria: the ONE runtime
      // caller is customer_api.matchAndNotify, which sends `{action:'match', inquiry_id, persist:false}`
      // and nothing else. So the lever was reachable only with the sales_engineer credential, an
      // internal credential, or the founder's admin JWT.
      //
      // IT WAS STILL A REAL DOOR, and it was proved open on production before this change: the same
      // ZZ DEMO gypsum inquiry returned its own gypsum supplier on an honest call, and — with
      // `trades:['painting'], emirate:'Sharjah'` in the body and nothing else changed — returned
      // `asked_for.trades = ['painting']` and 0 matches instead. The body won over the stored row on
      // EVERY criterion, because every one of them was written `body.x || inq.x`. "Only our own
      // functions can reach it" is an argument about today's callers, not a guard.
      //
      // TWO RULES NOW.
      //  1. OWNERSHIP IS ENFORCED BY THE BUILD, NOT BY A BRANCH THAT CANNOT RUN. The obvious fix —
      //     `if (caller.kind === 'customer' && inq.customer_id !== caller.customerId) return 403` —
      //     DOES NOT COMPILE here, and that is the evidence rather than an inconvenience: `deno check`
      //     reports `Property 'customerId' does not exist on type 'never'`, because the cutoff above
      //     has already returned for every customer, so the only kinds that reach this line are
      //     sales_engineer, founder and service. Writing that branch anyway, with a cast to silence
      //     the compiler, would read as protection while asserting nothing — and would carry a
      //     bilingual refusal string no customer could ever be shown. So the invariant is stated as a
      //     type below: if the `match` branch is ever moved above that cutoff, `caller` widens, the
      //     assignment stops compiling and the green build goes red.
      //  2. A NAMED INQUIRY DECIDES ITS OWN CRITERIA. When inquiry_id resolves, the stored row is
      //     the only source and the body contributes nothing but `persist` — which declines a write
      //     and can therefore narrow nobody. The body is read only when NO inquiry is named, and
      //     then there is no third party to steer: that path is an operator exercising the matcher.
      const inquiryId = String(body.inquiry_id || '').trim();
      let inq: Record<string, unknown> | null = null;
      if (inquiryId) {
        const { data } = await admin.from('inquiries')
          // BOTH SIDES KEPT on the merge of 23 Sep 2026: customer_id for #866's ownership invariant,
          // service_keys for this branch's p_services gate.
          .select('id,customer_id,summary,raw_input,category,keywords,trades,emirate,scope_type,role_needed,budget,expected_value,boq,service_keys')
          .eq('id', inquiryId).maybeSingle();
        if (!data) return J({ ok: false, error: 'inquiry_not_found', inquiry_id: inquiryId }, 404);
        inq = data as Record<string, unknown>;
      }

      // THE OWNERSHIP INVARIANT, ENFORCED BY `deno check` (see rule 1 above). No customer caller can
      // reach `match`: the cutoff earlier in this handler returns 403 for `caller.kind === 'customer'`
      // before any action below it is read. This assignment is the only thing standing between that
      // fact and a silent regression — move `match` above the cutoff, or add a customer variant that
      // skips it, and the type widens and the build fails. customer_id is selected above so the
      // ownership comparison is one line away the day a customer-facing caller does reach this path.
      const _onlyOperatorsReachMatch: Exclude<typeof caller, { kind: 'customer' }> = caller;
      void _onlyOperatorsReachMatch;

      const arr = (v: unknown): string[] =>
        (Array.isArray(v) ? v : []).map((x) => String(x).trim().toLowerCase()).filter(Boolean);

      // THE ONE SOURCE OF CRITERIA (see the two rules above). `src` is the stored inquiry whenever
      // one is named, and the body ONLY when none is — mapped onto the stored column names so that
      // nothing below has to ask which it is reading, and so that no criterion can be written as
      // `body.x || inq.x` again without the check noticing.
      const src: Record<string, unknown> = inq ?? {
        trades: body.trades, emirate: body.emirate, scope_type: body.project_type,
        role_needed: body.need, expected_value: body.value, budget: body.value,
        summary: body.text, raw_input: null, category: null, keywords: [],
        // The request's own service list belongs here with every other criterion (merge of #866 and
        // #859, 23 Sep 2026): on a NAMED inquiry `src` is the stored row, so the stored service_keys
        // decide and the request's list is never consulted — a caller cannot narrow somebody else's
        // match to the services it chooses. On an unnamed call there is no third party to steer.
        service_keys: body.services,
      };
      // NO STORED EQUIVALENT, SAID OUT LOUD. `inquiries` carries no products and no brands column —
      // the select above is the whole of what this path reads. On a NAMED inquiry they are therefore
      // EMPTY, which is both what the one runtime caller sends today and the only non-narrowing
      // choice: a product or brand term switches the relevance floor ON (relevanceFloorApplies) and
      // can only REMOVE suppliers, and letting a caller remove suppliers from somebody else's match
      // is the whole finding. They are deliberately NOT derived from `keywords`: that would turn the
      // floor on for every inquiry, which is the exact condition that scored aluminium at 5.0 against
      // a floor of 35 and invited nobody (measured 15 Sep 2026, smoke run 34888342875). On an
      // UNNAMED call there is no third party to steer, so the caller's own terms are used.
      const products = inq ? [] : arr(body.products);
      const brands = inq ? [] : arr(body.brands);

      // TRADES. The customer's own words resolved through taxonomy_trade.aliases by
      // public.fn_norm_trades — the estate's normaliser, word-START anchored so 'sign' matches
      // "signage" and not "design". Reused, not re-written.
      // A single-trade request stores its trade in `category` only (12 Oct 2026, run f4294be8: 9 of 9
      // matched nobody) — tradeSlugsOf tries that slug on its own before the brief is read.
      let trades = tradeSlugsOf(src);
      // STORED TRADES ARE INTAKE SLUGS, THE MATCHER SPEAKS TAXONOMY CODES (14 Sep 2026). 39 of the 56
      // intake slugs are not taxonomy codes ('glass' is 'glazing', 'fitout' is 'interior_fitout' ...),
      // and passing them through made fn_match_capability answer zero for every request in those
      // categories — measured: ['glass'] matched nobody while ['aluminium'] matched both demo
      // suppliers. public.fn_taxonomy_trades_for is the one resolver
      // (scripts/sql/every_intake_trade_resolves_to_the_capability_vocabulary.sql). It is EXACT ONLY
      // (founder, 14 Sep 2026: "either exact match or no match"): a slug resolves to itself and to the
      // same trade's taxonomy code, never to a neighbour. A category nobody is registered for matches
      // nobody, and the no-match path below says so honestly.
      if (trades.length) {
        const { data: codes, error: resErr } = await admin.rpc('fn_taxonomy_trades_for', { p_slugs: trades });
        if (!resErr && Array.isArray(codes)) trades = arr(codes);
      }
      const brief = [src.summary, src.raw_input, src.category, arr(src.keywords).join(' ')]
        .map((x) => String(x ?? '')).filter(Boolean).join(' ').slice(0, 4000);
      if (!trades.length && brief) {
        const { data: nt } = await admin.rpc('fn_norm_trades', { p_text: brief });
        trades = arr(nt);
      }

      // WHAT THE CUSTOMER NEEDS DONE, not what a supplier would like to sell. taxonomy_role
      // decides which roles can serve each; this only picks the column.
      const needAsked = inq ? '' : body.need;
      const need = String(needAsked ?? '').trim() ||
        (String(src.scope_type || '').toLowerCase().includes('turnkey')
          ? 'whole_scope'
          : (/supply|material|product/i.test(String(src.scope_type || src.role_needed || '')) ? 'supplies' : 'executes'));

      // VALUE. Only a number that is actually a number gates the size band; a budget we cannot read
      // stays null, because an unreadable budget parsed as 0 would exclude every supplier with a
      // minimum. "Unknown mandatory evidence is not a pass" cuts the other way too: it is not a
      // fail either — it is unknown, and an unknown value simply does not gate.
      const num = (v: unknown): number | null => {
        const n = Number(String(v ?? '').replace(/[^0-9.]/g, ''));
        return Number.isFinite(n) && n > 0 ? n : null;
      };
      const value = num(src.expected_value) ?? num(src.budget);
      const emirate = matchEmirate(src.emirate);
      const projectType = String(src.scope_type ?? '').trim() || null;

      // THE RELEVANCE FLOOR IS READ, NOT COMPILED IN (decision_policy.match_relevance_floor = 35, measured 9 Sep 2026).
      const { data: polRows } = await admin.from('decision_policy').select('key,value')
        .in('key', ['match_relevance_floor']);
      const pol = Object.fromEntries((polRows || []).map((r: { key: string; value: unknown }) => [r.key, Number(r.value)]));
      // EVERY MATCHED SUPPLIER IS INVITED (founder ruling 24 Sep 2026: ANY number of suppliers may quote; "top 3" is
      // only the comparison report's recommendation). The per-trade cap of 3 and the ceiling of 5 left a 4th capable
      // supplier uninvited (sandbox run 1c94fa6a S07). No count caps the invitation; the SQL gates and the relevance
      // floor decide who is matched. match_max_fanout / _per_trade are no longer read.
      const floor = Number.isFinite(pol.match_relevance_floor) ? pol.match_relevance_floor : 35;

      const policy = { max_fanout: null, max_fanout_per_trade: null, relevance_floor: floor };
      // HAVE WE MATCHED THIS KIND OF JOB BEFORE, AND HOW DID IT END? (23 Sep 2026.) By meaning, within
      // the same trade only (the exact-trade rule), never this inquiry itself. Evidence in the answer;
      // it does not change the SQL gates — a precedent informs the seat, it does not pick suppliers.
      const memory = await recallCases(admin, {
        seat: 'sales_engineer', path: 'match', situation: brief,
        // The same key the case row is written under (trg_case_memory_inquiry: trades[1], else category).
        trade: inq ? (arr(inq.trades)[0] || String(inq.category ?? '') || null) : null,
        exclude: inquiryId ? { table: 'inquiries', id: inquiryId } : null,
        // this worker's own gte-small session, not a second one
        embedding: brief ? await Promise.race([embed(brief), new Promise<null>((r) => setTimeout(() => r(null), 1500))]) : null,
      });
      // BOTH SIDES KEPT on the merge of 23 Sep 2026: `services` is this branch's p_services record,
      // `criteria_from` is #866's.
      const askedFor = { trades, need, products, brands, project_type: projectType, value, emirate, services: [] as string[], services_read: null as string | null };
      // WHERE EVERY FIGURE ABOVE CAME FROM, printed rather than assumed. A reader of a match record
      // should not have to diff the body against the inquiry to know which decided.
      const criteriaFrom = inq ? 'stored_inquiry' : 'request_body_no_inquiry_named';

      if (!trades.length) {
        // NOT A FAILURE AND NOT A COVERAGE GAP. Nobody was asked, because there was no question:
        // the brief names no trade this taxonomy recognises. Widening it to "everything" to produce
        // a list would be exactly the padding the grant forbids.
        await run('match', 'ok', { inquiry_id: inquiryId || null, trades: 0, matched: 0, gap: 'no_trade_identified' });
        return J({
          ok: true, seat: 'sales_engineer', inquiry_id: inquiryId || null, asked_for: askedFor, criteria_from: criteriaFrom, policy, precedent: memory,
          candidates: 0, above_floor: 0, matched: [], persisted: 0,
          gap: { reason: 'no_trade_identified',
            note: 'The brief names no trade in taxonomy_trade, so fn_match_capability was not called. This is a brief that needs a question answered, not a supply gap.' },
        });
      }

      // ── THE SERVICES THE INQUIRY NAMES ────────────────────────────────────────────────────────
      // The founder calls services "our cross matching main source" (15 Sep 2026, instruction
      // 438/439): the supplier's CONFIRMED service list decides who receives a request, exact or
      // none. fn_match_capability has taken p_services since 15 Sep and gates on it — and MEASURED
      // 22 Sep 2026, NO caller passed it: this matcher, customer_api's preview, inquiry_intake's
      // supplier count and public_site all sent 8 arguments, so every request in production was
      // matched at TRADE level and the services a supplier spent its Services tab confirming
      // decided nothing at all.
      //
      // ONE READER, THE SUPPLIER'S OWN. _shared/service_vocabulary.ts serviceKeysOf reads the brief and
      // BOQ with the rule the Services tab reads a supplier's words with: a phrase that IS a service, or
      // one that MEANS it over the stored service vectors (never an alias word inside it: ruling 890,
      // decision point 93, 29 Sep 2026). All or nothing: a text it could not read whole gives NO keys
      // (trade level, nobody dropped), and that "not read" is never stored as "names nothing".
      //
      // STORED, NOT RE-DERIVED. inquiries.service_keys carries what the reader found; null means
      // never derived (an inquiry created before this column), '{}' means derived and the brief
      // names no service in the taxonomy. Both are safe: an empty p_services leaves every
      // candidate through, so a brief the vocabulary does not recognise falls back to trade-level
      // matching and NOBODY is dropped for it. The derivation is stored on first use, which is
      // also how a pre-existing inquiry acquires its keys.
      //
      // NULL AND '{}' ARE DIFFERENT, and only the column itself can tell them apart — `arr` flattens
      // both to an empty list, so the derivation is decided by Array.isArray on the stored value, not
      // by the length. '{}' means a reader already looked and the brief names no service this taxonomy
      // knows; re-deriving it on every match would re-read the vocabulary for nothing.
      let serviceKeys = arr(src.service_keys);
      let servicesRead: string | null = null;
      if (inq && !Array.isArray(inq.service_keys)) {
        const sk = await serviceKeysOf(brief, inq.boq, { services: await serviceVocab(admin), embed: remoteEmbedder(admin, 'sales_engineer') });
        serviceKeys = sk.keys; servicesRead = sk.state;
        // Stored only when the whole text was read; a failed write must not stop the match (the keys
        // are still used for this run). An unread text stays null and is read again on the next match.
        if (sk.complete) await admin.from('inquiries').update({ service_keys: serviceKeys }).eq('id', inquiryId);
      }
      askedFor.services = serviceKeys;
      askedFor.services_read = servicesRead;

      // Every gated candidate, not a top N (fn_match_capability applies `limit greatest(1, p_limit)`).
      const headroom = MATCH_ALL;
      const { data: rowsRaw, error: matchErr } = await admin.rpc('fn_match_capability', {
        p_trades: trades, p_need: need, p_products: products, p_brands: brands,
        p_project_type: projectType, p_value: value, p_emirate: emirate, p_limit: headroom,
        p_services: serviceKeys,
      });
      if (matchErr) {
        await run('match', 'error', { inquiry_id: inquiryId || null }, matchErr.message);
        return J({ ok: false, error: 'match_failed', detail: matchErr.message }, 503);
      }
      const rows = (rowsRaw || []) as Array<Record<string, unknown>>;

      // THREE DIFFERENT EMPTIES, AND THEY MUST NOT PRINT AS THE SAME 0. `candidates` is what
      // cleared the hard gates; `above_floor` is what then cleared the relevance floor. A gap after
      // the gates is a market fact; a gap after the floor is a policy fact; they call for different
      // work and were previously one number.
      // THE FLOOR GATES ONLY WHAT IT CAN MEASURE (15 Sep 2026). Measured on production:
      // fn_match_capability(['aluminium']) with no products scored two verified, confirmed demo
      // aluminium suppliers at 5.0 (the product term is 0 and size is unknown, 0.5 x 10), and with
      // products ['aluminium windows'] at 45.0. customer_api's create_inquiry match sends no products,
      // so against the floor of 35 every supplier without a track record was dropped and a ready
      // aluminium request invited nobody (smoke run 34888342875: 0/3 matched). The #658 check calls
      // the SQL directly and never met this floor. With no product named there is no relevance to
      // measure; the exact trade already is the relevance test ("either exact match or no match"),
      // so the floor gates only when products were asked for. No count cap applies after it.
      const aboveFloor = relevanceFloorApplies(products) ? rows.filter((r) => Number(r.score) >= floor) : rows;

      const picked = aboveFloor;

      const matched = picked.map((r) => ({
        supplier_id: Number(r.supplier_id),
        company_name: r.company_name ?? null,
        // The SAME normalisation customer_api already applies: fn_match_capability's weights come
        // from decision_policy and sum to 100 by construction, so 100 is the denominator and the
        // stored similarity is a 0..1 fraction on a declared scale.
        score: Number(r.score),
        similarity: Math.round(Math.min(1, Math.max(0, Number(r.score) / 100)) * 1000) / 1000,
        reason: String(r.why || '').slice(0, 400),
        trades: r.trades, roles: r.roles, product_hits: r.product_hits,
        brand_hit: r.brand_hit, ptype_hit: r.ptype_hit, track: r.track,
      }));

      // THE MATCH RECORD. inquiry_matches carries a UNIQUE (inquiry_id, supplier_id), so this is an
      // upsert and a re-run of the same decision is not a second fanout.
      //
      // MEASURED 9 SEP 2026, AND IT CONTRADICTS THE COMMENT customer_api CARRIES: the two BEFORE
      // INSERT eligibility triggers it describes — a00_unsafe_match_eligibility and
      // gate_incomplete_match — DO NOT EXIST on this database. pg_trigger holds 4 rows for
      // inquiry_matches and every one is an internal referential-integrity trigger; there are 0
      // user triggers, and neither trigger FUNCTION exists in pg_proc either. So nothing between
      // this insert and the table refuses a supplier, and the eligibility that comment relies on is
      // being applied ONLY by fn_match_capability's own fn_is_matchable gate above. That is a real
      // gate and it is enough for this path — but it is one gate, not three, and it is stated here
      // rather than assumed.
      //
      // customer_api passes persist:false: it performs its own write immediately afterwards
      // because it needs the landed/refused split to decide who to email. One writer per path.
      let persisted = 0;
      const wantPersist = body.persist !== false && !!inquiryId;
      if (wantPersist && matched.length) {
        const { data: landed, error: insErr } = await admin.from('inquiry_matches')
          .upsert(matched.map((m) => ({
            inquiry_id: inquiryId, supplier_id: m.supplier_id,
            similarity: m.similarity, match_reason: m.reason,
          })), { onConflict: 'inquiry_id,supplier_id' })
          .select('supplier_id');
        if (insErr) {
          await run('match', 'error', { inquiry_id: inquiryId, matched: matched.length }, insErr.message);
          return J({ ok: false, error: 'match_record_failed', detail: insErr.message, matched }, 503);
        }
        persisted = (landed || []).length;
      }

      // A SUPPLY GAP IS A FINDING, NOT AN ERROR. ok stays true, the customer's intent is not
      // distorted, the project is not silently split, and nothing is escalated to the founder. The
      // recording and recovery path already exists and is NOT duplicated here: customer_api's
      // flagCoverageGap() fires on exactly this condition (zero landed matches) and writes the
      // agent_actions coverage_gap row, the founder_alerts line and the owner notification.
      const gap = matched.length ? null : {
        reason: rows.length === 0 ? 'no_capable_supplier' : 'below_relevance_floor',
        candidates_before_floor: rows.length,
        best_score: rows.length ? Number(rows[0].score) : null,
        relevance_floor: floor,
        note: rows.length === 0
          ? 'No supplier cleared fn_match_capability\'s hard gates for this trade, role, authority, value band, emirate and availability (a busy or paused supplier is skipped). This is a supply-coverage gap, or every capable supplier is busy: the demand is real and nobody can answer it now. customer_api flags it to the stalled-inquiry rescue (fn_stalled_inquiry_flag).'
          : 'Suppliers cleared the hard gates but none reached the configured relevance floor. Lowering the floor to produce a list is expressly forbidden by the sales.matching grant.',
        recovery: 'Recorded and pursued by customer_api.flagCoverageGap() on the create_inquiry path (agent_actions coverage_gap + founder_alerts + owner notification). The customer\'s scope is not widened, the project is not split, and no supplier choice is put to the founder.',
      };

      await run('match', 'ok', {
        inquiry_id: inquiryId || null, trades: trades.length, candidates: rows.length,
        above_floor: aboveFloor.length, matched: matched.length, persisted, gap: gap?.reason ?? null,
      });

      return J({
        ok: true, seat: 'sales_engineer', caller: caller.kind, precedent: memory,
        inquiry_id: inquiryId || null,
        asked_for: askedFor, criteria_from: criteriaFrom, policy,
        candidates: rows.length, above_floor: aboveFloor.length,
        matched, persisted, gap,
        grant: { grant: may.grant, limit: may.limit },
        basis: 'public.fn_match_capability — supplier-confirmed scope, trade intersection, declared exclusions, contracted role, mandatory authorities, project-value band, emirate coverage and each supplier\'s own availability (busy or paused is skipped) applied as SQL gates before ranking; then decision_policy\'s relevance floor; every supplier left is invited, with no count cap. No model was called and no supplier was added to reach a count.',
      });
    }

    // ── HEALTH ─────────────────────────────────────────────────────────────────────────────────
    // Readiness measured, not asserted. The audit of 9 Sep found the only honest liveness signal for
    // the CEO seat was an authenticated round-trip returning 200; edge_health_probe exists with 0
    // rows and nothing writes it. This route answers the question directly: is the seat established,
    // what may it do, and what is it waiting on.
    if (action === 'health') {
      const [agent, grants, know, routes] = await Promise.all([
        admin.from('org_agents').select('agent_key,active,available').eq('agent_key', 'sales_engineer').maybeSingle(),
        admin.from('ceo_standing_grant').select('grant_key,action_class,active').eq('grantee_role_id', 'sales_engineer'),
        admin.from('sales_knowledge').select('record_id', { count: 'exact', head: true }),
        admin.from('llm_route_health').select('model_id,open_until'),
      ]);

      const held = (routes.data || []).filter((r: { open_until: string | null }) =>
        r.open_until && new Date(r.open_until) > new Date());

      // A knowledge table that does not exist yet is a stage of the build, not an error. Say which.
      const knowledgeCount = know.error ? null : (know.count ?? 0);

      await run('health', 'ok', { grants: (grants.data || []).length, knowledge: knowledgeCount });
      return J({
        ok: true,
        seat: 'sales_engineer',
        caller: caller.kind,
        seated: agent.data?.active === true && agent.data?.available === true,
        grants: (grants.data || []).map((g: { grant_key: string; action_class: string; active: boolean }) =>
          ({ grant: g.grant_key, class: g.action_class, active: g.active })),
        knowledge_records: knowledgeCount,
        knowledge_state: know.error ? 'not_ingested' : (knowledgeCount ? 'ingested' : 'empty'),
        // The single most useful thing this route can report, because it is what gates the half of
        // this seat that needs judgement.
        model_calls_available: held.length === 0,
        model_hold: held.length
          ? { routes_held: held.length, until: held[0].open_until,
              note: 'fn_kernel_paid_provider_gate denies globally while any route is held; the founder set this and only he can clear it' }
          : null,
      });
    }

    // ── GRANTS ─────────────────────────────────────────────────────────────────────────────────
    // What may this seat do right now, answered by the database at call time — expiry and active
    // state are evaluated inside fn_agent_may_act, so a revoked grant cannot be used from a cached
    // answer. An uncovered class routes to the CEO and says so; it never routes to the founder.
    if (action === 'grants') {
      const cls = String(body.action_class || '').trim();
      if (cls) {
        const { data, error } = await admin.rpc('fn_agent_may_act', {
          p_grantee_role_id: 'sales_engineer', p_action_class: cls,
          p_amount_aed: body.amount_aed ?? null,
        });
        if (error) return J({ ok: false, refused: error.message }, 400);
        await run('grants', 'ok', { action_class: cls });
        return J({ ok: true, action_class: cls, ...(data as Record<string, unknown>) });
      }
      const { data } = await admin.from('ceo_standing_grant')
        .select('grant_key,action_class,scope_note,limit_note,max_amount_aed,active,expires_at')
        .eq('grantee_role_id', 'sales_engineer').order('grant_key');
      await run('grants', 'ok', { listed: (data || []).length });
      return J({ ok: true, grants: data || [] });
    }

    // ── OBLIGATIONS ────────────────────────────────────────────────────────────────────────────
    // The intake obligation set for one sector: which questions still resolve a material
    // uncertainty, given what is already known.
    //
    // This is the build prompt's section 6 made deterministic: "Build an inquiry-specific obligation
    // set instead of asking every field in a static category checklist. Each question must resolve a
    // material uncertainty... do not dump an enormous form, repeatedly ask answered questions or
    // require irrelevant information."
    //
    // `answered` is the set of field_keys already resolved by earlier answers or by a document. The
    // difference is the obligation set. No model is consulted to compute a set difference, and one
    // consulted here would make the same question non-reproducible between two identical inquiries.
    if (action === 'obligations') {
      const sector = String(body.sector_id || '').trim();
      if (!sector) return J({ error: 'sector_id_required' }, 400);
      const answered = new Set((Array.isArray(body.answered) ? body.answered : []).map(String));

      const { data, error } = await admin.from('sales_qualification_field')
        .select('field_key,question,answer_type,ask_only_if,criticality,unknown_handling')
        .eq('sector_id', sector).order('field_key');

      if (error) return J({ ok: false, error: 'knowledge_not_ingested', detail: error.message }, 503);
      if (!data?.length) return J({ ok: false, error: 'unknown_sector', sector_id: sector }, 404);

      const open = data.filter((f: { field_key: string }) => !answered.has(f.field_key));
      await run('obligations', 'ok', { sector, total: data.length, open: open.length });
      return J({
        ok: true,
        sector_id: sector,
        total_fields: data.length,
        answered: data.length - open.length,
        obligations: open,
        // Stated rather than implied: this is the sector's catalogue, not a judgement that these are
        // the only things that matter for this particular inquiry.
        basis: 'seed catalogue for this sector; a document or an answer may retire a field, and an unusual scope may add one that is not listed here',
      });
    }

    // ── SECTORS ────────────────────────────────────────────────────────────────────────────────
    if (action === 'sectors') {
      // A lookup box over the sector catalogue, not a matching judgement. Characters that are PostgREST filter
      // syntax are dropped so the caller's text cannot add conditions to the or() below.
      const q = String(body.q || '').replace(/[,()*%\\:."]/g, ' ').trim();
      let query = admin.from('sales_sector').select('sector_id,group_key,title,scope');
      if (q) query = query.or(`title.ilike.%${q}%,scope.ilike.%${q}%,sector_id.ilike.%${q}%`);
      const { data, error } = await query.order('sector_id').limit(Number(body.limit ?? 50));
      if (error) return J({ ok: false, error: 'knowledge_not_ingested', detail: error.message }, 503);
      await run('sectors', 'ok', { q, found: (data || []).length });
      return J({ ok: true, sectors: data || [], count: (data || []).length });
    }

    // ── CAPABILITY ─────────────────────────────────────────────────────────────────────────────
    // The per-format capability status the build prompt requires, section 8: "Implement real
    // parsers/adapters and expose per-format capability status... Never claim full extraction when
    // only a thumbnail or subset worked... Do not advertise unsupported DWG handling as completed."
    //
    // Every entry is MEASURED at call time against the deployed function list, not declared. A format
    // whose handler is not deployed reports unavailable with the reason, so a caller can tell "we
    // cannot read this" from "we read it and found nothing" — which are the same empty result and
    // very different facts.
    if (action === 'capability') {
      const { data: owned } = await admin.from('function_owner').select('function_slug');
      const present = new Set((owned || []).map((r: { function_slug: string }) => r.function_slug));

      // The handler each format needs, and what it can honestly do when it is present. Written from
      // the 9 Sep audit of every deployed document function, not from their names.
      const FORMATS = [
        { format: 'pdf_text_layer', handler: 'extract_text', gives: 'one flat text blob; no pages, no layout, no coordinates' },
        { format: 'pdf_scanned', handler: 'doc_extract', gives: 'OCR fallback — the only one in the estate' },
        { format: 'pdf_licence', handler: 'license_extract', gives: 'model-asserted licence fields; enum-whitelisted' },
        { format: 'pdf_quotation', handler: 'quote_extract', gives: 'quotation line items' },
        { format: 'drawing_to_boq', handler: 'drawing_boq', gives: 'model-read line items from page images; never geometry or scale' },
        { format: 'drawing_redaction', handler: 'drawing_redact', gives: 'pixel overlay on a raster; NOT layers, block attributes, xrefs or embedded thumbnails' },
        { format: 'dwg_dxf', handler: 'cad_convert', gives: 'raster preview only (200 dpi PNG via CloudConvert); no entities, layers or dimensions, ever' },
        { format: 'xlsx', handler: 'supplier_catalog_ingest', gives: 'first sheet only, cached values, hidden rows included, merges ignored' },
      ];

      const matrix = FORMATS.map((f) => ({
        ...f,
        available: present.has(f.handler),
        reason: present.has(f.handler) ? null : `${f.handler} is not deployed`,
      }));

      await run('capability', 'ok', { available: matrix.filter((m) => m.available).length, total: matrix.length });
      return J({
        ok: true,
        formats: matrix,
        available: matrix.filter((m) => m.available).length,
        total: matrix.length,
        // The sentence that must never be softened.
        native_dwg: 'NOT SUPPORTED. CloudConvert is configured and paid for, but it is a rasteriser — entity-level DWG needs a licensed SDK the estate does not have. Any DWG handling is raster preview only.',
      });
    }
}
