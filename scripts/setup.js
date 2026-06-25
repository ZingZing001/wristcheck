#!/usr/bin/env node
import { chmod, access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const root = process.cwd();
const executableFiles = [
  'bin/wristcheck.js',
  'examples/copilot-step.sh'
];

async function exists(path) {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

for (const file of executableFiles) {
  const path = join(root, file);
  if (await exists(path)) {
    await chmod(path, 0o755);
  }
}

console.log('WristCheck setup complete.');
console.log('');
console.log('Next steps:');
console.log('  npm run doctor');
console.log('  npm start -- --host 0.0.0.0 --port 8787');
console.log('  open WristCheck.xcodeproj');
