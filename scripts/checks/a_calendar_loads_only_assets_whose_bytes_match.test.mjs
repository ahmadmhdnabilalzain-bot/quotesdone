// A CALENDAR LOADS ONLY ASSETS WHOSE BYTES MATCH (marketing, 23 Sep 2026).
//
// scripts/marketing/load_calendar.mjs downloads every video and key frame the month-1 calendar names from the
// private marketing-media bucket and compares its sha256 before the one-transaction load. This drives that
// verification with invented bytes: a match loads, a changed file, a missing file, a missing path and two
// different hashes for one file each stop the load.
//
//   node --test scripts/checks/a_calendar_loads_only_assets_whose_bytes_match.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { verifyAssets } from '../marketing/load_calendar.mjs';

const bytes = { 'campaigns/c/videos/01.mp4': Buffer.from('ZZ DEMO video'), 'campaigns/c/frames/01.jpg': Buffer.from('ZZ DEMO frame') };
const sha = (b) => createHash('sha256').update(b).digest('hex');
const fetchBytes = async (p) => bytes[p] || null;
const post = (over = {}) => ({ key: 'zz-demo-01', video: { path: 'marketing-media/campaigns/c/videos/01.mp4', sha256: sha(bytes['campaigns/c/videos/01.mp4']) },
  keyframe: { path: 'campaigns/c/frames/01.jpg', sha256: sha(bytes['campaigns/c/frames/01.jpg']) }, ...over });

test('matching bytes pass; every mismatch is named and stops the load', async () => {
  assert.deepEqual(await verifyAssets({ posts: [post(), post({ key: 'zz-demo-02' })] }, fetchBytes), []);
  const changed = await verifyAssets({ posts: [post({ video: { path: 'campaigns/c/videos/01.mp4', sha256: 'a'.repeat(64) } })] }, fetchBytes);
  assert.match(changed[0], /sha256 is [0-9a-f]{64}, the calendar says a{64}/);
  const missing = await verifyAssets({ posts: [post({ keyframe: { path: 'campaigns/c/frames/02.jpg', sha256: 'b'.repeat(64) } })] }, fetchBytes);
  assert.match(missing[0], /not in the private marketing-media bucket/);
  assert.equal((await verifyAssets({ posts: [post({ keyframe: null })] }, fetchBytes)).length, 1);
  const conflict = await verifyAssets({ posts: [post(), post({ key: 'zz-demo-02', video: { path: 'campaigns/c/videos/01.mp4', sha256: 'c'.repeat(64) } })] }, fetchBytes);
  assert.match(conflict.join('|'), /two different sha256/);
});
