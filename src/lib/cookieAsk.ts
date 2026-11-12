// THE FIRST-VISIT MARK, AS A PLAIN MODULE (12 Nov 2026, review of the cookie notice, item 4): the server layout runs this text as an
// inline script before any content, so the notice (src/components/CookieConsent.tsx) is in the first paint when no cookie choice is
// stored. Kept out of the 'use client' component so the server layout does not import it across the client boundary.
export const COOKIE_ASK = "try{if(!localStorage.getItem('qd-cookie-consent'))document.documentElement.setAttribute('data-qd-cookie','ask')}catch(e){}";
