// supplier_onboard — SPEC FILE #5 §2. A SENTENCE IN, A SUPPLIER PROFILE OUT.
//
// The spec opens by rejecting the form wall: the supplier should not "register then fill 20 forms",
// they should be asked about their company and answer in their own words. Nothing in the estate did
// that. `profile_ai` looks like it does and does not: it enriches a lead from an INBOUND EMAIL and
// its attachments, it is gated by requireInternal so a supplier cannot call it, and its schema has
// no company_name at all — because in that flow the company is already known. Onboarding is the
// opposite case. The company is the one thing we do not know.
//
// ── THIS FUNCTION EXTRACTS. IT DOES NOT APPROVE, AND IT DOES NOT WRITE THE APPROVAL DECISION ─────
// supplier_api/save_profile carries the licence gate: it decides approval_status and `verified` from
// a readable, in-date trade licence. Writing the profile from here would either duplicate that gate
// or bypass it, and bypassing it means a supplier talks their way to `verified` in one paragraph.
// So the write goes back through create_company + save_profile, unchanged, and this endpoint only
// ever returns structure. Nothing here can approve anybody.
//
// ── AND IT NEVER INVENTS ─────────────────────────────────────────────────────────────────────────
// A field the supplier did not state comes back null and is reported as still missing, so the
// conversation can ask for it. An extraction that guesses "Dubai" because most suppliers are in
// Dubai is worse than an empty field: the supplier would have to notice the error to correct it.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';

// The same closed category list save_profile and the matching engine use. An extraction that
// returns a category outside it is not a category, it is a free-text label that nothing can match.
const CATS = ['acrylic', 'aluminium', 'carpentry', 'fitout', 'flooring', 'glass', 'gypsum', 'landscaping',
  'painting', 'safety', 'scaffolding', 'security', 'signage', 'steel', 'upholstery', 'wallpaper'];
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];

// THE SIX FIELDS §2 ENUMERATES, plus the conversational reply. `response_format` is asked for
// explicitly rather than hoped for: a prose answer with JSON somewhere inside it is a parse
// gamble, and this runs while a real supplier is waiting.
const EXTRACTION_PROMPT = `You are onboarding a UAE construction / fit-out / facilities supplier onto QuotesDone.
The supplier is describing their company in their own words. Extract ONLY what they actually said.

Return STRICT JSON, no markdown, exactly this shape:
{"company_name":string|null,
 "category":string|null,
 "company_type":string|null,
 "company_type_basis":string|null,
 "location":string|null,
 "capability_summary":string|null,
 "markets":[string],
 "reply":string}

Field rules:
- company_name: the trading name of THEIR company. Null unless they named it.
- category: the single best-fit trade, chosen ONLY from this exact list, lowercase:
  ${CATS.join(', ')}. Null if what they said does not clearly land in one.
- company_type: one of manufacturer, contractor, supplier, trader — or a short phrase if they
  stated something else clearly. Null if they did not say what kind of business they are.
- company_type_basis: the supplier's OWN WORDS that justify company_type, copied VERBATIM from
  their message — not your paraphrase. Null whenever company_type is null. If you cannot quote
  them saying it, you do not know it: return null for both. "We do curtain walling" does not make
  someone a contractor; "our own fabrication shop" does support manufacturer.
- location: the emirate or city they are based in, as they said it. Null if not stated.
- capability_summary: one paragraph, no line breaks, describing what they can actually do —
  products, services, scale, materials. This is what a matching engine reads. Null if they said
  nothing about their capability.
- markets: the emirates, countries or regions they SERVE (not where they are based). Use canonical
  emirate names where they mean an emirate. "all UAE" / "nationwide" means all seven. [] if unknown.
- reply: two sentences, warm and specific, addressed to the supplier. Acknowledge what you
  understood, then ask for the single most useful thing still missing. Never invent a fact back to
  them. If everything is present, confirm and say their profile is ready to save.

Never output "N/A", "unknown" or a placeholder. Use null.`;

function parseJson(txt: string) {
  try { return JSON.parse(txt); } catch { /* the model wrapped it */ }
  const m = String(txt || '').match(/\{[\s\S]*\}/);
  if (m) { try { return JSON.parse(m[0]); } catch { /* genuinely not JSON */ } }
  throw new Error('AI returned non-JSON');
}

const clean = (v: unknown, max = 600): string | null => {
  const s = String(v ?? '').trim();
  if (!s || /^(n\/?a|unknown|none|null)$/i.test(s)) return null;
  return s.slice(0, max);
};
const normCategory = (v: unknown): string | null => {
  const s = clean(v, 40)?.toLowerCase() ?? null;
  return s && CATS.includes(s) ? s : null;
};
// A served market is only useful if it resolves to something the matching engine indexes. Emirate
// names are canonicalised; anything else is kept verbatim as a country/region rather than dropped,
// because "we export to Oman" is a true and useful statement that no emirate list can hold.
const normMarkets = (arr: unknown): string[] => {
  if (!Array.isArray(arr)) return [];
  const out = new Set<string>();
  for (const raw of arr) {
    const s = String(raw ?? '').trim();
    if (!s) continue;
    const low = s.toLowerCase();
    const hit = EMIRATES.find((e) => low.includes(e.toLowerCase())
      || (e === 'Ras Al Khaimah' && /\brak\b/.test(low))
      || (e === 'Umm Al Quwain' && /\buaq\b/.test(low)));
    out.add(hit || s.slice(0, 60));
  }
  return [...out].slice(0, 12);
};

// Which of the six the supplier has actually given us. Drives the next question, and is returned so
// the portal can show progress without recomputing the rule in the browser.
const FIELDS = ['company_name', 'category', 'company_type', 'location', 'capability_summary', 'markets'] as const;
const fillState = (p: Record<string, unknown>) => {
  const filled = FIELDS.filter((f) => (f === 'markets' ? (p.markets as string[])?.length > 0 : p[f] != null));
  return { filled, missing: FIELDS.filter((f) => !filled.includes(f)) };
};

Deno.serve(observe('supplier_onboard', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    // Supplier-authed, like the rest of the portal. Onboarding deliberately does NOT require an
    // existing leads row — a supplier with no company yet is the whole point of this surface.
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || 'extract');
    if (action !== 'extract') return J({ error: 'unknown action' }, 400);

    const text = String(body.text || '').trim().slice(0, 6000);
    if (text.length < 2) return J({ error: 'nothing to extract' }, 400);

    const { data: keyRow } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
    if (!keyRow?.value) return J({ ok: false, error: 'smart engine not configured', fallback: true });

    // The turns so far, so a second message can complete a profile the first one started rather
    // than replacing it. Clipped: onboarding is short by design, and an unbounded history is an
    // unbounded bill.
    const history = Array.isArray(body.history) ? body.history.slice(-8) : [];
    const input = [
      ...history
        .filter((m: { role?: string; content?: string }) => m?.role === 'user' || m?.role === 'assistant')
        .map((m: { role: string; content: string }) => ({ role: m.role, content: String(m.content || '').slice(0, 2000) })),
      { role: 'user', content: text },
    ];

    let raw: Record<string, unknown>;
    try {
      const r = await fetch(GW, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          __secret: keyRow.value, fn: 'supplier_onboard', max: 900, temperature: 0.1,
          sys: EXTRACTION_PROMPT, response_format: 'json', input,
        }),
      });
      const d = await r.json();
      if (!r.ok || d?.ok === false) throw new Error(d?.detail || d?.error || 'ai_gateway error');
      raw = parseJson(d?.content || '{}');
    } catch (e) {
      // A model failure must not look like "the supplier told us nothing". It is reported as an
      // error with fallback:true so the portal keeps the typed text and offers the form instead.
      return J({ ok: false, error: String((e as Error)?.message || e), fallback: true });
    }

    // ── GROUNDING, ENFORCED HERE RATHER THAN HOPED FOR IN THE PROMPT ──────────────────────────
    // First run against staging, 8 Aug 2026: "we do curtain walling, shopfronts and cladding …
    // with our own fabrication shop" came back company_type "contractor". The supplier never said
    // that — the model reached for the nearest label. company_type drives matching and is shown to
    // customers, so a confident wrong answer is worse than an empty field the conversation can ask
    // about. The model must now quote the words that justify it, and the quote must actually be in
    // what the supplier wrote; an ungrounded type is dropped rather than trusted.
    const said = text.toLowerCase().replace(/\s+/g, ' ');
    const basis = clean(raw.company_type_basis, 200);
    const grounded = !!basis && said.includes(basis.toLowerCase().replace(/\s+/g, ' ').replace(/^["']|["']$/g, ''));
    const profile = {
      company_name: clean(raw.company_name, 160),
      category: normCategory(raw.category),
      company_type: grounded ? clean(raw.company_type, 60) : null,
      company_type_basis: grounded ? basis : null,
      location: clean(raw.location, 80),
      capability_summary: clean(raw.capability_summary, 1200),
      markets: normMarkets(raw.markets),
    };
    const { filled, missing } = fillState(profile);

    // Telemetry, not a profile write: how often extraction actually lands is the only way to know
    // whether this surface can replace the form. Failure to log must never fail the extraction.
    try {
      // `agent` is the NOT NULL column; there is no `actor`. The first version used `actor` and
      // the catch below swallowed the 42703 every time, so the one number that would show whether
      // this surface can replace the form was never recorded. A swallowed write looks exactly like
      // a feature nobody used.
      await admin.from('agent_actions').insert({
        agent: 'supplier_onboard', kind: 'supplier_onboard_extract', status: 'logged', risk: 'low',
        title: 'Onboarding extraction',
        detail: { filled: filled.length, missing, chars: text.length, by: email },
      });
    } catch { /* telemetry is not the product */ }

    return J({
      ok: true,
      profile,
      filled,
      missing,
      reply: clean(raw.reply, 600) || 'Thanks — tell me a little more about what your company makes or installs.',
      // The portal writes through create_company + save_profile. Said out loud in the payload so a
      // future reader does not go looking for a write path in here.
      write_path: 'supplier_api:create_company+save_profile',
    });
  } catch (e) {
    return J({ ok: false, error: String((e as Error)?.message || e), fallback: true });
  }
}));
