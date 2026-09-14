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
// WHERE tesseract loads from, pinned to exact versions on cdn.jsdelivr.net (see the CSP comment in
// next.config.mjs): worker tesseract.js@7.0.0 (~110 KB), core tesseract.js-core@7.0.0 (the LSTM wasm
// build, ~3.9 MB uncompressed), traineddata @tesseract.js-data/<lang>/4.0.0_best_int (tesseract's
// own default for LSTM; measured 14 Sep 2026: eng 2.95 MB + ara 1.66 MB gzipped). The browser caches
// all of it after the first OCR. Self-hosting would put ~8 MB of wasm variants in /public for no gain.
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

// Pinned CDN locations. Bump together with package.json, never to a floating tag.
const TESSERACT_WORKER = 'https://cdn.jsdelivr.net/npm/tesseract.js@7.0.0/dist/worker.min.js';
const TESSERACT_CORE = 'https://cdn.jsdelivr.net/npm/tesseract.js-core@7.0.0';

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
    workerPath: TESSERACT_WORKER,
    corePath: TESSERACT_CORE,
    // langPath left to tesseract's pinned default (@tesseract.js-data/<lang>/4.0.0_best_int): a
    // single explicit langPath would be shared by eng and ara and break the per-language folder.
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
