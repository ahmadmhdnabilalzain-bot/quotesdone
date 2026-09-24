import { assertEquals } from 'jsr:@std/assert@1';
import { belowUploadSpec, readMp4 } from './video_quality.ts';
// The one fixture is the real header shape; a synthetic one is built in marketing-asset-features.yml. Here: no moov -> null.
Deno.test('a non-MP4 is unreadable and therefore refused', () => {
  assertEquals(readMp4(new Uint8Array(16)), null);
  assertEquals(belowUploadSpec('youtube', null).length, 1);
});
Deno.test('YouTube 1080p60 at 817 kbps is refused; a platform with no bitrate floor passes it', () => {
  const info = { duration_s: 28, tracks: [{ kind: 'video' as const, codec: 'avc1.64002a', width: 1080, height: 1920, fps: 60, kbps: 817 }, { kind: 'audio' as const, codec: 'mp4a', channels: 1, sample_rate: 44100, kbps: 151 }] };
  assertEquals(belowUploadSpec('youtube', info).length, 2);
  assertEquals(belowUploadSpec('instagram', info), []);
  assertEquals(belowUploadSpec('tiktok', { ...info, tracks: [{ ...info.tracks[0], width: 720, height: 1280 }] }).length, 1);
});
