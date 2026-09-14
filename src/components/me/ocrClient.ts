// Photos and scanned BOQs -> images and text, in the CUSTOMER'S BROWSER.
//
// WHY: the model/vision routes are on hold (no paid inference), and a Supabase Edge function gets
// ~2 s of CPU per request, too little for OCR. So free OCR runs here, on the customer's machine, and
// the server receives plain text it can parse deterministically.
//
// WHAT:
//   toJpegPages(file) -> base64 images for the existing drawing/image path. JPEG/PNG/WebP pass through
//     (downscaled if wider than 2400 px); HEIC/HEIF are decoded by the browser itself (Safari can,
//     most others cannot -> HEIC_UNSUPPORTED); TIFF is decoded with utif (MIT), up to 10 pages.
//   ocrImages(images) -> tesseract.js (Apache-2.0), 'eng+ara' by default, one worker reused across
//     up to 10 pages and terminated at the end. Returns the joined text and mean confidence (0-100).
//
// WHERE tesseract loads from: SELF-HOSTED under /public/ocr, same origin, so the CSP trusts no new
// host (see next.config.mjs). A CDN such as jsDelivr serves anything anyone publishes, and trusting it
// in script-src would let any package run on every page. Files, pinned and hashed (sha256, 14 Sep 2026):
//   /ocr/worker.min.js                            tesseract.js@7.0.0            111 KB
//     576b7df7e3393e137e51849357c9adb53fe7ac1bb69bfa06cf3d61520f182c6d
//   /ocr/core/tesseract-core-relaxedsimd-lstm.wasm.js  tesseract.js-core@7.0.0  3.9 MB
//   /ocr/core/tesseract-core-simd-lstm.wasm.js         tesseract.js-core@7.0.0  3.9 MB
//   /ocr/core/tesseract-core-lstm.wasm.js              tesseract.js-core@7.0.0  3.9 MB
//     (the worker's getCore loads exactly ONE of the three, by the browser's SIMD support; LSTM-only
//      because createWorker is called with OEM 1; hashes in public/ocr/SHA256SUMS)
//   /ocr/lang/eng.traineddata.gz   @tesseract.js-data/eng@1.0.0 4.0.0_best_int  2.95 MB
//     45b4cb346724ac1774f1c36f42f182b887bcdb28ebe63e6fff90ac41f3fcff91
//   /ocr/lang/ara.traineddata.gz   @tesseract.js-data/ara@1.0.0 4.0.0_best_int  1.66 MB
//     f4746c44b02342dd5b3d4f0198000f47d7c49f1a229e63e0f436c0592dcd9639
// FIRST USE costs the customer ~8.5 MB (111 KB worker + one 3.9 MB core + 4.6 MB language data); the
// browser caches it. None of it loads on page load: only when a photo or scan is attached.
//
// HEIC: heic2any was rejected. It bundles libheif (LGPL-3) and libheif's author disputes that
// bundling. iPhones already hand a JPEG to a file picker that does not list HEIC, so the fallback is
// a clear error, not a second decoder.
//
// WHAT IT NEVER DOES: it never uploads an image anywhere itself. The only network traffic is the
// tesseract code and language data coming IN. The OCR text is untrusted input: the server parses and
// scrubs it like anything else a customer types.
//
// Nothing here touches a browser API at import time; every library is a dynamic import, so the
// portal's main bundle does not grow until a customer actually attaches a photo or scan.

export type PageImage = { mime: string; data: string };

const MAX_WIDTH = 2400;
const MAX_PAGES = 10;
const JPEG_QUALITY = 0.85;

// Self-hosted, same-origin locations (absolute, because a worker resolves relative URLs against its own
// script). Bump the files together with package.json, never to a floating tag.
const ocrUrl = (p: string) => `${window.location.origin}/ocr/${p}`;

/** Thrown when the browser cannot decode a HEIC/HEIF photo. The UI maps it to "export as JPEG". */
export const HEIC_UNSUPPORTED = 'HEIC_UNSUPPORTED';

function canvasToJpeg(c: HTMLCanvasElement): PageImage {
  return { mime: 'image/jpeg', data: c.toDataURL('image/jpeg', JPEG_QUALITY).split(',')[1] };
}

function drawScaled(src: CanvasImageSource, w: number, h: number): HTMLCanvasElement {
  const s = Math.min(1, MAX_WIDTH / w);
  const c = document.createElement('canvas');
  c.width = Math.round(w * s); c.height = Math.round(h * s);
  const ctx = c.getContext('2d') as CanvasRenderingContext2D;
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height); // transparent PNG -> white, not black
  ctx.drawImage(src, 0, 0, c.width, c.height);
  return c;
}

async function fileToBase64(file: Blob): Promise<string> {
  const buf = new Uint8Array(await file.arrayBuffer());
  let bin = '';
  for (let i = 0; i < buf.length; i += 0x8000) bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(bin);
}

export async function toJpegPages(file: File): Promise<PageImage[]> {
  const type = (file.type || '').toLowerCase();
  const name = file.name.toLowerCase();

  if (type === 'image/tiff' || /\.tiff?$/.test(name)) {
    // @ts-ignore utif ships no type declarations
    const mod: any = await import('utif');
    const UTIF = mod.default || mod;
    const buf = await file.arrayBuffer();
    const ifds = UTIF.decode(buf).slice(0, MAX_PAGES);
    const out: PageImage[] = [];
    for (const ifd of ifds) {
      UTIF.decodeImage(buf, ifd);
      const w = ifd.width, h = ifd.height;
      if (!w || !h) continue; // thumbnails / non-image IFDs
      const full = document.createElement('canvas');
      full.width = w; full.height = h;
      const ctx = full.getContext('2d') as CanvasRenderingContext2D;
      ctx.putImageData(new ImageData(new Uint8ClampedArray(UTIF.toRGBA8(ifd)), w, h), 0, 0);
      out.push(canvasToJpeg(w > MAX_WIDTH ? drawScaled(full, w, h) : full));
    }
    return out;
  }

  const heic = /^image\/hei[cf]/.test(type) || /\.hei[cf]$/.test(name);
  let bmp: ImageBitmap;
  try {
    bmp = await createImageBitmap(file);
  } catch (e) {
    if (heic) throw new Error(HEIC_UNSUPPORTED);
    throw e;
  }
  try {
    const passThrough = !heic && /^image\/(jpeg|png|webp)$/.test(type) && bmp.width <= MAX_WIDTH;
    if (passThrough) return [{ mime: type, data: await fileToBase64(file) }];
    return [canvasToJpeg(drawScaled(bmp, bmp.width, bmp.height))];
  } finally {
    bmp.close();
  }
}

export async function ocrImages(
  images: PageImage[],
  opts?: { langs?: string; onProgress?: (p: number) => void },
): Promise<{ text: string; confidence: number; pages: number }> {
  const pages = images.slice(0, MAX_PAGES);
  if (!pages.length) return { text: '', confidence: 0, pages: 0 };
  const { createWorker } = await import('tesseract.js');
  let done = 0;
  const worker = await createWorker(opts?.langs || 'eng+ara', 1 /* LSTM only */, {
    workerPath: ocrUrl('worker.min.js'),
    corePath: ocrUrl('core'),
    langPath: ocrUrl('lang'),
    // Load the worker from its own URL (worker-src 'self') rather than a blob: bootstrap.
    workerBlobURL: false,
    logger: (m: { status: string; progress: number }) => {
      if (m.status === 'recognizing text') opts?.onProgress?.((done + m.progress) / pages.length);
    },
  });
  try {
    const texts: string[] = [];
    let conf = 0;
    for (const img of pages) {
      const { data } = await worker.recognize(`data:${img.mime};base64,${img.data}`);
      texts.push(data.text.trim());
      conf += data.confidence;
      done++;
      opts?.onProgress?.(done / pages.length);
    }
    return { text: texts.join('\n\n--- page break ---\n\n'), confidence: conf / pages.length, pages: pages.length };
  } finally {
    await worker.terminate();
  }
}
