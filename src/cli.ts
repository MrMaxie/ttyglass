#!/usr/bin/env node

import { spawn } from 'node:child_process';

import type { CliAction } from './options.js';
import { formatHelp, parseCliArguments, UsageError } from './options.js';
import { startTtyglass } from './server.js';

const version = '0.0.0';

function openBrowser(url: string): void {
  const command =
    process.platform === 'win32'
      ? { executable: 'rundll32.exe', arguments: ['url.dll,FileProtocolHandler', url] }
      : process.platform === 'darwin'
        ? { executable: 'open', arguments: [url] }
        : { executable: 'xdg-open', arguments: [url] };
  const child = spawn(command.executable, command.arguments, {
    detached: true,
    stdio: 'ignore',
    windowsHide: true,
  });
  child.once('error', (error) => {
    process.stderr.write(`ttyglass: could not open the browser: ${error.message}\n`);
  });
  child.unref();
}

async function main(): Promise<void> {
  let action: CliAction;
  try {
    action = parseCliArguments(process.argv.slice(2));
  } catch (error) {
    if (error instanceof UsageError) {
      process.stderr.write(`ttyglass: ${error.message}\n\n${formatHelp()}`);
      process.exitCode = 2;
      return;
    }
    throw error;
  }

  if (action.kind === 'help') {
    process.stdout.write(formatHelp());
    return;
  }
  if (action.kind === 'version') {
    process.stdout.write(`${version}\n`);
    return;
  }

  const controller = await startTtyglass({
    command: action.options.command,
    commandArguments: action.options.commandArguments,
    cwd: action.options.cwd,
    port: action.options.port,
    diagnosticsLimit: action.options.diagnosticsLimit,
  });
  process.stdout.write(`ttyglass: ${controller.url}\n`);
  process.stdout.write(`command: ${action.options.command}\n`);
  process.stdout.write('Press Ctrl+C to stop.\n');

  if (action.options.open) {
    openBrowser(controller.url);
  }

  let stopping = false;
  const stop = (signal: string): void => {
    if (stopping) {
      return;
    }
    stopping = true;
    void controller.stop(signal).catch((error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      process.stderr.write(`ttyglass: shutdown failed: ${message}\n`);
      process.exitCode = 1;
    });
  };
  process.once('SIGINT', () => stop('SIGINT'));
  process.once('SIGTERM', () => stop('SIGTERM'));
  await controller.closed;
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`ttyglass: ${message}\n`);
  process.exitCode = 1;
});
