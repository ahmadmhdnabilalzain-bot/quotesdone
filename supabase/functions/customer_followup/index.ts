// customer_followup — the one-tap answer to "did you hire, and how was the supplier?" (customer_support,
// founder_instruction 1013 item 1). Served to the customer on quotesdone.ae/u/followup (src/app/u/followup),
// because Supabase serves an edge function's HTML as text/plain.
//   GET  ?t=<token>  shows the question (fn_customer_followup_view). Never writes.
//   POST ?t=<token>  records the answer (fn_customer_followup_answer): the outcome on the seat that decided, and
//                    the rating as the reveal's one review.
// No credential: the token is the customer's own, from the e-mail fn_customer_support_followup_tick sent.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { messagePage, parseAnswer, questionPage, UUID_RE, type View } from './page.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const H = { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' };
const html = (body: string, status = 200) => new Response(body, { status, headers: H });

Deno.serve(observe('customer_followup', async (req) => {
  const token = (new URL(req.url).searchParams.get('t') || '').trim();
  if (!UUID_RE.test(token)) return html(messagePage('en', 'invalid'), 400);
  const { data: view, error } = await admin.rpc('fn_customer_followup_view', { p_token: token });
  const v = (view || { ok: false }) as View;
  if (error) return html(messagePage('en', 'error'), 500);
  if (!v.ok) return html(messagePage('en', 'invalid'), 404);
  const lang = v.lang === 'ar' ? 'ar' : 'en';
  if (req.method === 'GET') return html(questionPage(v, token));
  if (req.method !== 'POST') return html(messagePage(lang, 'invalid'), 405);
  const a = parseAnswer(new URLSearchParams(await req.text()));
  if (!a) return html(questionPage(v, token), 400);
  const { data: r, error: e2 } = await admin.rpc('fn_customer_followup_answer',
    { p_token: token, p_hired: a.hired, p_stars: a.stars, p_comment: a.comment });
  if (e2 || !r?.ok) return html(messagePage(lang, 'error'), 500);
  return html(messagePage(lang, r.already ? 'already' : 'thanks'));
}));
