import { FitAddon } from '@xterm/addon-fit';
import { Terminal } from '@xterm/xterm';
import '@xterm/xterm/css/xterm.css';
import './styles.css';

function requireElement<T extends Element>(selector: string): T {
  const element = document.querySelector<T>(selector);
  if (element === null) {
    throw new Error(`Missing ${selector} element.`);
  }
  return element;
}

const terminalElement = requireElement<HTMLDivElement>('[data-terminal]');
const statusElement = requireElement<HTMLSpanElement>('[data-status]');
const statusDot = requireElement<HTMLSpanElement>('[data-status-dot]');
const commandElement = requireElement<HTMLElement>('[data-command]');
const pidElement = requireElement<HTMLSpanElement>('[data-pid]');
const restartButton = requireElement<HTMLButtonElement>('[data-restart]');
const diagnosticsButton = requireElement<HTMLButtonElement>('[data-diagnostics-toggle]');
const diagnosticsPanel = requireElement<HTMLElement>('#diagnostics');
const clearButton = requireElement<HTMLButtonElement>('[data-clear]');
const logOutput = requireElement<HTMLDivElement>('[data-log-output]');
const diagnosticsDescription = requireElement<HTMLParagraphElement>('[data-diagnostics-description]');
const shell = requireElement<HTMLElement>('[data-shell]');

const hashParameters = new URLSearchParams(location.hash.slice(1));
const hashToken = hashParameters.get('token');
if (hashToken !== null) {
  sessionStorage.setItem('ttyglass.token', hashToken);
  history.replaceState(null, '', `${location.pathname}${location.search}`);
}
const token = sessionStorage.getItem('ttyglass.token');

const terminal = new Terminal({
  allowProposedApi: false,
  allowTransparency: false,
  convertEol: false,
  cursorBlink: true,
  cursorStyle: 'block',
  fontFamily: '"Cascadia Mono", "SFMono-Regular", Consolas, "Liberation Mono", monospace',
  fontSize: 14,
  lineHeight: 1.18,
  scrollback: 0,
  theme: {
    background: '#0c1114',
    foreground: '#e9f1f2',
    cursor: '#9ed9e2',
    cursorAccent: '#0c1114',
    selectionBackground: '#31505a',
    black: '#151d21',
    red: '#f07778',
    green: '#82cc9c',
    yellow: '#dcc477',
    blue: '#75add0',
    magenta: '#bd9bd3',
    cyan: '#6fc4cf',
    white: '#e9f1f2',
    brightBlack: '#6f7f85',
    brightRed: '#ff9393',
    brightGreen: '#9ce0b3',
    brightYellow: '#edd58d',
    brightBlue: '#91c5e2',
    brightMagenta: '#d3b0e5',
    brightCyan: '#8bdde5',
    brightWhite: '#ffffff',
  },
});
const fitAddon = new FitAddon();
terminal.loadAddon(fitAddon);
terminal.open(terminalElement);

let socket: WebSocket | undefined;
let resizeTimer: number | undefined;

function setStatus(state: string, pid?: number, exitCode?: number): void {
  statusDot.dataset.state = state;
  if (state === 'running') {
    statusElement.textContent = 'Running';
    pidElement.textContent = pid === undefined ? '' : `PID ${pid}`;
    restartButton.disabled = false;
  } else if (state === 'exited') {
    statusElement.textContent = `Exited (${exitCode ?? 'unknown'})`;
    pidElement.textContent = pid === undefined ? '' : `PID ${pid}`;
    restartButton.disabled = false;
  } else if (state === 'failed') {
    statusElement.textContent = 'Failed to start';
    pidElement.textContent = '';
    restartButton.disabled = false;
  } else {
    statusElement.textContent = state;
    pidElement.textContent = '';
    restartButton.disabled = true;
  }
}

function send(message: object): void {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

function fitTerminal(): void {
  fitAddon.fit();
  send({ type: 'resize', cols: terminal.cols, rows: terminal.rows });
}

interface DiagnosticEntry {
  time: string;
  source: string;
  level: string;
  event: string;
  message?: string;
  fields: Record<string, unknown>;
}

function formatDiagnostic(entry: DiagnosticEntry): string {
  const time = new Date(entry.time).toLocaleTimeString('en-GB', { hour12: false });
  const message = entry.message === undefined ? '' : `  ${entry.message}`;
  const fields = Object.entries(entry.fields)
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
    .join(' ');
  return `${time}  ${entry.level.padEnd(5)}  ${entry.source}  ${entry.event}${message}${fields ? `  ${fields}` : ''}`;
}

function appendDiagnostic(entry: DiagnosticEntry): void {
  logOutput.querySelector('[data-empty-diagnostics]')?.remove();
  const row = document.createElement('div');
  row.className = `log-row level-${entry.level}`;
  row.textContent = formatDiagnostic(entry);
  logOutput.append(row);
  while (logOutput.childElementCount > 500) {
    logOutput.firstElementChild?.remove();
  }
  logOutput.scrollTop = logOutput.scrollHeight;
  clearButton.disabled = false;
}

function showEmptyDiagnostics(): void {
  if (logOutput.childElementCount > 0) {
    return;
  }
  const emptyState = document.createElement('p');
  emptyState.dataset.emptyDiagnostics = '';
  emptyState.textContent = 'No application diagnostics received.';
  logOutput.append(emptyState);
  clearButton.disabled = true;
}

function connect(): void {
  if (token === null) {
    setStatus('Missing session token');
    terminal.writeln('\r\nTTYGlass could not authenticate this tab. Open the exact URL printed by the CLI.');
    return;
  }
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  socket = new WebSocket(`${protocol}//${location.host}/terminal?token=${encodeURIComponent(token)}`);

  socket.addEventListener('open', () => {
    setStatus('Connected');
    requestAnimationFrame(() => {
      fitTerminal();
      terminal.focus();
    });
  });
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(String(event.data)) as Record<string, unknown>;
    if (message.type === 'output' && typeof message.data === 'string') {
      terminal.write(message.data);
    } else if (message.type === 'status' && typeof message.state === 'string') {
      setStatus(
        message.state,
        typeof message.pid === 'number' ? message.pid : undefined,
        typeof message.exitCode === 'number' ? message.exitCode : undefined,
      );
    } else if (message.type === 'metadata' && typeof message.command === 'string') {
      commandElement.textContent = message.command;
      diagnosticsDescription.textContent = `Structured events emitted by ${message.command}`;
      document.title = `${message.command} - ttyglass`;
    } else if (message.type === 'log' && typeof message.entry === 'object') {
      appendDiagnostic(message.entry as DiagnosticEntry);
    } else if (message.type === 'logs' && Array.isArray(message.entries)) {
      logOutput.replaceChildren();
      for (const entry of message.entries) {
        appendDiagnostic(entry as DiagnosticEntry);
      }
      showEmptyDiagnostics();
    } else if (message.type === 'logsCleared') {
      logOutput.replaceChildren();
      showEmptyDiagnostics();
    }
  });
  socket.addEventListener('close', (event) => {
    setStatus(event.code === 1013 ? 'Already open elsewhere' : 'Disconnected');
  });
  socket.addEventListener('error', () => setStatus('Connection error'));
}

terminal.onData((data) => send({ type: 'input', data }));
terminal.onBinary((data) => {
  const bytes = Uint8Array.from(data, (character) => character.charCodeAt(0));
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  send({ type: 'binary', data: btoa(binary) });
});

const resizeObserver = new ResizeObserver(() => {
  window.clearTimeout(resizeTimer);
  resizeTimer = window.setTimeout(fitTerminal, 80);
});
resizeObserver.observe(terminalElement);

restartButton.addEventListener('click', () => {
  terminal.reset();
  setStatus('Restarting');
  send({ type: 'restart', cols: terminal.cols, rows: terminal.rows });
  terminal.focus();
});
diagnosticsButton.addEventListener('click', () => {
  const expanded = diagnosticsButton.getAttribute('aria-expanded') !== 'true';
  diagnosticsButton.setAttribute('aria-expanded', String(expanded));
  diagnosticsPanel.hidden = !expanded;
  shell.classList.toggle('diagnostics-open', expanded);
  requestAnimationFrame(() => {
    fitTerminal();
    logOutput.scrollTop = logOutput.scrollHeight;
  });
});
clearButton.addEventListener('click', () => send({ type: 'clearLogs' }));
terminalElement.addEventListener('click', () => terminal.focus());
window.addEventListener('beforeunload', () => socket?.close());

setStatus('Connecting');
showEmptyDiagnostics();
connect();
