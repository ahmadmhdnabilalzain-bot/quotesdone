// node --test src/components/portal/supplier/profileSessionEnded.test.mjs
// Walk of 12 Nov 2026, S3 (sales_engineer, built by it_engineer): when the sign-in ended mid-edit the Profile tab said "what you
// typed and ticked here is kept", but edit mode keeps no draft (ProfileForm skips saveDraft when isEdit) and only "Sign out" was on
// screen (w2_iphone_expired_mid_form.jpg). This fails if the Profile tab promises a kept draft again or loses its "Sign in again".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { t } from './core/copy.ts';

const form = readFileSync(new URL('./core/ProfileForm.tsx', import.meta.url), 'utf8');
const panel = readFileSync(new URL('./core/Onboarding.tsx', import.meta.url), 'utf8');

test('the Profile tab says its changes were not saved and are not kept, and offers the sign-in', () => {
  assert.match(form, /if \(isEdit\) return undefined;\s*\n\s*const id = setTimeout\(\(\) => saveDraft/, 'edit mode saves a draft now: the wording may say so again');
  assert.doesNotMatch(t('en', 'session_ended_edit'), /kept/i);
  assert.match(t('en', 'session_ended_edit'), /not saved/);
  assert.match(form, /setMsg\(t\(lang, isEdit \? 'session_ended_edit' : 'session_ended_form'\)\)/);
  assert.match(form, /data-testid="sign-in-again"[^\n]*await onExpired\(\)/);
  assert.match(panel, /mode="edit"[^\n]*onExpired=\{onExpired\}/, 'the Profile tab is not given the sign-in');
});
