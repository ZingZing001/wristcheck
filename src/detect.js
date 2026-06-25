import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

const TOOLS = [
  {
    id: 'github-copilot-cli',
    name: 'GitHub Copilot CLI',
    matches(processInfo) {
      return /(^|\/|\\)copilot(\s|$)/i.test(processInfo.commandLine)
        || /@github\/copilot/i.test(processInfo.commandLine);
    }
  },
  {
    id: 'claude-code',
    name: 'Claude Code',
    matches(processInfo) {
      if (/Claude Helper|chrome_crashpad_handler/i.test(processInfo.commandLine)) return false;
      return /(^|\/|\\)claude(\s|$)/i.test(processInfo.commandLine)
        || /claude-code/i.test(processInfo.commandLine)
        || /\/Applications\/Claude\.app\/Contents\/MacOS\/Claude$/i.test(processInfo.commandLine);
    }
  }
];

export async function detectAiSessions() {
  const { stdout } = await execFileAsync('ps', ['-axo', 'pid=,comm=,args='], {
    maxBuffer: 1024 * 1024
  });

  return stdout
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map(parseProcessLine)
    .filter((processInfo) => processInfo && !isSelfDetection(processInfo))
    .map((processInfo) => ({
      ...processInfo,
      tools: TOOLS.filter((tool) => tool.matches(processInfo))
    }))
    .filter((processInfo) => processInfo.tools.length > 0);
}

export function formatDetectedSessions(sessions) {
  if (sessions.length === 0) {
    return 'No running Copilot or Claude sessions detected.';
  }

  return sessions
    .map((session) => {
      const tools = session.tools.map((tool) => tool.name).join(', ');
      return `${session.pid} ${tools}: ${session.commandLine}`;
    })
    .join('\n');
}

function parseProcessLine(line) {
  const match = line.match(/^(\d+)\s+(\S+)\s+(.+)$/);
  if (!match) return null;

  return {
    pid: Number(match[1]),
    executable: match[2],
    commandLine: match[3]
  };
}

function isSelfDetection(processInfo) {
  return processInfo.commandLine.includes('wristcheck doctor')
    || processInfo.commandLine.includes('src/detect.js')
    || processInfo.commandLine.includes('/wristcheck/')
    || processInfo.commandLine.includes('wristcheck.js');
}
