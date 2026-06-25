#!/usr/bin/env node
import { rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import process from 'node:process';

const label = 'com.wristcheck.server';
const plistPath = join(process.env.HOME, 'Library', 'LaunchAgents', `${label}.plist`);
const uid = process.getuid?.();

if (uid === undefined) {
  throw new Error('Cannot determine user id for LaunchAgent uninstall.');
}

spawnSync('launchctl', ['bootout', `gui/${uid}`, plistPath], { stdio: 'ignore' });
await rm(plistPath, { force: true });

console.log('Removed WristCheck autostart.');
