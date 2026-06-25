import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getWatchAdapter, listWatchAdapters } from './adapters/index.js';
import { detectAiSessions } from './detect.js';
import { ApprovalStore } from './store.js';

const rootDir = join(fileURLToPath(import.meta.url), '..', '..');

async function readJson(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }

  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function sendJson(response, status, body) {
  response.writeHead(status, {
    'content-type': 'application/json',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type'
  });
  response.end(JSON.stringify(body));
}

function sendText(response, status, text, contentType = 'text/plain; charset=utf-8') {
  response.writeHead(status, { 'content-type': contentType });
  response.end(text);
}

function routePattern(pathname, pattern) {
  const pathParts = pathname.split('/').filter(Boolean);
  const patternParts = pattern.split('/').filter(Boolean);
  if (pathParts.length !== patternParts.length) return null;

  const params = {};
  for (let index = 0; index < patternParts.length; index += 1) {
    const expected = patternParts[index];
    const actual = pathParts[index];
    if (expected.startsWith(':')) {
      params[expected.slice(1)] = actual;
    } else if (expected !== actual) {
      return null;
    }
  }

  return params;
}

export function createApprovalServer({ store = new ApprovalStore() } = {}) {
  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');

      if (request.method === 'OPTIONS') {
        sendJson(response, 204, {});
        return;
      }

      if (request.method === 'GET' && url.pathname === '/') {
        const html = await readFile(join(rootDir, 'public', 'index.html'), 'utf8');
        sendText(response, 200, html, 'text/html; charset=utf-8');
        return;
      }

      if (request.method === 'GET' && url.pathname === '/health') {
        sendJson(response, 200, { ok: true, adapters: listWatchAdapters() });
        return;
      }

      if (request.method === 'GET' && url.pathname === '/api/sessions') {
        const sessions = await detectAiSessions();
        sendJson(response, 200, sessions.map((session) => ({
          pid: session.pid,
          executable: session.executable,
          tools: session.tools
        })));
        return;
      }

      if (request.method === 'POST' && url.pathname === '/api/requests') {
        const body = await readJson(request);
        const created = store.create(body);
        sendJson(response, 201, created);
        return;
      }

      if (request.method === 'GET' && url.pathname === '/api/requests') {
        sendJson(response, 200, store.list());
        return;
      }

      if (request.method === 'GET' && url.pathname === '/api/requests/next') {
        const adapter = getWatchAdapter(url.searchParams.get('watchType') || 'apple-watch');
        const pending = store.nextPending();
        sendJson(response, 200, pending ? adapter.shapeRequest(pending) : null);
        return;
      }

      const requestMatch = routePattern(url.pathname, '/api/requests/:id');
      if (request.method === 'GET' && requestMatch) {
        const current = store.get(requestMatch.id);
        sendJson(response, current ? 200 : 404, current || { error: 'not_found' });
        return;
      }

      const decisionMatch = routePattern(url.pathname, '/api/requests/:id/decision');
      if (request.method === 'POST' && decisionMatch) {
        const body = await readJson(request);
        const result = store.decide(decisionMatch.id, body.decision, {
          actor: body.actor,
          watchType: body.watchType
        });

        if (result.error === 'not_found') {
          sendJson(response, 404, { error: result.error });
          return;
        }

        if (result.error) {
          sendJson(response, 409, { error: result.error, request: result.request });
          return;
        }

        sendJson(response, 200, result.request);
        return;
      }

      sendJson(response, 404, { error: 'not_found' });
    } catch (error) {
      sendJson(response, 400, { error: error.message });
    }
  });

  return { server, store };
}
