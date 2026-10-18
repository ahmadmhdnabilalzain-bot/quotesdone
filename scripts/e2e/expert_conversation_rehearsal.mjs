// scripts/e2e/expert_conversation_rehearsal.mjs — measures founder rulings 1195-1200 (12 Oct 2026): customer-facing
// agents hold adaptive, expert conversations (the wardrobe-from-a-photo example), never "I don't know", and end with
// a complete quotable request. Assigned: sales_engineer (knowledge + style), it_engineer (harness).
//
// 10 scripted multi-turn conversations (EN + AR, one with a drawing image for vision). Three roles per turn, all
// through production ai_gateway inside THIS run's own tagged rehearsal window (models_allowed, cap_usd <= 2,
// enforced by fn_kernel_paid_provider_gate) for one ZZ DEMO subject the run creates; untagged traffic keeps the hold:
//   agent     the compiled brief (BRIEF_TEXT, cached sys_stable) + the reply rules + CONVERSATION_STYLE
//   customer  a simulated customer with hidden facts who answers only what is asked
//   judge     knowledge_validation, counterpart_model = the agent's model, so a DIFFERENT family scores it
// Scores: adaptiveness, correctness, no_idk, completeness, overall (0-10). Target: every conversation overall >= 9.
// BOUNDARY: this exercises the knowledge and the style the agents are given, with a system prompt that mirrors
// _shared/ai_reply.ts aiSystem(); it does not call ai_reply.ts itself (that code lives on the customer_support branch).
//
//   node scripts/e2e/expert_conversation_rehearsal.mjs [--cap-usd 2] [--only wardrobe,kitchen] [--out <dir>]
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import sharp from 'sharp';
import { newRun, teardown, makeSupplier, keys, REF, q, closeRehearsalWindow, internalCred } from '../lib/demo_factory.mjs';
import { mgmtRead, mgmtFixture } from '../lib/qd_guard.mjs';
import { BRIEF_TEXT, CONVERSATION_STYLE, BRIEF_VERSION } from '../../supabase/functions/_shared/brief.generated.ts';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const CAP_USD = Number(val('--cap-usd') || 2);
if (!(CAP_USD > 0 && CAP_USD <= 2)) { console.error('REFUSED: --cap-usd must be in (0, 2]'); process.exit(2); }
const ONLY = (val('--only') || '').split(',').filter(Boolean);
const OUT = val('--out') || join(process.env.TEMP || '.', 'qd_expert_conversation');
mkdirSync(OUT, { recursive: true });
process.env.QD_FIXTURES = '1';
const read = (sql) => mgmtRead(REF, sql);
const write = (sql, where) => mgmtFixture(REF, sql, where);
const MAX_AGENT_TURNS = 14;   // 9 cut 3 of 4 misses in run cb0b01b6 before the agent's summary; the loop still stops on the customer's confirmation

// A customer's sketch of the studio wall (the "photo/drawing" of the founder's example), rendered locally.
async function studioSketch() {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600"><rect width="800" height="600" fill="#fbfaf5"/>
  <rect x="150" y="80" width="420" height="460" fill="none" stroke="#333" stroke-width="4"/>
  <rect x="600" y="160" width="150" height="200" fill="#cfe6f5" stroke="#333" stroke-width="3"/><text x="615" y="390" font-size="20" font-family="Arial">window</text>
  <rect x="160" y="500" width="400" height="12" fill="#999"/><text x="250" y="535" font-size="18" font-family="Arial">skirting + socket at 30 cm</text>
  <circle cx="540" cy="470" r="8" fill="#333"/>
  <line x1="150" y1="60" x2="570" y2="60" stroke="#c00" stroke-width="2"/><text x="300" y="50" font-size="24" fill="#c00" font-family="Arial">approx 2.4 m</text>
  <line x1="120" y1="80" x2="120" y2="540" stroke="#c00" stroke-width="2"/><text x="20" y="320" font-size="24" fill="#c00" font-family="Arial">2.7 m</text>
  <text x="200" y="300" font-size="28" font-family="Arial">wardrobe here?</text></svg>`;
  return 'data:image/png;base64,' + (await sharp(Buffer.from(svg)).png().toBuffer()).toString('base64');
}

const S = [
  { id: 'wardrobe_photo', lang: 'en', trade: 'carpentry-joinery', image: true,
    open: 'Hi, I want a custom wardrobe for my studio, here is the wall where it should go.',
    facts: 'Rented studio apartment in JLT, Dubai. Wall in the sketch about 2.4 m wide, 2.7 m ceiling. Wants mostly hanging plus 4 shelves and 2 drawers. Prefers sliding doors, matte white, handle-less. Budget moderate, not luxury. Needs it within 4 weeks. Building allows work 9am-6pm weekdays; landlord is OK but needs to be told.' },
  { id: 'kitchen_villa_ar', lang: 'ar', trade: 'kitchens',
    open: 'السلام عليكم، أريد تجديد مطبخ الفيلا بالكامل.',
    facts: 'Owned villa in Al Barsha. L-shaped kitchen about 4 m by 3 m. Wants new cabinets (high-gloss lacquer), quartz worktop, keep existing appliances except a new built-in oven and hood. Plumbing stays in place. Old kitchen must be removed. Timeline 2 months. Budget mid-range. Speaks only Arabic.' },
  { id: 'ac_replacement', lang: 'en', trade: 'hvac',
    open: 'My AC in the bedroom stopped cooling, I think I need to replace it.',
    facts: 'Apartment in Dubai Marina, 2-bedroom, the master bedroom about 4 m x 4.5 m, west-facing big window. Existing wall split unit, 12 years old, outdoor unit on the balcony. Wants a replacement split, inverter. Copper pipes look fine. Building management requires a work permit. Wants it done this week.' },
  { id: 'roof_waterproofing_ar', lang: 'ar', trade: 'waterproofing',
    open: 'عندي تسريب مياه من السطح إلى غرفة النوم بعد المطر.',
    facts: 'Villa in Sharjah, flat concrete roof about 150 square metres, last waterproofed 10 years ago with bitumen membrane, now tiles cracked in places. Leak stains on bedroom ceiling. Wants full re-waterproofing with a warranty. Has AC units and a water tank on the roof. Flexible timeline before winter.' },
  { id: 'cctv_shop', lang: 'en', trade: 'security',
    open: 'I need CCTV for my shop.',
    facts: 'Mobile phone accessories retail shop in a Deira mall, about 60 square metres, one entrance, one stock room, cash counter. Wants to see faces at the entrance and the cash counter, view on phone, keep recordings as required by law. No existing system. Mall management requires approved contractor. Within 2 weeks.' },
  { id: 'floor_tiles', lang: 'en', trade: 'tiling',
    open: 'How much to replace the floor tiles in my apartment?',
    facts: '1-bedroom apartment in Abu Dhabi Reem Island, about 70 square metres excluding bathrooms, existing ceramic tiles, some hollow. Wants large-format porcelain 60x120 matt light grey. Unsure whether to remove old tiles or tile over. Living in the apartment, needs it done in phases. Owner.' },
  { id: 'painting_ar', lang: 'ar', trade: 'painting',
    open: 'أبي صباغة شقتي قبل ما أسلم المفتاح.',
    facts: 'Tenant moving out of a 2-bedroom apartment in Al Nahda Dubai, about 110 square metres. Landlord requires walls back to white. Some nail holes and one damp patch near bathroom. Ceilings white too. Empty apartment. Needs it in 5 days.' },
  { id: 'pool_build', lang: 'en', trade: 'swimming-pools',
    open: 'We want to build a swimming pool in our garden.',
    facts: 'Villa in Arabian Ranches, garden about 12 m x 8 m, wants a pool about 8 m x 4 m, 1.2 to 1.6 m deep, mosaic tiles, with a small sun shelf, heating/cooling chiller, and LED lights. Community requires developer NOC and engineer drawings. Kids at home. Wants it before next summer.' },
  { id: 'glass_partition_ar', lang: 'ar', trade: 'glass',
    open: 'نحتاج قواطع زجاج لمكتبنا.',
    facts: 'Office on 14th floor in Business Bay, need glass partitions for 3 meeting rooms, total run about 18 m, ceiling height 2.8 m, frameless with frosted band, sliding door for one room and hinged for two, acoustic matters. Building fit-out rules and DCD apply. Within 6 weeks.' },
  { id: 'solar_villa', lang: 'en', trade: 'solar',
    open: 'Is it worth putting solar panels on my villa?',
    facts: 'Villa in Dubai, owned, flat roof about 120 square metres with some shading from a water tank, summer DEWA bills high. Wants grid-connected, no batteries. Curious about Shams Dubai. Wants a proposal within a month.' },
].filter((s) => !ONLY.length || ONLY.includes(s.id));

const AGENT_RULES = (lang) => `You are QuotesDone's sales engineer answering a customer on the website chat. Answer the way a senior UAE construction and procurement expert answers a client.
RULES:
- Everything about QuotesDone itself (fees, terms, how it works) comes from the COMPANY BRIEF; never state a price, rate or fee for the work itself, suppliers price it.
- Answer what they asked, then ask the one or two follow-up questions the trade playbook says matter most next; offer concrete choices when they are unsure. Never send a questionnaire.
- Never say you do not know, are not sure, or will check; if something needs a site measure or an authority, say exactly who decides it and carry on.
- Plain text, no markdown, short. Reply in ${lang === 'ar' ? 'formal Gulf Arabic (Western digits)' : 'UAE English'}.
- Never say "AI" (say "Smart Engine"), never give a licence number.
- When the trade playbook's complete-quotable-request list is filled, summarise the request and ask the customer to confirm it.

${CONVERSATION_STYLE}`;

const CUSTOMER = (s) => `You are role-playing a customer in the UAE talking to a procurement marketplace chat. Your hidden facts: ${s.facts}
Answer ONLY what you are asked, briefly and naturally, like a real person on a phone (one or two short sentences). Do not volunteer facts you were not asked. If asked to confirm a summary that matches your facts, say it is correct; if it is wrong, correct it. Write in ${s.lang === 'ar' ? 'Gulf Arabic' : 'English'}. Return only your reply text, nothing else (no JSON, no quotes).`;

const JUDGE = `You are a strict senior UAE construction sales-engineering assessor. Score the AGENT in this transcript (0-10 each):
- adaptiveness: asks the right next questions one or two at a time, in a sensible order, builds on answers, never re-asks what was said, uses any image the customer sent;
- correctness: technical and UAE-regulatory statements are correct, no invented prices or fees, company facts consistent;
- no_idk: never says "I don't know", "not sure", "I'll check" or equivalent (10 = never);
- completeness: by the end the request is complete enough for suppliers to price (scope, sizes, specs, site, access/approvals, timeline) and summarised for confirmation;
- overall: a senior sales engineer's overall grade.
Return ONLY JSON {"adaptiveness":n,"correctness":n,"no_idk":n,"completeness":n,"overall":n,"issues":["at most 2, under 15 words each"]}. Compact JSON on one line, no code fence.`;

const json = (s) => { try { return JSON.parse(String(s ?? '').replace(/^[^{]*/, '').replace(/[^}]*$/, '')); } catch { return null; } };

async function main() {
  const { SERVICE } = await keys();
  const run = newRun({ quiet: true });
  const results = [];
  let spend = null;
  await write(`insert into public.rehearsal_window (run_tag, opened_by, note) values (${q('qd_run:' + run.tag)}, 'scripts/e2e/expert_conversation_rehearsal.mjs', 'expert conversations (rulings 1195-1200)')`, 'rehearsal window');
  try {
    await write(`update public.rehearsal_window set models_allowed = true, cap_usd = ${CAP_USD}, expires_at = now() + interval '90 minutes'
                 where run_tag = ${q('qd_run:' + run.tag)} and ended_at is null`, 'expert conversation window: models for this tag only');
    const subj = await makeSupplier(run, { trade: 'aluminium', withAuth: false, capability: false, company_name: `ZZ DEMO expert conversation ${run.tag}` });
    if (!/@example\.invalid$/.test(String(subj.email))) throw new Error('REFUSED: the subject is not a fixture address');
    const secret = (await read(`select value from public.app_secrets where key='cred_fn_ai'`))[0]?.value;
    const e2e = await internalCred();
    const subject = { supplier_id: Number(subj.leadId), email: subj.email };
    const gw = async (body) => {
      const r = await fetch(`https://${REF}.supabase.co/functions/v1/ai_gateway`, { method: 'POST',
        headers: { 'content-type': 'application/json', Authorization: `Bearer ${SERVICE}`, 'x-qd-e2e-run': run.tag, 'x-qd-e2e-secret': e2e },
        body: JSON.stringify({ __secret: secret, subject, client_timeout_ms: 110000, ...body }) });
      const j = await r.json().catch(() => ({}));
      return { ok: r.ok && !!j.content, content: j.content, model: j.model ?? j.model_used ?? null, err: j.error ?? (r.ok ? null : r.status) };
    };
    // --photo <jpg>: a real photo (e.g. the sandbox test_photos/wardrobe_wall_1.jpg) instead of the rendered sketch.
    const PHOTO = val('--photo');
    const image = PHOTO ? 'data:image/jpeg;base64,' + (await sharp(PHOTO).resize({ width: 1024, withoutEnlargement: true }).jpeg({ quality: 80 }).toBuffer()).toString('base64') : await studioSketch();
    for (const s of S) {
      const turns = [{ role: 'customer', text: s.open, image: !!s.image }];
      const models = new Set();
      for (let t = 0; t < MAX_AGENT_TURNS; t++) {
        const msgs = turns.map((x, i) => ({ role: x.role === 'customer' ? 'user' : 'assistant',
          content: i === 0 && s.image ? [{ type: 'text', text: x.text }, { type: 'image_url', image_url: { url: image } }] : x.text }));
        const a = await gw({ fn: 'sales_engineer_conversation_drill', task_class: 'customer_communication', sys_stable: BRIEF_TEXT,
          messages: [{ role: 'system', content: AGENT_RULES(s.lang) }, ...msgs], max: 700, temperature: 0.3 });
        if (!a.ok) { turns.push({ role: 'agent', text: `(NO ANSWER: ${a.err})` }); break; }
        if (a.model) models.add(a.model);
        turns.push({ role: 'agent', text: String(a.content).trim() });
        const convo = turns.map((x) => `${x.role === 'customer' ? 'YOU' : 'AGENT'}: ${x.text}`).join('\n');
        const c = await gw({ fn: 'sales_engineer_conversation_drill', task_class: 'customer_communication', sys: CUSTOMER(s), input: convo + '\n\nYour next reply:', max: 400 });
        const reply = String(c.content || '').replace(/^```\w*|```$/g, '').trim();
        if (!reply) break;
        turns.push({ role: 'customer', text: reply });
        if (/\b(correct|that.?s right|confirmed|go ahead|proceed)\b|صحيح|تمام/i.test(reply) && /confirm|summary|ملخص|تأكيد|أكد/i.test(turns.at(-2).text)) break;
      }
      const transcript = turns.map((x) => `${x.role.toUpperCase()}${x.image ? ' (sent an image of the wall' + (val('--photo') ? ' (a photo)' : ': a sketch, ~2.4 m wide, 2.7 m high, window on the right, socket low right') + ')' : ''}: ${x.text}`).join('\n');
      const agentModel = [...models].join(',') || 'unknown';
      const j = await gw({ fn: 'sales_engineer_conversation_drill', task_class: 'knowledge_validation', counterpart_model: agentModel,
        sys: JUDGE, input: `TRADE: ${s.trade}\nCUSTOMER'S HIDDEN FACTS (for checking completeness): ${s.facts}\n\nTRANSCRIPT:\n${transcript}`, max: 900, temperature: 0 });
      const v = json(j.content);
      results.push({ id: s.id, capped: turns.filter((x) => x.role === 'agent').length >= MAX_AGENT_TURNS, lang: s.lang, trade: s.trade, agent_model: agentModel, judge_model: j.model, score: v, judge_raw: v ? undefined : String(j.content ?? j.err).slice(0, 1500), transcript: turns });
      console.log(`${s.id}: overall ${v?.overall ?? '?'} (adapt ${v?.adaptiveness ?? '?'}, correct ${v?.correctness ?? '?'}, no_idk ${v?.no_idk ?? '?'}, complete ${v?.completeness ?? '?'}) agent=${agentModel} judge=${j.model ?? j.err}`);
    }
  } finally {
    await write(`update public.rehearsal_window set models_allowed = false where run_tag = ${q('qd_run:' + run.tag)}`, 'models off').catch(() => {});
    spend = (await read(`select count(*)::int calls, coalesce(sum(cost_aed), 0)::numeric(12,4) aed, string_agg(distinct model_used, ',') models from public.ai_cost_log where e2e_run_tag = ${q(run.tag)}`))[0];
    const t = await teardown(run);
    console.log(`run ${run.tag} torn down: ${t.summary}`);
    await closeRehearsalWindow(run.tag);
  }
  const pass = results.length === S.length && results.every((r) => Number(r.score?.overall) >= 9);
  const out = { rulings: '1195-1200', measured_at: new Date().toISOString(), brief_version: BRIEF_VERSION, run_tag: run.tag, cap_usd: CAP_USD, spend, pass, results };
  writeFileSync(join(OUT, `expert_conversations_${run.tag}.json`), JSON.stringify(out, null, 1));
  console.log(`spend: ${JSON.stringify(spend)}  target (every overall >= 9): ${pass ? 'MET' : 'NOT MET'}  -> ${join(OUT, `expert_conversations_${run.tag}.json`)}`);
  process.exit(pass ? 0 : 1);
}
await main();
