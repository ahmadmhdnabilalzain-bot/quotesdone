// learn_gaps — self-improving intake. Looks at inquiries matched to suppliers but with ZERO quotes,
// and per category asks an expert estimator which quote-critical attributes are commonly missing, then
// merges new fields into that category's intake checklist. Weekly cron + callable ({job:'run'}).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'learn_gaps', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
let PARSE_FAILS = 0, SAVE_FAILS = 0, LLM_CALLS = 0; let LAST_ERR = '';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });
const llmShared = makeLlm(SONNET_FIRST, { max: 1400, temperature: 0.2 }); // Sonnet-first for cost (fleet policy)
const CLOSED = ['completed', 'accepted', 'closed', 'cancelled'];

async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(txt: string) { try { return JSON.parse(txt); } catch { /* */ } const m = txt.match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch { /* */ } } return null; }
async function llm(_key: string, sys: string, user: string, max = 1400) {
  LLM_CALLS++;
  const c = await llmShared(sys, user, max);
  if (c === null) { LAST_ERR = 'openrouter call failed or returned no content'; throw new Error('openrouter error'); }
  return c;
}

const SYS = `You are a senior UAE estimator improving a quotation platform's intake. You are shown a set of customer briefs in ONE category that were sent to matched suppliers but received ZERO quotes — a strong signal the brief was missing something suppliers need to price without contacting the customer. You are also shown the category's CURRENT intake checklist.

Identify up to 3 quote-critical attributes that are (a) commonly missing or ambiguous across these briefs, (b) genuinely required to give a firm price, and (c) NOT already covered by the current checklist. Do not propose technical/engineering choices the supplier should decide, budget, or the customer's identity.

Return STRICT JSON ONLY: {"fields":[{"key":"snake_case","question":"short plain customer-facing question","type":"select|multiselect|number|text","options":["concrete option","Not sure"],"required":true,"reason":"why suppliers likely couldn't quote without it"}]}. If the briefs look complete and the zero quotes are for other reasons, return {"fields":[]}.`;

async function learnCategory(key: string, category: string, briefs: string[], currentFields: any[]) {
  const user = 'CATEGORY: ' + category + '\n\nCURRENT INTAKE CHECKLIST (JSON):\n' + JSON.stringify(currentFields) + '\n\nBRIEFS THAT GOT ZERO QUOTES (' + briefs.length + '):\n' + briefs.map((b, i) => (i + 1) + '. ' + b).join('\n');
  const raw = await llm(key, SYS, user);
  const j = parseJson(raw);
  if (j === null) { PARSE_FAILS++; LAST_ERR = 'LLM output for category ' + category + ' was not parseable JSON, treated as zero suggestions'; }
  const fields = (j && Array.isArray(j.fields)) ? j.fields.filter((f: any) => f && f.key && f.question) : [];
  return fields.slice(0, 3);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'learn_gaps');
    if (!__auth.ok) { await logRun('error', { categories_reviewed: 0, fields_added: 0 }, 'call rejected: wrong or missing inbound secret; intake checklists were not reviewed or improved'); return J({ error: 'forbidden' }, 403); }
    const key = await sec('openrouter_api_key'); if (!key) { await logRun('error', { categories_reviewed: 0, fields_added: 0 }, 'openrouter_api_key missing from app_secrets: no intake checklist learning ran, categories with zero-quote briefs keep asking customers the same incomplete questions'); return J({ error: 'AI not configured' }, 200); }
    const maxCats = Math.max(1, Math.min(8, Number(body.max_categories) || 4));
    const minCases = Math.max(1, Number(body.min_cases) || 2);
    const sinceDays = Math.max(2, Number(body.since_days) || 3);
    const olderThan = new Date(Date.now() - sinceDays * 864e5).toISOString();
    const floor = new Date(Date.now() - 45 * 864e5).toISOString();

    const { data: inqs } = await admin.from('inquiries').select('id,category,summary,spec,status,created_at').not('status', 'in', '(' + CLOSED.join(',') + ')').lt('created_at', olderThan).gte('created_at', floor).not('category', 'is', null).limit(1500);
    // H15 (OS audit): was 2 count queries PER inquiry (~3,000 sequential round-trips at the 1,500 cap).
    // Replace with a few chunked bulk lookups of which inquiries have >=1 match / >=1 quote, then filter in memory.
    const ids = (inqs || []).map((i: any) => i.id);
    const hasMatch = new Set<any>(); const hasQuote = new Set<any>();
    for (let i = 0; i < ids.length; i += 200) {
      const chunk = ids.slice(i, i + 200);
      const [{ data: mr }, { data: qr }] = await Promise.all([
        admin.from('inquiry_matches').select('inquiry_id').in('inquiry_id', chunk),
        admin.from('quotes').select('inquiry_id').in('inquiry_id', chunk),
      ]);
      for (const r of (mr || [])) hasMatch.add(r.inquiry_id);
      for (const r of (qr || [])) hasQuote.add(r.inquiry_id);
    }
    const byCat: Record<string, string[]> = {};
    for (const inq of (inqs || [])) {
      const cat = String(inq.category || '').trim(); if (!cat) continue;
      if (!hasMatch.has(inq.id) || hasQuote.has(inq.id)) continue;
      const brief = String(inq.summary || '') + (inq.spec ? (' | specs: ' + JSON.stringify(inq.spec)) : '');
      (byCat[cat] = byCat[cat] || []).push(brief.slice(0, 600));
    }

    const cats = Object.entries(byCat).filter(([, arr]) => arr.length >= minCases).sort((a, b) => b[1].length - a[1].length).slice(0, maxCats);
    const results: any[] = [];
    for (const [cat, briefs] of cats) {
      try {
        const { data: cs } = await admin.from('category_specs').select('category,label,fields').eq('category', cat).maybeSingle();
        const currentFields = Array.isArray(cs?.fields) ? cs!.fields : [];
        const have = new Set(currentFields.map((f: any) => String(f.key || '').toLowerCase()));
        const proposed = await learnCategory(key, cat, briefs.slice(0, 10), currentFields);
        const fresh = proposed.filter((f: any) => !have.has(String(f.key).toLowerCase()));
        if (!fresh.length) { results.push({ category: cat, zero_quote_cases: briefs.length, added: 0 }); continue; }
        const clean = fresh.map((f: any) => ({ key: String(f.key).slice(0, 60), question: String(f.question).slice(0, 240), type: ['select', 'multiselect', 'number', 'text'].includes(f.type) ? f.type : 'text', options: Array.isArray(f.options) ? f.options.map((o: any) => String(o)).slice(0, 8) : [], required: f.required !== false, source: 'learned' }));
        const merged = currentFields.concat(clean).slice(0, 22);
        if (cs) { const _u = await admin.from('category_specs').update({ fields: merged }).eq('category', cat); if (_u && (_u as any).error) { SAVE_FAILS++; LAST_ERR = 'category_specs update failed for ' + cat + ': ' + String((_u as any).error?.message || ''); } }
        else { const _i = await admin.from('category_specs').insert({ category: cat, label: cat, fields: merged }); if (_i && (_i as any).error) { SAVE_FAILS++; LAST_ERR = 'category_specs insert failed for ' + cat + ': ' + String((_i as any).error?.message || ''); } }
        const _a = await admin.from('agent_actions').insert({ agent: 'learn', kind: 'checklist_improved', status: 'pending', risk: 'low', title: 'Intake checklist improved for "' + cat + '" (+' + clean.length + ' field(s) from ' + briefs.length + ' zero-quote briefs)', recommendation: 'review the added questions; remove any that are not truly needed', target_table: 'category_specs', target_id: cat, detail: { added: clean, reasons: fresh.map((f: any) => f.reason).filter(Boolean) } });
        if (_a && (_a as any).error) { SAVE_FAILS++; LAST_ERR = 'agent_actions insert failed for ' + cat + ': ' + String((_a as any).error?.message || ''); }
        results.push({ category: cat, zero_quote_cases: briefs.length, added: clean.length, keys: clean.map((f: any) => f.key) });
      } catch (e) { LAST_ERR = 'category ' + cat + ' failed: ' + String((e as Error)?.message || e); results.push({ category: cat, error: String((e as Error)?.message || e) }); }
    }
    const errored = results.filter((r) => r.error).length;
    const added = results.reduce((a: number, r: any) => a + (Number(r.added) || 0), 0);
    let note: string;
    if (cats.length === 0) { note = 'no category had enough matched-but-zero-quote inquiries to review; nothing learned and nothing failed'; }
    else if (errored === cats.length) { note = 'NO intake checklist learning happened this run: the model call failed for all ' + cats.length + ' categories reviewed, so categories whose briefs get zero quotes keep collecting the same incomplete information'; }
    else if (PARSE_FAILS > 0 && added === 0) { note = 'reviewed ' + cats.length + ' zero-quote categories but added NOTHING: the model returned unparseable output for ' + PARSE_FAILS + ' of them, which is silently treated as "no suggestions" — intake checklists are unchanged and may still be missing quote-critical questions'; }
    else if (added === 0) { note = 'reviewed ' + cats.length + ' zero-quote categories; the model proposed no new quote-critical fields, so checklists are unchanged'; }
    else { note = 'reviewed ' + cats.length + ' zero-quote categories and added ' + added + ' new intake field(s)' + (errored ? ('; ' + errored + ' category/categories failed outright') : '') + (PARSE_FAILS ? ('; ' + PARSE_FAILS + ' model response(s) were unparseable and silently contributed nothing') : ''); }
    if (SAVE_FAILS > 0) { note += ' | ' + SAVE_FAILS + ' write(s) to category_specs/agent_actions failed, so learned fields may not have been saved'; }
    if (LAST_ERR) { note += ' | last error: ' + LAST_ERR; }
    const bad = SAVE_FAILS > 0 || (cats.length > 0 && errored === cats.length) || (cats.length > 0 && PARSE_FAILS > 0 && added === 0);
    await logRun(bad ? 'error' : 'ok', { categories_reviewed: cats.length, fields_added: added, categories_errored: errored, llm_calls: LLM_CALLS, parse_failures: PARSE_FAILS, save_failures: SAVE_FAILS }, note);
    return J({ ok: true, categories_reviewed: cats.length, results });
  } catch (e) { await logRun('error', { categories_reviewed: 0, fields_added: 0, llm_calls: LLM_CALLS, parse_failures: PARSE_FAILS }, 'learn_gaps crashed before completing; no intake checklists were improved this run: ' + String((e as Error)?.message || e)); return J({ error: String((e as Error)?.message || e) }, 500); }
});
