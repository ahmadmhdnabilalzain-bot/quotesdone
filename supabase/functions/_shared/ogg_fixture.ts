// TEST-ONLY: a minimal ogg/opus voice note for _shared/speech_to_text.test.ts and wa_inbound's voice-note test (10 Nov 2026).
// Not imported by any function at runtime.
/** A minimal ogg/opus stream: an OpusHead page and a last page whose granule position is `seconds` at 48 kHz. */
export function oggOpus(seconds: number, padBytes = 64): Uint8Array<ArrayBuffer> {
  const page = (granule: bigint, packet: Uint8Array) => {
    const h = new Uint8Array(27 + 1 + packet.length);
    h.set([0x4f, 0x67, 0x67, 0x53], 0); new DataView(h.buffer).setBigUint64(6, granule, true);
    h[26] = 1; h[27] = packet.length; h.set(packet, 28); return h;
  };
  const head = new Uint8Array(19); head.set(new TextEncoder().encode('OpusHead'), 0); head[8] = 1; head[9] = 1;
  const a = page(0n, head), b = page(BigInt(Math.round(seconds * 48000)), new Uint8Array(Math.min(padBytes, 255)).fill(7));
  const out = new Uint8Array(a.length + b.length); out.set(a, 0); out.set(b, a.length); return out;
}
