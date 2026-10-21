// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const code = await readFile(new URL('../services/friends-fallback/dist/_worker.js', import.meta.url), 'utf8');
const { default: worker } = await import('data:text/javascript;base64,' + Buffer.from(code).toString('base64'));
for (const status of [200, 400, 401, 429, 503]) {
  const request = new Request('https://example.invalid/v1/state');
  const text = JSON.stringify({ error: '好友服务登录已失效' });
  const response = await worker.fetch(request, { FRIENDS_SERVICE: { fetch: async (forwarded) => {
    assert.equal(forwarded, request);
    return new Response(text, { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Retry-After': '15' } });
  } } });
  assert.equal(response.status, status);
  assert.equal(response.headers.get('Content-Type'), 'application/json; charset=utf-8');
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.equal(response.headers.get('Retry-After'), '15');
  assert.equal(await response.text(), text);
}
const other = new Response('plain', { headers: { 'Content-Type': 'text/plain' } });
assert.equal(await worker.fetch(new Request('https://example.invalid/'), { FRIENDS_SERVICE: { fetch: async () => other } }), other);
console.log('Gateway preserves body, status, headers and request; declares UTF-8 JSON.');
