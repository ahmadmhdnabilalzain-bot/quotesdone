#!/usr/bin/env node
// EVAL B: THE T3a SALES INTERVIEW AND ITS VOICE (it_engineer, cost seat; 10 Nov 2026; rulings 1572 and 1571; design
// docs/reports/2026-11-10-design-model-routing.md section 5c). It gates
// scripts/sql/the_inquiry_interview_moves_to_the_model_eval_b_passes.sql. NOT RUN on 10 Nov 2026: the intake flow it drives was
// being rebuilt by another session; run it against the rebuilt intake, before that file is applied.
//
// WHAT RUNS. 7 scripted inquiries through the DEPLOYED inquiry_intake (or --local <url>, the function served from a branch),
// as ZZ DEMO customers (scripts/e2e/fixtures.mjs: @example.invalid, the fixture mobile block), inside a tagged rehearsal
// window whose cap is ALSO enforced here before every turn (tagged ai_cost_log spend + the next turn's estimate):
//   six of 20 customer turns: English x2, Gulf, Egyptian, Levantine, Gulf with Arabizi; one of 50 customer turns (100 messages)
//   in mixed Gulf and Arabizi. Each plants >= 3 facts at turn 2 and never repeats them; 8 expert probes are spread over the set.
// WHICH MODEL. The interview runs on whatever model_policy routes inquiry_qualification_conversation to at run time, and the
// report names it (ai_cost_log.model_used for the run's tag). The control is today's route (Sonnet 5.5) on --only en1,gulf. The
// candidate is run against a branch function served locally (--local) whose interview call names a class routed to the
// candidate (customer_communication = Luna Pro), or after the gated file is applied with the window open; never by changing
// production routing for a test.
//
// CODE GRADES (pass, design 5c): a planted turn-2 fact re-asked after it was given <= 1 across the set; every planted fact in the
// final brief.details; >= 6 of 7 inquiries reach `ready` with every required checklist key; JSON valid on 100% of turns (HTTP 200
// with a parseable body); every turn within turn_clock; the 100-message run loses no fact. The expert probes (>= 7 of 8, by
// keywords here and by the judge), the register (>= 90% of judged turns) and judge mean >= Sonnet control - 0.5 are graded by
// eval_b_judge.ts over the transcripts this writes (a judge of another family than the interview's model).
//
//   QD_FIXTURES=1 node scripts/eval/model_routing/eval_b.mjs --cap 1.20 [--only en1,lev] [--local <url>] [--out <file.json>]
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { openRun, closeRun, makeDemoCustomer, call, read } from '../../e2e/fixtures.mjs';

const arg = (k) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : null);
const CAP = Number(arg('--cap') ?? '1.20');
const ONLY = arg('--only')?.split(',') ?? null;
const LOCAL = arg('--local');
const OUT = arg('--out') ?? 'docs/reports/model-routing-evals-2026-11-10/eval_b.json';
const TURN_EST = 0.02;   // USD, one interview turn plus its voice on Sonnet (the dearest arm)
const TURN_CLOCK_MS = 90_000;

// ── the scripted inquiries ───────────────────────────────────────────────────────────────────────────────────
// planted: { key, said, find } - `find` must appear in the final brief.details; `reask` matches a question asking it again.
const P = (key, find, reask) => ({ key, find, reask });
const fill = (lines, n) => Array.from({ length: n }, (_, i) => lines[i % lines.length]);
const INQUIRIES = [
  { id: 'en1', lang: 'en', opening: 'Hi, I need gypsum partitions for my villa', turn2: 'It is a villa in Al Barsha, ceiling height is 3.2 m, budget about 15k AED',
    planted: [P('location', 'Barsha', /where is|location|which area/i), P('ceiling', '3.2', /ceiling height|how high/i), P('budget', '15', /budget/i)],
    probes: [{ at: 5, said: 'Can I use MDF for the partition in the bathroom?', want: [/moisture|humid|wet/i, /pvc|cement board|moisture.resistant|wrap/i] }],
    filler: ['about 40 square metres in total', 'two rooms and the corridor', 'standard finish, painted white', 'next month if possible', 'no drawings, I can send photos', 'yes that is fine'] },
  { id: 'en2', lang: 'en', opening: 'We need AC installation for a new office', turn2: 'Office in JLT Cluster D, 3 rooms each 4 x 5 m, we want split units',
    planted: [P('location', 'JLT', /where|location|area/i), P('rooms', '4', /room size|dimensions|how big/i), P('system', 'split', /type of (ac|system)|split or/i)],
    probes: [{ at: 4, said: 'How many tons do I need for a 4 x 5 m room?', want: [/1(\.5)?\s*(ton|tr)|1\.5|btu/i] }, { at: 9, said: 'Is inverter worth it?', want: [/inverter/i, /saving|efficien|electric/i] }],
    filler: ['ceiling is false ceiling 2.7 m', 'we work 9 to 6', 'brand open, good quality', 'within 3 weeks', 'yes', 'no ducted'] },
  { id: 'gulf', lang: 'ar', opening: 'السلام عليكم، أبي أبلط الحوش برا', turn2: 'البيت في الخوانيج، المساحة 120 متر مربع، وأبي البلاط يتحمل الشمس',
    planted: [P('location', 'الخوانيج', /وين|الموقع|المنطقة/), P('area', '120', /كم المساحة|المساحة/), P('sun', 'الشمس', /الشمس/)],
    probes: [{ at: 6, said: 'وش أفضل بلاط للحوش عشان ما يزلق؟', want: [/انزلاق|R11|R12|خشن|مضاد/i] }],
    filler: ['زين', 'أبي لون فاتح', 'الأرض جاهزة', 'خلال شهر', 'إن شاء الله', 'تمام'] },
  { id: 'egy', lang: 'ar', opening: 'عايز أعمل حمام جديد في الشقة', turn2: 'الشقة في المرسى دبي، الحمام 2 في 3 متر، وعايز بلاط سيراميك',
    planted: [P('location', 'المرسى', /فين|الموقع|المنطقة/), P('size', '3', /مقاس|المساحة|كام متر/), P('tile', 'سيراميك', /نوع البلاط/)],
    probes: [{ at: 5, said: 'أحط جبس بورد عادي ولا أسمنت بورد في الحمام؟', want: [/أسمنت|مقاوم للرطوبة|cement/i] }],
    filler: ['تمام', 'عايز دش مش بانيو', 'اللون أبيض', 'كمان شهر', 'ماشي', 'أيوه'] },
  { id: 'lev', lang: 'ar', opening: 'مرحبا، بدي قواطع ألمنيوم وزجاج للمكتب', turn2: 'المكتب بالبزنس باي، طول القاطع 8 متر وارتفاعه 2.8، وبدي زجاج سيكوريت',
    planted: [P('location', 'البزنس باي', /وين|الموقع|المنطقة/), P('length', '8', /طول|قديش الطول/), P('glass', 'سيكوريت', /نوع الزجاج/)],
    probes: [{ at: 7, said: 'شو الفرق بين زجاج سيكوريت والزجاج العادي للقواطع؟', want: [/مقسّى|مقسى|tempered|أمان|يتكسر/i] }],
    filler: ['تمام', 'لون الألمنيوم أسود', 'في باب واحد', 'خلال أسبوعين', 'يعطيك العافية', 'أكيد'] },
  { id: 'arabizi', lang: 'ar', opening: 'hala, abi 7ad ysawi lee kitchen cabinets', turn2: 'el bait fi Mirdif, el kitchen 3.5 m tool, w abi el khashab MDF',
    planted: [P('location', 'Mirdif', /where|location|وين/i), P('length', '3.5', /length|طول/i), P('material', 'MDF', /material|نوع الخشب/i)],
    probes: [{ at: 6, said: 'MDF zain 7ag el kitchen ya3ni ma ytkharab ma3 el may?', want: [/moisture|رطوبة|MR|HMR|water/i] }],
    filler: ['ok zain', 'abi lon abyath', 'ma fee drawings', 'b3d shahar', 'inshallah', 'tamam'] },
  { id: 'long100', lang: 'ar', turns: 50, opening: 'هلا، عندي فيلا جديدة وأبي أشطب الداخل كامل', turn2: 'الفيلا في العوير، 4 غرف، السقف 3.5 متر، والميزانية تقريباً 300 ألف',
    planted: [P('location', 'العوير', /وين|الموقع|المنطقة|where/i), P('rooms', '4', /كم غرفة|عدد الغرف|how many rooms/i), P('ceiling', '3.5', /ارتفاع السقف|ceiling/i), P('budget', '300', /الميزانية|budget/i)],
    probes: [{ at: 30, said: 'el gypsum ceiling fe el 7amam ok wala la?', want: [/moisture|رطوبة|مقاوم|MR|cement/i] }, { at: 41, said: 'شو أحسن عازل للسطح؟', want: [/عزل|membrane|بولي|foam|bitumen|بيتومين/i] }],
    filler: ['زين', 'ok', 'أبي الأرضيات رخام', 'el abwab khashab', 'الدهان لون فاتح', 'yalla', 'إن شاء الله', 'tamam', 'المطبخ مفتوح', 'abi spotlights'] },
];
const scriptOf = (q) => {
  const n = q.turns ?? 20;
  const t = [q.opening, q.turn2, ...fill(q.filler, n - 2)];
  for (const p of q.probes) t[p.at - 1] = p.said;
  return t;
};

// ── the run ───────────────────────────────────────────────────────────────────────────────────────────────
const run = await openRun({ label: 'eval-b-model-routing', capUsd: CAP, minutes: 120 });
const tag = run.tag;
const spent = async () => Number((await read(`select coalesce(sum(coalesce(cost_usd_reported, cost_aed / 3.6725)), 0)::float8 s from public.ai_cost_log where e2e_run_tag = '${tag}'`))[0].s);
const results = []; let stopped = null;
const intake = async (jwt, body) => {
  if (!LOCAL) return call('inquiry_intake', jwt, body, TURN_CLOCK_MS + 30_000);
  const { keys, internalCred } = await import('../../lib/demo_factory.mjs');
  const { ANON } = await keys();
  const r = await fetch(LOCAL, { method: 'POST', signal: AbortSignal.timeout(TURN_CLOCK_MS + 30_000), headers: { apikey: ANON, Authorization: 'Bearer ' + jwt,
    'Content-Type': 'application/json', 'x-qd-e2e-run': tag, 'x-qd-e2e-secret': await internalCred() }, body: JSON.stringify(body) });
  const text = await r.text(); let json = null; try { json = JSON.parse(text); } catch { /* the body is the finding */ }
  return { status: r.status, json };
};
try {
  for (const q of INQUIRIES.filter((x) => !ONLY || ONLY.includes(x.id))) {
    const cust = await makeDemoCustomer(run, { locale: q.lang });
    const turns = []; let intakeId = null; let last = {};
    for (const [i, text] of scriptOf(q).entries()) {
      const s = await spent();
      if (s + TURN_EST >= CAP) { stopped = `spend cap: USD ${s.toFixed(4)} spent + ${TURN_EST} would reach USD ${CAP}`; break; }
      const t0 = Date.now();
      const r = await intake(cust.jwt, { ...(intakeId ? { intake_id: intakeId } : {}), text, email: cust.email });
      const ms = Date.now() - t0;
      last = r.json || {};
      intakeId = last.intake_id || intakeId;
      const reply = String(last.reply ?? last.message ?? last.text ?? '');
      const asked = [String(last.next_question?.text ?? ''), ...((last.questions || []).map((x) => String(x?.text ?? x)))].join(' | ');
      turns.push({ n: i + 1, said: text, http: r.status, json_ok: r.status === 200 && !!r.json, ms, status: last.status ?? null, reply, asked,
        missing_keys: last.missing_keys || [] });
      if (last.status === 'ready') break;
    }
    // what the intake holds at the end: brief.details (the request it would send)
    const row = intakeId ? (await read(`select status, brief from public.inquiry_intake where id = '${String(intakeId).replace(/[^0-9a-f-]/gi, '')}'`))[0] ?? {} : {};
    const details = JSON.stringify(row.brief?.details ?? row.brief ?? {});
    const after2 = turns.slice(2);
    const reasked = q.planted.filter((p) => after2.some((t) => p.reask.test(t.asked) || p.reask.test(t.reply))).map((p) => p.key);
    const probes = q.probes.map((p) => { const t = turns.find((x) => x.n === p.at); return { at: p.at, said: p.said, reply: t?.reply ?? '', met: !!t && p.want.every((re) => re.test(t.reply + ' ' + t.asked)) }; });
    results.push({ id: q.id, lang: q.lang, turns, final_status: row.status ?? last.status ?? null, details,
      planted_missing: q.planted.filter((p) => !details.includes(p.find)).map((p) => p.key), reasked, probes,
      json_ok_pct: 100 * turns.filter((t) => t.json_ok).length / Math.max(1, turns.length), over_clock: turns.filter((t) => t.ms > TURN_CLOCK_MS).length,
      models: (await read(`select distinct model_used from public.ai_cost_log where e2e_run_tag = '${tag}' and fn = 'inquiry_intake'`)).map((x) => x.model_used) });
    console.log(`${q.id}: ${turns.length} turns, ${results.at(-1).final_status}, missing [${results.at(-1).planted_missing}], re-asked [${reasked}], probes ${probes.filter((p) => p.met).length}/${probes.length}`);
    if (stopped) break;
  }
} finally {
  await closeRun(run).catch((e) => console.error('teardown: ' + e.message));
}
const m = { inquiries: results.length, reasked_total: results.reduce((s, r) => s + r.reasked.length, 0),
  planted_missing_total: results.reduce((s, r) => s + r.planted_missing.length, 0), ready: results.filter((r) => r.final_status === 'ready').length,
  probes_met: results.flatMap((r) => r.probes).filter((p) => p.met).length, probes: results.flatMap((r) => r.probes).length,
  json_ok_pct: Math.min(...results.map((r) => r.json_ok_pct)), over_clock: results.reduce((s, r) => s + r.over_clock, 0),
  long_run_lost_facts: results.find((r) => r.id === 'long100')?.planted_missing ?? null, spend_usd: await spent().catch(() => null), cap_usd: CAP, run_tag: 'qd_run:' + tag, stopped };
const codePass = !stopped && m.inquiries === 7 && m.reasked_total <= 1 && m.planted_missing_total === 0 && m.ready >= 6 && m.json_ok_pct === 100
  && m.over_clock === 0 && Array.isArray(m.long_run_lost_facts) && m.long_run_lost_facts.length === 0 && m.probes_met >= 7;
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify({ eval: 'B', at: new Date().toISOString(), code_pass: codePass, judge: 'pending: node is not the judge; run eval_b_judge.ts over this file', metrics: m, results }, null, 1));
console.log(JSON.stringify({ code_pass: codePass, ...m }, null, 1));
process.exit(codePass ? 0 : 1);
