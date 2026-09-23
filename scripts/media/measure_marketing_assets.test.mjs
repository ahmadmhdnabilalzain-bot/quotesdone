// The parsers the media worker turns ffmpeg/ffprobe output into features with. Offline, no ffmpeg needed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseRate, parseCutTimes, parseEbur128, parseRmsDb, parseYavg, aspectOf, musicFor } from './measure_marketing_assets.mjs';

test('frame rate, aspect', () => {
  assert.equal(parseRate('60/1'), 60);
  assert.equal(Math.round(parseRate('30000/1001') * 1000) / 1000, 29.97);
  assert.equal(aspectOf(1080, 1920), '9:16');
});

test('scene cuts from showinfo', () => {
  const log = '[Parsed_showinfo_1 @ 0x] n:   0 pts:  1234 pts_time:2.4 duration...\n[Parsed_showinfo_1 @ 0x] n:   1 pts: 9 pts_time:7.95 x';
  assert.deepEqual(parseCutTimes(log), [2.4, 7.95]);
});

test('EBU R128 summary: integrated loudness and true peak; silence is null', () => {
  const log = 'noise I: -30.0 LUFS\n[Parsed_ebur128_0 @ 0x] Summary:\n\n  Integrated loudness:\n    I:         -16.2 LUFS\n    Threshold: -26.4 LUFS\n\n  True peak:\n    Peak:       -1.1 dBFS';
  assert.deepEqual(parseEbur128(log), { lufs: -16.2, peak: -1.1 });
  assert.deepEqual(parseEbur128('Summary:\n I: -inf LUFS\n Peak: -inf dBFS'), { lufs: null, peak: null });
});

test('astats overall RMS and signalstats mean', () => {
  assert.equal(parseRmsDb('Channel: 1\nRMS level dB: -20.0\nOverall\nDC offset: 0\nRMS level dB: -18.5\n'), -18.5);
  assert.equal(parseYavg('lavfi.signalstats.YAVG=10\nlavfi.signalstats.YAVG=20\n'), 15);
});

test('music comes from the manifest row for the video, by name or by its number', () => {
  const manifest = [{ Video: '01_Stop_Chasing_Suppliers', Track: 'Lofi A', BPM: '88', Mood: 'calm' },
                    { Video: '2', Track: 'Lofi B', BPM: '92 bpm', Mood: 'warm' }];
  assert.deepEqual(musicFor(manifest, '01_Stop_Chasing_Suppliers_LoFiMix_60fps.mp4').bpm, 88);
  const two = musicFor(manifest, '02_Big_Plans_LoFiMix_60fps.mp4');
  assert.equal(two.bpm, 92); assert.equal(two.mood, 'warm');
  assert.equal(musicFor(manifest, '12_Other.mp4').on_file, false);
});
