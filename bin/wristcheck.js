#!/usr/bin/env node
import os from 'node:os';
import process from 'node:process';
import { detectAiSessions, formatDetectedSessions } from '../src/detect.js';
import { createApprovalServer } from '../src/server.js';

const DEFAULT_URL = 'http://127.0.0.1:8787';

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
  --wait / --no-wait
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
  const preview = flags.preview ? String(flags.preview) : await readStdinIfAvailable();
  const title = String(flags.title || 'Copilot step approval');
  const summary = String(flags.summary || 'Review this AI step before it continues.');
  const wait = flags.wait !== false;

  const request = await postJson(`${serverUrl}/api/requests`, {
    title,
    summary,
    preview,
    source: String(flags.source || 'copilot-cli'),
    timeoutSeconds
  });

  console.log(`approval request ${request.id} created`);

  if (!wait) return;

  const deadline = Date.now() + timeoutSeconds * 1000;
  while (Date.now() < deadline) {
    const current = await getJson(`${serverUrl}/api/requests/${request.id}`);
    if (current.status === 'approved') {
      console.log(`approved by ${current.decidedBy || 'watch'}`);
      return;
    }

    if (current.status === 'denied' || current.status === 'expired') {
      console.error(`${current.status} by ${current.decidedBy || 'watch'}`);
      process.exitCode = 2;
      return;
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  console.error('approval timed out');
  process.exitCode = 2;
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
