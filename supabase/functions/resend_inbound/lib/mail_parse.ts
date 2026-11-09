// resend_inbound: small parsers for the inbound payload. Moved out of index.ts unchanged (9 Nov 2026).


export function addr(v: unknown){ if(!v) return ''; if(Array.isArray(v)) v=v[0]; const s=String((v as any)?.email||(v as any)?.address||v); const m=s.match(/<([^>]+)>/); return (m?m[1]:s).trim().toLowerCase(); }
export function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return {}; } }
export function stripHtml(s:string){ return String(s||'').replace(/<style[\s\S]*?<\/style>/gi,' ').replace(/<script[\s\S]*?<\/script>/gi,' ').replace(/<[^>]+>/g,' ').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&#36;/g,'$').replace(/\s+/g,' ').trim(); }
export function pickBody(d:any){ const t = d?.text || d?.plain || d?.['body-plain'] || d?.['stripped-text'] || d?.email?.text || d?.parsed?.text || ''; const h = d?.html || d?.['body-html'] || d?.email?.html || d?.parsed?.html || ''; let body = String(t||''); if (!body && h) body = stripHtml(String(h)); return body; }
export function b64ToBytes(b64:string){ const bin=atob(b64.replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
export function bytesToB64(u8:Uint8Array){ let bin=''; const c=0x8000; for(let i=0;i<u8.length;i+=c){ bin+=String.fromCharCode.apply(null, Array.from(u8.subarray(i,i+c))); } return btoa(bin); }
