// Built-in Node test runner; no installed packages. Actual Functions acceptance
// is separate from this injected worker transport contract.
import test from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../functions/teamstats-files/index.ts';
const worker = 'http://127.0.0.1:55448';
const id = '11111111-1111-4111-8111-111111111111';
const base = 'http://127.0.0.1:55431/functions/v1/teamstats-files';
const headers = { Authorization: 'Bearer synthetic-local-test' };
test('unconfigured or nonloopback worker is unavailable before any transfer', async () => {
  for (const config of [undefined, 'https://example.invalid', worker + '/other']) {
    const result = await handle(new Request(base + '/files/' + id + '?operation=' + id, {headers}), config, () => assert.fail('no transfer'));
    assert.equal(result.status, 503);
  }
});
test('route and identity rejection never reaches worker', async () => {
  for (const path of ['/files/' + id, '/files/' + id + '?operation=' + id + '&operation=' + id, '/uploads/not-an-id', '/uploads/' + id + '/other', '/files/' + id + '?operation=' + id + '&url=https://example.invalid']) {
    const result = await handle(new Request(base + path, {headers}), worker, () => assert.fail('no transfer'));
    assert.equal(result.status, 404);
  }
  assert.equal((await handle(new Request(base + '/files/' + id + '?operation=' + id), worker)).status, 401);
});
test('exact bounded upload forwards only caller credentials and preserves receipt', async () => {
  const result = await handle(new Request(base + '/uploads/' + id, {method:'POST',headers:{...headers,'Content-Length':'3',apikey:'never-forward'},body:'abc'}), worker, async (url, init) => {
    assert.equal(url, worker + '/uploads/' + id);
    assert.equal(init.headers.get('Content-Length'), '3');
    assert.equal(init.headers.get('apikey'), null);
    assert.equal(init.redirect, 'error');
    assert.equal(new TextDecoder().decode(init.body), 'abc');
    return Response.json({status:'ready'});
  });
  assert.equal(result.status, 200);
  assert.equal((await result.json()).status, 'ready');
});
test('Functions passes function-name-relative paths after its API gateway', async () => {
  const result = await handle(new Request('http://127.0.0.1:8081/teamstats-files/uploads/' + id + '/reconcile', {method:'POST',headers}), worker,
    async (url, init) => { assert.equal(url, worker + '/uploads/' + id + '/reconcile'); assert.equal(init.body.byteLength,0); return Response.json({status:'failed'}); });
  assert.equal(result.status,200);
});
test('reconciliation has no upload body; declared and actual overflows fail safely', async () => {
  const route = base + '/uploads/' + id;
  assert.equal((await handle(new Request(route, {method:'POST',headers:{...headers,'Content-Length':'10485761'},body:'a'}), worker, () => assert.fail('no transfer'))).status, 413);
  assert.equal((await handle(new Request(route, {method:'POST',headers:{...headers,'Content-Length':'2'},body:'a'}), worker, () => assert.fail('no transfer'))).status, 400);
  assert.equal((await handle(new Request(route + '/reconcile', {method:'POST',headers,body:'a'}), worker, () => assert.fail('no transfer'))).status, 503);
});
test('delivery keeps digest, bounds response, and never follows redirects', async () => {
  const request = new Request(base + '/files/' + id + '?operation=' + id, {headers});
  const result = await handle(request, worker, async () => new Response('abc',{headers:{'Content-Length':'3','Content-Type':'video/mp4','X-TeamStats-SHA256':'synthetic'}}));
  assert.equal(await result.text(), 'abc'); assert.equal(result.headers.get('X-TeamStats-SHA256'),'synthetic');
  assert.equal((await handle(request, worker, async () => new Response('a',{headers:{'Content-Length':'10485761'}}))).status,502);
  assert.equal((await handle(request, worker, async () => new Response('a',{headers:{'Content-Length':'2'}}))).status,502);
  assert.equal((await handle(request, worker, async () => {throw new Error('private provider diagnostic');})).status,503);
});
test('unexpected worker error bodies never disclose private diagnostics', async () => {
  const request = new Request(base + '/files/' + id + '?operation=' + id, {headers});
  for (const body of ['private provider diagnostic', JSON.stringify({error:'private_provider_diagnostic'}), JSON.stringify({error:'access_denied',debug:'private provider diagnostic'})]) {
    const result = await handle(request,worker,async()=>new Response(body,{status:503}));
    assert.equal((await result.json()).error,'operation_unconfirmed_reconcile');
  }
  const denied = await handle(request,worker,async()=>Response.json({error:'access_denied'},{status:403}));
  assert.deepEqual(await denied.json(),{error:'access_denied'});
});
