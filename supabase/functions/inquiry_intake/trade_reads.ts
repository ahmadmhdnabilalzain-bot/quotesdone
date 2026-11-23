// inquiry_intake/trade_reads.ts — WHAT THE TRADE BRINGS TO THE TURN: its checklist(s), the desks' ordered questions, its
// specialist and its field knowledge. handle.ts starts the four reads together (27 Oct 2026, turn_clock.ts) and awaits each
// here, in the order it always did; what each does with its answer is unchanged. Moved verbatim from handle.ts (19 Nov 2026,
// it_engineer; ledgers 1714/1715/1556: handle.ts was 1,418 lines).
// deno-lint-ignore-file no-explicit-any
import { admin } from './shared.ts';

type Read<T> = PromiseLike<{ data: T }> | null;

/** The checklist of the stored trade and of each trade of a multi-trade request (category_specs.fields). */
export async function readChecklists(specsP: Read<any>, tradeSlugsForChecklist: string[], category: string | null) {
  let checklist: any[] = [];
  const perTradeChecklists: { slug: string; label: string; fields: any[] }[] = [];
  if (specsP) {
    const { data: specs } = await specsP;
    for (const slug of tradeSlugsForChecklist) {
      const spec = (specs || []).find((s: any) => String(s.category) === slug);
      if (spec && Array.isArray(spec.fields)) { perTradeChecklists.push({ slug, label: spec.label || slug, fields: spec.fields }); if (slug === category) checklist = spec.fields; }
    }
    if (!checklist.length && perTradeChecklists.length) checklist = perTradeChecklists[0].fields;
  }
  return { checklist, perTradeChecklists };
}

/** The desks' qualification order (fn_category_questions): the prompt's "ASK IN THIS ORDER" and field_key -> ask_order. */
export async function readOrderedQuestions(questionsP: Read<any>) {
  // 6 Aug 2026. THE ORDERED INTERVIEW. category_specs.fields is a FLAT list with a required flag
  // and no sequence, so the model chose its own order every turn. The corpus carries the spec's
  // "Inquiry Qualification Logic": 16,588 questions, 4,117 distinct, 7,079 mandatory, each with an
  // explicit ask-order and a supplier-facing field key - and it had no runtime reader at all
  // (grep kb_stage over supabase/functions returned exactly one file, its own importer).
  //
  // Added ALONGSIDE the checklist, never instead of it: category_specs.fields is a CONTRACT.
  // fn_rfq_required_check scores those exact keys and trg_rfq_complete computes rfq_ready from
  // them, and dispatch answers a not-ready inquiry with {"ok":true,"skip":"not_rfq_ready"} - a 200
  // that contacts nobody. So the checklist still decides completeness; this only decides what gets
  // asked, and in what order.
  let orderedQuestions = '';
  // field_key -> ask_order, for the deterministic interview. MEASURED 14 Sep 2026: only 7 of the
  // 396 category_specs keys appear among fn_category_questions' supplier-facing keys (acrylic,
  // signage and upholstery `quantity` at 110; general-building-contracting `project_type` at 30;
  // three more at 999), so for almost every field the spec's own order decides. It is applied
  // anyway so the interview follows the desks' order wherever the two vocabularies do meet.
  const askOrder: Record<string, number> = {};
  if (questionsP) {
    try {
      const { data: qs } = await questionsP;
      const list = ((qs as any[]) || []).filter((q: any) => q && q.question);
      for (const q of list) if (q.field_key && askOrder[q.field_key] === undefined) askOrder[q.field_key] = Number(q.ask_order) || 999;
      if (list.length) {
        orderedQuestions = list
          .map((q: any, i: number) => `${i + 1}. [${q.field_key || 'q'}] ${String(q.question).trim()}${q.answer_type ? ` (${q.answer_type})` : ''}`)
          .join('\n');
      }
    } catch (_e) { /* the ordered interview is an enhancement, never a gate on intake */ }
  }
  return { orderedQuestions, askOrder };
}

/** The category specialist: the category_agents row whose key IS the trade, else none (the generic sales engineer). */
export async function readSpecialist(agentP: Read<any>, turns: any[]) {
  // ── CATEGORY SPECIALIST TAKEOVER ───────────────────────────────────────────────────────────────
  // WHY THIS EXISTS: the product spec is "once the system understands the category of the inquiry, the
  // relevant EXPERT agent joins the conversation". The expert-selection logic (token match over
  // category_agents, plus the agent's persona) already existed inside inquiry_ai but had ZERO callers
  // anywhere in the repo — it was dead code — so in practice ONE generic agent answered every turn and
  // no category expert ever took over. It is folded in HERE, inside the single live intake path, so the
  // specialist owns the conversation with NO extra LLM round-trip (same single call, specialist voice).
  // If no specialist matches the category we fall through to the generic prompt, unchanged.
  let specialist: { slug: string; name: string; persona: string } | null = null;
  let specialistIsNew = false;
  if (agentP) {
    try {
      // The specialist is the one whose key IS the reasoned category (23 Sep 2026, decision point
      // inquiry_intake.specialist): the shared-token score over slugs and names that picked a "nearest" persona is
      // gone. No agent with exactly this key: the generic sales engineer answers — never a neighbour's persona.
      // One read now carries the persona too (it was a second read of the same row by the same key).
      const { data: best } = await agentP;
      if (best) {
        const sp = { slug: String(best.slug), name: String(best.name || best.slug), persona: String(best.persona || '') };
        specialist = sp;
        // First turn where this specialist is in charge → it introduces itself once (the visible hand-over).
        specialistIsNew = !turns.some((t: any) => t && t.role === 'assistant' && t.agent === sp.slug);
      }
    } catch (_e) { /* specialist selection is best-effort — it must never block intake */ }
  }
  return { specialist, specialistIsNew };
}

/** The specialist's field knowledge: kb_query by the customer's own words, else fn_category_knowledge per trade. */
export async function readFieldKnowledge(kbP: Promise<(string | null)[]> | null, tradeSlugsForChecklist: string[]): Promise<string> {
  // Specialist FIELD KNOWLEDGE — RAG-retrieved from the deep, cited knowledge base (kb_chunks:
  // 2.3k+ embedded chunks) using the CUSTOMER'S OWN words, so intake gets the passages actually
  // relevant to this request (authorities, standards, specs, price drivers, the sharp qualifying
  // questions). Falls back to the flat trade brief if retrieval is empty.
  let specialistKB = '';
  if (kbP) {
    // kbFor (below the handler) is the 3 s budgeted kb_query read; it was started with the trade's other reads.
    const parts = (await kbP).filter((p): p is string => !!p);
    specialistKB = parts.join('\n\n').slice(0, 3800);
    if (!specialistKB) {
      // 6 Aug 2026. THIS FALLBACK COULD NOT FIRE FOR 53 OF 56 CATEGORIES, AND THAT WAS INVISIBLE.
      // It used to read agent_knowledge directly with `'cat:' + s`, where s is a LEGACY
      // category_specs slug ('glass', 'hvac', 'fitout'). agent_knowledge is keyed by CATALOGUE
      // slug ('cat:aluminium-and-glass-suppliers'), and the measured overlap between the two
      // vocabularies is EXACTLY ZERO — so `cat:glass` matched no row, the query returned [], and
      // the specialist went into the conversation with its checklist and none of its Industry,
      // Technical, UAE-authority or Supplier knowledge. The customer got a generic interrogation
      // from an agent that had 15 modules of expertise sitting one join away.
      //
      // Nothing failed. No error, no empty-result log — the `if (kbRows && kbRows.length)` guard
      // simply skipped, and FIELD EXPERTISE was omitted from the prompt. A silently absent prompt
      // section reads exactly like a category that has no knowledge yet.
      //
      // fn_category_knowledge accepts EITHER vocabulary and resolves through lead_trade_map, so
      // the caller does not have to know which one it is holding.
      const catParts: string[] = [];
      for (const s of tradeSlugsForChecklist.slice(0, 2)) {
        try {
          const { data: mods } = await admin.rpc('fn_category_knowledge', { p_category: s });
          const rows = ((mods as any[]) || []).map((r: any) => String(r.content || '').trim()).filter(Boolean);
          if (rows.length) catParts.push(s + ':\n' + rows.join('\n').slice(0, 1400));
        } catch (_e) { /* knowledge is an enhancement, never a gate on intake */ }
      }
      specialistKB = catParts.join('\n\n').slice(0, 2800);
    }
  }
  return specialistKB;
}
