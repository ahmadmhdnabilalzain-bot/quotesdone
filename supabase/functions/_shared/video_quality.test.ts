import { assertEquals } from 'jsr:@std/assert@1';
import { belowFloor, belowRecommended, readMp4 } from './video_quality.ts';
// The one fixture is the real header shape; a synthetic one is built in marketing-asset-features.yml. Here: no moov -> null.
Deno.test('a non-MP4 is unreadable and therefore refused', () => {
  assertEquals(readMp4(new Uint8Array(16)), null);
  assertEquals(belowRecommended('youtube', null).length, 1);
});
Deno.test('YouTube 1080p60 at 817 kbps is refused; a platform with no bitrate floor passes it', () => {
  const info = { duration_s: 28, tracks: [{ kind: 'video' as const, codec: 'avc1.64002a', width: 1080, height: 1920, fps: 60, kbps: 817 }, { kind: 'audio' as const, codec: 'mp4a', channels: 1, sample_rate: 44100, kbps: 151 }] };
  assertEquals(belowRecommended('youtube', info).length, 2);
  assertEquals(belowRecommended('instagram', info), []);
  assertEquals(belowRecommended('tiktok', { ...info, tracks: [{ ...info.tracks[0], width: 720, height: 1280 }] }).length, 1);
});
Deno.test('the month-1 file (1080x1920 60fps 817 kbps mono) is the floor: it passes; below it is refused', () => {
  const v = { kind: 'video' as const, codec: 'avc1.64002a', width: 1080, height: 1920, fps: 60, kbps: 817 };
  const a = { kind: 'audio' as const, codec: 'mp4a', channels: 1, sample_rate: 44100, kbps: 151 };
  assertEquals(belowFloor({ duration_s: 28, tracks: [v, a] }), []);
  assertEquals(belowFloor({ duration_s: 28, tracks: [{ ...v, codec: 'hvc1', fps: 30, kbps: 694 }, a] }), []);
  assertEquals(belowFloor({ duration_s: 28, tracks: [{ ...v, kbps: 640 }, a] }).length, 1);
  assertEquals(belowFloor({ duration_s: 28, tracks: [{ ...v, fps: 25 }, a] }).length, 1);
  assertEquals(belowFloor({ duration_s: 28, tracks: [{ ...v, width: 720, height: 1280 }, a] }).length, 1);
  assertEquals(belowFloor({ duration_s: 28, tracks: [{ ...v, codec: 'vp09' }, a] }).length, 1);
  assertEquals(belowFloor(null).length, 1);
});
