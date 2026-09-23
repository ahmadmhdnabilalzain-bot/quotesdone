'use client';
import { useEffect } from 'react';
import { captureFirstTouch } from '@/lib/firstTouch';

// Keeps the first tagged visit's UTM (src/lib/firstTouch.ts). Renders nothing.
export function FirstTouch() {
  useEffect(() => { try { captureFirstTouch(window.location.href, window.localStorage); } catch (_e) {} }, []);
  return null;
}
