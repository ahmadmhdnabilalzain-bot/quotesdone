// scratch probe (not committed): what does the seat's ml-space retrieval return for a question?
import { createClient } from 'jsr:@supabase/supabase-js@2';
const REF = 'htdblwldjkcgjvmqkbeh';
const home = Deno.env.get('USERPROFILE')!;
const mgmt = (await Deno.readTextFile(`${home}/.supabase/access-token`)).trim();
const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: `Bearer ${mgmt}` } })).json();
const service = keys.find((k: { name: string }) => k.name === 'service_role')?.api_key;
Deno.env.set('SUPABASE_URL', `https://${REF}.supabase.co`); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', service);
const admin = createClient(`https://${REF}.supabase.co`, service, { auth: { persistSession: false } });
const { embedQueryMlRemote } = await import('../../supabase/functions/_shared/ml_embed_client.ts');
const { embedLine } = await import('../../supabase/functions/_shared/gte_embed.ts');
const [seat, ...q] = Deno.args; const question = q.join(' ');
const ml = await embedQueryMlRemote(admin as never, question, 'knowledge_exam', 15000);
const gte = await embedLine(question).catch(() => null);
const { data, error } = await admin.rpc('fn_reason_retrieve_ml', { p_seat: seat, p_embedding: ml, p_embedding_gte: gte, p_k: 6, p_own: null, p_trade: null, p_kind: null, p_area: null });
console.log(error?.message ?? '', ml ? 'ml ok' : 'NO ML VECTOR', gte ? 'gte ok' : 'NO GTE');
for (const r of (Array.isArray(data) ? data : [])) console.log(r.source, r.id, (r.similarity ?? '').toString().slice(0, 5), String(r.title ?? '').slice(0, 80));
