#!/usr/bin/env node
import { access, chmod } from 'node:fs/promises';
import { constants } from 'node:fs';
import { execFile } from 'node:child_process';
import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const projectRoot = new URL('..', import.meta.url);
const executableFiles = [
  'bin/wristcheck.js',
  'examples/copilot-step.sh'
];

async function main() {
  console.log('Setting up WristCheck...');
  await ensureCommand('node', ['--version']);
  await run('npm', ['install']);
  await makeScriptsExecutable();

  const xcodeProject = new URL('WristCheck.xcodeproj', projectRoot);
  await access(xcodeProject, constants.R_OK);

  const hasXcode = await commandSucceeds('xcodebuild', ['-version']);
  if (hasXcode) {
    await run('xcodebuild', ['-list', '-project', fileURLToPath(xcodeProject)]);
  } else {
    console.log('Xcode command-line tools were not found. Install Xcode before building the Watch app.');
  }

  console.log('\nSetup complete.');
  console.log('Next steps:');
  console.log('  npm run doctor');
  console.log('  npm start -- --host 0.0.0.0 --port 8787');
  console.log('  open WristCheck.xcodeproj');
}

async function ensureCommand(command, args) {
  if (!(await commandSucceeds(command, args))) {
    throw new Error(`${command} is required but was not found.`);
  }
}

async function commandSucceeds(command, args) {
  try {
    await execFileAsync(command, args);
    return true;
  } catch {
    return false;
  }
}

async function makeScriptsExecutable() {
  for (const file of executableFiles) {
    const path = join(fileURLToPath(projectRoot), file);
    try {
      await access(path, constants.F_OK);
      await chmod(path, 0o755);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
}

async function run(command, args) {
  console.log(`> ${command} ${args.join(' ')}`);
  const subprocess = spawn(command, args, {
    cwd: fileURLToPath(projectRoot),
    stdio: 'inherit'
  });

  await new Promise((resolve, reject) => {
    subprocess.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited with ${code}`));
    });
    subprocess.on('error', reject);
  });
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
