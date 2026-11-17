// Synthetic contract checks; do not imply hosted engine/licensing acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {handle} from '../functions/teamstats-pdf-validator/index.ts';
const source='https://github.com/nanu731/rps-bball-app/tree/'+ '0'.repeat(40)+'/supabase/functions/teamstats-pdf-validator';
const key='SYNTHETIC_ONLY_NOT_A_DEPLOYMENT_KEY';
const settings={enabled:'reviewed_nonproduction',key,source};
const url='http://127.0.0.1/validate';
test('unconfigured/disabled validator fails closed without importing the engine',async()=>{
 for(const config of [{},{...settings,enabled:undefined},{...settings,key:'short'},{...settings,source:'https://example.invalid/source'}]) {
  const reply=await handle(new Request(url,{method:'POST',body:'TEST ONLY'}),config);
  assert.equal(reply.status,503);assert.deepEqual(await reply.json(),{error:'validation_unavailable'});
 }
 const health=await handle(new Request('http://127.0.0.1/health'),settings);
 assert.equal(health.status,503);assert.match((await health.json()).readiness,/disabled/);
});
test('server-only authorization, no browser preflight permission and bounded inputs',async()=>{
 const denied=await handle(new Request(url,{method:'POST',headers:{Authorization:'Bearer SYNTHETIC_WRONG_KEY'},body:'TEST ONLY PRIVATE CONTENT'}),settings);
 assert.equal(denied.status,403);assert.doesNotMatch(await denied.text(),/PRIVATE|WRONG_KEY/);
 const preflight=await handle(new Request(url,{method:'OPTIONS',headers:{Origin:'https://untrusted.example.invalid'}}),settings);
 assert.equal(preflight.status,404);assert.equal(preflight.headers.get('Access-Control-Allow-Origin'),null);
 const tooBig=await handle(new Request(url,{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Length':'5242881'}}),settings);
 assert.equal(tooBig.status,413);
 const mismatch=await handle(new Request(url,{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Length':'5'},body:'abc'}),settings);
 assert.equal(mismatch.status,422);
});
test('cancellation releases the local lease and source offer contains no private configuration',async()=>{
 const controller=new AbortController();controller.abort();
 const reply=await handle(new Request(url,{method:'POST',signal:controller.signal,headers:{Authorization:'Bearer '+key},body:'TEST ONLY'}),settings);
 assert.equal(reply.status,503);
 const again=await handle(new Request(url,{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Length':'5'},body:'abc'}),settings);
 assert.equal(again.status,422);
 const offer=await handle(new Request('http://127.0.0.1/source'),settings);
 const body=await offer.text();assert.match(body,/AGPL-3.0-or-later/);assert.doesNotMatch(body,/SYNTHETIC_ONLY|VALIDATION_KEY/);
});
test('one worker lease rejects overlap, releases on cancellation and bounds undeclared streams',async()=>{
 let started;const reading=new Promise(resolve=>{started=resolve;});
 const controller=new AbortController();
 const stream=new ReadableStream({pull(){started();}},{highWaterMark:0});
 const first=handle(new Request(url,{method:'POST',headers:{Authorization:'Bearer '+key},body:stream,duplex:'half',signal:controller.signal}),settings);
 await reading;
 const second=await handle(new Request(url,{method:'POST',headers:{Authorization:'Bearer '+key},body:'TEST ONLY'}),settings);
 assert.equal(second.status,503);assert.equal(second.headers.get('Retry-After'),'1');
 controller.abort();assert.equal((await first).status,503);
 const oversized=new ReadableStream({start(c){c.enqueue(new Uint8Array(5*1024*1024+1));c.close();}});
 const result=await handle(new Request(url,{method:'POST',headers:{Authorization:'Bearer '+key},body:oversized,duplex:'half'}),settings);
 assert.equal(result.status,413);
});
