#!/usr/bin/env node
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import { dirname, join } from 'node:path';
import process from 'node:process';
import { createInterface } from 'node:readline/promises';
import { detectAiSessions, formatDetectedSessions } from '../src/detect.js';
import { createApprovalServer } from '../src/server.js';

const DEFAULT_URL = 'http://127.0.0.1:8787';
const APPROVAL_STATE_FILE = join(os.homedir(), '.wristcheck', 'approval-state.json');

function parseArgs(argv) {
  const [command = 'help', ...rest] = argv;
  const flags = {};

  for (let index = 0; index < rest.length; index += 1) {
    const arg = rest[index];
    if (!arg.startsWith('--')) continue;

    const key = arg.slice(2);
    if (key.startsWith('no-')) {
      flags[key.slice(3)] = false;
      continue;
    }

    const next = rest[index + 1];
    if (!next || next.startsWith('--')) {
      flags[key] = true;
      continue;
    }

    flags[key] = next;
    index += 1;
  }

  return { command, flags };
}

function usage() {
  return `wristcheck

Approve AI/Copilot steps from your watch.

Commands:
  wristcheck serve [--host 127.0.0.1] [--port 8787]
  wristcheck doctor
  wristcheck request --title "Run migration" --summary "Adds users table" --preview "$(git diff --stat)"

Request flags:
  --server http://127.0.0.1:8787
  --source copilot-cli
  --timeout-seconds 300
  --fallback-delay-seconds 10
  --wait / --no-wait
  --cli / --no-cli
`;
}

function getLanAddresses(port) {
  return Object.values(os.networkInterfaces())
    .flat()
    .filter((entry) => entry && entry.family === 'IPv4' && !entry.internal)
    .map((entry) => `http://${entry.address}:${port}`);
}

async function readStdinIfAvailable() {
  if (process.stdin.isTTY) return '';

  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }

  return Buffer.concat(chunks).toString('utf8').trim();
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });

  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(json.error || `${response.status} ${response.statusText}`);
  }

  return json;
}

async function getJson(url) {
  const response = await fetch(url);
  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(json.error || `${response.status} ${response.statusText}`);
  }

  return json;
}

async function readApprovalState() {
  try {
    return JSON.parse(await readFile(APPROVAL_STATE_FILE, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return { cliAway: false };
    throw error;
  }
}

async function writeApprovalState(state) {
  await mkdir(dirname(APPROVAL_STATE_FILE), { recursive: true });
  await writeFile(APPROVAL_STATE_FILE, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
}

async function runServe(flags) {
  const host = String(flags.host || '127.0.0.1');
  const port = Number(flags.port || 8787);
  const app = createApprovalServer();

  app.server.listen(port, host, () => {
    console.log(`wristcheck approval server listening on http://${host}:${port}`);
    for (const address of getLanAddresses(port)) {
      console.log(`watch/client URL: ${address}`);
    }
    console.log('Open the Watch app settings and use the watch/client URL for pairing.');
  });
}

async function runDoctor(flags) {
  const port = Number(flags.port || 8787);
  const lanAddresses = getLanAddresses(port);

  console.log('WristCheck doctor');
  console.log('');
  console.log(`Local server URL: ${DEFAULT_URL}`);
  if (lanAddresses.length > 0) {
    console.log('Watch pairing URLs:');
    for (const address of lanAddresses) {
      console.log(`  ${address}`);
    }
  } else {
    console.log('No LAN address found. Connect to Wi-Fi so the Watch can reach this Mac.');
  }

  console.log('');
  console.log('Detected AI sessions:');
  console.log(formatDetectedSessions(await detectAiSessions()));
}

async function runRequest(flags) {
  const serverUrl = String(flags.server || process.env.WRISTCHECK_SERVER || DEFAULT_URL).replace(/\/$/, '');
  const timeoutSeconds = Number(flags['timeout-seconds'] || 300);
  const fallbackDelaySeconds = Number(flags['fallback-delay-seconds'] || 10);
  const preview = flags.preview ? String(flags.preview) : await readStdinIfAvailable();
  const title = String(flags.title || 'Copilot step approval');
  const summary = String(flags.summary || 'Review this AI step before it continues.');
  const wait = flags.wait !== false;
  const cliApproval = flags.cli !== false && process.stdin.isTTY && process.stdout.isTTY;
  const approvalState = await readApprovalState();
  const effectiveFallbackDelaySeconds = approvalState.cliAway ? 0 : fallbackDelaySeconds;

  const createRequest = () => postJson(`${serverUrl}/api/requests`, {
    title,
    summary,
    preview,
    source: String(flags.source || 'copilot-cli'),
    timeoutSeconds
  });

  if (!wait || !cliApproval) {
    const request = await createRequest();
    console.log(`approval request ${request.id} created`);

    if (!wait) return;

    const deadline = Date.now() + timeoutSeconds * 1000;
    const result = await waitForRemoteDecision(serverUrl, request.id, deadline, new AbortController().signal);
    applyDecisionExit(result);
    return;
  }

  console.log(approvalState.cliAway
    ? 'CLI was idle on the previous approval. WristCheck fallback starts immediately until you approve/deny in CLI.'
    : `Approve or deny in this terminal. WristCheck fallback starts after ${fallbackDelaySeconds} seconds without a CLI response.`);
  const deadline = Date.now() + timeoutSeconds * 1000;
  const abortController = new AbortController();
  const fallbackRequests = [];

  async function createFallbackRequest() {
    const request = await createRequest();
    fallbackRequests.push(request);
    console.log(`WristCheck fallback triggered: approval request ${request.id} created`);
    return request;
  }

  const result = await Promise.race([
    waitForRepeatedFallbackDecision(serverUrl, effectiveFallbackDelaySeconds, deadline, createFallbackRequest, fallbackRequests, abortController.signal),
    waitForCliDecision(async (decision) => {
      await writeApprovalState({ cliAway: false, updatedAt: new Date().toISOString() });
      if (fallbackRequests.length === 0) return { status: decision, decidedBy: 'CLI' };

      return decideFallbackRequests(serverUrl, fallbackRequests, decision);
    }, abortController.signal)
  ]);

  abortController.abort();
  applyDecisionExit(result);
}

async function waitForRepeatedFallbackDecision(serverUrl, fallbackDelaySeconds, deadline, createFallbackRequest, fallbackRequests, signal) {
  await sleep(fallbackDelaySeconds * 1000, signal);
  if (signal.aborted) return new Promise(() => {});

  await writeApprovalState({ cliAway: true, updatedAt: new Date().toISOString() });

  while (Date.now() < deadline && !signal.aborted) {
    await createFallbackRequest();

    const decision = await firstRemoteDecision(serverUrl, fallbackRequests);
    if (decision) return decision;
    await sleep(1000, signal);
  }

  return { status: 'timed_out' };
}

async function firstRemoteDecision(serverUrl, requests) {
  for (const request of requests) {
    const current = await getJson(`${serverUrl}/api/requests/${request.id}`);
    if (current.status !== 'pending') return current;
  }

  return null;
}

async function decideFallbackRequests(serverUrl, requests, decision) {
  let firstDecision;

  for (const request of requests) {
    const current = await getJson(`${serverUrl}/api/requests/${request.id}`);
    if (current.status !== 'pending') {
      firstDecision ||= current;
      continue;
    }

    const decided = await postJson(`${serverUrl}/api/requests/${request.id}/decision`, {
      decision,
      actor: 'CLI',
      watchType: 'cli'
    });
    firstDecision ||= decided;
  }

  return firstDecision || { status: decision, decidedBy: 'CLI' };
}

async function waitForRemoteDecision(serverUrl, requestId, deadline, signal) {
  while (Date.now() < deadline && !signal.aborted) {
    const current = await getJson(`${serverUrl}/api/requests/${requestId}`);
    if (current.status !== 'pending') return current;

    await sleep(1000, signal);
  }

  return { status: 'timed_out' };
}

async function waitForCliDecision(decide, signal) {
  const inputClosed = Symbol('inputClosed');
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout
  });

  try {
    while (!signal.aborted) {
      const answer = await rl.question('Approve in CLI? [a]pprove / [d]eny / [enter] wait: ', { signal })
        .catch((error) => {
          if (error.name === 'AbortError') return null;
          if (error.code === 'ERR_USE_AFTER_CLOSE' || error.message === 'readline was closed') {
            return inputClosed;
          }
          throw error;
        });

      if (answer === inputClosed) {
        console.log('CLI input closed; waiting for WristCheck fallback.');
        return new Promise(() => {});
      }

      if (answer === null) {
        await sleep(1000, signal);
        continue;
      }

      const normalized = answer.trim().toLowerCase();
      if (normalized === '') continue;

      if ('approve'.startsWith(normalized) || normalized === 'y' || normalized === 'yes') {
        return decide('approved');
      }

      if ('deny'.startsWith(normalized) || normalized === 'n' || normalized === 'no') {
        return decide('denied');
      }

      console.log('Type "a" to approve, "d" to deny, or press Enter to keep waiting.');
    }
  } finally {
    rl.close();
  }

  return new Promise(() => {});
}

function applyDecisionExit(decision) {
  if (!decision) return;

  if (decision.status === 'approved') {
    console.log(`approved by ${decision.decidedBy || 'WristCheck'} at ${decision.decidedAt || new Date().toISOString()}`);
    return;
  }

  if (decision.status === 'denied' || decision.status === 'expired') {
    console.error(`${decision.status} by ${decision.decidedBy || 'WristCheck'} at ${decision.decidedAt || new Date().toISOString()}`);
    process.exitCode = 2;
    return;
  }

  if (decision.status === 'timed_out') {
    console.error(`approval timed out at ${new Date().toISOString()}`);
    process.exitCode = 2;
  }
}

async function sleep(milliseconds, signal) {
  if (signal.aborted) return;

  await new Promise((resolve) => {
    const timeout = setTimeout(resolve, milliseconds);
    signal.addEventListener('abort', () => {
      clearTimeout(timeout);
      resolve();
    }, { once: true });
  });
}

async function main() {
  const { command, flags } = parseArgs(process.argv.slice(2));

  if (command === 'serve') {
    await runServe(flags);
    return;
  }

  if (command === 'doctor') {
    await runDoctor(flags);
    return;
  }

  if (command === 'request') {
    await runRequest(flags);
    return;
  }

  console.log(usage());
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
