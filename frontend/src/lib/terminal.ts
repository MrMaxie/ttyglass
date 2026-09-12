import { FitAddon } from '@xterm/addon-fit';
import { SerializeAddon } from '@xterm/addon-serialize';
import { type ITheme, Terminal } from '@xterm/xterm';
import '@xterm/xterm/css/xterm.css';

import { AnsiPaletteMapper } from './ansi-palette';
import { type ColorScheme, findColorScheme } from './color-schemes';

export type TerminalMessage =
  | { type: 'input'; data: string }
  | { type: 'binary'; data: string }
  | { type: 'resize'; cols: number; rows: number };

export interface TerminalSize {
  cols: number;
  rows: number;
}

export type TerminalSizingMode = 'dynamic' | 'fixed';

export interface TerminalController {
  dispose(): void;
  fit(): void;
  focus(): void;
  reset(): void;
  setColorScheme(scheme: ColorScheme): void;
  setDynamicSize(): void;
  setFixedSize(size: TerminalSize): void;
  size(): TerminalSize;
  write(data: string): void;
  writeln(data: string): void;
}

interface TerminalOptions {
  onSize: (size: TerminalSize) => void;
  scheme: ColorScheme;
  send: (message: TerminalMessage) => boolean;
}

export function createTerminal(element: HTMLElement, options: TerminalOptions): TerminalController {
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
    theme: options.scheme.terminal,
  });
  const sourceTheme: ITheme = findColorScheme('default').terminal;
  const sourceTerminal = new Terminal({
    allowProposedApi: false,
    allowTransparency: false,
    convertEol: false,
    scrollback: 0,
    theme: sourceTheme,
  });
  const serializeAddon = new SerializeAddon();
  const paletteMapper = new AnsiPaletteMapper(sourceTheme, options.scheme);
  const fitAddon = new FitAddon();
  let resizeTimer: number | undefined;
  let sizingMode: TerminalSizingMode = 'dynamic';
  let lastReportedSize: TerminalSize | undefined;
  let paletteRevision = 0;
  let repaintingPalette = false;
  let pendingOutput: string[] = [];

  sourceTerminal.loadAddon(serializeAddon);
  terminal.loadAddon(fitAddon);
  terminal.open(element);
  sourceTerminal.resize(terminal.cols, terminal.rows);

  const reportSize = (): void => {
    const size = { cols: terminal.cols, rows: terminal.rows };
    sourceTerminal.resize(size.cols, size.rows);
    options.onSize(size);
    if (lastReportedSize?.cols === size.cols && lastReportedSize.rows === size.rows) {
      return;
    }
    if (options.send({ type: 'resize', ...size })) {
      lastReportedSize = size;
    }
  };
  const fit = (): void => {
    if (sizingMode !== 'dynamic') {
      return;
    }
    fitAddon.fit();
    reportSize();
  };
  const dataSubscription = terminal.onData((data) => options.send({ type: 'input', data }));
  const binarySubscription = terminal.onBinary((data) => {
    const bytes = Uint8Array.from(data, (character) => character.charCodeAt(0));
    let binary = '';
    for (const byte of bytes) {
      binary += String.fromCharCode(byte);
    }
    options.send({ type: 'binary', data: btoa(binary) });
  });
  const resizeObserver = new ResizeObserver(() => {
    if (sizingMode !== 'dynamic') {
      return;
    }
    window.clearTimeout(resizeTimer);
    resizeTimer = window.setTimeout(fit, 80);
  });
  const focus = (): void => terminal.focus();

  resizeObserver.observe(element);
  element.addEventListener('click', focus);

  return {
    dispose(): void {
      window.clearTimeout(resizeTimer);
      resizeObserver.disconnect();
      element.removeEventListener('click', focus);
      dataSubscription.dispose();
      binarySubscription.dispose();
      sourceTerminal.dispose();
      terminal.dispose();
    },
    fit,
    focus,
    reset(): void {
      paletteRevision += 1;
      repaintingPalette = false;
      pendingOutput = [];
      paletteMapper.reset();
      sourceTerminal.reset();
      terminal.reset();
    },
    setColorScheme(scheme): void {
      const revision = ++paletteRevision;
      repaintingPalette = true;
      paletteMapper.setScheme(scheme);
      terminal.options.theme = scheme.terminal;
      sourceTerminal.write('', () => {
        if (revision !== paletteRevision) {
          return;
        }
        const snapshot = serializeAddon.serialize({ scrollback: 0 });
        paletteMapper.reset();
        terminal.reset();
        terminal.write(paletteMapper.transform(snapshot), () => {
          if (revision !== paletteRevision) {
            return;
          }
          const queuedOutput = pendingOutput;
          pendingOutput = [];
          for (const data of queuedOutput) {
            terminal.write(paletteMapper.transform(data));
          }
          repaintingPalette = false;
        });
      });
    },
    setDynamicSize(): void {
      sizingMode = 'dynamic';
      fit();
    },
    setFixedSize(size): void {
      sizingMode = 'fixed';
      window.clearTimeout(resizeTimer);
      terminal.resize(size.cols, size.rows);
      reportSize();
    },
    size: () => ({ cols: terminal.cols, rows: terminal.rows }),
    write(data): void {
      sourceTerminal.write(data);
      if (repaintingPalette) {
        pendingOutput.push(data);
        return;
      }
      terminal.write(paletteMapper.transform(data));
    },
    writeln(data): void {
      const line = `${data}\r\n`;
      sourceTerminal.write(line);
      if (repaintingPalette) {
        pendingOutput.push(line);
        return;
      }
      terminal.write(paletteMapper.transform(line));
    },
  };
}
