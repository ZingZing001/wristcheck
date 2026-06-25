#!/usr/bin/env node
import net from 'node:net';
import { access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import process from 'node:process';

const root = process.cwd();
const checks = [];

function addCheck(name, ok, detail, severity = 'error') {
  checks.push({ name, ok, detail, severity });
}

async function exists(path) {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function commandExists(command) {
  const result = spawnSync('sh', ['-c', `command -v ${command}`], { stdio: 'ignore' });
  return result.status === 0;
}

function commandSucceeds(command, args) {
  const result = spawnSync(command, args, { stdio: 'ignore' });
  return result.status === 0;
}

function portAvailable(port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once('error', () => resolve(false));
    server.once('listening', () => {
      server.close(() => resolve(true));
    });
    server.listen(port, '127.0.0.1');
  });
}

async function healthResponds(port) {
  try {
    const response = await fetch(`http://127.0.0.1:${port}/health`);
    const body = await response.json();
    return response.ok && body.ok === true;
  } catch {
    return false;
  }
}

const nodeMajor = Number(process.versions.node.split('.')[0]);
const portReady = await portAvailable(8787) || await healthResponds(8787);
const xcodebuildReady = commandExists('xcodebuild') && commandSucceeds('xcodebuild', ['-version']);
addCheck('Node.js >= 20', nodeMajor >= 20, process.version);
addCheck('npm available', commandExists('npm'), commandExists('npm') ? 'found' : 'missing');
addCheck('Xcode open available', commandExists('open'), commandExists('open') ? 'found' : 'missing');
addCheck('full Xcode available', xcodebuildReady, xcodebuildReady ? 'xcodebuild ready' : 'install/select full Xcode to run on Apple Watch', 'warning');
addCheck('WristCheck.xcodeproj exists', await exists(join(root, 'WristCheck.xcodeproj', 'project.pbxproj')), 'open WristCheck.xcodeproj');
addCheck('watchOS source exists', await exists(join(root, 'watchos', 'WristCheckWatchApp', 'WristCheckApp.swift')), 'watchos/WristCheckWatchApp/WristCheckApp.swift');
addCheck('port 8787 ready', portReady, 'free or already running WristCheck');

let failed = false;
let warned = false;
for (const check of checks) {
  const mark = check.ok ? '✓' : check.severity === 'warning' ? '!' : '✗';
  console.log(`${mark} ${check.name} (${check.detail})`);
  failed ||= !check.ok && check.severity === 'error';
  warned ||= !check.ok && check.severity === 'warning';
}

if (failed) {
  console.error('');
  console.error('Doctor found issues to fix before running WristCheck.');
  process.exitCode = 1;
} else {
  console.log('');
  console.log(warned ? 'Doctor completed with warnings. Server setup is ready.' : 'Doctor passed. You can run:');
  console.log('  npm start -- --host 0.0.0.0 --port 8787');
  console.log('  open WristCheck.xcodeproj');
}
