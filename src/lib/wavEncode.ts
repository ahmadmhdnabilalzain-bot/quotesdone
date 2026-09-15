// A recording as 16 kHz mono 16-bit WAV, base64 — the one format the transcribe function sends on
// (it sniffs the bytes and accepts WAV or MP3). Moved here from components/me/NewRequest.tsx on
// 15 Sep 2026 so the supplier Services tab uses the same encoder instead of a second copy.
function encodeWav(samples: Float32Array, rate: number): ArrayBuffer {
  const buffer = new ArrayBuffer(44 + samples.length * 2); const view = new DataView(buffer);
  const ws = (o: number, str: string) => { for (let i = 0; i < str.length; i++) view.setUint8(o + i, str.charCodeAt(i)); };
  ws(0, 'RIFF'); view.setUint32(4, 36 + samples.length * 2, true); ws(8, 'WAVE'); ws(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true); view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true); ws(36, 'data'); view.setUint32(40, samples.length * 2, true);
  let o = 44; for (let i = 0; i < samples.length; i++) { const x = Math.max(-1, Math.min(1, samples[i])); view.setInt16(o, x < 0 ? x * 0x8000 : x * 0x7FFF, true); o += 2; }
  return buffer;
}

/** Decode any recorded blob, resample to 16 kHz mono and return { b64, bytes, durationMs }. */
export async function blobToWav(blob: Blob): Promise<{ b64: string; bytes: number; durationMs: number }> {
  const w = window as unknown as { AudioContext?: typeof AudioContext; webkitAudioContext?: typeof AudioContext };
  const AC = (w.AudioContext || w.webkitAudioContext)!; const ac = new AC();
  const buf = await ac.decodeAudioData(await blob.arrayBuffer());
  try { await ac.close(); } catch (_e) { /* nothing to release */ }
  const rate = 16000; const off = new OfflineAudioContext(1, Math.max(1, Math.ceil(buf.duration * rate)), rate);
  const src = off.createBufferSource(); src.buffer = buf; src.connect(off.destination); src.start();
  const pcm = (await off.startRendering()).getChannelData(0);
  // In 32 KB slices: one character at a time over ~2 MB stalled a phone's main thread (review, 15 Sep).
  const bytes = new Uint8Array(encodeWav(pcm, rate)); let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, Array.from(bytes.subarray(i, i + 0x8000)));
  return { b64: btoa(bin), bytes: bytes.length, durationMs: Math.round(buf.duration * 1000) };
}

export async function blobToWavB64(blob: Blob): Promise<string> { return (await blobToWav(blob)).b64; }
