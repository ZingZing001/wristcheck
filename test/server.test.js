import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { createApprovalServer } from '../src/server.js';

let app;
let baseUrl;

before(async () => {
  app = createApprovalServer();
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const { port } = app.server.address();
  baseUrl = `http://127.0.0.1:${port}`;
});

after(async () => {
  await new Promise((resolve) => app.server.close(resolve));
});

async function json(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...options.headers
    }
  });

  return {
    status: response.status,
    body: await response.json()
  };
}

test('creates a pending approval request and exposes it to Apple Watch clients', async () => {
  const created = await json('/api/requests', {
    method: 'POST',
    body: JSON.stringify({
      title: 'Run tests',
      summary: 'Copilot wants to run the focused test suite.',
      preview: 'npm test -- --runInBand',
      source: 'copilot-cli'
    })
  });

  assert.equal(created.status, 201);
  assert.equal(created.body.status, 'pending');

  const next = await json('/api/requests/next?watchType=apple-watch');
  assert.equal(next.status, 200);
  assert.equal(next.body.id, created.body.id);
  assert.equal(next.body.title, 'Run tests');
});

test('records a watch decision once', async () => {
  const created = await json('/api/requests', {
    method: 'POST',
    body: JSON.stringify({ title: 'Apply patch' })
  });

  const approved = await json(`/api/requests/${created.body.id}/decision`, {
    method: 'POST',
    body: JSON.stringify({
      decision: 'approved',
      actor: 'Johnson Apple Watch',
      watchType: 'apple-watch'
    })
  });

  assert.equal(approved.status, 200);
  assert.equal(approved.body.status, 'approved');
  assert.equal(approved.body.decidedBy, 'Johnson Apple Watch');

  const denied = await json(`/api/requests/${created.body.id}/decision`, {
    method: 'POST',
    body: JSON.stringify({ decision: 'denied' })
  });

  assert.equal(denied.status, 409);
  assert.equal(denied.body.error, 'already_decided');
});

test('reports detected local AI sessions', async () => {
  const sessions = await json('/api/sessions');

  assert.equal(sessions.status, 200);
  assert.ok(Array.isArray(sessions.body));
});
