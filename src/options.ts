import { resolve } from 'node:path';

export interface RunOptions {
  command: string;
  commandArguments: string[];
  cwd: string;
  port: number;
  diagnosticsLimit: number;
  open: boolean;
}

export type CliAction = { kind: 'help' } | { kind: 'version' } | { kind: 'run'; options: RunOptions };

export class UsageError extends Error {
  override readonly name = 'UsageError';
}

function readValue(arguments_: string[], index: number, option: string): string {
  const value = arguments_[index + 1];
  if (value === undefined || value === '--') {
    throw new UsageError(`${option} requires a value.`);
  }
  return value;
}

function parseInteger(value: string, option: string, minimum: number, maximum: number): number {
  if (!/^\d+$/.test(value)) {
    throw new UsageError(`${option} must be an integer from ${minimum} to ${maximum}.`);
  }
  const parsed = Number.parseInt(value, 10);
  if (parsed < minimum || parsed > maximum) {
    throw new UsageError(`${option} must be an integer from ${minimum} to ${maximum}.`);
  }
  return parsed;
}

export function parseCliArguments(arguments_: string[], initialCwd = process.cwd()): CliAction {
  if (arguments_.length === 1 && (arguments_[0] === '--help' || arguments_[0] === '-h')) {
    return { kind: 'help' };
  }
  if (arguments_.length === 1 && arguments_[0] === '--version') {
    return { kind: 'version' };
  }

  const separator = arguments_.indexOf('--');
  if (separator < 0) {
    throw new UsageError('Separate ttyglass options from the TUI command with --.');
  }

  let cwd = initialCwd;
  let port = 0;
  let diagnosticsLimit = 500;
  let open = false;
  for (let index = 0; index < separator; index += 1) {
    const argument = arguments_[index];
    if (argument === '--cwd') {
      cwd = resolve(initialCwd, readValue(arguments_, index, '--cwd'));
      index += 1;
    } else if (argument === '--port') {
      port = parseInteger(readValue(arguments_, index, '--port'), '--port', 0, 65_535);
      index += 1;
    } else if (argument === '--diagnostics-limit') {
      diagnosticsLimit = parseInteger(
        readValue(arguments_, index, '--diagnostics-limit'),
        '--diagnostics-limit',
        1,
        5_000,
      );
      index += 1;
    } else if (argument === '--open') {
      open = true;
    } else if (argument === '--no-open') {
      open = false;
    } else {
      throw new UsageError(`Unknown ttyglass option: ${argument ?? ''}`);
    }
  }

  const command = arguments_[separator + 1];
  if (command === undefined || command.length === 0) {
    throw new UsageError('Provide a TUI command after --.');
  }

  return {
    kind: 'run',
    options: {
      command,
      commandArguments: arguments_.slice(separator + 2),
      cwd,
      port,
      diagnosticsLimit,
      open,
    },
  };
}

export function formatHelp(): string {
  return `ttyglass - observe a real TUI in a local browser

Usage:
  ttyglass [options] -- <command> [arguments...]

Options:
  --cwd <path>                Run the command from this directory
  --port <number>             Use a fixed loopback port (default: available port)
  --diagnostics-limit <count> Keep 1-5000 diagnostic entries (default: 500)
  --open                      Open the browser after startup
  --no-open                   Do not open the browser (default)
  -h, --help                  Show this help
  --version                   Show the package version

Examples:
  ttyglass -- lazygit
  ttyglass --cwd ../app -- npm run tui
  npx ttyglass -- cargo run
  nubx ttyglass -- python -m textual_demo
`;
}
