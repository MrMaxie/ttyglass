import { sendTtyglassDiagnostic } from 'ttyglass';

const language = 'TypeScript';
const source = 'stress-typescript';
const levels = ['trace', 'debug', 'info', 'warn', 'error'] as const;
const phases = ['full redraw', 'rapid counters', 'palette sweep', 'wide glyphs'] as const;

function durationFromArguments(): number | undefined {
  const index = process.argv.indexOf('--duration-ms');
  if (index < 0) return undefined;
  const value = Number(process.argv[index + 1]);
  return Number.isFinite(value) && value > 0 ? value : undefined;
}

function clip(value: string, width: number): string {
  return Array.from(value).slice(0, Math.max(0, width)).join('');
}

function bar(value: number, width: number): string {
  const safeWidth = Math.max(4, width);
  const filled = Math.round((safeWidth * value) / 100);
  return `${'#'.repeat(filled)}${'.'.repeat(safeWidth - filled)}`;
}

function paletteLine(frame: number, width: number): string {
  const cells = Math.max(1, Math.min(16, Math.floor((width - 10) / 3)));
  const colors = Array.from({ length: cells }, (_, index) => {
    const color = (index + Math.floor(frame / 3)) % 16;
    return `\x1b[48;5;${color}m  \x1b[0m`;
  }).join(' ');
  return `ANSI-16  ${colors}`;
}

function gradientLine(frame: number, width: number): string {
  const cells = Math.max(1, Math.min(32, Math.floor((width - 10) / 2)));
  const colors = Array.from({ length: cells }, (_, index) => {
    const hue = (index * 11 + frame * 4) % 256;
    return `\x1b[48;2;${hue};${255 - hue};${(hue * 3) % 256}m  \x1b[0m`;
  }).join('');
  return `RGB      ${colors}`;
}

function render(frame: number, startedAt: number, paused: boolean, diagnosticsSent: number): void {
  const columns = process.stdout.columns ?? 100;
  const rows = process.stdout.rows ?? 30;
  const phase = phases[Math.floor(frame / 25) % phases.length] ?? phases[0];
  const uptime = ((Date.now() - startedAt) / 1_000).toFixed(1);
  const lines: string[] = [
    `\x1b[1;36mTTYGLASS STRESS TUI\x1b[0m | ${language} | frame ${frame} | ${uptime}s`,
    clip('-'.repeat(columns), columns),
    `viewport ${columns}x${rows} | phase: ${phase} | diagnostics: ${diagnosticsSent} | ${paused ? 'PAUSED' : 'RUNNING'}`,
    paletteLine(frame, columns),
    gradientLine(frame, columns),
    clip('Wide glyphs: zażółć gęślą jaźń | 日本語 | λ | box: +---+ | combining: e\u0301', columns),
    '',
  ];

  const footerRows = 2;
  const tableRows = Math.max(0, rows - lines.length - footerRows);
  for (let index = 0; index < tableRows; index += 1) {
    const progress = (frame * 3 + index * 13) % 101;
    const latency = (frame * 17 + index * 29) % 997;
    const state = index % 7 === 0 ? '\x1b[33mBUSY\x1b[0m' : '\x1b[32mOK  \x1b[0m';
    lines.push(
      clip(`${String(index + 1).padStart(3, '0')} worker-${String(index % 12).padStart(2, '0')} `, 18) +
        `${state} [${bar(progress, Math.min(28, Math.max(4, columns - 47)))}] ${String(latency).padStart(3)} ms`,
    );
  }

  lines.push(clip('-'.repeat(columns), columns));
  lines.push(clip('q quit | space pause | b diagnostic burst | d diagnostic | r redraw', columns));

  const screen = lines
    .slice(0, rows)
    .map((line, index, visibleLines) => `\x1b[2K${line}${index === visibleLines.length - 1 ? '' : '\r\n'}`)
    .join('');
  process.stdout.write(`\x1b[H${screen}`);
}

let frame = 0;
let paused = false;
let diagnosticsSent = 0;
let stopped = false;
let previousSize = '';
const startedAt = Date.now();
const duration = durationFromArguments();

function diagnostic(
  event: string,
  level: (typeof levels)[number] = levels[diagnosticsSent % levels.length] ?? 'info',
  extra = {},
): void {
  diagnosticsSent += 1;
  void sendTtyglassDiagnostic({
    source,
    level,
    event,
    message: `${language} emitted ${event}`,
    fields: {
      frame,
      columns: process.stdout.columns ?? 100,
      rows: process.stdout.rows ?? 30,
      ...extra,
    },
  });
}

function stop(): void {
  if (stopped) return;
  stopped = true;
  clearInterval(renderTimer);
  clearInterval(diagnosticTimer);
  diagnostic('fixture.stopped', 'info');
  process.stdin.setRawMode?.(false);
  process.stdout.write('\x1b[?25h\x1b[?1049l');
  process.exit(0);
}

process.stdin.setRawMode?.(true);
process.stdin.setEncoding('utf8');
process.stdin.resume();
process.stdin.on('data', (data: string) => {
  for (const key of data) {
    if (key === 'q' || key === '\x03') stop();
    else if (key === ' ') paused = !paused;
    else if (key === 'b') {
      for (let index = 0; index < 12; index += 1) diagnostic('burst.item', levels[index % levels.length], { index });
    } else if (key === 'd') diagnostic('input.manual', 'info');
    else if (key === 'r') render(frame, startedAt, paused, diagnosticsSent);
  }
});

process.on('SIGINT', stop);
process.on('SIGTERM', stop);
process.stdout.write('\x1b[?1049h\x1b[2J\x1b[H\x1b[?25l');
diagnostic('fixture.ready', 'info', { standardLibraryUi: true, ttyglassLibraryDiagnostics: true });

const renderTimer = setInterval(() => {
  if (!paused) frame += 1;
  const size = `${process.stdout.columns ?? 100}x${process.stdout.rows ?? 30}`;
  if (size !== previousSize) {
    previousSize = size;
    process.stdout.write('\x1b[2J');
    diagnostic('viewport.changed', 'debug', { size });
  }
  render(frame, startedAt, paused, diagnosticsSent);
  if (duration !== undefined && Date.now() - startedAt >= duration) stop();
}, 100);

const diagnosticTimer = setInterval(() => {
  diagnostic('fixture.heartbeat', undefined, {
    phase: phases[Math.floor(frame / 25) % phases.length] ?? phases[0],
  });
}, 500);
