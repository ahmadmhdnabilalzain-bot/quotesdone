// node --test src/components/me/speech.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { recognitionLangs, getRecognition, speechErrorKey } from './speech.ts';

test('the portal locale picks the Gulf dictation language, with a fallback every engine ships', () => {
  assert.deepEqual(recognitionLangs('en'), ['en-AE', 'en-US']);
  assert.deepEqual(recognitionLangs('ar'), ['ar-AE', 'ar-SA']);
  assert.deepEqual(recognitionLangs(undefined), ['en-AE', 'en-US']);
});

test('no speech recognition (Firefox, SSR) is null, never the paid transcribe path', () => {
  assert.equal(getRecognition({}), null);
  assert.equal(getRecognition(undefined), null);
  function W() {} function S() {}
  assert.equal(getRecognition({ webkitSpeechRecognition: W }), W);
  assert.equal(getRecognition({ SpeechRecognition: S, webkitSpeechRecognition: W }), S);
});

test('errors map to words; an unsupported language means retry, an abort says nothing', () => {
  assert.equal(speechErrorKey('language-not-supported'), null);
  assert.equal(speechErrorKey('not-allowed'), 'nr_mic_denied');
  assert.equal(speechErrorKey('no-speech'), 'nr_voice_nospeech');
  assert.equal(speechErrorKey('aborted'), '');
  assert.equal(speechErrorKey('network'), 'nr_voice_failed');
});
