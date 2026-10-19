import { assertEquals } from 'jsr:@std/assert@1';
import { shapeRequest, THINKING_HEADROOM } from './request_shape.ts';

const RF = { type: 'json_object' };

Deno.test('Opus 5.5 never receives temperature, gets effort and thinking headroom', () => {
  const p = shapeRequest({ model: 'anthropic/claude-opus-5.5', maxTokens: 2000, temperature: 0.2 });
  assertEquals(p.temperature, undefined);
  assertEquals(p.reasoning, { effort: 'medium' });
  assertEquals(p.max_tokens, 2000 + THINKING_HEADROOM);
});

Deno.test('a caller effort is honoured, an invalid one falls back to medium', () => {
  assertEquals(shapeRequest({ model: 'anthropic/claude-opus-5.5', maxTokens: 1, effort: 'high' }).reasoning, { effort: 'high' });
  assertEquals(shapeRequest({ model: 'anthropic/claude-opus-5.5', maxTokens: 1, effort: 'none' }).reasoning, { effort: 'medium' });
});

Deno.test('non-Claude routes keep temperature and their own max_tokens, no reasoning field', () => {
  const p = shapeRequest({ model: 'google/gemini-3.8-flash', maxTokens: 700, temperature: 0.3 });
  assertEquals(p, { max_tokens: 700, temperature: 0.3 });
});

Deno.test('response_format only where the model lists it', () => {
  assertEquals(shapeRequest({ model: 'qwen/qwen3.8-max-0902', maxTokens: 1, responseFormat: RF, supported: new Set(['response_format']) }).response_format, RF);
  assertEquals(shapeRequest({ model: 'qwen/x', maxTokens: 1, responseFormat: RF, supported: new Set(['temperature']) }).response_format, undefined);
  assertEquals(shapeRequest({ model: 'qwen/x', maxTokens: 1, responseFormat: RF, supported: null }).response_format, undefined);
});

Deno.test('an explicit effort reaches a non-Claude reasoning model only where it lists reasoning; none given = untouched', () => {
  const luna = 'openai/gpt-6-luna-pro';
  assertEquals(shapeRequest({ model: luna, maxTokens: 900, effort: 'low', supported: new Set(['reasoning']) }).reasoning, { effort: 'low' });
  assertEquals(shapeRequest({ model: luna, maxTokens: 900, effort: 'low', supported: new Set(['response_format']) }).reasoning, undefined);
  assertEquals(shapeRequest({ model: luna, maxTokens: 900, supported: new Set(['reasoning']) }).reasoning, undefined);
  assertEquals(shapeRequest({ model: luna, maxTokens: 900, effort: 'bogus', supported: new Set(['reasoning']) }).reasoning, undefined);
});

Deno.test('a non-Claude reasoning model gets thinking headroom, so its answer is not cut off (exam run cdd95305)', () => {
  const p = shapeRequest({ model: 'openai/gpt-6-luna-pro', maxTokens: 900, supported: new Set(['reasoning', 'max_tokens']) });
  assertEquals(p.max_tokens, 900 + THINKING_HEADROOM);
  assertEquals(p.reasoning, undefined);
  assertEquals(shapeRequest({ model: 'x/plain', maxTokens: 900, supported: new Set(['max_tokens']) }).max_tokens, 900);
});
