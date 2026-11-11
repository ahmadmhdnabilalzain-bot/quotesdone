// Ruling 1630 (11 Nov 2026): effort by consequence. These replay the inputs that were wrong before the policy existed.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { classEffort, conversationEffort, depthReason, EFFORT_BY_CLASS, effortFor, SURFACES, surfaceEffort, UNKNOWN_CLASS_EFFORT } from './effort_policy.ts';
import { HIGH_EFFORT_HEADROOM, shapeRequest, THINKING_HEADROOM } from './request_shape.ts';

Deno.test('a class that decides, reads documents, prices or matches is high; a conversation is medium; an unknown class is high', () => {
  for (const c of ['internal_judgement', 'routine_employee_reasoning', 'quote_comparison', 'document_extraction', 'supplier_trade_choice', 'rfq_routing', 'marketing_copy', 'knowledge_validation']) {
    assertEquals(classEffort(c), 'high', c);
  }
  for (const c of ['conversation_reply', 'visitor_chat', 'customer_portal_assistant', 'supplier_communication', 'customer_communication', 'status_reply']) {
    assertEquals(classEffort(c), 'medium', c);
  }
  assertEquals(classEffort('a_class_nobody_classified'), UNKNOWN_CLASS_EFFORT);
  assertEquals(UNKNOWN_CLASS_EFFORT, 'high');
  // no class is low until a side-by-side proves it (ruling 1618)
  assertEquals(Object.entries(EFFORT_BY_CLASS).filter(([, e]) => e === 'low'), []);
});

Deno.test('the six call sites that asked low by literal: none is low, and the two that decide are high', () => {
  // before 11 Nov every one of these sent 'low' with no side-by-side behind it
  for (const s of Object.keys(SURFACES)) assert(surfaceEffort(s) !== 'low', s + ' is not proven low');
  assertEquals(surfaceEffort('inquiry_intake.trade'), 'high', 'the intake trade decides the match');
  assertEquals(surfaceEffort('inquiry_intake.exact_spec'), 'high', 'the spec reader fills the request');
  assertEquals(surfaceEffort('wa_inbound.needs_a_person'), 'high');
  assertEquals(surfaceEffort('wa_inbound.intent_table'), 'high', 'the WhatsApp reading also decides whether a person is needed');
  assertEquals(surfaceEffort('wa_inbound.greeting_state'), 'medium', 'menu sorting: medium until proven');
  assertEquals(surfaceEffort('wa_inbound.status_lane'), 'medium', 'a status answer is a conversation');
  assertEquals(surfaceEffort('email_triage.needs_a_person'), 'high', 'an unlabelled surface is treated as deciding');
});

Deno.test('the gateway: no effort named takes the class; a low on a deciding class is raised; an explicit high stands', () => {
  assertEquals(effortFor('internal_judgement', null), 'high', 'before: no effort, so GPT-6 Luna Pro reasoned at its own default');
  assertEquals(effortFor('internal_judgement', 'low'), 'high', 'a decision is never made at low, whoever asks');
  assertEquals(effortFor('conversation_reply', undefined), 'medium');
  assertEquals(effortFor('conversation_reply', 'high'), 'high', 'an escalated turn or a re-ask stays high');
  assertEquals(effortFor('intent_detection', 'low'), 'low', 'sorting may be low where the caller has the proof');
  assertEquals(effortFor('conversation_reply', 'nonsense'), 'medium');
});

Deno.test('a conversation that is not straightforward gets the deeper thinking (cheap rule, no model)', () => {
  const high: [string, string][] = [
    ['You quoted the wrong thing, I asked for 14 windows not 12', 'price_challenge'],
    ['I want a refund, the supplier never responded', 'refund'],
    ['This is unacceptable, nobody has answered me for three days', 'complaint'],
    ['I will raise a chargeback with my bank', 'dispute'],
    ['Why is it so expensive? Can you get a better price?', 'price_challenge'],
    ['How long does verification take? And can I quote in several emirates?', 'multi_part'],
    ['1. the kitchen\n2. the two bathrooms\n3. the balcony', 'multi_part'],
    ['السعر غالي جدا', 'price_challenge'],
    ['أريد استرداد المبلغ', 'refund'],
    ['عندي شكوى على المورد', 'complaint'],
  ];
  for (const [m, why] of high) { assertEquals(depthReason(m), why, m); assertEquals(conversationEffort(m), 'high', m); }
  for (const m of ['hi', 'How does it work?', 'What is the reveal fee?', 'مرحبا', 'Do you cover glass balustrades?']) {
    assertEquals(conversationEffort(m), 'medium', m);
  }
  assertEquals(conversationEffort('How does it work?', { priorProblems: ['it states a figure the brief does not'] }), 'high', 'a re-draft after a failed check');
  assertEquals(conversationEffort('How does it work?', { flagged: true }), 'high', 'a classifier flagged it');
});

Deno.test('high effort gets the larger thinking headroom on Claude and on a reasoning model of another family', () => {
  const luna = shapeRequest({ model: 'openai/gpt-6-luna-pro', maxTokens: 900, effort: 'high', supported: new Set(['reasoning']) });
  assertEquals(luna.max_tokens, 900 + HIGH_EFFORT_HEADROOM);
  assertEquals((luna.reasoning as { effort: string }).effort, 'high');
  const sonnet = shapeRequest({ model: 'anthropic/claude-sonnet-5.5', maxTokens: 900, effort: 'medium' });
  assertEquals(sonnet.max_tokens, 900 + THINKING_HEADROOM);
  assert(HIGH_EFFORT_HEADROOM > THINKING_HEADROOM);
});
