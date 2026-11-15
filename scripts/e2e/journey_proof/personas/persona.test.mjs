// The persona journey's own judgements, with the model stubbed: the player answers only what was asked or says it is not
// sure, code catches a model that breaks character, a person leaves by the rule, the "Would a real person have got
// through?" section says what happened, and each supplier persona uses the doors its behaviour needs. No network.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL node --test scripts/e2e/journey_proof/personas/persona.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CUSTOMERS, personaProblems } from './customers.mjs';
import { createPlayer, stubComplete, checkReply, topicsFor, personaPrompt, gatewayComplete, PERSONA_FN, PERSONA_TASK_CLASS } from './player.mjs';
import { isRepeat, shouldAbandon, overlap, isStuck } from './abandon.mjs';
import { peopleSection, peopleText, afterNotSure, PEOPLE_TITLE } from './report.mjs';
import { SUPPLIERS, playSupplier } from './suppliers.mjs';
import { simplePdf, quotePdf, pricedLines, HVAC_RATE } from './artefacts.mjs';

const V = CUSTOMERS.villa_owner, F = CUSTOMERS.facility_manager, I = CUSTOMERS.impatient, A = CUSTOMERS.arabic_mixed;
const q = (key, text, options) => ({ key, text, options });
const fixed = (content) => async () => ({ ok: true, content: JSON.stringify(content), model: 'zz/stub', cost_usd: 0.0002 });

test('every truth sheet is a ZZ DEMO person who does not know everything, and a bad one is refused', () => {
  for (const p of Object.values(CUSTOMERS)) assert.deepEqual(personaProblems(p), [], p.key);
  assert.ok(Object.keys(CUSTOMERS).length >= 4);
  const bad = { ...V, label: 'Ahmed', facts: V.facts.map((f) => ({ ...f, knows: true })) };
  const pr = personaProblems(bad).join(' | ');
  assert.match(pr, /ZZ DEMO/); assert.match(pr, /does not know everything/);
  // the hidden sheet is in the prompt; the prompt forbids volunteering and inventing
  const sys = personaPrompt(V);
  assert.match(sys, /\[capacity\].*do NOT know/); assert.match(sys, /Answer ONLY what/); assert.match(sys, /Never invent/);
  assert.equal(personaPrompt(V), personaPrompt(V), 'byte-stable, so the gateway may cache it');
});

test('the stub person answers only the question asked, in its own words, and nothing else', async () => {
  const pl = createPlayer({ persona: V, complete: stubComplete(V) }); pl.opener();
  const t = await pl.turn({ message: 'Should the supplier only deliver, or also install?', question: q('scope', 'Should the supplier only deliver, install, or do everything?'), latency_s: 9 });
  assert.deepEqual(t.answered, ['scope']);
  assert.equal(t.reply, V.facts.find((f) => f.id === 'scope').says);
  assert.doesNotMatch(t.reply, /Villa 15|Gree|roof/i, 'it volunteered another fact');
  assert.equal(t.repeat, false); assert.equal(t.understood, true); assert.deepEqual(t.problems, []);
});

test('what the person does not know is "not sure" in its own words; a word it does not know is asked back, with the photo it has', async () => {
  const pl = createPlayer({ persona: V, complete: stubComplete(V) }); pl.opener();
  const t1 = await pl.turn({ message: 'Inverter or fixed speed?', question: q('spec_inverter_or_fixed_speed', 'Inverter or fixed speed'), latency_s: 5 });
  assert.deepEqual(t1.not_sure, ['inverter']); assert.deepEqual(t1.answered, []); assert.match(t1.reply, /don't know/);
  const t2 = await pl.turn({ message: 'What is the cooling capacity in BTU/h?', question: q('spec_cooling_capacity', 'Cooling capacity (BTU/h, TR or kW) per unit'), latency_s: 5 });
  assert.equal(t2.understood, false); assert.equal(t2.asked_back, true); assert.match(t2.reply, /What do you mean by "BTU"/);
  assert.equal(t2.file, 'nameplate_photo', 'a person with a photo of the nameplate sends it'); assert.deepEqual(pl.filesSent, ['nameplate_photo']);
  // the facility manager knows the word and the number
  const fm = createPlayer({ persona: F, complete: stubComplete(F) }); fm.opener();
  const t3 = await fm.turn({ message: 'Capacity?', question: q('spec_cooling_capacity', 'Cooling capacity (BTU/h, TR or kW) per unit'), latency_s: 5 });
  assert.deepEqual(t3.answered, ['capacity']); assert.equal(t3.understood, true); assert.deepEqual(t3.problems, []);
  // the Arabic speaker answers in Arabic
  const ar = createPlayer({ persona: A, complete: stubComplete(A) }); ar.opener();
  const t4 = await ar.turn({ message: 'متى تحتاج العمل؟', question: q('required_by', 'متى تحتاج العمل؟'), latency_s: 5 });
  assert.match(t4.reply, /[؀-ۿ]/); assert.deepEqual(t4.answered, ['timeline']);
});

test('the question is matched by its key first, then by its words', () => {
  assert.deepEqual(topicsFor(V, q('spec_cooling_capacity', 'anything')), ['capacity']);
  assert.deepEqual(topicsFor(V, q(null, 'By when do you need it done?')), ['timeline']);
  assert.deepEqual(topicsFor(V, q(null, 'What colour is your car')), []);
});

test('code catches a model that breaks character: unknown ids, a fact the person does not know, a file it does not have, a volunteered number', () => {
  const r = checkReply(F, JSON.stringify({ reply: 'Inverter. Office is about 280 m2.', answered: ['inverter', 'pipes', 'nonsense'], asked_topics: ['inverter'], send_file: 'nameplate_photo' }));
  assert.equal(r.ok, true);
  assert.deepEqual(r.answered, ['inverter']); assert.ok(r.not_sure.includes('pipes'), 'a fact the person does not know is moved to not sure');
  assert.equal(r.send_file, null);
  assert.deepEqual(r.volunteered, ['rooms']);
  const words = r.problems.join(' | ');
  for (const w of ['"nonsense" is not a fact', 'claimed to know "pipes"', 'send_file "nameplate_photo"', 'volunteered what was not asked: rooms']) assert.ok(words.includes(w), w);
  // a number explained by the fact asked is not volunteered; the 2 of "m2" and of "2.5" are not the number 2
  assert.deepEqual(checkReply(F, JSON.stringify({ reply: '2 years.', answered: ['warranty'], asked_topics: ['warranty'] })).volunteered, []);
  assert.deepEqual(checkReply(F, JSON.stringify({ reply: 'about 280 m2', answered: ['rooms'], asked_topics: ['rooms'] })).volunteered, []);
  assert.equal(checkReply(F, 'not json').ok, false);
  assert.equal(checkReply(F, JSON.stringify({ reply: '' })).ok, false);
});

test('the player keeps its own cap, retries a broken answer once, and counts a person it cannot play as leaving', async () => {
  let calls = 0;
  const broken = async () => { calls++; return { ok: true, content: 'not json', model: 'zz/stub', cost_usd: 0.001 }; };
  const pl = createPlayer({ persona: V, complete: broken }); pl.opener();
  const t = await pl.turn({ message: 'Which emirate?', question: q('location', 'Which emirate?'), latency_s: 3 });
  assert.equal(calls, 2); assert.equal(t.abandoned.rule, 'player_failed'); assert.equal(t.reply, null);
  const capped = createPlayer({ persona: V, complete: fixed({ reply: 'Villa 15, Al Barsha 2, Dubai.', answered: ['location'], asked_topics: ['location'] }), maxCalls: 1 }); capped.opener();
  await capped.turn({ message: 'Which emirate?', question: q('location', 'Which emirate?'), latency_s: 3 });
  const t2 = await capped.turn({ message: 'When?', question: q('required_by', 'When?'), latency_s: 3 });
  assert.equal(t2.abandoned.rule, 'player_cap'); assert.equal(capped.spend.calls, 1); assert.equal(capped.spend.usd, 0.0002);
  // a tap must be one of the buttons
  const tapper = createPlayer({ persona: V, complete: fixed({ reply: '', tap: 'Supply and install', answered: ['scope'], asked_topics: ['scope'] }) }); tapper.opener();
  const t3 = await tapper.turn({ message: 'Scope?', question: q('scope', 'Scope?', ['Supply only', 'Supply and install']), latency_s: 3 });
  assert.equal(t3.tap, 'Supply and install');
  const t4 = await tapper.turn({ message: 'Scope?', question: q('installation', 'Install?', ['Yes', 'No']), latency_s: 3 });
  assert.equal(t4.tap, null); assert.match(t4.problems.join(' '), /not one of the buttons/);
});

test('a repeat is the same key, the same topic or nearly the same words; asking again right after "what does that mean" is a rephrase', () => {
  const T = [{ n: 1, question: { key: 'application_area', text: 'What is the space used for, and roughly how big is it?', topics: ['rooms'] }, understood: true }];
  assert.deepEqual(isRepeat({ key: 'application_area', text: 'x' }, T), { repeat: true, of: 1, why: 'same key' });
  assert.equal(isRepeat({ key: 'spec_room_use_and_area_or_heat_load_calc', text: 'Room use and area', topics: ['rooms'] }, T).why, 'same topic');
  assert.equal(isRepeat({ key: null, text: 'What is the space used for and roughly how big is it' }, T).why, 'same words');
  assert.equal(isRepeat({ key: 'scope', text: 'Supply only or supply and install?' }, T).repeat, false);
  assert.ok(overlap('Room use and area', 'Should the supplier install?') < 0.6);
  const confused = [{ ...T[0], understood: false, asked_back: true }];
  assert.deepEqual(isRepeat({ key: 'application_area', text: 'How big is the room?' }, confused), { repeat: false, rephrase: true, of: 1, why: 'same key' });
});

test('the abandonment rule: slow replies, a repeat, too many questions, or nothing happening', () => {
  const P = I.patience;   // slow_s 20, max_slow 3, abandon_on_repeat 1, max_questions 6
  const t = (n, latency_s, extra = {}) => ({ n, latency_s, question: { key: 'k' + n, text: 'q' + n }, status: 'needs_info', message: 'q?', ...extra });
  assert.equal(shouldAbandon([t(1, 25), t(2, 10), t(3, 22)], P).abandon, false);
  const slow = shouldAbandon([t(1, 25), t(2, 10), t(3, 22), t(4, 30)], P);
  assert.deepEqual([slow.abandon, slow.rule, slow.at], [true, 'slow', 4]); assert.match(slow.reason, /3 replies slower than 20 s \(turns 1, 3, 4; the slowest 30 s\)/);
  const rep = shouldAbandon([t(1, 5), t(2, 5, { repeat: true, repeat_of: 1 })], P);
  assert.deepEqual([rep.rule, rep.at], ['repeat', 2]); assert.match(rep.reason, /first asked at turn 1/);
  assert.equal(shouldAbandon([t(1, 5), t(2, 5, { repeat: true, repeat_of: 1 })], V.patience).abandon, false, 'the villa owner tolerates a repeat');
  const many = shouldAbandon([1, 2, 3, 4, 5, 6].map((n) => t(n, 5)), P);
  assert.equal(many.rule, 'too_many_questions');
  const idle = (n) => ({ n, latency_s: 5, question: null, status: 'needs_info', message: 'Thanks, noted.' });
  assert.equal(isStuck(idle(1)), true); assert.equal(isStuck({ ...idle(1), message: 'Roughly how big is the room?' }), false); assert.equal(isStuck({ ...idle(1), status: 'ready' }), false);
  assert.equal(shouldAbandon([t(1, 5), idle(2)], V.patience).abandon, false);
  assert.equal(shouldAbandon([t(1, 5), idle(2), idle(3)], V.patience).rule, 'stuck');
});

test('a person who is asked again what he answered leaves, and the player says where and why', async () => {
  const pl = createPlayer({ persona: I, complete: stubComplete(I) }); pl.opener();
  const t1 = await pl.turn({ message: 'Capacity?', question: q('spec_cooling_capacity', 'Cooling capacity per unit'), latency_s: 8 });
  assert.deepEqual(t1.answered, ['capacity']);
  const t2 = await pl.turn({ message: 'Capacity?', question: q('spec_cooling_capacity', 'Cooling capacity per unit'), latency_s: 8 });
  assert.equal(t2.repeat, true); assert.equal(t2.repeat_of, 1); assert.deepEqual(pl.abandoned, { at: 2, rule: 'repeat', reason: 'asked again what was already answered once (turn 2, first asked at turn 1)' });
  assert.equal(t2.reply, null, 'a person who left does not answer');
  // the opener counts: asking what he already typed is a repeat by his own words ("i said that")
  const p2 = createPlayer({ persona: I, complete: stubComplete(I) }); p2.opener();
  const t3 = await p2.turn({ message: 'Is it new or a replacement?', question: q('new_or_replace', 'Is this new, a replacement or a repair?'), latency_s: 8 });
  assert.equal(t3.repeat, true); assert.equal(t3.repeat_why, 'the person said it was already answered'); assert.equal(p2.abandoned.rule, 'repeat');
});

test('"Would a real person have got through?" names the abandonment, repeats, slowest replies and what was done with each "not sure"', () => {
  const T = [
    { n: 1, question: { key: 'spec_cooling_capacity', text: 'Cooling capacity (BTU/h) per unit', topics: ['capacity'] }, latency_s: 12, understood: false, reply: 'What do you mean by "BTU"?', answered: [], not_sure: ['capacity'], file: 'nameplate_photo', problems: [] },
    { n: 2, question: { key: 'spec_cooling_capacity', text: 'Cooling capacity (BTU/h) per unit', topics: ['capacity'] }, latency_s: 31, repeat: true, repeat_of: 1, repeat_why: 'same key', understood: true, reply: 'I sent the photo', answered: [], not_sure: ['capacity'], problems: [] },
    { n: 3, question: { key: 'spec_copper_pipe_length_included_per_unit', text: 'Copper pipe length?', topics: ['pipes'] }, latency_s: 40, understood: true, reply: 'No idea', answered: [], not_sure: ['pipes'], problems: ['volunteered what was not asked: rooms'] },
    { n: 4, question: { key: 'scope', text: 'Supply and install?', topics: ['scope'] }, latency_s: 22, understood: null, reply: null, answered: [], not_sure: [], abandoned: { at: 4, rule: 'slow', reason: 'too slow' }, problems: [] },
  ];
  const s = peopleSection({ persona: V, turns: T, abandoned: { at: 4, rule: 'slow', reason: '3 replies slower than 20 s' }, outcome: 'abandoned', final_details: { spec_copper_pipe_length_included_per_unit: 'Customer does not know: supplier to advise' },
    suppliers: [{ label: 'ZZ DEMO Quiet Air', behaviour_words: 'ignores the request', outcome: 'ignored', steps: [{ outcome: 'never answered' }] }], mode: 'test', latency_source: 'test', spend: { calls: 3, usd: 0.0006, models: new Set(['zz/stub']) } });
  assert.equal(s.title, PEOPLE_TITLE); assert.equal(s.got_through, false);
  assert.match(s.headline, /^No\. ZZ DEMO villa owner left at turn 4: 3 replies slower than 20 s\.$/);
  assert.deepEqual(s.repeats.map((r) => [r.n, r.first_asked_at, r.why]), [[2, 1, 'same key']]);
  assert.deepEqual(s.slowest.map((x) => x.seconds), [40, 31, 22]);
  assert.equal(s.not_sure[0].platform_did, 'asked the same thing again at turn 2: "Cooling capacity (BTU/h) per unit"');
  assert.match(s.not_sure[2].platform_did, /^accepted it and moved on to: "Supply and install\?"/);
  assert.equal(s.not_sure[2].recorded_as, 'Customer does not know: supplier to advise');
  assert.deepEqual(s.misunderstood.map((m) => m.n), [1]); assert.deepEqual(s.files.map((f) => f.file), ['nameplate_photo']);
  assert.equal(s.verdicts[0].as_expected, false); assert.equal(s.verdicts[1].as_expected, false); assert.equal(s.verdicts[2].as_expected, true, 'the slowest (40 s) is within the villa owner\'s 45 s');
  assert.equal(s.verdicts[3].as_expected, false, 'a "not sure" was asked again'); assert.equal(s.verdicts[4].as_expected, false);
  assert.deepEqual(s.spend, { calls: 3, usd: 0.0006, models: ['zz/stub'] });
  const txt = peopleText(s);
  for (const w of ['Abandoned at turn 4 (slow)', '[REPEAT]', '[not understood]', 'Slowest replies: 40 s (turn 3)', 'Could not answer:', 'ZZ DEMO Quiet Air (ignores the request): ignored', 'volunteered']) assert.ok(txt.includes(w), w);
  // a person who got through
  const ok = peopleSection({ persona: F, turns: [{ n: 1, question: { key: 'scope', text: 'Scope?', topics: ['scope'] }, latency_s: 9, understood: true, reply: 'Supply and install.', answered: ['scope'], not_sure: [] }], outcome: 'ready' });
  assert.equal(ok.got_through, true); assert.match(ok.headline, /^Yes\. ZZ DEMO facility manager got through in 1 question\.$/);
  assert.equal(afterNotSure([{ n: 1 }], 0, 'ready'), 'it went on to the summary: the request was ready');
});

test('each supplier persona uses the doors its behaviour needs, with its own real file', async () => {
  const calls = []; const job = { rfq: 'ZZRFQ001', lines: V.job.lines };
  const doors = {
    message: async (text) => { calls.push(['message', text]); return { http: 200, said: 'ZZ DEMO: the outdoor units are on the roof, reached by stairs.' }; },
    upload: async ({ filename, mime, bytes }) => { calls.push(['upload', filename, mime, bytes.length]); return { http: 200, read_amount: 1000, quote_id: 'zz-q-' + calls.length, accepted: mime === 'application/pdf', held: mime !== 'application/pdf', missing: ['line 1: model'] }; },
    afterSilence: async () => [{ at: 't', what: 'a reminder e-mail (suppressed)' }],
  };
  const clock = () => '2026-11-15T10:00:00.000Z';
  const silent = await playSupplier(SUPPLIERS.silent, { doors, job, now: clock });
  assert.equal(calls.length, 0); assert.match(silent.outcome, /ignored the request; the platform then: a reminder e-mail/);
  const asker = await playSupplier(SUPPLIERS.asker, { doors, job, now: clock });
  assert.deepEqual(calls.slice(0, 2).map((c) => c[0]), ['message', 'upload']); assert.match(asker.steps[0].outcome, /the platform answered in/); assert.match(asker.outcome, /asked first, was answered, then quoted: live/);
  calls.length = 0;
  const range = await playSupplier(SUPPLIERS.range, { doors, job, now: clock });
  assert.ok(range.range.low < range.range.high); assert.match(range.outcome, /went live as AED 1000 with nothing telling the customer it is a range/);
  const hand = await playSupplier(SUPPLIERS.handwritten, { doors, job, now: clock });
  assert.equal(calls[1][2], 'image/jpeg'); assert.match(hand.outcome, /a handwritten photo: held/);
  const proper = await playSupplier(SUPPLIERS.proper, { doors, job, now: clock });
  assert.match(proper.outcome, /a proper PDF: live/);
  for (const s of [silent, asker, range, hand, proper]) assert.match(s.label, /^ZZ DEMO /);
  // a question nobody answers: the asker does not quote
  const mute = await playSupplier(SUPPLIERS.asker, { doors: { ...doors, message: async () => ({ http: 200, said: null }) }, job, now: clock });
  assert.equal(mute.quote_id, null); assert.match(mute.outcome, /got no answer, so did not quote/);
});

test('the suppliers\' files are what they say: a PDF with a range subject to site visit, a typed PDF with the total, a JPEG photo', async () => {
  const lines = pricedLines(V.job.lines, HVAC_RATE, 1);
  const range = quotePdf({ supplier: SUPPLIERS.range, rfq: 'R1', ref: 'Q1', lines, kind: 'range', low: 9000, high: 14000 }).toString('latin1');
  assert.ok(range.startsWith('%PDF-1.4') && range.includes('%%EOF'));
  assert.match(range, /AED 9,000 to AED 14,000 excluding VAT, SUBJECT TO SITE VISIT\./);
  const proper = quotePdf({ supplier: SUPPLIERS.proper, rfq: 'R1', ref: 'Q2', lines }).toString('latin1');
  assert.match(proper, new RegExp(`Subtotal AED ${lines.reduce((a, l) => a + l.amount, 0).toLocaleString('en-US')}`));
  assert.doesNotMatch(proper + range, /@(?!example\.invalid)[a-z0-9-]+\.(com|ae)\b/i, 'no real address');
  // pdftotext reads the hand-written PDF as a reader would (when installed)
  const dir = mkdtempSync(join(tmpdir(), 'zz-persona-')); const f = join(dir, 'q.pdf');
  try {
    (await import('node:fs')).writeFileSync(f, simplePdf(['ZZ DEMO line one', { text: 'Total AED 1,234', bold: true }]));
    const r = spawnSync('pdftotext', [f, '-'], { encoding: 'utf8' });
    if (r.status === 0) assert.match(r.stdout, /ZZ DEMO line one[\s\S]*Total AED 1,234/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('the live model call goes through ai_gateway under the run tag, never untagged', async () => {
  assert.throws(() => gatewayComplete({ base: 'https://zz.invalid', service: 's' }), /run tag/);
  let seen = null;
  const fetchImpl = async (url, init) => { seen = { url, headers: init.headers, body: JSON.parse(init.body) }; return new Response(JSON.stringify({ ok: true, content: '{"reply":"x"}', model: 'zz/model', cost_usd: 0.0003 }), { status: 200 }); };
  const c = gatewayComplete({ base: 'https://zz.invalid', service: 'svc', fnSecret: 'fs', e2eSecret: 'es', runTag: 'zz12', fetchImpl });
  const r = await c({ sys: 'S', input: 'I' });
  assert.equal(seen.url, 'https://zz.invalid/functions/v1/ai_gateway');
  assert.equal(seen.headers['x-qd-e2e-run'], 'zz12'); assert.equal(seen.headers['x-qd-e2e-secret'], 'es');
  assert.deepEqual([seen.body.fn, seen.body.task_class, seen.body.sys, seen.body.input, seen.body.__secret], [PERSONA_FN, PERSONA_TASK_CLASS, 'S', 'I', 'fs']);
  assert.deepEqual(r, { ok: true, content: '{"reply":"x"}', model: 'zz/model', cost_usd: 0.0003, error: null });
});

test('the dry run plays the villa owner and the impatient customer against the REAL intake handler offline', { skip: spawnSync('deno', ['--version']).status !== 0 && 'deno is not installed', timeout: 240000 }, async () => {
  const { dryJourney } = await import('./dry_run.mjs');
  const out = mkdtempSync(join(tmpdir(), 'zz-persona-dry-'));
  try {
    const v = await dryJourney(V, { out, log: () => {} });
    assert.equal(v.people.outcome, 'ready', v.people.headline);
    assert.ok(v.people.turns.length >= 3 && v.people.turns.every((t) => t.question), 'every turn the villa owner met carried a question');
    assert.ok(v.people.misunderstood.length >= 1, 'the capacity card uses BTU, which this person does not understand');
    assert.equal(v.people.suppliers.length, 5);
    const rec = JSON.parse(readFileSync(join(v.dir, 'record.json'), 'utf8'));
    assert.equal(rec.sections.people.title, PEOPLE_TITLE); assert.match(rec.journey.mode, /^dry/);
    const i = await dryJourney(I, { out, log: () => {} });
    assert.equal(i.people.got_through, false); assert.ok(i.people.abandoned, 'the impatient customer leaves');
  } finally { rmSync(out, { recursive: true, force: true }); }
});
