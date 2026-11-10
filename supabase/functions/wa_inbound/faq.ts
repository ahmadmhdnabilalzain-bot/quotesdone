// faq.ts - the approved FAQ as wa_inbound reads it: the in-region question embedding (one session per worker) and the
// lexical retrieval that grounds the reply. Moved out of index.ts unchanged (9 Nov 2026, customer_support).
import { admin } from './shared.ts';

// THE QUESTION IS UNDERSTOOD, NOT ONLY MATCHED (instruction 763). Measured 22 Sep 2026: wa_inbound
// called fn_faq_answer(p_text) with no embedding, so WhatsApp answered only when the stemmed words
// lined up. The site assistant's path (ai_gateway try_faq) passes a gte-small vector. This is the same
// model: Supabase.ai in-region, free, never OpenRouter. Module scope so one worker builds one session.
// If it fails the vector is null and fn_faq_answer answers by keyword alone, exactly as before.
// deno-lint-ignore no-explicit-any
let _emb: any = null;
export async function embedQuestion(text: string): Promise<string | null> {
  try {
    // deno-lint-ignore no-explicit-any
    if (_emb === null) _emb = new (globalThis as any).Supabase.ai.Session('gte-small');
    const v = await _emb.run(String(text).slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
    return Array.isArray(v) && v.length === 384 ? '[' + v.join(',') + ']' : null;
  } catch (e) {
    console.error('wa_inbound embed: gte-small failed:', String((e as Error)?.message || e).slice(0, 300));
    return null;
  }
}
// The cosine floor for a CORROBORATED semantic answer. fn_faq_answer only accepts a neighbour that
// also shares the asker's own words (see the_whatsapp_menu_answers_like_a_senior_member_of_staff.sql);
// measured 22 Sep: "how much do you charge" -> "What are the platform fees?" at 0.8516, while the
// unrelated "what is the weather in paris" peaks at 0.7148 over the whole FAQ.
export const FAQ_MIN_SIMILARITY = 0.84;
function tok(s: string): string[] { return (String(s || '').toLowerCase().match(/[a-z0-9؀-ۿ]{3,}/g) || []); }

export async function retrieveFaq(q: string): Promise<{ ctx: string; ids: number[] }> {
  const { data } = await admin.from('company_faq').select('id,question,answer,tags').eq('status', 'approved').eq('public', true);
  const qt = tok(q);
  const scored = (data || []).map((f: any) => { const hay = tok(f.question + ' ' + f.answer + ' ' + ((f.tags || []).join(' '))); let sc = 0; for (const t of qt) if (hay.includes(t)) sc++; return { f, sc }; })
    .sort((a, b) => b.sc - a.sc).slice(0, 8).filter((x) => x.sc > 0);
  return { ctx: scored.map((x: any) => `Q: ${x.f.question}\nA: ${x.f.answer}`).join('\n\n'), ids: scored.map((x: any) => x.f.id) };
}
