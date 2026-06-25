#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import process from 'node:process';

const label = 'com.wristcheck.server';
const home = process.env.HOME;
const root = process.cwd();
const nodePath = process.execPath;
const plistPath = join(home, 'Library', 'LaunchAgents', `${label}.plist`);
const logDir = join(home, 'Library', 'Logs', 'WristCheck');
const uid = process.getuid?.();

if (!home || uid === undefined) {
  throw new Error('Cannot determine HOME or user id for LaunchAgent install.');
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: options.stdio || 'pipe',
    encoding: 'utf8'
  });

  if (options.allowFailure) return result;
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed: ${result.stderr || result.stdout}`);
  }

  return result;
}

function xmlEscape(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

await mkdir(dirname(plistPath), { recursive: true });
await mkdir(logDir, { recursive: true });

const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${xmlEscape(nodePath)}</string>
    <string>${xmlEscape(join(root, 'bin', 'wristcheck.js'))}</string>
    <string>serve</string>
    <string>--host</string>
    <string>0.0.0.0</string>
    <string>--port</string>
    <string>8787</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${xmlEscape(root)}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${xmlEscape(join(logDir, 'server.out.log'))}</string>
  <key>StandardErrorPath</key>
  <string>${xmlEscape(join(logDir, 'server.err.log'))}</string>
</dict>
</plist>
`;

await writeFile(plistPath, plist, 'utf8');

run('launchctl', ['bootout', `gui/${uid}`, plistPath], { allowFailure: true });
run('launchctl', ['bootstrap', `gui/${uid}`, plistPath]);
run('launchctl', ['kickstart', '-k', `gui/${uid}/${label}`], { allowFailure: true });

console.log(`Installed WristCheck autostart: ${plistPath}`);
console.log('Logs:');
console.log(`  ${join(logDir, 'server.out.log')}`);
console.log(`  ${join(logDir, 'server.err.log')}`);
