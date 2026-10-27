// A browser walk adds its run tag and internal credential to edge-function calls (ruling 1260). Only this
// project's Supabase host, under /functions/v1/, may ever receive them (#1558 review).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { carriesRunTag } from '../e2e/browser.mjs';

const BASE = 'https://htdblwldjkcgjvmqkbeh.supabase.co';
test('our edge function gets it', () => assert.equal(carriesRunTag(BASE + '/functions/v1/supplier_api', BASE), true));
test('a foreign host with the same path does not', () => assert.equal(carriesRunTag('https://evil.example/functions/v1/supplier_api', BASE), false));
test('a look-alike host does not', () => assert.equal(carriesRunTag('https://htdblwldjkcgjvmqkbeh.supabase.co.evil.example/functions/v1/x', BASE), false));
test('the path only in a query string does not', () => assert.equal(carriesRunTag('https://checkout.stripe.com/pay?next=/functions/v1/x', BASE), false));
test('our host on another path does not', () => assert.equal(carriesRunTag(BASE + '/rest/v1/leads?x=/functions/v1/', BASE), false));
test('the site origin does not', () => assert.equal(carriesRunTag('https://quotesdone.com/functions/v1/supplier_api', BASE), false));
test('plain http does not', () => assert.equal(carriesRunTag('http://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/x', BASE), false));
