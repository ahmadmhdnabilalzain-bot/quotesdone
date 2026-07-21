import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'match', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}

// SECURITY FIX 18-19 Jul 2026 --------------------------------------------------------------
// match_suppliers_kw returns supplier company_name, phone, email, whatsapp and website. This
// endpoint previously returned those rows VERBATIM to any caller holding a Supabase user JWT,
// with body.limit passed straight through unclamped.
//
//   1. limit is clamped to MAX_LIMIT.
//   2. Contact/identity columns are redacted for JWT callers. Internal callers authenticating
//      with inbound_secret (route_inquiry, dispatch_inquiry) still get full rows, because they
//      need contact details to notify a matched supplier.
//   3. FREE-TEXT SCRUB. capability_summary is LLM-generated prose that opens with the company
//      name verbatim ("Emirates Prestige Flooring LLC is a UAE-based flooring supplier...").
//      Dropping the phone/email columns while leaving that text in place still discloses
//      identity and still defeats the paid-reveal model, so free text is scrubbed too.
//
// WHY THE SCRUB MATCHES ON WORD PAIRS, NOT SINGLE WORDS:
// UAE company names routinely embed their own trade - "... Flooring LLC", "... Joinery LLC",
// "... Contracting LLC". A single-token rule therefore deletes the services/products text of
// every flooring company purely because the word "flooring" appears in it, which destroys the
// search result for no privacy gain: nobody is identified by the word "flooring". A CONSECUTIVE
// WORD PAIR from the registered name ("Prestige Flooring", "Emirates Prestige") is identifying;
// a lone trade word is not. So: scrub the full name, the name minus legal suffix, and every
// adjacent word pair; then drop the field only if a word pair somehow survives. Fail closed on
// the identifying case, stay useful on the generic one.
const MAX_LIMIT = 25;
const SAFE_FIELDS = new Set(['id', 'supplier_id', 'lead_id', 'score', 'match_score', 'similarity', 'rank', 'sector', 'category', 'emirate', 'in_emirate', 'service_emirates', 'business_role', 'rating', 'app_rating', 'reviews', 'app_reviews', 'verified', 'capability_summary', 'services', 'products']);
const FREE_TEXT_FIELDS = new Set(['capability_summary', 'services', 'products']);

function escapeRe(s: string) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

// Adjacent word pairs from the company name, e.g. "Emirates Prestige Flooring LLC"
// -> ["Emirates Prestige", "Prestige Flooring", "Flooring LLC"]
function namePairs(name: string): string[] {
  const toks = String(name || '').replace(/[^A-Za-z0-9 ]/g, ' ').split(/\s+/).filter((t) => t.length > 1);
  const pairs: string[] = [];
  for (let i = 0; i + 1 < toks.length; i++) pairs.push(toks[i] + ' ' + toks[i + 1]);
  return pairs;
}

// Returns scrubbed text, or null if the field must be dropped (identity survived the scrub).
function scrubText(txt: unknown, companyName: string): string | null {
  if (txt === null || txt === undefined) return txt as null;
  let out = String(txt);
  const full = String(companyName || '').trim();
  if (full.length > 2) {
    const bare = full.replace(/[\s,]+(l\.?l\.?c\.?|fze|fzc|fz-llc|est\.?|establishment|co\.?|general trading|trading)\s*$/i, '').trim();
    // Longest first so the full name is consumed before its constituent pairs.
    const variants = [full, bare, ...namePairs(full)].filter((v) => v.length > 3)
      .sort((a, b) => b.length - a.length);
    for (const v of variants) out = out.replace(new RegExp(escapeRe(v), 'gi'), 'This supplier');
    // Collapse the artefact of adjacent replacements ("This supplier This supplier is ...").
    out = out.replace(/(This supplier)(\s+This supplier)+/gi, 'This supplier').replace(/\s{2,}/g, ' ').trim();
    // Backstop: an identifying word pair must not survive.
    const low = out.toLowerCase();
    for (const p of namePairs(full)) if (p.length > 3 && low.includes(p.toLowerCase())) return null;
  }
  return out;
}

function redact(rows: any[]) {
  return (rows || []).map((r) => {
    const out: Record<string, unknown> = {};
    const company = String(r?.company_name || '');
    for (const k of Object.keys(r || {})) {
      if (!SAFE_FIELDS.has(k)) continue;
      if (FREE_TEXT_FIELDS.has(k)) {
        const scrubbed = scrubText(r[k], company);
        if (scrubbed !== null) out[k] = scrubbed; // null => drop the field entirely
      } else out[k] = r[k];
    }
    return out;
  });
}

// BUG FIX 19 Jul 2026 ----------------------------------------------------------------------
// public.match_suppliers_kw exists in TWO overloads, both with every argument defaulted:
//   (p_keywords, p_category, p_emirate, p_role, p_min_rating, p_limit)            -- 6 args
//   (p_keywords, p_category, p_emirate, p_role, p_min_rating, p_limit, p_multi)   -- 7 args
// Calling it with only the six shared names matches BOTH candidates, so PostgREST refuses with
// PGRST203 "Could not choose the best candidate function" and this endpoint returned HTTP 500 to
// every caller, including the internal route_inquiry / dispatch_inquiry path. Supplier matching
// was failing in a way that reads downstream as "no suppliers found".
// Passing p_multi explicitly disambiguates to the 7-arg overload. Do NOT remove this argument
// without first dropping one of the two overloads.
const P_MULTI_DEFAULT = false;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const body = await req.json().catch(() => ({} as any));
    let ok = false; let internal = false;
    const { data: s, error: secErr } = await admin.from('app_secrets').select('value').eq('key', 'inbound_secret').maybeSingle();
    if (secErr) { await logRun('error', { suppliers: 0, secret_lookup_ok: 0 }, 'match could not read the inbound_secret from app_secrets (' + String(secErr.message).slice(0, 140) + '), so secret-authenticated callers are rejected regardless of correctness. Supplier matching returns nothing for an auth-infrastructure reason, not because no supplier matches.'); }
    if (s?.value && body?.__secret === s.value) { ok = true; internal = true; }
    if (!ok) {
      const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
      if (jwt) { try { const { data: { user } } = await admin.auth.getUser(jwt); if (user) ok = true; } catch (_e) { /* */ } }
    }
    if (!ok) {
      if (body?.__secret !== undefined) { await logRun('error', { suppliers: 0, bad_secret: 1 }, 'match rejected a caller that presented a wrong inbound secret (401). Any internal component relying on this call just received zero suppliers for an authentication reason, not because no supplier matches the request — that absence will look like a genuine coverage gap.'); }
      return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: cors });
    }

    const askedLimit = Number(body.limit ?? 8);
    const limit = Math.max(1, Math.min(Number.isFinite(askedLimit) ? askedLimit : 8, MAX_LIMIT));
    const clamped = Number.isFinite(askedLimit) && askedLimit > MAX_LIMIT;

    const { data, error } = await admin.rpc('match_suppliers_kw', {
      p_keywords: body.keywords ?? [],
      p_category: body.category ?? null,
      p_emirate: body.emirate ?? null,
      p_role: body.role ?? null,
      p_min_rating: body.min_rating ?? null,
      p_limit: limit,
      p_multi: body.multi ?? P_MULTI_DEFAULT,
    });
    if (error) { await logRun('error', { suppliers: 0, zero_matches_genuine: 0, rpc_ok: 0 }, 'match returned no suppliers because the match_suppliers_kw retrieval query failed (' + String(error.message).slice(0, 140) + '), not because no supplier matches — the caller sees an empty supplier set that is indistinguishable from a genuine coverage gap.'); return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: cors }); }
    const _n = data?.length ?? 0;
    const payload = internal ? (data ?? []) : redact(data ?? []);
    const _dropped = internal ? 0 : (payload as any[]).filter((p) => !('capability_summary' in p)).length;

    if (clamped && !internal) await logRun('error', { suppliers: _n, asked_limit: askedLimit, clamped_to: MAX_LIMIT, redacted: true, summaries_dropped: _dropped }, 'A signed-in (non-internal) caller requested ' + askedLimit + ' supplier matches; clamped to ' + MAX_LIMIT + ', contact fields redacted and free text scrubbed of supplier names. A large page request from a user JWT is the shape of a supplier-list scrape - worth checking who called.');
    else await logRun('ok', { suppliers: _n, zero_matches_genuine: _n === 0 ? 1 : null, rpc_ok: 1, internal, redacted: !internal, summaries_dropped: _dropped, category: body.category ?? null, emirate: body.emirate ?? null }, _n === 0 ? 'match ran cleanly and genuinely found zero suppliers for these criteria (category=' + String(body.category ?? '-') + ', emirate=' + String(body.emirate ?? '-') + '). This is a real supply coverage gap, not a failure.' : ('match returned ' + _n + ' candidate supplier(s) for category=' + String(body.category ?? '-') + ', emirate=' + String(body.emirate ?? '-') + (internal ? ' (internal caller, full detail).' : ' (redacted: contact fields withheld; ' + _dropped + ' summary field(s) dropped because a supplier-name word pair survived scrubbing).')));
    return new Response(JSON.stringify({ count: _n, suppliers: payload, redacted: !internal }), { headers: cors });
  } catch (e) {
    await logRun('error', { suppliers: 0, zero_matches_genuine: 0, unhandled_exception: 1 }, 'match threw an unhandled exception and returned 500: ' + String(e).slice(0, 200) + ' — the caller received no suppliers for an internal reason, not because no supplier matches.');
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: cors });
  }
});
