<script lang="ts">
  import { onMount } from 'svelte';

  import DiagnosticsPanel from './DiagnosticsPanel.svelte';
  import DisplayPanel from './DisplayPanel.svelte';
  import { type ColorSchemeId, colorSchemes, findColorScheme } from './lib/color-schemes';
  import type { DiagnosticEntry } from './lib/diagnostics';
  import type {
    TerminalController,
    TerminalMessage,
    TerminalSize,
    TerminalSizingMode,
  } from './lib/terminal';
  import TerminalPane from './TerminalPane.svelte';

  interface ProcessStatus {
    state: string;
    label: string;
    pid: number | undefined;
    restartable: boolean;
  }

  type ClientMessage =
    | TerminalMessage
    | { type: 'restart'; cols: number; rows: number }
    | { type: 'clearLogs' };

  function readSessionToken(): string | null {
    const hashParameters = new URLSearchParams(location.hash.slice(1));
    const hashToken = hashParameters.get('token');
    if (hashToken !== null) {
      sessionStorage.setItem('ttyglass.token', hashToken);
      history.replaceState(null, '', `${location.pathname}${location.search}`);
    }
    return sessionStorage.getItem('ttyglass.token');
  }

  const token = readSessionToken();
  let command = $state('Terminal session');
  let diagnosticsOpen = $state(false);
  let displayOpen = $state(false);
  let diagnostics = $state<DiagnosticEntry[]>([]);
  let colorSchemeId = $state<ColorSchemeId>('default');
  let sizingMode = $state<TerminalSizingMode>('dynamic');
  let terminalSize = $state<TerminalSize>({ cols: 100, rows: 30 });
  let processStatus = $state<ProcessStatus>({
    state: 'connecting',
    label: 'Connecting',
    pid: undefined,
    restartable: false,
  });
  let socket: WebSocket | undefined;
  let terminal = $state<TerminalController | undefined>();

  function setStatus(state: string, pid?: number, exitCode?: number): void {
    if (state === 'running') {
      processStatus = { state, label: 'Running', pid, restartable: true };
    } else if (state === 'exited') {
      processStatus = { state, label: `Exited (${exitCode ?? 'unknown'})`, pid, restartable: true };
    } else if (state === 'failed') {
      processStatus = { state, label: 'Failed to start', pid: undefined, restartable: true };
    } else {
      processStatus = {
        state: state.toLowerCase().replaceAll(' ', '-'),
        label: state,
        pid: undefined,
        restartable: false,
      };
    }
  }

  function send(message: ClientMessage): boolean {
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(message));
      return true;
    }
    return false;
  }

  function handleServerMessage(event: MessageEvent): void {
    let message: Record<string, unknown>;
    try {
      const parsed = JSON.parse(String(event.data)) as unknown;
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
        return;
      }
      message = parsed as Record<string, unknown>;
    } catch {
      return;
    }

    if (message.type === 'output' && typeof message.data === 'string') {
      terminal?.write(message.data);
    } else if (message.type === 'status' && typeof message.state === 'string') {
      setStatus(
        message.state,
        typeof message.pid === 'number' ? message.pid : undefined,
        typeof message.exitCode === 'number' ? message.exitCode : undefined,
      );
    } else if (message.type === 'metadata' && typeof message.command === 'string') {
      command = message.command;
      document.title = `${message.command} - ttyglass`;
    } else if (message.type === 'log' && typeof message.entry === 'object' && message.entry !== null) {
      diagnostics = [...diagnostics, message.entry as DiagnosticEntry].slice(-500);
    } else if (message.type === 'logs' && Array.isArray(message.entries)) {
      diagnostics = (message.entries as DiagnosticEntry[]).slice(-500);
    } else if (message.type === 'logsCleared') {
      diagnostics = [];
    }
  }

  function connect(): void {
    if (token === null) {
      setStatus('Missing session token');
      return;
    }
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    socket = new WebSocket(`${protocol}//${location.host}/terminal?token=${encodeURIComponent(token)}`);
    socket.addEventListener('open', () => {
      setStatus('Connected');
      requestAnimationFrame(() => {
        terminal?.fit();
        terminal?.focus();
      });
    });
    socket.addEventListener('message', handleServerMessage);
    socket.addEventListener('close', (event) => {
      setStatus(event.code === 1013 ? 'Already open elsewhere' : 'Disconnected');
    });
    socket.addEventListener('error', () => setStatus('Connection error'));
  }

  function handleTerminalReady(controller: TerminalController | undefined): void {
    terminal = controller;
    if (controller !== undefined && token === null) {
      controller.writeln('\r\nTTYGlass could not authenticate this tab. Open the exact URL printed by the CLI.');
    }
  }

  function handleSchemeChange(nextSchemeId: ColorSchemeId): void {
    colorSchemeId = nextSchemeId;
    terminal?.setColorScheme(findColorScheme(nextSchemeId));
  }

  function useDynamicSize(): void {
    sizingMode = 'dynamic';
    terminal?.setDynamicSize();
  }

  function useFixedSize(size: TerminalSize): void {
    sizingMode = 'fixed';
    terminal?.setFixedSize(size);
  }

  function restart(): void {
    if (terminal === undefined) {
      return;
    }
    terminal.reset();
    setStatus('Restarting');
    send({ type: 'restart', ...terminal.size() });
    terminal.focus();
  }

  function toggleDiagnostics(): void {
    diagnosticsOpen = !diagnosticsOpen;
    if (diagnosticsOpen) {
      displayOpen = false;
    }
  }

  function toggleDisplay(): void {
    displayOpen = !displayOpen;
    if (displayOpen) {
      diagnosticsOpen = false;
    }
  }

  function closePanels(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      diagnosticsOpen = false;
      displayOpen = false;
    }
  }

  onMount(() => {
    const closeSocket = (): void => socket?.close();
    window.addEventListener('beforeunload', closeSocket);
    connect();

    return () => {
      window.removeEventListener('beforeunload', closeSocket);
      socket?.close();
    };
  });
</script>

<svelte:window onkeydown={closePanels} />

<main class="shell" class:diagnostics-open={diagnosticsOpen}>
  <header class="toolbar">
    <div class="identity">
      <img src="/ttyglass-logo.svg" alt="" width="24" height="24" />
      <div>
        <span class="product">ttyglass</span>
        <strong>{command}</strong>
      </div>
    </div>
    <div class="process-state" aria-live="polite">
      <span class="status-dot" data-state={processStatus.state}></span>
      <span>{processStatus.label}</span>
      {#if processStatus.pid !== undefined}
        <span class="pid">PID {processStatus.pid}</span>
      {/if}
    </div>
    <button
      type="button"
      class="secondary"
      disabled={!processStatus.restartable || terminal === undefined}
      onclick={restart}>Restart</button
    >
    <button
      type="button"
      class="secondary"
      aria-expanded={displayOpen}
      aria-controls="display-panel"
      onclick={toggleDisplay}>Display</button
    >
    <button
      type="button"
      class="secondary"
      aria-expanded={diagnosticsOpen}
      aria-controls="diagnostics"
      onclick={toggleDiagnostics}>Diagnostics</button
    >
  </header>
  <section
    class="terminal-panel"
    class:fixed-terminal={sizingMode === 'fixed'}
    aria-label="Observed terminal"
  >
    <TerminalPane
      onReady={handleTerminalReady}
      onSize={(size) => (terminalSize = size)}
      scheme={findColorScheme(colorSchemeId)}
      {send}
    />
  </section>
  {#if displayOpen}
    <DisplayPanel
      schemes={colorSchemes}
      schemeId={colorSchemeId}
      {sizingMode}
      {terminalSize}
      onSchemeChange={handleSchemeChange}
      onDynamicSize={useDynamicSize}
      onFixedSize={useFixedSize}
    />
  {/if}
  {#if diagnosticsOpen}
    <DiagnosticsPanel entries={diagnostics} onClear={() => send({ type: 'clearLogs' })} />
  {/if}
</main>
