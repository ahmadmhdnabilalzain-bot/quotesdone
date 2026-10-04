// THE SEAT EXAM, THROUGH think(): the same questions and the same grade as scripts/eval/seat_qualification_exam.mjs, but
// each question goes through think() itself, so the planner first reads the question's trade and kind and retrieval is
// asked for that area (knowledge_lookup_goes_to_the_trade_first.sql). Seat: sales_engineer, 28 Sep 2026.
//
// WHAT IT SPENDS. Only the planner (decompose: the routine internal class) runs. The run is stopped at the synthesis
// phase, before any answer, verify or research call, so each item costs one decompose call and the free embedder.
// Under the model hold think() answers 'held' and this reports HELD per item: there is no live score until the lift.
//
// HOW AN ITEM PASSES. Every retrieval call think() made for the item is read (its own planned queries, the space it
// reads, the trade/kind it sent). PASS = in the first 5 rows of ANY of those calls there is an expected entry's
// English row whose excerpt (the 1,200 characters the seat sees) holds every expected fact: grade() of the exam.
//
//   deno run -A scripts/eval/seat_exam_through_think.ts --seat sales_engineer [--limit 10] [--out report.json]
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { think, defaultDeps, type ThinkDeps } from '../../supabase/functions/_shared/think.ts';

const REF = 'htdblwldjkcgjvmqkbeh';
const arg = (f: string) => { const i = Deno.args.indexOf(f); return i >= 0 ? Deno.args[i + 1] : null; };
const seat = arg('--seat') ?? 'sales_engineer';
const limit = Number(arg('--limit') ?? 1e9);
const home = Deno.env.get('USERPROFILE') ?? Deno.env.get('HOME') ?? '';
const mgmt = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? await Deno.readTextFile(`${home}/.supabase/access-token`)).trim();
const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: `Bearer ${mgmt}` } })).json();
const service = keys.find((k: { name: string }) => k.name === 'service_role')?.api_key;
if (!service) throw new Error('no service_role key from the management API');
const admin = createClient(`https://${REF}.supabase.co`, service, { auth: { persistSession: false } });

type Item = { id: string; checklist: string; q_en: string; expected_entry_ids: string[]; expected_facts: string[] };
const exam = JSON.parse(await Deno.readTextFile(`knowledge/exams/${seat}.json`)) as { items: Item[] };
const has = (t: unknown, f: string) => String(t ?? '').toLowerCase().includes(f.toLowerCase());
class Stop extends Error {}

const out: Record<string, unknown>[] = [];
let pass = 0, held = 0;
for (const it of exam.items.slice(0, limit)) {
  const live = defaultDeps(admin, 'seat_exam_through_think');
  const calls: { args: Record<string, unknown>; top: { id: string; excerpt: string }[] }[] = [];
  const deps: ThinkDeps = {
    ...live,
    llm: (phase, ...rest) => (phase === 'decompose' ? live.llm(phase, ...rest) : Promise.reject(new Stop('stopped before ' + phase))),
    rpc: async (fn, args) => {
      const r = await live.rpc(fn, args);
      if (/^fn_reason_retrieve/.test(fn)) calls.push({ args: { ...args, p_embedding: undefined, p_embedding_gte: undefined }, top: (Array.isArray(r.data) ? r.data : []).slice(0, 5) });
      return r;
    },
  };
  let status = 'stopped';
  try { status = (await think(deps, { seat: seat as never, surface: 'think.answer', question: it.q_en, subject: { fixture: true } as never })).status; }
  catch (e) { if (!(e instanceof Stop)) status = 'error: ' + (e as Error).message; }
  if (!calls.length) { held++; out.push({ id: it.id, status: status === 'stopped' ? 'no retrieval' : status }); continue; }
  const ok = calls.some((c) => c.top.some((r) => it.expected_entry_ids.includes(r.id) && it.expected_facts.every((f) => has(r.excerpt, f))));
  if (ok) pass++;
  out.push({ id: it.id, pass: ok, trade: calls[0].args.p_trade ?? null, kind: calls[0].args.p_kind ?? null, top: calls.map((c) => c.top.map((r) => r.id)) });
  console.log(`${it.id} ${ok ? 'PASS' : 'fail'} trade=${calls[0].args.p_trade ?? '-'} kind=${calls[0].args.p_kind ?? '-'}`);
}
const n = Math.min(limit, exam.items.length);
console.log(`${seat}: pass ${pass}/${n}; not run (held / no retrieval) ${held}`);
if (arg('--out')) await Deno.writeTextFile(arg('--out')!, JSON.stringify({ seat, pass, held, items: out }, null, 1));
