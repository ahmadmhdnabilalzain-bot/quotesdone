// VOICE TYPING WITHOUT A MODEL (founder, 14 Sep 2026: "the customer doesnt have voice recording option").
// The mic had been hidden because the only path was the transcribe edge function, a paid model call held
// with OpenRouter. The browser's own speech recognition (Web Speech API) costs nothing and returns text
// only: no audio is recorded, stored or uploaded by QuotesDone, so a voice never reaches a supplier.
// Support, measured against the vendors' docs: Chrome/Edge desktop + Android (webkitSpeechRecognition),
// Safari macOS 14.1+ and iOS 14.5+ (webkitSpeechRecognition), Samsung Internet; Firefox has none.

export type DictLang = 'en' | 'ar';

// Gulf locale first, then the variant every engine ships. Some engines refuse en-AE/ar-AE with
// 'language-not-supported'; the composer then retries with the next entry.
const LANGS: Record<DictLang, string[]> = { en: ['en-AE', 'en-US'], ar: ['ar-AE', 'ar-SA'] };

export function recognitionLangs(lang: string): string[] {
  return LANGS[lang === 'ar' ? 'ar' : 'en'];
}

// The constructor, or null where the browser has none (Firefox, old Safari, SSR).
export function getRecognition(win: any = typeof window === 'undefined' ? undefined : window): any {
  if (!win) return null;
  return win.SpeechRecognition || win.webkitSpeechRecognition || null;
}

// What the composer shows for a recognition error; null means "retry with the fallback language".
export function speechErrorKey(error: string): string | null {
  if (error === 'language-not-supported') return null;
  if (error === 'not-allowed' || error === 'service-not-allowed' || error === 'audio-capture') return 'nr_mic_denied';
  if (error === 'no-speech') return 'nr_voice_nospeech';
  if (error === 'aborted') return '';
  return 'nr_voice_failed';
}
